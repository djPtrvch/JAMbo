import XCTest
@testable import Core

final class ClockPlanTests: XCTestCase {
    /// Без игры: тики с темпом проекта (120 BPM — 20,833 мс), ровно, без повторов между вызовами.
    func testFreeRunning() {
        var p = ClockPlan()
        var all: [ClockPlan.Event] = []
        var now: Double = 10
        while now < 11 {
            let r = p.update(now: now, bpm: 120, play: nil, startStop: true)
            XCTAssertFalse(r.flush)
            all.append(contentsOf: r.events)
            now += 1.0 / 60
        }
        XCTAssertTrue(all.allSatisfy { $0.kind == .tick })
        for i in 1..<all.count { XCTAssertEqual(all[i].time - all[i - 1].time, 60.0 / (120 * 24), accuracy: 1e-9) }
    }

    /// PLAY: Start и первый тик — в момент первого шага; дальше 6 тиков на шаг по сетке; стоп — Stop, клок идёт дальше.
    func testStartStop() {
        var p = ClockPlan()
        _ = p.update(now: 10, bpm: 120, play: nil, startStop: true)
        // Шаг 1 звучит в 10,15 — значит шаг 0 (старт) в 10,025; шаг 1/16 при 120 BPM — 0,125 с.
        let g = ClockPlan.Grid(step: 1, time: 10.15, stepDur: 0.125)
        let r = p.update(now: 10.01, bpm: 120, play: g, startStop: true)
        XCTAssertTrue(r.flush)
        let start = r.events.first { $0.kind == .start }
        XCTAssertEqual(start?.time ?? 0, 10.025, accuracy: 1e-9)
        let ticks: [Double] = r.events.filter { $0.kind == .tick }.map { $0.time }
        XCTAssertTrue(ticks.contains { abs($0 - 10.025) < 1e-9 })
        // Тики свободного хода — только раньше старта; после старта — шагом 0,125 / 6.
        let after: [Double] = ticks.filter { $0 >= 10.025 - 1e-9 }
        for i in 1..<after.count { XCTAssertEqual(after[i] - after[i - 1], 0.125 / 6, accuracy: 1e-9) }
        XCTAssertTrue(ticks.filter { $0 < 10.025 }.allSatisfy { $0 < 10.025 - 0.01 })
        // Следующий вызов продолжает сетку без повторов.
        let r2 = p.update(now: 10.03, bpm: 120, play: g, startStop: true)
        XCTAssertFalse(r2.flush)
        XCTAssertEqual((r2.events.first?.time ?? 0) - (after.last ?? 0), 0.125 / 6, accuracy: 1e-9)
        // Стоп.
        let r3 = p.update(now: 10.2, bpm: 120, play: nil, startStop: true)
        XCTAssertEqual(r3.events.first?.kind, .stop)
        XCTAssertTrue(r3.events.dropFirst().allSatisfy { $0.kind == .tick })
        // Без SYNC START/STOP — только тики.
        var q = ClockPlan()
        let r4 = q.update(now: 10, bpm: 120, play: g, startStop: false)
        XCTAssertFalse(r4.events.contains { $0.kind != .tick })
    }
}
