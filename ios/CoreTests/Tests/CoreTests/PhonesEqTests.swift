import XCTest
@testable import Core

/// Коррекция наушников: предусиление, профиль Sony WH-1000XM4, обработка и пауза на экспорт.
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

    /// Пик синуса после n отсчётов разгона, dB.
    private func run(_ ph: PhonesEq, hz: Double) -> Double {
        let n = 256
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        var peak: Float = 0
        var t = 0
        for block in 0..<200 {
            for i in 0..<n {
                let v = Float(0.5 * sin(2 * Double.pi * hz * Double(t) / 48000))
                l[i] = v
                r[i] = v
                t += 1
            }
            ph.process(l, r, n)
            if block >= 150 { for i in 0..<n { peak = max(peak, abs(l[i])) } }
        }
        return 20 * log10(Double(peak) / 0.5)
    }

    func testProcess() {
        let ph = PhonesEq(sampleRate: 48000)
        // Без параметров — без изменений.
        XCTAssertEqual(run(ph, hz: 1000), 0, accuracy: 0.05)
        let e: Eq = sonyEq()
        ph.publish(e)
        let pre: Double = EqSpec.preamp(e)
        let at: Double = EqCoeffs.response(e.bands[4]!, hz: 2273)
        // Подъём на 2,3 кГц почти съеден предусилением; выход не выше 0 dB к входу.
        let g: Double = run(ph, hz: 2273)
        XCTAssertLessThan(g, 0.3)
        XCTAssertGreaterThan(g, pre + at - 1.5)
        // Экспорт: коррекция и предусиление выключены.
        ph.paused.store(1)
        XCTAssertEqual(run(ph, hz: 2273), 0, accuracy: 0.05)
        ph.paused.store(0)
        // BYPASS — без изменений.
        var off = e
        off.on = false
        ph.publish(off)
        XCTAssertEqual(run(ph, hz: 2273), 0, accuracy: 0.05)
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
