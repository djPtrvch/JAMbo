import XCTest
@testable import Core

/// Dynamic EQ (S7b): правки, номер источника за дорожкой, порядок микшера, источник-дорожка в звуке, сдвиг для экрана.
final class EqDynTests: XCTestCase {
    func testEdits() {
        var p = Project()
        XCTAssertEqual(p.addEqBand(0, freq: 100, gain: 0), 0)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.dyn, -1)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.thr, -24)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.range, -6)
        p.setEqDyn(0, 0, 3)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.dyn, 3)
        p.setEqDyn(0, 0, 99)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.dyn, Params.maxTracks)
        p.setEqDyn(0, 0, -5)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.dyn, -1)
        p.setEqDynParams(0, 0, thr: -70, range: 7.26)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.thr, -60)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.range, 7.3)
        p.setEqDynParams(0, 0, thr: 3, range: -30)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.thr, 0)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.range, -18)
    }

    /// Снимок: источник — только у bell и shelf; у cut и notch — −1.
    func testFill() {
        var e = Eq()
        var b = EqBand(type: EqSpec.highShelf, freq: 5000, gain: 3, q: 1)
        b.dyn = 2
        b.thr = -30
        b.range = 9
        e.bands[0] = b
        b.type = EqSpec.notch
        e.bands[1] = b
        let p = UnsafeMutablePointer<Double>.allocate(capacity: EqSpec.stride)
        defer { p.deallocate() }
        EqSpec.fill(p, e)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: p + 1 + 6, count: 3)), [2, -30, 9])
        XCTAssertEqual(p[1 + EqSpec.bandStride + 6], -1)
    }

    /// Номер источника следует за дорожкой при перестановке; удалённая дорожка — OFF (как в вебе).
    func testRemap() {
        var p = Project()
        p.addEqBand(0, freq: 100, gain: 0)
        p.setEqDyn(0, 0, 3)
        p.addEqBand(EqSpec.masterChannel, freq: 100, gain: 0)
        p.setEqDyn(EqSpec.masterChannel, 0, 2)
        let id3 = p.tracks[2].id
        p.moveTrack(2, 3)
        XCTAssertEqual(p.tracks[3].id, id3)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.dyn, 4)
        XCTAssertEqual(p.masterEq.bands[0]?.dyn, 2)
        p.moveTrack(3, 0)
        // Дорожка с EQ (была 0) — теперь 1; её источник (id3) — дорожка 0.
        XCTAssertEqual(p.tracks[0].id, id3)
        XCTAssertEqual(p.tracks[1].eq.bands[0]?.dyn, 1)
        XCTAssertEqual(p.masterEq.bands[0]?.dyn, 3)
        p.addTrack()
        p.deleteTrack(0)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.dyn, -1)
        XCTAssertEqual(p.masterEq.bands[0]?.dyn, 2)
    }

    /// Порядок микшера: источник — раньше того, кто его слушает; в кольце — меньший номер первым.
    func testMixOrder() {
        var p = Project()
        XCTAssertEqual(EqSpec.mixOrder(p, 3), [0, 1, 2])
        p.addEqBand(0, freq: 100, gain: 0)
        p.setEqDyn(0, 0, 3)
        XCTAssertEqual(EqSpec.mixOrder(p, 3), [1, 2, 0])
        p.addEqBand(2, freq: 100, gain: 0)
        p.setEqDyn(2, 0, 1)
        XCTAssertEqual(EqSpec.mixOrder(p, 3), [1, 0, 2], "кольцо 0 ↔ 2: сначала 1, затем меньший номер")
        p.setEqDyn(2, 0, 2)
        XCTAssertEqual(EqSpec.mixOrder(p, 3), [1, 2, 0])
        p.tracks[0].eq.on = false
        XCTAssertEqual(EqSpec.mixOrder(p, 3), [0, 1, 2], "BYPASS — источника нет")
    }

    private func render(_ core: AudioCore, frames: Int) -> [Float] {
        var out: [Float] = []
        var bl = [Float](repeating: 0, count: 256), br = [Float](repeating: 0, count: 256)
        while out.count < frames {
            core.render(frames: 256, left: &bl, right: &br)
            out += bl
        }
        return out
    }

    private func rms(_ x: ArraySlice<Float>) -> Double {
        return sqrt(x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(1, x.count)))
    }

    /// Дорожка 0 — синус 100 Гц, bell 100 Гц с источником T2 (сдвиг −12 dB, порог −40); дорожка 1 — громкий синус,
    /// заглушена (источник — до mute). track — номер дорожки-слушателя (0 или 2: источник раньше или позже в списке).
    private func duck(_ source: Bool, listener: Int = 0) -> (Double, Float) {
        let core = AudioCore(master: false)
        var p = Project()
        p.tracks[listener].addSamples(["s"])
        p.tracks[listener].vol = 0
        p.tracks[1].addSamples(["k"])
        p.tracks[1].mute = true
        p.addEqBand(listener, freq: 100, gain: 0)
        p.setEqDyn(listener, 0, 2)
        p.setEqDynParams(listener, 0, thr: -40, range: -12)
        let s = SampleData(left: (0..<48000).map { Float(0.5 * sin(2 * Double.pi * 100 * Double($0) / 48000)) }, right: nil)
        let k = SampleData(left: (0..<48000).map { Float(0.5 * sin(2 * Double.pi * 100 * Double($0) / 48000)) }, right: nil)
        core.publish(p, samples: ["s": s, "k": k])
        _ = render(core, frames: 4096)
        core.events.push(.noteOn(track: listener, note: 48, id: 1, velocity: 1))
        if source { core.events.push(.noteOn(track: 1, note: 48, id: 2, velocity: 1)) }
        let o = render(core, frames: 24000)
        return (rms(o[12000..<24000]), core.eqDyn.offset(listener, 0))
    }

    func testTrackSource() {
        let (dry, off0) = duck(false)
        let (ducked, off1) = duck(true)
        XCTAssertGreaterThan(dry, 0.1)
        XCTAssertEqual(off0, 0)
        XCTAssertEqual(off1, -12, accuracy: 0.01, "источник громкий — сдвиг упирается в RANGE")
        XCTAssertEqual(20 * log10(ducked / dry), -12, accuracy: 0.3)
        // Слушатель раньше источника в списке дорожек — порядок микшера ставит источник первым.
        let (ducked2, _) = duck(true, listener: 2)
        XCTAssertEqual(20 * log10(ducked2 / dry), -12, accuracy: 0.3)
    }

    /// Нагрузка (отладочная сборка, доля одного ядра): 8 динамических bell (SELF), сдвиг всё время меняется.
    func testLoad() {
        let n = 256, blocks = 48000 / 256
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n), r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let p = UnsafeMutablePointer<Double>.allocate(capacity: EqSpec.stride)
        defer { l.deallocate(); r.deallocate(); p.deallocate() }
        var e = Eq()
        for k in 0..<8 {
            var b = EqBand(type: k % 3, freq: 100 * Double(k + 1), gain: 3, q: 1)
            b.dyn = 0
            b.thr = -30
            b.range = -12
            e.bands[k] = b
        }
        EqSpec.fill(p, e)
        let u = EqUnit(sampleRate: 48000)
        var rnd = FxRandom(3)
        var phase = 0
        let t0 = Date()
        for _ in 0..<blocks {
            for i in 0..<n {
                // Шум с огибающей 4 Гц: сдвиг всё время меняется.
                let env = Float(0.5 + 0.5 * sin(2 * Double.pi * 4 * Double(phase) / 48000))
                l[i] = Float(rnd.next() - 0.5) * env
                r[i] = Float(rnd.next() - 0.5) * env
                phase += 1
            }
            u.process(left: l, right: r, frames: n, params: p)
        }
        print(String(format: "load 8 dynamic bells: %.1f %%", Date().timeIntervalSince(t0) * 100))
    }
}

/// Пресеты EQ (S7d): имя, сохранение, загрузка без BYPASS, источник DYN несуществующей дорожки — OFF, JSON.
final class EqPresetTests: XCTestCase {
    func testBook() {
        var p = Project()
        p.addEqBand(0, freq: 100, gain: 3)
        p.addEqBand(0, freq: 1000, gain: -3)
        p.setEqMs(0, 1, 2)
        p.setEqDyn(0, 1, Params.maxTracks)
        p.setEqDynParams(0, 1, thr: -30, range: 9)
        var book = EqPresetBook()
        XCTAssertEqual(book.nextName(), "EQ 1")
        book.save(name: "  ", eq: p.tracks[0].eq)
        XCTAssertEqual(book.list[0].name, "EQ 1")
        XCTAssertEqual(book.list[0].count, 2)
        book.save(name: String(repeating: "x", count: 50), eq: p.masterEq)
        XCTAssertEqual(book.list[1].name.count, 40)
        XCTAssertEqual(book.list[1].count, 0)
        book.rename(1, to: "Flat")
        XCTAssertEqual(book.list[1].name, "Flat")
        XCTAssertEqual(book.nextName(), "EQ 3")
        // Загрузка в мастер: полосы как в пресете, BYPASS не меняется; дорожки 16 нет — DYN OFF.
        p.toggleEq(EqSpec.masterChannel)
        p.applyEqPreset(EqSpec.masterChannel, book.list[0])
        XCTAssertFalse(p.masterEq.on)
        XCTAssertEqual(p.masterEq.bands[0], p.tracks[0].eq.bands[0])
        XCTAssertEqual(p.masterEq.bands[1]?.ms, 2)
        XCTAssertEqual(p.masterEq.bands[1]?.thr, -30)
        XCTAssertEqual(p.masterEq.bands[1]?.dyn, -1)
        // Пустой пресет очищает полосы.
        p.applyEqPreset(EqSpec.masterChannel, book.list[1])
        XCTAssertEqual(p.masterEq.bands.compactMap { $0 }.count, 0)
        // JSON туда и обратно; повреждённый — пустой список.
        XCTAssertEqual(EqPresetBook.decode(book.encode()), book)
        XCTAssertEqual(EqPresetBook.decode(Data("{".utf8)).list.count, 0)
        book.delete(0)
        XCTAssertEqual(book.list.map { $0.name }, ["Flat"])
    }
}
