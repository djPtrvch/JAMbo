import XCTest
@testable import Core

/// Версия 6 (ТЗ «Granular»): ручки GRANULAR прежних проектов и пресетов — по новым формулам, звук прежний.
final class GranularMigrationTests: XCTestCase {
    /// Длина зерна и зёрен в секунду — те же; разброс позиции — тот же.
    func testKnobs() {
        let r = GranularMigration.knobs(size: 45, density: 55, spray: 20)
        let oldSec = 0.005 * pow(100, 0.45), oldRate = 2 * pow(40, 0.55)
        XCTAssertEqual(TexGran.grainSize(r.s / 100), oldSec, accuracy: 1e-9)
        XCTAssertEqual(TexGran.overlap(r.d / 100) / TexGran.grainSize(r.s / 100), oldRate, accuracy: 1e-6)
        XCTAssertEqual(TexGran.posSpread(r.p / 100), 0.35 * 0.2, accuracy: 1e-9)
        // Края: зерно короче 10 мс — 10 мс, перекрытие больше 24 — 24, SPRAY выше 57 % — 100 %.
        let e = GranularMigration.knobs(size: 0, density: 100, spray: 100)
        XCTAssertEqual(e.s, 0)
        XCTAssertEqual(GranularMigration.knobs(size: 100, density: 100, spray: 0).d, 100)
        XCTAssertEqual(e.p, 100)
    }

    func testProject() throws {
        var p = Project()
        p.version = 5
        p.tracks[0].setSynth(Jambo.granular)
        p.tracks[0].params["timbre"] = 45
        p.tracks[0].params["morph"] = 55
        p.tracks[0].params["p4"] = 20
        p.tracks[0].pages[0][2].locks = ["morph": 80, "level": 90]
        var blk = ArrBlock(clip: 0, start: 0, length: 16)
        blk.autos = [ArrAutoLane(param: "p4", points: [ArrAutoPoint(x: 1, y: 0.2)])]
        p.tracks[0].blocks = [blk]
        p.tracks[1].setSynth(Jambo.analog)
        p.tracks[1].params["timbre"] = 45
        let pr = SynthPreset(name: "G", sound: "mi:26", params: ["timbre": 45, "morph": 55, "p4": 20], fmt: 3)
        p.tracks[1].folder.items = [FolderItem(preset: pr)]
        let data = try JSONEncoder().encode(p)
        var q = try JSONDecoder().decode(Project.self, from: data)
        q.repair()
        XCTAssertEqual(q.version, 8)
        let want = GranularMigration.knobs(size: 45, density: 55, spray: 20)
        let t = q.tracks[0]
        XCTAssertEqual(t.params["timbre"]!, want.s, accuracy: 1e-9)
        XCTAssertEqual(t.params["morph"]!, want.d, accuracy: 1e-9)
        XCTAssertEqual(t.params["p4"]!, want.p, accuracy: 1e-9)
        XCTAssertEqual(t.params["harm"], 8, "POSITION не меняется")
        // P-lock DENSITY — по SIZE дорожки (прежнему), остальное у шага не трогается.
        XCTAssertEqual(t.pages[0][2].locks["morph"]!, GranularMigration.knobs(size: 45, density: 80, spray: 0).d, accuracy: 1e-9)
        XCTAssertEqual(t.pages[0][2].locks["level"], 90)
        XCTAssertNil(t.pages[0][2].locks["timbre"])
        XCTAssertEqual(t.blocks.first?.autos.first?.points.first?.y ?? -1, want.p / 100, accuracy: 1e-9)
        // Другой движок — как был; пресет GRANULAR в папке — переведён.
        XCTAssertEqual(q.tracks[1].params["timbre"], 45)
        let qp = q.tracks[1].folder.items[0].preset!
        XCTAssertEqual(qp.fmt, 4)
        XCTAssertEqual(qp.params["morph"]!, want.d, accuracy: 1e-9)
        // Повторно не переводится.
        var again = q
        again.repair()
        XCTAssertEqual(again.tracks[0].params, q.tracks[0].params)
        // Новый проект — версия 6, ручки по умолчанию как есть.
        var n = Project()
        n.tracks[0].setSynth(Jambo.granular)
        n.repair()
        XCTAssertEqual(n.tracks[0].params["timbre"], 62)
    }
}
