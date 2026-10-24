import XCTest
@testable import Core

final class TransitionTests: XCTestCase {
    private let last = Params.patternSlots - 1

    /// Проект: у дорожки i в активном клипе триг на шаге 0, сэмпл "old{i}", BPM bpm.
    private func project(_ name: String, bpm: Double, tracks: Int = 8, trigs: [Int]) -> Project {
        var p = Project()
        while p.tracks.count < tracks { p.tracks.append(Track(index: p.tracks.count)) }
        p.bpm = bpm
        for i in p.tracks.indices {
            p.tracks[i].sample = "\(name)\(i)"
            if trigs.contains(i) { p.tracks[i].clips[0]!.pages[0][0].on = true }
        }
        return p
    }

    func testMixPutsActiveClipsIntoPrev() {
        var old = project("old", bpm: 100, trigs: [0, 1, 2])
        old.tracks[1].stopped = true
        old.tracks[2].mute = true
        old.scale = 3
        let next = project("new", bpm: 140, trigs: [0])
        let (p, tr) = old.mixed(into: next, playing: true, leaving: [Bool](repeating: false, count: 8))
        XCTAssertTrue(p.prevRow)
        XCTAssertEqual(p.scenes[last].name, "PREV")
        XCTAssertEqual(tr.moves.map { $0.track }, [0, 1, 2])
        // Звучала только дорожка 0; дорожка 1 стояла — в PREV, но не запущена.
        XCTAssertFalse(p.tracks[0].stopped)
        XCTAssertTrue(p.tracks[1].stopped)
        XCTAssertEqual(p.tracks[0].slot, last)
        // Пока играет PREV — звук старой дорожки, свой — в home.
        XCTAssertEqual(p.tracks[0].sample, "old0")
        XCTAssertEqual(p.tracks[0].home?.sample, "new0")
        // Без тригов — ячейка PREV пустая, своя ячейка и свой звук.
        XCTAssertNil(p.tracks[5].clips[last])
        XCTAssertEqual(p.tracks[5].sample, "new5")
        XCTAssertTrue(p.tracks[5].stopped)
        // Mute — старого проекта; гамма — старого лидера; общие настройки — старые.
        XCTAssertTrue(p.tracks[2].mute)
        XCTAssertEqual(p.scale, 3)
        XCTAssertEqual(p.bpm, 100)
        XCTAssertEqual(tr.to.bpm, 140)
    }

    /// Гамма клипа: PREV — старого проекта, новый клип — свой (нарезка звучит в гамме своего клипа).
    func testClipKeyPerClip() {
        var old = project("old", bpm: 100, trigs: [0])
        old.tracks[0].clips[0]!.scale = 3
        old.tracks[0].clips[0]!.root = 2
        var next = project("new", bpm: 120, trigs: [0])
        next.tracks[0].clips[0]!.scale = 5
        next.tracks[0].clips[0]!.root = 7
        var (p, _) = old.mixed(into: next, playing: true, leaving: [])
        XCTAssertTrue(p.clipKey(0, prev: true) == (3, 2), "PREV — гамма старого клипа")
        XCTAssertTrue(p.clipKey(0, prev: false) == (p.scale, p.root), "играет PREV — свой звук без своего клипа")
        p.tracks[0].activate(0)
        XCTAssertTrue(p.clipKey(0, prev: false) == (5, 7), "новый клип — своя гамма")
    }

    func testNoPlayLeavesAllStopped() {
        let old = project("old", bpm: 100, trigs: [0])
        let (p, _) = old.mixed(into: project("new", bpm: 120, trigs: []), playing: false, leaving: [])
        XCTAssertTrue(p.tracks[0].stopped)
        XCTAssertEqual(p.tracks[0].slot, last)
    }

    func testRowsDuringTransition() {
        let old = project("old", bpm: 100, trigs: [0])
        var (p, _) = old.mixed(into: project("new", bpm: 120, trigs: []), playing: true, leaving: [])
        XCTAssertEqual(p.visibleRows, 1)
        XCTAssertEqual(p.rowLimit, last)
        // Пустые ячейки PREV не заполняются; строк проекта — до 15, PREV остаётся на месте.
        XCTAssertNil(p.tracks[3].clips[last])
        for _ in 0..<20 { p.addRow() }
        XCTAssertEqual(p.visibleRows, last)
        XCTAssertNotNil(p.tracks[0].clips[last]?.src)
        p.deleteRow(0)
        XCTAssertNotNil(p.tracks[0].clips[last]?.src)
        XCTAssertEqual(p.tracks[0].slot, last)
        p.duplicateRow(0)
        XCTAssertNotNil(p.tracks[0].clips[last]?.src)
        XCTAssertEqual(p.tracks[0].slot, last)
    }

    func testLaunchSwapsSound() {
        let old = project("old", bpm: 100, trigs: [0])
        var (p, _) = old.mixed(into: project("new", bpm: 120, trigs: [0]), playing: true, leaving: [])
        // Правка звука, пока играет PREV, — звуку старой дорожки.
        p.tracks[0].params["smp.tune"] = 5
        p.tracks[0].activate(0)
        XCTAssertEqual(p.tracks[0].sample, "new0")
        XCTAssertNil(p.tracks[0].home)
        XCTAssertNotEqual(p.tracks[0].params["smp.tune"], 5)
        XCTAssertEqual(p.tracks[0].sound(prev: true)?.params["smp.tune"], 5)
        XCTAssertEqual(p.tracks[0].sound(prev: false)?.sample, "new0")
        p.tracks[0].activate(last)
        XCTAssertEqual(p.tracks[0].sample, "old0")
        XCTAssertEqual(p.tracks[0].params["smp.tune"], 5)
        XCTAssertEqual(p.tracks[0].sound(prev: false)?.sample, "new0")
    }

    func testEndAndSave() {
        var next = project("new", bpm: 140, tracks: 8, trigs: [0])
        next.tracks[0].clips[last] = Clip()
        next.tracks[0].clips[last]!.pages[0][3].on = true
        next.scenes[last].name = "END"
        next.scale = 5
        let old = project("old", bpm: 100, tracks: 10, trigs: [0, 9])
        var (p, tr) = old.mixed(into: next, playing: true, leaving: [])
        XCTAssertEqual(p.tracks.count, 10)
        XCTAssertTrue(p.prevPlaying)
        let saved = p.forSave(tr)
        XCTAssertFalse(saved.prevRow)
        XCTAssertEqual(saved.bpm, 140)
        XCTAssertEqual(saved.scale, 5)
        XCTAssertEqual(saved.scenes[last].name, "END")
        XCTAssertEqual(saved.tracks[0].clips[last], next.tracks[0].clips[last])
        XCTAssertEqual(saved.tracks[0].sample, "new0")
        XCTAssertEqual(saved.tracks[0].slot, 0)
        XCTAssertNil(saved.tracks[0].home)
        XCTAssertEqual(saved.tracks.count, 8)
        XCTAssertTrue(saved.tracks.allSatisfy { t in t.clips.allSatisfy { $0?.src == nil } })
        // Конец перехода во время игры: гамма играющего лидера остаётся.
        p.endMix(tr)
        XCTAssertEqual(p.scale, 0)
        XCTAssertEqual(p.tracks[0].sample, "new0")
        XCTAssertTrue(p.tracks[0].stopped)
        XCTAssertFalse(p.prevPlaying)
    }

    func testSampleKeysIncludePrev() {
        let old = project("old", bpm: 100, trigs: [0])
        let (p, _) = old.mixed(into: project("new", bpm: 120, trigs: [0]), playing: true, leaving: [])
        XCTAssertTrue(p.sampleKeys.contains("old0"))
        XCTAssertTrue(p.sampleKeys.contains("new0"))
    }
}

extension TransitionTests {
    /// Снимок звука: второй звук дорожки (клип PREV) действует, пока в колбэке активна ячейка PREV.
    func testSnapshotSoundBySlot() {
        let last = Params.patternSlots - 1
        var old = Project()
        old.tracks[0].clips[0]!.pages[0][0].on = true
        old.tracks[0].params["pitch"] = 7
        old.tracks[0].sample = "mi:17"
        var next = Project()
        next.tracks[0].params["pitch"] = -3
        let (p, _) = old.mixed(into: next, playing: true, leaving: [])
        let slots = UnsafeMutablePointer<Int>.allocate(capacity: Params.maxTracks)
        defer { slots.deallocate() }
        slots.initialize(repeating: 0, count: Params.maxTracks)
        let snap = SoundSnapshot(p, samples: [:], map: .chromatic, slots: slots)
        let d = snap.data
        XCTAssertEqual(d.alt[0], 1)
        XCTAssertEqual(d.alt[1], 0)
        XCTAssertEqual(d.param(0, VoiceParam.pitch), -3)
        XCTAssertEqual(d.sound[d.s(0)], SoundKey.hash(""))
        slots[0] = last
        XCTAssertEqual(d.param(0, VoiceParam.pitch), 7)
        XCTAssertEqual(d.sound[d.s(0)], SoundKey.hash("mi:17"))
        // Без второго звука ячейка PREV ничего не меняет.
        slots[1] = last
        XCTAssertEqual(d.s(1), 1)
        // После конца перехода второго звука нет.
        var q = p
        q.endMix(MixTransition(from: MixGlobals(p), to: MixGlobals(p)))
        let snap2 = SoundSnapshot(q, samples: [:], map: .chromatic, slots: slots)
        XCTAssertEqual(snap2.data.alt[0], 0)
        XCTAssertEqual(snap2.data.param(0, VoiceParam.pitch), -3)
    }
}
