// Снимок паттернов для аудиопотока: плоские массивы чисел, без Swift-коллекций и ARC.
// Строится в основном потоке после каждой правки (SeqSnapshot(project)), передаётся в колбэк через очередь
// (AudioCore.publish); прежний возвращается обратно и освобождается в основном потоке.

/// Указатели снимка — простые значения: колбэк копирует их себе, не трогая счётчик ссылок.
/// У каждого клипа (дорожка·slots + ячейка) свой паттерн: блок шагов (номер блока или −1 — ячейка пуста),
/// длина и играющие страницы.
public struct SeqData {
    public static let maxTracks = Params.maxTracks
    public static let maxSteps = Params.maxPages * Params.stepsPerPage
    public static let maxNotes = 8
    public static let slots = Params.patternSlots

    public var trackCount: Int = 0
    /// На дорожку: остановлена, активная ячейка (колбэк берёт их, пока транспорт стоит; при игре ими управляет сам).
    public var stopped: UnsafeMutablePointer<UInt8>
    public var slot: UnsafeMutablePointer<Int32>
    /// На клип: блок шагов (−1 — пусто), длина паттерна, страницы from…to.
    public var clipBlock: UnsafeMutablePointer<Int32>
    public var clipLength: UnsafeMutablePointer<Int32>
    public var clipFrom: UnsafeMutablePointer<Int32>
    public var clipTo: UnsafeMutablePointer<Int32>
    /// На шаг (блок·maxSteps + шаг): триг, длина, число нот и ноты (·maxNotes), Chance, Ratchet, Swing (с p-lock).
    public var on: UnsafeMutablePointer<UInt8>
    public var len: UnsafeMutablePointer<Int32>
    public var noteCount: UnsafeMutablePointer<UInt8>
    public var notes: UnsafeMutablePointer<Int16>
    public var prob: UnsafeMutablePointer<Float>
    public var ratchet: UnsafeMutablePointer<Int32>
    public var swing: UnsafeMutablePointer<Float>
    /// Свой звук шага (ключ; 0 — звук дорожки) и p-lock параметров голоса (биты VoiceParam и значения).
    public var sound: UnsafeMutablePointer<UInt64>
    public var lockMask: UnsafeMutablePointer<UInt16>
    public var lockVal: UnsafeMutablePointer<Float>
    /// P-lock общих FX (биты Params.fxIds и значения): действуют, пока шаг играет.
    public var fxMask: UnsafeMutablePointer<UInt32>
    public var fxVal: UnsafeMutablePointer<Float>
    /// Строки: видимых, повторы, строка старта, в конце — стоп, LOOP ROW.
    public var rows: Int = 1
    public var repeats: UnsafeMutablePointer<Int32>
    public var arrStart: Int = 0
    public var arrEndStop: Bool = false
    public var rowLoop: Bool = true

    @inline(__always)
    private func ci(_ t: Int, _ k: Int) -> Int {
        return t * SeqData.slots + max(0, min(SeqData.slots - 1, k))
    }

    @inline(__always)
    public func filled(_ t: Int, _ k: Int) -> Bool {
        return k >= 0 && k < SeqData.slots && clipBlock[t * SeqData.slots + k] >= 0
    }

    /// Страницы клипа k дорожки t.
    @inline(__always)
    public func clip(_ t: Int, _ k: Int) -> (from: Int, to: Int) {
        let i = ci(t, k)
        return (Int(clipFrom[i]), Int(clipTo[i]))
    }

    @inline(__always)
    public func pageLen(_ t: Int, _ k: Int, _ p: Int, from: Int) -> Int {
        let n = Params.stepsPerPage
        let length = Int(clipLength[ci(t, k)])
        if length > from * n { return max(0, min(n, length - p * n)) }
        return n
    }

    @inline(__always)
    public func playLen(_ t: Int, slot k: Int) -> Int {
        let c = clip(t, k)
        var n = 0
        var p = c.from
        while p <= c.to {
            n += pageLen(t, k, p, from: c.from)
            p += 1
        }
        return max(1, n)
    }

    /// Шаг (p·16 + s) клипа k на позиции n прохода, по кругу.
    @inline(__always)
    public func playIndex(_ t: Int, slot k: Int, _ n: Int) -> Int {
        let c = clip(t, k)
        let total = playLen(t, slot: k)
        var r = ((n % total) + total) % total
        var p = c.from
        while p <= c.to {
            let l = pageLen(t, k, p, from: c.from)
            if r < l { return p * Params.stepsPerPage + r }
            r -= l
            p += 1
        }
        return c.from * Params.stepsPerPage
    }

    /// Индекс шага pos клипа k в массивах шагов; −1 — ячейка пуста.
    @inline(__always)
    public func stepIndex(_ t: Int, slot k: Int, _ pos: Int) -> Int {
        let b = Int(clipBlock[ci(t, k)])
        if b < 0 || pos < 0 || pos >= SeqData.maxSteps { return -1 }
        return b * SeqData.maxSteps + pos
    }

    /// Для дорожки с активным клипом из проекта (тесты, интерфейс).
    public func playLen(_ t: Int) -> Int { return playLen(t, slot: Int(slot[t])) }
    public func playIndex(_ t: Int, _ n: Int) -> Int { return playIndex(t, slot: Int(slot[t]), n) }
}

public final class SeqSnapshot: @unchecked Sendable {
    public let data: SeqData
    /// Сколько снимков сейчас в памяти (создаются и освобождаются в основном потоке) — для проверки утечек.
    public static var liveCount = 0

    public init(_ project: Project) {
        let tracks = SeqData.maxTracks
        let cells = tracks * SeqData.slots
        let used = min(project.tracks.count, tracks)
        var blocks = 0
        for t in 0..<used { blocks += project.tracks[t].clips.filter { $0 != nil }.count }
        let steps = max(1, blocks) * SeqData.maxSteps
        var d = SeqData(
            stopped: .allocate(capacity: tracks), slot: .allocate(capacity: tracks),
            clipBlock: .allocate(capacity: cells), clipLength: .allocate(capacity: cells),
            clipFrom: .allocate(capacity: cells), clipTo: .allocate(capacity: cells),
            on: .allocate(capacity: steps), len: .allocate(capacity: steps),
            noteCount: .allocate(capacity: steps), notes: .allocate(capacity: steps * SeqData.maxNotes),
            prob: .allocate(capacity: steps), ratchet: .allocate(capacity: steps), swing: .allocate(capacity: steps),
            sound: .allocate(capacity: steps), lockMask: .allocate(capacity: steps),
            lockVal: .allocate(capacity: steps * VoiceParam.count),
            fxMask: .allocate(capacity: steps), fxVal: .allocate(capacity: steps * Params.fxCount),
            repeats: .allocate(capacity: SeqData.slots)
        )
        d.stopped.initialize(repeating: 1, count: tracks)
        d.slot.initialize(repeating: 0, count: tracks)
        d.clipBlock.initialize(repeating: -1, count: cells)
        d.clipLength.initialize(repeating: Int32(Params.stepsPerPage), count: cells)
        d.clipFrom.initialize(repeating: 0, count: cells)
        d.clipTo.initialize(repeating: 0, count: cells)
        d.on.initialize(repeating: 0, count: steps)
        d.len.initialize(repeating: 1, count: steps)
        d.noteCount.initialize(repeating: 0, count: steps)
        d.notes.initialize(repeating: 0, count: steps * SeqData.maxNotes)
        d.prob.initialize(repeating: 100, count: steps)
        d.ratchet.initialize(repeating: 0, count: steps)
        d.swing.initialize(repeating: 50, count: steps)
        d.sound.initialize(repeating: 0, count: steps)
        d.lockMask.initialize(repeating: 0, count: steps)
        d.lockVal.initialize(repeating: 0, count: steps * VoiceParam.count)
        d.fxMask.initialize(repeating: 0, count: steps)
        d.fxVal.initialize(repeating: 0, count: steps * Params.fxCount)
        d.repeats.initialize(repeating: 1, count: SeqData.slots)
        d.rows = project.visibleRows
        d.arrStart = min(project.arrStart, d.rows - 1)
        d.arrEndStop = project.arrEndStop
        d.rowLoop = project.rowLoop
        for k in 0..<SeqData.slots { d.repeats[k] = Int32(project.scenes[k].repeats) }
        d.trackCount = used
        var block = 0
        for t in 0..<used {
            let track = project.tracks[t]
            d.stopped[t] = track.stopped || track.blank ? 1 : 0
            d.slot[t] = Int32(track.slot)
            for k in 0..<SeqData.slots {
                guard let c = track.clips[k] else { continue }
                SeqSnapshot.fill(&d, track, c, cell: t * SeqData.slots + k, block: block)
                block += 1
            }
        }
        data = d
        SeqSnapshot.liveCount += 1
    }

    /// Снимок паттернов тот же: шаги, клипы, строки и ручки Chance, Ratchet, Swing не менялись.
    public static func same(_ a: Project, _ b: Project) -> Bool {
        if a.tracks.count != b.tracks.count || a.scenes != b.scenes || a.rows != b.rows || a.arrStart != b.arrStart
            || a.arrEndStop != b.arrEndStop || a.rowLoop != b.rowLoop { return false }
        for (x, y) in zip(a.tracks, b.tracks) {
            if x.slot != y.slot || x.stopped != y.stopped || x.clips != y.clips { return false }
            for id in ["prob", "ratchet", "swing"] where x.params[id] != y.params[id] { return false }
        }
        return true
    }

    private static func fill(_ d: inout SeqData, _ track: Track, _ c: Clip, cell: Int, block: Int) {
        let r = c.range
        d.clipBlock[cell] = Int32(block)
        d.clipLength[cell] = Int32(c.length)
        d.clipFrom[cell] = Int32(r.lowerBound)
        d.clipTo[cell] = Int32(r.upperBound)
        for (p, page) in c.pages.enumerated() where p < Params.maxPages {
            for (s, step) in page.enumerated() {
                let i = block * SeqData.maxSteps + p * Params.stepsPerPage + s
                d.on[i] = step.on ? 1 : 0
                d.len[i] = Int32(step.len)
                let n = min(step.notes.count, SeqData.maxNotes)
                d.noteCount[i] = UInt8(n)
                for k in 0..<n { d.notes[i * SeqData.maxNotes + k] = Int16(step.notes[k]) }
                d.prob[i] = Float(track.value("prob", step: step))
                d.ratchet[i] = Int32(track.value("ratchet", step: step).rounded())
                d.swing[i] = Float(track.value("swing", step: step))
                if let snd = step.sound { d.sound[i] = SoundKey.hash(snd) }
                if !step.locks.isEmpty {
                    var mask: UInt16 = 0
                    for (p, id) in VoiceParam.ids.enumerated() {
                        guard let v = step.locks[id] else { continue }
                        mask |= UInt16(1) << UInt16(p)
                        d.lockVal[i * VoiceParam.count + p] = Float(v)
                    }
                    d.lockMask[i] = mask
                    var fm: UInt32 = 0
                    for (p, id) in Params.fxIds.enumerated() {
                        guard let v = step.locks[id] else { continue }
                        fm |= UInt32(1) << UInt32(p)
                        d.fxVal[i * Params.fxCount + p] = Float(v)
                    }
                    d.fxMask[i] = fm
                }
            }
        }
    }

    deinit {
        SeqSnapshot.liveCount -= 1
        data.stopped.deallocate()
        data.slot.deallocate()
        data.clipBlock.deallocate()
        data.clipLength.deallocate()
        data.clipFrom.deallocate()
        data.clipTo.deallocate()
        data.on.deallocate()
        data.len.deallocate()
        data.noteCount.deallocate()
        data.notes.deallocate()
        data.prob.deallocate()
        data.ratchet.deallocate()
        data.swing.deallocate()
        data.sound.deallocate()
        data.lockMask.deallocate()
        data.lockVal.deallocate()
        data.fxMask.deallocate()
        data.fxVal.deallocate()
        data.repeats.deallocate()
    }
}
