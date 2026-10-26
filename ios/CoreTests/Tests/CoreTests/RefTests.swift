import XCTest
@testable import Core

/// Референс аранжировщика (S15g): место в файле по курсору, A/B, только с таймлайна, петля, данные.
final class RefTests: XCTestCase {
    /// Шаг при 120 BPM — 6000 кадров; такт — 96000.
    private let unit: Float = 1e-6

    /// Сэмпл-рампа: значение кадра i — i·unit (по нему видно, какое место играет).
    private func ramp(_ frames: Int) -> SampleData {
        let l: [Float] = (0..<frames).map { Float($0) * unit }
        return SampleData(left: l, right: l)
    }

    private func project(offset: Double = 0) -> Project {
        var p = Project()
        for t in 0..<p.tracks.count { p.tracks[t].clips = p.tracks[t].clips.map { _ in nil } }
        p.arrange.ref = ArrRef(key: "r", name: "ref.wav", offset: offset)
        return p
    }

    private func core(_ p: Project, b: Bool, arrange: Bool = true, from: Int = 0) -> AudioCore {
        let c = AudioCore()
        c.publish(p, samples: ["r": ramp(400_000)], refB: b)
        if arrange { c.events.push(.arrange(on: true, from: from)) }
        c.events.push(.play(true))
        return c
    }

    /// Блоки по 256: вывод левого канала блока last.
    private func render(_ c: AudioCore, blocks: Int) -> [Float] {
        var l = [Float](repeating: 0, count: 256)
        var r = [Float](repeating: 0, count: 256)
        for _ in 0..<blocks { c.render(frames: 256, left: &l, right: &r) }
        return l
    }

    /// Место в файле по значению рампы.
    private func at(_ v: Float) -> Int { return Int((v / unit).rounded()) }

    func testPlaysByCursorInB() {
        let c = core(project(), b: true)
        let l = render(c, blocks: 20)
        XCTAssertEqual(Double(at(l[0])), Double(19 * 256), accuracy: 3, "с начала таймлайна — с начала файла")
        XCTAssertEqual(at(l[255]) - at(l[0]), 255, "подряд, в своём темпе")
        XCTAssertTrue(c.ref.active)
    }

    func testCursorAndOffset() {
        // С такта 2 (шаг 16 = 2 с), начало файла сдвинуто на 0,5 с: место — 1,5 с.
        let c = core(project(offset: 0.5), b: true, from: 16)
        let l = render(c, blocks: 10)
        XCTAssertEqual(Double(at(l[0])), Double(72000 + 9 * 256), accuracy: 3)
    }

    func testBeforeFileStartIsSilent() {
        let c = core(project(offset: 1), b: true)
        let l = render(c, blocks: 10)
        XCTAssertEqual(l.map { abs($0) }.max() ?? 1, 0, "до начала файла — тишина")
    }

    func testAIsProjectButRefMeters() {
        let c = core(project(), b: false)
        let l = render(c, blocks: 20)
        XCTAssertLessThan(l.map { abs($0) }.max() ?? 1, 1e-6, "A — слышен проект (пустой), референса нет")
        let lv = c.levels
        var peak: Float = 0
        _ = lv.read(since: 0) { b in peak = max(peak, Levels.value(b, Levels.ref, 0)) }
        XCTAssertGreaterThan(peak, 0, "референс идёт и в A: метр Levels.ref")
    }

    func testABSwitchIsSmooth() {
        let c = core(project(), b: false)
        _ = render(c, blocks: 20)
        var p = project()
        p.bpm = c.sequencer.bpm
        c.publish(p, samples: ["r": ramp(400_000)], refB: true)
        let l = render(c, blocks: 1)
        XCTAssertLessThan(l[0], l[255] * 0.1, "B — с подъёмом")
        XCTAssertGreaterThan(c.ref.ab, 0.5)
        let l2 = render(c, blocks: 2)
        XCTAssertEqual(Double(at(l2[0])), Double(22 * 256), accuracy: 3)
    }

    func testOnlyFromTimeline() {
        let c = core(project(), b: true, arrange: false)
        let l = render(c, blocks: 20)
        XCTAssertEqual(l.map { abs($0) }.max() ?? 1, 0, "игра из сетки — референс молчит")
        XCTAssertFalse(c.ref.active)
    }

    func testStopFadesOut() {
        let c = core(project(), b: true)
        _ = render(c, blocks: 20)
        c.events.push(.play(false))
        let l = render(c, blocks: 1)
        XCTAssertGreaterThan(l[0], 0)
        XCTAssertLessThan(abs(l[255]), l[0] * 0.05, "стоп — затухание за блок")
        XCTAssertFalse(c.ref.active)
        let l2 = render(c, blocks: 1)
        XCTAssertEqual(l2.map { abs($0) }.max() ?? 1, 0)
    }

    func testLoopJumpsBack() {
        var p = project()
        p.arrange.loopFrom = 0
        p.arrange.loopTo = 16
        p.arrange.loop = true
        let c = core(p, b: true)
        // Такт — 375 блоков; через 400 блоков курсор снова в начале такта.
        let l = render(c, blocks: 400)
        XCTAssertEqual(Double(at(l[0])), Double(399 * 256 - 96000), accuracy: 3, "после петли — снова с начала")
    }

    func testDataAndKeys() throws {
        var p = project(offset: 1.25)
        p.arrange.ref?.gain = -6
        p.arrange.ref?.bpm = 126
        p.arrange.showRef = true
        XCTAssertTrue(p.sampleKeys.contains("r"), "копия файла — в проекте")
        let back = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.arrange.ref, p.arrange.ref)
        XCTAssertTrue(back.arrange.showRef)
        var a = Arrangement()
        a.ref = ArrRef(key: "x", gain: 12)
        a.repair()
        XCTAssertEqual(a.ref?.gain, 0)
        a.ref?.bpm = -.infinity
        a.repair()
        XCTAssertNil(a.ref?.bpm)
        a.ref = ArrRef(key: "")
        a.repair()
        XCTAssertNil(a.ref)
    }
}
