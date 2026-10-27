import Foundation

// Шины общих эффектов и Sidechain (как схема engine.ts веба): посылы дорожек Reverb, Delay, Drive (после громкости
// и mute/solo дорожки) → эффект → выход (Drive — с усилением 0,5). Огибающая Sidechain одна на проект: громкость
// дорожки = 1 − amount·e (amount — ручка 3.4, у источника 0), посылы приглушаются так же, если включён переключатель
// SETTINGS → SIDECHAIN. Значения FX — из снимка звука с p-lock играющих шагов (любой дорожки) — на блок.
// Всё в колбэке: буферы выделены при создании.

public final class FxRack {
    /// Выходное усиление шины Drive (как у прежнего Overdrive).
    static let driveOut: Float = 0.5
    /// Наибольшее время Delay, с: 1 такт при наименьшем темпе.
    static let maxDelay: Double = 4 * 60 / Params.bpmMin
    /// Время без синхронизации — копия Params.dlyFreeMin, dlyFreeMax / dlyFreeMin, dlyFreeTop.
    static let freeMin: Double = Params.dlyFreeMin
    static let freeRatio: Double = Params.dlyFreeMax / Params.dlyFreeMin
    static let freeTop: Double = Params.dlyFreeTop

    let sr: Double
    public let reverb: FxReverb
    public let delay: FxDelay
    public let drive: FxDrive
    public let duck: FxDuck
    /// Входы шин (L, R × 3: Reverb, Delay, Drive), огибающая e на блок, выход эффекта.
    let inL: UnsafeMutablePointer<Float>
    let inR: UnsafeMutablePointer<Float>
    let e: UnsafeMutablePointer<Float>
    let outL: UnsafeMutablePointer<Float>
    let outR: UnsafeMutablePointer<Float>
    /// Значения FX на этот блок (Params.fxIds, с p-lock).
    public let live: UnsafeMutablePointer<Double>
    /// Глубина Sidechain дорожек и переключатели посылов — сглаженные (~10 мс).
    let amount: UnsafeMutablePointer<Float>
    let sendFlag: UnsafeMutablePointer<Float>
    var source = 0
    var anyDucked = false
    /// Покой Reverb и Delay (S14b): вход молчит и выход тише −120 dBFS дольше самого длинного внутреннего пути
    /// (Reverb — предзадержка до 240 мс и линии; Delay — наибольшее время и 0,5 с) — эффект не считается, состояние
    /// с нуля; первый ненулевой вход будит его. Звук не меняется: всё, что внутри, уже ниже −120 dB.
    static let idleLevel: Float = 1e-6
    static let revIdleSec: Double = 1
    static let dlyIdleSec: Double = FxRack.maxDelay + 0.5
    private var revQuiet = 0
    private var dlyQuiet = 0
    private(set) var revIdle = false
    private(set) var dlyIdle = false
    let maxFrames: Int
    /// Время Delay по пунктам (четверти) — копия Params.delayDivs (колбэк не читает Swift-массивы).
    let delayBeats: UnsafeMutablePointer<Double>
    let delayDivs: Int

    public init(sampleRate: Double, maxFrames: Int = 4096) {
        sr = sampleRate
        self.maxFrames = maxFrames
        let divs = Params.delayDivs
        let beats = UnsafeMutablePointer<Double>.allocate(capacity: divs.count)
        for (k, d) in divs.enumerated() { (beats + k).initialize(to: d.beats) }
        delayDivs = divs.count
        delayBeats = beats
        reverb = FxReverb(sampleRate: sampleRate, seed: FxRandom.seed())
        delay = FxDelay(sampleRate: sampleRate, maxTime: FxRack.maxDelay, seed: FxRandom.seed())
        drive = FxDrive(sampleRate: sampleRate)
        duck = FxDuck(sampleRate: sampleRate)
        inL = UnsafeMutablePointer<Float>.allocate(capacity: 3 * maxFrames)
        inR = UnsafeMutablePointer<Float>.allocate(capacity: 3 * maxFrames)
        e = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
        outL = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
        outR = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
        inL.initialize(repeating: 0, count: 3 * maxFrames)
        inR.initialize(repeating: 0, count: 3 * maxFrames)
        e.initialize(repeating: 0, count: maxFrames)
        outL.initialize(repeating: 0, count: maxFrames)
        outR.initialize(repeating: 0, count: maxFrames)
        live = UnsafeMutablePointer<Double>.allocate(capacity: Params.fxCount)
        for (k, id) in Params.fxIds.enumerated() { (live + k).initialize(to: Params.byId[id]?.def ?? 0) }
        amount = UnsafeMutablePointer<Float>.allocate(capacity: SoundData.maxTracks)
        amount.initialize(repeating: 0, count: SoundData.maxTracks)
        sendFlag = UnsafeMutablePointer<Float>.allocate(capacity: 3)
        sendFlag.initialize(repeating: -1, count: 3)
    }

    deinit {
        for p in [inL, inR, e, outL, outR, amount, sendFlag] { p.deallocate() }
        live.deallocate()
        delayBeats.deallocate()
    }

    /// Номера FX в Params.fxIds (прежний порядок сетки, затем скрытые).
    static let revSize = 0, dlyTime = 1, odDrive = 2, scAttack = 3
    static let revDecay = 4, dlyFeedback = 5, odType = 6, scRelease = 7
    static let revTone = 8, dlyFilter = 9, odTone = 10, scSource = 11
    static let revHpf = 12, dlySpread = 13, odLowcut = 14, scCurve = 15, revPredelay = 16, dlySync = 17

    /// Начало блока: FX снимка с p-lock играющих шагов (дорожки по порядку — у последней приоритет), источник
    /// и есть ли кого приглушать.
    public func begin(_ d: SoundData, lockMask: UnsafePointer<UInt32>, lockVal: UnsafePointer<Float>, mod: ModEngine? = nil,
                      frame: Int64 = 0) {
        let c = Params.fxCount
        var p = 0
        while p < c {
            live[p] = Double(d.fx[p])
            p += 1
        }
        var t = 0
        while t < d.trackCount {
            let m = lockMask[t]
            if m != 0 {
                p = 0
                while p < c {
                    if m & (UInt32(1) << UInt32(p)) != 0 { live[p] = Double(lockVal[t * c + p]) }
                    p += 1
                }
            }
            t += 1
        }
        // LFO/ENV на ручках FX: источник — дорожка, выбранная при назначении.
        if let m = mod {
            p = 0
            while p < c {
                let src = Int(d.fxSrc[p])
                let tr = Int(d.fxTrack[p])
                if src != 0 && tr < d.trackCount {
                    let sc = d.fxScale[p]
                    let n: Double = sc.toNorm(live[p]) + Double(d.fxAmt[p]) * m.source(tr, src, frame)
                    live[p] = sc.fromNorm(Swift.min(1, Swift.max(0, n)))
                }
                p += 1
            }
        }
        source = Int((live[FxRack.scSource]).rounded())
        anyDucked = false
        t = 0
        while t < d.trackCount {
            if t != source && d.scAmount[d.s(t)] > 0 { anyDucked = true }
            t += 1
        }
    }

    /// Нота дорожки t в кадре frame (каждый удар рэтчета, живая нота): триг Sidechain, если это источник и хоть одна
    /// другая дорожка приглушается.
    public func noteTrig(track t: Int, at frame: Int64) {
        if t != source || !anyDucked { return }
        duck.trig(frame: frame, attack: live[FxRack.scAttack], release: live[FxRack.scRelease], curve: live[FxRack.scCurve])
    }

    /// Огибающая e на блок (после всех тригов секвенсора) и очистка входов шин.
    public func prepare(blockStart: Int64, frames n: Int) {
        duck.process(blockStart: blockStart, out: e, frames: n)
        var k = 0
        while k < 3 {
            (inL + k * maxFrames).update(repeating: 0, count: n)
            (inR + k * maxFrames).update(repeating: 0, count: n)
            k += 1
        }
    }

    /// Эффекты: входы шин → выход (прибавляется к left/right). bpm — для времени Delay.
    public func process(frames n: Int, bpm: Double, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        let lv = live
        let lvl: Float = FxRack.idleLevel
        let revIn: Float = peak(inL, inR, n)
        if revIdle && revIn > lvl {
            revIdle = false
            revQuiet = 0
        }
        if !revIdle {
            reverb.process(inL: inL, inR: inR, outL: outL, outR: outR, frames: n, size: Float(lv[FxRack.revSize]),
                           decay: Float(lv[FxRack.revDecay]), tone: Float(lv[FxRack.revTone]),
                           lowcut: Float(lv[FxRack.revHpf]), predelay: Float(lv[FxRack.revPredelay]))
            add(n, 1, left, right)
            revQuiet = revIn <= lvl && peak(outL, outR, n) <= lvl ? revQuiet + n : 0
            if Double(revQuiet) >= FxRack.revIdleSec * sr {
                revIdle = true
                reverb.sleep()
            }
        }
        let di = Swift.max(0, Swift.min(delayDivs - 1, Int(lv[FxRack.dlyTime].rounded())))
        // Dly Sync выключен — время в мс (10…2000 по экспоненте, как Params.dlyFreeMs).
        let synced: Bool = lv[FxRack.dlySync] >= 0.5
        let freeX: Double = Swift.min(1, Swift.max(0, lv[FxRack.dlyTime] / FxRack.freeTop))
        let freeSec: Double = FxRack.freeMin * pow(FxRack.freeRatio, freeX) / 1000
        let time: Double = Swift.min(FxRack.maxDelay, synced ? delayBeats[di] * 60 / Swift.max(1, bpm) : freeSec)
        let fb: Float = Float(lv[FxRack.dlyFeedback] / 100)
        let dlyIn: Float = peak(inL + maxFrames, inR + maxFrames, n)
        if dlyIdle && dlyIn > lvl {
            dlyIdle = false
            dlyQuiet = 0
        }
        if !dlyIdle {
            delay.process(inL: inL + maxFrames, inR: inR + maxFrames, outL: outL, outR: outR, frames: n, time: Float(time),
                          feedback: fb, filter: Float(lv[FxRack.dlyFilter] / 100),
                          spread: Float(lv[FxRack.dlySpread] / 100))
            add(n, 1, left, right)
            dlyQuiet = dlyIn <= lvl && peak(outL, outR, n) <= lvl ? dlyQuiet + n : 0
            if Double(dlyQuiet) >= FxRack.dlyIdleSec * sr {
                dlyIdle = true
                delay.sleep()
            }
        }
        drive.process(inL: inL + 2 * maxFrames, inR: inR + 2 * maxFrames, outL: outL, outR: outR, frames: n,
                      drive: Float(lv[FxRack.odDrive]), type: Float(lv[FxRack.odType]), tone: Float(lv[FxRack.odTone]),
                      lowcut: Float(lv[FxRack.odLowcut]))
        add(n, FxRack.driveOut, left, right)
    }

    /// Наибольший модуль отсчёта двух каналов блока.
    @inline(__always)
    private func peak(_ l: UnsafePointer<Float>, _ r: UnsafePointer<Float>, _ n: Int) -> Float {
        var m: Float = 0
        var i = 0
        while i < n {
            let a: Float = l[i] < 0 ? -l[i] : l[i]
            let b: Float = r[i] < 0 ? -r[i] : r[i]
            if a > m { m = a }
            if b > m { m = b }
            i += 1
        }
        return m
    }

    @inline(__always)
    private func add(_ n: Int, _ g: Float, _ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>) {
        var i = 0
        while i < n {
            left[i] += outL[i] * g
            right[i] += outR[i] * g
            i += 1
        }
    }

    /// Остановка: будущие триги Sidechain отменяются (возврат досчитывается).
    public func flush() { duck.flush() }
}
