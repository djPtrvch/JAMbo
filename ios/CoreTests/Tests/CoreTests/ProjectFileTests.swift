import XCTest
@testable import Core

/// S9a: файл проекта, чтение прежних и неполных файлов, хранилище проектов.
final class ProjectFileTests: XCTestCase {
    private func sample() -> Project {
        var p = Project()
        p.bpm = 97
        p.scale = 1
        p.root = 9
        p.outVol = -Double.infinity
        p.master["cmp.release"] = MasterChain.autoValue
        p.tracks[0].sample = "abc123"
        p.tracks[0].folder = Folder(items: ["abc123", "mi:3"], index: 0)
        p.tracks[0].slices["abc123"] = [SliceMark(at: 0.5, note: 62)]
        p.tracks[0].assigns["filter"] = ModAssign(lfo: 2, amount: -0.5)
        p.tracks[1].withStep(3) { s in
            s.on = true
            s.addNote(60, len: 3, vel: 100)
            s.addNote(64, len: 1, vel: nil)
            s.locks["filter"] = 40
            s.sound = "def456"
        }
        p.tracks[2].clips[5] = Clip(pages: [Track.emptyPage(), Track.emptyPage()], length: 20, playFrom: 0, playTo: 1,
                                    scale: 3, root: 2, fx: ["rev.size": 30])
        var b = EqBand(type: EqSpec.bell, freq: 300, gain: -4, q: 2)
        b.dyn = 2
        p.tracks[3].eq.bands[1] = b
        p.scenes[2] = SceneRow(name: "DROP", repeats: 4)
        p.rows = 3
        return p
    }

    private func info() -> ProjectInfo {
        return ProjectInfo(id: "p1", name: "Jam", updated: 1000)
    }

    func testRoundTripKeepsEverything() throws {
        let p = sample()
        let data = try XCTUnwrap(ProjectFormat.encode(ProjectFile(info: info(), doc: p)))
        let f = try XCTUnwrap(ProjectFormat.decode(data))
        XCTAssertEqual(f.doc, p)
        XCTAssertEqual(f.info.name, "Jam")
        XCTAssertEqual(f.info.bpm, 97)
        XCTAssertEqual(f.info.root, 9)
        XCTAssertEqual(f.info.scale, 1)
        let s = try XCTUnwrap(f.doc.tracks[1].step(3))
        XCTAssertEqual(s.lens, [3, 1])
        XCTAssertEqual(s.vels, [100, -1])
        XCTAssertEqual(f.doc.outVol, -Double.infinity)
    }

    func testRepairKeepsValidProject() {
        let ref = sample()
        var p = ref
        p.repair()
        XCTAssertEqual(p, ref)
        var q = Project()
        q.repair()
        XCTAssertEqual(q.tracks.count, Params.trackCount)
        XCTAssertEqual(q.fx, Project().fx)
    }

    func testMissingFieldsGetDefaults() throws {
        let json = """
        {"format":"jambo-swift","version":1,"future":42,
         "info":{"id":"x","name":"Old","updated":5},
         "doc":{"bpm":999,"scale":77,"rows":0,"newField":{"a":1},
                "tracks":[{"name":"KICK","vol":"loud","params":{"filter":12},
                           "clips":[{"pages":[[{"on":true,"notes":[60,64],"lens":[2],"vels":[90,80]}]],
                                     "length":500,"playTo":9}],
                           "eq":{"bands":[{"type":0,"freq":200,"gain":3,"q":1,"dyn":40}]}}]}}
        """
        let f = try XCTUnwrap(ProjectFormat.decode(Data(json.utf8)))
        let d = f.doc
        XCTAssertEqual(d.bpm, Params.bpmMax)
        XCTAssertEqual(d.scale, Scales.all.count - 1)
        XCTAssertEqual(d.rows, 1)
        XCTAssertEqual(d.tracks.count, Params.trackCount)
        XCTAssertEqual(d.chanSeqs.map { $0.name }, ["MIX", "MST"])
        XCTAssertEqual(d.scenes.count, Params.patternSlots)
        XCTAssertEqual(d.master, MasterChain.defaultValues())
        let t = d.tracks[0]
        XCTAssertEqual(t.name, "KICK")
        XCTAssertEqual(t.vol, Params.volDef)
        XCTAssertEqual(t.params["filter"], 12)
        XCTAssertEqual(t.params.count, Params.defaults().count)
        XCTAssertEqual(t.clips.count, Params.patternSlots)
        let c = try XCTUnwrap(t.clips[0])
        XCTAssertEqual(c.pages[0].count, Params.stepsPerPage)
        XCTAssertEqual(c.length, Params.stepsPerPage)
        XCTAssertEqual(c.playTo, 0)
        let s = c.pages[0][0]
        XCTAssertTrue(s.on)
        XCTAssertNil(s.lens)
        XCTAssertEqual(s.vels, [90, 80])
        XCTAssertEqual(t.eq.bands.count, EqSpec.bands)
        XCTAssertEqual(t.eq.bands[0]?.dyn, -1)
        XCTAssertEqual(t.eq.bands[0]?.freq, 200)
    }

    /// Каждое поле модели — в CodingKeys (иначе оно молча не сохранится).
    func testCodingKeysCoverAllFields() {
        func check<K: CaseIterable & RawRepresentable>(_ value: Any, _ keys: K.Type) where K.RawValue == String {
            let fields = Set(Mirror(reflecting: value).children.compactMap { $0.label })
            XCTAssertEqual(fields, Set(K.allCases.map { $0.rawValue }), "\(type(of: value))")
        }
        check(Project(), Project.CodingKeys.self)
        check(Track(index: 0), Track.CodingKeys.self)
        check(Clip(), Clip.CodingKeys.self)
        check(Step(), Step.CodingKeys.self)
        check(SceneRow(), SceneRow.CodingKeys.self)
        check(ModAssign(lfo: 1, amount: 0), ModAssign.CodingKeys.self)
        check(Eq(), Eq.CodingKeys.self)
        check(EqBand(type: 0, freq: 100, gain: 0, q: 1), EqBand.CodingKeys.self)
        check(Folder(), Folder.CodingKeys.self)
        check(SliceMark(at: 0), SliceMark.CodingKeys.self)
    }

    func testNotAProject() {
        XCTAssertNil(ProjectFormat.decode(Data("{\"format\":\"other\",\"version\":1}".utf8)))
        XCTAssertNil(ProjectFormat.decode(Data("not json".utf8)))
    }

    func testSampleKeys() {
        XCTAssertEqual(sample().sampleKeys, ["abc123", "def456"])
    }

    func testStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jambo-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(dir: dir)
        XCTAssertTrue(store.list().isEmpty)
        let a = sample()
        XCTAssertTrue(store.save(a, info: ProjectInfo(id: "pa", name: "A", updated: 10)))
        XCTAssertTrue(store.save(Project(), info: ProjectInfo(id: "pb", name: "B", updated: 20)))
        XCTAssertTrue(store.save(Project(), info: ProjectInfo(id: ProjectStore.autosaveId, name: "Autosave", updated: 30,
                                                            projectId: "pa", projectName: "A")))
        XCTAssertFalse(store.save(Project(), info: ProjectInfo(id: "../x", name: "X", updated: 1)))
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("junk.json"))
        XCTAssertEqual(store.list().map { $0.id }, [ProjectStore.autosaveId, "pb", "pa"])
        XCTAssertEqual(store.list().last?.bpm, 97)
        XCTAssertEqual(store.load("pa")?.doc, a)
        XCTAssertEqual(store.load(ProjectStore.autosaveId)?.info.projectId, "pa")
        XCTAssertTrue(store.rename("pa", to: "A2"))
        XCTAssertEqual(store.load("pa")?.info.name, "A2")
        XCTAssertEqual(store.load("pa")?.info.updated, 10)
        XCTAssertEqual(store.find(name: "A2")?.id, "pa")
        XCTAssertNil(store.find(name: "Autosave"))
        store.delete("pb")
        XCTAssertNil(store.load("pb"))
        XCTAssertEqual(store.list().count, 2)
        XCTAssertNotEqual(ProjectStore.newId(), ProjectStore.newId())
    }
}

/// S9b: текущий проект, Autosave, пометка «unsaved».
final class ProjectSessionTests: XCTestCase {
    private func tempStore() -> ProjectStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jambo-test-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return ProjectStore(dir: dir)
    }

    func testStartFresh() {
        let store = tempStore()
        XCTAssertTrue(store.save(Project(), info: ProjectInfo(id: "pa", name: "Project 1", updated: 1)))
        let (s, p) = ProjectSession.start(store, last: nil)
        XCTAssertEqual(s.name, "Project 2")
        XCTAssertNotEqual(s.id, "pa")
        XCTAssertTrue(s.unsaved(p))
        XCTAssertTrue(s.needsAutosave(p))
    }

    func testStartFromAutosaveKeepsProject() {
        let store = tempStore()
        var saved = Project()
        saved.bpm = 100
        var work = saved
        work.bpm = 130
        XCTAssertTrue(store.save(saved, info: ProjectInfo(id: "pa", name: "Jam", updated: 1)))
        let s0 = ProjectSession(id: "pa", name: "Jam")
        XCTAssertTrue(store.save(work, info: s0.autosaveInfo(now: 2)))
        let (s, p) = ProjectSession.start(store, last: "pa")
        XCTAssertEqual(s.id, "pa")
        XCTAssertEqual(s.name, "Jam")
        XCTAssertEqual(p.bpm, 130)
        XCTAssertTrue(s.unsaved(p))
        XCTAssertFalse(s.needsAutosave(p))
        var back = p
        back.bpm = 100
        XCTAssertFalse(s.unsaved(back))
    }

    func testStartFromLastProject() {
        let store = tempStore()
        var saved = Project()
        saved.bpm = 90
        XCTAssertTrue(store.save(saved, info: ProjectInfo(id: "pa", name: "Jam", updated: 1)))
        let (s, p) = ProjectSession.start(store, last: "pa")
        XCTAssertEqual(s.name, "Jam")
        XCTAssertEqual(p.bpm, 90)
        XCTAssertFalse(s.unsaved(p))
        XCTAssertTrue(s.needsAutosave(p))
    }
}

/// S9c: NEW, SAVE, SAVE AS, RENAME, удаление из списка.
final class ProjectActionsTests: XCTestCase {
    private func tempStore() -> ProjectStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jambo-test-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return ProjectStore(dir: dir)
    }

    func testSaveAndSaveAs() {
        let store = tempStore()
        var s = ProjectSession.fresh(store)
        var p = Project()
        p.bpm = 111
        XCTAssertTrue(s.save(p, store: store, now: 5))
        XCTAssertFalse(s.unsaved(p))
        XCTAssertEqual(store.list().map { $0.name }, ["Project 1"])
        let first = s.id
        p.bpm = 122
        XCTAssertTrue(s.unsaved(p))
        XCTAssertTrue(s.saveAs(p, name: "  Copy of a very long project name here  ", replace: nil, store: store, now: 6))
        XCTAssertNotEqual(s.id, first)
        XCTAssertEqual(s.name, "Copy of a very long proj")
        XCTAssertEqual(s.name.count, ProjectSession.nameLimit)
        XCTAssertFalse(s.unsaved(p))
        XCTAssertEqual(store.load(first)?.doc.bpm, 111)
        XCTAssertEqual(store.load(s.id)?.doc.bpm, 122)
        XCTAssertEqual(ProjectSession.nextName(store.list()), "Project 2")
    }

    func testSaveAsOverwrite() {
        let store = tempStore()
        var a = ProjectSession(id: "pa", name: "A")
        XCTAssertTrue(a.save(Project(), store: store, now: 1))
        var b = ProjectSession(id: "pb", name: "B")
        var p = Project()
        p.bpm = 140
        XCTAssertNil(b.named("B", in: store.list()))
        let same = b.named(" A ", in: store.list())
        XCTAssertEqual(same?.id, "pa")
        XCTAssertTrue(b.saveAs(p, name: "A", replace: same, store: store, now: 2))
        XCTAssertEqual(b.id, "pa")
        XCTAssertEqual(store.list().count, 1)
        XCTAssertEqual(store.load("pa")?.doc.bpm, 140)
    }

    func testRenameAndDelete() {
        let store = tempStore()
        var s = ProjectSession(id: "pa", name: "A")
        XCTAssertTrue(s.save(Project(), store: store, now: 1))
        XCTAssertTrue(store.save(Project(), info: ProjectInfo(id: "pb", name: "B", updated: 2)))
        s.rename("A2", store: store)
        XCTAssertEqual(s.name, "A2")
        XCTAssertEqual(store.load("pa")?.info.name, "A2")
        s.rename("   ", store: store)
        XCTAssertEqual(s.name, "A2")
        s.rename(id: "pb", to: "B2", store: store)
        XCTAssertEqual(store.load("pb")?.info.name, "B2")
        XCTAssertEqual(s.name, "A2")
        s.rename(id: "pa", to: "A3", store: store)
        XCTAssertEqual(s.name, "A3")
        s.delete(id: "pa", store: store)
        XCTAssertNil(store.load("pa"))
        XCTAssertTrue(s.unsaved(Project()))
        XCTAssertEqual(s.name, "A3")
    }

    func testMeta() {
        var i = ProjectInfo(id: "p", name: "x", updated: 0)
        i.bpm = 119.6
        i.root = 0
        i.scale = 1
        XCTAssertEqual(ProjectSession.meta(i), "120 · C Min")
    }
}

/// S9: MORPH на все дорожки, возврат после выключения, подстройка громкости (trim).
final class MorphModesTests: XCTestCase {
    func testShiftAllTracksKeepsOffsets() throws {
        var p = Project()
        let f = try XCTUnwrap(Params.byId["filter"])
        p.tracks[0].params["filter"] = f.fromNorm(0.5)
        p.tracks[1].params["filter"] = f.fromNorm(0.2)
        p.tracks[2].params["filter"] = f.fromNorm(0.9)
        p.tracks[0].morphParam("filter")
        p.tracks[0].params["filter"] = f.fromNorm(0.6)
        p.morphShift(from: 0, id: "filter", norm: 0.6)
        XCTAssertEqual(f.toNorm(p.tracks[1].params["filter"] ?? 0), 0.3, accuracy: 1e-6)
        XCTAssertEqual(f.toNorm(p.tracks[2].params["filter"] ?? 0), 1.0, accuracy: 1e-6)
        XCTAssertTrue(p.tracks[1].morphEdited)
        // Вернули ручку — соотношение прежнее (у края не потерялось).
        p.tracks[0].params["filter"] = f.fromNorm(0.5)
        p.morphShift(from: 0, id: "filter", norm: 0.5)
        XCTAssertEqual(f.toNorm(p.tracks[2].params["filter"] ?? 0), 0.9, accuracy: 1e-6)
    }

    func testReturnGlide() throws {
        var p = Project()
        let f = try XCTUnwrap(Params.byId["filter"])
        p.tracks[0].params["filter"] = f.fromNorm(0.2)
        p.tracks[0].morphParam("filter")
        p.tracks[0].params["filter"] = f.fromNorm(0.8)
        let pts = p.morphReturnPoints()
        XCTAssertEqual(pts.count, 1)
        p.applyMorphReturn(pts, 0.5)
        XCTAssertEqual(f.toNorm(p.tracks[0].params["filter"] ?? 0), 0.5, accuracy: 1e-6)
        p.applyMorphReturn(pts, 1)
        XCTAssertEqual(p.tracks[0].params["filter"], f.fromNorm(0.2))
        XCTAssertEqual(MorphReturn.seconds(3, bpm: 120), 2, accuracy: 1e-9)
        XCTAssertEqual(MorphReturn.seconds(0, bpm: 120), 0)
    }

    func testTrimLowersTrackGain() {
        var p = Project()
        p.tracks[0].vol = -10
        p.tracks[0].trim = -6
        let s = SoundSnapshot(p, samples: [:], map: .chromatic)
        XCTAssertEqual(Double(s.data.gain[0]), Params.volGain(-16), accuracy: 1e-6)
        let abs = SoundSnapshot(p, samples: [:], map: .chromatic, levelRelative: false)
        XCTAssertEqual(Double(abs.data.gain[0]), Params.volGain(-10), accuracy: 1e-6, "ABSOLUTE — ровно громкость MIX")
        XCTAssertEqual(abs.data.trim[0], 1)
        p.tracks[0].trim = Params.volMin
        let q = SoundSnapshot(p, samples: [:], map: .chromatic)
        XCTAssertEqual(q.data.gain[0], 0)
    }

    func testSettingsDefaults() {
        let s = AppSettings.decode(Data("{\"morphReturn\":99}".utf8))
        XCTAssertFalse(s.levelRelative)
        XCTAssertTrue(s.morphAll, "ALL TRACKS по умолчанию включён")
        XCTAssertEqual(s.morphReturn, 0)
        XCTAssertTrue(s.mixKey)
        XCTAssertTrue(s.mixCrossfader)
    }
}
