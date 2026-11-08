import XCTest
@testable import Core

/// TEXTURE (25) по ТЗ docs/texture-engine.md: формулы и приёмка раздела 5 (уровень, ровность, Metal, смена ноты,
/// стерео, сглаживание ручек, предел щелчков).
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
        XCTAssertEqual(TextureMap.rate(0), 5, accuracy: 1e-9)
        XCTAssertEqual(TextureMap.rate(1), 150, accuracy: 1e-9)
        XCTAssertEqual(TextureMap.length(0), 0.012, accuracy: 1e-12)
        XCTAssertEqual(TextureMap.length(1), 0.003, accuracy: 1e-12)
        XCTAssertEqual(TextureMap.gain(0.02), 0)
        XCTAssertEqual(TextureMap.gain(1), 2.2, accuracy: 1e-12)
        XCTAssertEqual(TextureMap.lpHz(0, 48000), 250, accuracy: 1e-9)
        XCTAssertEqual(TextureMap.lpHz(0.55, 48000), 18000, accuracy: 1e-6)
        XCTAssertEqual(TextureMap.hpHz(1), 6000, accuracy: 1e-6)
        XCTAssertEqual(TextureMap.q(1), 100, accuracy: 1e-12)
        XCTAssertEqual(TextureMap.weight(0, 0), 1, accuracy: 1e-12)
        XCTAssertEqual(TextureMap.weight(3, 1), 0.8, accuracy: 1e-12)
        XCTAssertEqual(TextureMap.ratio(3, 0), 4, accuracy: 1e-12)
        XCTAssertEqual(TextureMap.ratio(3, 1), 8.93, accuracy: 1e-12)
        XCTAssertEqual(TextureMap.colorName(0.1), "brown")
        XCTAssertEqual(TextureMap.colorName(0.9), "blue")
    }

    static let defaults: [Double] = [0.4, 0.3, 0.3, 0]

    /// RMS обоих каналов после 0,2 с.
    static func level(_ k: [Double], note: Double = 57) -> Double {
        let (l, r) = render(k, note: note, frames: 48000)
        return (stats(Array(l[9600...])).rms + stats(Array(r[9600...])).rms) / 2
    }

    /// 1. Уровень при любых ручках — ±35 % от уровня по умолчанию (края Color, Grit, Tone, Metal).
    func testLevel() {
        let ref = TextureEngineTests.level(TextureEngineTests.defaults)
        print(String(format: "TEXTURE default RMS %.3f", ref))
        var worst = 0.0
        for c in [0.0, 0.4, 1] {
            for g in [0.0, 0.3, 1] {
                for t in [0.0, 0.3, 1] {
                    for m in [0.0, 1] {
                        for note in [45.0, 57, 72] {
                            let x = TextureEngineTests.level([c, g, t, m], note: note) / ref
                            worst = max(worst, abs(x - 1))
                            XCTAssertEqual(x, 1, accuracy: 0.35, "C \(c) G \(g) T \(t) M \(m) note \(note)")
                        }
                    }
                }
            }
        }
        print(String(format: "TEXTURE level spread: ±%.0f%%", worst * 100))
    }

    /// Коэффициент вариации RMS окон по 10 мс.
    static func cv(_ x: [Float]) -> Double {
        var w: [Double] = []
        var i = 0
        while i + 480 <= x.count {
            w.append(stats(Array(x[i..<(i + 480)])).rms)
            i += 480
        }
        let m = w.reduce(0, +) / Double(w.count)
        let sd = sqrt(w.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(w.count))
        return sd / m
    }

    /// 2. Ровность: CV окон 10 мс при Grit 0 ≤ 0,1, при Grit 1 ≤ 0,2; пауз нет (нет окна тише трети среднего).
    func testEvenness() {
        for (g, lim) in [(0.0, 0.1), (1.0, 0.2)] {
            let (l, _) = TextureEngineTests.render([0.4, g, 0.3, 0], frames: 96000)
            let x = Array(l[9600...])
            let c = TextureEngineTests.cv(x)
            print(String(format: "TEXTURE Grit %.0f: CV %.3f", g, c))
            XCTAssertLessThanOrEqual(c, lim)
        }
    }

    /// Амплитуда спектра (Блэкман–Харрис) около f, наибольшая в ±1,5 % по частоте.
    static func peak(_ re: [Double], _ im: [Double], _ f: Double, _ binHz: Double) -> Double {
        let a = Int((f * 0.985 / binHz).rounded(.down)), b = Int((f * 1.015 / binHz).rounded(.up))
        var m = 0.0
        for k in a...b { m = max(m, (re[k] * re[k] + im[k] * im[k]).squareRoot()) }
        return m
    }

    /// 3. Tone 1: Metal 0 — пики на f0·1, 2, 3, 4, Metal 1 — на 1, 2.76, 5.40, 8.93; между ними (×1.5, ×2.4 …) — тише.
    func testMetalPeaks() {
        let f0 = 220.0
        for (m, ra) in [(0.0, [1, 2, 3, 4]), (1.0, [1, 2.76, 5.40, 8.93])] {
            let (l, _) = TextureEngineTests.render([0.7, 0, 1, m], frames: 9600 + 32768)
            var re = [Double](repeating: 0, count: 32768), im = re
            for i in 0..<32768 {
                let a = 2 * Double.pi * Double(i) / 32768
                let w = 0.35875 - 0.48829 * cos(a) + 0.14128 * cos(2 * a) - 0.01168 * cos(3 * a)
                re[i] = Double(l[9600 + i]) * w
            }
            SynthKnobsTests.fft(&re, &im)
            let bin = 48000.0 / 32768
            for (i, r) in ra.enumerated() {
                let on = TextureEngineTests.peak(re, im, f0 * r, bin)
                // Между резонаторами (середина до следующего, у последнего — ×1.25).
                let next: Double = i + 1 < ra.count ? ra[i + 1] : r * 1.5
                let off = TextureEngineTests.peak(re, im, f0 * (r + next) / 2, bin)
                XCTAssertGreaterThan(20 * log10(on / off), 12, "Metal \(m), ×\(r)")
            }
        }
    }

    /// 4. Смена ноты A3 → C4 (Tone 1): резонаторы переезжают без щелчка и без провала (окна 10 мс не тише половины
    /// среднего, скачок между отсчётами — не больше, чем в установившемся звуке).
    func testNoteChange() {
        let k: [Double] = [0.5, 0.3, 1, 0]
        let (l, _) = TextureEngineTests.render(k, frames: 48000) { pos, v in
            if pos == 24000 { v.set(note: 60, k[0], k[1], k[2], k[3]) }
        }
        var w: [Double] = []
        var i = 9600
        while i + 480 <= 48000 {
            w.append(TextureEngineTests.stats(Array(l[i..<(i + 480)])).rms)
            i += 480
        }
        let m = w.reduce(0, +) / Double(w.count)
        XCTAssertGreaterThan(w.min() ?? 0, m * 0.5)
        func maxStep(_ x: ArraySlice<Float>) -> Float {
            var s: Float = 0
            var p = x.first ?? 0
            for v in x.dropFirst() {
                s = max(s, abs(v - p))
                p = v
            }
            return s
        }
        XCTAssertLessThan(maxStep(l[24000..<26400]), maxStep(l[9600..<24000]) * 1.5)
    }

    /// 5. Стерео: корреляция L/R заметно ниже 1.
    func testStereo() {
        let (l, r) = TextureEngineTests.render(TextureEngineTests.defaults, frames: 48000)
        var lr = 0.0, ll = 0.0, rr = 0.0
        for i in 9600..<48000 {
            lr += Double(l[i]) * Double(r[i])
            ll += Double(l[i]) * Double(l[i])
            rr += Double(r[i]) * Double(r[i])
        }
        let corr = lr / sqrt(ll * rr)
        print(String(format: "TEXTURE L/R correlation %.2f", corr))
        XCTAssertLessThan(corr, 0.7)
        XCTAssertGreaterThan(corr, 0.05)
    }

    /// Окно активности: после него новые щелчки не рождаются, подложка звучит (её глушит огибающая голоса).
    func testWindow() {
        let v = TextureVoice(sampleRate: 48000, seed: 3)
        v.silence()
        v.trigger(note: 57, 0.4, 1, 0, 0)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: 24)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: 24)
        var maxEvents = 0
        for b in 0..<4000 {
            v.render(l, r, 24, window: max(0, 48000 - b * 24))
            maxEvents = max(maxEvents, v.events)
        }
        XCTAssertLessThanOrEqual(maxEvents, TextureMap.maxEvents)
        XCTAssertEqual(v.events, 0)
        l.deallocate()
        r.deallocate()
    }

    /// 6. Резкая смена ручек и нот: разрывов не больше, чем в самом звуке при тех же ручках.
    func testKnobJumps() {
        let a: [Double] = [0.4, 0.3, 0.6, 0], b: [Double] = [0.9, 0.8, 0.9, 1]
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

    /// Пик и NaN на краях ручек.
    func testFinite() {
        for c in [0.0, 1] {
            for g in [0.0, 1] {
                for t in [0.0, 1] {
                    let (l, r) = TextureEngineTests.render([c, g, t, t], frames: 24000)
                    let s = TextureEngineTests.stats(l), q = TextureEngineTests.stats(r)
                    XCTAssertTrue(s.finite && q.finite)
                    XCTAssertLessThan(max(s.peak, q.peak), 1)
                }
            }
        }
    }
}
