import XCTest
@testable import Core

/// Миниатюра ENV: точка всегда на кривой (уровень кривой в точке = настоящий уровень ENV), движется без скачков вниз
/// по уровню, форма от длины ноты не зависит.
final class EnvDotTests: XCTestCase {
    /// Настоящий уровень (как ModEngine.env).
    func real(_ a: Double, _ d: Double, _ s: Double, _ r: Double, _ t: Double, _ g: Double) -> Double {
        return EnvDot.curve(a, d, s, r, t, g)
    }

    func testDotOnCurveAtRealLevel() {
        let cases: [(Double, Double, Double, Double)] = [(199, 474, 0, 42), (10, 100, 0.4, 300), (500, 50, 1, 200),
                                                        (2, 800, 0.2, 1000), (50, 0, 0.6, 100)]
        for (a, d, s, r) in cases {
            let gate: Double = a + d + Swift.max(200, (a + d + r) * 0.3)
            for g in [20.0, a * 0.5, a, a + d * 0.3, a + d + 50, 5000] {
                var t = 0.0
                while t < g + r + 50 {
                    let x = EnvDot.x(a, d, s, r, t: t, g: g, gate: gate)
                    let onCurve = EnvDot.curve(a, d, s, r, x, gate)
                    XCTAssertGreaterThanOrEqual(x, 0)
                    XCTAssertLessThanOrEqual(x, gate + r + 1e-9)
                    // Отпущено: уровень точки = настоящий (держится — по времени, до конца условного гейта).
                    if t >= g {
                        XCTAssertEqual(onCurve, real(a, d, s, r, t, g), accuracy: 1e-9, "A\(a) D\(d) S\(s) R\(r) g\(g) t\(t)")
                    } else if t <= gate {
                        XCTAssertEqual(onCurve, real(a, d, s, r, t, g), accuracy: 1e-9)
                    }
                    t += 7
                }
            }
        }
    }

    /// После отпускания точка идёт только вперёд по кривой.
    func testDotMovesForward() {
        let a = 199.0, d = 474.0, s = 0.0, r = 42.0
        let gate: Double = a + d + 200
        for g in [100.0, 300, 700] {
            var last = -1.0
            var t = g
            while t < g + r + 10 {
                let x = EnvDot.x(a, d, s, r, t: t, g: g, gate: gate)
                XCTAssertGreaterThanOrEqual(x, last - 1e-9)
                last = x
                t += 1
            }
        }
    }
}
