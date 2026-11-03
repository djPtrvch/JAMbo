import XCTest
@testable import Core

/// Арпеджиатор: ряд нот, направления, октавы, сетка, GATE, LATCH, запись.
final class ArpTests: XCTestCase {
    func testSequence() {
        XCTAssertEqual(Arp.sequence([64, 60, 67], dir: Arp.up, octaves: 1), [60, 64, 67])
        XCTAssertEqual(Arp.sequence([64, 60, 67], dir: Arp.down, octaves: 1), [67, 64, 60])
        XCTAssertEqual(Arp.sequence([64, 60, 67], dir: Arp.upDown, octaves: 1), [60, 64, 67, 64])
        XCTAssertEqual(Arp.sequence([64, 60, 67], dir: Arp.downUp, octaves: 1), [67, 64, 60, 64])
        XCTAssertEqual(Arp.sequence([64, 60, 67], dir: Arp.order, octaves: 1), [64, 60, 67])
        XCTAssertEqual(Arp.sequence([60, 64], dir: Arp.up, octaves: 2), [60, 64, 72, 76])
        XCTAssertEqual(Arp.sequence([60, 60], dir: Arp.up, octaves: 1), [60], "повтор убран")
        XCTAssertEqual(Arp.sequence([120], dir: Arp.up, octaves: 3), [120], "выше 127 не берётся")
    }

    /// Ноты блоков подряд (стоп транспорта): (кадр, нота) включений и кадры отпусканий.
    private func run(_ a: Arpeggiator, blocks: Int, frames: Int = 256, playing: Bool = false,
                     stepFrames: Double = 6000) -> (on: [(Int64, Int32)], off: [Int64]) {
        var on: [(Int64, Int32)] = []
        var off: [Int64] = []
        for b in 0..<blocks {
            let s: Int64 = Int64(b * frames)
            a.process(start: s, frames: frames, playing: playing, nextTick: 0, nextFrame: 0, stepFrames: stepFrames)
            for i in 0..<a.emitCount {
                if a.emitKind[i] == 1 { on.append((a.emitFrame[i], a.emitNote[i])) } else { off.append(a.emitFrame[i]) }
            }
            a.clearEmit()
        }
        return (on, off)
    }

    func testFreeRunUpWithGate() {
        let a = Arpeggiator()
        a.configure(track: 0, on: true, dir: Arp.up, rate: 2, octaves: 1, gate: 0.5, latch: false, at: 0)
        a.press(track: 0, note: 64, id: 1, velocity: 1, at: 0)
        a.press(track: 0, note: 60, id: 2, velocity: 1, at: 0)
        let r = run(a, blocks: 100)  // 25600 кадров, шаг 1/16 — 6000 кадров
        XCTAssertEqual(r.on.map { $0.0 }, [0, 6000, 12000, 18000, 24000])
        XCTAssertEqual(r.on.map { $0.1 }, [60, 64, 60, 64, 60])
        XCTAssertEqual(Array(r.off.prefix(2)), [3000, 9000], "GATE 50 %")
    }

    func testReleaseStopsAndLatchKeeps() {
        let a = Arpeggiator()
        a.configure(track: 0, on: true, dir: Arp.up, rate: 2, octaves: 1, gate: 1, latch: false, at: 0)
        a.press(track: 0, note: 60, id: 1, velocity: 1, at: 0)
        _ = run(a, blocks: 4)
        a.release(track: 0, id: 1, at: 1024)
        XCTAssertEqual(a.emitCount, 1, "звучащая нота гаснет")
        a.clearEmit()
        XCTAssertTrue(run(a, blocks: 100).on.isEmpty)
        // LATCH: отпустили — играет; новое нажатие после отпускания всех — новый набор.
        let b = Arpeggiator()
        b.configure(track: 2, on: true, dir: Arp.up, rate: 2, octaves: 1, gate: 0.5, latch: true, at: 0)
        b.press(track: 2, note: 60, id: 1, velocity: 1, at: 0)
        b.release(track: 2, id: 1, at: 10)
        XCTAssertEqual(run(b, blocks: 50).on.count, 3)
        b.press(track: 2, note: 70, id: 5, velocity: 1, at: 12800)
        let r = run(b, blocks: 50)
        XCTAssertTrue(r.on.allSatisfy { $0.1 == 70 }, "набор заменён")
        b.configure(track: 2, on: true, dir: Arp.up, rate: 2, octaves: 1, gate: 0.5, latch: false, at: 0)
        XCTAssertEqual(b.emitCount, 0, "палец держит — играет")
        b.release(track: 2, id: 5, at: 0)
        b.clearEmit()
        XCTAssertTrue(run(b, blocks: 50).on.isEmpty)
    }

    func testGridWhenPlaying() {
        let a = Arpeggiator()
        a.configure(track: 1, on: true, dir: Arp.up, rate: 0, octaves: 1, gate: 0.5, latch: false, at: 0)
        // Нажатие в кадре 1000: первая нота сразу, следующая — на сетке 1/8 (каждые 12000 кадров от 0).
        a.press(track: 1, note: 60, id: 1, velocity: 0.5, at: 1000)
        var on: [Int64] = []
        for b in 0..<120 {
            let s: Int64 = Int64(b * 256)
            a.process(start: s, frames: 256, playing: true, nextTick: 0, nextFrame: 0, stepFrames: 6000)
            for i in 0..<a.emitCount where a.emitKind[i] == 1 { on.append(a.emitFrame[i]) }
            a.clearEmit()
        }
        XCTAssertEqual(on, [1000, 12000, 24000])
        var outs: [ArpOut] = []
        while let o = a.out.pop() { outs.append(o) }
        XCTAssertEqual(outs.count, 3)
        XCTAssertEqual(outs[0].velocity, 0.5)
        XCTAssertEqual(outs[1].gateFrames, 6000)
    }

    func testDirectionsInEngine() {
        let a = Arpeggiator()
        a.configure(track: 0, on: true, dir: Arp.upDown, rate: 4, octaves: 2, gate: 0.5, latch: false, at: 0)
        a.press(track: 0, note: 60, id: 1, velocity: 1, at: 0)
        a.press(track: 0, note: 64, id: 2, velocity: 1, at: 0)
        let r = run(a, blocks: 100)  // 1/32 — 3000 кадров
        XCTAssertEqual(Array(r.on.map { $0.1 }.prefix(8)), [60, 64, 72, 76, 72, 64, 60, 64])
        let b = Arpeggiator()
        b.configure(track: 0, on: true, dir: Arp.random, rate: 4, octaves: 1, gate: 0.5, latch: false, at: 0)
        b.press(track: 0, note: 60, id: 1, velocity: 1, at: 0)
        b.press(track: 0, note: 62, id: 2, velocity: 1, at: 0)
        b.press(track: 0, note: 64, id: 3, velocity: 1, at: 0)
        let notes = Set(run(b, blocks: 200).on.map { $0.1 })
        XCTAssertEqual(notes, [60, 62, 64])
    }

    func testTrackArpCoding() throws {
        var t = Track(index: 0)
        t.arp.mode = true
        t.arp.on = true
        t.arp.dir = 3
        t.arp.rate = 4
        t.arp.octaves = 3
        t.arp.gate = 0.8
        t.arp.latch = true
        let back = try JSONDecoder().decode(Track.self, from: try JSONEncoder().encode(t))
        XCTAssertEqual(back.arp, t.arp)
        var obj = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(Track(index: 0))) as! [String: Any]
        obj["arp"] = nil
        let old = try JSONDecoder().decode(Track.self, from: try JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(old.arp, TrackArp(), "старый проект — CHORD и значения по умолчанию")
        XCTAssertEqual(TrackArp().rate, 2)
        XCTAssertEqual(Arp.rates[TrackArp().rate], "1/16")
    }
}
