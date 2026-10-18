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
