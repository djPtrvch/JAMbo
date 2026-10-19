import XCTest
@testable import Core

final class MidiTests: XCTestCase {
    func testParseChannelMessages() {
        XCTAssertEqual(MidiMessage.parse(MidiMessage.ump(status: 0x93, 60, 100)),
                       MidiMessage(kind: .noteOn, channel: 3, data1: 60, data2: 100))
        // Note On с силой 0 — Note Off.
        XCTAssertEqual(MidiMessage.parse(MidiMessage.ump(status: 0x90, 60, 0))?.kind, .noteOff)
        XCTAssertEqual(MidiMessage.parse(MidiMessage.ump(status: 0x8F, 61, 40)),
                       MidiMessage(kind: .noteOff, channel: 15, data1: 61, data2: 40))
        XCTAssertEqual(MidiMessage.parse(MidiMessage.ump(status: 0xB1, 20, 127)),
                       MidiMessage(kind: .cc, channel: 1, data1: 20, data2: 127))
        // Pitch bend, aftertouch — не нужны.
        XCTAssertNil(MidiMessage.parse(MidiMessage.ump(status: 0xE0, 0, 64)))
        XCTAssertNil(MidiMessage.parse(MidiMessage.ump(status: 0xD0, 10, 0)))
    }

    func testParseRealtime() {
        XCTAssertEqual(MidiMessage.parse(MidiMessage.ump(status: 0xF8, 0, 0))?.kind, .clock)
        XCTAssertEqual(MidiMessage.parse(MidiMessage.ump(status: 0xFA, 0, 0))?.kind, .start)
        XCTAssertEqual(MidiMessage.parse(MidiMessage.ump(status: 0xFB, 0, 0))?.kind, .cont)
        XCTAssertEqual(MidiMessage.parse(MidiMessage.ump(status: 0xFC, 0, 0))?.kind, .stop)
        XCTAssertTrue(MidiMessage(kind: .clock).isRealtime)
        XCTAssertFalse(MidiMessage(kind: .cc).isRealtime)
    }

    /// Пакет из нескольких сообщений: SysEx (2 слова) и MIDI 2.0 (2 слова) пропускаются целиком.
    func testParsePacketSkipsLongMessages() {
        let words: [UInt32] = [
            MidiMessage.ump(status: 0x90, 36, 90),
            0x3016_F07E, 0x0000_0000,           // SysEx7, 2 слова
            0x4090_2400, 0xFFFF_0000,           // MIDI 2.0 Note On, 2 слова
            MidiMessage.ump(status: 0xF8, 0, 0),
            MidiMessage.ump(status: 0x80, 36, 0),
        ]
        let out: [MidiMessage] = words.withUnsafeBufferPointer { MidiMessage.parse(words: $0) }
        XCTAssertEqual(out.map { $0.kind }, [.noteOn, .clock, .noteOff])
        XCTAssertEqual(out[0].data1, 36)
    }

    func testNoteRouting() {
        var s = MidiSettings()
        let on = MidiMessage(kind: .noteOn, channel: 2, data1: 60, data2: 100)
        XCTAssertEqual(s.noteTrack(on, selected: 5, tracks: 8), 5)
        s.noteChannel = 4
        XCTAssertNil(s.noteTrack(on, selected: 5, tracks: 8))
        s.noteChannel = 3
        XCTAssertEqual(s.noteTrack(on, selected: 5, tracks: 8), 5)
        // CH 1–16 → TRACKS: канал 3 (индекс 2) — третья дорожка; канал без дорожки — мимо.
        s.noteChannel = 0
        s.noteRoute = .channel
        XCTAssertEqual(s.noteTrack(on, selected: 5, tracks: 8), 2)
        XCTAssertNil(s.noteTrack(on, selected: 0, tracks: 2))
        XCTAssertNil(s.noteTrack(MidiMessage(kind: .cc, channel: 0, data1: 1, data2: 1), selected: 0, tracks: 8))
    }

    func testInputFilterAndVelocity() {
        var s = MidiSettings()
        XCTAssertTrue(s.accepts(source: 123))
        s.input = 77
        XCTAssertFalse(s.accepts(source: 123))
        XCTAssertTrue(s.accepts(source: 77))
        XCTAssertEqual(MidiSettings.velocity(127, sensitive: true), 1)
        XCTAssertEqual(MidiSettings.velocity(0, sensitive: true), 1.0 / 127, accuracy: 1e-9)
        XCTAssertEqual(MidiSettings.velocity(20, sensitive: false), 1)
        XCTAssertNotEqual(MidiSettings.keyId(channel: 0, note: 60), MidiSettings.keyId(channel: 1, note: 60))
        XCTAssertLessThan(MidiSettings.keyId(channel: 15, note: 127), 0)
    }

    /// Настройки MIDI хранятся в AppSettings; старые настройки без них читаются со значениями по умолчанию.
    func testSettingsCoding() throws {
        var a = AppSettings()
        a.midi.input = -42
        a.midi.noteChannel = 10
        a.midi.noteRoute = .channel
        let back = AppSettings.decode(a.encode())
        XCTAssertEqual(back.midi, a.midi)
        let old = AppSettings.decode(Data("{\"velocity\":true}".utf8))
        XCTAssertEqual(old.midi, MidiSettings())
        XCTAssertTrue(old.velocity)
        let bad = AppSettings.decode(Data("{\"midi\":{\"noteChannel\":40}}".utf8))
        XCTAssertEqual(bad.midi.noteChannel, 0)
        // Нажатие ручки как касание и STEP SWIPE: по умолчанию ON и LENGTH, сохраняются.
        XCTAssertTrue(old.midi.pressTouch)
        XCTAssertFalse(old.stepPaint)
        var b = AppSettings()
        b.midi.pressTouch = false
        b.stepPaint = true
        let c = AppSettings.decode(b.encode())
        XCTAssertFalse(c.midi.pressTouch)
        XCTAssertTrue(c.stepPaint)
    }
}
