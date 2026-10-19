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

/// S11b3: предпрослушка — сэмпл библиотеки в снимке вне дорожек, p-lock ручек пресета.
final class LibraryPreviewTests: XCTestCase {
    func testExtraEntryFoundOnlyForPreview() {
        let p = Project()
        let s = SampleData(left: [Float](repeating: 0.5, count: 100), right: nil)
        let snap = SoundSnapshot(p, samples: ["lib": s], map: .chromatic, extra: ["lib", "missing"])
        let plain = SoundSnapshot(p, samples: ["lib": s], map: .chromatic)
        defer { withExtendedLifetime((snap, plain)) {} }
        let d = snap.data
        XCTAssertEqual(d.extraCount, 1)
        let e = d.anyEntry(SoundKey.hash("lib"))
        XCTAssertEqual(e, d.extraStart)
        XCTAssertEqual(d.eFrames[e], 100)
        // Дорожкам сэмпл не принадлежит.
        XCTAssertEqual(d.entry(0, SoundKey.hash("lib")), -1)
        XCTAssertEqual(plain.data.anyEntry(SoundKey.hash("lib")), -1)
    }

    func testNoteLocksFromPreset() {
        var l = NoteLocks(["harm": 30, "decay": 900, "unknown": 1])
        XCTAssertEqual(l.mask, (UInt16(1) << UInt16(VoiceParam.ids.firstIndex(of: "harm")!))
                       | (UInt16(1) << UInt16(VoiceParam.decay)))
        let decay: Float = withUnsafeBytes(of: &l.vals) { $0.bindMemory(to: Float.self)[VoiceParam.decay] }
        XCTAssertEqual(decay, 900)
    }
}

/// S11b4: свои таблицы WTABLE — разбор WAV, ключи, построение таблицы.
final class UserWavetableTests: XCTestCase {
    /// WAV: 16 бит моно (или float 32 стерео), необязательная метка 'clm '.
    static func wav(_ x: [Float], float: Bool = false, stereo: Bool = false, clm: String? = nil) -> Data {
        let ch = stereo ? 2 : 1
        let bytes = float ? 4 : 2
        var body = Data()
        for v in x {
            for _ in 0..<ch {
                if float {
                    withUnsafeBytes(of: v.bitPattern.littleEndian) { body.append(contentsOf: $0) }
                } else {
                    let s = Int16(max(-32768, min(32767, (v * 32768).rounded())))
                    withUnsafeBytes(of: s.littleEndian) { body.append(contentsOf: $0) }
                }
            }
        }
        func u32(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255), UInt8((v >> 16) & 255), UInt8(v >> 24)] }
        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8)] }
        var fmt = Data(u16(float ? 3 : 1) + u16(ch) + u32(48000) + u32(48000 * ch * bytes) + u16(ch * bytes) + u16(bytes * 8))
        fmt = Data("fmt ".utf8) + Data(u32(fmt.count)) + fmt
        var chunks = fmt
        if let c = clm {
            var t = Data(c.utf8)
            if t.count % 2 == 1 { t.append(0) }
            chunks += Data("clm ".utf8) + Data(u32(t.count)) + t
        }
        chunks += Data("data".utf8) + Data(u32(body.count)) + body
        return Data("RIFF".utf8) + Data(u32(4 + chunks.count)) + Data("WAVE".utf8) + chunks
    }

    func testParseAndFrameSize() throws {
        let x: [Float] = (0..<1024).map { Float(sin(2 * Double.pi * Double($0) / 256)) * 0.5 }
        let w = try XCTUnwrap(WtWav.parse(UserWavetableTests.wav(x)))
        XCTAssertEqual(w.samples.count, 1024)
        XCTAssertEqual(w.samples[64], 0.5, accuracy: 0.001)
        XCTAssertNil(w.clm)
        XCTAssertEqual(WtWav.autoFrameSize(w), 1024)
        let f = try XCTUnwrap(WtWav.parse(UserWavetableTests.wav(x, float: true, stereo: true, clm: "<!>256 10000000")))
        XCTAssertEqual(f.samples, x)
        XCTAssertEqual(f.clm, 256)
        XCTAssertEqual(WtWav.autoFrameSize(f), 256)
        XCTAssertEqual(WtWav.framesFor(f, 256), 4)
        XCTAssertNil(WtWav.parse(Data("RIFF....WAVEjunk".utf8)))
    }

    func testKeys() {
        XCTAssertEqual(WavetableKey.user("abc1", frameSize: 512), "wt:abc1:512")
        XCTAssertEqual(WavetableKey.parseUser("wt:abc1:512")?.wav, "abc1")
        XCTAssertNil(WavetableKey.parseUser("wt:abc1:300"))
        XCTAssertNil(WavetableKey.parseUser("wt:../x:512"))
        XCTAssertNil(WavetableKey.parseUser("builtin:PWM"))
    }

    /// Синус на кадр 256 — в таблице синус кадра 2048 с пиком 1 (вся таблица к пику 1.0, как в вебе).
    func testUserTableIsNormalizedSine() {
        let x: [Float] = (0..<512).map { Float(sin(2 * Double.pi * Double($0) / 256)) * 0.25 }
        let t = WtTable.user(x, frameSize: 256)
        XCTAssertEqual(t.frames, 2)
        let size = t.sizes[0]
        XCTAssertEqual(size, 2048)
        for j in stride(from: 0, to: size, by: 97) {
            XCTAssertEqual(t.data[0][j], Float(sin(2 * Double.pi * Double(j) / Double(size))), accuracy: 0.001)
        }
    }

    func testProjectTableKeys() {
        var p = Project()
        p.tracks[0].table = "wt:aa:2048"
        p.tracks[1].folder.items = [FolderItem(preset: SynthPreset(name: "W", sound: "mi:19", params: [:], table: "wt:bb:256"))]
        p.tracks[2].table = "builtin:PWM"
        XCTAssertEqual(p.tableKeys, ["aa", "bb"])
    }
}

/// Звук шага, которого уже нет в папке дорожки (папку заменила библиотека), остаётся в снимке звука.
final class StepSoundSnapshotTests: XCTestCase {
    func testStepSampleOutsideFolderStaysInSnapshot() {
        var p = Project()
        p.tracks[0].addSamples(["a", "b"])
        p.tracks[0].withStep(2) { $0.on = true }
        p.tracks[0].setStepSound([2], "b")
        p.tracks[0].setFolder([FolderItem(sample: "c")])
        let s = SampleData(left: [Float](repeating: 0.1, count: 10), right: nil)
        let snap = SoundSnapshot(p, samples: ["a": s, "b": s, "c": s], map: .chromatic)
        defer { withExtendedLifetime(snap) {} }
        XCTAssertGreaterThanOrEqual(snap.data.entry(0, SoundKey.hash("b")), 0)
        XCTAssertGreaterThanOrEqual(snap.data.entry(0, SoundKey.hash("c")), 0)
        XCTAssertEqual(snap.data.entry(0, SoundKey.hash("a")), -1)
    }
}
