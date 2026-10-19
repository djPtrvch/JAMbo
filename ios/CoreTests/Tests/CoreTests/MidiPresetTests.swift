import XCTest
@testable import Core

final class MidiPresetTests: XCTestCase {
    func testSaveRenameDelete() {
        var b = MidiPresetBook()
        XCTAssertEqual(b.nextName, "Controller 1")
        let m = MidiMapping(src: MidiSource(type: .cc, ch: 0, num: 1), target: .knob(0), continuous: true)
        XCTAssertEqual(b.save("  Twister  ", [m]), "Twister")
        XCTAssertNil(b.save("   ", [m]))
        XCTAssertEqual(b.preset("Twister")?.mappings, [m])
        // То же имя — перезапись.
        b.save("Twister", [])
        XCTAssertEqual(b.list.count, 1)
        XCTAssertEqual(b.preset("Twister")?.mappings.count, 0)
        b.save("Launch", [m])
        XCTAssertNil(b.rename("Launch", to: "Twister"))
        XCTAssertEqual(b.rename("Launch", to: "LPX"), "LPX")
        XCTAssertEqual(b.save(String(repeating: "x", count: 50), []), String(repeating: "x", count: 40))
        b.delete("LPX")
        XCTAssertNil(b.preset("LPX"))
        let back = MidiPresetBook.decode(b.encode())
        XCTAssertEqual(back, b)
        XCTAssertEqual(MidiPresetBook.decode(nil), MidiPresetBook())
    }
}
