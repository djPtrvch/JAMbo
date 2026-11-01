import XCTest
@testable import Core

/// GRANULAR (26): формулы ТЗ, сверка с прототипом на его демо-сэмпле, тишина без сэмпла, смена сэмпла на лету.
final class GranularEngineTests: XCTestCase {
    /// Демо-сэмпл прототипа (makeDemo): арпеджио и пэд, 6 с, моно, пик 0,85, 44,1 кГц — и, как в Chromium (буфер
    /// 44,1 кГц в контексте 48 кГц), к 48 кГц линейной интерполяцией (она чуть заваливает верх).
    static let demo: SampleData = {
        let sr = 44100.0
        let len = Int(sr) * 6
        var d = [Float](repeating: 0, count: len)
        var r = 12345
        func noise() -> Double {
            r = (r &* 1103515245 &+ 12345) & 0x7FFF_FFFF
            return Double(r) / 1073741823.5 - 1
        }
        let notes: [Double] = [220, 261.63, 329.63, 440, 392, 329.63, 293.66, 261.63]
        let nl = Int(sr * 0.4)
        for (ni, f) in notes.enumerated() {
            let s0 = ni * nl, total = Int(Double(nl) * 1.6)
            var i = 0
            while i < total && s0 + i < len {
                let t = Double(i) / sr
                var v = 0.0
                for k in 1...8 { v += sin(2 * Double.pi * f * Double(k) * t) / Double(k) * exp(-t * (2.5 + Double(k) * 1.4)) }
                if i < 400 { v += noise() * 0.4 * (1 - Double(i) / 400) }
                d[s0 + i] += Float(v * 0.5)
                i += 1
            }
        }
        let p0 = Int(sr * 3.4), plen = len - p0
        let chord: [Double] = [110, 164.81, 220, 329.63]
        for i in 0..<plen {
            let t = Double(i) / sr, x = Double(i) / Double(plen)
            let env = pow(sin(Double.pi * x), 1.5), vib = 1 + 0.004 * sin(2 * Double.pi * 5 * t)
            var v = 0.0
            for c in chord { for k in 1...5 { v += sin(2 * Double.pi * c * vib * Double(k) * t) / Double(k * k) } }
            d[p0 + i] += Float(v * 0.12 * env + noise() * 0.03 * env)
        }
        let pk = d.map { abs($0) }.max() ?? 1
        let g = Float(0.85) / pk
        let n48 = Int(Double(len) * 48000 / sr)
        var o = [Float](repeating: 0, count: n48)
        for i in 0..<n48 {
            let x = Double(i) * sr / 48000
            let k = Int(x), f = Float(x - Double(k))
            let a = d[k], b = k + 1 < len ? d[k + 1] : 0
            o[i] = (a + (b - a) * f) * g
        }
        return SampleData(left: o, right: nil)
    }()

    static func src(_ s: SampleData?) -> GrainSrc {
        guard let s = s else { return GrainSrc() }
        return GrainSrc(left: s.left, right: s.channels > 1 ? s.right : nil, frames: s.frames, channels: s.channels)
    }

    static func render(_ k: [Double], note: Double = 48, frames: Int = 96000, window: Int = Int.max, seed: Int = 1,
                       sample: SampleData? = GranularEngineTests.demo,
                       change: ((Int, GranularVoice) -> GrainSrc?)? = nil) -> ([Float], [Float]) {
        let v = GranularVoice(sampleRate: 48000, seed: seed)
        v.silence()
        v.trigger(note: note, k[0], k[1], k[2], k[3])
        var l = [Float](repeating: 0, count: frames), r = [Float](repeating: 0, count: frames)
        var s = src(sample)
        l.withUnsafeMutableBufferPointer { bl in
            r.withUnsafeMutableBufferPointer { br in
                var pos = 0
                while pos < frames {
                    let n = min(24, frames - pos)
                    if let c = change?(pos, v) { s = c }
                    let w: Int = window == Int.max ? Int.max : window - pos
                    v.render(bl.baseAddress! + pos, br.baseAddress! + pos, n, window: w, src: s)
                    pos += n
                }
            }
        }
        return (l, r)
    }

    func testMaps() {
        XCTAssertEqual(TexGran.grainSize(0), 0.005, accuracy: 1e-12)
        XCTAssertEqual(TexGran.grainSize(1), 0.5, accuracy: 1e-12)
        XCTAssertEqual(TexGran.grainSize(0.45) * 1000, 39.7, accuracy: 0.1)
        XCTAssertEqual(TexGran.grainRate(0), 2, accuracy: 1e-12)
        XCTAssertEqual(TexGran.grainRate(1), 80, accuracy: 1e-9)
        XCTAssertEqual(TexGran.grainRate(0.55).rounded(), 15)
    }

    /// Без сэмпла — тишина, без NaN; зёрен нет.
    func testNoSampleSilent() {
        let (l, r) = GranularEngineTests.render([0.12, 0.45, 0.55, 0.2], sample: nil)
        XCTAssertEqual(l.map { abs($0) }.max(), 0)
        XCTAssertEqual(r.map { abs($0) }.max(), 0)
    }

    /// Сверка с прототипом (proto.json, 4 прогона по 10 с, исходная высота, Hold): RMS и полосы ±3 dB.
    func testMatchesPrototype() throws {
        let refs = ProtoCompare.load()
        try XCTSkipIf(refs.isEmpty, "нет proto.json")
        let names = refs.keys.filter { $0.hasPrefix("gran_") }.sorted()
        XCTAssertEqual(names.count, 6)
        let g = 20 * log10(TextureMap.out)
        for name in names {
            let ref = refs[name]!
            let s = ProtoCompare.average(4) { run in
                let (l, r) = GranularEngineTests.render(ref.k, frames: 480000, seed: 21 + run)
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

    /// Окно активности: новые зёрна не рождаются, звучащие доигрывают — потом тишина.
    func testWindow() {
        let (l, _) = GranularEngineTests.render([0.12, 0.45, 0.55, 0.2], frames: 72000, window: 4800)
        XCTAssertLessThan(l[48000...].map { abs($0) }.max() ?? 1, 1e-6)
        XCTAssertGreaterThan(l[..<9600].map { abs($0) }.max() ?? 0, 0.01)
    }

    /// Смена сэмпла посреди игры и резкие ручки: без NaN, без скачков больше, чем в обычном облаке.
    func testSwapAndKnobs() {
        let other = SampleData(left: (0..<96000).map { Float(sin(Double($0) * 0.05) * 0.8) },
                               right: (0..<96000).map { Float(cos(Double($0) * 0.031) * 0.8) })
        let a: [Double] = [0.2, 0.6, 0.6, 0.3], b: [Double] = [0.8, 0.2, 0.9, 0.9]
        let (l, r) = GranularEngineTests.render(a, frames: 96000) { pos, v in
            let k = (pos / 4800) % 2 == 0 ? a : b
            v.set(note: (pos / 9600) % 2 == 0 ? 48 : 55, k[0], k[1], k[2], k[3])
            if pos == 48000 { return GranularEngineTests.src(other) }
            return nil
        }
        XCTAssertFalse(l.contains { !$0.isFinite } || r.contains { !$0.isFinite })
        func maxStep(_ l: [Float], _ r: [Float]) -> Float {
            var m: Float = 0
            for i in 1..<l.count { m = max(m, abs(l[i] - l[i - 1]), abs(r[i] - r[i - 1])) }
            return m
        }
        // Порог — скачки обычного облака на тех же ручках и сэмплах (без смены), с запасом 1,5.
        var ref: Float = 0
        for k in [a, b] {
            for smp in [GranularEngineTests.demo, other] {
                let (x, y) = GranularEngineTests.render(k, note: 55, frames: 48000, sample: smp)
                ref = max(ref, maxStep(x, y))
            }
        }
        XCTAssertLessThan(maxStep(l, r), ref * 1.5)
    }

    /// Плотный край (DENSITY 1, SIZE 1): не больше 160 зёрен, уровень — не выше прочих синтов.
    func testDenseLimit() {
        let v = GranularVoice(sampleRate: 48000, seed: 5)
        v.silence()
        v.trigger(note: 48, 0.5, 1, 1, 0.5)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: 24), r = UnsafeMutablePointer<Float>.allocate(capacity: 24)
        var peak: Float = 0, most = 0
        for _ in 0..<(48000 * 3 / 24) {
            v.render(l, r, 24, window: Int.max, src: GranularEngineTests.src(GranularEngineTests.demo))
            most = max(most, v.grains)
            for i in 0..<24 { peak = max(peak, abs(l[i]), abs(r[i])) }
        }
        XCTAssertLessThanOrEqual(most, 160)
        XCTAssertLessThan(peak, 1)
        l.deallocate()
        r.deallocate()
    }
}
