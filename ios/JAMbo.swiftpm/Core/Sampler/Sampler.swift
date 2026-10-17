import Foundation

// Голоса сэмплера и микшер дорожек (в колбэке; как triggerTrack, legatoCut, fadeVoice, retrigger, releaseLive и
// gateTrack веба). Голос: сэмпл (Start/End или маркер нарезки, кубическая интерполяция, край — 4 мс) → Attack/Decay
// (длинная нота держит уровень до конца, Decay — как Release) → Level → фильтр (LP/HP + Resonance, Web Audio) →
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
    let hz = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let qDb = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let ftype = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let coef = UnsafeMutablePointer<Biquad>.allocate(capacity: slots)
    let z = UnsafeMutablePointer<Float>.allocate(capacity: slots * 4)
    let lockMask = UnsafeMutablePointer<UInt16>.allocate(capacity: slots)
    let lockVal = UnsafeMutablePointer<Float>.allocate(capacity: slots * VoiceParam.count)
    private var nextSerial = 0

    // Шины дорожек, микшер.
    let busL = UnsafeMutablePointer<Float>.allocate(capacity: SoundData.maxTracks * maxFrames)
    let busR = UnsafeMutablePointer<Float>.allocate(capacity: SoundData.maxTracks * maxFrames)
    let used = UnsafeMutablePointer<UInt8>.allocate(capacity: SoundData.maxTracks)
    let volCur = UnsafeMutablePointer<Float>.allocate(capacity: SoundData.maxTracks)
    let gateCur = UnsafeMutablePointer<Float>.allocate(capacity: SoundData.maxTracks)

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
        hz.initialize(repeating: 20000, count: s)
        qDb.initialize(repeating: 0.7, count: s)
        ftype.initialize(repeating: -1, count: s)
        coef.initialize(repeating: Biquad(), count: s)
        z.initialize(repeating: 0, count: s * 4)
        lockMask.initialize(repeating: 0, count: s)
        lockVal.initialize(repeating: 0, count: s * VoiceParam.count)
        busL.initialize(repeating: 0, count: SoundData.maxTracks * Sampler.maxFrames)
        busR.initialize(repeating: 0, count: SoundData.maxTracks * Sampler.maxFrames)
        used.initialize(repeating: 0, count: SoundData.maxTracks)
        volCur.initialize(repeating: -1, count: SoundData.maxTracks)
        gateCur.initialize(repeating: -1, count: SoundData.maxTracks)
        one.initialize(to: 0)
        scratch.initialize(repeating: 0, count: VoiceParam.count)
        for e in 0..<SynthEngines.count { (synthHash + e).initialize(to: SoundKey.hash(SynthKey.key(e))) }
    }

    deinit {
        for p in [active, fading, own, stereo, released, used] as [UnsafeMutablePointer<UInt8>] { p.deallocate() }
        for p in [track, trackId, note, liveId, serial, srcFrames, ftype] as [UnsafeMutablePointer<Int>] { p.deallocate() }
        for p in [pos, endPos, edge, noteRatio, rate, attackF, decaySec, hz, qDb] as [UnsafeMutablePointer<Double>] { p.deallocate() }
        for p in [start, holdEnd, stopAt, fadeAt] as [UnsafeMutablePointer<Int64>] { p.deallocate() }
        for p in [decayK, env, fadeK, fadeG, level, pan, z, lockVal, busL, busR, volCur, gateCur, scratch] as [UnsafeMutablePointer<Float>] {
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

    // MARK: — запуск

    /// Значение параметра p голоса: p-lock (mask, vals) или ручка дорожки t.
    @inline(__always)
    private func pv(_ d: SoundData, _ t: Int, _ p: Int, _ mask: UInt16, _ vals: UnsafePointer<Float>?) -> Double {
        if mask & (UInt16(1) << UInt16(p)) != 0, let v = vals { return Double(v[p]) }
        return Double(d.param(t, p))
    }

    /// Ноты дорожки t в кадре frame. hash — свой звук шага (0 — звук дорожки); gate — удержание в кадрах
    /// (−1 — нота в 1 шаг: Decay сразу после атаки; Int64.max — живая нота до release).
    public func trigger(track t: Int, at frame: Int64, notes: UnsafePointer<Int16>, count: Int, mask: UInt16,
                        vals: UnsafePointer<Float>?, hash: UInt64, gate: Int64, own isOwn: Bool, liveId live: Int,
                        retrig: Bool = false) {
        guard let d = sound, t >= 0, t < d.trackCount else { return }
        let h: UInt64 = hash != 0 ? hash : d.sound[t]
        let se = synthEngine(h)
        if se >= 0 {
            synth?.trigger(d, track: t, engine: se, at: frame, notes: notes, count: count, mask: mask, vals: vals,
                           gate: gate, own: isOwn, liveId: live, retrig: retrig)
            return
        }
        let e = d.entry(t, h)
        if e < 0 { return }
        let frames = d.eFrames[e]
        let start0: Double = Double(frames) * pv(d, t, VoiceParam.start, mask, vals) / 100
        let end0: Double = Double(frames) * pv(d, t, VoiceParam.end, mask, vals) / 100
        let sc = Int(d.eSliceCount[e])
        let minLen: Double = 0.003 * sr
        if sc == 0 && end0 - start0 < minLen { return }
        let attack: Double = pv(d, t, VoiceParam.attack, mask, vals) / 1000
        let decay: Double = pv(d, t, VoiceParam.decay, mask, vals) / 1000
        if !retrig { legatoCut(t, notes, count, frame, attack) }
        for k in 0..<count {
            let n = Int(notes[k])
            var a = start0
            var b = end0
            var ratio: Double = pow(2, Double(n - Params.sampleRoot) / 12)
            if sc > 0 {
                let s0 = Int(d.eSliceStart[e])
                var idx = -1
                for j in 0..<sc where Int(d.sliceNote[s0 + j]) == n {
                    idx = j
                    break
                }
                if idx < 0 { continue }
                a = d.sliceAt[s0 + idx] * Double(frames)
                b = (idx + 1 < sc ? d.sliceAt[s0 + idx + 1] : 1) * Double(frames)
                if b - a < minLen { continue }
                ratio = 1
            }
            let v = allocate(frame)
            setupVoice(v, d, t, e, frame, a, b, ratio, n, attack, decay, gate, mask, vals)
            own[v] = isOwn ? 1 : 0
            liveId[v] = live
            _ = out.push(.start(voice: v, track: t, hash: h, frame: frame, a: a / Double(frames), b: b / Double(frames),
                                rate: rate[v], frames: frames))
        }
    }

    private func setupVoice(_ v: Int, _ d: SoundData, _ t: Int, _ e: Int, _ frame: Int64, _ a: Double, _ b: Double,
                            _ ratio: Double, _ n: Int, _ attack: Double, _ decay: Double, _ gate: Int64,
                            _ mask: UInt16, _ vals: UnsafePointer<Float>?) {
        active[v] = 1
        fading[v] = 0
        track[v] = t
        trackId[v] = d.trackId[t]
        note[v] = n
        srcL[v] = d.eLeft[e]
        srcR[v] = d.eRight[e]
        srcFrames[v] = d.eFrames[e]
        stereo[v] = d.eChannels[e] == 2 ? 1 : 0
        start[v] = frame
        pos[v] = a
        endPos[v] = b
        noteRatio[v] = ratio
        lockMask[v] = mask
        for p in 0..<VoiceParam.count {
            lockVal[v * VoiceParam.count + p] = vals.map { $0[p] } ?? 0
        }
        let pitch: Double = pv(d, t, VoiceParam.pitch, mask, vals)
        rate[v] = ratio * pow(2, pitch / 12)
        // Край сэмпла (End или конец файла) гаснет за 4 мс (не больше четверти звучания).
        let playDur: Double = (b - a) / rate[v]
        edge[v] = Swift.max(1, Swift.min(0.004 * sr, playDur / 4))
        let att: Double = Swift.max(0.001, attack) * sr
        attackF[v] = att
        decaySec[v] = decay
        decayK[v] = Float(exp(-1 / (Swift.max(0.005, decay / 4) * sr)))
        if gate == Int64.max {
            holdEnd[v] = Int64.max
            stopAt[v] = Int64.max
        } else {
            let hold: Double = gate < 0 ? att : Swift.max(att, Double(gate))
            holdEnd[v] = frame + Int64(hold.rounded())
            stopAt[v] = holdEnd[v] + Int64(((Swift.max(0.02, decay)) * 2 + 0.05) * sr)
        }
        released[v] = 0
        env[v] = 0
        fadeAt[v] = Int64.max
        fadeG[v] = 1
        fadeK[v] = 1
        level[v] = Float(pow(pv(d, t, VoiceParam.level, mask, vals) / 127, 1.5))
        pan[v] = Float(Swift.max(-1, Swift.min(1, pv(d, t, VoiceParam.pan, mask, vals) / 64)))
        let f = Biquad.knob(pv(d, t, VoiceParam.filter, mask, vals), reso: pv(d, t, VoiceParam.reso, mask, vals))
        ftype[v] = f.type
        hz[v] = f.hz
        qDb[v] = f.q
        coef[v].set(type: f.type, hz: f.hz, qDb: f.q, sampleRate: sr)
        for k in 0..<4 { z[v * 4 + k] = 0 }
    }

    /// Свободная ячейка; больше maxVoices звучащих — самый старый гаснет за ~5 мс.
    private func allocate(_ frame: Int64) -> Int {
        var free = -1
        var live = 0
        var oldest = -1
        var oldestAny = -1
        for v in 0..<Sampler.slots {
            if active[v] == 0 {
                if free < 0 { free = v }
                continue
            }
            if oldestAny < 0 || serial[v] < serial[oldestAny] { oldestAny = v }
            if fading[v] != 0 { continue }
            live += 1
            if oldest < 0 || serial[v] < serial[oldest] { oldest = v }
        }
        if live >= Sampler.maxVoices && oldest >= 0 {
            fade(oldest, at: frame, tau: 0.0015)
            stopAt[oldest] = Swift.min(stopAt[oldest], frame + Int64(0.02 * sr))
        }
        if free < 0 {
            // Все ячейки заняты гаснущими — самая старая освобождается сразу.
            free = Swift.max(0, oldestAny)
            finish(free)
        }
        nextSerial += 1
        serial[free] = nextSerial
        return free
    }

    /// Быстро погасить голос с кадра at (постоянная tau, с).
    private func fade(_ v: Int, at: Int64, tau: Double) {
        if fading[v] != 0 && fadeAt[v] <= at { return }
        fading[v] = 1
        fadeAt[v] = at
        fadeK[v] = Float(exp(-1 / (tau * sr)))
        stopAt[v] = Swift.min(stopAt[v], at + Int64((tau * 8 + 0.005) * sr))
    }

    private func finish(_ v: Int) {
        if active[v] == 0 { return }
        active[v] = 0
        _ = out.push(.end(voice: v))
    }

    /// Нота той же высоты продолжает державшуюся: прежняя гаснет вместе с атакой новой (без провала и удвоения).
    private func legatoCut(_ t: Int, _ notes: UnsafePointer<Int16>, _ count: Int, _ at: Int64, _ attack: Double) {
        let tol = Int64(0.005 * sr)
        for v in 0..<Sampler.slots where active[v] != 0 && fading[v] == 0 && track[v] == t && holdEnd[v] != Int64.max {
            var same = false
            for k in 0..<count where Int(notes[k]) == note[v] { same = true }
            if !same { continue }
            if start[v] < at && holdEnd[v] >= at - tol { fade(v, at: at, tau: Swift.max(0.0015, attack / 3)) }
        }
    }

    /// Отпустили клавишу: живые ноты (liveId) — Decay как Release с кадра at.
    public func release(track t: Int, liveId id: Int, at: Int64) {
        synth?.release(track: t, liveId: id, at: at)
        for v in 0..<Sampler.slots where active[v] != 0 && track[v] == t && liveId[v] == id && holdEnd[v] == Int64.max {
            holdEnd[v] = Swift.max(at, start[v])
            stopAt[v] = holdEnd[v] + Int64((Swift.max(0.02, decaySec[v]) * 2 + 0.05) * sr)
        }
    }

    /// Живая нота с пианоролла: держится до release; level — сила нажатия (1 — без p-lock).
    public func noteOn(track t: Int, note n: Int, liveId id: Int, velocity: Float, at: Int64) {
        guard let d = sound, t < d.trackCount else { return }
        one.pointee = Int16(n)
        var mask: UInt16 = 0
        if velocity < 1 {
            mask = UInt16(1) << UInt16(VoiceParam.level)
            scratch[VoiceParam.level] = d.param(t, VoiceParam.level) * velocity
        }
        trigger(track: t, at: at, notes: one, count: 1, mask: mask, vals: scratch, hash: 0, gate: Int64.max,
                own: false, liveId: id)
    }

    // MARK: — новый снимок звука

    /// Снимок звука сменился: перестановка дорожек и убранные сэмплы — голоса гаснут; сменился звук дорожки —
    /// держащиеся ноты сразу звучат новым звуком (прежний голос гаснет за ~3 мс, новый — на оставшееся удержание).
    public func adopt(_ d: SoundData, now: Int64) {
        let old = sound
        sound = d
        for v in 0..<Sampler.slots where active[v] != 0 {
            let t = track[v]
            if t >= d.trackCount || d.trackId[t] != trackId[v] {
                fade(v, at: now, tau: 0.0015)
                continue
            }
            if let l = srcL[v], !d.holds(l) { fade(v, at: now, tau: 0.0015) }
        }
        synth?.adopt(d, now: now)
        guard let o = old else { return }
        let n = Swift.min(d.trackCount, o.trackCount)
        let lastSynth = synth?.lastSerial ?? 0
        for t in 0..<n where d.trackId[t] == o.trackId[t] && d.sound[t] != o.sound[t] {
            retrigger(t, now)
            retriggerSynth(t, now, lastSynth)
        }
    }

    private func retrigger(_ t: Int, _ now: Int64) {
        let edgeTol = Int64(0.01 * sr)
        // Новые голоса (созданные в этом же цикле) не перезапускаются.
        let last = nextSerial
        for v in 0..<Sampler.slots where active[v] != 0 && fading[v] == 0 && track[v] == t && own[v] == 0 && serial[v] <= last {
            let at = Swift.max(now, start[v])
            if holdEnd[v] != Int64.max && holdEnd[v] <= at + edgeTol { continue }
            let gate: Int64 = holdEnd[v] == Int64.max ? Int64.max : holdEnd[v] - at
            fade(v, at: at, tau: 0.003)
            one.pointee = Int16(note[v])
            let base = v * VoiceParam.count
            for p in 0..<VoiceParam.count { scratch[p] = lockVal[base + p] }
            trigger(track: t, at: at, notes: one, count: 1, mask: lockMask[v], vals: scratch, hash: 0, gate: gate,
                    own: false, liveId: liveId[v], retrig: true)
        }
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
                used[t] = 1
            }
            renderVoice(v, d, blockStart, n)
        }
        synth?.render(d, blockStart: blockStart, frames: n, busL: busL, busR: busR, used: used, stride: Sampler.maxFrames)
        mix(d, n, left, right)
        renderPreview(n, left, right)
    }

    private func mix(_ d: SoundData, _ n: Int, _ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>) {
        // Гейт mute/solo — за ~5 мс (постоянная 1,5 мс), громкость — за ~10 мс.
        let gk = Float(1 - exp(-1 / (0.0015 * sr)))
        let vk = Float(1 - exp(-1 / (0.01 * sr)))
        for t in 0..<d.trackCount {
            let vt: Float = d.gain[t]
            let gt: Float = d.open[t] != 0 ? 1 : 0
            if volCur[t] < 0 { volCur[t] = vt }
            if gateCur[t] < 0 { gateCur[t] = gt }
            if used[t] == 0 {
                volCur[t] = vt
                gateCur[t] = gt
                continue
            }
            let bl = busL + t * Sampler.maxFrames
            let br = busR + t * Sampler.maxFrames
            var vol = volCur[t]
            var gate = gateCur[t]
            for i in 0..<n {
                vol += (vt - vol) * vk
                gate += (gt - gate) * gk
                let g = vol * gate
                left[i] += bl[i] * g
                right[i] += br[i] * g
            }
            volCur[t] = vol
            gateCur[t] = gate
        }
    }

    private func renderVoice(_ v: Int, _ d: SoundData, _ blockStart: Int64, _ n: Int) {
        guard let l = srcL[v], let r = srcR[v] else { finish(v); return }
        let t = track[v]
        let mask = lockMask[v]
        let base = v * VoiceParam.count
        // Ручки дорожки меняют звучащую ноту сразу; p-lock шага держит своё.
        @inline(__always) func val(_ p: Int) -> Double {
            if mask & (UInt16(1) << UInt16(p)) != 0 { return Double(lockVal[base + p]) }
            return Double(d.param(t, p))
        }
        let rateT: Double = noteRatio[v] * pow(2, val(VoiceParam.pitch) / 12)
        let levelT = Float(pow(val(VoiceParam.level) / 127, 1.5))
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
                if st {
                    if pn <= 0 {
                        busL[k] += a + b * gc
                        busR[k] += b * gs
                    } else {
                        busL[k] += a * gc
                        busR[k] += b + a * gs
                    }
                } else {
                    busL[k] += a * gc
                    busR[k] += a * gs
                }
                pos[v] += rt
            }
            // Денормалы в состоянии фильтра.
            for k in 0..<4 where abs(z[zb + k]) < 1e-20 { z[zb + k] = 0 }
            i += m
        }
    }
}
