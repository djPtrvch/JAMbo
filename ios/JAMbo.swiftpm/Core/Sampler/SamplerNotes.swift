import Foundation

// Запуск и остановка голосов сэмплера (из Sampler.swift — по размеру файла): ноты дорожки, живые ноты,
// новый снимок звука. Всё — в колбэке, без выделений памяти.

extension Sampler {
    // MARK: — запуск

    /// Значение параметра p голоса: p-lock (mask, vals) или ручка дорожки t.
    @inline(__always)
    func pv(_ d: SoundData, _ t: Int, _ p: Int, _ mask: VoiceMask, _ vals: UnsafePointer<Float>?) -> Double {
        var x: Double = Double(d.param(t, p))
        if mask & (VoiceMask(1) << VoiceMask(p)) != 0, let v = vals { x = Double(v[p]) }
        // LFO/ENV — сверху (ENV — на кадр ноты).
        if let m = mod, m.modulated(t) { x = m.value(t, p, x, modFrame) }
        return x
    }

    /// Ноты дорожки t в кадре frame. hash — свой звук шага (0 — звук дорожки); gate — удержание в кадрах
    /// (−1 — нота в 1 шаг: Decay сразу после атаки; Int64.max — живая нота до release).
    public func trigger(track t: Int, at frame: Int64, notes: UnsafePointer<Int16>, count: Int, mask: VoiceMask,
                        vals: UnsafePointer<Float>?, hash: UInt64, gate: Int64, own isOwn: Bool, liveId live: Int,
                        retrig: Bool = false) {
        guard let d = sound, t >= 0, t < d.trackCount else { return }
        modFrame = frame
        // Sidechain: каждая нота источника (не перезапуск звука на держащейся ноте).
        if !retrig { fx?.noteTrig(track: t, at: frame) }
        let h: UInt64 = hash != 0 ? hash : d.sound[d.s(t)]
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
            // Полоса воспроизведения: реверс — от конца отрезка к началу.
            let fa: Double = a / Double(frames), fb: Double = b / Double(frames)
            let rev: Bool = rate[v] < 0
            _ = out.push(.start(voice: v, track: t, hash: h, frame: frame, a: rev ? fb : fa, b: rev ? fa : fb,
                                rate: rate[v], frames: frames))
        }
    }

    func setupVoice(_ v: Int, _ d: SoundData, _ t: Int, _ e: Int, _ frame: Int64, _ a: Double, _ b: Double,
                            _ ratio: Double, _ n: Int, _ attack: Double, _ decay: Double, _ gate: Int64,
                            _ mask: VoiceMask, _ vals: UnsafePointer<Float>?) {
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
        beginPos[v] = a
        endPos[v] = b
        noteRatio[v] = ratio
        lockMask[v] = mask
        for p in 0..<VoiceParam.count {
            lockVal[v * VoiceParam.count + p] = vals.map { $0[p] } ?? 0
        }
        let pitch: Double = pv(d, t, VoiceParam.pitch, mask, vals)
        let pitchR: Double = ratio * pow(2, pitch / 12)
        let rateK: Double = pv(d, t, VoiceParam.rate, mask, vals) / 100
        // RATE (Sampler.renderVoice): PTCH — скорость и высота вместе; TSTR — скорость времени по темпу проекта.
        let ts: Bool = d.rateMode[d.s(t)] != 0
        tstr[v] = ts ? 1 : 0
        srcBpm[v] = ts ? d.eBpm[e] : 0
        grainRatio[v] = pitchR
        let tempoK: Double = srcBpm[v] > 0 ? bpm / srcBpm[v] : 1
        rate[v] = ts ? tempoK * rateK : pitchR * rateK
        // Реверс — от конца отрезка.
        pos[v] = rate[v] < 0 ? b - 1 : a
        if ts { stretch.start(v, dir: rate[v]) }
        // Край сэмпла (End или конец файла) гаснет за 4 мс (не больше четверти звучания).
        let playDur: Double = (b - a) / Swift.max(1e-3, Swift.abs(rate[v]))
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
        for k in 0..<3 { send[v * 3 + k] = Float(pv(d, t, VoiceParam.reverb + k, mask, vals) / 100) }
        let f = Biquad.knob(pv(d, t, VoiceParam.filter, mask, vals), reso: pv(d, t, VoiceParam.reso, mask, vals))
        ftype[v] = f.type
        hz[v] = f.hz
        qDb[v] = f.q
        coef[v].set(type: f.type, hz: f.hz, qDb: f.q, sampleRate: sr)
        for k in 0..<4 { z[v * 4 + k] = 0 }
    }

    /// Свободная ячейка; больше maxVoices звучащих — самый старый гаснет за ~5 мс.
    func allocate(_ frame: Int64) -> Int {
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
    func fade(_ v: Int, at: Int64, tau: Double) {
        if fading[v] != 0 && fadeAt[v] <= at { return }
        fading[v] = 1
        fadeAt[v] = at
        fadeK[v] = Float(exp(-1 / (tau * sr)))
        stopAt[v] = Swift.min(stopAt[v], at + Int64((tau * 8 + 0.005) * sr))
    }

    func finish(_ v: Int) {
        if active[v] == 0 { return }
        active[v] = 0
        _ = out.push(.end(voice: v))
    }

    /// Нота той же высоты продолжает державшуюся: прежняя гаснет вместе с атакой новой (без провала и удвоения).
    func legatoCut(_ t: Int, _ notes: UnsafePointer<Int16>, _ count: Int, _ at: Int64, _ attack: Double) {
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
        midiRelease(liveId: id, at: at)
        synth?.release(track: t, liveId: id, at: at)
        for v in 0..<Sampler.slots where active[v] != 0 && track[v] == t && liveId[v] == id && holdEnd[v] == Int64.max {
            holdEnd[v] = Swift.max(at, start[v])
            stopAt[v] = holdEnd[v] + Int64((Swift.max(0.02, decaySec[v]) * 2 + 0.05) * sr)
        }
    }

    /// Живая нота с клавиатуры (и NOTE PREVIEW пианоролла): держится до release; level — сила нажатия (1 — без p-lock).
    public func noteOn(track t: Int, note n: Int, liveId id: Int, velocity: Float, at: Int64) {
        guard let d = sound, t < d.trackCount else { return }
        one.pointee = Int16(n)
        var mask: VoiceMask = 0
        if velocity < 1 {
            mask = VoiceMask(1) << VoiceMask(VoiceParam.level)
            scratch[VoiceParam.level] = d.param(t, VoiceParam.level) * velocity
        }
        if sendsMidi(t) {
            sidechainTrig(track: t, at: at)
            midiNotes(track: t, at: at, notes: one, count: 1, mask: mask, vals: scratch, length: -1, liveId: id)
            return
        }
        trigger(track: t, at: at, notes: one, count: 1, mask: mask, vals: scratch, hash: 0, gate: Int64.max,
                own: false, liveId: id)
    }

    // MARK: — новый снимок звука

    /// Снимок звука сменился: перестановка дорожек — голоса переезжают с дорожкой (сэмплы — без перерыва, синт —
    /// держащиеся ноты заново на новом месте), удалённая дорожка и убранные сэмплы — голоса гаснут; переход MIX
    /// (rebind) — голоса остаются на своём месте; сменился звук дорожки — держащиеся ноты сразу звучат новым звуком
    /// (прежний голос гаснет за ~3 мс, новый — на оставшееся удержание).
    public func adopt(_ d: SoundData, now: Int64) {
        let old = sound
        sound = d
        for v in 0..<Sampler.slots where active[v] != 0 {
            let t = track[v]
            if d.rebind && t < d.trackCount {
                trackId[v] = d.trackId[t]
            } else if t >= d.trackCount || d.trackId[t] != trackId[v] {
                let t2: Int = Sampler.index(of: trackId[v], in: d)
                if t2 < 0 {
                    fade(v, at: now, tau: 0.0015)
                    continue
                }
                track[v] = t2
            }
            if let l = srcL[v], !d.holds(l) { fade(v, at: now, tau: 0.0015) }
        }
        if let o = old, !d.rebind { moveSynthNotes(o, d, now) }
        // Предпрослушка ▶ держит указатели прошлого снимка: сэмпла в новом нет — гаснет (~40 мс, прошлый снимок
        // живёт ещё 0,5 с), иначе после выгрузки сэмпла колбэк читал бы освобождённую память.
        if let l = pvL, !d.holds(l) { pvStop = true }
        synth?.adopt(d, now: now)
        guard let o = old else { return }
        let n = Swift.min(d.trackCount, o.trackCount)
        let lastSynth = synth?.lastSerial ?? 0
        for t in 0..<n where d.trackId[t] == o.trackId[t] && d.sound[d.s(t)] != o.sound[o.s(t)] {
            retrigger(t, now)
            retriggerSynth(t, now, lastSynth)
        }
    }

    /// Место дорожки с id в снимке (−1 — нет).
    static func index(of id: Int, in d: SoundData) -> Int {
        var t: Int = 0
        while t < d.trackCount {
            if d.trackId[t] == id { return t }
            t += 1
        }
        return -1
    }

    /// Перестановка: держащиеся ноты синта дорожки, которая сменила место, — заново на новом месте (голоса синта
    /// привязаны к месту дорожки).
    func moveSynthNotes(_ o: SoundData, _ d: SoundData, _ now: Int64) {
        guard let s = synth else { return }
        let last: Int = s.lastSerial
        var t: Int = 0
        while t < o.trackCount {
            let id: Int = o.trackId[t]
            let same: Bool = t < d.trackCount && d.trackId[t] == id
            let t2: Int = same ? t : Sampler.index(of: id, in: d)
            if !same && t2 >= 0 {
                s.retrigger(t, now, upTo: last) { n, at, gate, mask, vals, live in
                    one.pointee = Int16(n)
                    for p in 0..<VoiceParam.count { scratch[p] = vals[p] }
                    trigger(track: t2, at: at, notes: one, count: 1, mask: mask, vals: scratch, hash: 0, gate: gate,
                            own: false, liveId: live, retrig: true)
                }
            }
            t += 1
        }
    }

    func retrigger(_ t: Int, _ now: Int64) {
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
}
