import XCTest
@testable import Core

/// Тип фильтра (9.11): Filter — частота на всём ходу, SHIFT + тап — LP → HP → BP (у SUB — LP → LADDER → BP);
/// перевод прежней двухполярной ручки; BP и LADDER.
final class FilterTypeTests: XCTestCase {
    private let sub: String = SynthKey.key(Jambo.sub)

    func testCycle() {
        let lp = FilterType.lp, hp = FilterType.hp, bp = FilterType.bp, lad = FilterType.ladder
        XCTAssertEqual(FilterType.next(lp, sound: "s1"), hp)
        XCTAssertEqual(FilterType.next(hp, sound: "s1"), bp)
        XCTAssertEqual(FilterType.next(bp, sound: "s1"), lp)
        XCTAssertEqual(FilterType.next(lp, sound: sub), lad)
        XCTAssertEqual(FilterType.next(lad, sound: sub), bp)
        XCTAssertEqual(FilterType.next(bp, sound: sub), lp)
        XCTAssertEqual(FilterType.next(hp, sound: sub), lp, "HP у SUB (со звука другого движка) — дальше LP")
        XCTAssertEqual(FilterType.effective(lad, sound: "mi:16"), lp, "LADDER — только у SUB")
        XCTAssertEqual(FilterType.next(lad, sound: "mi:16"), hp)
        XCTAssertEqual(FilterType.of(nil), lp)
        XCTAssertEqual(FilterType.of(7), lp)
        // Открытый фильтр остаётся открытым, прикрытый — та же частота.
        XCTAssertEqual(FilterType.valueAfterSwitch(100, from: lp, to: hp), 0)
        XCTAssertEqual(FilterType.valueAfterSwitch(0, from: hp, to: bp), 50)
        XCTAssertEqual(FilterType.valueAfterSwitch(40, from: lp, to: hp), 40)
        XCTAssertEqual(FilterType.valueAfterSwitch(100, from: bp, to: lp), 100, "BP не бывает открытым")
    }

    /// Частота прежней ручки сохраняется.
    func testOldValueKeepsFrequency() {
        for v in [-100.0, -60, -30, -1] {
            let old: Double = 20000 * pow(30.0 / 20000, -v / 100)
            XCTAssertEqual(Fmt.filterHz(FilterMigration.value(v, type: FilterType.lp)), old, accuracy: old * 1e-9)
        }
        for v in [1.0, 40, 100] {
            let old: Double = 20 * pow(10000.0 / 20, v / 100)
            XCTAssertEqual(Fmt.filterHz(FilterMigration.value(v, type: FilterType.hp)), old, accuracy: old * 1e-9)
        }
        XCTAssertEqual(FilterMigration.value(0, type: FilterType.lp), 100, "центр — LP открыт")
        XCTAssertEqual(FilterMigration.value(0, type: FilterType.hp), 0, "центр — HP открыт")
        XCTAssertEqual(FilterMigration.value(-40, type: FilterType.hp), 0, "LP у HP-звука — открыт")
        XCTAssertEqual(FilterMigration.value(40, type: FilterType.lp), 100, "HP у LP-звука — открыт")
    }

    func testMigrateProject() throws {
        var p = Project()
        // Прежний проект: ручка по умолчанию — 0 (центр, выкл.).
        for i in 0..<p.tracks.count { p.tracks[i].params["filter"] = 0 }
        // T1: LP (−40), p-lock HP 50 и LP −20, кривая HP; T2: ручка в центре, p-lock HP — тип HP.
        p.tracks[0].params["filter"] = -40
        p.tracks[0].pages[0][1].locks["filter"] = 50
        p.tracks[0].pages[0][2].locks["filter"] = -20
        p.tracks[0].placeBlock(ArrBlock(clip: 0, start: 0, length: 16))
        p.tracks[0].setAuto("filter", [ArrAutoPoint(x: 0, y: 0.3), ArrAutoPoint(x: 8, y: 0.8)])
        p.tracks[1].params["filter"] = 0
        p.tracks[1].pages[0][0].locks["filter"] = 60
        p.tracks[1].pages[0][4].locks["filter"] = 30
        // Пресет-лок: тип — по своей ручке.
        p.tracks[2].pages[0][3].locks["filter"] = 20
        p.tracks[2].pages[0][3].soundLocks = ["filter"]
        p.version = 8
        let data = try JSONEncoder().encode(p)
        var q = try JSONDecoder().decode(Project.self, from: data)
        q.repair()
        XCTAssertEqual(q.version, 9)
        let t0 = q.tracks[0]
        XCTAssertEqual(t0.params[Params.filterTypeId], Double(FilterType.lp))
        XCTAssertEqual(t0.params["filter"]!, FilterMigration.value(-40, type: FilterType.lp), accuracy: 1e-9)
        XCTAssertEqual(t0.pages[0][1].locks["filter"], 100, "HP у LP-дорожки — открыт")
        XCTAssertEqual(t0.pages[0][2].locks["filter"]!, FilterMigration.value(-20, type: FilterType.lp), accuracy: 1e-9)
        let ys: [Double] = t0.autoPoints("filter").map { $0.y }
        XCTAssertEqual(ys[0], FilterMigration.value(-40, type: FilterType.lp) / 100, accuracy: 1e-9)
        XCTAssertEqual(ys.last!, 1, accuracy: 1e-9, "HP на кривой LP-дорожки — открыт")
        let t1 = q.tracks[1]
        XCTAssertEqual(t1.params[Params.filterTypeId], Double(FilterType.hp), "центр, p-lock HP — HP")
        XCTAssertEqual(t1.params["filter"], 0, "центр — HP открыт")
        XCTAssertEqual(t1.pages[0][0].locks["filter"]!, FilterMigration.value(60, type: FilterType.hp), accuracy: 1e-9)
        let s = q.tracks[2].pages[0][3]
        XCTAssertEqual(s.locks[Params.filterTypeId], Double(FilterType.hp))
        XCTAssertEqual(s.soundLocks?.sorted(), ["filter", Params.filterTypeId])
        // Ручка в центре без p-lock — LP открыт.
        XCTAssertEqual(q.tracks[5].params[Params.filterTypeId], Double(FilterType.lp))
        XCTAssertEqual(q.tracks[5].params["filter"], 100)
        // Второй repair ничего не меняет.
        var r = q
        r.repair()
        XCTAssertEqual(r, q)
    }

    func testPresetAndDefaults() throws {
        let old = Data(#"{"name":"Bass","sound":"mi:24","params":{"filter":-50,"harm":10},"fmt":4}"#.utf8)
        let p = try JSONDecoder().decode(SynthPreset.self, from: old)
        XCTAssertEqual(p.fmt, 5)
        XCTAssertEqual(p.params[Params.filterTypeId], Double(FilterType.lp))
        XCTAssertEqual(p.params["filter"]!, FilterMigration.value(-50, type: FilterType.lp), accuracy: 1e-9)
        let noFilter = try JSONDecoder().decode(SynthPreset.self, from: Data(#"{"name":"A","sound":"mi:24","params":{"harm":10},"fmt":4}"#.utf8))
        XCTAssertNil(noFilter.params["filter"])
        XCTAssertNil(noFilter.value(Params.filterTypeId), "нет ручки Filter — тип не ставится")
        // Свои значения по умолчанию (UserDefaults): прежняя ручка переводится один раз.
        let kd = Data(#"{"values":{"sampler/filter":30,"synth24/filter":-40,"fx/rev.size":20}}"#.utf8)
        let k = KnobDefaults.decode(kd)
        XCTAssertEqual(k.filterV, 2)
        XCTAssertEqual(k.values["sampler/filter.type"], Double(FilterType.hp))
        XCTAssertEqual(k.values["sampler/filter"]!, FilterMigration.value(30, type: FilterType.hp), accuracy: 1e-9)
        XCTAssertEqual(k.values["synth24/filter.type"], Double(FilterType.lp))
        XCTAssertEqual(k.values["fx/rev.size"], 20)
        let again = KnobDefaults.decode(try JSONEncoder().encode(k))
        XCTAssertEqual(again, k)
        // Тип — вместе со значением ручки.
        var t = Track(index: 0)
        t.setSynth(24)
        k.applySound(to: &t)
        XCTAssertEqual(t.params[Params.filterTypeId], Double(FilterType.lp))
    }

    /// BP: середина проходит, края — нет.
    func testBandpass() {
        func gain(_ f: Double) -> Double {
            var b = Biquad()
            b.set(type: 2, hz: 1000, qDb: 0.7, sampleRate: 48000)
            var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0, e: Double = 0, ei: Double = 0
            for i in 0..<48000 {
                let x: Float = Float(sin(2 * Double.pi * f * Double(i) / 48000))
                let y: Float = b.b0 * x + b.b1 * x1 + b.b2 * x2 - b.a1 * y1 - b.a2 * y2
                x2 = x1; x1 = x; y2 = y1; y1 = y
                if i >= 24000 { e += Double(y * y); ei += Double(x * x) }
            }
            return 10 * log10(e / ei)
        }
        XCTAssertEqual(gain(1000), 0, accuracy: 0.1)
        XCTAssertLessThan(gain(100), -18)
        XCTAssertLessThan(gain(10000), -18)
    }

    /// LADDER отдельно: 24 dB/окт, резонанс устойчив, GRIT громкость растит умеренно.
    func testLadder() {
        func run(_ x: [Float], hz: Double, reso: Double, grit: Double) -> [Float] {
            let f = LadderFilter(slots: 1)
            var b = x
            b.withUnsafeMutableBufferPointer { p in
                var pos = 0
                while pos < p.count {
                    let m: Int = Swift.min(24, p.count - pos)
                    f.run(0, p.baseAddress! + pos, m, hz0: hz, hz1: hz, qDb: 0.7 + reso * 18, grit: grit, sr: 48000,
                          fq: 1, dfq: 0)
                    pos += m
                }
            }
            return b
        }
        func tone(_ f: Double, _ a: Double = 0.01) -> [Float] {
            return (0..<9600).map { Float(a * sin(2 * Double.pi * f * Double($0) / 48000)) }
        }
        func db(_ x: [Float]) -> Double {
            var e: Double = 0
            for v in x[(x.count / 2)...] { e += Double(v * v) }
            return 10 * log10(e / Double(x.count / 2) + 1e-30)
        }
        let ref: Double = db(tone(250))
        XCTAssertEqual(db(run(tone(250), hz: 1000, reso: 0, grit: 0)) - ref, -1.1, accuracy: 0.5)
        XCTAssertEqual(db(run(tone(1000), hz: 1000, reso: 0, grit: 0)) - ref, -12, accuracy: 0.5)
        XCTAssertLessThan(db(run(tone(4000), hz: 1000, reso: 0, grit: 0)) - ref, -45, "24 dB/окт")
        XCTAssertGreaterThan(db(run(tone(1000), hz: 1000, reso: 1, grit: 0)) - ref, 15, "резонанс")
        var imp = [Float](repeating: 0, count: 48000)
        imp[0] = 1
        let ring = run(imp, hz: 1000, reso: 1, grit: 1)
        XCTAssertFalse(ring.contains { !$0.isFinite })
        XCTAssertLessThan(db(ring), -100, "без самовозбуждения — затухает")
        var saw = [Float](repeating: 0, count: 24000)
        for i in 0..<saw.count {
            let ph: Double = (55 * Double(i) / 48000).truncatingRemainder(dividingBy: 1)
            saw[i] = Float(0.58 * (2 * ph - 1))
        }
        let clean: Double = db(run(saw, hz: 20000, reso: 0.3, grit: 0))
        for g in [0.5, 1.0] {
            let y = run(saw, hz: 20000, reso: 0.3, grit: g)
            XCTAssertLessThanOrEqual(y.map(abs).max()!, 1)
            XCTAssertLessThan(db(y) - clean, 7, "GRIT \(g): громкость растёт умеренно")
        }
    }

    /// SUB в AudioCore: LADDER звучит (не так, как LP 12 dB), NaN нет, пик ≤ 0 dBFS; у другого движка LADDER — LP.
    func testSubLadderInCore() {
        func render(_ engine: Int, type: Int, grit: Double = 0) -> [Float] {
            var p = Project()
            for t in 1..<8 { p.tracks[t].clips[0] = nil }
            p.tracks[0].setSynth(engine)
            p.tracks[0].params[Params.filterTypeId] = Double(type)
            p.tracks[0].params["filter"] = 55
            p.tracks[0].params["reso"] = 60
            p.tracks[0].params["p4"] = grit
            p.tracks[0].params["timbre"] = 0
            p.tracks[0].clips[0]!.pages[0][0].on = true
            p.tracks[0].clips[0]!.pages[0][0].notes = [36]
            p.tracks[0].clips[0]!.pages[0][0].len = 8
            let core = AudioCore(master: false)
            core.installSynth()
            core.publish(p)
            core.events.push(.play(true))
            var l = [Float](repeating: 0, count: 256), r = l
            var y: [Float] = []
            while y.count < 24000 {
                core.render(frames: 256, left: &l, right: &r)
                while core.sequencer.out.pop() != nil {}
                y += l
            }
            return y
        }
        let lp = render(Jambo.sub, type: FilterType.lp)
        let lad = render(Jambo.sub, type: FilterType.ladder)
        let hot = render(Jambo.sub, type: FilterType.ladder, grit: 100)
        for y in [lp, lad, hot] {
            XCTAssertFalse(y.contains { !$0.isFinite })
            XCTAssertLessThanOrEqual(y.map(abs).max()!, 1)
            XCTAssertGreaterThan(y.map(abs).max()!, 0.01)
        }
        var d: Float = 0
        for i in 0..<lp.count { d = Swift.max(d, abs(lp[i] - lad[i])) }
        XCTAssertGreaterThan(d, 0.01, "LADDER — другой фильтр")
        d = 0
        for i in 0..<lad.count { d = Swift.max(d, abs(hot[i] - lad[i])) }
        XCTAssertGreaterThan(d, 0.01, "GRIT — перегруз входа LADDER")
        let a1 = render(17, type: FilterType.ladder), a2 = render(17, type: FilterType.lp)
        XCTAssertEqual(a1, a2, "у ANALOG LADDER звучит как LP")
    }
}
