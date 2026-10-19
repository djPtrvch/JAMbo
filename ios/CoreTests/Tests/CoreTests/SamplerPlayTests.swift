import XCTest
@testable import Core

/// S12, этап 2: PLAY сэмплера (1.4) — ONE, LOOP, REV, PING.
final class SamplerPlayTests: XCTestCase {
    private let center: Float = Float(cos(Double.pi / 4))

    private func render(_ core: AudioCore, frames: Int) -> [Float] {
        var l = [Float](repeating: 0, count: frames)
        var bl = [Float](repeating: 0, count: 256)
        var br = [Float](repeating: 0, count: 256)
        var pos = 0
        while pos < frames {
            let n = min(256, frames - pos)
            core.render(frames: n, left: &bl, right: &br)
            for i in 0..<n { l[pos + i] = bl[i] }
            pos += n
        }
        return l
    }

    /// Живая нота C3 (исходная высота) на дорожке 1 с сэмплом x и режимом PLAY mode.
    private func play(_ x: [Float], mode: Double, frames: Int, params: [String: Double] = [:]) -> [Float] {
        let core = AudioCore(master: false)
        var p = Project()
        p.tracks[0].addSamples(["k"])
        p.tracks[0].vol = 0
        p.tracks[0].params["play"] = mode
        p.tracks[0].params["decay"] = 4000
        for (k, v) in params { p.tracks[0].params[k] = v }
        core.publish(p, samples: ["k": SampleData(left: x, right: nil)])
        core.events.push(.noteOn(track: 0, note: Params.sampleRoot, id: 1, velocity: 1))
        return render(core, frames: frames)
    }

    func testPlayKnob() {
        let p = Params.byId["play"]!
        XCTAssertEqual(p.options, ["ONE", "LOOP", "REV", "PING"])
        XCTAssertEqual(p.def, 0, "по умолчанию ONE (старые проекты — как раньше)")
        XCTAssertEqual(Params.trackGrid[12].id, "play")
    }

    /// REV: от End к Start — бит в бит как ONE перевёрнутого буфера (тот же путь: атака, край, фильтр, панорама).
    func testReverseIsReversedBuffer() {
        let n = 4800
        let x: [Float] = (0..<n).map { Float(sin(Double($0) * 0.013) * 0.9) }
        let y = play(x, mode: 2, frames: n + 960)
        let ref = play(Array(x.reversed()), mode: 0, frames: n + 960)
        // Звучащая часть — бит в бит; после Start — только хвост фильтра (~1e-16).
        let bad = (0..<n).filter { y[$0] != ref[$0] }
        XCTAssertTrue(bad.isEmpty, "первые расхождения: \(bad.prefix(5).map { ($0, y[$0], ref[$0]) }), всего \(bad.count)")
        XCTAssertGreaterThan(y[2000..<2400].map(abs).max() ?? 0, 0.3)
        XCTAssertLessThan(y[n + 100..<n + 960].map(abs).max() ?? 1, 1e-6, "Start — конец звука")
    }

    /// LOOP: кусок по кругу, пока держится нота; стык без щелчка (кроссфейд 4 мс); пик ≤ 0 dBFS.
    func testLoopSeamWithoutClick() {
        // 1000 кадров синуса с нецелым числом периодов: без кроссфейда на стыке — скачок.
        let x: [Float] = (0..<1000).map { Float(sin(Double($0) * 2 * Double.pi * 3.37 / 1000)) }
        let y = play(x, mode: 1, frames: 24000)
        XCTAssertGreaterThan(y[20000..<24000].map(abs).max() ?? 0, 0.3, "звучит дольше куска")
        var steady: Float = 0
        for i in 101..<800 { steady = max(steady, abs(y[i] - y[i - 1])) }
        var worst: Float = 0
        for i in 1000..<24000 { worst = max(worst, abs(y[i] - y[i - 1])) }
        XCTAssertLessThanOrEqual(worst, steady * 1.6, "стык петли без щелчка")
        XCTAssertLessThanOrEqual(y.map(abs).max() ?? 2, 1)
    }

    /// PING: Start → End → Start по кругу, крайние отсчёты не повторяются: бит в бит как ONE развёрнутого буфера
    /// (0…999, 998…1, 0…) до его края.
    func testPingPong() {
        let x: [Float] = (0..<1000).map { Float($0) / 1000 }
        var unfolded: [Float] = []
        for k in 0..<4 { unfolded += k % 2 == 0 ? (k == 0 ? Array(x) : Array(x[1...])) : Array(x[..<999].reversed()) }
        let y = play(x, mode: 3, frames: 3500)
        let ref = play(unfolded, mode: 0, frames: 3500)
        XCTAssertEqual(Array(y[0..<3500]), Array(ref[0..<3500]))
        XCTAssertGreaterThan(y[999], y[1100], "после End — назад")
    }

    /// ONE — как раньше: доигрывает кусок и молчит.
    func testOneShotStops() {
        let x = [Float](repeating: 0.5, count: 1000)
        let y = play(x, mode: 0, frames: 3000)
        XCTAssertEqual(y[500], center * 0.5, accuracy: 1e-5)
        XCTAssertLessThan(y[1100..<3000].map(abs).max() ?? 1, 1e-6)
    }

    /// Нарезка: PLAY действует на кусок выбранной ноты (от маркера до следующего).
    func testSliceReverse() {
        let n = 2000
        let x: [Float] = (0..<n).map { Float($0) / Float(n) }
        let core = AudioCore(master: false)
        var p = Project()
        p.tracks[0].addSamples(["k"])
        p.tracks[0].vol = 0
        p.tracks[0].params["play"] = 2
        p.tracks[0].params["attack"] = 0
        p.tracks[0].slices["k"] = [SliceMark(at: 0, note: 60), SliceMark(at: 0.5, note: 61)]
        core.publish(p, samples: ["k": SampleData(left: x, right: nil)])
        core.events.push(.noteOn(track: 0, note: 60, id: 1, velocity: 1))
        let y = render(core, frames: 1200)
        XCTAssertEqual(y[100], center * x[999 - 100], accuracy: 2e-3, "первый кусок — от его конца")
        XCTAssertLessThan(y[1050..<1200].map(abs).max() ?? 1, 1e-6)
    }
}
