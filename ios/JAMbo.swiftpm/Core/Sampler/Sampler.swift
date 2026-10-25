import Foundation

// Голоса сэмплера и микшер дорожек (в колбэке; как triggerTrack, legatoCut, fadeVoice, retrigger, releaseLive и
// gateTrack веба). Голос: сэмпл (Start/End или маркер нарезки, кубическая интерполяция, край — 4 мс) → Attack/Decay
// (длинная нота держит уровень до конца, Decay — как Release) → Velocity → фильтр (LP/HP + Resonance, Web Audio) →
// Pan (StereoPanner) → шина дорожки → громкость микшера и гейт mute/solo → выход.
// Без выделений памяти после создания: голоса — массивы указателей.

/// Из колбэка в интерфейс: полоса воспроизведения (позиция считается в интерфейсе по времени от начала ноты).
public enum VoiceOut: Sendable {
    case none
    /// Голос v начал звучать в кадре frame: дорожка (−1 — предпрослушка), сэмпл, отрезок a…b (доли), скорость.
    case start(voice: Int, track: Int, hash: UInt64, frame: Int64, a: Double, b: Double, rate: Double, frames: Int)
    case end(voice: Int)
}

public final class Sampler {
    /// Больше 48 голосов — самый старый гаснет за ~5 мс; ячеек с запасом на гаснущие.
    public static let maxVoices = 48
    static let slots = 64
    static let maxFrames = 4096
    public static let previewGain: Float = 0.7

    public let out = SPSCQueue<VoiceOut>(capacity: 2048, filler: .none)
    /// Ноты дорожек с MIDI OUT (SamplerMidi.swift) — для MidiOutPump.
    public let midiOut = SPSCQueue<MidiNoteOut>(capacity: 2048, filler: MidiNoteOut())
    public var sound: SoundData?
    /// Голоса синта (ставит AudioCore.installSynth); звук «mi:<n>» — ноты уходят туда, шины и микшер — общие.
    public internal(set) var synth: SynthVoices?
    /// Ключи звуков синта по движку (сравнение в колбэке без строк).
    let synthHash = UnsafeMutablePointer<UInt64>.allocate(capacity: SynthEngines.count)
    let sr: Double

    // Голоса (по ячейке).
    let active = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    let fading = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    let own = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    let track = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let trackId = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let note = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let liveId = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let serial = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let srcL = UnsafeMutablePointer<UnsafeMutablePointer<Float>?>.allocate(capacity: slots)
    let srcR = UnsafeMutablePointer<UnsafeMutablePointer<Float>?>.allocate(capacity: slots)
    let srcFrames = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let stereo = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    let start = UnsafeMutablePointer<Int64>.allocate(capacity: slots)
    let pos = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let endPos = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let edge = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let noteRatio = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let rate = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let attackF = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let decaySec = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let decayK = UnsafeMutablePointer<Float>.allocate(capacity: slots)
    let holdEnd = UnsafeMutablePointer<Int64>.allocate(capacity: slots)
    let released = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    let env = UnsafeMutablePointer<Float>.allocate(capacity: slots)
    let stopAt = UnsafeMutablePointer<Int64>.allocate(capacity: slots)
    let fadeAt = UnsafeMutablePointer<Int64>.allocate(capacity: slots)
    let fadeK = UnsafeMutablePointer<Float>.allocate(capacity: slots)
    let fadeG = UnsafeMutablePointer<Float>.allocate(capacity: slots)
    let level = UnsafeMutablePointer<Float>.allocate(capacity: slots)
    let pan = UnsafeMutablePointer<Float>.allocate(capacity: slots)
    /// Посылы голоса (Reverb, Delay, Drive; 0…1, сглаженные).
    let send = UnsafeMutablePointer<Float>.allocate(capacity: slots * 3)
    let hz = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let qDb = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let ftype = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let coef = UnsafeMutablePointer<Biquad>.allocate(capacity: slots)
    let z = UnsafeMutablePointer<Float>.allocate(capacity: slots * 4)
    let lockMask = UnsafeMutablePointer<VoiceMask>.allocate(capacity: slots)
    let lockVal = UnsafeMutablePointer<Float>.allocate(capacity: slots * VoiceParam.count)
    var nextSerial = 0

    // Шины дорожек, микшер.
    let busL = UnsafeMutablePointer<Float>.allocate(capacity: SoundData.maxTracks * maxFrames)
    let busR = UnsafeMutablePointer<Float>.allocate(capacity: SoundData.maxTracks * maxFrames)
    let used = UnsafeMutablePointer<UInt8>.allocate(capacity: SoundData.maxTracks)
    let volCur = UnsafeMutablePointer<Float>.allocate(capacity: SoundData.maxTracks)
    let gateCur = UnsafeMutablePointer<Float>.allocate(capacity: SoundData.maxTracks)
    /// Была ли дорожка слышна в прошлом блоке (MUTE TAILS: 2 — ещё неизвестно).
    let openPrev = UnsafeMutablePointer<UInt8>.allocate(capacity: SoundData.maxTracks)
    /// Шины посылов дорожек: (дорожка·3 + посыл)·maxFrames; sendUsed — шины дорожки очищены в этом блоке.
    let sendL = UnsafeMutablePointer<Float>.allocate(capacity: SoundData.maxTracks * 3 * maxFrames)
    let sendR = UnsafeMutablePointer<Float>.allocate(capacity: SoundData.maxTracks * 3 * maxFrames)
    let sendUsed = UnsafeMutablePointer<UInt8>.allocate(capacity: SoundData.maxTracks)
    /// Глубина Sidechain дорожки (сглаженная) и переключатели посылов.
    let duckCur = UnsafeMutablePointer<Float>.allocate(capacity: SoundData.maxTracks)
    let flagCur = UnsafeMutablePointer<Float>.allocate(capacity: 3)
    /// Шины эффектов и Sidechain (ставит AudioCore; nil — без эффектов, как в тестах сэмплера).
    public var fx: FxRack?
    /// EQ дорожек (до Sidechain и громкости микшера; TrackEqs).
    public var eqs: TrackEqs?
    /// Выходы дорожек после громкости микшера, до mute (дорожка·maxFrames) — источники динамических полос EQ.
    public let outL = UnsafeMutablePointer<Float>.allocate(capacity: SoundData.maxTracks * maxFrames)
    public let outR = UnsafeMutablePointer<Float>.allocate(capacity: SoundData.maxTracks * maxFrames)
    /// Сдвиги динамических полос для экрана (ставит AudioCore).
    public var eqDyn: EqDynLevels?
    /// Прослушивание полосы EQ дорожки (после её EQ, во всех линиях).
    public var eqListen: EqListen?
    /// P-lock громкостей играющего шага MIX (Sequencer.mixLockMask / mixLockGain; ставит AudioCore).
    public var mixLockMask: UnsafeMutablePointer<UInt16>?
    public var mixLockGain: UnsafeMutablePointer<Float>?
    /// Точки съёма спектров EQ (ставит AudioCore).
    public var spectra: Spectra?
    /// Пики дорожек для измерителя и метров MIX, громкость показанной дорожки (ставит AudioCore).
    public var levels: Levels?
    /// Замеры колбэка по разделам (S14a; задаёт AudioCore).
    public var profile: RenderProfile?
    /// Запись стемов (S11d): гейт mute/solo по отсчётам (дорожка·maxFrames) — пишет микшер; nil — запись не идёт.
    var stemGate: UnsafeMutablePointer<Float>?
    /// Сигнал показанной дорожки (после громкости, до mute/solo) — для LUFS.
    let meterL = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
    let meterR = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
    /// Модуляция LFO/ENV (ставит AudioCore); modFrame — кадр ноты, которую сейчас запускают.
    public var mod: ModEngine?
    var modFrame: Int64 = 0
    /// Темп (время Delay по долям такта) — ставит AudioCore на блок.
    public var bpm: Double = 120

    // Предпрослушка (▶ редактора): сэмпл в исходной высоте сразу на выход.
    var pvL: UnsafeMutablePointer<Float>?
    var pvR: UnsafeMutablePointer<Float>?
    var pvPos: Double = 0
    var pvEnd: Double = 0
    var pvGain: Float = 0
    var pvStop: Bool = false
    var pvStereo = false
    /// Ячейка полосы предпрослушки в сообщениях VoiceOut.
    public static let previewVoice = 99

    // Ноты для retrigger и живых нот.
    let one = UnsafeMutablePointer<Int16>.allocate(capacity: 1)
    let scratch = UnsafeMutablePointer<Float>.allocate(capacity: VoiceParam.count)

    public init(sampleRate: Double) {
        sr = sampleRate
        let s = Sampler.slots
        active.initialize(repeating: 0, count: s)
        fading.initialize(repeating: 0, count: s)
        own.initialize(repeating: 0, count: s)
        track.initialize(repeating: 0, count: s)
        trackId.initialize(repeating: 0, count: s)
        note.initialize(repeating: 0, count: s)
        liveId.initialize(repeating: -1, count: s)
        serial.initialize(repeating: 0, count: s)
        srcL.initialize(repeating: nil, count: s)
        srcR.initialize(repeating: nil, count: s)
        srcFrames.initialize(repeating: 0, count: s)
        stereo.initialize(repeating: 0, count: s)
        start.initialize(repeating: 0, count: s)
        pos.initialize(repeating: 0, count: s)
        endPos.initialize(repeating: 0, count: s)
        edge.initialize(repeating: 1, count: s)
        noteRatio.initialize(repeating: 1, count: s)
        rate.initialize(repeating: 1, count: s)
        attackF.initialize(repeating: 48, count: s)
        decaySec.initialize(repeating: 0.5, count: s)
        decayK.initialize(repeating: 0, count: s)
        holdEnd.initialize(repeating: 0, count: s)
        released.initialize(repeating: 0, count: s)
        env.initialize(repeating: 0, count: s)
        stopAt.initialize(repeating: 0, count: s)
        fadeAt.initialize(repeating: Int64.max, count: s)
        fadeK.initialize(repeating: 1, count: s)
        fadeG.initialize(repeating: 1, count: s)
        level.initialize(repeating: 1, count: s)
        pan.initialize(repeating: 0, count: s)
        send.initialize(repeating: 0, count: s * 3)
        sendL.initialize(repeating: 0, count: SoundData.maxTracks * 3 * Sampler.maxFrames)
        sendR.initialize(repeating: 0, count: SoundData.maxTracks * 3 * Sampler.maxFrames)
        sendUsed.initialize(repeating: 0, count: SoundData.maxTracks)
        duckCur.initialize(repeating: 0, count: SoundData.maxTracks)
        flagCur.initialize(repeating: -1, count: 3)
        hz.initialize(repeating: 20000, count: s)
        qDb.initialize(repeating: 0.7, count: s)
        ftype.initialize(repeating: -1, count: s)
        coef.initialize(repeating: Biquad(), count: s)
        z.initialize(repeating: 0, count: s * 4)
        lockMask.initialize(repeating: 0, count: s)
        lockVal.initialize(repeating: 0, count: s * VoiceParam.count)
        busL.initialize(repeating: 0, count: SoundData.maxTracks * Sampler.maxFrames)
        busR.initialize(repeating: 0, count: SoundData.maxTracks * Sampler.maxFrames)
        outL.initialize(repeating: 0, count: SoundData.maxTracks * Sampler.maxFrames)
        outR.initialize(repeating: 0, count: SoundData.maxTracks * Sampler.maxFrames)
        used.initialize(repeating: 0, count: SoundData.maxTracks)
        volCur.initialize(repeating: -1, count: SoundData.maxTracks)
        gateCur.initialize(repeating: -1, count: SoundData.maxTracks)
        openPrev.initialize(repeating: 2, count: SoundData.maxTracks)
        one.initialize(to: 0)
        scratch.initialize(repeating: 0, count: VoiceParam.count)
        // Незанятые номера (движки Mutable Instruments) — 0: такой звук не синт и не сэмпл (пустой).
        synthHash.initialize(repeating: 0, count: SynthEngines.count)
        for e in SynthEngines.all { synthHash[e.id] = SoundKey.hash(SynthKey.key(e.id)) }
    }

    deinit {
        for p in [active, fading, own, stereo, released, used, sendUsed, openPrev] as [UnsafeMutablePointer<UInt8>] { p.deallocate() }
        for p in [send, sendL, sendR, duckCur, flagCur, meterL, meterR] { p.deallocate() }
        for p in [track, trackId, note, liveId, serial, srcFrames, ftype] as [UnsafeMutablePointer<Int>] { p.deallocate() }
        for p in [pos, endPos, edge, noteRatio, rate, attackF, decaySec, hz, qDb] as [UnsafeMutablePointer<Double>] { p.deallocate() }
        for p in [start, holdEnd, stopAt, fadeAt] as [UnsafeMutablePointer<Int64>] { p.deallocate() }
        for p in [decayK, env, fadeK, fadeG, level, pan, z, lockVal, busL, busR, outL, outR, volCur, gateCur, scratch] as [UnsafeMutablePointer<Float>] {
            p.deallocate()
        }
        srcL.deallocate()
        srcR.deallocate()
        coef.deallocate()
        lockMask.deallocate()
        one.deallocate()
        synthHash.deallocate()
    }


    /// Сколько голосов звучит (для тестов и диагностики).
    public var activeCount: Int {
        var n = 0
        for v in 0..<Sampler.slots where active[v] != 0 { n += 1 }
        return n
    }

    // MARK: — звук

    @inline(__always)
    private static func cubic(_ p: UnsafeMutablePointer<Float>, _ n: Int, _ x: Double) -> Float {
        let i = Int(x)
        let f = Float(x - Double(i))
        let ym1: Float = i >= 1 && i - 1 < n ? p[i - 1] : 0
        let y0: Float = i < n ? p[i] : 0
        let y1: Float = i + 1 < n ? p[i + 1] : 0
        let y2: Float = i + 2 < n ? p[i + 2] : 0
        let c1: Float = 0.5 * (y1 - ym1)
        let c2: Float = ym1 - 2.5 * y0 + 2 * y1 - 0.5 * y2
        let c3: Float = 0.5 * (y2 - ym1) + 1.5 * (y0 - y1)
        return ((c3 * f + c2) * f + c1) * f + y0
    }

    /// Блок: голоса в шины дорожек, микшер (громкость, mute/solo) и предпрослушка — прибавляются к left/right.
    public func render(blockStart: Int64, frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        let n = Swift.min(frames, Sampler.maxFrames)
        guard let d = sound else { return }
        for t in 0..<SoundData.maxTracks { used[t] = 0 }
        for v in 0..<Sampler.slots where active[v] != 0 {
            let t = track[v]
            if t >= d.trackCount { finish(v); continue }
            if used[t] == 0 {
                (busL + t * Sampler.maxFrames).update(repeating: 0, count: n)
                (busR + t * Sampler.maxFrames).update(repeating: 0, count: n)
                clearSends(t, n)
                used[t] = 1
            }
            renderVoice(v, d, blockStart, n)
        }
        let pf: RenderProfile? = profile
        pf?.lap(RenderProfile.voices)
        synth?.render(d, blockStart: blockStart, frames: n, busL: busL, busR: busR, sendL: sendL, sendR: sendR,
                      used: used, stride: Sampler.maxFrames)
        pf?.lap(RenderProfile.synth)
        wakeEqs(d, n)
        pf?.lap(RenderProfile.eq)
        fx?.prepare(blockStart: blockStart, frames: n)
        pf?.lap(RenderProfile.fx)
        mix(d, n, left, right)
        pf?.lap(RenderProfile.mix)
        fx?.process(frames: n, bpm: bpm, left: left, right: right)
        pf?.lap(RenderProfile.fx)
    }

    /// Шины посылов дорожки t — с нуля (n отсчётов).
    @inline(__always)
    private func clearSends(_ t: Int, _ n: Int) {
        var k = 0
        while k < 3 {
            (sendL + (t * 3 + k) * Sampler.maxFrames).update(repeating: 0, count: n)
            (sendR + (t * 3 + k) * Sampler.maxFrames).update(repeating: 0, count: n)
            k += 1
        }
    }

    private func renderVoice(_ v: Int, _ d: SoundData, _ blockStart: Int64, _ n: Int) {
        guard let l = srcL[v], let r = srcR[v] else { finish(v); return }
        let t = track[v]
        let mask = lockMask[v]
        let base = v * VoiceParam.count
        // Ручки дорожки меняют звучащую ноту сразу; p-lock шага держит своё.
        let modE: ModEngine? = mod != nil && mod!.modulated(t) ? mod : nil
        @inline(__always) func val(_ p: Int) -> Double {
            var x: Double = Double(d.param(t, p))
            if mask & (VoiceMask(1) << VoiceMask(p)) != 0 { x = Double(lockVal[base + p]) }
            if let mm = modE { x = mm.value(t, p, x, blockStart) }
            return x
        }
        let rateT: Double = noteRatio[v] * pow(2, val(VoiceParam.pitch) / 12)
        let levelT = Float(pow(val(VoiceParam.level) / 127, 1.5))
        let sb = v * 3
        let send0T = Float(val(VoiceParam.reverb) / 100), send1T = Float(val(VoiceParam.delay) / 100)
        let send2T = Float(val(VoiceParam.drive) / 100)
        let sends0L = sendL + t * 3 * Sampler.maxFrames, sends0R = sendR + t * 3 * Sampler.maxFrames
        let mf = Sampler.maxFrames
        let panT = Float(Swift.max(-1, Swift.min(1, val(VoiceParam.pan) / 64)))
        let fk = Biquad.knob(val(VoiceParam.filter), reso: val(VoiceParam.reso))
        if fk.type != ftype[v] {
            ftype[v] = fk.type
            hz[v] = fk.hz
        }
        let sub = 32
        let ks: Double = 1 - exp(-Double(sub) / (0.01 * sr))
        let kf: Double = 1 - exp(-Double(sub) / (0.015 * sr))
        let frames = srcFrames[v]
        let st = stereo[v] != 0
        let zb = v * 4
        var i = 0
        while i < n {
            let m = Swift.min(sub, n - i)
            // Сглаживание ручек по кусочкам (setTargetAtTime веба: 10 мс, фильтр — 15 мс).
            rate[v] += (rateT - rate[v]) * ks
            level[v] += (levelT - level[v]) * Float(ks)
            pan[v] += (panT - pan[v]) * Float(ks)
            send[sb] += (send0T - send[sb]) * Float(ks)
            send[sb + 1] += (send1T - send[sb + 1]) * Float(ks)
            send[sb + 2] += (send2T - send[sb + 2]) * Float(ks)
            let sg0 = send[sb], sg1 = send[sb + 1], sg2 = send[sb + 2]
            let hasSend: Bool = sg0 > 1e-6 || sg1 > 1e-6 || sg2 > 1e-6
            let h0 = hz[v]
            let q0 = qDb[v]
            hz[v] += (fk.hz - hz[v]) * kf
            qDb[v] += (fk.q - qDb[v]) * kf
            if abs(hz[v] - h0) > 1e-6 || abs(qDb[v] - q0) > 1e-6 {
                coef[v].set(type: ftype[v], hz: hz[v], qDb: qDb[v], sampleRate: sr)
            }
            let c = coef[v]
            let pn = pan[v]
            // StereoPanner: моно — cos/sin; стерео — перекрёстно в сторону панорамы.
            let x: Float = st ? (pn <= 0 ? pn + 1 : pn) : (pn + 1) / 2
            let gc = cos(x * Float.pi / 2)
            let gs = sin(x * Float.pi / 2)
            let lv = level[v]
            let rt = rate[v]
            for j in 0..<m {
                let frame = blockStart + Int64(i + j)
                if frame < start[v] { continue }
                if frame >= stopAt[v] || pos[v] >= endPos[v] || pos[v] >= Double(frames) {
                    finish(v)
                    return
                }
                // Огибающая: атака линейно, удержание, затем Decay как Release (экспонента, τ = Decay/4).
                var e: Float
                if frame >= holdEnd[v] {
                    if released[v] == 0 {
                        released[v] = 1
                        let tt = Double(frame - start[v])
                        env[v] = tt < attackF[v] ? Float(tt / attackF[v]) : 1
                    }
                    env[v] *= decayK[v]
                    e = env[v]
                } else {
                    let tt = Double(frame - start[v])
                    e = tt < attackF[v] ? Float(tt / attackF[v]) : 1
                    env[v] = e
                }
                if frame >= fadeAt[v] { fadeG[v] *= fadeK[v] }
                let remain: Double = (endPos[v] - pos[v]) / rt
                let eg = Float(Swift.min(1, remain / edge[v]))
                let g: Float = e * eg * lv * fadeG[v]
                var a: Float = Sampler.cubic(l, frames, pos[v]) * g
                var b: Float = st ? Sampler.cubic(r, frames, pos[v]) * g : 0
                // Фильтр (TDF II).
                let ya: Float = c.b0 * a + z[zb]
                z[zb] = c.b1 * a - c.a1 * ya + z[zb + 1]
                z[zb + 1] = c.b2 * a - c.a2 * ya
                a = ya
                if st {
                    let yb: Float = c.b0 * b + z[zb + 2]
                    z[zb + 2] = c.b1 * b - c.a1 * yb + z[zb + 3]
                    z[zb + 3] = c.b2 * b - c.a2 * yb
                    b = yb
                }
                let k = t * Sampler.maxFrames + i + j
                let oa: Float
                let ob: Float
                if st {
                    if pn <= 0 {
                        oa = a + b * gc
                        ob = b * gs
                    } else {
                        oa = a * gc
                        ob = b + a * gs
                    }
                } else {
                    oa = a * gc
                    ob = a * gs
                }
                busL[k] += oa
                busR[k] += ob
                // Посылы голоса — после Pan.
                if hasSend {
                    let q = i + j
                    sends0L[q] += oa * sg0
                    sends0R[q] += ob * sg0
                    sends0L[mf + q] += oa * sg1
                    sends0R[mf + q] += ob * sg1
                    sends0L[2 * mf + q] += oa * sg2
                    sends0R[2 * mf + q] += ob * sg2
                }
                pos[v] += rt
            }
            // Денормалы в состоянии фильтра.
            for k in 0..<4 where abs(z[zb + k]) < 1e-20 { z[zb + k] = 0 }
            i += m
        }
    }
}
