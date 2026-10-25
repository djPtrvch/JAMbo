// Секвенсор в аудиоколбэке (как transport.ts веба, но без планирования наперёд): шаг k звучит в момент
// timeAt(k/4) источника такта — с точностью до отсчёта. Chance, Ratchet и Swing (с p-lock) — как в вебе.
// Сработавшие ноты играет сэмплер (в своём кадре); в интерфейс уходят шаги и ноты (мигание дорожек).

/// Сообщения из колбэка в интерфейс.
public enum SeqOut: Sendable {
    case none
    /// Шаг pos дорожки track начал играть (pos = p·16 + s; −1 — дорожка стоит); track maxTracks + c —
    /// последовательность MIX (c = 0) или MST (c = 1).
    case step(track: Int, pos: Int)
    /// Сработала нота дорожки (каждый удар рэтчета) в кадре frame.
    case trig(track: Int, frame: Int64)
    /// Доля метронома (accent — начало такта).
    case beat(accent: Bool)
    /// Дорожка играет клип slot (или остановлена) с тика start.
    case clip(track: Int, slot: Int, stopped: Bool, start: Int)
    /// Ожидание у дорожки: Launcher.none, Launcher.stop или ячейка.
    case queue(track: Int, value: Int)
    /// Играет строка row (−1 — нет) с тика start, проход len шагов.
    case scene(row: Int, start: Int, len: Int)
    /// Ожидающая строка (−1 — нет).
    case sceneQueue(row: Int)
    /// Транспорт остановился сам (строки кончились, AT THE END: STOP; конец аранжировки).
    case ended
    /// Курсор аранжировки на текущем шаге (S15), шаги от начала аранжировки.
    case arrange(pos: Int)
    /// Дорожка идёт по таймлайну аранжировки (on) или играет сетку паттернов.
    case follow(track: Int, on: Bool)
}

public final class Sequencer {
    public let out = SPSCQueue<SeqOut>(capacity: 4096, filler: .none)
    /// Ход транспорта для интерфейса (запись нот с REC).
    public let clock = PlayClock()
    public private(set) var playing = false
    public private(set) var tick = 0
    public var metronome = false
    public var data: SeqData? {
        didSet { if !playing, let d = data { launcher.adopt(d) } }
    }
    /// Запуск клипов и строк.
    public let launcher: Launcher

    private let sampleRate: Double
    let tempo: InternalTempoSource
    private var wantedBpm: Double
    private var click: Click
    /// Ноты, назначенные на будущее (рэтчеты и свинг): момент (кадры ядра), дорожка и копия данных шага —
    /// ноты, p-lock голоса, свой звук, удержание (снимок к моменту ноты может смениться).
    private let pendingTime = UnsafeMutablePointer<Double>.allocate(capacity: Sequencer.pendingMax)
    private let pendingTrack = UnsafeMutablePointer<Int32>.allocate(capacity: Sequencer.pendingMax)
    private let pendingNotes = UnsafeMutablePointer<Int16>.allocate(capacity: Sequencer.pendingMax * SeqData.maxNotes)
    private let pendingCountN = UnsafeMutablePointer<Int32>.allocate(capacity: Sequencer.pendingMax)
    private let pendingMask = UnsafeMutablePointer<VoiceMask>.allocate(capacity: Sequencer.pendingMax)
    private let pendingVals = UnsafeMutablePointer<Float>.allocate(capacity: Sequencer.pendingMax * VoiceParam.count)
    private let pendingSound = UnsafeMutablePointer<UInt64>.allocate(capacity: Sequencer.pendingMax)
    private let pendingGate = UnsafeMutablePointer<Int64>.allocate(capacity: Sequencer.pendingMax)
    /// Гейт ENV ноты (кадров): рэтчет — 0,6 удара, от 2 шагов — длина ноты, иначе 0,9 шага.
    private let pendingEnv = UnsafeMutablePointer<Int64>.allocate(capacity: Sequencer.pendingMax)
    /// Голоса сэмплера (задаёт AudioCore).
    public var sampler: Sampler?
    /// P-lock общих FX играющего шага каждой дорожки (биты Params.fxIds и значения; 0 — нет): читает FxRack.
    public let fxLockMask = UnsafeMutablePointer<UInt32>.allocate(capacity: SeqData.maxTracks)
    public let fxLockVal = UnsafeMutablePointer<Float>.allocate(capacity: SeqData.maxTracks * Params.fxCount)
    /// P-lock LFO/ENV играющего шага каждой дорожки (биты Params.modIds и значения): читает ModEngine.
    public let modLockMask = UnsafeMutablePointer<UInt16>.allocate(capacity: SeqData.maxTracks)
    public let modLockVal = UnsafeMutablePointer<Float>.allocate(capacity: SeqData.maxTracks * Params.modCount)
    /// P-lock громкостей играющего шага MIX (биты дорожек и усиления): читает микшер (SamplerMix).
    public let mixLockMask = UnsafeMutablePointer<UInt16>.allocate(capacity: 1)
    public let mixLockGain = UnsafeMutablePointer<Float>.allocate(capacity: SeqData.maxTracks)
    /// Модуляция (ENV от нот; LFO/ENV на Chance, Ratchet, Swing) — задаёт AudioCore.
    public var mod: ModEngine?
    /// Запись стемов (S11d): звук — в кольцо, правила начала и конца — SequencerStems.swift.
    public let stemRing = StemRing()
    let stemRules = StemRules()
    private var pendingCount = 0
    private static let pendingMax = 512
    private var rng: UInt32 = 0x9E3779B9

    public init(sampleRate: Double, bpm: Double) {
        self.sampleRate = sampleRate
        tempo = InternalTempoSource(bpm: bpm)
        wantedBpm = bpm
        click = Click(sampleRate: sampleRate)
        launcher = Launcher(out: out)
        pendingTime.initialize(repeating: 0, count: Sequencer.pendingMax)
        pendingTrack.initialize(repeating: 0, count: Sequencer.pendingMax)
        pendingNotes.initialize(repeating: 0, count: Sequencer.pendingMax * SeqData.maxNotes)
        pendingCountN.initialize(repeating: 0, count: Sequencer.pendingMax)
        pendingMask.initialize(repeating: 0, count: Sequencer.pendingMax)
        pendingVals.initialize(repeating: 0, count: Sequencer.pendingMax * VoiceParam.count)
        pendingSound.initialize(repeating: 0, count: Sequencer.pendingMax)
        pendingGate.initialize(repeating: -1, count: Sequencer.pendingMax)
        pendingEnv.initialize(repeating: 0, count: Sequencer.pendingMax)
        modLockMask.initialize(repeating: 0, count: SeqData.maxTracks)
        modLockVal.initialize(repeating: 0, count: SeqData.maxTracks * Params.modCount)
        fxLockMask.initialize(repeating: 0, count: SeqData.maxTracks)
        fxLockVal.initialize(repeating: 0, count: SeqData.maxTracks * Params.fxCount)
        mixLockMask.initialize(to: 0)
        mixLockGain.initialize(repeating: 0, count: SeqData.maxTracks)
    }

    deinit {
        pendingTime.deallocate()
        pendingTrack.deallocate()
        pendingNotes.deallocate()
        pendingCountN.deallocate()
        pendingMask.deallocate()
        pendingVals.deallocate()
        pendingSound.deallocate()
        pendingGate.deallocate()
        fxLockMask.deallocate()
        fxLockVal.deallocate()
        pendingEnv.deallocate()
        modLockMask.deallocate()
        modLockVal.deallocate()
        mixLockMask.deallocate()
        mixLockGain.deallocate()
    }

    public var bpm: Double { return tempo.tempo }

    /// Темп: при игре — со следующего шага (доля не прыгает), без игры — сразу.
    public func set(bpm: Double) {
        wantedBpm = bpm
        if !playing { tempo.set(bpm) }
    }

    /// Старт и стоп в кадре at (первый шаг звучит в этом кадре).
    public func set(playing on: Bool, at: Int64) {
        if on == playing { return }
        playing = on
        pendingCount = 0
        if on {
            tick = 0
            tempo.set(wantedBpm)
            tempo.start(at: Double(at) / sampleRate)
            if let d = data { launcher.start(d) }
        } else {
            // Стемы дописываются в кадре остановки (STOP в конце строк, стоп из интерфейса, другой проект).
            stemsStopped(at: at)
            sampler?.midiAllOff(at: at)
            launcher.reset()
            fxLockMask.update(repeating: 0, count: SeqData.maxTracks)
            modLockMask.update(repeating: 0, count: SeqData.maxTracks)
            mixLockMask.pointee = 0
            for t in 0..<SeqData.maxTracks + SeqData.chans { out.push(.step(track: t, pos: -1)) }
            out.push(.scene(row: -1, start: 0, len: 16))
            out.push(.sceneQueue(row: -1))
        }
    }

    /// Старт по MIDI-клоку (S13e): шаг 0 — в кадре frame. В прошлом не дальше 0,9 шага — опоздает только шаг 0.
    public func start(at frame: Int64, now: Int64) {
        if playing { return }
        let step: Double = 60 / wantedBpm / TempoGrid.stepsPerBeat * sampleRate
        let earliest: Int64 = now - Int64(step * 0.9)
        set(playing: true, at: Swift.max(frame, earliest))
    }

    /// Ведомый по MIDI-клоку: следующий шаг step должен звучать в кадре frame — фаза сдвигается на 25 % ошибки
    /// (ошибка больше шага — пропуск, как в вебе).
    public func clockPhase(step: Int, frame: Double) {
        guard playing && step == tick else { return }
        let err: Double = stepFrame(step) - frame
        let len: Double = 60 / tempo.tempo / TempoGrid.stepsPerBeat * sampleRate
        if abs(err) >= len { return }
        tempo.shift(-err * 0.25 / sampleRate)
    }

    /// Тап по ячейке во время игры (без игры клип ставит сам интерфейс — снимком проекта).
    public func queue(track t: Int, slot k: Int) {
        if playing { launcher.queue(t, k) }
    }

    /// Строки переставили: активные ячейки и остановки — из снимка, ожидания и строка сбрасываются (ход дорожек — прежний).
    public func adoptPlay() {
        guard let d = data else { return }
        launcher.adopt(d)
        launcher.clearQueues()
    }

    public func queueScene(_ k: Int, atPass: Bool) {
        if playing { launcher.queueScene(k, atPass: atPass) }
    }

    /// Аранжировщик (S15): PLAY в его окне (on) — все дорожки по таймлайну с позиции from; без игры — только задаётся.
    public func setArrange(on: Bool, from: Int) {
        launcher.arrangeMode = on
        launcher.arrFrom = Swift.max(0, from)
    }

    /// Курсор аранжировки на позицию pos во время игры (со следующего шага); без игры — позиция старта.
    public func seekArrange(_ pos: Int) {
        let p: Int = Swift.max(0, pos)
        launcher.arrFrom = p
        guard playing else { return }
        launcher.seek(p)
    }

    /// Возврат дорожки к таймлайну во время игры (track < 0 — всех).
    public func returnToArrange(track t: Int) {
        guard playing else { return }
        if t < 0 {
            for k in 0..<SeqData.maxTracks { launcher.returnToArrange(k) }
        } else {
            launcher.returnToArrange(t)
        }
    }

    /// Переход MIX: все дорожки — в сетку паттернов (играют свои клипы дальше).
    public func leaveArrange() {
        launcher.setFollow(all: false)
    }

    /// Кадр (дробный) шага k от старта.
    @inline(__always)
    func stepFrame(_ k: Int) -> Double {
        return tempo.timeAt(Double(k) / TempoGrid.stepsPerBeat) * sampleRate
    }

    /// Блок [blockStart, blockStart + frames): шаги, ноты и щелчки, попавшие в него; щелчок прибавляется к left/right.
    public func process(blockStart: Int64, frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
                        host: Double = 0) {
        let end = Double(blockStart + Int64(frames))
        if playing, let d = data {
            var guardSteps = 0
            while playing && stepFrame(tick) < end && guardSteps < 64 {
                playStep(d, at: stepFrame(tick))
                tempo.retempo(wantedBpm, fromBeat: Double(tick - 1) / TempoGrid.stepsPerBeat)
                guardSteps += 1
            }
        }
        firePending(before: end)
        click.render(blockStart: blockStart, frames: frames, left: left, right: right)
        var st = PlayClock.State()
        st.playing = playing
        st.nextTick = tick
        st.nextFrame = stepFrame(tick)
        st.stepFrames = 60 / tempo.tempo / TempoGrid.stepsPerBeat * sampleRate
        st.blockFrame = Double(blockStart)
        st.blockHost = host
        clock.write(st)
    }

    private func playStep(_ d: SeqData, at time: Double) {
        if !launcher.beforeStep(d, tick: tick) {
            set(playing: false, at: Int64(time))
            out.push(.ended)
            return
        }
        // Стемы — после смены строк и клипов на этом тике; PLAY во время записи — стоп, когда всё дописано.
        if stemsStep(d, at: time) {
            set(playing: false, at: Int64(time))
            out.push(.ended)
            return
        }
        let dur: Double = 60 / tempo.tempo / TempoGrid.stepsPerBeat * sampleRate
        if tick % Int(TempoGrid.stepsPerBeat) == 0 {
            let accent = TempoGrid.isBarStart(Double(tick) / TempoGrid.stepsPerBeat)
            if metronome { click.trigger(at: Int64(time), accent: accent) }
            out.push(.beat(accent: accent))
        }
        // Свои последовательности MIX и MST: только p-lock на время шага (громкости — у MIX), с PLAY с первого шага.
        var c = 0
        while c < SeqData.chans {
            let pos = d.chanIndex(c, tick)
            out.push(.step(track: SeqData.maxTracks + c, pos: pos))
            if c == Project.mixSeq {
                let m: UInt16 = pos >= 0 && pos < SeqData.maxSteps ? d.mixMask[pos] : 0
                mixLockMask.pointee = m
                if m != 0 {
                    var t = 0
                    while t < SeqData.maxTracks {
                        mixLockGain[t] = d.mixGain[pos * SeqData.maxTracks + t]
                        t += 1
                    }
                }
            }
            c += 1
        }
        for t in 0..<d.trackCount {
            if !launcher.plays(d, t) {
                out.push(.step(track: t, pos: -1))
                fxLockMask[t] = 0
                modLockMask[t] = 0
                continue
            }
            // Скорость клипа (S14): ×2 — два шага за тик (второй — через полшага), медленнее — шаг раз в 2…16 тиков
            // (на остальных тиках играющий шаг продолжается: p-lock FX и LFO/ENV остаются).
            let k = launcher.slot[t]
            let len: Int = d.playLen(t, slot: k)
            let rate: Int = d.rate(t, slot: k)
            let pass: Int = d.tickLen(t, slot: k)
            let o: Int = ((tick - launcher.trackStart[t]) % pass + pass) % pass
            var n: Int = o
            var count: Int = 1
            if rate > 0 {
                n = o * 2
                count = 2
            } else if rate < 0 {
                let div: Int = 1 << (-rate)
                if o % div != 0 { continue }
                n = o / div
            }
            let stepDur: Double = rate > 0 ? dur / 2 : dur * Double(1 << max(0, -rate))
            var h = 0
            while h < count && n + h < len {
                let pos = d.playIndex(t, slot: k, n + h)
                let i = d.stepIndex(t, slot: k, pos)
                if h == 0 {
                    out.push(.step(track: t, pos: pos))
                    // P-lock FX и LFO/ENV — на время шага (и на шаге без ноты); при ×2 — первого из двух.
                    fxLockMask[t] = i >= 0 ? d.fxMask[i] : 0
                    if i >= 0 && d.fxMask[i] != 0 {
                        for p in 0..<Params.fxCount { fxLockVal[t * Params.fxCount + p] = d.fxVal[i * Params.fxCount + p] }
                    }
                    modLockMask[t] = i >= 0 ? d.modMask[i] : 0
                    if i >= 0 && d.modMask[i] != 0 {
                        for p in 0..<Params.modCount { modLockVal[t * Params.modCount + p] = d.modVal[i * Params.modCount + p] }
                    }
                }
                if i >= 0 && d.on[i] != 0 {
                    trig(d, t, i, pos, at: time + Double(h) * stepDur, dur: stepDur)
                }
                h += 1
            }
        }
        tick += 1
    }

    /// Триг шага i дорожки t в момент time; dur — длительность шага с учётом скорости клипа.
    private func trig(_ d: SeqData, _ t: Int, _ i: Int, _ pos: Int, at time: Double, dur: Double) {
        // Chance, Ratchet — с p-lock и LFO/ENV на момент шага; Swing — значение дорожки.
        var prob = Double(d.prob[i])
        var ratchetV = Double(d.ratchet[i])
        let swing = Double(d.swing[i])
        if let m = mod, m.modulated(t) {
            let f = Int64(time)
            prob = m.value(t, ModTarget.prob, prob, f)
            ratchetV = m.value(t, ModTarget.ratchet, ratchetV, f)
        }
        if Double(nextRandom()) * 100 >= prob { return }
        let ratchet = Int(ratchetV.rounded()) + 1
        let offset: Double = pos % 2 == 1 ? (swing - 50) / 50 * dur : 0
        let sub = dur / Double(ratchet)
        // Нота от 2 шагов держится до своего конца (Decay — после); в 1 шаг и рэтчет — Decay сразу после атаки.
        let gate: Int64 = ratchet == 1 && d.len[i] >= 2 ? Int64((Double(d.len[i]) * dur).rounded()) : -1
        let envGate: Int64 = Int64((ratchet > 1 ? sub * 0.6 : (d.len[i] >= 2 ? Double(d.len[i]) * dur : dur * 0.9)).rounded())
        for r in 0..<ratchet {
            let at: Double = time + offset + Double(r) * sub
            if d.split[i] == 0 {
                schedule(track: t, at: at, d, i, gate, envGate)
                continue
            }
            // Ноты со своими длинами и velocity (S8) — по одной; с конца, чтобы у DRUM осталась первая.
            var j: Int = Int(d.noteCount[i]) - 1
            while j >= 0 {
                let nl: Int32 = d.noteLen[i * SeqData.maxNotes + j]
                let ng: Int64 = ratchet == 1 && nl >= 2 ? Int64((Double(nl) * dur).rounded()) : -1
                scheduleNote(track: t, at: at, d, i, j, ng, envGate)
                j -= 1
            }
        }
    }

    private func schedule(track: Int, at time: Double, _ d: SeqData, _ i: Int, _ gate: Int64, _ envGate: Int64) {
        if pendingCount >= Sequencer.pendingMax { return }
        let k = pendingCount
        pendingTime[k] = time
        pendingTrack[k] = Int32(track)
        let n = Int(d.noteCount[i])
        pendingCountN[k] = Int32(n)
        for j in 0..<n { pendingNotes[k * SeqData.maxNotes + j] = d.notes[i * SeqData.maxNotes + j] }
        pendingMask[k] = d.lockMask[i]
        for p in 0..<VoiceParam.count { pendingVals[k * VoiceParam.count + p] = d.lockVal[i * VoiceParam.count + p] }
        pendingSound[k] = d.sound[i]
        pendingGate[k] = gate
        pendingEnv[k] = envGate
        pendingCount += 1
    }

    /// Одна нота j шага i; своя velocity — p-lock Level этой ноты.
    private func scheduleNote(track: Int, at time: Double, _ d: SeqData, _ i: Int, _ j: Int, _ gate: Int64,
                              _ envGate: Int64) {
        if pendingCount >= Sequencer.pendingMax { return }
        let k = pendingCount
        schedule(track: track, at: time, d, i, gate, envGate)
        if pendingCount == k { return }
        pendingCountN[k] = 1
        pendingNotes[k * SeqData.maxNotes] = d.notes[i * SeqData.maxNotes + j]
        let v: Float = d.noteVel[i * SeqData.maxNotes + j]
        if v >= 0 {
            pendingMask[k] |= VoiceMask(1) << VoiceMask(VoiceParam.level)
            pendingVals[k * VoiceParam.count + VoiceParam.level] = v
        }
    }

    /// Ячейку k — на место последней (порядок неважен).
    private func movePending(_ from: Int, _ to: Int) {
        pendingTime[to] = pendingTime[from]
        pendingTrack[to] = pendingTrack[from]
        pendingCountN[to] = pendingCountN[from]
        for j in 0..<SeqData.maxNotes { pendingNotes[to * SeqData.maxNotes + j] = pendingNotes[from * SeqData.maxNotes + j] }
        pendingMask[to] = pendingMask[from]
        for p in 0..<VoiceParam.count { pendingVals[to * VoiceParam.count + p] = pendingVals[from * VoiceParam.count + p] }
        pendingSound[to] = pendingSound[from]
        pendingGate[to] = pendingGate[from]
        pendingEnv[to] = pendingEnv[from]
    }

    /// Ноты, момент которых наступил (раньше конца блока).
    private func firePending(before end: Double) {
        var k = 0
        while k < pendingCount {
            if pendingTime[k] < end {
                let t = Int(pendingTrack[k])
                let frame = Int64(pendingTime[k].rounded(.down))
                out.push(.trig(track: t, frame: frame))
                // ENV запускается в кадре ноты — начальные значения ноты берут ENV на этот момент.
                mod?.trig(track: t, at: frame, gate: pendingEnv[k])
                // MIDI OUT дорожки: нота на устройство (длина — как гейт ENV), голоса не звучат.
                if let s = sampler, s.sendsMidi(t) {
                    s.midiNotes(track: t, at: frame, notes: pendingNotes + k * SeqData.maxNotes, count: Int(pendingCountN[k]),
                                mask: pendingMask[k], vals: pendingVals + k * VoiceParam.count, length: pendingEnv[k],
                                liveId: -1)
                    pendingCount -= 1
                    if k != pendingCount { movePending(pendingCount, k) }
                    continue
                }
                sampler?.trigger(track: t, at: frame, notes: pendingNotes + k * SeqData.maxNotes, count: Int(pendingCountN[k]),
                                 mask: pendingMask[k], vals: pendingVals + k * VoiceParam.count, hash: pendingSound[k],
                                 gate: pendingGate[k], own: pendingSound[k] != 0, liveId: -1)
                pendingCount -= 1
                if k != pendingCount { movePending(pendingCount, k) }
            } else {
                k += 1
            }
        }
    }

    /// Равномерное 0…1 (xorshift32) — для Chance.
    @inline(__always)
    private func nextRandom() -> Float {
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return Float(rng >> 8) / Float(1 << 24)
    }

    // MARK: — для тестов

    /// Кадр шага k (для проверки точности).
    public func frameOfStep(_ k: Int) -> Double {
        return stepFrame(k)
    }
}
