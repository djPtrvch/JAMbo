import XCTest
@testable import Core

/// S8: длина и velocity у каждой ноты шага.
final class StepNotesTests: XCTestCase {
    private func render(_ core: AudioCore, frames: Int) -> [Float] {
        var l = [Float](repeating: 0, count: frames)
        var pos = 0
        var bl = [Float](repeating: 0, count: 256)
        var br = [Float](repeating: 0, count: 256)
        while pos < frames {
            let n = min(256, frames - pos)
            core.render(frames: n, left: &bl, right: &br)
            for i in 0..<n { l[pos + i] = bl[i] }
            pos += n
        }
        return l
    }

    private func project() -> Project {
        var p = Project()
        p.tracks[0].addSamples(["k"])
        p.tracks[0].vol = 0
        return p
    }

    private let center: Float = Float(cos(Double.pi / 4))
    private let quarter: Double = 127 * pow(0.25, 1 / 1.5)

    func testAddRemoveAndNormalize() {
        var s = Step()
        s.on = true
        s.addNote(48, len: 2, vel: nil)
        XCTAssertEqual(s.notes, [48])
        XCTAssertEqual(s.len, 2)
        XCTAssertNil(s.lens, "одна длина — без lens")
        s.addNote(43, len: 4, vel: 90)
        XCTAssertEqual(s.notes, [43, 48])
        XCTAssertEqual(s.lens, [4, 2])
        XCTAssertEqual(s.len, 4, "len — самая длинная")
        XCTAssertEqual(s.vels, [90, -1])
        XCTAssertEqual(s.noteVel(0), 90)
        XCTAssertNil(s.noteVel(1))
        XCTAssertTrue(Track.hasManualLocks(s), "velocity ноты — точка p-lock")
        s.setNoteVel(0, nil)
        XCTAssertNil(s.vels)
        XCTAssertFalse(Track.hasManualLocks(s))
        s.setNotes([48, 50])
        XCTAssertEqual(s.lens, [2, 4], "у новой ноты — len шага")
        s.removeNote(1)
        s.removeNote(0)
        XCTAssertTrue(s.notes.isEmpty)
        XCTAssertFalse(s.on, "без нот — без трига")
    }

    func testSetAllLenAndLevelLockClear() {
        var t = Track(index: 0)
        t.withStep(2) { s in
            s.on = true
            s.addNote(48, len: 1, vel: 50)
            s.addNote(52, len: 3, vel: nil)
            s.setAllLen(2)
        }
        XCTAssertNil(t.pages[0][2].lens)
        XCTAssertEqual(t.pages[0][2].noteLen(1), 2)
        XCTAssertEqual(t.pages[0][2].vels, [50, -1], "длина всех не трогает velocity")
        t.clearLock(2, "level")
        XCTAssertNil(t.pages[0][2].vels, "снять Level — снять и velocity нот")
    }

    func testOldStepDecodes() throws {
        let json = #"{"on":true,"len":3,"notes":[48,52],"locks":{}}"#
        let s = try JSONDecoder().decode(Step.self, from: Data(json.utf8))
        XCTAssertNil(s.lens)
        XCTAssertNil(s.vels)
        XCTAssertEqual(s.noteLen(1), 3)
        let back = try JSONDecoder().decode(Step.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func testSnapshotCarriesNotes() {
        var p = project()
        p.tracks[0].withStep(0) { s in
            s.on = true
            s.addNote(48, len: 2, vel: 30)
            s.addNote(60, len: 1, vel: nil)
        }
        let snap = SeqSnapshot(p)
        let d = snap.data
        let i = d.stepIndex(0, slot: 0, 0)
        XCTAssertEqual(d.split[i], 1)
        XCTAssertEqual(d.len[i], 2)
        XCTAssertEqual(d.noteLen[i * SeqData.maxNotes], 2)
        XCTAssertEqual(d.noteLen[i * SeqData.maxNotes + 1], 1)
        XCTAssertEqual(d.noteVel[i * SeqData.maxNotes], 30)
        XCTAssertEqual(d.noteVel[i * SeqData.maxNotes + 1], -1)
        withExtendedLifetime(snap) {}
    }

    /// Нота 48 — 2 шага с velocity ¼ по уровню, нота 60 — velocity 0 (не слышна): держится и звучит только первая.
    func testNoteVelocityAndOwnGate() {
        let core = AudioCore(master: false)
        var p = project()
        p.tracks[0].withStep(0) { s in
            s.on = true
            s.addNote(48, len: 2, vel: quarter)
            s.addNote(60, len: 1, vel: 0)
        }
        core.publish(p, samples: ["k": SampleData(left: [Float](repeating: 1, count: 96000), right: nil)])
        core.events.push(.play(true))
        let o = render(core, frames: 13000)
        XCTAssertEqual(o[100], center * 0.25, accuracy: 0.005)
        XCTAssertEqual(o[11900], center * 0.25, accuracy: 0.005, "своя длина 2 шага")
        XCTAssertLessThan(o[12999], center * 0.25 * 0.995)
    }

    /// Нота 48 — 1 шаг (а шаг держит нота 60 в 2 шага, неслышная): после атаки — сразу Decay.
    func testShortNoteInLongStep() {
        let core = AudioCore(master: false)
        var p = project()
        p.tracks[0].withStep(0) { s in
            s.on = true
            s.addNote(48, len: 1, vel: quarter)
            s.addNote(60, len: 2, vel: 0)
        }
        core.publish(p, samples: ["k": SampleData(left: [Float](repeating: 1, count: 96000), right: nil)])
        core.events.push(.play(true))
        let o = render(core, frames: 13000)
        XCTAssertLessThan(o[11900], center * 0.25 * 0.9, "своя длина 1 шаг — не держится до конца шага ноты 60")
    }
}
