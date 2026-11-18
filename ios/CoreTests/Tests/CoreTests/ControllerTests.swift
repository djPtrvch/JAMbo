import XCTest
@testable import Core

/// SysEx в UMP и JAMboPAD (SET_SCALE, SET_MIDI_OUT, ROOT, пресет SMC-PAD ×2).
final class ControllerTests: XCTestCase {
    /// 5 байт — одно сообщение; 8 — начало и конец; 13 — начало, продолжение, конец; чтение собирает обратно.
    func testSysExRoundTrip() {
        for len in [0, 5, 6, 8, 13] {
            let bytes: [UInt8] = (0..<len).map { UInt8($0 * 9 % 128) }
            let w: [UInt32] = SysEx7.words(bytes)
            XCTAssertEqual(w.count, max(1, (len + 5) / 6) * 2)
            var r = SysExReader()
            var got: [UInt8]? = nil
            var i: Int = 0
            while i < w.count {
                if let b = r.feed(w[i], w[i + 1]) { got = b }
                i += 2
            }
            XCTAssertEqual(got, bytes)
        }
        XCTAssertEqual(SysEx7.words([1, 2, 3, 4, 5])[0] >> 20, 0x300)
        XCTAssertEqual((SysEx7.words([UInt8](repeating: 1, count: 8))[0] >> 20) & 0xF, 1)
    }

    /// Продолжение без начала — не SysEx; длиннее предела — отбрасывается.
    func testSysExReaderGuards() {
        var r = SysExReader()
        let w: [UInt32] = SysEx7.words([UInt8](repeating: 1, count: 8))
        XCTAssertNil(r.feed(w[2], w[3]))
        let big: [UInt32] = SysEx7.words([UInt8](repeating: 2, count: SysExReader.maxBytes + 10))
        var got: [UInt8]? = nil
        var i: Int = 0
        while i < big.count {
            if let b = r.feed(big[i], big[i + 1]) { got = b }
            i += 2
        }
        XCTAssertNil(got)
    }

    /// Major от C, октава 3: маска 0xAB5 → 35 15 (пример из docs/jambo.md).
    func testSetScale() {
        let pad = JamboPad()
        XCTAssertEqual(JamboPad.mask(scale: 0), 0xAB5)
        XCTAssertEqual(pad.stateSysEx(ControllerState(root: 0, scale: 0, octave: 3)), [0x7D, 0x4A, 0x50, 0x0C, 0, 0x35, 0x15, 3])
        let chr: [UInt8]? = pad.stateSysEx(ControllerState(root: 14, scale: 10, octave: 9))
        XCTAssertEqual(chr, [0x7D, 0x4A, 0x50, 0x0C, 2, 0x7F, 0x1F, 7])
    }

    func testMidiOutAndRoot() {
        XCTAssertEqual(JamboPad.midiOut(thru: 2, controls: true), [0x7D, 0x4A, 0x50, 0x0D, 2, 1])
        XCTAssertEqual(JamboPad.midiOut(thru: 5, controls: false), [0x7D, 0x4A, 0x50, 0x0D, 2, 0])
        let pad = JamboPad()
        XCTAssertEqual(pad.event([0x7D, 0x4A, 0x50, 0x65, 7]), .root(7))
        XCTAssertNil(pad.event([0x7D, 0x4A, 0x50, 0x65, 12]))
        XCTAssertNil(pad.event([0x7D, 0x4A, 0x50, 0x4D, 0]))
        XCTAssertNil(pad.event([0x00, 0x20, 0x29, 0x65, 1]))
        XCTAssertEqual(pad.event([0x7D, 0x4A, 0x50, 0x67, 1, 0x2D, 0x0B]), .scale(1))
        XCTAssertNil(pad.event([0x7D, 0x4A, 0x50, 0x67, 11, 0, 0]))
        XCTAssertTrue(pad.owns("SMC-PAD"))
        XCTAssertTrue(pad.owns("JAMboPAD L"))
        XCTAssertFalse(pad.owns("Launchpad X"))
    }

    /// Пресет по таблице раскладки: источники не повторяются, цели — существующие, обратная связь — на все SMC-PAD.
    func testPreset() throws {
        let p: MidiPreset = try XCTUnwrap(JamboPad().preset)
        XCTAssertEqual(p.name, "SMC-PAD ×2")
        XCTAssertTrue(Controllers.isBuiltIn("SMC-PAD ×2"))
        XCTAssertEqual(p.mappings.count, 16 + 48 + 6 + 16 + 10)
        XCTAssertEqual(Set(p.mappings.map { $0.src }).count, p.mappings.count)
        XCTAssertTrue(p.mappings.allSatisfy { $0.port == .controller("JAMboPAD") && $0.input == nil && $0.cond == .global })
        func target(_ t: MidiSourceType, _ ch: Int, _ n: Int) -> MidiTarget? {
            return p.mappings.first { $0.src == MidiSource(type: t, ch: ch, num: n) }?.target
        }
        XCTAssertEqual(target(.cc, 0, 6), .knob(6))
        XCTAssertEqual(p.mappings.first { $0.target == .knob(6) }?.control, .abs)
        XCTAssertEqual(target(.note, 1, 36), .button("STEP 1"))
        XCTAssertEqual(target(.note, 4, 51), .button("MUTE 16"))
        XCTAssertEqual(target(.note, 5, 40), .button("T5"))
        XCTAssertEqual(target(.note, 1, 9), .button("MST"))
        XCTAssertEqual(target(.note, 2, 43), .button("PAGE 8"))
        XCTAssertEqual(target(.note, 2, 51), .button("MORPH"))
        XCTAssertEqual(target(.note, 2, 0), .button("PLAY"))
        XCTAssertEqual(target(.note, 2, 9), .button("METRONOME"))
        // Пресет сохраняется и читается, как свои (порт по имени — тоже).
        let back = try JSONDecoder().decode(MidiPreset.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }
}
