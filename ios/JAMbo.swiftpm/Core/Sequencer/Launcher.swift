// Запуск клипов и строк в колбэке (как queuePattern, startScene, advanceScenes в transport.ts веба):
// ожидающий клип стартует, когда текущий клип дорожки доиграет (у остановленной — с начала такта);
// строка — с начала такта (стрелки SWITCH — в конце прохода строки); повторы строк, LOOP ROW, AT THE END.
// Пока транспорт стоит, активные ячейки и остановки берутся из снимка проекта; при игре ими управляет колбэк,
// изменения уходят в интерфейс сообщениями clip, queue, scene.

public final class Launcher {
    /// Нет ожидания / ожидает остановки (иначе — номер ячейки).
    public static let none = -2
    public static let stop = -1

    let out: SPSCQueue<SeqOut>
    let slot = UnsafeMutablePointer<Int>.allocate(capacity: SeqData.maxTracks)
    let stopped = UnsafeMutablePointer<Bool>.allocate(capacity: SeqData.maxTracks)
    let queued = UnsafeMutablePointer<Int>.allocate(capacity: SeqData.maxTracks)
    let trackStart = UnsafeMutablePointer<Int>.allocate(capacity: SeqData.maxTracks)
    /// Играющая строка (−1 — нет), её начало (тик) и проход (самый длинный клип строки).
    public private(set) var sceneRow = -1
    public private(set) var sceneStart = 0
    public private(set) var sceneLen = 16
    /// Ожидающая строка (−1 — нет); atPass — в конце прохода играющей строки (стрелки SWITCH).
    public private(set) var sceneQueued = -1
    var sceneAtPass = false
    /// Тик, на котором строки пошли по кругу (AT THE END: LOOP) — там кончаются стемы (−1 — не было).
    public private(set) var wrappedAt = -1

    init(out: SPSCQueue<SeqOut>) {
        self.out = out
        slot.initialize(repeating: 0, count: SeqData.maxTracks)
        stopped.initialize(repeating: false, count: SeqData.maxTracks)
        queued.initialize(repeating: Launcher.none, count: SeqData.maxTracks)
        trackStart.initialize(repeating: 0, count: SeqData.maxTracks)
    }

    deinit {
        slot.deallocate()
        stopped.deallocate()
        queued.deallocate()
        trackStart.deallocate()
    }

    /// Транспорт стоит: активные ячейки и остановки — из снимка проекта.
    func adopt(_ d: SeqData) {
        for t in 0..<SeqData.maxTracks {
            slot[t] = t < d.trackCount ? Int(d.slot[t]) : 0
            stopped[t] = t >= d.trackCount || d.stopped[t] != 0
        }
    }

    /// Ожидания и строка сбрасываются (начала проходов дорожек — прежние).
    func clearQueues() {
        for t in 0..<SeqData.maxTracks where queued[t] != Launcher.none {
            queued[t] = Launcher.none
            out.push(.queue(track: t, value: Launcher.none))
        }
        sceneRow = -1
        sceneQueued = -1
        out.push(.scene(row: -1, start: 0, len: 16))
        out.push(.sceneQueue(row: -1))
    }

    func reset() {
        for t in 0..<SeqData.maxTracks {
            queued[t] = Launcher.none
            trackStart[t] = 0
        }
        sceneRow = -1
        sceneQueued = -1
        sceneAtPass = false
        wrappedAt = -1
    }

    /// Старт транспорта (тик 0): ожидающие клипы — сразу; ожидающая строка или строка старта (если в ней что-то есть).
    func start(_ d: SeqData) {
        var anyQueued = false
        for t in 0..<d.trackCount where queued[t] != Launcher.none {
            anyQueued = true
            apply(t, queued[t], tick: 0)
        }
        if sceneQueued >= 0 {
            startScene(d, sceneQueued, at: 0)
        } else if !anyQueued {
            let k = min(d.arrStart, d.rows - 1)
            if rowFilled(d, k) { startScene(d, k, at: 0) }
        }
    }

    // MARK: — команды интерфейса (во время игры)

    /// Тап по ячейке: k — запуск клипа, Launcher.stop — остановка; повторный тап по ожидающей — отмена.
    func queue(_ t: Int, _ k: Int) {
        queued[t] = queued[t] == k ? Launcher.none : k
        out.push(.queue(track: t, value: queued[t]))
    }

    /// Тап по строке: с начала следующего такта (повторный — отмена); atPass — в конце прохода играющей строки.
    func queueScene(_ k: Int, atPass: Bool) {
        if atPass {
            sceneQueued = k
            sceneAtPass = true
        } else {
            sceneQueued = sceneQueued == k ? -1 : k
            sceneAtPass = false
        }
        out.push(.sceneQueue(row: sceneQueued))
    }

    // MARK: — на каждом шаге

    /// Перед шагом tick: строки и ожидающие клипы. false — транспорт остановился (строки кончились, STOP).
    func beforeStep(_ d: SeqData, tick: Int) -> Bool {
        if sceneQueued >= 0 && sceneDue(tick) {
            startScene(d, sceneQueued, at: tick)
            sceneAtPass = false
        } else if sceneRow >= 0 && sceneEnds(d, tick) {
            if sceneRow + 1 < d.rows {
                startScene(d, sceneRow + 1, at: tick)
            } else if d.arrEndStop {
                return false
            } else {
                startScene(d, min(d.arrStart, d.rows - 1), at: tick)
                wrappedAt = tick
            }
        }
        for t in 0..<d.trackCount where queued[t] != Launcher.none && atBoundary(d, t, tick) {
            apply(t, queued[t], tick: tick)
        }
        return true
    }

    /// Дорожка играет: активная ячейка с клипом и не остановлена.
    @inline(__always)
    func plays(_ d: SeqData, _ t: Int) -> Bool {
        return !stopped[t] && d.filled(t, slot[t])
    }

    // MARK: — внутреннее

    private func rowFilled(_ d: SeqData, _ k: Int) -> Bool {
        for t in 0..<d.trackCount where d.filled(t, k) { return true }
        return false
    }

    private func sceneDue(_ tick: Int) -> Bool {
        if sceneAtPass && sceneRow >= 0 && sceneLen > 0 {
            return tick > sceneStart && (tick - sceneStart) % sceneLen == 0
        }
        return TempoGrid.isBarStart(Double(tick) / TempoGrid.stepsPerBeat)
    }

    /// Строка с повторами кончилась (одна строка или LOOP ROW — играет по кругу).
    func sceneEnds(_ d: SeqData, _ tick: Int) -> Bool {
        let reps = Int(d.repeats[max(0, min(SeqData.slots - 1, sceneRow))])
        return reps > 0 && !d.rowLoop && d.rows > 1 && tick - sceneStart >= reps * sceneLen
    }

    private func atBoundary(_ d: SeqData, _ t: Int, _ tick: Int) -> Bool {
        if !plays(d, t) { return TempoGrid.isBarStart(Double(tick) / TempoGrid.stepsPerBeat) }
        return (tick - trackStart[t]) % d.playLen(t, slot: slot[t]) == 0
    }

    private func apply(_ t: Int, _ q: Int, tick: Int) {
        queued[t] = Launcher.none
        if q == Launcher.stop {
            stopped[t] = true
        } else {
            slot[t] = q
            stopped[t] = false
        }
        trackStart[t] = tick
        out.push(.clip(track: t, slot: slot[t], stopped: stopped[t], start: tick))
    }

    /// Строка k на тике at: на каждой дорожке — её клип этой строки, дорожки с пустой ячейкой останавливаются.
    private func startScene(_ d: SeqData, _ k: Int, at: Int) {
        var len = 0
        for t in 0..<d.trackCount {
            queued[t] = Launcher.none
            trackStart[t] = at
            if d.filled(t, k) {
                slot[t] = k
                stopped[t] = false
                len = max(len, d.playLen(t, slot: k))
            } else {
                stopped[t] = true
            }
            out.push(.clip(track: t, slot: slot[t], stopped: stopped[t], start: at))
        }
        sceneRow = k
        sceneStart = at
        sceneLen = len > 0 ? len : 16
        sceneQueued = -1
        sceneAtPass = false
        out.push(.scene(row: k, start: at, len: sceneLen))
        // Ожидание снято: строка больше не мигает.
        out.push(.sceneQueue(row: -1))
    }
}
