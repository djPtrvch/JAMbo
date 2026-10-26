import Foundation

// Голоса синта (в колбэке; как triggerSynth веба и jambo-synth-worklet.js): 6 голосов на дорожку, слот — по кругу
// (свободный: голос дозвучал), иначе крадётся следующий — гаснет за ~5 мс (τ 1,5 мс), новая нота — через 8 мс.
// Громкость — внешняя огибающая, как у сэмпла: Attack (не меньше 2 мс) → удержание → Decay как Release.
// Движок → огибающая → Level → фильтр → Pan → шина дорожки (микшер — в Sampler). Куски по 24 отсчёта (BLOCK worklet).
// Стерео-движки (TEXTURE, GRANULAR): фильтр голоса — по двум каналам с общими коэффициентами, Pan — баланс (StereoPanner веба
// со стерео-входом).
// Затухающие сами (KICK): огибающая только с атакой (без удержания и релиза), голос считается до тишины (не дольше
// 15 с), слот занят до атаки + 0,3 с + 4·Decay; с атакой ≤ 2,5 мс в свободном слоте огибающая не обнуляется — хвост
// прошлой ноты не обрывается скачком, ручки звука слота подстраиваются за ~1 мс.

public final class SynthVoices {
    public static let perTrack = 6
    static let tracks = SoundData.maxTracks
    static let slots = tracks * perTrack
    static let chunk = 24
    /// Голос без звука дольше 4800 отсчётов (и с начала ноты прошло больше) замолкает (SILENCE worklet).
    static let silence = 4800

    let sr: Double
    let bank: JamboBank
    // Таблицы для колбэка — указатели (Swift-массивы не читаем).
    static let engines = SynthEngines.count
    /// 1 — движок затухает сам (SynthEngine.decay).
    private let selfDecayE = UnsafeMutablePointer<UInt8>.allocate(capacity: engines)

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
    /// Движок ноты.
    let engine = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let start = UnsafeMutablePointer<Int64>.allocate(capacity: slots)
    let holdEnd = UnsafeMutablePointer<Int64>.allocate(capacity: slots)
    let stopAt = UnsafeMutablePointer<Int64>.allocate(capacity: slots)
    let fadeAt = UnsafeMutablePointer<Int64>.allocate(capacity: slots)
    let attackF = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let decaySec = UnsafeMutablePointer<Double>.allocate(capacity: slots)
    let decayK = UnsafeMutablePointer<Float>.allocate(capacity: slots)
    let env = UnsafeMutablePointer<Float>.allocate(capacity: slots)
    /// Уровень, с которого идёт атака (SUB: новая нота на звучащей — с текущего уровня огибающей, без провала).
    let env0 = UnsafeMutablePointer<Float>.allocate(capacity: slots)
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
    /// Состояние фильтра правого канала стерео-движка.
    let zR = UnsafeMutablePointer<Float>.allocate(capacity: slots * 2)
    /// Слот занят до (затухающие сами — атака + 0,3 с + 4·Decay; остальные — до stopAt).
    let busyUntil = UnsafeMutablePointer<Int64>.allocate(capacity: slots)
    /// Голос затухающего самого движка; keep — огибающая с 1 (без атаки), ручки звука — за ~1 мс.
    let selfDecay = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    let keep = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    let quiet = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let lockMask = UnsafeMutablePointer<VoiceMask>.allocate(capacity: slots)
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
    /// Ждущая нота монофоничного движка: прежняя звучит до её кадра и не гасится (стык — в самом движке).
    let pKeep = UnsafeMutablePointer<UInt8>.allocate(capacity: slots)
    let pLive = UnsafeMutablePointer<Int>.allocate(capacity: slots)
    let pMask = UnsafeMutablePointer<VoiceMask>.allocate(capacity: slots)
    let pVal = UnsafeMutablePointer<Float>.allocate(capacity: slots * VoiceParam.count)
    /// Следующий слот дорожки (по кругу).
    let next = UnsafeMutablePointer<Int>.allocate(capacity: tracks)
    /// Дрейф ANALOG (общий на дорожку, как узел worklet) и начало текущего блока.
    let drift = UnsafeMutablePointer<JamboDrift>.allocate(capacity: tracks)
    private var blockStart: Int64 = 0
    var nextSerial = 0

    private let outBuf = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
    private let outBufR = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
    /// Огибающая · Level · затухание кражи на кусок (0 после остановки голоса).
    let gBuf = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
    /// Бит p-lock параметра p (1 << p): в отладочной сборке VoiceMask(p) — обобщённое преобразование, вызов на каждый
    /// параметр каждого куска (S14b).
    private let bit = UnsafeMutablePointer<VoiceMask>.allocate(capacity: VoiceParam.count)

    /// Создаётся вне колбэка (≈ 100 голосов).
    public init(sampleRate: Double) {
        sr = sampleRate
        bank = JamboBank(count: SynthVoices.slots, sampleRate: sampleRate, perTrack: SynthVoices.perTrack)
        drift.initialize(repeating: JamboDrift(), count: SynthVoices.tracks)
        selfDecayE.initialize(repeating: 0, count: SynthVoices.engines)
        for e in SynthEngines.all { selfDecayE[e.id] = e.decay ? 1 : 0 }
        let s = SynthVoices.slots
        for p in [active, fading, own, released, triggered, pActive, pOwn, pKeep, selfDecay, keep] as [UnsafeMutablePointer<UInt8>] {
            p.initialize(repeating: 0, count: s)
        }
        for p in [trackId, note, serial, ftype, quiet, pNote] as [UnsafeMutablePointer<Int>] {
            p.initialize(repeating: 0, count: s)
        }
        for p in [liveId, engine, pEngine, pLive] as [UnsafeMutablePointer<Int>] {
            p.initialize(repeating: -1, count: s)
        }
        for p in [start, holdEnd, stopAt, pStart, pGate, busyUntil] as [UnsafeMutablePointer<Int64>] {
            p.initialize(repeating: 0, count: s)
        }
        fadeAt.initialize(repeating: Int64.max, count: s)
        for p in [attackF, decaySec, hz, qDb] as [UnsafeMutablePointer<Double>] { p.initialize(repeating: 0, count: s) }
        for p in [decayK, env, env0, fadeK, fadeG, level, pan] as [UnsafeMutablePointer<Float>] { p.initialize(repeating: 0, count: s) }
        send.initialize(repeating: 0, count: s * 3)
        coef.initialize(repeating: Biquad(), count: s)
        z.initialize(repeating: 0, count: s * 2)
        zR.initialize(repeating: 0, count: s * 2)
        lockMask.initialize(repeating: 0, count: s)
        pMask.initialize(repeating: 0, count: s)
        lockVal.initialize(repeating: 0, count: s * VoiceParam.count)
        pVal.initialize(repeating: 0, count: s * VoiceParam.count)
        next.initialize(repeating: 0, count: SynthVoices.tracks)
        outBuf.initialize(repeating: 0, count: SynthVoices.chunk)
        outBufR.initialize(repeating: 0, count: SynthVoices.chunk)
        gBuf.initialize(repeating: 0, count: SynthVoices.chunk)
        for p in 0..<VoiceParam.count { bit[p] = VoiceMask(1) << VoiceMask(p) }
    }

    deinit {
        for p in [active, fading, own, released, triggered, pActive, pOwn, pKeep, selfDecay, keep, selfDecayE]
            as [UnsafeMutablePointer<UInt8>] { p.deallocate() }
        for p in [trackId, note, serial, ftype, quiet, pNote, liveId, engine, pEngine, pLive, next]
            as [UnsafeMutablePointer<Int>] { p.deallocate() }
        for p in [start, holdEnd, stopAt, pStart, pGate, fadeAt, busyUntil] as [UnsafeMutablePointer<Int64>] { p.deallocate() }
        for p in [attackF, decaySec, hz, qDb] as [UnsafeMutablePointer<Double>] { p.deallocate() }
        send.deallocate()
        for p in [decayK, env, env0, fadeK, fadeG, level, pan, z, zR, lockVal, pVal, outBuf, outBufR, gBuf]
            as [UnsafeMutablePointer<Float>] { p.deallocate() }
        bit.deallocate()
        coef.deallocate()
        drift.deallocate()
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
    private func pv(_ d: SoundData, _ t: Int, _ p: Int, _ mask: VoiceMask, _ vals: UnsafePointer<Float>?) -> Double {
        var x: Double = Double(d.param(t, p))
        if mask & (VoiceMask(1) << VoiceMask(p)) != 0, let v = vals { x = Double(v[p]) }
        // LFO/ENV — сверху (ENV — на кадр ноты).
        if let m = mod, m.modulated(t) { x = m.value(t, p, x, modFrame) }
        return x
    }

    /// Ноты дорожки t движком e в кадре frame (gate — как у Sampler.trigger: −1 — нота в 1 шаг, Int64.max — живая).
    func trigger(_ d: SoundData, track t: Int, engine e: Int, at frame: Int64, notes: UnsafePointer<Int16>, count: Int,
                 mask: VoiceMask, vals: UnsafePointer<Float>?, gate: Int64, own isOwn: Bool, liveId live: Int, retrig: Bool) {
        if t < 0 || t >= SynthVoices.tracks { return }
        modFrame = frame
        // Ударные (KICK, SNARE, HAT, CLAP, PERC) и SUB монофоничны: ноты дорожки — в первый голос дорожки, из
        // аккорда — нижняя нота, без кражи (хвост прошлой гаснет в самом движке за ~2 мс).
        if Jambo.mono(e) {
            guard count > 0 else { return }
            let v = t * SynthVoices.perTrack
            var low = Int(notes[0])
            for k in 1..<Swift.max(1, count) where Int(notes[k]) < low { low = Int(notes[k]) }
            // Голос звучит: новая нота — в свой кадр (ноты секвенсора приходят заранее), прежняя играет до него;
            // иначе голос молчал бы от вызова до начала ноты — обрыв хвоста, щелчок.
            if active[v] != 0 && fading[v] == 0 {
                pActive[v] = 1
                pKeep[v] = 1
                pStart[v] = frame
                pNote[v] = low
                pEngine[v] = e
                pGate[v] = gate
                pOwn[v] = isOwn ? 1 : 0
                pLive[v] = live
                pMask[v] = mask
                for p in 0..<VoiceParam.count { pVal[v * VoiceParam.count + p] = vals.map { $0[p] } ?? 0 }
                return
            }
            pActive[v] = 0
            pKeep[v] = 0
            setup(v, d, t, e, frame, low, gate, mask, vals, isOwn, live, steal: false)
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

    private func setup(_ v: Int, _ d: SoundData, _ t: Int, _ e: Int, _ frame: Int64, _ n: Int, _ gate: Int64,
                       _ mask: VoiceMask, _ vals: UnsafePointer<Float>?, _ isOwn: Bool, _ live: Int, steal: Bool) {
        let decaying = selfDecayE[e] != 0
        // Хвост прошлой ноты слота (тот же голос) не обрывается: огибающая с 1, ручки — за ~1 мс.
        let wasActive = active[v] != 0
        // SUB: новая нота на звучащей — атака с текущего уровня огибающей.
        let legato: Bool = wasActive && !decaying && Jambo.mono(e) && fading[v] == 0
        let prevEnv: Float = legato ? env[v] * fadeG[v] : 0
        let keepEnv = decaying && !steal && pv(d, t, VoiceParam.attack, mask, vals) <= 2.5
        // Голос молчал — у KICK нет хвоста для стыка.
        if !wasActive { bank.jamboSilent(v) }
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
        env[v] = prevEnv
        env0[v] = prevEnv
        fadeAt[v] = Int64.max
        fadeG[v] = 1
        fadeK[v] = 1
        // keep на звучащем хвосте и SUB поверх звучащей ноты: Level, Pan и фильтр слота не прыгают — подстраиваются
        // в renderChunk.
        if (keepEnv || legato) && wasActive { return }
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
        zR[v * 2] = 0
        zR[v * 2 + 1] = 0
    }

    /// Ждущая нота слота v становится голосом (прежняя погасла).
    private func activatePending(_ v: Int, _ d: SoundData) {
        pActive[v] = 0
        let t = v / SynthVoices.perTrack
        // Монофоничный: прежняя нота звучит до этого кадра — продолжение (огибающая с текущего уровня, стык в движке).
        let keepOld: Bool = pKeep[v] != 0
        pKeep[v] = 0
        if !keepOld { active[v] = 0 }
        if t >= d.trackCount { return }
        setup(v, d, t, pEngine[v], pStart[v], pNote[v], pGate[v], pMask[v], pVal + v * VoiceParam.count,
              pOwn[v] != 0, pLive[v], steal: !keepOld)
    }

    func fade(_ v: Int, at: Int64, tau: Double) {
        if active[v] == 0 || (fading[v] != 0 && fadeAt[v] <= at) { return }
        fading[v] = 1
        fadeAt[v] = at
        fadeK[v] = Float(exp(-1 / (tau * sr)))
        stopAt[v] = Swift.min(stopAt[v], at + Int64((tau * 8 + 0.005) * sr))
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

    /// Ручка p голоса: p-lock голоса или ручка дорожки (row — строка параметров дорожки), сверху LFO/ENV. Метод без
    /// захвата (вложенная функция с захватом в отладочной сборке готовит контекст на каждый вызов — S14b).
    @inline(__always)
    private func knob(_ row: UnsafeMutablePointer<Float>, _ locks: UnsafeMutablePointer<Float>, _ mask: VoiceMask,
                      _ modE: ModEngine?, _ t: Int, _ frame: Int64, _ p: Int) -> Double {
        let x: Double = Double(mask & bit[p] != 0 ? locks[p] : row[p])
        guard let mm = modE else { return x }
        return mm.value(t, p, x, frame)
    }

    @inline(__always)
    private func renderChunk(_ v: Int, _ d: SoundData, _ t: Int, _ frame0: Int64, _ m: Int,
                             _ bl: UnsafeMutablePointer<Float>, _ br: UnsafeMutablePointer<Float>, _ off: Int) {
        let mask = lockMask[v]
        // Ручки дорожки меняют звучащую ноту сразу; p-lock шага держит своё. Строка параметров дорожки, p-lock голоса
        // и биты — указатели на кусок (без SoundData.param и преобразований на каждый параметр).
        let modE: ModEngine? = mod != nil && mod!.modulated(t) ? mod : nil
        let row: UnsafeMutablePointer<Float> = d.params + d.s(t) * VoiceParam.count
        let locks: UnsafeMutablePointer<Float> = lockVal + v * VoiceParam.count
        let e = engine[v]
        let decaying = selfDecay[v] != 0
        var peak: Float = 0
        // Свои движки (jambo-synth-worklet.js): p1–p4 — ручки 1.1–1.4 / 100, Decay — мс; сглаживание — в голосе (5 мс).
        let q1 = knob(row, locks, mask, modE, t, frame0, VoiceParam.harm) / 100, q2 = knob(row, locks, mask, modE, t, frame0, VoiceParam.timbre) / 100, q3 = knob(row, locks, mask, modE, t, frame0, VoiceParam.morph) / 100
        let q4 = knob(row, locks, mask, modE, t, frame0, VoiceParam.p4) / 100
        let dec = knob(row, locks, mask, modE, t, frame0, VoiceParam.decay)
        let nt = Double(note[v])
        let dr = drift[t]
        if triggered[v] == 0 {
            bank.jamboTrigger(v, e, note: nt, q1, q2, q3, q4, decay: dec, now: Double(Int(frame0)),
                              tau: dr.tau + Double(Int(frame0 - blockStart)) * dr.ratio)
            triggered[v] = 1
        } else {
            bank.jamboSet(v, note: nt, q1, q2, q3, q4, decay: dec)
        }
        let stereo: Bool = Jambo.stereo(e)
        if stereo {
            // Окно активности TEXTURE и GRANULAR: события и зёрна рождаются до attack + 1,7·Decay после отпускания
            // (держится — всегда).
            let hEnd = holdEnd[v]
            var win = Int.max
            if hEnd != Int64.max {
                let endF: Int64 = hEnd + Int64(1.7 * decaySec[v] * sr)
                win = endF > frame0 ? Int(endF - frame0) : 0
            }
            bank.stereoRender(v, outBuf, outBufR, m, window: win, src: d.grainRef[d.s(t)])
        } else {
            bank.jamboRender(v, outBuf, m, driftRatio: dr.ratio, table: d.tableRef[d.s(t)])
        }
        var q = 0
        while q < m {
            let a = outBuf[q] < 0 ? -outBuf[q] : outBuf[q]
            if a > peak { peak = a }
            if stereo {
                let b = outBufR[q] < 0 ? -outBufR[q] : outBufR[q]
                if b > peak { peak = b }
            }
            q += 1
        }
        quiet[v] = peak < 1e-5 ? quiet[v] + m : 0
        if quiet[v] > SynthVoices.silence && frame0 - start[v] > Int64(SynthVoices.silence) {
            active[v] = 0
            return
        }
        // Сглаживание ручек (setTargetAtTime веба: 10 мс, фильтр — 15 мс).
        let levelT = Float(pow(knob(row, locks, mask, modE, t, frame0, VoiceParam.level) / 127, 1.5))
        let panT = Float(Swift.max(-1, Swift.min(1, knob(row, locks, mask, modE, t, frame0, VoiceParam.pan) / 64)))
        let fk = Biquad.knob(knob(row, locks, mask, modE, t, frame0, VoiceParam.filter), reso: knob(row, locks, mask, modE, t, frame0, VoiceParam.reso))
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
        send[sb] += (Float(knob(row, locks, mask, modE, t, frame0, VoiceParam.reverb) / 100) - send[sb]) * Float(ks)
        send[sb + 1] += (Float(knob(row, locks, mask, modE, t, frame0, VoiceParam.delay) / 100) - send[sb + 1]) * Float(ks)
        send[sb + 2] += (Float(knob(row, locks, mask, modE, t, frame0, VoiceParam.drive) / 100) - send[sb + 2]) * Float(ks)
        let sg0 = send[sb], sg1 = send[sb + 1], sg2 = send[sb + 2]
        let hasSend: Bool = sg0 > 1e-6 || sg1 > 1e-6 || sg2 > 1e-6
        let st = stride
        let s0L = sendL! + t * 3 * st + off, s0R = sendR! + t * 3 * st + off
        let h0 = hz[v]
        let q0 = qDb[v]
        let cPrev = coef[v]
        hz[v] += (fk.hz - hz[v]) * kf
        qDb[v] += (fk.q - qDb[v]) * kf
        let dh: Double = hz[v] - h0, dq: Double = qDb[v] - q0
        if dh > 1e-6 || dh < -1e-6 || dq > 1e-6 || dq < -1e-6 {
            coef[v].set(type: ftype[v], hz: hz[v], qDb: qDb[v], sampleRate: sr)
        }
        let c = coef[v]
        let lv = level[v]
        let zb = v * 2
        // Огибающая — отдельным проходом в gBuf (с остановкой голоса), затем фильтр, Pan и посылы — моно или стерео.
        let stopped: Bool = envelope(v, frame0, m, lv)
        // Коэффициенты фильтра — плавно от прежних к новым внутри куска (иначе ступеньки раз в 24 отсчёта при ENV/LFO
        // на фильтре звучат призвуком ~2 кГц).
        var b0 = cPrev.b0, b1 = cPrev.b1, b2 = cPrev.b2, a1 = cPrev.a1, a2 = cPrev.a2
        let im: Float = 1 / Float(m)
        let db0 = (c.b0 - b0) * im, db1 = (c.b1 - b1) * im, db2 = (c.b2 - b2) * im
        let da1 = (c.a1 - a1) * im, da2 = (c.a2 - a2) * im
        let gb = gBuf
        let src = outBuf
        var z0 = z[zb], z1 = z[zb + 1]
        var j = 0
        if !stereo {
            // StereoPanner, моно: cos/sin.
            let x: Float = (pan[v] + 1) / 2
            let gc = cos(x * Float.pi / 2)
            let gs = sin(x * Float.pi / 2)
            while j < m {
                let a: Float = src[j] * gb[j]
                b0 += db0
                b1 += db1
                b2 += db2
                a1 += da1
                a2 += da2
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
                j += 1
            }
        } else {
            // StereoPanner, стерео-вход (баланс): pan ≤ 0 — правый канал частью уходит влево, pan > 0 — наоборот.
            let p: Float = pan[v]
            let x: Float = p <= 0 ? p + 1 : p
            let gc = cos(x * Float.pi / 2)
            let gs = sin(x * Float.pi / 2)
            let ll: Float = p <= 0 ? 1 : gc, rl: Float = p <= 0 ? gc : 0
            let rr: Float = p <= 0 ? gs : 1, lr: Float = p <= 0 ? 0 : gs
            let srcR = outBufR
            var w0 = zR[zb], w1 = zR[zb + 1]
            while j < m {
                let g: Float = gb[j]
                let a: Float = src[j] * g
                let aR: Float = srcR[j] * g
                b0 += db0
                b1 += db1
                b2 += db2
                a1 += da1
                a2 += da2
                let y: Float = b0 * a + z0
                z0 = b1 * a - a1 * y + z1
                z1 = b2 * a - a2 * y
                let yR: Float = b0 * aR + w0
                w0 = b1 * aR - a1 * yR + w1
                w1 = b2 * aR - a2 * yR
                let oa: Float = y * ll + yR * rl
                let ob: Float = yR * rr + y * lr
                bl[j] += oa
                br[j] += ob
                if hasSend {
                    s0L[j] += oa * sg0
                    s0R[j] += ob * sg0
                    s0L[st + j] += oa * sg1
                    s0R[st + j] += ob * sg1
                    s0L[2 * st + j] += oa * sg2
                    s0R[2 * st + j] += ob * sg2
                }
                j += 1
            }
            zR[zb] = (w0 < 1e-20 && w0 > -1e-20) ? 0 : w0
            zR[zb + 1] = (w1 < 1e-20 && w1 > -1e-20) ? 0 : w1
        }
        z[zb] = z0
        z[zb + 1] = z1
        if stopped {
            active[v] = 0
            return
        }
        // Денормалы в состоянии фильтра.
        if z0 < 1e-20 && z0 > -1e-20 { z[zb] = 0 }
        if z1 < 1e-20 && z1 > -1e-20 { z[zb + 1] = 0 }
    }


}
