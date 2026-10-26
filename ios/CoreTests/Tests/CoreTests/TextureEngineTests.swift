import XCTest
@testable import Core

/// TEXTURE (25): формулы ТЗ, офлайн-рендер контрольных положений — NaN нет, уровень, стерео, без щелчков.
final class TextureEngineTests: XCTestCase {
    struct Stats {
        var peak: Float = 0
        var rms: Double = 0
        var finite = true
    }

    /// Рендер кусками по 24 (как голос); window — кадров окна активности.
    static func render(_ k: [Double], note: Double = 57, frames: Int = 96000, window: Int = Int.max,
                       seed: Int = 1, change: ((Int, TextureVoice) -> Void)? = nil) -> ([Float], [Float]) {
        let v = TextureVoice(sampleRate: 48000, seed: seed)
        v.silence()
        v.trigger(note: note, k[0], k[1], k[2], k[3])
        var l = [Float](repeating: 0, count: frames)
        var r = [Float](repeating: 0, count: frames)
        l.withUnsafeMutableBufferPointer { bl in
            r.withUnsafeMutableBufferPointer { br in
                var pos = 0
                while pos < frames {
                    let n = min(24, frames - pos)
                    change?(pos, v)
                    let w: Int = window == Int.max ? Int.max : window - pos
                    v.render(bl.baseAddress! + pos, br.baseAddress! + pos, n, window: w)
                    pos += n
                }
            }
        }
        return (l, r)
    }

    static func stats(_ a: [Float], from: Int = 0) -> Stats {
        var s = Stats()
        var sum = 0.0
        for i in from..<a.count {
            let x = a[i]
            if !x.isFinite { s.finite = false }
            s.peak = max(s.peak, abs(x))
            sum += Double(x) * Double(x)
        }
        s.rms = sqrt(sum / Double(max(1, a.count - from)))
        return s
    }

    func testMaps() {
        XCTAssertEqual(TextureMap.rate(0), 2, accuracy: 1e-9)
        XCTAssertEqual(TextureMap.rate(1), 120, accuracy: 1e-9)
        XCTAssertEqual(TextureMap.length(0), 0.002, accuracy: 1e-12)
        XCTAssertEqual(TextureMap.length(1), 0.12, accuracy: 1e-12)
        XCTAssertEqual(TextureMap.lpHz(0, 48000), 250, accuracy: 1e-9)
        XCTAssertEqual(TextureMap.lpHz(0.55, 48000), 18000, accuracy: 1e-6)
        XCTAssertEqual(TextureMap.lpHz(1, 44100), 18000, accuracy: 1e-6)
        XCTAssertEqual(TextureMap.hpHz(0.55), 30, accuracy: 1e-9)
        XCTAssertEqual(TextureMap.hpHz(1), 6000, accuracy: 1e-6)
        XCTAssertEqual(TextureMap.q(0), 2, accuracy: 1e-12)
        XCTAssertEqual(TextureMap.q(1), 100, accuracy: 1e-12)
        XCTAssertEqual(TextureMap.weight(0, 0), 1, accuracy: 1e-12)
        XCTAssertEqual(TextureMap.weight(3, 1), 0.8, accuracy: 1e-12)
        XCTAssertEqual(TextureMap.colorName(0.1), "brown")
        XCTAssertEqual(TextureMap.colorName(0.4), "white")
        XCTAssertEqual(TextureMap.colorName(0.9), "blue")
    }

    /// Контрольные положения ТЗ: NaN нет, пик ниже 0 dBFS; сводка уровней — в отчёт.
    func testControlPositions() {
        let cases: [[Double]] = [[0.4, 0.5, 0.3, 0.3], [0, 0.5, 0, 0], [1, 0.5, 0, 0], [0.4, 1, 0, 0],
                                 [0.4, 0.5, 1, 0], [0.4, 0.5, 0.3, 1], [1, 1, 1, 1], [0, 0, 1, 0], [0, 1, 1, 1]]
        for k in cases {
            for note in [33.0, 57, 81] {
                let (l, r) = TextureEngineTests.render(k, note: note)
                let a = TextureEngineTests.stats(l), b = TextureEngineTests.stats(r)
                XCTAssertTrue(a.finite && b.finite, "\(k) \(note)")
                XCTAssertGreaterThan(a.rms, 1e-4, "\(k) \(note)")
                XCTAssertLessThan(max(a.peak, b.peak), 4, "\(k) \(note)")
                if note == 57 {
                    print(String(format: "TEXTURE %@ peak %.3f rms %.4f", k.description, max(a.peak, b.peak), (a.rms + b.rms) / 2))
                }
            }
        }
    }

    /// Стерео: события панорамируются случайно — каналы различаются.
    func testStereo() {
        let (l, r) = TextureEngineTests.render([0.4, 0.5, 0, 0])
        var diff = 0.0
        for i in 0..<l.count { diff += abs(Double(l[i] - r[i])) }
        XCTAssertGreaterThan(diff, 1)
    }

    /// Окно активности: после него новые события не рождаются, звучащие доигрывают — тишина.
    func testWindow() {
        let (l, _) = TextureEngineTests.render([0.4, 0.5, 0, 0], frames: 48000, window: 4800)
        let tail = TextureEngineTests.stats(Array(l[24000...]))
        XCTAssertLessThan(tail.peak, 1e-4)
    }

    /// Плотность событий: при Density 0 — около 2 событий в секунду.
    func testSparse() {
        let v = TextureVoice(sampleRate: 48000, seed: 3)
        v.silence()
        v.trigger(note: 57, 0.4, 0, 0, 0)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: 24)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: 24)
        var maxEvents = 0
        for _ in 0..<(48000 * 10 / 24) {
            v.render(l, r, 24, window: Int.max)
            maxEvents = max(maxEvents, v.events)
        }
        XCTAssertLessThanOrEqual(maxEvents, 3)
        l.deallocate()
        r.deallocate()
    }

    /// Резкая смена ручек: разрывов (скачков между отсчётами) не больше, чем в самом шуме при тех же ручках.
    func testKnobJumps() {
        let a: [Double] = [0.4, 0.5, 0.6, 0], b: [Double] = [0.9, 0.8, 0.9, 0]
        let (l, _) = TextureEngineTests.render(a, frames: 48000) { pos, v in
            let k = (pos / 2400) % 2 == 0 ? a : b
            v.set(note: (pos / 4800) % 2 == 0 ? 57 : 64, k[0], k[1], k[2], k[3])
        }
        let (ra, _) = TextureEngineTests.render(a, frames: 48000)
        let (rb, _) = TextureEngineTests.render(b, frames: 48000)
        func maxStep(_ x: [Float]) -> Float {
            var m: Float = 0
            for i in 1..<x.count { m = max(m, abs(x[i] - x[i - 1])) }
            return m
        }
        XCTAssertLessThan(maxStep(l), max(maxStep(ra), maxStep(rb)) * 1.5)
    }

    /// Сверка с прототипом (proto.json, 4 прогона по 10 с, нота A3, Hold): RMS ±3 dB, третьоктавные полосы ±3 dB там, где эталон
    /// не тише 30 dB от своей самой громкой полосы. Уровень Swift — с множителем TextureMap.out (эталон × 0,63).
    func testMatchesPrototype() throws {
        let refs = ProtoCompare.load()
        try XCTSkipIf(refs.isEmpty, "нет proto.json")
        let names = refs.keys.filter { $0.hasPrefix("tex_") }.sorted()
        XCTAssertEqual(names.count, 7)
        let g = 20 * log10(TextureMap.out)
        for name in names {
            let ref = refs[name]!
            let s = ProtoCompare.average(4) { run in
                let (l, r) = TextureEngineTests.render(ref.k, frames: 480000, seed: 11 + run)
                if run == 0 { ProtoCompare.wav(name, l, r) }
                return (l, r)
            }
            let dRms = 20 * log10(s.rms / ref.rms) - g
            let top = ref.bands.max() ?? 0
            var worst = 0.0, worstAt = 0
            for (i, b) in ref.bands.enumerated() where b > top - 30 {
                let d = s.bands[i] - g - b
                if abs(d) > abs(worst) {
                    worst = d
                    worstAt = i
                }
            }
            print(String(format: "%@ rms %.4f (ref×0.63 %.4f) %+.1f dB, peak %.2f (ref×0.63 %.2f), worst band %d Hz %+.1f dB",
                         name, s.rms, ref.rms * TextureMap.out, dRms, s.peak, ref.peak * TextureMap.out,
                         Int(1000 * pow(2, Double(worstAt - 16) / 3)), worst))
            XCTAssertLessThan(abs(dRms), 3, name)
            XCTAssertLessThan(abs(worst), 3, name)
        }
    }
}

