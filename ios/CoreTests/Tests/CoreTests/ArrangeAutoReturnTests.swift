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
        func render(_ curve: Bool, toLP: Bool = false, fromOff: Bool = false, lpEnd: Bool = false) -> [Float] {
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
                // LP прикрыт → конец кривой (выкл.).
                if lpEnd { pts = [ArrAutoPoint(x: 0, y: 0.2), ArrAutoPoint(x: 9, y: 0.2)] }
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
        let yl2: [Float] = render(true, lpEnd: true)
        let le: Float = jump(yl2, 9 * step - 2000, 9 * step + 4000)
        var pk: Float = 0, pkPlain: Float = 0
        for i in (9 * step)..<(9 * step + 4000) { pk = Swift.max(pk, abs(yl2[i])); pkPlain = Swift.max(pkPlain, abs(plain[i])) }
        print(String(format: "FILTER LP END: jump %.5f peak %.4f plain peak %.4f", le, pk, pkPlain))
    }

    /// Удар KICK на конце кривой HP (как на iPad 1.11): после конца — без всплеска (пики окнами по 500 отсчётов не выше,
    /// чем без кривой), и с резонансом: фильтр не проезжает через низы, выход переходит через сухой сигнал.
    func testNoBurstAfterHpCurve() {
        func render(_ curve: Bool, reso: Double) -> [Float] {
            var p = Project()
            for t in 1..<8 { p.tracks[t].clips[0] = nil }
            p.tracks[0].setSynth(16)
            p.tracks[0].params["filter"] = 0
            p.tracks[0].params["reso"] = reso
            p.tracks[0].params["decay"] = 600
            p.tracks[0].params["attack"] = 0
            for k in [0, 4, 8, 12] {
                p.tracks[0].clips[0]!.pages[0][k].on = true
                p.tracks[0].clips[0]!.pages[0][k].notes = [48]
            }
            p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 16))
            if curve { p.tracks[0].setAuto("filter", [ArrAutoPoint(x: 0, y: 0.9), ArrAutoPoint(x: 8, y: 0.9)]) }
            let core = AudioCore(master: false)
            core.installSynth()
            core.publish(p)
            core.events.push(.arrange(on: true, from: 0))
            core.events.push(.play(true))
            var l = [Float](repeating: 0, count: 256), r = l
            var out: [Float] = []
            while out.count < 14 * step {
                core.render(frames: 256, left: &l, right: &r)
                while core.sequencer.out.pop() != nil {}
                out += l
            }
            return out
        }
        for reso in [0.0, 50.0] {
            let a: [Float] = render(true, reso: reso)
            let b: [Float] = render(false, reso: reso)
            for w in 0..<12 {
                let i0: Int = 8 * step + w * 500
                var pa: Float = 0
                var pb: Float = 0
                for i in i0..<(i0 + 500) {
                    pa = Swift.max(pa, abs(a[i]))
                    pb = Swift.max(pb, abs(b[i]))
                }
                XCTAssertLessThanOrEqual(pa, pb * 1.1 + 0.002, "reso \(reso), окно \(w): без всплеска")
            }
        }
    }

    /// Ступенька кривой HP → выкл. посреди хвоста KICK (как на видео 1.11 и 2.11): низ хвоста возвращается без щелчка
    /// и без толчка — доля фильтра в выходе идёт по S-кривой, с HP — за 80 мс. Мера щелчка — пик выше 1 кГц у ступеньки против того же места
    /// без кривой (выкл.) и с HP без ступеньки.
    func testHpToOffStepWithoutClick() {
        func render(_ pts: [ArrAutoPoint]?) -> [Float] {
            var p = Project()
            for t in 1..<8 { p.tracks[t].clips[0] = nil }
            p.tracks[0].setSynth(16)
            p.tracks[0].params["filter"] = 0
            p.tracks[0].params["decay"] = 1000
            p.tracks[0].params["attack"] = 0
            p.tracks[0].clips[0]!.pages[0][9].on = true
            p.tracks[0].clips[0]!.pages[0][9].notes = [36]
            p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 16))
            if let pts = pts { p.tracks[0].setAuto("filter", pts) }
            let core = AudioCore(master: false)
            core.installSynth()
            core.publish(p)
            core.events.push(.arrange(on: true, from: 0))
            core.events.push(.play(true))
            var l = [Float](repeating: 0, count: 256), r = l
            var y: [Float] = []
            while y.count < 14 * step {
                core.render(frames: 256, left: &l, right: &r)
                while core.sequencer.out.pop() != nil {}
                y += l
            }
            return y
        }
        func highPeak(_ y: [Float], _ a: Int, _ b: Int) -> Float {
            var hp = Biquad()
            hp.set(type: 1, hz: 1000, qDb: 0, sampleRate: 48000)
            var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0, m: Float = 0
            for i in 0..<b {
                let o: Float = hp.b0 * y[i] + hp.b1 * x1 + hp.b2 * x2 - hp.a1 * y1 - hp.a2 * y2
                x2 = x1; x1 = y[i]; y2 = y1; y1 = o
                if i >= a { m = Swift.max(m, abs(o)) }
            }
            return m
        }
        let hpY: Double = 0.75
        for at in [11.0, 11.4, 12.0] {
            let stepped: [Float] = render([ArrAutoPoint(x: 0, y: hpY), ArrAutoPoint(x: at, y: hpY),
                                           ArrAutoPoint(x: at, y: 0.5), ArrAutoPoint(x: 16, y: 0.5)])
            let off: [Float] = render(nil)
            let hp: [Float] = render([ArrAutoPoint(x: 0, y: hpY), ArrAutoPoint(x: 16, y: hpY)])
            let a: Int = Int(at * Double(step)) - 500, b: Int = Int(at * Double(step)) + 1500
            let s: Float = highPeak(stepped, a, b), r: Float = Swift.max(highPeak(off, a, b), highPeak(hp, a, b))
            var lo: Float = 0
            for i in (a + 6500)..<(a + 7500) { lo = Swift.max(lo, abs(stepped[i] - off[i])) }
            print(String(format: "HP→OFF at %.1f: high %.6f, ref %.6f", at, s, r))
            XCTAssertGreaterThan(r, 0)
            XCTAssertLessThanOrEqual(s, r * 1.1, "ступенька HP → выкл. — без щелчка")
            XCTAssertLessThan(lo, 1e-3, "после ступеньки — как без фильтра")
            // Низ хвоста возвращается плавно (не толчком): через 10 мс — меньше трети, через 150 мс — весь.
            func rms(_ y: [Float], _ i0: Int) -> Float {
                var e: Float = 0
                for i in i0..<(i0 + 240) { e += y[i] * y[i] }
                return (e / 240).squareRoot()
            }
            let s0: Int = Int(at * Double(step))
            let early: Float = rms(stepped, s0 + 240) / Swift.max(1e-9, rms(off, s0 + 240))
            let late: Float = rms(stepped, s0 + 7200) / Swift.max(1e-9, rms(off, s0 + 7200))
            print(String(format: "HP→OFF at %.1f: low early %.3f, late %.3f", at, early, late))
            XCTAssertLessThan(early, 0.33, "низ — без толчка")
            XCTAssertEqual(late, 1, accuracy: 0.02)
        }
    }
}
