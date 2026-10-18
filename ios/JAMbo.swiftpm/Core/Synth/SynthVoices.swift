import Foundation

// Голоса синта Plaits (в колбэке; как triggerSynth веба, plaits-worklet.js и jambo_voices.cc): 6 голосов на дорожку,
// слот — по кругу (свободный: голос дозвучал), иначе крадётся следующий — гаснет за ~5 мс (τ 1,5 мс), новая нота —
// через 8 мс. Plaits получает только триггер (первый кусок ноты), громкость — внешняя огибающая, как у сэмпла:
// Attack (не меньше 2 мс) → удержание → Decay как Release. Движок → Post (усиление, < 0 — лимитер) → ±1 →
// огибающая → Level → фильтр → Pan → шина дорожки (микшер — в Sampler). Куски по 24 отсчёта (BLOCK worklet).
// Затухающие сами (STRING, MODAL, KICK, SNARE, HI-HAT): Morph Plaits — √(Decay / 4000 мс), ручка 1.3 — микс
// OUT→AUX; огибающая только с атакой (без удержания и релиза), голос считается до тишины (не дольше 15 с), слот
// занят до атаки + 0,3 с + 4·Decay; с атакой ≤ 2,5 мс в свободном слоте огибающая не обнуляется — хвост прошлой
// ноты не обрывается скачком, ручки звука слота подстраиваются за ~1 мс.

public final class SynthVoices {
    public static let perTrack = 6
    static let tracks = SoundData.maxTracks
    static let slots = tracks * perTrack
    static let chunk = kMaxBlockSize
    /// Голос без звука дольше 4800 отсчётов (и с начала ноты прошло больше) замолкает (SILENCE worklet).
    static let silence = 4800
    static let accent: Float = 0.8
    /// Усиления OUT и AUX движков 0–15 (< 0 — лимитер с предусилением), как в jambo_voices.cc.
    public static let outGains: [Float] = [0.8, 0.7, 0.6, 0.7, 0.8, 0.6, 0.8, -0.7,
                                           -3.0, -1.0, -2.0, -1.0, -1.0, 0.8, 0.8, 0.8]
    public static let auxGains: [Float] = [0.8, 0.6, 0.6, 0.6, 0.8, 0.6, 0.8, 0.8,
                                           1.0, -1.0, 1.0, 0.8, 0.8, 0.8, 0.8, 0.8]

    let sr: Double
    let bank: SynthEngineBank
    // Таблицы для колбэка — указатели (Swift-массивы не читаем).
    static let engines = SynthEngines.count
    private let gains = UnsafeMutablePointer<Float>.allocate(capacity: engines)
    private let auxGainsP = UnsafeMutablePointer<Float>.allocate(capacity: engines)
    /// 1 — движок затухает сам (SynthEngine.decay).
    private let selfDecayE = UnsafeMutablePointer<UInt8>.allocate(capacity: engines)
    /// Точки harmonics по пункту (SPEECH: 3 точки), начиная с points[e * 4].
    private let points = UnsafeMutablePointer<Float>.allocate(capacity: engines * 4)
    private let pointCount = UnsafeMutablePointer<Int>.allocate(capacity: engines)

    // Голос (по слоту: дорожка = слот / perTrack).
    let active = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    let fading = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    let own = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    let released = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    let triggered = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    let trackId = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let note = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let liveId = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let serial = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    /// Движок ноты и движок, выбранный в слоте (−1 — ещё нет; смена — LoadUserData и Reset).
    let engine = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let slotEngine = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let start = UnsafeMutablePointer<Int64>.allocate(capacity: slots)
    let holdEnd = UnsafeMutablePointer<Int64>.allocate(capacity: slots)
    let stopAt = UnsafeMutablePointer<Int64>.allocate(capacity: slots)
    let fadeAt = UnsafeMutablePointer<Int64>.allocate(capacity: slots)
    let attackF = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let decaySec = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let decayK = UnsafeMutablePointer<Float>.allocate(capacity: slots)
    let env = UnsafeMutablePointer<Float>.allocate(capacity: slots)
    let fadeK = UnsafeMutablePointer<Float>.allocate(capacity: slots)
    let fadeG = UnsafeMutablePointer<Float>.allocate(capacity: slots)
    let level = UnsafeMutablePointer<Float>.allocate(capacity: slots)
    /// Посылы слота (Reverb, Delay, Drive; 0…1, сглаженные).
    let send = UnsafeMutablePointer<Float>.allocate(capacity: slots * 3)
    let pan = UnsafeMutablePointer<Float>.allocate(capacity: slots)
    let hz = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let qDb = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let ftype = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let coef = UnsafeMutablePointer<Biquad>.allocate(capacity: slots)
    let z = UnsafeMutablePointer<Float>.allocate(capacity: slots * 2)
    let limiter = UnsafeMutablePointer<StmLimiter>.allocate(capacity: slots)
    let auxLimiter = UnsafeMutablePointer<StmLimiter>.allocate(capacity: slots)
    /// Слот занят до (затухающие сами — атака + 0,3 с + 4·Decay; остальные — до stopAt).
    let busyUntil = UnsafeMutablePointer<Int64>.allocate(capacity: slots)
    /// Голос затухающего самого движка; keep — огибающая с 1 (без атаки), ручки звука — за ~1 мс.
    let selfDecay = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    let keep = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    /// Сглаженные Timbre, Morph (у затухающих самих — от Decay) и доля AUX: в вебе (и jambo_voices.cc) они
    /// приходят скачками — у MODAL с длинным Decay скачок добротности и микса OUT→AUX трещит.
    let smooth = UnsafeMutablePointer<Float>.allocate(capacity: slots * 3)
    let quiet = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let lockMask = UnsafeMutablePointer<UInt16>.allocate(capacity: slots)
    let lockVal = UnsafeMutablePointer<Float>.allocate(capacity: slots * VoiceParam.count)
    /// Шины посылов на блок (ставит render).
    var sendL: UnsafeMutablePointer<Float>?
    var sendR: UnsafeMutablePointer<Float>?
    var stride = 0
    /// Модуляция LFO/ENV (ставит AudioCore); modFrame — кадр ноты, которую сейчас запускают.
    var mod: ModEngine?
    var modFrame: Int64 = 0
    // Нота, ждущая украденный слот (стартует через 8 мс, когда прежняя погаснет).
    let pActive = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    let pStart = UnsafeMutablePointer<Int64>.allocate(capacity: slots)
    let pNote = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let pEngine = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let pGate = UnsafeMutablePointer<Int64>.allocate(capacity: slots)
    let pOwn = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    let pLive = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let pMask = UnsafeMutablePointer<UInt16>.allocate(capacity: slots)
    let pVal = UnsafeMutablePointer<Float>.allocate(capacity: slots * VoiceParam.count)
    /// Следующий слот дорожки (по кругу).
    let next = UnsafeMutablePointer<Int>.allocate(capacity: tracks)
    /// Дрейф ANALOG (общий на дорожку, как узел worklet) и начало текущего блока.
    let drift = UnsafeMutablePointer<JamboDrift>.allocate(capacity: tracks)
    private var blockStart: Int64 = 0
    private var nextSerial = 0

    private let outBuf = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
    private let auxBuf = UnsafeMutablePointer<Float>.allocate(capacity: chunk)

    /// Создаётся вне колбэка (≈ 100 голосов × 16 движков).
    public init(resources: PlaitsResources, sampleRate: Double) {
        sr = sampleRate
        bank = SynthEngineBank(resources, count: SynthVoices.slots, perTrack: SynthVoices.perTrack, sampleRate: sampleRate)
        drift.initialize(repeating: JamboDrift(), count: SynthVoices.tracks)
        let ne = SynthVoices.engines
        gains.initialize(repeating: 1, count: ne)
        auxGainsP.initialize(repeating: 1, count: ne)
        selfDecayE.initialize(repeating: 0, count: ne)
        points.initialize(repeating: 0, count: ne * 4)
        pointCount.initialize(repeating: 0, count: ne)
        for e in 0..<Swift.min(ne, SynthEngines.count) {
            // Усиления — только у Plaits (свои движки без Post).
            if e < SynthVoices.outGains.count {
                gains[e] = SynthVoices.outGains[e]
                auxGainsP[e] = SynthVoices.auxGains[e]
            }
            selfDecayE[e] = SynthEngines.all[e].decay ? 1 : 0
            let pts = SynthEngines.all[e].harmPoints
            pointCount[e] = Swift.min(4, pts.count)
            for k in 0..<pointCount[e] { points[e * 4 + k] = pts[k] }
        }
        let s = SynthVoices.slots
        for p in [active, fading, own, released, triggered, pActive, pOwn, selfDecay, keep] as [UnsafeMutablePointer<UInt8>] {
            p.initialize(repeating: 0, count: s)
        }
        for p in [trackId, note, serial, ftype, quiet, pNote] as [UnsafeMutablePointer<Int>] {
            p.initialize(repeating: 0, count: s)
        }
        for p in [liveId, engine, slotEngine, pEngine, pLive] as [UnsafeMutablePointer<Int>] {
            p.initialize(repeating: -1, count: s)
        }
        for p in [start, holdEnd, stopAt, pStart, pGate, busyUntil] as [UnsafeMutablePointer<Int64>] {
            p.initialize(repeating: 0, count: s)
        }
        fadeAt.initialize(repeating: Int64.max, count: s)
        for p in [attackF, decaySec, hz, qDb] as [UnsafeMutablePointer<Double>] { p.initialize(repeating: 0, count: s) }
        for p in [decayK, env, fadeK, fadeG, level, pan] as [UnsafeMutablePointer<Float>] { p.initialize(repeating: 0, count: s) }
        send.initialize(repeating: 0, count: s * 3)
        coef.initialize(repeating: Biquad(), count: s)
        z.initialize(repeating: 0, count: s * 2)
        limiter.initialize(repeating: StmLimiter(), count: s)
        auxLimiter.initialize(repeating: StmLimiter(), count: s)
        smooth.initialize(repeating: 0, count: s * 3)
        lockMask.initialize(repeating: 0, count: s)
        pMask.initialize(repeating: 0, count: s)
        lockVal.initialize(repeating: 0, count: s * VoiceParam.count)
        pVal.initialize(repeating: 0, count: s * VoiceParam.count)
        next.initialize(repeating: 0, count: SynthVoices.tracks)
        outBuf.initialize(repeating: 0, count: SynthVoices.chunk)
        auxBuf.initialize(repeating: 0, count: SynthVoices.chunk)
    }

    deinit {
        for p in [active, fading, own, released, triggered, pActive, pOwn, selfDecay, keep, selfDecayE]
            as [UnsafeMutablePointer<UInt8>] { p.deallocate() }
        for p in [trackId, note, serial, ftype, quiet, pNote, liveId, engine, slotEngine, pEngine, pLive, next, pointCount]
            as [UnsafeMutablePointer<Int>] { p.deallocate() }
        for p in [start, holdEnd, stopAt, pStart, pGate, fadeAt, busyUntil] as [UnsafeMutablePointer<Int64>] { p.deallocate() }
        for p in [attackF, decaySec, hz, qDb] as [UnsafeMutablePointer<Double>] { p.deallocate() }
        send.deallocate()
        for p in [decayK, env, fadeK, fadeG, level, pan, z, lockVal, pVal, outBuf, auxBuf, gains, auxGainsP, points, smooth]
            as [UnsafeMutablePointer<Float>] { p.deallocate() }
        coef.deallocate()
        drift.deallocate()
        limiter.deallocate()
        auxLimiter.deallocate()
        lockMask.deallocate()
        pMask.deallocate()
    }

    /// Сколько голосов звучит или ждёт старта (тесты, диагностика).
    public var activeCount: Int {
        var n = 0
        for v in 0..<SynthVoices.slots where active[v] != 0 || pActive[v] != 0 { n += 1 }
        return n
    }

    // MARK: — запуск

    @inline(__always)
    private func pv(_ d: SoundData, _ t: Int, _ p: Int, _ mask: UInt16, _ vals: UnsafePointer<Float>?) -> Double {
        var x: Double = Double(d.param(t, p))
        if mask & (UInt16(1) << UInt16(p)) != 0, let v = vals { x = Double(v[p]) }
        // LFO/ENV — сверху (ENV — на кадр ноты).
        if let m = mod, m.modulated(t) { x = m.value(t, p, x, modFrame) }
        return x
    }

    /// Ноты дорожки t движком e в кадре frame (gate — как у Sampler.trigger: −1 — нота в 1 шаг, Int64.max — живая).
    func trigger(_ d: SoundData, track t: Int, engine e: Int, at frame: Int64, notes: UnsafePointer<Int16>, count: Int,
                 mask: UInt16, vals: UnsafePointer<Float>?, gate: Int64, own isOwn: Bool, liveId live: Int, retrig: Bool) {
        if t < 0 || t >= SynthVoices.tracks { return }
        modFrame = frame
        // DRUM монофонична: удары дорожки — в первый голос дорожки, из аккорда — одна нота, без кражи
        // (хвост прошлого удара гаснет в самом движке за ~2 мс).
        if e == Jambo.drum {
            guard count > 0 else { return }
            let v = t * SynthVoices.perTrack
            pActive[v] = 0
            setup(v, d, t, e, frame, Int(notes[0]), gate, mask, vals, isOwn, live, steal: false)
            return
        }
        let attack: Double = pv(d, t, VoiceParam.attack, mask, vals) / 1000
        if !retrig { legatoCut(t, notes, count, frame, attack) }
        for k in 0..<count {
            let n = Int(notes[k])
            let (v, steal) = allocate(t, frame)
            if steal {
                fade(v, at: frame, tau: 0.0015)
                pActive[v] = 1
                pStart[v] = frame + Int64((0.008 * sr).rounded())
                pNote[v] = n
                pEngine[v] = e
                pGate[v] = gate
                pOwn[v] = isOwn ? 1 : 0
                pLive[v] = live
                pMask[v] = mask
                for p in 0..<VoiceParam.count { pVal[v * VoiceParam.count + p] = vals.map { $0[p] } ?? 0 }
                stopAt[v] = Swift.min(stopAt[v], pStart[v])
            } else {
                pActive[v] = 0
                setup(v, d, t, e, frame, n, gate, mask, vals, isOwn, live, steal: false)
            }
        }
    }

    /// Слот дорожки по кругу: свободный — голос дозвучал (stopAt); иначе крадётся следующий (steal).
    private func allocate(_ t: Int, _ at: Int64) -> (Int, Bool) {
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

    private func setup(_ v: Int, _ d: SoundData, _ t: Int, _ e: Int, _ frame: Int64, _ n: Int, _ gate: Int64,
                       _ mask: UInt16, _ vals: UnsafePointer<Float>?, _ isOwn: Bool, _ live: Int, steal: Bool) {
        if slotEngine[v] != e {
            bank.select(v, e)
            limiter[v].initialize()
            auxLimiter[v].initialize()
            slotEngine[v] = e
        }
        let decaying = selfDecayE[e] != 0
        // Хвост прошлой ноты слота (тот же голос Plaits) не обрывается: огибающая с 1, ручки — за ~1 мс.
        let wasActive = active[v] != 0
        let keepEnv = decaying && !steal && pv(d, t, VoiceParam.attack, mask, vals) <= 2.5
        // Голос молчал — у DRUM нет хвоста для стыка.
        if !wasActive && e >= SynthEngines.firstJambo { bank.jamboSilent(v) }
        nextSerial += 1
        serial[v] = nextSerial
        active[v] = 1
        fading[v] = 0
        own[v] = isOwn ? 1 : 0
        liveId[v] = live
        trackId[v] = d.trackId[t]
        note[v] = n
        engine[v] = e
        start[v] = frame
        triggered[v] = 0
        quiet[v] = 0
        lockMask[v] = mask
        for p in 0..<VoiceParam.count { lockVal[v * VoiceParam.count + p] = vals.map { $0[p] } ?? 0 }
        let attack: Double = pv(d, t, VoiceParam.attack, mask, vals) / 1000
        let decay: Double = pv(d, t, VoiceParam.decay, mask, vals) / 1000
        let att: Double = Swift.max(0.002, attack) * sr
        attackF[v] = att
        decaySec[v] = decay
        decayK[v] = Float(exp(-1 / (Swift.max(0.005, decay / 4) * sr)))
        selfDecay[v] = decaying ? 1 : 0
        keep[v] = keepEnv ? 1 : 0
        if decaying {
            // Удержания и релиза нет (физику движка не трогаем): голос — до тишины, не дольше 15 с.
            holdEnd[v] = frame + Int64(att.rounded())
            stopAt[v] = holdEnd[v] + Int64(15 * sr)
            busyUntil[v] = holdEnd[v] + Int64((0.3 + 4 * decay) * sr)
        } else if gate == Int64.max {
            busyUntil[v] = Int64.max
            holdEnd[v] = Int64.max
            stopAt[v] = Int64.max
        } else {
            busyUntil[v] = Int64.max
            let hold: Double = gate < 0 ? att : Swift.max(att, Double(gate))
            holdEnd[v] = frame + Int64(hold.rounded())
            stopAt[v] = holdEnd[v] + Int64((Swift.max(0.02, decay) * 2 + 0.05) * sr)
        }
        released[v] = 0
        env[v] = 0
        fadeAt[v] = Int64.max
        fadeG[v] = 1
        fadeK[v] = 1
        // keep на звучащем хвосте: Level, Pan и фильтр слота не прыгают — подстраиваются в renderChunk.
        if keepEnv && wasActive { return }
        level[v] = Float(pow(pv(d, t, VoiceParam.level, mask, vals) / 127, 1.5))
        pan[v] = Float(Swift.max(-1, Swift.min(1, pv(d, t, VoiceParam.pan, mask, vals) / 64)))
        for k in 0..<3 { send[v * 3 + k] = Float(pv(d, t, VoiceParam.reverb + k, mask, vals) / 100) }
        let f = Biquad.knob(pv(d, t, VoiceParam.filter, mask, vals), reso: pv(d, t, VoiceParam.reso, mask, vals))
        ftype[v] = f.type
        hz[v] = f.hz
        qDb[v] = f.q
        coef[v].set(type: f.type, hz: f.hz, qDb: f.q, sampleRate: sr)
        z[v * 2] = 0
        z[v * 2 + 1] = 0
    }

    /// Ждущая нота слота v становится голосом (прежняя погасла).
    private func activatePending(_ v: Int, _ d: SoundData) {
        pActive[v] = 0
        let t = v / SynthVoices.perTrack
        active[v] = 0
        if t >= d.trackCount { return }
        setup(v, d, t, pEngine[v], pStart[v], pNote[v], pGate[v], pMask[v], pVal + v * VoiceParam.count,
              pOwn[v] != 0, pLive[v], steal: true)
    }

    private func fade(_ v: Int, at: Int64, tau: Double) {
        if active[v] == 0 || (fading[v] != 0 && fadeAt[v] <= at) { return }
        fading[v] = 1
        fadeAt[v] = at
        fadeK[v] = Float(exp(-1 / (tau * sr)))
        stopAt[v] = Swift.min(stopAt[v], at + Int64((tau * 8 + 0.005) * sr))
    }

    /// Та же нота продолжает державшуюся: прежняя гаснет вместе с атакой новой (legatoCut веба).
    private func legatoCut(_ t: Int, _ notes: UnsafePointer<Int16>, _ count: Int, _ at: Int64, _ attack: Double) {
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

    /// Перестановка или удаление дорожек — голоса гаснут (как у сэмплера).
    func adopt(_ d: SoundData, now: Int64) {
        for v in 0..<SynthVoices.slots where active[v] != 0 || pActive[v] != 0 {
            let t = v / SynthVoices.perTrack
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
                   _ body: (_ note: Int, _ at: Int64, _ gate: Int64, _ mask: UInt16, _ vals: UnsafePointer<Float>,
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

    // MARK: — звук

    /// Голоса в шины дорожек (bus + t·stride); used[t] — шина уже очищена в этом блоке.
    /// sendL/sendR — шины посылов ((дорожка·3 + посыл)·stride; очищаются вместе с шиной дорожки).
    func render(_ d: SoundData, blockStart: Int64, frames n: Int, busL: UnsafeMutablePointer<Float>,
                busR: UnsafeMutablePointer<Float>, sendL: UnsafeMutablePointer<Float>, sendR: UnsafeMutablePointer<Float>,
                used: UnsafeMutablePointer<UInt8>, stride: Int) {
        self.sendL = sendL
        self.sendR = sendR
        self.stride = stride
        // Дрейф ANALOG — в начале блока (process() узла worklet), время дорожки — в конце.
        self.blockStart = blockStart
        var t = 0
        while t < SynthVoices.tracks {
            drift[t].begin(n, sr)
            t += 1
        }
        defer {
            var k = 0
            while k < SynthVoices.tracks {
                drift[k].end(n)
                k += 1
            }
        }
        for v in 0..<SynthVoices.slots where active[v] != 0 || pActive[v] != 0 {
            let t = v / SynthVoices.perTrack
            if t >= d.trackCount {
                active[v] = 0
                pActive[v] = 0
                continue
            }
            if used[t] == 0 {
                (busL + t * stride).update(repeating: 0, count: n)
                (busR + t * stride).update(repeating: 0, count: n)
                var k = 0
                while k < 3 {
                    (sendL + (t * 3 + k) * stride).update(repeating: 0, count: n)
                    (sendR + (t * 3 + k) * stride).update(repeating: 0, count: n)
                    k += 1
                }
                used[t] = 1
            }
            renderSlot(v, d, t, blockStart, n, busL + t * stride, busR + t * stride)
        }
    }

    private func renderSlot(_ v: Int, _ d: SoundData, _ t: Int, _ blockStart: Int64, _ n: Int,
                            _ bl: UnsafeMutablePointer<Float>, _ br: UnsafeMutablePointer<Float>) {
        var i = 0
        while i < n {
            let frame0 = blockStart + Int64(i)
            if pActive[v] != 0 && pStart[v] <= frame0 { activatePending(v, d) }
            if active[v] == 0 {
                guard pActive[v] != 0 else { return }
                let s = Int(pStart[v] - blockStart)
                if s >= n { return }
                i = Swift.max(i + 1, s)
                continue
            }
            if start[v] > frame0 {
                let s = Int(start[v] - blockStart)
                if s >= n { return }
                i = s
                continue
            }
            var m = Swift.min(SynthVoices.chunk, n - i)
            if pActive[v] != 0 && pStart[v] < frame0 + Int64(m) { m = Int(pStart[v] - frame0) }
            if m <= 0 { continue }
            renderChunk(v, d, t, frame0, m, bl + i, br + i, i)
            i += m
        }
    }

    @inline(__always)
    private func renderChunk(_ v: Int, _ d: SoundData, _ t: Int, _ frame0: Int64, _ m: Int,
                             _ bl: UnsafeMutablePointer<Float>, _ br: UnsafeMutablePointer<Float>, _ off: Int) {
        let mask = lockMask[v]
        let base = v * VoiceParam.count
        // Ручки дорожки меняют звучащую ноту сразу; p-lock шага держит своё.
        let modE: ModEngine? = mod != nil && mod!.modulated(t) ? mod : nil
        @inline(__always) func val(_ p: Int) -> Double {
            var x: Double = Double(d.param(t, p))
            if mask & (UInt16(1) << UInt16(p)) != 0 { x = Double(lockVal[base + p]) }
            if let mm = modE { x = mm.value(t, p, x, frame0) }
            return x
        }
        let e = engine[v]
        let decaying = selfDecay[v] != 0
        var peak: Float = 0
        if e >= SynthEngines.firstJambo {
            // Свои движки (jambo-synth-worklet.js): p1–p3 — ручки 1.1–1.3 / 100, Decay — мс; сглаживание — в голосе
            // (5 мс), без Post и ±1 (как выход узла worklet).
            let q1 = val(VoiceParam.harm) / 100, q2 = val(VoiceParam.timbre) / 100, q3 = val(VoiceParam.morph) / 100
            let dec = val(VoiceParam.decay)
            let nt = Double(note[v])
            let dr = drift[t]
            if triggered[v] == 0 {
                bank.jamboTrigger(v, e, note: nt, q1, q2, q3, decay: dec, now: Double(Int(frame0)),
                                  tau: dr.tau + Double(Int(frame0 - blockStart)) * dr.ratio)
                triggered[v] = 1
            } else {
                bank.jamboSet(v, note: nt, q1, q2, q3, decay: dec)
            }
            bank.jamboRender(v, outBuf, m, driftRatio: dr.ratio, table: d.tableRef[t])
            var j = 0
            while j < m {
                let a = outBuf[j] < 0 ? -outBuf[j] : outBuf[j]
                if a > peak { peak = a }
                j += 1
            }
        } else {
            // Ручки → Plaits (synthParams веба): harmonics 0…1 (SPEECH — точка пункта), timbre, morph; accent 0,8.
            var p = EngineParameters()
            let h = Float(val(VoiceParam.harm) / 100)
            let pc = pointCount[e]
            p.harmonics = pc > 0 ? points[e * 4 + Params.stepIndex(Double(h), pc)] : h
            let timbreT = Float(val(VoiceParam.timbre) / 100)
            // Затухающие сами: Morph Plaits — от Decay (decayNorm веба), ручка 1.3 — доля AUX.
            var morphT: Float
            var auxT: Float = 0
            if decaying {
                morphT = Float(Swift.min(1, Swift.max(0, val(VoiceParam.decay) / 4000)).squareRoot())
                auxT = Float(Swift.min(1, Swift.max(0, val(VoiceParam.morph) / 100)))
            } else {
                morphT = Float(val(VoiceParam.morph) / 100)
            }
            // Сглаживание 10 мс (как у Level и Pan); в начале ноты — сразу значения ноты. Harmonics не сглаживается:
            // у ступенчатой (WAVETABLE, CHORDS, SPEECH) проскакивали бы соседние пункты.
            let sb = v * 3
            let aux0: Float
            if triggered[v] == 0 {
                smooth[sb] = timbreT
                smooth[sb + 1] = morphT
                smooth[sb + 2] = auxT
                aux0 = auxT
            } else {
                let k = Float(1 - exp(-Double(m) / (0.01 * sr)))
                aux0 = smooth[sb + 2]
                smooth[sb] += (timbreT - smooth[sb]) * k
                smooth[sb + 1] += (morphT - smooth[sb + 1]) * k
                smooth[sb + 2] += (auxT - smooth[sb + 2]) * k
            }
            p.timbre = smooth[sb]
            p.morph = smooth[sb + 1]
            let aux1 = smooth[sb + 2]
            p.note = Float(note[v])
            p.accent = SynthVoices.accent
            p.trigger = triggered[v] == 0 ? (triggerRisingEdge | triggerHigh) : triggerLow
            triggered[v] = 1
            bank.render(v, e, p, outBuf, auxBuf, m)
            // Post (jambo_voices.cc): усиление, < 0 — лимитер; микс OUT и AUX (aux_mix); ±1.
            var gain = gains[e]
            if gain < 0 {
                limiter[v].process(-gain, outBuf, m)
                gain = 1
            }
            var auxGain = auxGainsP[e]
            if auxGain < 0 {
                auxLimiter[v].process(-auxGain, auxBuf, m)
                auxGain = 1
            }
                for j in 0..<m {
                // Доля AUX — линейно внутри куска (без ступенек).
                let auxMix = aux0 + (aux1 - aux0) * Float(j + 1) / Float(m)
                let mixed = outBuf[j] * gain * (1 - auxMix) + auxBuf[j] * auxGain * auxMix
                let x = Swift.min(1, Swift.max(-1, mixed))
                outBuf[j] = x
                peak = Swift.max(peak, abs(x))
            }
        }
        quiet[v] = peak < 1e-5 ? quiet[v] + m : 0
        if quiet[v] > SynthVoices.silence && frame0 - start[v] > Int64(SynthVoices.silence) {
            active[v] = 0
            return
        }
        // Сглаживание ручек (setTargetAtTime веба: 10 мс, фильтр — 15 мс).
        let levelT = Float(pow(val(VoiceParam.level) / 127, 1.5))
        let panT = Float(Swift.max(-1, Swift.min(1, val(VoiceParam.pan) / 64)))
        let fk = Biquad.knob(val(VoiceParam.filter), reso: val(VoiceParam.reso))
        if fk.type != ftype[v] {
            ftype[v] = fk.type
            hz[v] = fk.hz
        }
        // keep: ручки слота на звучащем хвосте подстраиваются за ~1 мс (первые 10 мс ноты).
        let fast = keep[v] != 0 && frame0 - start[v] < Int64(0.01 * sr)
        let ks: Double = 1 - exp(-Double(m) / ((fast ? 0.001 : 0.01) * sr))
        let kf: Double = 1 - exp(-Double(m) / ((fast ? 0.001 : 0.015) * sr))
        level[v] += (levelT - level[v]) * Float(ks)
        pan[v] += (panT - pan[v]) * Float(ks)
        let sb = v * 3
        send[sb] += (Float(val(VoiceParam.reverb) / 100) - send[sb]) * Float(ks)
        send[sb + 1] += (Float(val(VoiceParam.delay) / 100) - send[sb + 1]) * Float(ks)
        send[sb + 2] += (Float(val(VoiceParam.drive) / 100) - send[sb + 2]) * Float(ks)
        let sg0 = send[sb], sg1 = send[sb + 1], sg2 = send[sb + 2]
        let hasSend: Bool = sg0 > 1e-6 || sg1 > 1e-6 || sg2 > 1e-6
        let st = stride
        let s0L = sendL! + t * 3 * st + off, s0R = sendR! + t * 3 * st + off
        let h0 = hz[v]
        let q0 = qDb[v]
        hz[v] += (fk.hz - hz[v]) * kf
        qDb[v] += (fk.q - qDb[v]) * kf
        if abs(hz[v] - h0) > 1e-6 || abs(qDb[v] - q0) > 1e-6 {
            coef[v].set(type: ftype[v], hz: hz[v], qDb: qDb[v], sampleRate: sr)
        }
        let c = coef[v]
        // StereoPanner, моно: cos/sin.
        let x: Float = (pan[v] + 1) / 2
        let gc = cos(x * Float.pi / 2)
        let gs = sin(x * Float.pi / 2)
        let lv = level[v]
        let zb = v * 2
        // Состояние голоса — в локальных переменных на кусок, кадр и время от начала ноты — счётчиками:
        // в отладочной сборке (Playgrounds) преобразования Int64 → Double и обращения к указателям-свойствам
        // на каждом отсчёте заметно дороже самой арифметики.
        let stop = stopAt[v], hold = holdEnd[v], fadeFrom = fadeAt[v], att = attackF[v]
        let keepEnv = keep[v] != 0
        let dk = decayK[v], fadeKV = fadeK[v]
        var envV = env[v], fadeV = fadeG[v], rel = released[v] != 0
        var z0 = z[zb], z1 = z[zb + 1]
        let b0 = c.b0, b1 = c.b1, b2 = c.b2, a1 = c.a1, a2 = c.a2
        var frame = frame0
        var tt = Double(frame0 - start[v])
        var j = 0
        var stopped = false
        while j < m {
            if frame >= stop {
                stopped = true
                break
            }
            // Огибающая: атака линейно, удержание, затем Decay как Release (экспонента, τ = Decay/4).
            var g: Float
            if keepEnv {
                // Затухающий сам с короткой атакой: огибающая не обнуляется.
                g = 1
            } else if decaying {
                // Только атака, дальше 1 — затухает сам движок.
                g = tt < att ? Float(tt / att) : 1
            } else if frame >= hold {
                if !rel {
                    rel = true
                    envV = tt < att ? Float(tt / att) : 1
                }
                envV *= dk
                g = envV
            } else {
                g = tt < att ? Float(tt / att) : 1
                envV = g
            }
            if frame >= fadeFrom { fadeV *= fadeKV }
            g *= lv * fadeV
            let a: Float = outBuf[j] * g
            // Фильтр (TDF II).
            let y: Float = b0 * a + z0
            z0 = b1 * a - a1 * y + z1
            z1 = b2 * a - a2 * y
            let oa: Float = y * gc
            let ob: Float = y * gs
            bl[j] += oa
            br[j] += ob
            // Посылы слота — после Pan.
            if hasSend {
                s0L[j] += oa * sg0
                s0R[j] += ob * sg0
                s0L[st + j] += oa * sg1
                s0R[st + j] += ob * sg1
                s0L[2 * st + j] += oa * sg2
                s0R[2 * st + j] += ob * sg2
            }
            frame += 1
            tt += 1
            j += 1
        }
        env[v] = envV
        fadeG[v] = fadeV
        released[v] = rel ? 1 : 0
        z[zb] = z0
        z[zb + 1] = z1
        if stopped {
            active[v] = 0
            return
        }
        // Денормалы в состоянии фильтра.
        for k in 0..<2 where abs(z[zb + k]) < 1e-20 { z[zb + k] = 0 }
    }
}
