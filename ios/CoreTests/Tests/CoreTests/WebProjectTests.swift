import XCTest
@testable import Core

/// S11a: импорт проекта веба — эталон ios/tools/webproject/web_project.jambo (настоящие normalizeDoc и packProject веба).
final class WebProjectTests: XCTestCase {
    private static let fileURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("tools/webproject/web_project.jambo")
    private let kick = "996fcd77b06704cb2a060d43"
    private let snare = "cc26a9357310b53250e42f71"

    private func load() throws -> (ProjectPack, Project) {
        let pack = try XCTUnwrap(ProjectPack.decode(Data(contentsOf: WebProjectTests.fileURL)))
        XCTAssertTrue(pack.isWeb)
        let p = try XCTUnwrap(pack.project())
        return (pack, p)
    }

    func testGlobals() throws {
        let (pack, p) = try load()
        XCTAssertEqual(pack.name, "Web Jam")
        XCTAssertEqual(p.bpm, 97)
        XCTAssertEqual(p.scale, 2)
        XCTAssertEqual(p.root, 5)
        XCTAssertEqual(p.tracks.count, 9)
        XCTAssertEqual(p.master["cmp.release"], MasterChain.autoValue)
        XCTAssertEqual(p.master["lim.ceiling"], -2)
        XCTAssertNil(p.master["clip.mix"])
        XCTAssertEqual(Set(p.master.keys), Set(MasterChain.ids.map { $0.id }))
        XCTAssertTrue(p.satBypass)
        XCTAssertFalse(p.limBypass)
        XCTAssertEqual(p.outVol, -60)
        XCTAssertEqual(p.masterEq.bands[0]?.type, 3)
        XCTAssertEqual(p.masterEq.bands[0]?.slope, 1)
        XCTAssertEqual(p.fxAssigns["rev.size"], ModAssign(lfo: 1, amount: 0.3, track: 2))
        XCTAssertEqual(p.scenes[1], SceneRow(name: "DROP", repeats: 4))
        XCTAssertEqual(p.rows, 3)
        XCTAssertEqual(p.arrStart, 1)
        XCTAssertTrue(p.arrEndStop)
        XCTAssertFalse(p.plusCopy)
        XCTAssertFalse(p.rowLoop)
        XCTAssertTrue(p.arrowSwitch)
        XCTAssertFalse(p.prevRow)
        XCTAssertEqual(p.files, [kick: "kick.wav", snare: "snare.wav"])
        XCTAssertEqual(p.roots, [kick: 36])
    }

    func testTrackClipsGetOwnPatternCopies() throws {
        let (_, p) = try load()
        let t = p.tracks[0]
        XCTAssertEqual(t.name, "KICK")
        XCTAssertEqual(t.sample, kick)
        XCTAssertEqual(t.params["filter"], 40)
        XCTAssertEqual(t.assigns["filter"], ModAssign(lfo: 2, amount: -0.5))
        XCTAssertTrue(t.mute)
        XCTAssertEqual(t.vol, -6)
        XCTAssertEqual(t.slot, 2)
        XCTAssertEqual(t.open, 2)
        XCTAssertEqual(t.clips.map { $0 != nil }, (0..<16).map { [0, 2, 5].contains($0) })
        // Активный клип — из полей дорожки.
        let a = try XCTUnwrap(t.clips[2])
        XCTAssertEqual(a.pages.count, 2)
        XCTAssertEqual(a.length, 20)
        XCTAssertEqual(a.playFrom, 0)
        XCTAssertEqual(a.playTo, 1)
        XCTAssertEqual(a.scale, 4)
        XCTAssertEqual(a.root, 7)
        XCTAssertEqual(a.fx?["rev.size"], 70)
        let s = a.pages[0][3]
        XCTAssertTrue(s.on)
        XCTAssertEqual(s.len, 2)
        XCTAssertEqual(s.notes, [60, 64])
        XCTAssertEqual(s.locks, ["filter": 30])
        XCTAssertEqual(s.sound, snare)
        XCTAssertEqual(s.soundLocks, ["decay"])
        XCTAssertEqual(a.pages[1][0].notes, [48])
        // Клип из slots: свои playFrom, гамма, FX; страницы — копия страниц дорожки.
        let c = try XCTUnwrap(t.clips[0])
        XCTAssertEqual(c.pages, a.pages)
        XCTAssertEqual(c.length, 20)
        XCTAssertEqual(c.playFrom, 1)
        XCTAssertEqual(c.playTo, 1)
        XCTAssertEqual(c.scale, 1)
        XCTAssertEqual(c.root, 3)
        XCTAssertEqual(c.fx?["dly.time"], 9)
        // Без гаммы в вебе — гамма проекта (normalizeDoc).
        XCTAssertEqual(t.clips[5]?.scale, 2)
        XCTAssertEqual(t.slices[kick], [SliceMark(at: 0.5, note: 62), SliceMark(at: 0.75)])
        // Папка: сэмплы и пресет синта (S11b), звучит snare. Пресет движка Mutable Instruments (mi:2) — пустой (S12).
        let bell = SynthPreset(name: "Bell", sound: "", params: ["harm": 30], fmt: 2)
        XCTAssertEqual(t.folder, Folder(items: [FolderItem(sample: kick), FolderItem(preset: bell), FolderItem(sample: snare)],
                                        index: 2))
        let q = t.eq.bands[1]
        XCTAssertEqual(q?.ms, 1)
        XCTAssertEqual(q?.dyn, 2)
        XCTAssertEqual(q?.thr, -30)
    }

    func testBlankStoppedTablesAndChannels() throws {
        let (_, p) = try load()
        let t1 = p.tracks[1]
        XCTAssertEqual(t1.sample, "", "звук движка Mutable Instruments (mi:3) — пустой (S12)")
        XCTAssertEqual(t1.slot, 1)
        XCTAssertTrue(t1.blank)
        XCTAssertTrue(t1.stopped)
        XCTAssertTrue(t1.solo)
        XCTAssertNotNil(t1.clips[0])
        XCTAssertEqual(t1.table, "builtin:ORGAN")
        XCTAssertEqual(t1.vol, -60)
        // Своя таблица WTABLE (S11b4): ключ без 's:', WAV — отдельно от сэмплов.
        XCTAssertEqual(p.tracks[2].sample, "mi:19")
        XCTAssertEqual(p.tracks[2].table, "wt:b4ea7a86523069b0187961e4:2048")
        XCTAssertEqual(p.tableKeys, ["b4ea7a86523069b0187961e4"])
        XCTAssertEqual(p.tracks[8].name, "9")
        XCTAssertEqual(p.chanSeqs.map { $0.name }, ["MIX", "MST"])
        XCTAssertEqual(p.chanSeqs[0].clips[0]?.pages[0][0].locks, ["mix.vol1": -12])
        XCTAssertEqual(p.chanSeqs[1].clips[0]?.pages[0][4].locks, ["lim.ceiling": -3])
        XCTAssertEqual(p.chanSeqs[0].clips.count, 16)
    }

    func testSamplesForProject() throws {
        let (pack, p) = try load()
        XCTAssertEqual(pack.samples.count, 3)
        let s = pack.samples(for: p)
        XCTAssertEqual(s.map { $0.key }, [kick, snare])
        XCTAssertEqual(s.map { $0.name }, ["kick.wav", "snare.wav"])
        XCTAssertEqual(p.sampleKeys, [kick, snare])
        let t = pack.tables(for: p)
        XCTAssertEqual(t.map { $0.key }, ["b4ea7a86523069b0187961e4"])
        // WAV таблицы — 2048 × 4 отсчётов, 4 кадра по 2048.
        let w = try XCTUnwrap(WtWav.parse(t[0].bytes))
        XCTAssertEqual(w.samples.count, 8192)
        XCTAssertEqual(WtWav.autoFrameSize(w), 2048)
        XCTAssertEqual(WtWav.framesFor(w, 2048), 4)
    }

    /// Импортированный проект сохраняется и читается обычным файлом Swift-версии без потерь.
    func testConvertedProjectRoundTrips() throws {
        let (_, p) = try load()
        let data = try XCTUnwrap(ProjectFormat.encode(ProjectFile(info: ProjectInfo(id: "p1", name: "W", updated: 1), doc: p)))
        XCTAssertEqual(ProjectFormat.decode(data)?.doc, p)
    }

    func testImportAndExportNames() {
        let list = [ProjectInfo(id: "a", name: "Web Jam", updated: 0), ProjectInfo(id: "b", name: "Project 1", updated: 0)]
        XCTAssertEqual(ProjectSession.importedName("Web Jam", in: list), "Web Jam (imported)")
        XCTAssertEqual(ProjectSession.importedName("New", in: list), "New")
        XCTAssertEqual(ProjectSession.importedName("  ", in: list), "Project 2")
        XCTAssertEqual(ProjectSession.exportFileName("My Jam/2: dub"), "My Jam_2_ dub.jambo")
        XCTAssertEqual(ProjectSession.exportFileName(""), "project.jambo")
    }
}
