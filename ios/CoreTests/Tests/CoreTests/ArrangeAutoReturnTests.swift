import XCTest
@testable import Core

/// Конец кривой (как на iPad 1.11): блок с кривой Filter, за ним вплотную блоки того же клипа — после последней
/// точки звучит значение ручки.
final class ArrangeAutoReturnTests: XCTestCase {
    private let step = 6000

    var republish: Project? = nil

    private func run(_ core: AudioCore, steps: Int) {
        var l = [Float](repeating: 0, count: 256)
        var r = [Float](repeating: 0, count: 256)
        var pos = 0
        while pos < steps * step {
            core.render(frames: 256, left: &l, right: &r)
            while core.sequencer.out.pop() != nil {}
            // Как интерфейс во время игры: снимок звука публикуется заново (каждые ~0,1 с).
            if let p = republish, (pos / 256) % 20 == 0 { core.publish(p) }
            pos += 256
        }
    }

    func testFilterReturnsAfterCurve() { check(own: false) }
    func testFilterReturnsAfterCurveOwnPatterns() { check(own: true) }

    private func check(own: Bool) {
        var p = Project()
        for t in 1..<8 { p.tracks[t].clips[0] = nil }
        p.tracks[0].clips[0]!.pages[0][0].on = true
        p.tracks[0].clips[0]!.pages[0][8].on = true
        p.tracks[0].params["filter"] = -40
        let c: Clip = p.tracks[0].clips[0]!
        for k in 0..<6 { p.tracks[0].placeBlock(ArrBlock(clip: 0, start: k * 16, length: 16, pattern: own ? c : nil)) }
        p.tracks[0].setAuto("filter", [ArrAutoPoint(x: 16, y: 0.8), ArrAutoPoint(x: 32, y: 0.8)])
        let core = AudioCore()
        core.publish(p)
        republish = p
        core.events.push(.arrange(on: true, from: 0))
        core.events.push(.play(true))
        let f: Int = VoiceParam.filter
        run(core, steps: 8)
        let knob: Float = core.sampler.sound!.params[f]
        run(core, steps: 16)
        let mid: Float = core.sampler.sound!.params[f]
        XCTAssertNotEqual(mid, knob, "кривая действует")
        run(core, steps: 20)
        XCTAssertEqual(core.sampler.sound!.params[f], knob, accuracy: 1e-4, "после кривой — значение ручки")
    }

    /// Звук: KICK с Filter 0; кривая поднимает HP (тип фильтра другой) и кончается — дальше выход как без кривой
    /// (коэффициенты фильтра не застревают после скачка типа).
    func testSynthFilterSoundReturns() {
        func make(_ curve: Bool) -> AudioCore {
            var p = Project()
            for t in 1..<8 { p.tracks[t].clips[0] = nil }
            // KICK с длинным хвостом: новый удар на звучащем хвосте (голос слота продолжается).
            p.tracks[0].setSynth(16)
            p.tracks[0].params["filter"] = 0
            p.tracks[0].params["decay"] = 1000
            p.tracks[0].params["attack"] = 0
            for k in stride(from: 0, to: 16, by: 2) {
                p.tracks[0].clips[0]!.pages[0][k].on = true
                p.tracks[0].clips[0]!.pages[0][k].notes = [48]
            }
            // До шага 16 тишина: первый удар — на начале кривой (новый голос), дальше — на звучащем хвосте.
            p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 16, length: 16))
            p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 32, length: 16))
            if curve { p.tracks[0].setAuto("filter", [ArrAutoPoint(x: 16, y: 0.9), ArrAutoPoint(x: 32, y: 0.9)]) }
            let core = AudioCore(master: false)
            core.installSynth()
            core.publish(p)
            core.events.push(.arrange(on: true, from: 0))
            core.events.push(.play(true))
            return core
        }
        func energy(_ core: AudioCore, from a: Int, to b: Int) -> Double {
            var l = [Float](repeating: 0, count: 256)
            var r = [Float](repeating: 0, count: 256)
            var e: Double = 0
            var pos = 0
            while pos < b * step {
                core.render(frames: 256, left: &l, right: &r)
                while core.sequencer.out.pop() != nil {}
                if pos >= a * step { for x in l { e += Double(x * x) } }
                pos += 256
            }
            return e
        }
        let plain: Double = energy(make(false), from: 36, to: 46)
        let auto: Double = energy(make(true), from: 36, to: 46)
        XCTAssertGreaterThan(plain, 0)
        XCTAssertEqual(auto / plain, 1, accuracy: 0.02, "после кривой — звук как без неё")
    }

    /// Конец кривой HP посреди звучащей ноты KICK — без щелчка: фильтр уезжает к прозрачному краю, тип не прыгает;
    /// HP → LP и выкл. → HP — провалом выхода фильтра (3 мс), тип меняется.
    /// Мера щелчка — скачок отсчёта (|y[i] − y[i−1]|) у конца кривой против скачков хвоста без кривой.
    func testFilterEndWithoutClick() {
        var lastType: Int = 99
        func render(_ curve: Bool, toLP: Bool = false, fromOff: Bool = false) -> [Float] {
            var p = Project()
            for t in 1..<8 { p.tracks[t].clips[0] = nil }
            p.tracks[0].setSynth(16)
            p.tracks[0].params["filter"] = 0
            p.tracks[0].params["decay"] = 1000
            p.tracks[0].params["attack"] = 0
            p.tracks[0].clips[0]!.pages[0][8].on = true
            p.tracks[0].clips[0]!.pages[0][8].notes = [48]
            p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 16))
            if curve {
                var pts: [ArrAutoPoint] = [ArrAutoPoint(x: 0, y: 0.7), ArrAutoPoint(x: 9, y: 0.7)]
                // HP → LP скачком (через прозрачный край).
                if toLP { pts += [ArrAutoPoint(x: 9, y: 0.3), ArrAutoPoint(x: 16, y: 0.3)] }
                // Выкл. → HP посреди ноты.
                if fromOff { pts = [ArrAutoPoint(x: 9, y: 0.7), ArrAutoPoint(x: 16, y: 0.7)] }
                p.tracks[0].setAuto("filter", pts)
            }
            let core = AudioCore(master: false)
            core.installSynth()
            core.publish(p)
            core.events.push(.arrange(on: true, from: 0))
            core.events.push(.play(true))
            var l = [Float](repeating: 0, count: 256), r = l
            var y: [Float] = []
            while y.count < 12 * step {
                core.render(frames: 256, left: &l, right: &r)
                while core.sequencer.out.pop() != nil {}
                y += l
            }
            if let sv = core.sampler.synth {
                for v in 0..<SynthVoices.slots where sv.active[v] != 0 { lastType = sv.ftype[v] }
            }
            return y
        }
        func jump(_ y: [Float], _ a: Int, _ b: Int) -> Float {
            var m: Float = 0
            for i in (a + 1)..<b { m = Swift.max(m, abs(y[i] - y[i - 1])) }
            return m
        }
        let plain: [Float] = render(false)
        let auto: [Float] = render(true)
        let ref: Float = jump(plain, 9 * step - 2000, 9 * step + 4000)
        let atEnd: Float = jump(auto, 9 * step - 2000, 9 * step + 4000)
        print(String(format: "FILTER END: jump %.5f, plain %.5f", atEnd, ref))
        XCTAssertGreaterThan(ref, 0)
        XCTAssertLessThanOrEqual(atEnd, ref * 1.1, "конец кривой — без скачка сверх хвоста")
        let yl: [Float] = render(true, toLP: true)
        let lp: Float = jump(yl, 9 * step - 2000, 9 * step + 4000)
        print(String(format: "FILTER HP→LP: jump %.5f", lp))
        XCTAssertLessThanOrEqual(lp, ref * 1.1, "HP → LP — без скачка")
        XCTAssertEqual(lastType, -1, "тип сменился на LP")
        let on: Float = jump(render(true, fromOff: true), 9 * step - 2000, 9 * step + 4000)
        print(String(format: "FILTER OFF→HP: jump %.5f", on))
        XCTAssertLessThanOrEqual(on, ref * 1.1, "выкл. → HP — без скачка")
        XCTAssertEqual(lastType, 1, "тип сменился на HP")
    }
}
