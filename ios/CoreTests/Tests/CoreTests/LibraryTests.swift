import XCTest
@testable import Core

/// S11b1: библиотека (дерево папок), пресеты синта, папка дорожки с пресетами.
final class LibraryTests: XCTestCase {
    func testTreeOrderNamesAndRemove() {
        var lib = Library()
        XCTAssertEqual(lib.node(Library.recordings)?.isSystem, true)
        let drums = lib.createFolder(Library.root, "Drums")
        let bass = lib.createFolder(Library.root, "Bass")
        let k10 = lib.addSample(drums.id, key: "k10", name: "Kick 10")
        _ = lib.addSample(drums.id, key: "k2", name: "Kick 2")
        // Тот же сэмпл в той же папке — тот же узел; другое содержимое с тем же именем — «Kick 10 2».
        XCTAssertEqual(lib.addSample(drums.id, key: "k10", name: "Other").id, k10.id)
        XCTAssertEqual(lib.addSample(drums.id, key: "k11", name: "Kick 10").name, "Kick 10 2")
        let sub = lib.createFolder(drums.id, "Sub")
        _ = lib.addPreset(drums.id, SynthPreset(name: "Bell", sound: "mi:2", params: [:]))
        XCTAssertEqual(lib.children(Library.root).map { $0.name }, ["RECORDINGS", "Bass", "Drums"])
        XCTAssertEqual(lib.children(drums.id).map { $0.name }, ["Sub", "Bell", "Kick 2", "Kick 10", "Kick 10 2"])
        XCTAssertEqual(lib.path(sub.id).map { $0.name }, ["Drums", "Sub"])
        _ = lib.addSample(sub.id, key: "s", name: "Snare")
        XCTAssertEqual(lib.countInside(drums.id), 6)
        XCTAssertEqual(lib.sameName(drums.id, " Bell ")?.kind, .preset)
        XCTAssertNil(lib.sameName(drums.id, "Sub"))
        lib.rename(bass.id, to: "Drums")
        XCTAssertEqual(lib.node(bass.id)?.name, "Drums 2")
        lib.rename(Library.recordings, to: "X")
        lib.remove(Library.recordings)
        XCTAssertEqual(lib.node(Library.recordings)?.name, "RECORDINGS")
        lib.remove(drums.id)
        XCTAssertEqual(lib.nodes.count, 2)
    }

    func testOverwriteAndStore() throws {
        var lib = Library()
        let s = lib.addSample(Library.root, key: "a", name: "Pad")
        lib.overwrite(s.id, with: FolderItem(preset: SynthPreset(name: "x", sound: "mi:5", params: ["harm": 10])))
        XCTAssertEqual(lib.node(s.id)?.kind, .preset)
        XCTAssertEqual(lib.node(s.id)?.preset?.name, "Pad")
        lib.overwrite(s.id, with: FolderItem(sample: "b"))
        XCTAssertEqual(lib.node(s.id)?.key, "b")
        XCTAssertNil(lib.node(s.id)?.preset)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LibraryStore(url: url)
        XCTAssertEqual(store.load(), Library())
        XCTAssertTrue(store.save(lib))
        XCTAssertEqual(store.load(), lib)
        XCTAssertEqual(Library.clean("  "), "Untitled")
        XCTAssertEqual(Library.clean(String(repeating: "a", count: 50)).count, 40)
    }

    func testTrackFolderWithPresets() {
        var t = Track(index: 0)
        t.addSamples(["s1"])
        t.params["harm"] = 77
        let bell = SynthPreset(name: "Bell", sound: "mi:2", params: ["harm": 30, "decay": 900])
        t.addItems([FolderItem(preset: bell)])
        t.stepFolder(1)
        XCTAssertEqual(t.sample, "s1")
        t.stepFolder(1)
        XCTAssertEqual(t.sample, "mi:2")
        XCTAssertEqual(t.params["harm"], 30)
        XCTAssertEqual(t.params["decay"], 900)
        XCTAssertEqual(t.presetName, "Bell")
        t.stepFolder(1)
        XCTAssertEqual(t.sample, "s1")
        XCTAssertEqual(t.presetName, "")
        // Шаг + стрелка: звук шага — пресет и p-lock его ручек.
        t.withStep(0) { $0.on = true }
        t.stepFolderOnSteps([0], 1)
        XCTAssertEqual(t.step(0)?.sound, "mi:2")
        XCTAssertEqual(t.step(0)?.locks["harm"], 30)
        XCTAssertEqual(t.step(0)?.soundLocks?.sorted(), ["decay", "harm"])
        // Пресет из синта дорожки; у WTABLE — с таблицей.
        XCTAssertNil(t.preset(named: "x"))
        t.sample = "mi:19"
        t.table = "builtin:ORGAN"
        let p = t.preset(named: "Wave")
        XCTAssertEqual(p?.table, "builtin:ORGAN")
        XCTAssertEqual(p?.params.count, SynthPreset.params.count)
        t.setFolder([FolderItem(preset: bell), FolderItem(sample: "s2")])
        XCTAssertEqual(t.folder.index, 0)
        XCTAssertEqual(t.sample, "mi:2")
        XCTAssertEqual(t.folder.sampleKeys, ["s2"])
    }

    /// Папка прежних файлов (строки) читается; новая пишется как в вебе ({ sample } / { preset }).
    func testFolderCoding() throws {
        let old = Data(#"{"items":["abc","mi:3"],"index":1}"#.utf8)
        let f = try JSONDecoder().decode(Folder.self, from: old)
        XCTAssertEqual(f.items, ["abc", "mi:3"])
        var g = f
        g.items.append(FolderItem(preset: SynthPreset(name: "P", sound: "mi:1", params: ["timbre": 2])))
        let data = try JSONEncoder().encode(g)
        XCTAssertEqual(try JSONDecoder().decode(Folder.self, from: data), g)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#"{"sample":"abc"}"#))
    }
}
