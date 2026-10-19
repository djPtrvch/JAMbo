import XCTest
@testable import Core

/// S12, этап 2: ручки 1.4 своих движков — перевод старых проектов (версия 4) и проверка по свойствам
/// (NaN, пик, алиасинг ANALOG, щелчки при смене ручки, нагрузка 8 голосов).
final class SynthKnobsTests: XCTestCase {
    // MARK: — перевод старых проектов

    func testMigrateKnobs() {
        let an = SynthMigration.knobs(Jambo.analog, 37.5, 50, 30)
        XCTAssertEqual([an.h, an.t, an.m, an.p4], [37.5, 37.5, 50, 50])
        XCTAssertTrue(an.lostSub)
        XCTAssertFalse(SynthMigration.knobs(Jambo.analog, 37.5, 50, 0).lostSub)
        let kick = SynthMigration.knobs(Jambo.drum, 50, 40, 70)
        XCTAssertEqual([kick.m, kick.p4], [70, 70], "CLICK — прежний уровень клика (от DRIVE)")
        let one = SynthMigration.knobs(Jambo.wtable, 10, 20, 20)
        XCTAssertEqual(one.m, 100.0 / 6, accuracy: 1e-9, "UNISON до 25 % — один голос")
        let three = SynthMigration.knobs(Jambo.wtable, 10, 20, 70)
        XCTAssertEqual(three.m, 50)
        XCTAssertEqual(three.p4, 24.0 / 60 * 100, accuracy: 1e-9, "прежние 24 цента")
        XCTAssertEqual(SynthMigration.knobs(Jambo.fm, 1, 2, 3).p4, 50)
    }

    func testMigrateProject() throws {
        var p = Project()
        p.version = 3
        p.tracks[0].name = "Bass"
        p.tracks[0].sample = "mi:17"
        p.tracks[0].params["harm"] = 62.5
        p.tracks[0].params["timbre"] = 40
        p.tracks[0].params["morph"] = 25
        p.tracks[0].assigns["timbre"] = ModAssign(lfo: 1, amount: 0.3)
        p.tracks[0].assigns["morph"] = ModAssign(lfo: 2, amount: 0.5)
        p.tracks[0].pages[0][2].locks = ["timbre": 80, "decay": 100]
        p.tracks[1].sample = "mi:19"
        p.tracks[1].params["morph"] = 10
        p.tracks[2].sample = "mi:17"
        p.tracks[2].params["morph"] = 0
        p.repair()
        XCTAssertEqual(p.version, 4)
        let t = p.tracks[0]
        XCTAssertEqual(t.params["harm"], 62.5)
        XCTAssertEqual(t.params["timbre"], 62.5, "WAVE B — прежний WAVE")
        XCTAssertEqual(t.params["morph"], 40, "DETUNE — с 1.2 на 1.3")
        XCTAssertEqual(t.params["p4"], 50)
        XCTAssertEqual(t.assigns["morph"], ModAssign(lfo: 1, amount: 0.3))
        XCTAssertNil(t.assigns["timbre"])
        XCTAssertEqual(t.pages[0][2].locks, ["morph": 80, "decay": 100])
        XCTAssertEqual(p.tracks[1].params["morph"] ?? 0, 100.0 / 6, accuracy: 1e-9)
        XCTAssertEqual(p.notice, "SUB removed (ANALOG): Bass", "у T3 суба не было")
        // Повторный repair (версия 4) ничего не переводит.
        var q = p
        q.repair()
        XCTAssertEqual(q.tracks[0].params, p.tracks[0].params)
    }

    func testPresetMigration() throws {
        let web = Data(#"{"name":"Pad","sound":"mi:17","params":{"harm":87.5,"timbre":20,"morph":60},"fmt":2}"#.utf8)
        let p = try JSONDecoder().decode(SynthPreset.self, from: web)
        XCTAssertEqual(p.fmt, 3)
        XCTAssertEqual(p.params["timbre"], 87.5)
        XCTAssertEqual(p.params["morph"], 20)
        let again = try JSONDecoder().decode(SynthPreset.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(again, p, "fmt 3 — без повторного перевода")
    }

    // MARK: — звук по свойствам

    private static let tables = JamboTables()
    private static let basic = WtTable.builtin("BASIC")

    /// n кадров движка e: ручки 0…1, нота note; change — смена ручек в кадре at.
    private func render(_ e: Int, note: Double, _ k: [Double], decay: Double = 500, frames: Int = 24000,
                        change: (at: Int, k: [Double])? = nil) -> [Float] {
        let v = JamboVoice(tables: SynthKnobsTests.tables, sampleRate: 48000)
        let wt = SynthKnobsTests.basic
        let ref = e == Jambo.wtable ? WtRef(frames: wt.frames, sizes: UnsafePointer(wt.sizes), data: UnsafePointer(wt.data))
            : WtRef()
        v.trigger(engine: e, note: note, k[0], k[1], k[2], k[3], decay: decay, now: 0, tau: 0)
        var out = [Float](repeating: 0, count: frames)
        var pos = 0
        out.withUnsafeMutableBufferPointer { b in
            while pos < frames {
                if let c = change, pos == c.at { v.set(note: note, c.k[0], c.k[1], c.k[2], c.k[3], decay: decay) }
                let n = min(24, frames - pos)
                v.render(b.baseAddress! + pos, n, driftRatio: 1, table: ref)
                pos += n
            }
        }
        return out
    }

    /// Сетка ручек 0 / 50 / 100 % и ноты C1–C7: без NaN, пик ≤ 0 dBFS.
    func testFiniteAndPeak() {
        var worst: [Int: Float] = [:]
        for e in [Jambo.drum, Jambo.analog, Jambo.fm, Jambo.wtable] {
            for note in stride(from: 24.0, through: 96, by: 24) {
                for a in [0.0, 0.5, 1] {
                    for b in [0.0, 1] {
                        let x = render(e, note: note, [a, b, 1 - a, b], frames: 9600)
                        XCTAssertFalse(x.contains { !$0.isFinite }, "\(e) \(note) \(a) \(b)")
                        let pk = x.map(abs).max() ?? 0
                        worst[e] = max(worst[e] ?? 0, pk)
                    }
                }
            }
            XCTAssertLessThanOrEqual(worst[e] ?? 2, 1.0, "движок \(e)")
        }
        print("peaks:", worst.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.1f", 20 * log10($0.value))) dBFS" })
    }

    /// MIX ANALOG: A и B — синусы; 0 и 100 % — одна форма, 50 % — та же громкость (нормировка на сумму долей).
    func testAnalogMixLevel() {
        func rms(_ k: [Double]) -> Float {
            let x = render(Jambo.analog, note: 57, k)
            var s: Float = 0
            for i in 4800..<24000 { s += x[i] * x[i] }
            return (s / 19200).squareRoot()
        }
        let a = rms([0.125, 0.125, 0, 0]), mid = rms([0.125, 0.125, 0, 0.5]), b = rms([0.125, 0.125, 0, 1])
        XCTAssertEqual(mid / a, 1, accuracy: 0.02)
        XCTAssertEqual(b / a, 1, accuracy: 0.02)
        // Разные формы: A — синус, B — квадрат; MIX 0 — синус (пик ниже квадрата на MIX 100 нет: пики выровнены).
        let sq = render(Jambo.analog, note: 57, [0.125, 0.875, 0, 1])
        XCTAssertGreaterThan(sq.map(abs).max() ?? 0, 0.3)
    }

    /// Смена MIX на звучащей ноте сглаживается (5 мс): шаг между отсчётами не больше, чем у самих волн A и B.
    func testMixChangeNoClick() {
        let x = render(Jambo.analog, note: 45, [0.125, 0.625, 0, 0], change: (at: 12000, k: [0.125, 0.625, 0, 1]))
        let b = render(Jambo.analog, note: 45, [0.125, 0.625, 0, 1])
        func maxStep(_ y: [Float], _ r: Range<Int>) -> Float { r.map { abs(y[$0] - y[$0 - 1]) }.max() ?? 0 }
        let steady = max(maxStep(x, 4801..<12000), maxStep(b, 4801..<12000))
        XCTAssertLessThanOrEqual(maxStep(x, 12000..<12600), steady * 1.05 + 1e-4)
    }

    /// Алиасинг ANALOG: пила C6, только A (MIX 0) — посторонние составляющие ниже −60 dBc.
    func testAnalogAliasing() {
        let x = render(Jambo.analog, note: 84, [0.625, 0.625, 0, 0], frames: 4800 + 16384)
        let seg = Array(x[4800..<(4800 + 16384)])
        let db = SynthKnobsTests.nonHarmonicDbc(seg, f0: 440 * pow(2, (84 - 69) / 12.0))
        print(String(format: "ANALOG saw C6 aliasing: %.1f dBc", db))
        XCTAssertLessThan(db, -60)
    }

    /// Нагрузка: 8 голосов каждого движка, 1 с (отладочная сборка тестов, доля одного ядра).
    func testLoad8Voices() {
        for e in [Jambo.drum, Jambo.analog, Jambo.fm, Jambo.wtable] {
            let t0 = Date()
            for k in 0..<8 { _ = render(e, note: 48 + Double(k * 3), [0.5, 0.5, 1, 0.5], frames: 48000) }
            print(String(format: "engine %d: 8 voices — %.1f%% of one core", e, Date().timeIntervalSince(t0) * 100))
        }
    }

    /// Наибольшая составляющая 20 Гц–20 кГц не на гармониках f0 (±6 бинов) относительно основной, dBc (окно
    /// Блэкмана–Харриса, ДПФ по 2^k; выше 20 кГц — переходная полоса фильтра децимации, не слышно).
    static func nonHarmonicDbc(_ x: [Float], f0: Double) -> Double {
        let n = x.count
        var re = [Double](repeating: 0, count: n), im = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let a = 2 * Double.pi * Double(i) / Double(n)
            let w = 0.35875 - 0.48829 * cos(a) + 0.14128 * cos(2 * a) - 0.01168 * cos(3 * a)
            re[i] = Double(x[i]) * w
        }
        fft(&re, &im)
        let binHz = 48000.0 / Double(n)
        var fund = 0.0, worst = 0.0
        // Ниже 20 Гц (постоянная составляющая и утечка окна у нуля) не считается.
        for k in Int((20 / binHz).rounded(.up))..<Int(20000 / binHz) {
            let m = (re[k] * re[k] + im[k] * im[k]).squareRoot()
            let h = Double(k) * binHz / f0
            let near = abs(h - h.rounded()) * f0 / binHz <= 6 && h.rounded() >= 1
            if near && h.rounded() == 1 { fund = max(fund, m) } else if !near { worst = max(worst, m) }
        }
        return 20 * log10(max(worst, 1e-12) / max(fund, 1e-12))
    }

    static func fft(_ re: inout [Double], _ im: inout [Double]) {
        let n = re.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j |= bit
            if i < j { re.swapAt(i, j); im.swapAt(i, j) }
        }
        var len = 2
        while len <= n {
            let ang = -2 * Double.pi / Double(len)
            for s in stride(from: 0, to: n, by: len) {
                for k in 0..<(len / 2) {
                    let wr = cos(ang * Double(k)), wi = sin(ang * Double(k))
                    let a = s + k, b = a + len / 2
                    let tr = re[b] * wr - im[b] * wi, ti = re[b] * wi + im[b] * wr
                    re[b] = re[a] - tr; im[b] = im[a] - ti
                    re[a] += tr; im[a] += ti
                }
            }
            len <<= 1
        }
    }
}
