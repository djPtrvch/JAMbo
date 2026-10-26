import Foundation

// Голоса синта: выбор слота, legato одной ноты, отпускание живых нот, новый снимок звука (перестановка дорожек, MIX), перезапуск держащихся нот
// новым звуком — вне звукового пути (SynthVoices.swift).

extension SynthVoices {
    /// Отпустили клавишу: живые ноты (liveId) — Decay как Release с кадра at.
    func release(track t: Int, liveId id: Int, at: Int64) {
        if t < 0 || t >= SynthVoices.tracks { return }
        let base = t * SynthVoices.perTrack
        for v in base..<(base + SynthVoices.perTrack) {
            if active[v] != 0 && liveId[v] == id && holdEnd[v] == Int64.max {
                holdEnd[v] = Swift.max(at, start[v])
                stopAt[v] = holdEnd[v] + Int64((Swift.max(0.02, decaySec[v]) * 2 + 0.05) * sr)
            }
            if pActive[v] != 0 && pLive[v] == id && pGate[v] == Int64.max {
                pGate[v] = at > pStart[v] ? at - pStart[v] : -1
            }
        }
    }

    // MARK: — новый снимок звука

    /// Перестановка или удаление дорожек — голоса гаснут (держащиеся ноты переставленной дорожки сэмплер уже завёл
    /// заново на новом месте); переход MIX (rebind) — голоса остаются на своём месте.
    func adopt(_ d: SoundData, now: Int64) {
        for v in 0..<SynthVoices.slots where active[v] != 0 || pActive[v] != 0 {
            let t = v / SynthVoices.perTrack
            if d.rebind && t < d.trackCount {
                trackId[v] = d.trackId[t]
                continue
            }
            if t >= d.trackCount || d.trackId[t] != trackId[v] {
                pActive[v] = 0
                fade(v, at: now, tau: 0.0015)
            }
        }
    }

    var lastSerial: Int { return nextSerial }

    /// Держащиеся ноты дорожки t (не свой звук шага, созданные до serial last) — для перезапуска новым звуком:
    /// голос гаснет за ~3 мс, body получает ноту, удержание, p-lock и liveId.
    func retrigger(_ t: Int, _ now: Int64, upTo last: Int,
                   _ body: (_ note: Int, _ at: Int64, _ gate: Int64, _ mask: VoiceMask, _ vals: UnsafePointer<Float>,
                            _ live: Int) -> Void) {
        if t < 0 || t >= SynthVoices.tracks { return }
        let edgeTol = Int64(0.01 * sr)
        let base = t * SynthVoices.perTrack
        for v in base..<(base + SynthVoices.perTrack)
        where active[v] != 0 && fading[v] == 0 && own[v] == 0 && serial[v] <= last {
            let at = Swift.max(now, start[v])
            if holdEnd[v] != Int64.max && holdEnd[v] <= at + edgeTol { continue }
            let gate: Int64 = holdEnd[v] == Int64.max ? Int64.max : holdEnd[v] - at
            fade(v, at: at, tau: 0.003)
            body(note[v], at, gate, lockMask[v], lockVal + v * VoiceParam.count, liveId[v])
        }
    }

    /// Слот дорожки по кругу: свободный — голос дозвучал (stopAt); иначе крадётся следующий (steal).
    func allocate(_ t: Int, _ at: Int64) -> (Int, Bool) {
        let base = t * SynthVoices.perTrack
        let pt = SynthVoices.perTrack
        for k in 0..<pt {
            let c = (next[t] + k) % pt
            let v = base + c
            if pActive[v] != 0 { continue }
            if active[v] == 0 || Swift.min(stopAt[v], busyUntil[v]) <= at {
                next[t] = (c + 1) % pt
                return (v, false)
            }
        }
        let c = next[t] % pt
        next[t] = (c + 1) % pt
        return (base + c, true)
    }

    /// Та же нота продолжает державшуюся: прежняя гаснет вместе с атакой новой (legatoCut веба).
    func legatoCut(_ t: Int, _ notes: UnsafePointer<Int16>, _ count: Int, _ at: Int64, _ attack: Double) {
        let tol = Int64(0.005 * sr)
        let base = t * SynthVoices.perTrack
        for v in base..<(base + SynthVoices.perTrack)
        where active[v] != 0 && fading[v] == 0 && holdEnd[v] != Int64.max {
            var same = false
            for k in 0..<count where Int(notes[k]) == note[v] { same = true }
            if !same { continue }
            if start[v] < at && holdEnd[v] >= at - tol { fade(v, at: at, tau: Swift.max(0.0015, attack / 3)) }
        }
    }
}
