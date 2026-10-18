import XCTest
@testable import Core

/// Пресеты модулей мастера и параметры окон (Params.masterExtra).
final class MasterPresetTests: XCTestCase {
    func testIdsByModule() {
        XCTAssertEqual(MasterPresetBook.ids(0), ["sat.drive", "sat.type", "sat.tone", "sat.mix", "sat.focus"])
        XCTAssertEqual(MasterPresetBook.ids(1).count, 8)
        XCTAssertEqual(MasterPresetBook.ids(2), ["clip.drive", "clip.ceiling", "clip.softness", "clip.bass"])
        XCTAssertEqual(MasterPresetBook.ids(3), ["lim.input", "lim.ceiling", "lim.lookahead", "lim.release"])
        // У каждого параметра мастера есть описание (ручка или поле окна).
        for (id, _) in MasterChain.ids { XCTAssertNotNil(Params.byId[id], id) }
    }

    func testSaveApplyRoundTrip() {
        var b = MasterPresetBook()
        var m: [String: Double] = MasterChain.defaultValues()
        m["lim.ceiling"] = -3
        m["lim.release"] = MasterChain.autoValue
        m["cmp.ratio"] = 4
        b.save(3, name: "  Loud  ", master: m)
        XCTAssertEqual(b.list(3).first?.name, "Loud")
        XCTAssertEqual(b.list(3).first?.values.count, 4)
        XCTAssertNil(b.list(3).first?.values["cmp.ratio"])
        var other: [String: Double] = MasterChain.defaultValues()
        other["cmp.ratio"] = 10
        b.apply(3, 0, to: &other)
        XCTAssertEqual(other["lim.ceiling"], -3)
        XCTAssertEqual(other["lim.release"], MasterChain.autoValue)
        XCTAssertEqual(other["cmp.ratio"], 10, "другие модули не меняются")
        let back = MasterPresetBook.decode(b.encode())
        XCTAssertEqual(back, b)
    }

    func testNamesRenameDelete() {
        var b = MasterPresetBook()
        let m = MasterChain.defaultValues()
        b.save(1, name: "", master: m)
        b.save(1, name: "", master: m)
        XCTAssertEqual(b.list(1).map { $0.name }, ["COMP 1", "COMP 2"])
        b.rename(1, 0, to: String(repeating: "x", count: 50))
        XCTAssertEqual(b.list(1)[0].name.count, MasterPresetBook.nameMax)
        b.rename(1, 1, to: "   ")
        XCTAssertEqual(b.list(1)[1].name, "COMP 2", "пустое имя не меняет")
        b.delete(1, 0)
        XCTAssertEqual(b.list(1).count, 1)
        XCTAssertEqual(b.nextName(1), "COMP 3")
        XCTAssertEqual(MasterPresetBook.decode(Data("junk".utf8)), MasterPresetBook())
    }

    func testExtraParams() throws {
        let ratio = try XCTUnwrap(Params.byId["cmp.ratio"])
        XCTAssertEqual(ratio.fromNorm(ratio.toNorm(4)), 4, accuracy: 0.011)
        XCTAssertEqual(ratio.format(2), "2.0:1")
        XCTAssertEqual(ratio.format(20), "20:1")
        let hpf = try XCTUnwrap(Params.byId["cmp.schpf"])
        XCTAssertEqual(hpf.format(20), "OFF")
        XCTAssertEqual(hpf.format(90), "90 Hz")
        let focus = try XCTUnwrap(Params.byId["sat.focus"])
        XCTAssertEqual(focus.format(1500), "1.50 kHz")
    }
}

/// Ввод числом в полях окон модулей мастера.
final class MasterInputTests: XCTestCase {
    private func p(_ id: String) -> ParamDef { return Params.byId[id]! }

    func testParse() {
        XCTAssertEqual(MasterInput.parse(p("lim.ceiling"), "-3,24") ?? 0, -3.2, accuracy: 1e-9)
        XCTAssertEqual(MasterInput.parse(p("lim.ceiling"), "-40"), -24)
        XCTAssertEqual(MasterInput.parse(p("lim.release"), "auto"), MasterChain.autoValue)
        XCTAssertEqual(MasterInput.parse(p("cmp.release"), "1.2 s"), 1200)
        XCTAssertEqual(MasterInput.parse(p("cmp.release"), "80 ms"), 80)
        XCTAssertEqual(MasterInput.parse(p("clip.bass"), "off"), 0)
        XCTAssertEqual(MasterInput.parse(p("clip.bass"), "120 Hz"), 120)
        XCTAssertEqual(MasterInput.parse(p("sat.focus"), "1.5k"), 1500)
        XCTAssertEqual(MasterInput.parse(p("cmp.schpf"), "OFF"), 20)
        XCTAssertEqual(MasterInput.parse(p("sat.type"), "edge"), 2)
        XCTAssertEqual(MasterInput.parse(p("sat.type"), "7"), 2)
        XCTAssertEqual(MasterInput.parse(p("cmp.ratio"), "4"), 4)
        XCTAssertNil(MasterInput.parse(p("lim.input"), "abc"))
    }

    func testText() {
        XCTAssertEqual(MasterInput.text(p("lim.ceiling"), -1), "-1.0")
        XCTAssertEqual(MasterInput.text(p("lim.release"), MasterChain.autoValue), "auto")
        XCTAssertEqual(MasterInput.text(p("lim.release"), 150), "150")
        XCTAssertEqual(MasterInput.text(p("lim.lookahead"), 3), "3.0")
        XCTAssertEqual(MasterInput.text(p("clip.bass"), 0), "off")
        XCTAssertEqual(MasterInput.text(p("cmp.ratio"), 2), "2.00")
        XCTAssertEqual(MasterInput.text(p("sat.type"), 1), "TUBE")
    }
}

/// Окно компрессора: статическая кривая TRANSFER совпадает с GR компрессора на установившемся синусе.
final class GlueCurveTests: XCTestCase {
    func testStaticCurveMatchesDsp() {
        let sr: Double = 48000
        let n: Int = 256
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        for (amp, ratio, knee) in [(0.6, 4.0, 0.0), (0.3, 2.0, 6.0), (0.9, 10.0, 12.0), (0.1, 20.0, 24.0)] {
            let g = MasterGlue(sampleRate: sr)
            var ph: Double = 0
            for _ in 0..<1500 {
                for i in 0..<n {
                    let v = Float(amp * sin(ph))
                    l[i] = v
                    r[i] = v
                    ph += 2 * Double.pi * 1000 / sr
                }
                g.process(inL: l, inR: r, outL: l, outR: r, frames: n, thr: -20, att: 1, rel: 50, auto: false,
                          makeup: 0, ratio: ratio, knee: knee, mix: 100, schpf: 20, bypass: false)
            }
            let want = MasterGlue.staticGr(g.frameDet, thr: -20, ratio: ratio, knee: knee)
            XCTAssertEqual(g.frameGr, want, accuracy: 0.3, "amp \(amp) ratio \(ratio) knee \(knee)")
        }
        XCTAssertEqual(MasterGlue.staticGr(-4, thr: -12, ratio: 4, knee: 0), 6, accuracy: 1e-9)
        XCTAssertEqual(MasterGlue.nextRatio(2), 4)
        XCTAssertEqual(MasterGlue.nextRatio(3.3), 4)
        XCTAssertEqual(MasterGlue.nextRatio(10), 2)
        XCTAssertEqual(MasterGlue.nextRatio(15), 2)
    }
}

/// Окно клиппера: статическая кривая TRANSFER совпадает с пиком выхода клиппера на синусе 200 Гц.
final class ClipCurveTests: XCTestCase {
    func testStaticCurveMatchesDsp() {
        let sr: Double = 48000
        let n: Int = 256
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        for (input, ceiling, soft) in [(0.0, -1.0, 30.0), (6.0, -3.0, 0.0), (12.0, -6.0, 100.0), (6.0, -1.0, 30.0)] {
            let c = MasterClipper(sampleRate: sr)
            var ph: Double = 0
            var outPeak: Double = 0
            var inPeak: Double = 0
            for b in 0..<600 {
                for i in 0..<n {
                    let v = Float(0.5 * sin(ph))
                    l[i] = v
                    r[i] = v
                    ph += 2 * Double.pi * 200 / sr
                }
                c.process(inL: l, inR: r, outL: l, outR: r, frames: n, drive: input, ceiling: ceiling,
                          softness: soft, bass: 0, bypass: false)
                if b > 400 {
                    for i in 0..<n { outPeak = max(outPeak, Double(abs(l[i]))) }
                    inPeak = max(inPeak, c.frameIn)
                }
            }
            let x: Double = 20 * log10(inPeak) - input
            let want: Double = MasterClipper.staticOut(x, input: input, ceiling: ceiling, softness: soft)
            XCTAssertEqual(20 * log10(outPeak), want, accuracy: 0.1, "input \(input) ceiling \(ceiling) soft \(soft)")
        }
    }
}

/// Окно сатуратора: кривая TRANSFER с компенсацией — пик синуса −12 dBFS сохраняется при любом DRIVE.
final class SatCurveTests: XCTestCase {
    func testCompensatedCurve() {
        let t = MasterTables.shared
        for type in 0..<3 {
            XCTAssertEqual(t.satCurve(type, driveDb: 0, 0), 0, accuracy: 1e-9)
            for drive in [0.0, 6.0, 12.0, 24.0] where type != 1 {
                XCTAssertEqual(t.satCurve(type, driveDb: drive, 0.25), 0.25, accuracy: 0.01, "type \(type) drive \(drive)")
            }
            XCTAssertLessThan(t.satCurve(type, driveDb: 24, 1), t.satCurve(type, driveDb: 0, 1) * 1.5 + 1)
        }
        // TUBE несимметричен: пик без постоянной составляющей — около 0,25 (между +x и −x).
        let up = MasterTables.shared.satCurve(1, driveDb: 12, 0.25)
        let dn = MasterTables.shared.satCurve(1, driveDb: 12, -0.25)
        XCTAssertEqual((up - dn) / 2, 0.25, accuracy: 0.03)
    }

    func testTapsOnlyWhenShown() {
        let m = MasterChain(sampleRate: 48000)
        let n = 256
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        l.initialize(repeating: 0.1, count: n)
        r.initialize(repeating: 0.1, count: n)
        var p = MasterChain.defaults
        p.withUnsafeMutableBufferPointer { b in
            m.process(left: l, right: r, frames: n, params: UnsafePointer(b.baseAddress!))
        }
        XCTAssertEqual(m.satIn.written.load(), 0)
        m.satOn.store(1)
        p.withUnsafeMutableBufferPointer { b in
            m.process(left: l, right: r, frames: n, params: UnsafePointer(b.baseAddress!))
        }
        XCTAssertEqual(m.satIn.written.load(), n)
        XCTAssertEqual(m.satOut.written.load(), n)
    }
}
