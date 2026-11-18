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
        // Ответ HELLO: статус, версия 1.2.3, формат 2, сторона LEFT, профиль 0, 4 профиля, MIDI OUT ALL, сообщения пэда.
        XCTAssertEqual(pad.event([0x7D, 0x4A, 0x50, 0x41, 0, 1, 2, 3, 2, 1, 0, 4, 2, 1, 0, 0]),
                       .pad(side: 1, thru: 2, controls: true))
        XCTAssertNil(pad.event([0x7D, 0x4A, 0x50, 0x41, 1]))
        XCTAssertEqual(JamboPad.helloSysEx, [0x7D, 0x4A, 0x50, 0x01])
        XCTAssertEqual(JamboPad.side(name: "JAMboPAD L"), 1)
        XCTAssertEqual(JamboPad.side(name: "JAMboPAD R"), 0)
        XCTAssertNil(JamboPad.side(name: "SMC-PAD"))
        XCTAssertNil(pad.event([0x7D, 0x4A, 0x50, 0x65, 12]))
        XCTAssertNil(pad.event([0x7D, 0x4A, 0x50, 0x4D, 0]))
        XCTAssertNil(pad.event([0x00, 0x20, 0x29, 0x65, 1]))
        XCTAssertEqual(pad.event([0x7D, 0x4A, 0x50, 0x67, 1, 0x2D, 0x0B]), .scale(1))
        XCTAssertNil(pad.event([0x7D, 0x4A, 0x50, 0x67, 11, 0, 0]))
        XCTAssertTrue(pad.owns("SMC-PAD"))
        XCTAssertTrue(pad.owns("JAMboPAD L"))
        XCTAssertFalse(pad.owns("Launchpad X"))
    }

    /// Маппинги по таблице раскладки: источники не повторяются, цели — существующие, обратная связь — на выходы устройства.
    func testMappings() throws {
        let maps: [MidiMapping] = JamboPad().mappings
        XCTAssertEqual(maps.count, 16 + 48 + 6 + 16 + 10)
        XCTAssertEqual(Set(maps.map { $0.src }).count, maps.count)
        XCTAssertTrue(maps.allSatisfy { $0.port == .standard && $0.input == nil && $0.cond == .global })
        func target(_ t: MidiSourceType, _ ch: Int, _ n: Int) -> MidiTarget? {
            return maps.first { $0.src == MidiSource(type: t, ch: ch, num: n) }?.target
        }
        XCTAssertEqual(target(.cc, 0, 6), .knob(6))
        XCTAssertEqual(maps.first { $0.target == .knob(6) }?.control, .abs)
        XCTAssertEqual(target(.note, 1, 36), .button("STEP 1"))
        XCTAssertEqual(target(.note, 4, 51), .button("MUTE 16"))
        XCTAssertEqual(target(.note, 5, 40), .button("T5"))
        XCTAssertEqual(target(.note, 1, 9), .button("MST"))
        XCTAssertEqual(target(.note, 2, 43), .button("PAGE 8"))
        XCTAssertEqual(target(.note, 2, 51), .button("MORPH"))
        XCTAssertEqual(target(.note, 2, 0), .button("PLAY"))
        XCTAssertEqual(target(.note, 2, 9), .button("METRONOME"))
    }

    /// Устройства: JAMboPAD в списке всегда, выключен; включённый работает только со своих входов; новый вход —
    /// своё устройство, включённое; два включённых — маппинги вместе, один источник у каждого свой.
    func testDevices() throws {
        var s = MidiSettings()
        XCTAssertEqual(s.devices.map { $0.name }, ["JAMboPAD"])
        XCTAssertFalse(s.isOn("JAMboPAD"))
        XCTAssertTrue(s.mappings.isEmpty)
        let ctx = MidiContext(clipOpen: false, page: .track)
        let cc6 = MidiSource(type: .cc, ch: 0, num: 6)
        s.setOn("JAMboPAD", true)
        XCTAssertEqual(s.mappings.count, 96)
        XCTAssertEqual(s.resolve(cc6, input: 1, owners: s.owners("SMC-PAD"), ctx).active.map { $0.target }, [.knob(6)])
        XCTAssertFalse(s.resolve(cc6, input: 2, owners: s.owners("Synth"), ctx).mapped)
        XCTAssertTrue(s.addPort("Synth"))
        XCTAssertFalse(s.addPort("Synth"))
        XCTAssertFalse(s.addPort("JAMboPAD L"))
        XCTAssertTrue(s.isOn("Synth"))
        s.learn(.knob(0), src: cc6, input: 2, dev: "Synth", continuous: true, ctx)
        XCTAssertEqual(s.device("Synth")?.mappings.count, 1)
        XCTAssertEqual(s.device("JAMboPAD")?.mappings.count, 96)
        XCTAssertEqual(s.resolve(cc6, input: 2, owners: s.owners("Synth"), ctx).active.map { $0.target }, [.knob(0)])
        XCTAssertTrue(s.device("JAMboPAD")?.modified == false)
        // Выключенный — его маппинги не действуют и не теряются.
        s.setOn("JAMboPAD", false)
        XCTAssertEqual(s.mappings.count, 1)
        s.clear("Synth")
        XCTAssertEqual(s.device("JAMboPAD")?.mappings.count, 96)
        // RESTORE, RENAME, DELETE.
        s.setOn("JAMboPAD", true)
        s.unmap(.knob(6), ctx)
        XCTAssertTrue(s.device("JAMboPAD")?.modified == true)
        s.restore("JAMboPAD")
        XCTAssertTrue(s.device("JAMboPAD")?.modified == false)
        XCTAssertFalse(s.rename("JAMboPAD", to: "X"))
        XCTAssertTrue(s.rename("Synth", to: "Keys"))
        XCTAssertNotNil(s.device("Keys"))
        s.remove("JAMboPAD")
        s.remove("Keys")
        XCTAssertEqual(s.devices.map { $0.name }, ["JAMboPAD"])
        // Запись: устройства и их маппинги.
        s.setOn("JAMboPAD", true)
        let back = try JSONDecoder().decode(MidiSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    /// Файл устройства: EXPORT и IMPORT; встроенный — маппинги заменяются; своё — замена или копия.
    func testDeviceFile() throws {
        var s = MidiSettings()
        _ = s.addPort("Synth")
        s.learn(.knob(0), src: MidiSource(type: .cc, ch: 0, num: 7), input: 2, dev: "Synth", continuous: true,
                MidiContext(clipOpen: false, page: .track))
        let data: Data = try XCTUnwrap(s.device("Synth")?.fileData())
        let d: MidiDevice = try XCTUnwrap(MidiDevice.read(data))
        XCTAssertEqual(d.name, "Synth")
        XCTAssertEqual(d.port, "Synth")
        XCTAssertEqual(d.mappings, s.device("Synth")?.mappings)
        XCTAssertNil(MidiDevice.read(Data("{\"name\":\"X\"}".utf8)))
        XCTAssertEqual(s.importDevice(d, replace: false), "Synth 2")
        XCTAssertEqual(s.device("Synth 2")?.mappings.first?.dev, "Synth 2")
        s.setOn("Synth", false)
        var e = d
        e.mappings = []
        XCTAssertEqual(s.importDevice(e, replace: true), "Synth")
        XCTAssertEqual(s.device("Synth")?.mappings.count, 0)
        XCTAssertFalse(s.isOn("Synth"))
        var pad = MidiDevice(name: "JAMboPAD", port: "", on: true, mappings: [])
        pad.mappings = []
        XCTAssertEqual(s.importDevice(pad, replace: false), "JAMboPAD")
        XCTAssertEqual(s.device("JAMboPAD")?.mappings.count, 0)
    }

    /// controllers/JAMboPAD.json в репозитории — те же маппинги, что встроенные (JAMBO_WRITE_CONTROLLERS=1 — записать).
    func testJamboPadFile() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("controllers/JAMboPAD.json")
        let pad = MidiDevice(name: "JAMboPAD", port: "", on: true, mappings: JamboPad().mappings)
        if ProcessInfo.processInfo.environment["JAMBO_WRITE_CONTROLLERS"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try XCTUnwrap(pad.fileData()).write(to: url)
        }
        let d: MidiDevice = try XCTUnwrap(MidiDevice.read(try Data(contentsOf: url)))
        XCTAssertEqual(d.mappings, pad.mappings)
    }
}
