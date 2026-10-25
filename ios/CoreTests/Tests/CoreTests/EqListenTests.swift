import XCTest
@testable import Core

/// Прослушивание полосы EQ (SHIFT + точка): фильтр после EQ канала, плавное включение и выключение.
final class EqListenTests: XCTestCase {
    /// RMS синуса hz (dBFS) на выходе после блоков с прослушиванием полосы b канала 0 (on — включено).
    private func level(_ hz: Double, _ b: EqBand, on: Bool, blocks: Int = 40) -> (l: Double, r: Double) {
        let n = 256
        let u = EqUnit(sampleRate: 48000)
        let x = EqListen(sampleRate: 48000)
        let p = UnsafeMutablePointer<Double>.allocate(capacity: EqSpec.stride)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n), r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { p.deallocate(); l.deallocate(); r.deallocate() }
        EqSpec.fill(p, Eq())
        let f = EqListen.filter(b)
        x.kind.store(f.kind)
        x.q.store(Float(f.q))
        x.freq.store(Float(b.freq))
        x.ms.store(b.ms)
        x.channel.store(on ? 0 : -1)
        var sl: Double = 0, sr: Double = 0
        var k = 0
        for blk in 0..<blocks {
            for i in 0..<n {
                let ph: Double = 2 * Double.pi * hz * Double(k) / 48000
                l[i] = Float(0.5 * sin(ph))
                r[i] = Float(0.25 * sin(ph))
                k += 1
            }
            u.process(left: l, right: r, frames: n, params: p)
            x.process(0, u, n)
            if blk >= blocks / 2 {
                for i in 0..<n {
                    sl += Double(l[i] * l[i])
                    sr += Double(r[i] * r[i])
                }
            }
        }
        let cnt = Double(n * (blocks - blocks / 2))
        return (10 * log10(sl / cnt + 1e-30), 10 * log10(sr / cnt + 1e-30))
    }

    func testBell() {
        let b = EqBand(type: EqSpec.bell, freq: 1000, gain: 6, q: 2)
        let dry = level(1000, b, on: false)
        let at = level(1000, b, on: true)
        let away = level(100, b, on: true)
        XCTAssertEqual(at.l, dry.l, accuracy: 0.2)
        XCTAssertLessThan(away.l, dry.l - 25)
    }

    func testCuts() {
        let low = EqBand(type: EqSpec.lowCut, freq: 500, gain: 0, q: 0.71)
        XCTAssertLessThan(level(5000, low, on: true).l, level(5000, low, on: false).l - 30)
        XCTAssertEqual(level(50, low, on: true).l, level(50, low, on: false).l, accuracy: 0.3)
        let high = EqBand(type: EqSpec.highShelf, freq: 5000, gain: 3, q: 0.71)
        XCTAssertLessThan(level(300, high, on: true).l, level(300, high, on: false).l - 30)
    }

    /// SIDE: бока (L−R)/2 на оба канала с обратным знаком справа.
    func testSide() {
        var b = EqBand(type: EqSpec.bell, freq: 1000, gain: 0, q: 1)
        b.ms = 2
        let s = level(1000, b, on: true)
        // L = 0,5, R = 0,25 → S = 0,125: RMS синуса 0,125 ≈ −21,1 dBFS.
        XCTAssertEqual(s.l, -21.07, accuracy: 0.3)
        XCTAssertEqual(s.r, -21.07, accuracy: 0.3)
    }

    /// Выключено — сигнал без изменений; после выключения канал отпускается.
    func testOffAndRelease() {
        let b = EqBand(type: EqSpec.bell, freq: 1000, gain: 0, q: 1)
        XCTAssertEqual(level(100, b, on: false).l, -9.03, accuracy: 0.1)
        let u = EqUnit(sampleRate: 48000)
        let x = EqListen(sampleRate: 48000)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: 256), r = UnsafeMutablePointer<Float>.allocate(capacity: 256)
        defer { l.deallocate(); r.deallocate() }
        l.initialize(repeating: 0.1, count: 256)
        r.initialize(repeating: 0.1, count: 256)
        u.laneL[0] = l
        u.laneR[0] = r
        x.channel.store(3)
        x.process(3, u, 256)
        XCTAssertEqual(x.active, 3)
        x.process(5, u, 256)
        XCTAssertEqual(x.active, 3)
        x.channel.store(5)
        x.process(3, u, 256)
        x.process(3, u, 256)
        XCTAssertEqual(x.active, -1)
        x.process(5, u, 256)
        XCTAssertEqual(x.active, 5)
    }
}

extension EqListenTests {
    /// Полоса подсветки: ширина bell — f/Q, края по −3 dB (среднее геометрическое — частота); cut — до края.
    func testSpan() {
        let b = EqBand(type: EqSpec.bell, freq: 1000, gain: 0, q: 2)
        let s = EqListen.span(b)
        XCTAssertEqual(s.hi - s.lo, 500, accuracy: 1e-9)
        XCTAssertEqual((s.lo * s.hi).squareRoot(), 1000, accuracy: 1e-9)
        let low = EqListen.span(EqBand(type: EqSpec.lowCut, freq: 200, gain: 0, q: 0.71))
        XCTAssertEqual(low.lo, 0)
        XCTAssertEqual(low.hi, 200)
        XCTAssertTrue(EqListen.span(EqBand(type: EqSpec.highShelf, freq: 5000, gain: 0, q: 0.71)).hi.isInfinite)
    }
}
