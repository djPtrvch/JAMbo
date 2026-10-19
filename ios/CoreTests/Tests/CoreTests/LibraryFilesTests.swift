import XCTest
@testable import Core

/// S11c: ZIP (запись, чтение со сжатием), WAV 32-бит float, .jambopreset, архив библиотеки.
final class LibraryFilesTests: XCTestCase {
    private static let deflatedURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("tools/zip/deflated.zip")

    func testZipRoundTrip() throws {
        let e = [ZipEntry(path: "A/", data: Data()), ZipEntry(path: "A/Пэд 1.wav", data: Data([1, 2, 3])),
                 ZipEntry(path: "B.jambopreset", data: Data("{}".utf8))]
        let z = Zip.write(e)
        XCTAssertEqual(Zip.read(z), e)
        XCTAssertNil(Zip.read(Data("not a zip".utf8)))
        XCTAssertEqual(Zip.crc32(Data("123456789".utf8)), 0xcbf43926)
    }

    /// Архив со сжатием (Python zipfile, deflate): папки, служебные файлы macOS пропускаются.
    func testReadsDeflatedZip() throws {
        let entries = try XCTUnwrap(Zip.read(Data(contentsOf: LibraryFilesTests.deflatedURL)))
        XCTAssertEqual(entries.map { $0.path }, ["Kit/", "Kit/Empty/", "Kit/Sub/text.wav", "Kit/Bell.jambopreset", "big.bin"])
        XCTAssertEqual(entries[2].data, Data("RIFF".utf8) + Data((0..<40).flatMap { _ in (0..<256).map { UInt8($0) } }))
        var big = Data()
        for _ in 0..<5000 { big.append(contentsOf: Array("abcabcabd".utf8)) }
        big.append(contentsOf: (0..<20000).map { UInt8($0 * 7 % 251) })
        XCTAssertEqual(entries[4].data, big)
    }

    func testInflateRejectsGarbage() {
        XCTAssertNil(Inflate.inflate(Data([0xff, 0xff, 0xff])))
        // Блок без сжатия (тип 0): «abc».
        XCTAssertEqual(Inflate.inflate(Data([0x01, 0x03, 0x00, 0xfc, 0xff, 0x61, 0x62, 0x63])), Data("abc".utf8))
    }

    func testWavFloat32ReadsBack() throws {
        let l: [Float] = [0, 0.5, -0.25, 1]
        let r: [Float] = [0.1, 0.2, 0.3, 0.4]
        let st = WavFile.float32(left: l, right: r)
        let w = try XCTUnwrap(WtWav.parse(st))
        // Разбор таблиц берёт левый канал.
        XCTAssertEqual(w.samples, l)
        XCTAssertEqual(st.count, 12 + 26 + 12 + 8 + 32)
        XCTAssertEqual(try XCTUnwrap(WtWav.parse(WavFile.float32(left: l, right: nil))).samples, l)
    }

    func testPresetFile() throws {
        let p = SynthPreset(name: "Bell", sound: "mi:18", params: ["harm": 30], table: "wt:abc:512")
        XCTAssertEqual(PresetFile.decode(PresetFile.encode(p), fallback: "x"), p)
        // Файл веба: своя таблица с 's:', без имени — имя файла.
        let web = Data(#"{"jambo":"preset","preset":{"name":"","sound":"mi:19","params":{"harm":1},"table":"wt:s:ab12:2048"}}"#.utf8)
        let w = try XCTUnwrap(PresetFile.decode(web, fallback: "Wave"))
        XCTAssertEqual(w.name, "Wave")
        XCTAssertEqual(w.table, "wt:ab12:2048")
        XCTAssertNil(PresetFile.decode(Data("{}".utf8), fallback: "x"))
    }

    func testLibraryExportAndImportZip() throws {
        var lib = Library()
        let kit = lib.createFolder(Library.root, "Kit")
        _ = lib.createFolder(kit.id, "Empty")
        _ = lib.addSample(kit.id, key: "k1", name: "Kick.aif")
        _ = lib.addPreset(kit.id, SynthPreset(name: "Bell", sound: "mi:18", params: ["harm": 30]))
        _ = lib.addTable(kit.id, key: "wt:t1:2048", name: "Wave")
        _ = lib.addSample(kit.id, key: "gone", name: "Lost")
        let bytes = LibraryBytes(sample: { $0 == "k1" ? Data([1]) : nil }, table: { $0 == "t1" ? Data([2]) : nil })
        let e = lib.entries(lib.node(kit.id)!, prefix: "", bytes)
        XCTAssertEqual(e.map { $0.path }, ["Kit/", "Kit/Empty/", "Kit/Bell.jambopreset", "Kit/Kick.wav", "Kit/Wave.wav"])
        XCTAssertEqual(lib.entries(inside: Library.root, bytes).first?.path, "RECORDINGS/")
        // IMPORT в другую библиотеку: папки восстанавливаются, пресет — сразу, аудио — для декодирования.
        var other = Library()
        let into = other.createFolder(Library.root, "In").id
        let r = other.importZip(try XCTUnwrap(Zip.read(Zip.write(e))), into: into)
        XCTAssertEqual(r.presets, 1)
        XCTAssertEqual(r.audio.map { $0.1 }, ["Kick.wav", "Wave.wav"])
        let k = try XCTUnwrap(other.children(into).first)
        XCTAssertEqual(k.name, "Kit")
        XCTAssertEqual(other.children(k.id).map { $0.name }, ["Empty", "Bell"])
        XCTAssertEqual(r.audio[0].0, k.id)
        XCTAssertEqual(Library.safe("a/b: c?"), "a_b_ c_")
    }
}
