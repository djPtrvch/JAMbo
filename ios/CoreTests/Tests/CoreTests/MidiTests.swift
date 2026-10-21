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

    /// MIDI дорожки: канал ALL — только выбранная дорожка, канал 1–16 — всегда; устройство; вход выключен.
    func testTrackNoteRouting() {
        var p = Project()
        while p.tracks.count < 4 { p.tracks.append(Track(index: p.tracks.count)) }
        XCTAssertEqual(TrackMidi.tracks(p, source: 9, channel: 2, selected: 1), [1])
        p.tracks[3].midi.inChannel = 3
        XCTAssertEqual(TrackMidi.tracks(p, source: 9, channel: 2, selected: 1), [1, 3])
        XCTAssertEqual(TrackMidi.tracks(p, source: 9, channel: 0, selected: 1), [1])
        p.tracks[3].midi.inDevice = 77
        XCTAssertEqual(TrackMidi.tracks(p, source: 9, channel: 2, selected: 1), [1])
        XCTAssertEqual(TrackMidi.tracks(p, source: 77, channel: 2, selected: 3), [3])
        p.tracks[1].midi.inOn = false
        XCTAssertEqual(TrackMidi.tracks(p, source: 9, channel: 2, selected: 1), [])
    }

    /// MIDI дорожки сохраняется в проекте; прежние проекты без него — по умолчанию; плохой канал — по умолчанию.
    func testTrackMidiCoding() throws {
        var t = Track(index: 0)
        t.midi.inDevice = -5
        t.midi.inName = "Keys"
        t.midi.inChannel = 10
        t.midi.outDevice = 42
        t.midi.outName = "Synth"
        t.midi.outChannel = 16
        let back = try JSONDecoder().decode(Track.self, from: try JSONEncoder().encode(t))
        XCTAssertEqual(back.midi, t.midi)
        XCTAssertTrue(back.midi.sends)
        let old = try JSONDecoder().decode(Track.self, from: Data("{\"name\":\"1\"}".utf8))
        XCTAssertEqual(old.midi, TrackMidi())
        XCTAssertFalse(old.midi.sends)
        let bad = try JSONDecoder().decode(TrackMidi.self, from: Data("{\"inChannel\":40,\"outChannel\":0}".utf8))
        XCTAssertEqual(bad.inChannel, 0)
        XCTAssertEqual(bad.outChannel, 1)
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
        XCTAssertNotEqual(MidiSettings.keyId(track: 0, channel: 0, note: 60), MidiSettings.keyId(track: 0, channel: 1, note: 60))
        XCTAssertNotEqual(MidiSettings.keyId(track: 0, channel: 1, note: 60), MidiSettings.keyId(track: 1, channel: 1, note: 60))
        XCTAssertLessThan(MidiSettings.keyId(track: 15, channel: 15, note: 127), 0)
    }

    /// Настройки MIDI хранятся в AppSettings; старые настройки без них читаются со значениями по умолчанию.
    func testSettingsCoding() throws {
        var a = AppSettings()
        a.midi.input = -42
        let back = AppSettings.decode(a.encode())
        XCTAssertEqual(back.midi, a.midi)
        let old = AppSettings.decode(Data("{\"velocity\":true}".utf8))
        XCTAssertEqual(old.midi, MidiSettings())
        XCTAssertTrue(old.velocity)
        // Прежние noteChannel и noteRoute пропускаются.
        let bad = AppSettings.decode(Data("{\"midi\":{\"noteChannel\":40,\"input\":5}}".utf8))
        XCTAssertEqual(bad.midi.input, 5)
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
