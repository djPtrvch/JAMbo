import XCTest
@testable import Core

/// Снимок паттернов: ускоренное построение (S14) даёт те же массивы, что и прежнее, — сверка по контрольной сумме
/// на насыщенном проекте (ноты, длины, velocity, Chance, Ratchet, Swing, p-lock голоса, FX, MOD, MIX, свои звуки).
final class SeqSnapshotDigestTests: XCTestCase {
    static func richProject() -> Project {
        var rng = SystemRandomNumberGenerator.Seeded(seed: 7)
        var p = Project()
        while p.tracks.count < 6 { p.addTrack() }
        let ids: [String] = VoiceParam.ids + Params.fxIds + Params.modIds + ["prob", "ratchet", "unknown"]
        for t in 0..<6 {
            p.tracks[t].params["prob"] = Double(40 + t)
            p.tracks[t].params["ratchet"] = Double(t % 3)
            p.tracks[t].params["swing"] = Double(50 + t)
            for c in 0..<3 {
                var clip = Clip(pages: [[Step]](repeating: Track.emptyPage(), count: 1 + (t + c) % 4), length: 16 * (1 + (t + c) % 4) - c,
                                playFrom: 0, playTo: (t + c) % 4)
                for pg in clip.pages.indices {
                    for s in 0..<16 {
                        let r: Int = rng.next(100)
                        if r < 40 { continue }
                        var st = Step()
                        st.on = r % 3 != 0
                        st.len = 1 + r % 4
                        st.notes = Array((0..<(1 + r % 3)).map { 36 + $0 * 4 + s })
                        if r % 5 == 0 { st.lens = st.notes.map { _ in 1 + r % 3 } }
                        if r % 7 == 0 { st.vels = st.notes.map { _ in Double(r) } }
                        if r % 4 == 0 { st.sound = "snd\(r)" }
                        for k in 0..<(r % 5) { st.locks[ids[(r * 7 + k * 13) % ids.count]] = Double(r + k) }
                        clip.pages[pg][s] = st
                    }
                }
                p.tracks[t].clips[c] = clip
            }
            p.tracks[t].slot = t % 3
        }
        p.chanSeqs[Project.mixSeq].withOpen { c in
            c.pages[0][3].locks["mix.vol3"] = -6
            c.pages[0][5].locks["mix.vol1"] = 3
        }
        return p
    }

    static func digest(_ s: SeqSnapshot, blocks: Int) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        func eat<T>(_ p: UnsafeMutablePointer<T>, _ n: Int) {
            let raw = UnsafeRawBufferPointer(start: UnsafeRawPointer(p), count: n * MemoryLayout<T>.stride)
            for b in raw { h = (h ^ UInt64(b)) &* 1099511628211 }
        }
        let d = s.data
        let cells = SeqData.maxTracks * SeqData.slots
        let steps = max(1, blocks) * SeqData.maxSteps
        eat(d.stopped, SeqData.maxTracks); eat(d.slot, SeqData.maxTracks)
        eat(d.clipBlock, cells); eat(d.clipLength, cells); eat(d.clipFrom, cells); eat(d.clipTo, cells); eat(d.clipRate, cells)
        eat(d.on, steps); eat(d.len, steps); eat(d.noteCount, steps); eat(d.notes, steps * SeqData.maxNotes)
        eat(d.split, steps); eat(d.noteLen, steps * SeqData.maxNotes); eat(d.noteVel, steps * SeqData.maxNotes)
        eat(d.prob, steps); eat(d.ratchet, steps); eat(d.swing, steps); eat(d.sound, steps)
        eat(d.lockMask, steps); eat(d.lockVal, steps * VoiceParam.count)
        eat(d.fxMask, steps); eat(d.fxVal, steps * Params.fxCount)
        eat(d.modMask, steps); eat(d.modVal, steps * Params.modCount)
        eat(d.repeats, SeqData.slots); eat(d.chanLength, SeqData.chans); eat(d.chanFrom, SeqData.chans); eat(d.chanTo, SeqData.chans)
        eat(d.mixMask, SeqData.maxSteps); eat(d.mixGain, SeqData.maxSteps * SeqData.maxTracks)
        return h
    }

    func testDigest() {
        let p = SeqSnapshotDigestTests.richProject()
        let blocks = p.tracks.reduce(0) { $0 + $1.clips.filter { $0 != nil }.count }
        let h = SeqSnapshotDigestTests.digest(SeqSnapshot(p), blocks: blocks)
        print("SEQ DIGEST \(h)")
        XCTAssertEqual(h, SeqSnapshotDigestTests.expected)
    }

    // Длины клипов в снимке — упакованные длины страниц (своя длина у каждой страницы): сумма пересчитана.
    static let expected: UInt64 = 2286589868282060807
}

extension SystemRandomNumberGenerator {
    /// Простой детерминированный генератор для тестов.
    struct Seeded {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next(_ n: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(n))
        }
    }
}
