import XCTest
@testable import Core

final class MidiMapTests: XCTestCase {
    let track = MidiContext(clipOpen: false, page: .track)
    let fx = MidiContext(clipOpen: false, page: .fx)
    let clips = MidiContext(clipOpen: true, page: .track)
    let cc20 = MidiSource(type: .cc, ch: 0, num: 20)

    func testLearnAndLabels() {
        var s = MidiSettings()
        s.learn(.knob(4), src: cc20, input: 7, continuous: true, track)
        XCTAssertEqual(s.mappings.count, 1)
        let m = s.mappings[0]
        XCTAssertEqual(m.control, .abs)
        XCTAssertEqual(m.cond, .global)
        XCTAssertEqual(m.input, 7)
        XCTAssertEqual(m.target.label, "KNOB 1.2")
        XCTAssertEqual(MidiTarget.press(1).label, "KNOB 2.1 PRESS")
        XCTAssertEqual(m.src.short, "CC 20")
        XCTAssertEqual(MidiSource(type: .note, ch: 9, num: 36).label, "NOTE 36 · CH 10")
        // Нажатие ручки и кнопки — кнопочный тип.
        s.learn(.press(4), src: MidiSource(type: .cc, ch: 1, num: 4), input: 7, continuous: false, track)
        XCTAssertEqual(s.mapping(for: .press(4), track)?.control, .momentary)
        XCTAssertEqual(s.mapping(for: .press(4), track)?.press, .reset)
    }

    /// Один источник — одна цель (в том же условии); у цели один источник; тип управления при переназначении остаётся.
    func testOneSourceOneTarget() {
        var s = MidiSettings()
        s.learn(.knob(0), src: cc20, input: 1, continuous: true, track)
        s.update(.knob(0), continuous: true, track) { $0.control = .rel }
        s.learn(.knob(1), src: cc20, input: 1, continuous: true, track)
        XCTAssertNil(s.mapping(for: .knob(0), track))
        XCTAssertEqual(s.mapping(for: .knob(1), track)?.src, cc20)
        let cc21 = MidiSource(type: .cc, ch: 0, num: 21)
        s.update(.knob(1), continuous: true, track) { $0.control = .rel }
        s.learn(.knob(1), src: cc21, input: 1, continuous: true, track)
        XCTAssertEqual(s.mappings.count, 1)
        XCTAssertEqual(s.mappings[0].src, cc21)
        XCTAssertEqual(s.mappings[0].control, .rel)
        s.unmap(.knob(1), track)
        XCTAssertTrue(s.mappings.isEmpty)
    }

    /// Один источник в разных условиях: действует самое точное (Clip launcher, Current page, Global).
    func testConditions() {
        var s = MidiSettings()
        s.learn(.knob(0), src: cc20, input: 1, continuous: true, track)
        s.learn(.knob(5), src: cc20, input: 1, continuous: true, fx, pinned: "page:fx")
        XCTAssertEqual(s.mappings.count, 2)
        XCTAssertEqual(s.resolve(cc20, input: 1, track).active.map { $0.target }, [.knob(0)])
        XCTAssertEqual(s.resolve(cc20, input: 1, fx).active.map { $0.target }, [.knob(5)])
        // Сетка паттернов: новый маппинг — Clip launcher.
        s.learn(.button("PLAY"), src: cc20, input: 1, continuous: false, clips)
        XCTAssertEqual(s.mapping(for: .button("PLAY"), clips)?.cond, .clip)
        XCTAssertEqual(s.resolve(cc20, input: 1, clips).active.map { $0.target }, [.button("PLAY")])
        // Маппинг из LEARN слушает свой вход; с другого входа источник свободен.
        XCTAssertFalse(s.resolve(cc20, input: 2, track).mapped)
        let other = MidiSource(type: .note, ch: 0, num: 60)
        XCTAssertFalse(s.resolve(other, input: 1, track).mapped)
        // Ячейки сетки — всегда Clip launcher; вне сетки — не действуют, но источник назначен (нота не играет).
        let n61 = MidiSource(type: .note, ch: 0, num: 61)
        s.learn(.button("CLIP 1.1"), src: n61, input: 1, continuous: false, track)
        XCTAssertEqual(s.mapping(for: .button("CLIP 1.1"), clips)?.cond, .clip)
        let r = s.resolve(n61, input: 1, track)
        XCTAssertTrue(r.mapped)
        XCTAssertTrue(r.active.isEmpty)
        // GLOBAL у ячейки — запуск и при закрытой сетке; Current page у ячеек не бывает.
        s.update(.button("CLIP 1.1"), continuous: false, clips) { $0.cond = .global }
        XCTAssertEqual(s.resolve(n61, input: 1, track).active.map { $0.target }, [.button("CLIP 1.1")])
        s.update(.button("CLIP 1.1"), continuous: false, track) { $0.cond = .page }
        XCTAssertEqual(s.mapping(for: .button("CLIP 1.1"), clips)?.cond, .clip)
        // Кроссфейдер по умолчанию — GLOBAL, даже из сетки паттернов.
        s.learn(MidiTarget.crossfader, src: MidiSource(type: .cc, ch: 0, num: 30), input: 1, continuous: true, clips)
        XCTAssertEqual(s.mapping(for: MidiTarget.crossfader, track)?.cond, .global)
    }

    /// GLOBAL на ручке — параметр места, где назначили (громкость T3 в MIX — только она); на другом месте у той же
    /// ручки свой маппинг, источник — у одной цели.
    func testGlobalKnobPlace() {
        var s = MidiSettings()
        let mix = MidiContext(clipOpen: false, page: .mix, track: 0)
        s.learn(.knob(2), src: cc20, input: 1, continuous: true, mix)
        let m = s.mappings[0]
        XCTAssertEqual(m.place, MidiPlace(page: .mix, track: 0))
        // В MIX у другой выбранной дорожки — тот же параметр; на странице дорожки ручка 1.3 — не он.
        XCTAssertNotNil(s.mapping(for: .knob(2), MidiContext(clipOpen: false, page: .mix, track: 5)))
        XCTAssertNil(s.mapping(for: .knob(2), track))
        // Источник действует отовсюду (параметр — свой).
        XCTAssertEqual(s.resolve(cc20, input: 1, fx).active.count, 1)
        // На странице дорожки T2 та же ручка — свой маппинг; источник CC 21.
        let t2 = MidiContext(clipOpen: false, page: .track, track: 1)
        let cc21 = MidiSource(type: .cc, ch: 0, num: 21)
        s.learn(.knob(2), src: cc21, input: 1, continuous: true, t2)
        XCTAssertEqual(s.mappings.count, 2)
        XCTAssertEqual(s.mapping(for: .knob(2), t2)?.src, cc21)
        XCTAssertNil(s.mapping(for: .knob(2), MidiContext(clipOpen: false, page: .track, track: 0)))
        // Тот же CC 20 на T2 — уходит от MIX (один источник — одна цель).
        s.learn(.knob(2), src: cc20, input: 1, continuous: true, t2)
        XCTAssertEqual(s.mappings.count, 1)
        XCTAssertEqual(s.mappings[0].place, MidiPlace(page: .track, track: 1))
        // Current page — без места.
        s.update(.knob(2), continuous: true, t2) { $0.cond = .page }
        XCTAssertNil(s.mappings[0].place)
    }

    func testEncodersAndRange() {
        XCTAssertEqual(MidiEncoder.offset.step(65), 1)
        XCTAssertEqual(MidiEncoder.offset.step(63), -1)
        XCTAssertEqual(MidiEncoder.twos.step(1), 1)
        XCTAssertEqual(MidiEncoder.twos.step(127), -1)
        XCTAssertEqual(MidiEncoder.signed.step(1), 1)
        XCTAssertEqual(MidiEncoder.signed.step(65), -1)
        var m = MidiMapping(src: cc20, target: .knob(0), continuous: true)
        m.control = .rel
        XCTAssertEqual(m.relStep(65), 1.0 / 128)
        // Invert: энкодер крутит в обратную сторону; шаг — в пределах диапазона.
        m.min = 0.8
        m.max = 0.2
        XCTAssertEqual(m.relStep(65), -1.0 / 128)
        XCTAssertEqual(m.clamp(0.1), 0.2)
        XCTAssertEqual(m.value(at: 0), 0.8)
        XCTAssertEqual(m.value(at: 1), 0.2, accuracy: 1e-12)
    }

    func testInputs() {
        var t = MidiToggles()
        var m = MidiMapping(src: cc20, target: .knob(0), continuous: true)
        XCTAssertEqual(t.input(m, isCc: true, value: 127, press: true), .value(1))
        // Нота на непрерывной цели — кнопка: края диапазона.
        XCTAssertEqual(t.input(m, isCc: false, value: 100, press: true), .button(true))
        XCTAssertEqual(MidiInput.button(true).knobValue(m, cur: 0.5), 1)
        XCTAssertEqual(MidiInput.step(0.1).knobValue(m, cur: 0.95), 1)
        m.control = .toggle
        XCTAssertEqual(t.input(m, isCc: true, value: 127, press: true), .button(true))
        XCTAssertNil(t.input(m, isCc: true, value: 0, press: false))
        XCTAssertEqual(t.input(m, isCc: true, value: 127, press: true), .button(false))
        // Кнопка: ABSOLUTE — как MOMENTARY; RELATIVE — шаг вверх жмёт и отпускает.
        XCTAssertEqual(MidiInput.value(0.9).presses(press: true), [true])
        XCTAssertEqual(MidiInput.step(1.0 / 128).presses(press: true), [true, false])
        XCTAssertEqual(MidiInput.step(-1.0 / 128).presses(press: false), [])
    }

    /// Хранение: маппинги в настройках; испорченный маппинг пропускается, остальные читаются.
    func testCoding() {
        var a = AppSettings()
        a.midi.learn(.knob(3), src: cc20, input: 5, continuous: true, track)
        a.midi.learn(.press(3), src: MidiSource(type: .cc, ch: 1, num: 3), input: 5, continuous: false, track)
        a.midi.update(.press(3), continuous: false, track) { $0.press = .button("PLAY") }
        a.midi.update(.knob(3), continuous: true, track) { $0.port = .device(-9) }
        let back = AppSettings.decode(a.encode())
        XCTAssertEqual(back.midi.mappings, a.midi.mappings)
        let json = "{\"midi\":{\"mappings\":[{\"src\":{\"type\":\"cc\",\"ch\":0,\"num\":1},\"target\":{\"knob\":{\"_0\":2}}},{\"bad\":1}]}}"
        let s = AppSettings.decode(Data(json.utf8))
        XCTAssertEqual(s.midi.mappings.count, 1)
        XCTAssertEqual(s.midi.mappings[0].target, .knob(2))
        XCTAssertEqual(s.midi.mappings[0].control, .momentary)
    }
}
