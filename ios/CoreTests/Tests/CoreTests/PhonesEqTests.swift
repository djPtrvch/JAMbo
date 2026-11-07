import XCTest
@testable import Core

/// Коррекция наушников: предусиление, профиль Sony WH-1000XM4, правки полос (обработка — MonitorTests).
final class PhonesEqTests: XCTestCase {
    private func sonyEq() -> Eq {
        var e = Eq()
        e.apply(EqPresetBook.sonyXM4, tracks: 0)
        return e
    }

    func testPreamp() {
        XCTAssertEqual(EqSpec.preamp(Eq()), 0)
        let e: Eq = sonyEq()
        XCTAssertEqual(e.bands.compactMap { $0 }.count, 10)
        let pre: Double = EqSpec.preamp(e)
        XCTAssertLessThan(pre, -5.5)
        XCTAssertGreaterThan(pre, -6.5)
        var off = e
        off.on = false
        XCTAssertEqual(EqSpec.preamp(off), 0)
        // Только срезы — подъёма нет.
        var cut = Eq()
        cut.bands[0] = EqBand(type: EqSpec.lowCut, freq: 100, gain: 0, q: 0.7)
        XCTAssertEqual(EqSpec.preamp(cut), 0)
    }

    func testEqEdits() {
        var e = Eq()
        let k: Int = e.addBand(freq: 5, gain: 30)
        XCTAssertEqual(k, 0)
        XCTAssertEqual(e.bands[0]?.freq, EqSpec.freqMin)
        XCTAssertEqual(e.bands[0]?.gain, EqSpec.gainMax)
        e.setBand(0, gain: 1.234)
        XCTAssertEqual(e.bands[0]?.gain, 1.2)
        e.setType(0, -1)
        XCTAssertEqual(e.bands[0]?.type, EqSpec.types.count - 1)
        e.toggleBand(0)
        XCTAssertEqual(e.bands[0]?.on, false)
        e.deleteBand(0)
        XCTAssertNil(e.bands[0])
    }
}
