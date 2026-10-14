// Секвенсор в аудиоколбэке (как transport.ts веба, но без планирования наперёд): шаг k звучит в момент
// timeAt(k/4) источника такта — с точностью до отсчёта. Chance, Ratchet и Swing (с p-lock) — как в вебе.
// Звука нот пока нет (S2): сработавшие ноты уходят в интерфейс (мигание дорожек); метроном звучит.

/// Сообщения из колбэка в интерфейс.
public enum SeqOut: Sendable {
    case none
    /// Шаг pos дорожки track начал играть (pos = p·16 + s; −1 — дорожка стоит).
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
    /// Транспорт остановился сам (строки кончились, AT THE END: STOP).
    case ended
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
    private let tempo: InternalTempoSource
    private var wantedBpm: Double
    private var click: Click
    /// Ноты, назначенные на будущее (рэтчеты и свинг): момент (кадры ядра) и дорожка.
    private let pendingTime = UnsafeMutablePointer<Double>.allocate(capacity: Sequencer.pendingMax)
    private let pendingTrack = UnsafeMutablePointer<Int32>.allocate(capacity: Sequencer.pendingMax)
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
    }

    deinit {
        pendingTime.deallocate()
        pendingTrack.deallocate()
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
            launcher.reset()
            for t in 0..<SeqData.maxTracks { out.push(.step(track: t, pos: -1)) }
            out.push(.scene(row: -1, start: 0, len: 16))
            out.push(.sceneQueue(row: -1))
        }
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

    /// Кадр (дробный) шага k от старта.
    @inline(__always)
    private func stepFrame(_ k: Int) -> Double {
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
        let dur: Double = 60 / tempo.tempo / TempoGrid.stepsPerBeat * sampleRate
        if tick % Int(TempoGrid.stepsPerBeat) == 0 {
            let accent = TempoGrid.isBarStart(Double(tick) / TempoGrid.stepsPerBeat)
            if metronome { click.trigger(at: Int64(time), accent: accent) }
            out.push(.beat(accent: accent))
        }
        for t in 0..<d.trackCount {
            if !launcher.plays(d, t) {
                out.push(.step(track: t, pos: -1))
                continue
            }
            let k = launcher.slot[t]
            let pos = d.playIndex(t, slot: k, tick - launcher.trackStart[t])
            out.push(.step(track: t, pos: pos))
            let i = d.stepIndex(t, slot: k, pos)
            if i < 0 || d.on[i] == 0 { continue }
            if nextRandom() * 100 >= d.prob[i] { continue }
            let ratchet = Int(d.ratchet[i]) + 1
            let swing = Double(d.swing[i])
            let offset: Double = pos % 2 == 1 ? (swing - 50) / 50 * dur : 0
            let sub = dur / Double(ratchet)
            for r in 0..<ratchet {
                schedule(track: t, at: time + offset + Double(r) * sub)
            }
        }
        tick += 1
    }

    private func schedule(track: Int, at time: Double) {
        if pendingCount >= Sequencer.pendingMax { return }
        pendingTime[pendingCount] = time
        pendingTrack[pendingCount] = Int32(track)
        pendingCount += 1
    }

    /// Ноты, момент которых наступил (раньше конца блока).
    private func firePending(before end: Double) {
        var k = 0
        while k < pendingCount {
            if pendingTime[k] < end {
                out.push(.trig(track: Int(pendingTrack[k]), frame: Int64(pendingTime[k].rounded(.down))))
                pendingCount -= 1
                pendingTime[k] = pendingTime[pendingCount]
                pendingTrack[k] = pendingTrack[pendingCount]
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
