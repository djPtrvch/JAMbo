import XCTest
@testable import Core

/// IMPORT строк другого проекта и звук у клипа.
final class ImportRowsTests: XCTestCase {
    private func project(_ name: String, trigsRows: [Int], tracks: Int = 8) -> Project {
        var p = Project()
        while p.tracks.count < tracks { p.tracks.append(Track(index: p.tracks.count)) }
        for i in p.tracks.indices { p.tracks[i].sample = "\(name)\(i)" }
        for r in trigsRows {
            if r > 0 { p.addRow() }
            p.tracks[0].clips[r]!.pages[0][0].on = true
        }
        return p
    }

    /// Одна строка — импорт в новую строку 2; звук клипа — свой (у столбца другой).
    func testImportIntoNewRow() {
        var p = project("a", trigsRows: [0])
        let o = project("b", trigsRows: [0, 1])
        XCTAssertEqual(p.importRows(from: o), 2)
        XCTAssertEqual(p.visibleRows, 3)
        XCTAssertTrue(p.tracks[0].clips[1]!.hasTrigs)
        XCTAssertEqual(p.tracks[0].clips[1]!.src?.sample, "b0")
        XCTAssertEqual(p.tracks[0].sample, "a0", "звук дорожки свой")
        XCTAssertTrue(p.tracks[0].clips[0]!.hasTrigs, "своя строка не тронута")
    }

    /// Пустая первая строка не занимается; свободные строки после заполненных — заняты.
    func testFreeRowsAfterLast() {
        var p = project("a", trigsRows: [])
        p.addRow()
        p.addRow()
        XCTAssertEqual(p.visibleRows, 3)
        let o = project("b", trigsRows: [0])
        XCTAssertEqual(p.importRows(from: o), 1)
        XCTAssertFalse(p.tracks[0].clips[0]!.hasTrigs)
        XCTAssertTrue(p.tracks[0].clips[1]!.hasTrigs)
        XCTAssertEqual(p.visibleRows, 3)
    }

    /// Дорожек больше — добавляются со звуком дорожки другого проекта, клипы без своего звука.
    func testAddsTracks() {
        var p = project("a", trigsRows: [0])
        var o = project("b", trigsRows: [0], tracks: 10)
        o.tracks[9].clips[0]!.pages[0][3].on = true
        p.importRows(from: o)
        XCTAssertEqual(p.tracks.count, 10)
        XCTAssertEqual(p.tracks[9].sample, "b9")
        XCTAssertNil(p.tracks[9].clips[1]!.src)
    }

    /// Запуск клипа со своим звуком: звук дорожки — его, правки — в него; обратно — свой звук дорожки.
    func testClipSoundFollowsActivation() {
        var p = project("a", trigsRows: [0])
        p.importRows(from: project("b", trigsRows: [0]))
        p.tracks[0].activate(1)
        XCTAssertEqual(p.tracks[0].sample, "b0")
        p.tracks[0].params["pan"] = 40
        p.tracks[0].activate(0)
        XCTAssertEqual(p.tracks[0].sample, "a0")
        XCTAssertNil(p.tracks[0].home)
        XCTAssertEqual(p.tracks[0].clips[1]!.src?.params["pan"], 40)
        // Копия активного клипа — с правками звука.
        p.tracks[0].activate(1)
        p.tracks[0].params["pan"] = 20
        XCTAssertEqual(p.tracks[0].clipCopy(1)?.src?.params["pan"], 20)
    }

    /// Снимок звука: второй звук — у следующего клипа, и он остаётся на втором звуке после запуска.
    func testSnapshotNextClip() {
        var p = project("a", trigsRows: [0])
        p.importRows(from: project("b", trigsRows: [0]))
        p.tracks[0].params["pitch"] = 2
        p.tracks[0].clips[1]!.src!.params["pitch"] = 9
        let slots = UnsafeMutablePointer<Int>.allocate(capacity: Params.maxTracks)
        defer { slots.deallocate() }
        slots.initialize(repeating: 0, count: Params.maxTracks)
        let s1 = SoundSnapshot(p, samples: [:], map: .chromatic, slots: slots, next: [1])
        XCTAssertEqual(s1.data.param(0, VoiceParam.pitch), 2)
        slots[0] = 1
        XCTAssertEqual(s1.data.param(0, VoiceParam.pitch), 9)
        p.tracks[0].activate(1)
        let s2 = SoundSnapshot(p, samples: [:], map: .chromatic, slots: slots, next: [0], keepAlt: s1.altKeep)
        XCTAssertEqual(s2.data.s(0), Params.maxTracks)
        XCTAssertEqual(s2.data.param(0, VoiceParam.pitch), 9)
        slots[0] = 0
        XCTAssertEqual(s2.data.param(0, VoiceParam.pitch), 2)
    }
}
