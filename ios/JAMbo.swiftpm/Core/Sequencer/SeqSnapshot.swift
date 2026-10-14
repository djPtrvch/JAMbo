// Снимок паттернов для аудиопотока: плоские массивы чисел, без Swift-коллекций и ARC.
// Строится в основном потоке после каждой правки (SeqSnapshot(project)), передаётся в колбэк через очередь
// (AudioCore.publish); прежний возвращается обратно и освобождается в основном потоке.

/// Указатели снимка — простые значения: колбэк копирует их себе, не трогая счётчик ссылок.
public struct SeqData {
    public static let maxTracks = Params.maxTracks
    public static let maxSteps = Params.maxPages * Params.stepsPerPage
    public static let maxNotes = 8

    public var trackCount: Int = 0
    /// На дорожку: длина паттерна, играющие страницы, остановлена.
    public var length: UnsafeMutablePointer<Int32>
    public var playFrom: UnsafeMutablePointer<Int32>
    public var playTo: UnsafeMutablePointer<Int32>
    public var stopped: UnsafeMutablePointer<UInt8>
    /// На шаг (дорожка·maxSteps + шаг): триг, длина, число нот и ноты (·maxNotes), Chance, Ratchet, Swing (с p-lock).
    public var on: UnsafeMutablePointer<UInt8>
    public var len: UnsafeMutablePointer<Int32>
    public var noteCount: UnsafeMutablePointer<UInt8>
    public var notes: UnsafeMutablePointer<Int16>
    public var prob: UnsafeMutablePointer<Float>
    public var ratchet: UnsafeMutablePointer<Int32>
    public var swing: UnsafeMutablePointer<Float>
    /// Клипы (дорожка·slots + ячейка): есть ли, страницы from…to. Активная ячейка и остановка — как в проекте
    /// (колбэк берёт их, пока транспорт стоит; при игре ими управляет сам).
    public static let slots = Params.patternSlots
    public var clipFilled: UnsafeMutablePointer<UInt8>
    public var clipFrom: UnsafeMutablePointer<Int32>
    public var clipTo: UnsafeMutablePointer<Int32>
    public var slot: UnsafeMutablePointer<Int32>
    /// Строки: видимых, повторы, строка старта, в конце — стоп, LOOP ROW.
    public var rows: Int = 1
    public var repeats: UnsafeMutablePointer<Int32>
    public var arrStart: Int = 0
    public var arrEndStop: Bool = false
    public var rowLoop: Bool = true

    @inline(__always)
    public func pageLen(_ t: Int, _ p: Int, from: Int) -> Int {
        let n = Params.stepsPerPage
        let length = Int(self.length[t])
        if length > from * n { return max(0, min(n, length - p * n)) }
        return n
    }

    @inline(__always)
    public func filled(_ t: Int, _ k: Int) -> Bool {
        return k >= 0 && k < SeqData.slots && clipFilled[t * SeqData.slots + k] != 0
    }

    /// Страницы клипа k дорожки t.
    @inline(__always)
    public func clip(_ t: Int, _ k: Int) -> (from: Int, to: Int) {
        let i = t * SeqData.slots + max(0, min(SeqData.slots - 1, k))
        return (Int(clipFrom[i]), Int(clipTo[i]))
    }

    @inline(__always)
    public func playLen(_ t: Int, slot k: Int) -> Int {
        let c = clip(t, k)
        var n = 0
        var p = c.from
        while p <= c.to {
            n += pageLen(t, p, from: c.from)
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
            let l = pageLen(t, p, from: c.from)
            if r < l { return p * Params.stepsPerPage + r }
            r -= l
            p += 1
        }
        return c.from * Params.stepsPerPage
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
        let steps = tracks * SeqData.maxSteps
        var d = SeqData(
            length: .allocate(capacity: tracks), playFrom: .allocate(capacity: tracks),
            playTo: .allocate(capacity: tracks), stopped: .allocate(capacity: tracks),
            on: .allocate(capacity: steps), len: .allocate(capacity: steps),
            noteCount: .allocate(capacity: steps), notes: .allocate(capacity: steps * SeqData.maxNotes),
            prob: .allocate(capacity: steps), ratchet: .allocate(capacity: steps), swing: .allocate(capacity: steps),
            clipFilled: .allocate(capacity: tracks * SeqData.slots), clipFrom: .allocate(capacity: tracks * SeqData.slots),
            clipTo: .allocate(capacity: tracks * SeqData.slots), slot: .allocate(capacity: tracks),
            repeats: .allocate(capacity: SeqData.slots)
        )
        d.clipFilled.initialize(repeating: 0, count: tracks * SeqData.slots)
        d.clipFrom.initialize(repeating: 0, count: tracks * SeqData.slots)
        d.clipTo.initialize(repeating: 0, count: tracks * SeqData.slots)
        d.slot.initialize(repeating: 0, count: tracks)
        d.repeats.initialize(repeating: 1, count: SeqData.slots)
        d.rows = project.visibleRows
        d.arrStart = min(project.arrStart, d.rows - 1)
        d.arrEndStop = project.arrEndStop
        d.rowLoop = project.rowLoop
        for k in 0..<SeqData.slots { d.repeats[k] = Int32(project.scenes[k].repeats) }
        d.trackCount = min(project.tracks.count, tracks)
        d.length.initialize(repeating: 16, count: tracks)
        d.playFrom.initialize(repeating: 0, count: tracks)
        d.playTo.initialize(repeating: 0, count: tracks)
        d.stopped.initialize(repeating: 1, count: tracks)
        d.on.initialize(repeating: 0, count: steps)
        d.len.initialize(repeating: 1, count: steps)
        d.noteCount.initialize(repeating: 0, count: steps)
        d.notes.initialize(repeating: 0, count: steps * SeqData.maxNotes)
        d.prob.initialize(repeating: 100, count: steps)
        d.ratchet.initialize(repeating: 0, count: steps)
        d.swing.initialize(repeating: 50, count: steps)
        for t in 0..<d.trackCount {
            SeqSnapshot.fill(&d, t, project.tracks[t])
        }
        data = d
        SeqSnapshot.liveCount += 1
    }

    private static func fill(_ d: inout SeqData, _ t: Int, _ track: Track) {
        d.length[t] = Int32(track.length)
        d.playFrom[t] = Int32(track.playFrom)
        d.playTo[t] = Int32(track.playTo)
        d.stopped[t] = track.stopped || track.blank ? 1 : 0
        d.slot[t] = Int32(track.slot)
        for k in 0..<SeqData.slots {
            guard let r = track.clipRange(k) else { continue }
            let i = t * SeqData.slots + k
            d.clipFilled[i] = 1
            d.clipFrom[i] = Int32(r.lowerBound)
            d.clipTo[i] = Int32(r.upperBound)
        }
        for (p, page) in track.pages.enumerated() where p < Params.maxPages {
            for (s, step) in page.enumerated() {
                let i = t * SeqData.maxSteps + p * Params.stepsPerPage + s
                d.on[i] = step.on ? 1 : 0
                d.len[i] = Int32(step.len)
                let n = min(step.notes.count, SeqData.maxNotes)
                d.noteCount[i] = UInt8(n)
                for k in 0..<n { d.notes[i * SeqData.maxNotes + k] = Int16(step.notes[k]) }
                d.prob[i] = Float(track.value("prob", step: step))
                d.ratchet[i] = Int32(track.value("ratchet", step: step).rounded())
                d.swing[i] = Float(track.value("swing", step: step))
            }
        }
    }

    deinit {
        SeqSnapshot.liveCount -= 1
        data.length.deallocate()
        data.playFrom.deallocate()
        data.playTo.deallocate()
        data.stopped.deallocate()
        data.on.deallocate()
        data.len.deallocate()
        data.noteCount.deallocate()
        data.notes.deallocate()
        data.prob.deallocate()
        data.ratchet.deallocate()
        data.swing.deallocate()
        data.clipFilled.deallocate()
        data.clipFrom.deallocate()
        data.clipTo.deallocate()
        data.slot.deallocate()
        data.repeats.deallocate()
    }
}
