import XCTest
@testable import Core

/// GRANULAR (26, ТЗ «Granular»): формулы, сверка с прототипом (docs/prototype/texture-granular.html, вкладка Granular),
/// ровность, Spray 0 (сетка до отсчёта, синхронизация по фазе), тишина без сэмпла, без щелчков, лимит зёрен.
final class GranularEngineTests: XCTestCase {
    /// Linear-интерполяция 44,1 → 48 кГц (как Chromium читает буфер 44,1 кГц в контексте 48 кГц).
    static func to48(_ d: [Float]) -> [Float] {
        let sr = 44100.0
        let n48 = Int(Double(d.count) * 48000 / sr)
        var o = [Float](repeating: 0, count: n48)
        for i in 0..<n48 {
            let x = Double(i) * sr / 48000
            let k = Int(x), f = Float(x - Double(k))
            let a = d[k], b = k + 1 < d.count ? d[k + 1] : 0
            o[i] = a + (b - a) * f
        }
        return o
    }

    /// Демо-сэмпл прототипа (makeDemo): арпеджио и пэд, 6 с, моно, пик 0,85; период неизвестен.
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
        return SampleData(left: to48(d.map { $0 * g }), right: nil)
    }()

    /// Пэд прототипа (makePadB): 8 с, стерео, один тон A3 (пилы 110, 220, 440 Гц с расстройкой), ФНЧ 1 → 5 кГц, пик
    /// 0,8; период Ts = 1/110 с. Фазы генераторов случайные, как в прототипе (там — новые на каждый прогон): variant —
    /// зерно случайности.
    static let pad: SampleData = makePad(0)
    static var pads: [Int: SampleData] = [:]
    static func padVariant(_ k: Int) -> SampleData {
        if let p = pads[k] { return p }
        let p = makePad(k)
        pads[k] = p
        return p
    }

    static func makePad(_ variant: Int) -> SampleData {
        let sr = 44100.0
        let len = Int(sr) * 8, n = 2048
        var tab = [Double](repeating: 0, count: n + 1)
        for k in 1...18 {
            let a = 1 / pow(Double(k), 1.15)
            for i in 0...n { tab[i] += a * sin(2 * Double.pi * Double(k) * Double(i) / Double(n)) }
        }
        let tm = tab.map { abs($0) }.max() ?? 1
        for i in 0...n { tab[i] /= tm }
        let voices: [(Double, Double)] = [(110, 0.5), (220, 1), (440, 0.4)]
        let det: [Double] = [-12, 0, 12]
        let cnt = voices.count * det.count * 2
        var r = 777 + variant * 7919
        func uni() -> Double {
            r = (r &* 1103515245 &+ 12345) & 0x7FFF_FFFF
            return Double(r) / 2147483648
        }
        var ph = (0..<cnt).map { _ in uni() * Double(n) }
        let dp = (0..<cnt).map { _ in uni() * 6.283 }
        var inc = [Double](repeating: 0, count: cnt)
        var out = [[Float](repeating: 0, count: len), [Float](repeating: 0, count: len)]
        var y: [[Double]] = [[0, 0], [0, 0]]
        var s0 = 0
        while s0 < len {
            let t = Double(s0) / sr, fc = 1000 * pow(5, t / 8)
            for v in 0..<voices.count { for d in 0..<det.count { for ch in 0..<2 {
                let idx = (v * det.count + d) * 2 + ch
                let cents = det[d] * (ch == 1 ? -1 : 1) + 6 * sin(6.283 * 0.09 * t + dp[idx])
                inc[idx] = voices[v].0 * pow(2, cents / 1200) * Double(n) / sr
            } } }
            let a = 1 - exp(-6.283 * fc / sr)
            var q = 0
            while q < 128 && s0 + q < len {
                var l = 0.0, rr = 0.0
                for v in 0..<voices.count { for d in 0..<det.count { for ch in 0..<2 {
                    let idx = (v * det.count + d) * 2 + ch
                    var p = ph[idx] + inc[idx]
                    if p >= Double(n) { p -= Double(n) }
                    ph[idx] = p
                    let i0 = Int(p)
                    let val = (tab[i0] + (tab[i0 + 1] - tab[i0]) * (p - Double(i0))) * voices[v].1
                    if ch == 1 { rr += val } else { l += val }
                } } }
                y[0][0] += a * (l - y[0][0]); y[0][1] += a * (y[0][0] - y[0][1]); out[0][s0 + q] = Float(y[0][1])
                y[1][0] += a * (rr - y[1][0]); y[1][1] += a * (y[1][0] - y[1][1]); out[1][s0 + q] = Float(y[1][1])
                q += 1
            }
            s0 += 128
        }
        let pk = max(out[0].map { abs($0) }.max() ?? 1, out[1].map { abs($0) }.max() ?? 1)
        let g = Float(0.8) / pk
        let s = SampleData(left: to48(out[0].map { $0 * g }), right: to48(out[1].map { $0 * g }))
        s.period = 1.0 / 110
        return s
    }

    static func src(_ s: SampleData?) -> GrainSrc {
        guard let s = s else { return GrainSrc() }
        return GrainSrc(left: s.left, right: s.channels > 1 ? s.right : nil, frames: s.frames, channels: s.channels,
                        period: s.period)
    }

    /// Облако одной дорожки: голоса на ноты (как в JamboBank — общий GrainTrack, дрейф и счёт нот в начале куска).
    final class Cloud {
        let track = UnsafeMutablePointer<GrainTrack>.allocate(capacity: 1)
        var voices: [GranularVoice] = []

        init(notes: [Double], k: [Double], seed: Int) {
            track.initialize(to: GrainTrack(rnd: (seed &* 40503 + 11) & 0xFFFF_FFFF | 1))
            for (i, n) in notes.enumerated() {
                let v = GranularVoice(sampleRate: 48000, seed: seed * 16 + i, track: track)
                v.silence()
                v.trigger(note: n, k[0], k[1], k[2], k[3])
                voices.append(v)
            }
        }

        deinit { track.deallocate() }

        func render(frames: Int, window: Int = Int.max, sample: SampleData?,
                    change: ((Int, Cloud) -> GrainSrc?)? = nil) -> ([Float], [Float]) {
            var l = [Float](repeating: 0, count: frames), r = [Float](repeating: 0, count: frames)
            var s = GranularEngineTests.src(sample)
            let bl = UnsafeMutablePointer<Float>.allocate(capacity: 24), br = UnsafeMutablePointer<Float>.allocate(capacity: 24)
            defer {
                bl.deallocate()
                br.deallocate()
            }
            var pos = 0
            while pos < frames {
                let n = min(24, frames - pos)
                if let c = change?(pos, self) { s = c }
                track.pointee.notes = voices.filter { $0.spawning }.count
                track.pointee.advance(Double(n) / 48000)
                let w: Int = window == Int.max ? Int.max : window - pos
                for v in voices {
                    v.render(bl, br, n, window: w, src: s)
                    for i in 0..<n {
                        l[pos + i] += bl[i]
                        r[pos + i] += br[i]
                    }
                }
                pos += n
            }
            return (l, r)
        }
    }

    static func render(_ k: [Double], notes: [Double] = [48], frames: Int = 96000, window: Int = Int.max, seed: Int = 1,
                       sample: SampleData? = GranularEngineTests.pad,
                       change: ((Int, Cloud) -> GrainSrc?)? = nil) -> ([Float], [Float]) {
        return Cloud(notes: notes, k: k, seed: seed).render(frames: frames, window: window, sample: sample, change: change)
    }

    // MARK: — формулы

    func testMaps() {
        XCTAssertEqual(TexGran.grainSize(0), 0.01, accuracy: 1e-12)
        XCTAssertEqual(TexGran.grainSize(1), 0.8, accuracy: 1e-12)
        XCTAssertEqual(TexGran.grainSize(0.62) * 1000, 151.5, accuracy: 0.5)
        XCTAssertEqual(TexGran.overlap(0), 0.5, accuracy: 1e-12)
        XCTAssertEqual(TexGran.overlap(1), 24, accuracy: 1e-9)
        XCTAssertEqual(TexGran.overlap(0.6), 5.1, accuracy: 0.05)
        let h = Params.grid(sound: "mi:26")
        XCTAssertEqual(h[4].format(62), "151ms")
        XCTAssertEqual(h[4].format(100), "800ms")
        XCTAssertEqual(h[8].format(60), "×5.1")
        XCTAssertEqual(h[12].format(25), "25%")
        TexGran.sourceSeconds = 8
        XCTAssertEqual(h[0].format(8), "0.64 s")
        TexGran.sourceSeconds = 0
        // Частота запуска = зёрен одновременно / длина: SIZE не открывает пауз; не больше 100 в секунду.
        let a = TexGran.state(size: 0.4, density: 0.6, sc: 1, sampleSeconds: 8)
        let b = TexGran.state(size: 0.9, density: 0.6, sc: 1, sampleSeconds: 8)
        XCTAssertEqual(a.rate * a.dur, b.rate * b.dur, accuracy: 1e-9)
        let fast = TexGran.state(size: 0, density: 1, sc: 1, sampleSeconds: 8)
        XCTAssertEqual(fast.eff, 1, accuracy: 1e-9)
        XCTAssertEqual(fast.rate, 100, accuracy: 1e-9)
        // Короткий сэмпл: зерно не длиннее 0,9 длины; больше 4 нот — меньше зёрен на ноту.
        XCTAssertEqual(TexGran.state(size: 1, density: 0.5, sc: 1, sampleSeconds: 0.1).dur, 0.09, accuracy: 1e-12)
        XCTAssertEqual(TexGran.state(size: 0.62, density: 0.6, sc: 0.5, sampleSeconds: 8).eff, TexGran.overlap(0.6) / 2,
                       accuracy: 1e-9)
    }

    /// Разбросы SPRAY при 0, 25, 60 и 100 %: высота (центы), панорама, позиция, время.
    func testSprayCurves() {
        let cases: [(Double, Double, Double, Double, Double)] = [
            // sp, центы, панорама, позиция, дрожание интервала
            (0, 0, 0.1, 0, 0),
            (0.25, 1.5625, 0.1375, 0.0125, 0),
            (0.6, 9, 0.316, 0.072, 0.4 * pow(TexGran.smooth(0.4, 1, 0.6), 2)),
            (1, 145, 0.7, 0.2, 0.4),
        ]
        for (sp, c, p, x, j) in cases {
            XCTAssertEqual(TexGran.centsSpread(sp), c, accuracy: 1e-9, "\(sp)")
            XCTAssertEqual(TexGran.panSpread(sp), p, accuracy: 1e-9, "\(sp)")
            XCTAssertEqual(TexGran.posSpread(sp), x, accuracy: 1e-9, "\(sp)")
            XCTAssertEqual(TexGran.jitter(sp), j, accuracy: 1e-9, "\(sp)")
        }
        XCTAssertEqual(TexGran.jitter(0.4), 0)
        XCTAssertEqual(TexGran.smooth(0.4, 1, 0.6), 0.259, accuracy: 0.001)
        // Настоящие зёрна: разброс не выходит за формулы.
        for (sp, c, p, _, _) in cases {
            var cents: [Double] = [], pans: [Double] = []
            let cl = Cloud(notes: [48], k: [0.5, 0.5, 0.8, sp], seed: 3)
            cl.voices[0].onSpawn = { _, _, rate, pan in
                cents.append(1200 * log2(rate))
                pans.append(pan)
            }
            _ = cl.render(frames: 48000, sample: GranularEngineTests.demo)
            XCTAssertGreaterThan(cents.count, 20)
            XCTAssertLessThanOrEqual(cents.map { abs($0) }.max() ?? 0, c + 1e-6, "\(sp)")
            XCTAssertLessThanOrEqual(pans.map { abs($0) }.max() ?? 0, min(1, p) + 1e-9, "\(sp)")
            if sp > 0.5 { XCTAssertGreaterThan(cents.map { abs($0) }.max() ?? 0, c * 0.5) }
        }
    }

    /// Окна: Ханн и Гаусс σ = 0,2 (обнулён на краях), таблица 128 точек.
    func testWindows() {
        XCTAssertEqual(GranularVoice.window(0, gauss: false), 0, accuracy: 1e-12)
        XCTAssertEqual(GranularVoice.window(1, gauss: false), 0, accuracy: 1e-12)
        XCTAssertEqual(GranularVoice.window(0.5, gauss: false), 1, accuracy: 1e-3)
        XCTAssertEqual(GranularVoice.window(0.25, gauss: false), 0.5, accuracy: 0.01)
        XCTAssertEqual(GranularVoice.window(0, gauss: true), 0, accuracy: 1e-12)
        XCTAssertEqual(GranularVoice.window(1, gauss: true), 0, accuracy: 1e-12)
        XCTAssertEqual(GranularVoice.window(0.5, gauss: true), 1, accuracy: 1e-3)
        let sg = 0.2, g0 = exp(-0.5 * pow(0.5 / sg, 2))
        let want = (exp(-0.5 * pow(0.3 / sg, 2)) - g0) / (1 - g0)
        XCTAssertEqual(GranularVoice.window(0.2, gauss: true), want, accuracy: 0.01)
        // Ханн, равные интервалы, перекрытие 2 и больше — сумма окон постоянна.
        var sum = [Double](repeating: 0, count: 100)
        for k in 0..<4 { for i in 0..<100 { sum[i] += GranularVoice.window(Double((i + k * 25) % 100) / 100, gauss: false) } }
        XCTAssertLessThan((sum.max() ?? 0) - (sum.min() ?? 0), 0.01)
    }

    /// Интервал и усиление шины: без Ts — dur / eff и 1,3 / √eff; с Ts — целое число периодов выхода, усиление
    /// синфазных зёрен (по амплитуде) с переходом к несинфазному по SPRAY 30…70 %.
    func testPlan() {
        let a = TexGran.plan(dur: 0.15, eff: 5, ts: 0, semi: 0, spray: 0.25)
        XCTAssertEqual(a.iv, 0.03, accuracy: 1e-12)
        XCTAssertEqual(a.gain, 1.3 / sqrt(5), accuracy: 1e-12)
        let ts = 1.0 / 110
        let b = TexGran.plan(dur: 0.15, eff: 5, ts: ts, semi: 12, spray: 0)
        let tout = ts / 2
        XCTAssertEqual((b.iv / tout).rounded(), b.iv / tout, accuracy: 1e-9)
        XCTAssertEqual(b.iv, 7 * tout, accuracy: 1e-12)
        XCTAssertEqual(b.gain, 1.5 * 1.3 / (0.15 / b.iv), accuracy: 1e-12)
        let c = TexGran.plan(dur: 0.15, eff: 5, ts: ts, semi: 12, spray: 0.8)
        XCTAssertEqual(c.gain, 1.3 / sqrt(0.15 / c.iv), accuracy: 1e-12)
        // Интервал короче периода — один период.
        XCTAssertEqual(TexGran.plan(dur: 0.01, eff: 24, ts: ts, semi: 0, spray: 0).iv, ts, accuracy: 1e-12)
    }

    // MARK: — звук

    /// Без сэмпла — тишина, без NaN; зёрен нет.
    func testNoSampleSilent() {
        let (l, r) = GranularEngineTests.render([0.08, 0.62, 0.6, 0.25], sample: nil)
        XCTAssertEqual(l.map { abs($0) }.max(), 0)
        XCTAssertEqual(r.map { abs($0) }.max(), 0)
    }

    /// Spray 0: интервалы между зёрнами равны с точностью до отсчёта, высота без разброса; с известным Ts — моменты
    /// на сетке периодов выхода (до отсчёта), позиции кратны Ts.
    func testSprayZeroGrid() {
        for (smp, note) in [(GranularEngineTests.demo, 48.0), (GranularEngineTests.pad, 48.0), (GranularEngineTests.pad, 55.0)] {
            var times: [Double] = [], rates: [Double] = [], poss: [Double] = []
            let cl = Cloud(notes: [note], k: [0.3, 0.62, 0.6, 0], seed: 2)
            cl.voices[0].onSpawn = { t, p, rate, _ in
                times.append(t)
                poss.append(p)
                rates.append(rate)
            }
            _ = cl.render(frames: 96000, sample: smp)
            XCTAssertGreaterThan(times.count, 50)
            let iv = times[1] - times[0]
            for i in 2..<times.count { XCTAssertEqual(times[i] - times[i - 1], iv, accuracy: 1e-6) }
            let want: Double = pow(2, (note - 48) / 12)
            for r in rates { XCTAssertEqual(r, want, accuracy: 1e-12) }
            if smp.period > 0 {
                let tout = smp.period / want * 48000
                for t in times {
                    let k = ((t - times[0]) / tout).rounded()
                    XCTAssertLessThan(abs(t - times[0] - k * tout), 1, "момент вне сетки Tout")
                }
                for p in poss where p > 0.01 {
                    let k = (p / smp.period).rounded()
                    XCTAssertLessThan(abs(p - k * smp.period), 1e-9)
                }
            }
        }
    }

    /// Ровность: CV RMS окон 10 мс на однотоновом источнике (Ts известен), A3 удержана: Spray 10 % — не больше 0,10;
    /// Spray 25 % — печать для отчёта (ориентир ТЗ 0,15–0,25, прототип ниже).
    func testEvenness() {
        var lines: [String] = []
        for (sp, limit) in [(0.0, 0.10), (0.1, 0.10), (0.25, 0.25)] {
            var cv = 0.0
            for run in 0..<3 {
                let (l, r) = GranularEngineTests.render([0.08, 0.62, 0.6, sp], notes: [57], frames: 480000, seed: 31 + run)
                cv += ProtoCompare.cv(l, r) / 3
            }
            lines.append(String(format: "  spray %.0f%%: CV %.3f", sp * 100, cv))
            XCTAssertLessThanOrEqual(cv, limit, "spray \(sp)")
        }
        print("GRANULAR evenness (A3, pad):\n" + lines.joined(separator: "\n"))
    }

    /// Сверка с прототипом (proto.json, 4 прогона по 10 с, Hold): RMS и полосы ±3 dB, ровность — печать.
    func testMatchesPrototype() throws {
        let refs = ProtoCompare.load()
        try XCTSkipIf(refs.isEmpty, "нет proto.json")
        let names = refs.keys.filter { $0.hasPrefix("gran_") }.sorted()
        XCTAssertEqual(names.count, 11)
        let g = 20 * log10(TexGran.out)
        for name in names {
            let ref = refs[name]!
            var cv = 0.0
            let s = ProtoCompare.average(4) { run in
                let notes = ref.semis.map { 48 + $0 }
                let smp = ref.src == "pad" ? GranularEngineTests.padVariant(run) : GranularEngineTests.demo
                let (l, r) = GranularEngineTests.render(ref.k, notes: notes, frames: 480000, seed: 21 + run, sample: smp)
                cv += ProtoCompare.cv(l, r) / 4
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
            print(String(format: "%@ rms %.4f (ref×out %.4f) %+.1f dB, peak %.2f (ref×out %.2f), worst band %d Hz %+.1f dB, cv %.3f (ref %.3f)",
                         name, s.rms, ref.rms * TexGran.out, dRms, s.peak, ref.peak * TexGran.out,
                         Int(1000 * pow(2, Double(worstAt - 16) / 3)), worst, cv, ref.cv))
            if ProcessInfo.processInfo.environment["GRAN_BANDS"] != nil {
                print(ref.bands.enumerated().map { i, b in String(format: "%d:%+.1f(%.0f)", Int(1000 * pow(2, Double(i - 16) / 3)), s.bands[i] - g - b, b - top) }.joined(separator: " "))
            }
            XCTAssertLessThan(abs(dRms), 3, name)
            XCTAssertLessThan(abs(worst), 3, name)
        }
    }

    /// Окно запуска: новые зёрна не рождаются, звучащие доигрывают — потом тишина.
    func testWindow() {
        let (l, _) = GranularEngineTests.render([0.08, 0.62, 0.6, 0.25], frames: 72000, window: 4800)
        XCTAssertLessThan(l[48000...].map { abs($0) }.max() ?? 1, 1e-6)
        XCTAssertGreaterThan(l[..<9600].map { abs($0) }.max() ?? 0, 0.01)
    }

    /// Резкие ручки, смена ноты и сэмпла посреди игры: без NaN и без скачков больше, чем в обычном облаке.
    func testSwapAndKnobs() {
        let other = SampleData(left: (0..<96000).map { Float(sin(Double($0) * 0.05) * 0.8) },
                               right: (0..<96000).map { Float(cos(Double($0) * 0.031) * 0.8) })
        let a: [Double] = [0.2, 0.6, 0.6, 0.3], b: [Double] = [0.8, 0.2, 0.95, 0.9]
        let (l, r) = GranularEngineTests.render(a, frames: 96000, sample: GranularEngineTests.demo) { pos, cl in
            let k = (pos / 4800) % 2 == 0 ? a : b
            cl.voices[0].set(note: (pos / 9600) % 2 == 0 ? 48 : 55, k[0], k[1], k[2], k[3])
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
                let (x, y) = GranularEngineTests.render(k, notes: [55], frames: 48000, sample: smp)
                ref = max(ref, maxStep(x, y))
            }
        }
        print(String(format: "GRANULAR swap: max step %.4f, ref %.4f", maxStep(l, r), ref))
        XCTAssertLessThan(maxStep(l, r), ref * 1.5)
    }

    /// Резкая смена SIZE и DENSITY — без провала и скачка уровня: RMS окон 10 мс в переходе (0,6 с) — в пределах
    /// от половины до полутора средних уровней по сторонам (пэд, Spray 30 %; провал без сглаживания SIZE — до 0,02).
    func testGainSmooth() {
        var lines: [String] = []
        for (a, b) in [([0.5, 0.3, 0.6, 0.3], [0.5, 0.9, 1, 0.3]), ([0.5, 0.9, 1, 0.3], [0.5, 0.3, 0.6, 0.3]),
                       ([0.5, 0.62, 0.3, 0.3], [0.5, 0.62, 1, 0.3])] {
            var ws: [Double] = []
            for run in 0..<3 {
                let (l, r) = GranularEngineTests.render(a, frames: 144000, seed: 40 + run) { pos, cl in
                    let k = pos < 72000 ? a : b
                    cl.voices[0].set(note: 48, k[0], k[1], k[2], k[3])
                    return nil
                }
                var s = 0, i = 0
                while s + 480 <= l.count {
                    var p = 0.0
                    for j in s..<(s + 480) { p += Double(l[j] * l[j] + r[j] * r[j]) / 2 }
                    if run == 0 { ws.append(p / 480) } else { ws[i] += p / 480 }
                    s += 480
                    i += 1
                }
            }
            ws = ws.map { sqrt($0 / 3) }
            let before = ws[50..<150].reduce(0, +) / 100
            let after = ws[230..<300].reduce(0, +) / 70
            let tr = ws[150..<210]
            let lo = (tr.min() ?? 0) / min(before, after), hi = (tr.max() ?? 0) / max(before, after)
            lines.append(String(format: "  %@ → %@: before %.3f after %.3f, transition min ×%.2f max ×%.2f",
                                "\(a)", "\(b)", before, after, lo, hi))
            XCTAssertGreaterThan(lo, 0.5, "\(a) → \(b)")
            XCTAssertLessThan(hi, 1.5, "\(a) → \(b)")
        }
        print("GRANULAR gain smooth:\n" + lines.joined(separator: "\n"))
    }

    /// Плотный край (DENSITY 1, SIZE 1), восемь нот дорожки: не больше 240 зёрен на дорожку.
    func testDenseLimit() {
        let cl = Cloud(notes: [48, 51, 53, 55, 58, 60, 63, 65], k: [0.08, 1, 1, 0.25], seed: 5)
        var most = 0
        var peak: Float = 0
        let (l, r) = cl.render(frames: 48000 * 3, sample: GranularEngineTests.pad) { _, c in
            most = max(most, c.track.pointee.grains)
            return nil
        }
        for i in 0..<l.count { peak = max(peak, abs(l[i]), abs(r[i])) }
        XCTAssertLessThanOrEqual(most, 240)
        XCTAssertGreaterThan(most, 50)
        // Пик — выход голосов до Level, громкости дорожки (−10 dB) и мастера; на мастере — testGranularMasterLevel.
        print(String(format: "GRANULAR dense ×8: grains %d, peak %.2f", most, peak))
        XCTAssertLessThan(peak, 3)
    }
}
