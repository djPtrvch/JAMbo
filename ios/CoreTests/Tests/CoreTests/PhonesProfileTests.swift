import XCTest
@testable import Core

/// Профили коррекции наушников в файле: чтение AutoEQ (10 фильтров — как есть, больше — подгонка в 10 полос), запись и чтение обратно.
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
        // 10 фильтров — без подгонки, полосы — как в пресете Sony.
        let (e, fitted) = PhonesProfile.eq(f)
        XCTAssertFalse(fitted)
        let bands: [EqBand] = e.bands.compactMap { $0 }
        XCTAssertEqual(bands.count, 10)
        let preset: [EqBand] = EqPresetBook.sonyXM4.bands.compactMap { $0 }
        XCTAssertEqual(bands.sorted { $0.freq < $1.freq }, preset)
        // 12 фильтров — подгонка 10 полос под их кривую.
        var more: [PhonesProfile.Filter] = f
        more.append(PhonesProfile.Filter(type: EqSpec.bell, freq: 3200, gain: 0.8, q: 4))
        more.append(PhonesProfile.Filter(type: EqSpec.bell, freq: 260, gain: -0.7, q: 3))
        let (e2, fitted2) = PhonesProfile.eq(more)
        XCTAssertTrue(fitted2)
        let bands2: [EqBand] = e2.bands.compactMap { $0 }
        XCTAssertEqual(bands2.count, 10)
        let a: [Double] = curve(more.map { $0.band })
        let b: [Double] = curve(bands2)
        let worst: Double = zip(a, b).map { abs($0 - $1) }.max() ?? 99
        XCTAssertLessThan(worst, 1.3, "10 полос повторяют кривую 12 фильтров")
    }

    func testOldEightBands() {
        // EQ, сохранённый с 8 местами под полосы, читается с 10.
        var e = Eq()
        e.bands = Array(e.bands.prefix(8))
        e.bands[0] = EqBand(type: EqSpec.bell, freq: 100, gain: 3, q: 1)
        let d: Data = try! JSONEncoder().encode(e)
        let back: Eq = try! JSONDecoder().decode(Eq.self, from: d)
        XCTAssertEqual(back.bands.count, EqSpec.bands)
        XCTAssertEqual(back.bands[0], e.bands[0])
        // Прежний Sony (8 полос) в списке заменяется точным.
        var book = EqPresetBook()
        book.list = [EqPreset(name: EqPresetBook.sonyXM4.name, bands: Array(EqPresetBook.sonyXM4.bands.prefix(8)))]
        XCTAssertTrue(book.upgradeSonyXM4())
        XCTAssertEqual(book.list[0], EqPresetBook.sonyXM4)
        XCTAssertFalse(book.upgradeSonyXM4())
    }

    func testTextRoundTrip() {
        var e = Eq()
        e.apply(EqPresetBook.sonyXM4, tracks: 0)
        e.bands[7] = EqBand(type: EqSpec.lowCut, freq: 25, gain: 0, q: 0.71, slope: 1)
        let t: String = PhonesProfile.text(e)
        XCTAssertTrue(t.hasPrefix("Preamp: -"))
        let f = PhonesProfile.parse(t)
        XCTAssertEqual(f.count, 11, "срез 24 dB/окт — два фильтра")
        XCTAssertEqual(f.filter { $0.type == EqSpec.lowCut }.count, 2)
        // До 10 фильтров — как есть.
        let (back, fitted) = PhonesProfile.eq(Array(f.prefix(10)))
        XCTAssertFalse(fitted)
        XCTAssertEqual(back.bands.compactMap { $0 }.count, 10)
        XCTAssertEqual(PhonesProfile.name(fromFile: "Sony WH-1000XM4 ParametricEQ.txt"), "Sony WH-1000XM4")
        XCTAssertEqual(PhonesProfile.name(fromFile: " ParametricEQ.txt"), "Phones")
        XCTAssertTrue(PhonesProfile.parse("hello\nPreamp: 1 dB").isEmpty)
    }
}
