import XCTest
@testable import Core

final class ClockFollowerTests: XCTestCase {
    /// Внешний клок 123,4 BPM с дрожанием ±1 мс: темп — 123,4 (точнее целого), шаги — по тикам.
    func testTempoAndSteps() {
        var f = ClockFollower()
        let iv: Double = 60 / (123.4 * 24)
        var rng: UInt32 = 1
        var t: Double = 5
        for _ in 0..<100 {
            rng = rng &* 1664525 &+ 1013904223
            let jitter: Double = (Double(rng % 2001) / 1000 - 1) / 1000
            _ = f.tick(at: t + jitter)
            t += iv
        }
        XCTAssertEqual(f.tempo ?? 0, 123.4, accuracy: 0.2)
        XCTAssertTrue(f.alive(now: t))
        XCTAssertFalse(f.alive(now: t + 0.6))
    }

    /// Start — игра с первого тика после Start; шаг k — через 6k тиков; Stop — стоп; Continue — старт сразу.
    func testTransport() {
        var f = ClockFollower()
        let iv: Double = 60 / (120.0 * 24)
        var t: Double = 1
        for _ in 0..<24 {
            _ = f.tick(at: t)
            t += iv
        }
        XCTAssertNil(f.transport(.start, at: t - iv / 2, playing: false))
        let a = f.tick(at: t)
        XCTAssertEqual(a, .start(at: t))
        f.started(at: t)
        XCTAssertEqual(f.stepTime(0) ?? 0, t, accuracy: 1e-9)
        XCTAssertEqual(f.stepTime(4) ?? 0, t + 24 * iv, accuracy: 1e-6)
        // Дальше тики: шаг 2 — тик 12.
        for _ in 0..<12 {
            t += iv
            XCTAssertNil(f.tick(at: t))
        }
        XCTAssertEqual(f.stepTime(2) ?? 0, t, accuracy: 1e-6)
        XCTAssertEqual(f.transport(.stop, at: t, playing: true), .stop)
        XCTAssertEqual(f.transport(.cont, at: t, playing: false), .start(at: t))
        XCTAssertNil(f.transport(.cont, at: t, playing: true))
        // Start во время игры — стоп, игра — со следующего тика.
        XCTAssertEqual(f.transport(.start, at: t, playing: true), .stop)
        XCTAssertEqual(f.tick(at: t + iv), .start(at: t + iv))
        f.lose()
        XCTAssertNil(f.tempo)
    }

    /// PLAY своей кнопкой между тиками — шаг 0 на ближайшем тике.
    func testOwnStart() {
        var f = ClockFollower()
        let iv: Double = 60 / (100.0 * 24)
        var t: Double = 2
        for _ in 0..<30 {
            _ = f.tick(at: t)
            t += iv
        }
        let last: Double = t - iv
        f.started(at: last + iv * 2.2)
        XCTAssertEqual(f.stepTime(0) ?? 0, last + iv * 2, accuracy: 1e-6)
        XCTAssertEqual(f.stepTime(1) ?? 0, last + iv * 8, accuracy: 1e-6)
    }

    /// Клок пропал во время игры (устройство отключили) и вернулся: без новой привязки шаги не по тикам; первые тики —
    /// без темпа; started — шаг снова на ближайшем тике.
    func testReconnect() {
        var f = ClockFollower()
        let iv: Double = 60 / (120.0 * 24)
        var t: Double = 1
        for _ in 0..<30 {
            _ = f.tick(at: t)
            t += iv
        }
        f.started(at: t - iv)
        XCTAssertTrue(f.anchored)
        f.lose()
        XCTAssertFalse(f.anchored)
        // Через 3 с клок снова идёт.
        t += 3
        for _ in 0..<3 {
            _ = f.tick(at: t)
            t += iv
        }
        XCTAssertNil(f.tempo)
        XCTAssertFalse(f.alive(now: t))
        for _ in 0..<10 {
            _ = f.tick(at: t)
            t += iv
        }
        XCTAssertEqual(f.tempo ?? 0, 120, accuracy: 0.01)
        XCTAssertTrue(f.alive(now: t))
        let last: Double = t - iv
        f.started(at: last + iv * 0.9)
        XCTAssertTrue(f.anchored)
        XCTAssertEqual(f.stepTime(0) ?? 0, last + iv, accuracy: 1e-6)
    }
}
