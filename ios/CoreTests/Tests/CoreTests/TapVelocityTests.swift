import XCTest
@testable import Core

/// KEY VELOCITY по акселерометру (S12): сила по толчку в окне касания.
final class TapVelocityTests: XCTestCase {
    func testVelocityScale() {
        XCTAssertEqual(TapVelocity.velocity(peak: 0), 0.2)
        XCTAssertEqual(TapVelocity.velocity(peak: TapVelocity.gMin), 0.2)
        XCTAssertEqual(TapVelocity.velocity(peak: TapVelocity.gMax), 1)
        XCTAssertEqual(TapVelocity.velocity(peak: 5), 1)
        let mid = (TapVelocity.gMin * TapVelocity.gMax).squareRoot()
        XCTAssertEqual(TapVelocity.velocity(peak: mid), 0.6, accuracy: 1e-9, "середина — логарифмически")
        XCTAssertEqual(TapVelocity.velocity(peak: .nan), 0.2)
    }

    func testPeakWindow() {
        let s: [(t: Double, g: Double)] = [(0.90, 0.9), (0.97, 0.1), (1.005, 0.3), (1.010, 0.2), (1.02, 0.8)]
        XCTAssertEqual(TapVelocity.peak(s, at: 1.0), 0.3, "40 мс до и 15 мс после касания")
        XCTAssertNil(TapVelocity.peak(s, at: 2.0), "нет отсчётов — нет датчика")
    }
}
