import XCTest
@testable import Core

/// Профили коррекции наушников в файле: чтение AutoEQ, подгонка 10 фильтров в 8 полос, запись и чтение обратно.
final class PhonesProfileTests: XCTestCase {
    static let sony: String = """
    Preamp: -6.1 dB
    Filter 1: ON LSC Fc 105 Hz Gain -4.2 dB Q 0.70
    Filter 2: ON PK Fc 143 Hz Gain -5.2 dB Q 1.10
    Filter 3: ON PK Fc 2289 Hz Gain 6.1 dB Q 1.57
    Filter 4: ON PK Fc 56 Hz Gain 1.2 dB Q 1.19
    Filter 5: ON PK Fc 5144 Hz Gain -3.2 dB Q 6.00
    Filter 6: ON HSC Fc 10000 Hz Gain -1.0 dB Q 0.70
    Filter 7: ON PK Fc 407 Hz Gain 1.7 dB Q 3.14
    Filter 8: ON PK Fc 6715 Hz Gain 3.0 dB Q 5.99
    Filter 9: ON PK Fc 1007 Hz Gain 1.0 dB Q 3.41
    Filter 10: ON PK Fc 576 Hz Gain -1.2 dB Q 3.55
    Filter 11: OFF PK Fc 100 Hz Gain 9.0 dB Q 1.00
    """

    private func curve(_ bands: [EqBand]) -> [Double] {
        let hz: [Double] = (0..<200).map { 20 * pow(1000, Double($0) / 199) }
        return PhonesFit.curve(bands, hz)
    }

    func testParseAndFit() {
        let f = PhonesProfile.parse(PhonesProfileTests.sony)
        XCTAssertEqual(f.count, 10, "выключенный фильтр пропущен")
        XCTAssertEqual(f[0].type, EqSpec.lowShelf)
        XCTAssertEqual(f[2].freq, 2289)
        let (e, fitted) = PhonesProfile.eq(f)
        XCTAssertTrue(fitted)
        let bands: [EqBand] = e.bands.compactMap { $0 }
        XCTAssertEqual(bands.count, 8)
        let a: [Double] = curve(f.map { $0.band })
        let b: [Double] = curve(bands)
        let worst: Double = zip(a, b).map { abs($0 - $1) }.max() ?? 99
        XCTAssertLessThan(worst, 1.3, "8 полос повторяют кривую 10 фильтров")
    }

    func testTextRoundTrip() {
        var e = Eq()
        e.apply(EqPresetBook.sonyXM4, tracks: 0)
        e.bands[7] = EqBand(type: EqSpec.lowCut, freq: 25, gain: 0, q: 0.71, slope: 1)
        let t: String = PhonesProfile.text(e)
        XCTAssertTrue(t.hasPrefix("Preamp: -"))
        let f = PhonesProfile.parse(t)
        XCTAssertEqual(f.count, 9, "срез 24 dB/окт — два фильтра")
        XCTAssertEqual(f.filter { $0.type == EqSpec.lowCut }.count, 2)
        // До 8 фильтров — как есть.
        let (back, fitted) = PhonesProfile.eq(Array(f.prefix(8)))
        XCTAssertFalse(fitted)
        XCTAssertEqual(back.bands.compactMap { $0 }.count, 8)
        XCTAssertEqual(PhonesProfile.name(fromFile: "Sony WH-1000XM4 ParametricEQ.txt"), "Sony WH-1000XM4")
        XCTAssertEqual(PhonesProfile.name(fromFile: " ParametricEQ.txt"), "Phones")
        XCTAssertTrue(PhonesProfile.parse("hello\nPreamp: 1 dB").isEmpty)
    }
}
