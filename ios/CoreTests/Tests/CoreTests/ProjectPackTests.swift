import XCTest
@testable import Core

/// S11a1: файл проекта .jambo (контейнер JMB1, как в вебе).
final class ProjectPackTests: XCTestCase {
    private func project() -> Project {
        var p = Project()
        p.bpm = 101
        p.outVol = -Double.infinity
        p.tracks[0].sample = "abc"
        return p
    }

    func testSwiftRoundTrip() throws {
        let s1 = PackSample(key: "abc", name: "kick.caf", bytes: Data([1, 2, 3]))
        let s2 = PackSample(key: "def", name: "empty.caf", bytes: Data())
        let orig = project()
        let pack = try XCTUnwrap(ProjectPack.swift(name: "Jam", doc: orig, samples: [s1, s2]))
        let data = try XCTUnwrap(pack.encoded())
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "JMB1")
        let back = try XCTUnwrap(ProjectPack.decode(data))
        XCTAssertEqual(back.format, ProjectFormat.name)
        XCTAssertEqual(back.version, ProjectFormat.version)
        XCTAssertEqual(back.name, "Jam")
        XCTAssertEqual(back.samples, [s1, s2])
        XCTAssertFalse(back.isWeb)
        let p = try XCTUnwrap(back.swiftProject())
        XCTAssertEqual(p, orig)
    }

    /// Файл, собранный как packProject веба: формат jambo, длина заголовка старшим байтом вперёд.
    func testReadsWebLayout() throws {
        let header = #"{"format":"jambo","version":1,"name":"Web","doc":{"bpm":90,"tracks":[]},"samples":[{"key":"s:00ff","name":"a.wav","size":2},{"key":"s:11","name":"b.mp3","size":3}]}"#
        let h = Data(header.utf8)
        var data = Data("JMB1".utf8)
        data.append(contentsOf: [0, 0, UInt8(h.count >> 8), UInt8(h.count & 0xff)])
        data.append(h)
        data.append(contentsOf: [9, 8, 7, 6, 5])
        let pack = try XCTUnwrap(ProjectPack.decode(data))
        XCTAssertTrue(pack.isWeb)
        XCTAssertEqual(pack.name, "Web")
        XCTAssertEqual(pack.samples.map { $0.key }, ["s:00ff", "s:11"])
        XCTAssertEqual(pack.samples[0].bytes, Data([9, 8]))
        XCTAssertEqual(pack.samples[1].bytes, Data([7, 6, 5]))
        XCTAssertEqual(pack.samples[1].name, "b.mp3")
        let doc = try XCTUnwrap(JSONSerialization.jsonObject(with: pack.doc) as? [String: Any])
        XCTAssertEqual(doc["bpm"] as? Int, 90)
        XCTAssertNil(pack.swiftProject())
    }

    func testRejectsBrokenFiles() throws {
        XCTAssertNil(ProjectPack.decode(Data()))
        XCTAssertNil(ProjectPack.decode(Data("JMB2xxxx{}".utf8)))
        let pack = try XCTUnwrap(ProjectPack.swift(name: "J", doc: project(),
                                                   samples: [PackSample(key: "k", name: "n", bytes: Data([1, 2, 3, 4]))]))
        let data = try XCTUnwrap(pack.encoded())
        // Обрезан конец сэмпла или заголовок.
        XCTAssertNil(ProjectPack.decode(data.dropLast(1)))
        XCTAssertNil(ProjectPack.decode(data.prefix(20)))
        // Срез Data с ненулевым началом читается так же.
        var shifted = Data([0, 0])
        shifted.append(data)
        XCTAssertEqual(ProjectPack.decode(shifted.dropFirst(2))?.samples.first?.bytes, Data([1, 2, 3, 4]))
    }
}
