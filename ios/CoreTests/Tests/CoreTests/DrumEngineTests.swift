import XCTest
@testable import Core

/// S12, этап 3: ударные SNARE, HAT, CLAP, PERC — проверка по свойствам (NaN, пик, слышимость, алиасинг HAT,
/// стык ретрига, нагрузка).
final class DrumEngineTests: XCTestCase {
    private static let tables = JamboTables()
    private let drums = [Jambo.snare, Jambo.hat, Jambo.clap, Jambo.perc]

    /// Удар движка e (ручки 0…1); retrig — второй удар в этом кадре.
    private func render(_ e: Int, _ k: [Double], decay: Double = 400, frames: Int = 24000, retrig: Int? = nil) -> [Float] {
        let v = JamboDrumVoice(tables: DrumEngineTests.tables, sampleRate: 48000)
        v.trigger(engine: e, k[0], k[1], k[2], k[3], decay: decay)
        var out = [Float](repeating: 0, count: frames)
        var pos = 0
        out.withUnsafeMutableBufferPointer { b in
            while pos < frames {
                if let r = retrig, pos == r { v.trigger(engine: e, k[0], k[1], k[2], k[3], decay: decay) }
                var n = min(24, frames - pos)
                if let r = retrig, pos < r { n = min(n, r - pos) }
                v.render(b.baseAddress! + pos, n)
                pos += n
            }
        }
        return out
    }

    func testTable() {
        XCTAssertEqual(SynthEngines.drums, [16, 20, 21, 22, 23])
        XCTAssertEqual(SynthEngines.synths, [17, 24, 18, 19])
        for e in drums {
            let eng = SynthEngines.engine(e)
            XCTAssertEqual(eng?.decay, true)
            XCTAssertTrue(Jambo.mono(e))
        }
        XCTAssertFalse(Jambo.mono(Jambo.analog))
        XCTAssertEqual(Params.grid(sound: "mi:22")[4].format(50), "4", "BURSTS по умолчанию — 4")
        XCTAssertEqual(Params.grid(sound: "mi:22")[0].format(50), "1099 Hz", "TONE CLAP на 50 % ≈ 1.1 кГц")
        XCTAssertEqual(Params.grid(sound: "mi:22")[8].format(50), "12.0 ms")
        XCTAssertEqual(Params.grid(sound: "mi:21")[0].format(50), "0 st")
        XCTAssertEqual(Params.grid(sound: "mi:20")[5].max, 800)
        XCTAssertEqual(Params.grid(sound: "mi:23")[5].max, 2000)
    }

    /// Сетка ручек 0 / 50 / 100 % и Decay от минимума до предела: NaN нет, пик < 0 dBFS, по умолчанию слышно.
    func testFiniteAndPeak() {
        var peaks: [Int: Float] = [:]
        for e in drums {
            for a in [0.0, 0.5, 1] {
                for b in [0.0, 0.5, 1] {
                    for dec in [10.0, 400, 2000] {
                        let x = render(e, [a, b, 1 - a, b], decay: dec, frames: 12000)
                        XCTAssertFalse(x.contains { !$0.isFinite }, "\(e) \(a) \(b) \(dec)")
                        XCTAssertLessThan(x.map(abs).max() ?? 2, 1, "\(e)")
                    }
                }
            }
            let def = render(e, [0.5, 0.5, 0.5, 0.5])
            peaks[e] = def.map(abs).max() ?? 0
            XCTAssertGreaterThan(peaks[e] ?? 0, 0.2, "движок \(e) по умолчанию слышен")
        }
        print("drum peaks (defaults):", peaks.sorted { $0.key < $1.key }
            .map { "\($0.key) \(String(format: "%.1f", 20 * log10($0.value))) dBFS" })
    }

    /// Decay — длина звука: через Decay уровень ниже −50 dB от пика.
    func testDecayLength() {
        for e in drums {
            let x = render(e, [0.5, 0.5, 0.5, 0.5], decay: 300, frames: 48000)
            let pk = x.map(abs).max() ?? 1
            let tail = x[(14400 + 4800)..<48000].map(abs).max() ?? 1
            XCTAssertLessThan(tail / pk, 0.0032, "движок \(e): затух")
        }
    }

    /// Новый удар обрывает прошлый без щелчка: шаг между отсчётами на стыке — не больше, чем в начале удара.
    func testRetrigWithoutClick() {
        for e in [Jambo.snare, Jambo.perc] {
            let fresh = render(e, [0.5, 0.5, 0.5, 0], frames: 3000)
            var steady: Float = 0
            for i in 1..<3000 { steady = max(steady, abs(fresh[i] - fresh[i - 1])) }
            let x = render(e, [0.5, 0.5, 0.5, 0], frames: 9000, retrig: 6000)
            var worst: Float = 0
            for i in 5990..<6100 { worst = max(worst, abs(x[i] - x[i - 1])) }
            XCTAssertLessThanOrEqual(worst, steady * 1.2 + 1e-4, "движок \(e)")
        }
    }

    /// CLAP: вспышки по BURSTS — число пиков огибающей в кластере.
    func testClapBursts() {
        for (knob, count) in [(0.05, 1), (0.5, 4), (0.95, 6)] {
            let x = render(Jambo.clap, [0.5, knob, 0.5, 0], decay: 50, frames: 9600)
            // Огибающая по 2 мс; вспышка — рост больше чем втрое до уровня выше трети пика.
            var env: [Float] = []
            for b in 0..<(9600 / 96) { env.append(x[(b * 96)..<(b * 96 + 96)].map(abs).max() ?? 0) }
            let pk: Float = env.max() ?? 1
            var rises = 0
            for b in 1..<env.count where env[b] > 3 * env[b - 1] && env[b] > pk / 3 { rises += 1 }
            XCTAssertEqual(rises + 1, count, "BURSTS \(count)")
        }
    }

    /// Алиасинг HAT (только металл): составляющие не на нечётных гармониках шести квадратов — ниже −50 dB.
    func testHatAliasing() {
        let x = render(Jambo.hat, [0.75, 0.5, 0.75, 0], decay: 1500, frames: 16384 + 480)
        let seg = Array(x[480..<(480 + 16384)])
        let tune = pow(2, 2 * 0.75 - 1)
        let m = Jambo.hatMean
        let freqs: [Double] = [205.3, 304.4, 369.6, 522.7, 540, 800].map { tune * m * pow($0 / m, 1) }
        let n = seg.count
        var re = [Double](repeating: 0, count: n), im = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let a = 2 * Double.pi * Double(i) / Double(n)
            re[i] = Double(seg[i]) * (0.35875 - 0.48829 * cos(a) + 0.14128 * cos(2 * a) - 0.01168 * cos(3 * a))
        }
        SynthKnobsTests.fft(&re, &im)
        let binHz = 48000.0 / Double(n)
        var expected = Set<Int>()
        for f in freqs {
            var k = 1.0
            while k * f < 24000 {
                let b = Int((k * f / binHz).rounded())
                for d in -6...6 { expected.insert(b + d) }
                k += 2
            }
        }
        var top = 0.0, worst = 0.0
        for b in Int(20 / binHz)..<Int(20000 / binHz) {
            let mag = (re[b] * re[b] + im[b] * im[b]).squareRoot()
            if expected.contains(b) { top = max(top, mag) } else { worst = max(worst, mag) }
        }
        let db = 20 * log10(max(worst, 1e-12) / max(top, 1e-12))
        print(String(format: "HAT aliasing: %.1f dB", db))
        XCTAssertLessThan(db, -50)
    }

    /// Нагрузка: 8 ударов каждого движка по 1 с (отладочная сборка тестов, доля одного ядра).
    func testLoad8Hits() {
        for e in drums {
            let t0 = Date()
            for _ in 0..<8 { _ = render(e, [0.5, 0.5, 0.5, 0.5], decay: 2000, frames: 48000) }
            print(String(format: "drum %d: 8 hits — %.1f%% of one core", e, Date().timeIntervalSince(t0) * 100))
        }
    }

    /// Иконки ударных: есть элементы, координаты конечны и в поле 64×64 (с запасом на штрих), меняются от ручек.
    func testIcons() {
        for e in drums + [Jambo.sub] {
            var seen = Set<String>()
            for a in [0.0, 0.5, 1] {
                for b in [0.0, 1] {
                    let els = EngineIcons.elements(e, IconValues(h: a, t: b, m: 1 - a, q: b, d: a))
                    XCTAssertFalse(els.isEmpty, "\(e)")
                    for el in els {
                        for c in el.cmds {
                            switch c {
                            case .move(let x, let y), .line(let x, let y):
                                XCTAssertTrue(x.isFinite && y.isFinite && x >= 0 && x <= 64 && y >= 0 && y <= 64, "\(e) \(x) \(y)")
                            default:
                                break
                            }
                        }
                    }
                    seen.insert("\(els.map { $0.cmds })")
                }
            }
            XCTAssertGreaterThan(seen.count, 3, "иконка \(e) живая")
        }
    }
}
