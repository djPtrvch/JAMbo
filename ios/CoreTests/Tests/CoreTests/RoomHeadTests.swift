import XCTest
@testable import Core

/// HEAD (8.11): наборы прямой части по углам поворота головы — загрузка, совпадение с импульсом комнаты при голове
/// прямо, направление поворота, плавность при быстром повороте, выключение.
final class RoomHeadTests: XCTestCase {
    static func head(_ k: Int) -> (RoomIR, RoomInfo) {
        let r: RoomInfo = RoomTests.rooms()[k]
        let d = RoomTests.audio(r.headFile)
        return (RoomIR(name: r.name, wav: d, gainDb: r.headGainDb, direct: 0)!, r)
    }

    static func conv(_ k: Int) -> RoomConv {
        let (h, r) = head(k)
        return RoomConv(ir: RoomTests.ir(k), head: h, from: r.headFrom, step: r.headStep)
    }

    private func noise(_ n: Int, _ seed: UInt64) -> [Float] {
        var x: UInt64 = seed
        return (0..<n).map { _ in
            x = x &* 6364136223846793005 &+ 1442695040888963407
            return Float(Double(x >> 33) / Double(1 << 31) - 0.5) * 0.5
        }
    }

    /// Блоками по 256; yaw(b) — угол перед блоком b (nil — HEAD выключен).
    private func run(_ st: RoomStage, _ l: [Float], _ r: [Float], yaw: (Int) -> Float?) -> (l: [Float], r: [Float]) {
        var ol: [Float] = [], or: [Float] = []
        var bl = [Double](repeating: 0, count: 256), br = [Double](repeating: 0, count: 256)
        var at = 0, b = 0
        while at + 256 <= l.count {
            if let y = yaw(b) {
                st.headOn.store(1)
                st.headYaw.store(y)
            } else {
                st.headOn.store(0)
            }
            for i in 0..<256 { bl[i] = Double(l[at + i]); br[i] = Double(r[at + i]) }
            st.process(&bl, &br, 256)
            ol += bl.map { Float($0) }
            or += br.map { Float($0) }
            at += 256
            b += 1
        }
        return (ol, or)
    }

    private func stage(_ k: Int, amb: Float = 0) -> RoomStage {
        let st = RoomStage(sampleRate: 48000)
        st.ambience.store(amb)
        st.set(RoomHeadTests.conv(k))
        return st
    }

    private func energy(_ x: [Float], from: Int) -> Double {
        var e: Double = 0
        for i in from..<x.count { e += Double(x[i]) * Double(x[i]) }
        return e
    }

    func testHeadFiles() {
        for k in 0..<RoomTests.rooms().count {
            let (h, r) = RoomHeadTests.head(k)
            XCTAssertFalse(r.headFile.isEmpty)
            XCTAssertEqual(h.frames, 51 * RoomConv.part)
            XCTAssertEqual(r.headFrom, -50)
            XCTAssertEqual(r.headStep, 2)
        }
    }

    /// Голова прямо: как без HEAD (≤ −60 dB), во всех комнатах, с хвостом.
    func testZeroYawMatchesRoom() {
        let n = 256 * 40
        let l = noise(n, 3), r = noise(n, 4)
        for k in 0..<RoomTests.rooms().count {
            let a = run(stage(k, amb: 0.5), l, r) { _ in nil }
            let b = run(stage(k, amb: 0.5), l, r) { _ in 0 }
            var err: Double = 0
            for i in 4096..<n { err += Double((a.l[i] - b.l[i]) * (a.l[i] - b.l[i]) + (a.r[i] - b.r[i]) * (a.r[i] - b.r[i])) }
            let sig: Double = energy(a.l, from: 4096) + energy(a.r, from: 4096)
            let db: Double = 10 * log10(err / sig)
            print(String(format: "HEAD yaw 0 vs off, %@: %.1f dB", RoomTests.rooms()[k].name, db))
            XCTAssertLessThan(db, -60)
        }
    }

    /// Левая колонка (Studio, без хвоста): голова прямо — левое ухо громче; повернулась к ней (−30°) — уши почти
    /// равны; отвернулась (+30°) — разница больше.
    func testTurnDirection() {
        let n = 256 * 40
        let l = noise(n, 5), z = [Float](repeating: 0, count: n)
        func ratio(_ y: Float) -> Double {
            let o = run(stage(0), l, z) { _ in y }
            return 10 * log10(energy(o.l, from: 8192) / energy(o.r, from: 8192))
        }
        let left: Double = ratio(-30), mid: Double = ratio(0), right: Double = ratio(30)
        print(String(format: "HEAD left speaker L/R: yaw −30 %.1f dB, 0 %.1f dB, +30 %.1f dB", left, mid, right))
        XCTAssertLessThan(abs(left), 2.5)
        XCTAssertGreaterThan(mid, left + 3)
        XCTAssertGreaterThan(right, mid + 3)
    }

    /// Быстрый поворот (−50 → +50° за 0,5 с, синус 1 кГц): скачков нет — наибольшая разность соседних отсчётов не
    /// больше, чем у неподвижной головы на краях и в центре, плюс 15 %.
    func testSweepIsSmooth() {
        let n = 256 * 160
        var x = [Float](repeating: 0, count: n)
        for i in 0..<n { x[i] = 0.3 * Float(sin(2 * Double.pi * 1000 * Double(i) / 48000)) }
        func maxStep(_ o: (l: [Float], r: [Float]), _ from: Int, _ to: Int) -> Float {
            var m: Float = 0
            for i in (from + 1)..<to { m = max(m, abs(o.l[i] - o.l[i - 1]), abs(o.r[i] - o.r[i - 1])) }
            return m
        }
        var still: Float = 0
        for y in [Float(-50), 0, 50] {
            still = max(still, maxStep(run(stage(0), x, x) { _ in y }, 8192, n))
        }
        let sweep = run(stage(0), x, x) { b in
            let t: Float = Float(b - 40) / 94
            return -50 + 100 * min(1, max(0, t))
        }
        let moving: Float = maxStep(sweep, 8192, n)
        print(String(format: "HEAD sweep: max step %.4f, still %.4f", moving, still))
        XCTAssertLessThan(moving, still * 1.15)
    }

    /// Выключение HEAD при повороте: угол уходит к нулю, затем спектры без HEAD — выход как без HEAD (≤ −60 dB).
    func testTurnOffReturnsToRoom() {
        let n = 256 * 60
        let l = noise(n, 7), r = noise(n, 8)
        let a = run(stage(0), l, r) { _ in nil }
        let b = run(stage(0), l, r) { blk in blk < 20 ? 40 : nil }
        var err: Double = 0
        for i in (256 * 40)..<n { err += Double((a.l[i] - b.l[i]) * (a.l[i] - b.l[i])) }
        let db: Double = 10 * log10(err / energy(a.l, from: 256 * 40))
        print(String(format: "HEAD off after turn: %.1f dB", db))
        XCTAssertLessThan(db, -60)
    }
}
