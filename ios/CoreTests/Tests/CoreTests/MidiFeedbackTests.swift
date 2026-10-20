import XCTest
@testable import Core

final class MidiFeedbackTests: XCTestCase {
    let track = MidiContext(clipOpen: false, page: .track)
    let fx = MidiContext(clipOpen: false, page: .fx)
    let cc20 = MidiSource(type: .cc, ch: 0, num: 20)

    /// Значение в диапазоне Range: края, середина, Invert, за пределами — до края.
    func testValueInRange() {
        var m = MidiMapping(src: cc20, target: .knob(0), continuous: true)
        XCTAssertEqual(m.feedbackValue(0), 0)
        XCTAssertEqual(m.feedbackValue(1), 127)
        XCTAssertEqual(m.feedbackValue(0.5), 64)
        m.min = 0.25
        m.max = 0.75
        XCTAssertEqual(m.feedbackValue(0.5), 64)
        XCTAssertEqual(m.feedbackValue(0.1), 0)
        XCTAssertEqual(m.feedbackValue(0.9), 127)
        m.min = 1
        m.max = 0
        XCTAssertEqual(m.feedbackValue(1), 0)
        XCTAssertEqual(m.feedbackValue(0), 127)
        m.max = 1
        XCTAssertEqual(m.feedbackValue(0.3), 0)
    }

    /// Порт: Default — выход из DEVICES, None — нет, свой — свой.
    func testDest() {
        var m = MidiMapping(src: cc20, target: .button("PLAY"), continuous: false)
        XCTAssertEqual(m.feedbackDest(default: 5), 5)
        XCTAssertNil(m.feedbackDest(default: nil))
        m.port = .none
        XCTAssertNil(m.feedbackDest(default: 5))
        m.port = .device(9)
        XCTAssertEqual(m.feedbackDest(default: 5), 9)
    }

    /// Только изменения; другой выход или источник — свои значения; после reset — всё заново.
    func testChangesOnly() {
        var f = MidiFeedback()
        XCTAssertTrue(f.change(dest: 1, src: cc20, value: 10))
        XCTAssertFalse(f.change(dest: 1, src: cc20, value: 10))
        XCTAssertTrue(f.change(dest: 2, src: cc20, value: 10))
        XCTAssertTrue(f.change(dest: 1, src: MidiSource(type: .note, ch: 0, num: 20), value: 10))
        XCTAssertTrue(f.change(dest: 1, src: cc20, value: 11))
        f.reset()
        XCTAssertTrue(f.change(dest: 1, src: cc20, value: 11))
    }

    /// CC и нота на канале источника; разбор обратно даёт то же сообщение.
    func testWord() {
        let w = MidiFeedback.word(MidiSource(type: .cc, ch: 2, num: 7), value: 100)
        XCTAssertEqual(MidiMessage.parse(w), MidiMessage(kind: .cc, channel: 2, data1: 7, data2: 100))
        let n = MidiFeedback.word(MidiSource(type: .note, ch: 9, num: 36), value: 127)
        XCTAssertEqual(MidiMessage.parse(n), MidiMessage(kind: .noteOn, channel: 9, data1: 36, data2: 127))
        let off = MidiFeedback.word(MidiSource(type: .note, ch: 9, num: 36), value: 0)
        XCTAssertEqual(MidiMessage.parse(off)?.kind, .noteOff)
    }

    /// У источника — самое точное действующее условие; недействующие и PRESS — мимо.
    func testActiveMappings() {
        var s = MidiSettings()
        s.learn(.knob(0), src: cc20, input: 7, continuous: true, track)
        s.update(.knob(1), continuous: true, fx, pinned: "page:fx") { m in
            m.src = self.cc20
            m.input = 7
        }
        s.learn(.press(0), src: MidiSource(type: .cc, ch: 1, num: 20), input: 7, continuous: false, track)
        s.learn(.button("PLAY"), src: MidiSource(type: .note, ch: 0, num: 1), input: 7, continuous: false, track)
        let onTrack = s.feedbackMappings(track)
        XCTAssertEqual(onTrack.map { $0.target }, [.knob(0), .button("PLAY")])
        let onFx = s.feedbackMappings(fx)
        XCTAssertEqual(onFx.map { $0.target }, [.knob(1), .button("PLAY")])
    }

    /// GLOBAL ручки с одним входом и Current page MIX с другим (Any): на MIX обратная связь — от маппинга MIX, как
    /// управление (resolve), а не от того, что раньше в списке.
    func testFeedbackFollowsResolveAcrossInputs() {
        var s = MidiSettings()
        s.learn(.knob(0), src: cc20, input: 7, continuous: true, track)
        let mix = MidiContext(clipOpen: false, page: .mix)
        s.update(.knob(0), continuous: true, mix, pinned: "page:mix") { m in
            m.src = self.cc20
            m.input = nil
        }
        XCTAssertEqual(s.mappings.count, 2)
        XCTAssertEqual(s.resolve(cc20, input: 7, mix).active.map { $0.condKey }, ["page:mix"])
        XCTAssertEqual(s.feedbackMappings(mix).map { $0.condKey }, ["page:mix"])
        XCTAssertEqual(s.feedbackMappings(track).map { $0.condKey }, ["global"])
    }
}
