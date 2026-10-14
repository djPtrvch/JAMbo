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

    @inline(__always)
    public func pageLen(_ t: Int, _ p: Int) -> Int {
        let n = Params.stepsPerPage
        let length = Int(self.length[t])
        if length > Int(playFrom[t]) * n { return max(0, min(n, length - p * n)) }
        return n
    }

    @inline(__always)
    public func playLen(_ t: Int) -> Int {
        var n = 0
        var p = Int(playFrom[t])
        let to = Int(playTo[t])
        while p <= to {
            n += pageLen(t, p)
            p += 1
        }
        return max(1, n)
    }

    /// Шаг (p·16 + s) на позиции n прохода, по кругу.
    @inline(__always)
    public func playIndex(_ t: Int, _ n: Int) -> Int {
        let total = playLen(t)
        var r = ((n % total) + total) % total
        var p = Int(playFrom[t])
        let to = Int(playTo[t])
        while p <= to {
            let l = pageLen(t, p)
            if r < l { return p * Params.stepsPerPage + r }
            r -= l
            p += 1
        }
        return Int(playFrom[t]) * Params.stepsPerPage
    }
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
            prob: .allocate(capacity: steps), ratchet: .allocate(capacity: steps), swing: .allocate(capacity: steps)
        )
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
        d.stopped[t] = track.stopped ? 1 : 0
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
    }
}
