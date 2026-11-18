import Foundation

// Эффекты дорожек и Sidechain (17.11, решения пользователя): у каждой дорожки свои Reverb, Delay, Drive (прежде — общие
// шины); посылы — параллельные (ручки 3.1–3.3, после громкости и mute/solo дорожки) → эффекты
// дорожки → выход (Drive — с усилением 0,5). Значения — FX клипа, который играет на дорожке (SoundData.clipFx), с p-lock
// шагов своей дорожки и LFO/ENV, назначенными с этой дорожки. Огибающая Sidechain (Duck) одна на проект, её параметры
// и источник — общие (FX клипа, запущенного последним, с p-lock любой дорожки): громкость дорожки = 1 − amount·e,
// посылы приглушаются так же, если включён переключатель SETTINGS → SIDECHAIN.
// Эффекты дорожки считаются, только пока в них есть звук (покой — тишина на входе и выходе), — заданиями RenderPool
// (MULTICORE); выходы складываются по порядку дорожек. Всё в колбэке: буферы выделены при создании.

public final class FxRack: RenderJobs {
    /// Выходное усиление шины Drive (как у прежнего Overdrive).
    static let driveOut: Float = 0.5
    /// Наибольшее время Delay, с: 1 такт при наименьшем темпе.
    static let maxDelay: Double = 4 * 60 / Params.bpmMin
    /// Время без синхронизации — копия Params.dlyFreeMin, dlyFreeMax / dlyFreeMin, dlyFreeTop.
    static let freeMin: Double = Params.dlyFreeMin
    static let freeRatio: Double = Params.dlyFreeMax / Params.dlyFreeMin
    static let freeTop: Double = Params.dlyFreeTop
    static let tracks: Int = SoundData.maxTracks

    let sr: Double
    /// Эффекты дорожек (по дорожке).
    public let reverb: UnsafeMutablePointer<FxReverb>
    public let delay: UnsafeMutablePointer<FxDelay>
    public let drive: UnsafeMutablePointer<FxDrive>
    public let duck: FxDuck
    /// Входы эффектов дорожки (посылы после громкости): (дорожка·3 + посыл)·maxFrames; fed — вход записан в этом блоке.
    let inL: UnsafeMutablePointer<Float>
    let inR: UnsafeMutablePointer<Float>
    let fed: UnsafeMutablePointer<UInt8>
    /// Огибающая e на блок.
    let e: UnsafeMutablePointer<Float>
    /// Выход эффектов дорожки (сумма трёх) и выход одного эффекта: дорожка·maxFrames.
    let outL: UnsafeMutablePointer<Float>
    let outR: UnsafeMutablePointer<Float>
    let tmpL: UnsafeMutablePointer<Float>
    let tmpR: UnsafeMutablePointer<Float>
    /// Общие значения FX на блок (Params.fxIds: FX клипа лидера с p-lock любой дорожки) — Duck и источник.
    public let live: UnsafeMutablePointer<Double>
    /// Значения FX дорожек на блок: дорожка·fxCount.
    public let tlive: UnsafeMutablePointer<Double>
    /// Глубина Sidechain дорожек и переключатели посылов — сглаженные (~10 мс).
    let amount: UnsafeMutablePointer<Float>
    let sendFlag: UnsafeMutablePointer<Float>
    var source = 0
    var anyDucked = false
    /// Покой эффектов дорожки (S14b): вход молчит и выход тише −120 dBFS дольше самого длинного внутреннего пути
    /// (Reverb — предзадержка до 240 мс и линии; Delay — вся линия и 0,5 с; Drive — 0,1 с) — эффект не считается;
    /// первый ненулевой вход будит его. Звук не меняется: всё, что внутри, уже ниже −120 dB.
    static let idleLevel: Float = 1e-6
    static let revIdleSec: Double = 1
    static let odIdleSec: Double = 0.1
    let dlyIdleSec: Double
    private let revQuiet: UnsafeMutablePointer<Int>
    private let dlyQuiet: UnsafeMutablePointer<Int>
    private let odQuiet: UnsafeMutablePointer<Int>
    private let idle: UnsafeMutablePointer<UInt8>
    let maxFrames: Int
    /// Время Delay по пунктам (четверти) — копия Params.delayDivs (колбэк не читает Swift-массивы).
    let delayBeats: UnsafeMutablePointer<Double>
    let delayDivs: Int
    /// Многоядерный режим (ставит AudioCore): эффекты дорожек — задания пула.
    public var pool: RenderPool?
    private let jobTracks: UnsafeMutablePointer<Int>
    private var jobN: Int = 0
    private var jobBpm: Double = 120
    private var trackCount: Int = 0

    public init(sampleRate: Double, maxFrames: Int = 4096) {
        sr = sampleRate
        self.maxFrames = maxFrames
        let divs = Params.delayDivs
        let beats = UnsafeMutablePointer<Double>.allocate(capacity: divs.count)
        for (k, d) in divs.enumerated() { (beats + k).initialize(to: d.beats) }
        delayDivs = divs.count
        delayBeats = beats
        let nt: Int = FxRack.tracks
        reverb = UnsafeMutablePointer<FxReverb>.allocate(capacity: nt)
        delay = UnsafeMutablePointer<FxDelay>.allocate(capacity: nt)
        drive = UnsafeMutablePointer<FxDrive>.allocate(capacity: nt)
        for t in 0..<nt {
            (reverb + t).initialize(to: FxReverb(sampleRate: sampleRate, seed: FxRandom.seed()))
            (delay + t).initialize(to: FxDelay(sampleRate: sampleRate, maxTime: FxRack.maxDelay, seed: FxRandom.seed()))
            (drive + t).initialize(to: FxDrive(sampleRate: sampleRate))
        }
        // Вся линия Delay переписана тишиной — только тогда сон (линия не чистится).
        dlyIdleSec = Double(delay[0].len) / sampleRate + 0.5
        duck = FxDuck(sampleRate: sampleRate)
        inL = UnsafeMutablePointer<Float>.allocate(capacity: nt * 3 * maxFrames)
        inR = UnsafeMutablePointer<Float>.allocate(capacity: nt * 3 * maxFrames)
        inL.initialize(repeating: 0, count: nt * 3 * maxFrames)
        inR.initialize(repeating: 0, count: nt * 3 * maxFrames)
        fed = UnsafeMutablePointer<UInt8>.allocate(capacity: nt)
        fed.initialize(repeating: 0, count: nt)
        e = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
        e.initialize(repeating: 0, count: maxFrames)
        outL = UnsafeMutablePointer<Float>.allocate(capacity: nt * maxFrames)
        outR = UnsafeMutablePointer<Float>.allocate(capacity: nt * maxFrames)
        tmpL = UnsafeMutablePointer<Float>.allocate(capacity: nt * maxFrames)
        tmpR = UnsafeMutablePointer<Float>.allocate(capacity: nt * maxFrames)
        for p in [outL, outR, tmpL, tmpR] { p.initialize(repeating: 0, count: nt * maxFrames) }
        live = UnsafeMutablePointer<Double>.allocate(capacity: Params.fxCount)
        for (k, id) in Params.fxIds.enumerated() { (live + k).initialize(to: Params.byId[id]?.def ?? 0) }
        tlive = UnsafeMutablePointer<Double>.allocate(capacity: nt * Params.fxCount)
        for t in 0..<nt { (tlive + t * Params.fxCount).initialize(from: live, count: Params.fxCount) }
        amount = UnsafeMutablePointer<Float>.allocate(capacity: nt)
        amount.initialize(repeating: 0, count: nt)
        sendFlag = UnsafeMutablePointer<Float>.allocate(capacity: 3)
        sendFlag.initialize(repeating: -1, count: 3)
        revQuiet = UnsafeMutablePointer<Int>.allocate(capacity: nt)
        dlyQuiet = UnsafeMutablePointer<Int>.allocate(capacity: nt)
        odQuiet = UnsafeMutablePointer<Int>.allocate(capacity: nt)
        for p in [revQuiet, dlyQuiet, odQuiet] { p.initialize(repeating: 0, count: nt) }
        // Покой: дорожка·3 + эффект (0 Reverb, 1 Delay, 2 Drive); с начала — спят, первый посыл будит.
        idle = UnsafeMutablePointer<UInt8>.allocate(capacity: nt * 3)
        idle.initialize(repeating: 1, count: nt * 3)
        jobTracks = UnsafeMutablePointer<Int>.allocate(capacity: nt)
        jobTracks.initialize(repeating: 0, count: nt)
    }

    deinit {
        let nt: Int = FxRack.tracks
        reverb.deinitialize(count: nt)
        reverb.deallocate()
        delay.deinitialize(count: nt)
        delay.deallocate()
        drive.deinitialize(count: nt)
        drive.deallocate()
        for p in [inL, inR, e, outL, outR, tmpL, tmpR, amount, sendFlag] { p.deallocate() }
        for p in [revQuiet, dlyQuiet, odQuiet, jobTracks] { p.deallocate() }
        fed.deallocate()
        idle.deallocate()
        live.deallocate()
        tlive.deallocate()
        delayBeats.deallocate()
    }

    /// Покой эффекта дорожки t (тесты, диагностика).
    public func revIdle(_ t: Int) -> Bool { return idle[t * 3] != 0 }
    public func dlyIdle(_ t: Int) -> Bool { return idle[t * 3 + 1] != 0 }
    public func odIdle(_ t: Int) -> Bool { return idle[t * 3 + 2] != 0 }

    /// Номера FX в Params.fxIds (прежний порядок сетки, затем скрытые).
    static let revSize = 0, dlyTime = 1, odDrive = 2, scAttack = 3
    static let revDecay = 4, dlyFeedback = 5, odType = 6, scRelease = 7
    static let revTone = 8, dlyFilter = 9, odTone = 10, scSource = 11
    static let revHpf = 12, dlySpread = 13, odLowcut = 14, scCurve = 15, revPredelay = 16, dlySync = 17

    /// Начало блока: общие FX (FX клипа лидера с p-lock играющих шагов любой дорожки — у последней приоритет) — Duck
    /// и источник; FX дорожек — клипа, который играет на дорожке, с p-lock её шагов; LFO/ENV — на FX дорожки, с которой
    /// назначены (и на общие, как прежде).
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
        // FX дорожек: строка клипа, который играет (нет клипа — общие значения снимка).
        let slots: Int = Params.patternSlots
        trackCount = d.trackCount
        t = 0
        while t < d.trackCount {
            let row: UnsafeMutablePointer<Double> = tlive + t * c
            let k: Int = d.slotRef[t]
            let src: UnsafeMutablePointer<Float> = k >= 0 && k < slots ? d.clipFx + (t * slots + k) * c : d.fx
            let m = lockMask[t]
            p = 0
            while p < c {
                row[p] = m & (UInt32(1) << UInt32(p)) != 0 ? Double(lockVal[t * c + p]) : Double(src[p])
                p += 1
            }
            t += 1
        }
        // LFO/ENV на ручках FX: источник — дорожка, выбранная при назначении; её эффекты (и общие значения).
        if let m = mod {
            p = 0
            while p < c {
                let src = Int(d.fxSrc[p])
                let tr = Int(d.fxTrack[p])
                if src != 0 && tr < d.trackCount {
                    let sc = d.fxScale[p]
                    let sv: Double = Double(d.fxAmt[p]) * m.source(tr, src, frame)
                    let n: Double = sc.toNorm(live[p]) + sv
                    live[p] = sc.fromNorm(Swift.min(1, Swift.max(0, n)))
                    let row: UnsafeMutablePointer<Double> = tlive + tr * c
                    let nt: Double = sc.toNorm(row[p]) + sv
                    row[p] = sc.fromNorm(Swift.min(1, Swift.max(0, nt)))
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

    /// Огибающая e на блок (после всех тригов секвенсора); входы дорожек — не записаны (микшер пишет посылы звучащих).
    public func prepare(blockStart: Int64, frames n: Int) {
        duck.process(blockStart: blockStart, out: e, frames: n)
        fed.update(repeating: 0, count: FxRack.tracks)
    }

    /// Эффекты дорожек: входы → выходы дорожек (заданиями пула) → сумма по порядку дорожек к left/right.
    /// bpm — для времени Delay.
    public func process(frames n: Int, bpm: Double, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        var jt: Int = 0
        var t: Int = 0
        while t < trackCount {
            let b: Int = t * 3
            if fed[t] != 0 || idle[b] == 0 || idle[b + 1] == 0 || idle[b + 2] == 0 {
                jobTracks[jt] = t
                jt += 1
            }
            t += 1
        }
        if jt == 0 { return }
        jobN = n
        jobBpm = bpm
        if let p = pool, jt > 1 {
            p.run(jt, self)
        } else {
            var j: Int = 0
            while j < jt {
                processTrack(jobTracks[j])
                j += 1
            }
        }
        let mf: Int = maxFrames
        var j: Int = 0
        while j < jt {
            let ol: UnsafeMutablePointer<Float> = outL + jobTracks[j] * mf
            let or: UnsafeMutablePointer<Float> = outR + jobTracks[j] * mf
            var i = 0
            while i < n {
                left[i] += ol[i]
                right[i] += or[i]
                i += 1
            }
            j += 1
        }
    }

    /// Задание пула: эффекты j-й дорожки блока.
    public func runJob(_ j: Int) {
        processTrack(jobTracks[j])
    }

    /// Эффекты дорожки t: Reverb, Delay, Drive (каждый — пока в нём есть звук) → outL/outR дорожки.
    private func processTrack(_ t: Int) {
        let n: Int = jobN
        let mf: Int = maxFrames
        let c: Int = Params.fxCount
        let lv: UnsafeMutablePointer<Double> = tlive + t * c
        let lvl: Float = FxRack.idleLevel
        let ol: UnsafeMutablePointer<Float> = outL + t * mf
        let or: UnsafeMutablePointer<Float> = outR + t * mf
        let xl: UnsafeMutablePointer<Float> = tmpL + t * mf
        let xr: UnsafeMutablePointer<Float> = tmpR + t * mf
        ol.update(repeating: 0, count: n)
        or.update(repeating: 0, count: n)
        let isFed: Bool = fed[t] != 0
        let b: Int = t * 3
        let i0: Int = t * 3 * mf
        // Reverb.
        let rL: UnsafePointer<Float>? = isFed ? UnsafePointer(inL + i0) : nil
        let rR: UnsafePointer<Float>? = isFed ? UnsafePointer(inR + i0) : nil
        let revIn: Float = isFed ? peak(inL + i0, inR + i0, n) : 0
        if idle[b] != 0 && revIn > lvl {
            idle[b] = 0
            revQuiet[t] = 0
        }
        if idle[b] == 0 {
            reverb[t].process(inL: rL, inR: rR, outL: xl, outR: xr, frames: n, size: Float(lv[FxRack.revSize]),
                              decay: Float(lv[FxRack.revDecay]), tone: Float(lv[FxRack.revTone]),
                              lowcut: Float(lv[FxRack.revHpf]), predelay: Float(lv[FxRack.revPredelay]))
            add(n, 1, xl, xr, ol, or)
            revQuiet[t] = revIn <= lvl && peak(xl, xr, n) <= lvl ? revQuiet[t] + n : 0
            if Double(revQuiet[t]) >= FxRack.revIdleSec * sr {
                idle[b] = 1
                reverb[t].sleep()
            }
        }
        // Delay.
        let dL: UnsafePointer<Float>? = isFed ? UnsafePointer(inL + i0 + mf) : nil
        let dR: UnsafePointer<Float>? = isFed ? UnsafePointer(inR + i0 + mf) : nil
        let dlyIn: Float = isFed ? peak(inL + i0 + mf, inR + i0 + mf, n) : 0
        if idle[b + 1] != 0 && dlyIn > lvl {
            idle[b + 1] = 0
            dlyQuiet[t] = 0
        }
        if idle[b + 1] == 0 {
            let di = Swift.max(0, Swift.min(delayDivs - 1, Int(lv[FxRack.dlyTime].rounded())))
            // Dly Sync выключен — время в мс (10…2000 по экспоненте, как Params.dlyFreeMs).
            let synced: Bool = lv[FxRack.dlySync] >= 0.5
            let freeX: Double = Swift.min(1, Swift.max(0, lv[FxRack.dlyTime] / FxRack.freeTop))
            let freeSec: Double = FxRack.freeMin * pow(FxRack.freeRatio, freeX) / 1000
            let time: Double = Swift.min(FxRack.maxDelay, synced ? delayBeats[di] * 60 / Swift.max(1, jobBpm) : freeSec)
            let fb: Float = Float(lv[FxRack.dlyFeedback] / 100)
            delay[t].process(inL: dL, inR: dR, outL: xl, outR: xr, frames: n, time: Float(time), feedback: fb,
                             filter: Float(lv[FxRack.dlyFilter] / 100), spread: Float(lv[FxRack.dlySpread] / 100))
            add(n, 1, xl, xr, ol, or)
            dlyQuiet[t] = dlyIn <= lvl && peak(xl, xr, n) <= lvl ? dlyQuiet[t] + n : 0
            if Double(dlyQuiet[t]) >= dlyIdleSec * sr {
                idle[b + 1] = 1
                delay[t].sleep()
            }
        }
        // Drive.
        let vL: UnsafePointer<Float>? = isFed ? UnsafePointer(inL + i0 + 2 * mf) : nil
        let vR: UnsafePointer<Float>? = isFed ? UnsafePointer(inR + i0 + 2 * mf) : nil
        let odIn: Float = isFed ? peak(inL + i0 + 2 * mf, inR + i0 + 2 * mf, n) : 0
        if idle[b + 2] != 0 && odIn > lvl {
            idle[b + 2] = 0
            odQuiet[t] = 0
        }
        if idle[b + 2] == 0 {
            drive[t].process(inL: vL, inR: vR, outL: xl, outR: xr, frames: n, drive: Float(lv[FxRack.odDrive]),
                             type: Float(lv[FxRack.odType]), tone: Float(lv[FxRack.odTone]),
                             lowcut: Float(lv[FxRack.odLowcut]))
            add(n, FxRack.driveOut, xl, xr, ol, or)
            odQuiet[t] = odIn <= lvl && peak(xl, xr, n) <= lvl ? odQuiet[t] + n : 0
            if Double(odQuiet[t]) >= FxRack.odIdleSec * sr {
                idle[b + 2] = 1
                drive[t].reset()
            }
        }
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
    private func peak(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int) -> Float {
        return peak(UnsafePointer(l), UnsafePointer(r), n)
    }

    @inline(__always)
    private func add(_ n: Int, _ g: Float, _ xl: UnsafeMutablePointer<Float>, _ xr: UnsafeMutablePointer<Float>,
                     _ ol: UnsafeMutablePointer<Float>, _ or: UnsafeMutablePointer<Float>) {
        var i = 0
        while i < n {
            ol[i] += xl[i] * g
            or[i] += xr[i] * g
            i += 1
        }
    }

    /// Остановка: будущие триги Sidechain отменяются (возврат досчитывается).
    public func flush() { duck.flush() }
}
