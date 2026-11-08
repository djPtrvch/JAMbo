import XCTest
@testable import Core

/// ANALOG: модуляция B осциллятором A (SYNC, FM, RING) и октава B (8.11) — переключатели, пресеты, звук по свойствам.
final class AnalogModTests: XCTestCase {
    // MARK: — переключатели

    func testToggleAndCycle() {
        XCTAssertEqual(AnalogMod.mode(0), 0)
        XCTAssertEqual(AnalogMod.toggled(0), 1, "первое включение — SYNC")
        XCTAssertEqual(AnalogMod.cycled(1), 2)
        XCTAssertEqual(AnalogMod.cycled(2), 3)
        XCTAssertEqual(AnalogMod.cycled(3), 1)
        XCTAssertEqual(AnalogMod.cycled(1, back: true), 3, "второй тап двойного отменяет первый")
        XCTAssertEqual(AnalogMod.cycled(AnalogMod.cycled(2), back: true), 2)
        let off: Double = AnalogMod.toggled(3)
        XCTAssertEqual(AnalogMod.mode(off), 0)
        XCTAssertEqual(AnalogMod.cycled(off), off, "выключена — режим не меняется")
        XCTAssertEqual(AnalogMod.toggled(off), 3, "включение — прежний режим")
    }

    func testKnobLabels() {
        let grid = Params.synthGrids[Jambo.analog]
        let morph = grid[2], timbre = grid[1]
        XCTAssertEqual(AnalogMod.knob(morph, engine: Jambo.analog, params: [:]).label, "Detune")
        let sync = AnalogMod.knob(morph, engine: Jambo.analog, params: [AnalogMod.modId: 1])
        XCTAssertEqual(sync.label, "Sync")
        XCTAssertEqual(sync.format(50), "+12.0 st")
        XCTAssertEqual(AnalogMod.knob(morph, engine: Jambo.analog, params: [AnalogMod.modId: 2]).label, "FM")
        XCTAssertEqual(AnalogMod.knob(morph, engine: Jambo.analog, params: [AnalogMod.modId: -3]).label, "Detune")
        let low = AnalogMod.knob(timbre, engine: Jambo.analog, params: [AnalogMod.octId: 1])
        XCTAssertEqual(low.format(62.5), "Saw\n−1", "«−1» — второй строкой")
        XCTAssertTrue(AnalogMod.knob(morph, engine: Jambo.fm, params: [AnalogMod.modId: 1]) === morph)
    }

    func testSelectEngineResetsAndPresets() {
        var t = Track(index: 0)
        t.params[AnalogMod.modId] = 2
        t.params[AnalogMod.octId] = 1
        t.setSynth(Jambo.fm)
        t.setSynth(Jambo.analog)
        XCTAssertEqual(t.params[AnalogMod.modId], 0)
        XCTAssertEqual(t.params[AnalogMod.octId], 0)
        t.params[AnalogMod.modId] = 3
        t.params[AnalogMod.octId] = 1
        let p = t.preset(named: "Ring")!
        XCTAssertEqual(p.params[AnalogMod.modId], 3)
        XCTAssertEqual(p.params[AnalogMod.octId], 1)
        // Пресет другого движка — без скрытых значений ANALOG.
        var f = Track(index: 1)
        f.setSynth(Jambo.fm)
        XCTAssertNil(f.preset(named: "FM")!.params[AnalogMod.modId])
        // Старый пресет ANALOG (без значений) выключает модуляцию у дорожки.
        let old = SynthPreset(name: "Old", sound: "mi:17", params: ["harm": 12.5])
        t.applyItem(FolderItem(preset: old))
        XCTAssertEqual(t.params[AnalogMod.modId], 0)
        XCTAssertEqual(t.params[AnalogMod.octId], 0)
    }

    func testPresetLockCarriesMode() {
        let locks = NoteLocks([AnalogMod.modId: 2, AnalogMod.octId: 1])
        XCTAssertNotEqual(locks.mask & (VoiceMask(1) << VoiceMask(VoiceParam.amod)), 0)
        XCTAssertNotEqual(locks.mask & (VoiceMask(1) << VoiceMask(VoiceParam.aoct)), 0)
        XCTAssertEqual(locks.vals.17, 2)
        XCTAssertEqual(locks.vals.18, 1)
    }

    // MARK: — звук по свойствам

    private static let tables = JamboTables()

    /// n кадров ANALOG: ручки 0…1, режим и октава; change — смена режима в кадре at.
    private func render(note: Double, _ k: [Double], mode: Int, oct: Bool = false, frames: Int = 24000,
                        change: (at: Int, mode: Int)? = nil) -> [Float] {
        let v = JamboVoice(tables: AnalogModTests.tables, sampleRate: 48000)
        v.setAnalog(mode: mode, oct: oct)
        v.trigger(engine: Jambo.analog, note: note, k[0], k[1], k[2], k[3], decay: 500, now: 0, tau: 0)
        var out = [Float](repeating: 0, count: frames)
        var pos = 0
        out.withUnsafeMutableBufferPointer { b in
            while pos < frames {
                if let c = change, pos == c.at { v.setAnalog(mode: c.mode, oct: oct) }
                let n = min(24, frames - pos)
                v.render(b.baseAddress! + pos, n, driftRatio: 1, table: WtRef())
                pos += n
            }
        }
        return out
    }

    /// Все режимы, формы и AMOUNT 0 / 50 / 100 %, ноты C1–C7, октава: без NaN, пик ≤ 0 dBFS.
    func testFiniteAndPeak() {
        var worst: Float = 0
        for mode in 1...3 {
            for note in stride(from: 24.0, through: 96, by: 24) {
                for w in [0.125, 0.375, 0.625, 0.875] {
                    for amt in [0.0, 0.5, 1] {
                        let x = render(note: note, [w, 1 - w, amt, 0.5], mode: mode, oct: amt == 0.5, frames: 4800)
                        XCTAssertFalse(x.contains { !$0.isFinite }, "\(mode) \(note) \(w) \(amt)")
                        worst = max(worst, x.map(abs).max() ?? 0)
                    }
                }
            }
        }
        print(String(format: "ANALOG mod peak: %.1f dBFS", 20 * log10(worst)))
        XCTAssertLessThanOrEqual(worst, 1)
    }

    /// AMOUNT 0: FM и RING звучат как без модуляции (B — свободный осциллятор).
    func testZeroAmountTransparent() {
        let plain = render(note: 57, [0.125, 0.625, 0, 0.5], mode: 0)
        for mode in [2, 3] {
            let x = render(note: 57, [0.125, 0.625, 0, 0.5], mode: mode)
            let d = zip(plain, x).map { abs($0 - $1) }.max() ?? 1
            XCTAssertLessThan(d, 1e-5, "режим \(mode)")
        }
    }

    /// Октава ниже: основная частота B (только B, MIX 100 %, синус) — вдвое ниже.
    func testOctaveDown() {
        let x = render(note: 69, [0.125, 0.125, 0, 1], mode: 0, oct: true, frames: 4800 + 16384)
        let seg = Array(x[4800..<(4800 + 16384)])
        // Число переходов через ноль за 16384 отсчёта: 220 Гц ≈ 2 · 220 · 0.341 с ≈ 150.
        var zc = 0
        for i in 1..<seg.count where (seg[i - 1] < 0) != (seg[i] < 0) { zc += 1 }
        XCTAssertEqual(Double(zc), 2 * 220 * 16384 / 48000, accuracy: 4)
    }

    /// Смена режима на звучащей ноте — кроссфейд 5 мс: шаг между отсчётами не больше, чем у самих волн.
    func testModeChangeNoClick() {
        func maxStep(_ y: [Float], _ r: Range<Int>) -> Float { r.map { abs(y[$0] - y[$0 - 1]) }.max() ?? 0 }
        for (from, to) in [(0, 1), (1, 2), (2, 3), (3, 0), (1, 0)] {
            let k = [0.375, 0.625, 0.7, 0.5]
            let x = render(note: 45, k, mode: from, change: (at: 12000, mode: to))
            let a = render(note: 45, k, mode: from), b = render(note: 45, k, mode: to)
            let steady = max(maxStep(a, 4801..<12000), maxStep(b, 4801..<12000))
            XCTAssertLessThanOrEqual(maxStep(x, 12000..<12600), steady * 1.1 + 1e-4, "\(from) → \(to)")
        }
    }

    /// SYNC: B — пила, только B (MIX 100 %), C5, AMOUNT 50 % (+12 полутонов) — гармоники A; посторонние — ниже −50 dB
    /// от самой сильной гармоники (скачок сброса сглажен PolyBLEP).
    func testSyncAliasing() {
        let x = render(note: 72, [0.125, 0.625, 0.5, 1], mode: 1, frames: 4800 + 16384)
        let seg = Array(x[4800..<(4800 + 16384)])
        let db = AnalogModTests.nonHarmonicDb(seg, f0: 440 * pow(2, (72 - 69) / 12.0))
        print(String(format: "ANALOG SYNC saw C5 aliasing: %.1f dBc", db))
        XCTAssertLessThan(db, -50)
        // Неровное отношение (+7.2 полутона): сброс посреди периода B — пила и квадрат.
        for w in [0.625, 0.875] {
            let y = render(note: 72, [0.125, w, 0.3, 1], mode: 1, frames: 4800 + 16384)
            let d2 = AnalogModTests.nonHarmonicDb(Array(y[4800..<(4800 + 16384)]), f0: 440 * pow(2, (72 - 69) / 12.0))
            print(String(format: "ANALOG SYNC +7.2 st wave %.3f aliasing: %.1f dB", w, d2))
            XCTAssertLessThan(d2, -55)
        }
    }

    /// Нагрузка: 8 голосов в каждом режиме, 1 с (отладочная сборка тестов, доля одного ядра).
    func testLoad8Voices() {
        for mode in 0...3 {
            let t0 = Date()
            for k in 0..<8 { _ = render(note: 48 + Double(k * 3), [0.625, 0.625, 0.6, 0.5], mode: mode, frames: 48000) }
            print(String(format: "ANALOG mode %d: 8 voices — %.1f%% of one core", mode, Date().timeIntervalSince(t0) * 100))
        }
    }

    /// Наибольшая составляющая 20 Гц–20 кГц не на гармониках f0 (±6 бинов) относительно самой сильной гармоники, dB.
    static func nonHarmonicDb(_ x: [Float], f0: Double) -> Double {
        let n = x.count
        var re = [Double](repeating: 0, count: n), im = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let a = 2 * Double.pi * Double(i) / Double(n)
            let w = 0.35875 - 0.48829 * cos(a) + 0.14128 * cos(2 * a) - 0.01168 * cos(3 * a)
            re[i] = Double(x[i]) * w
        }
        SynthKnobsTests.fft(&re, &im)
        let binHz = 48000.0 / Double(n)
        var top = 0.0, worst = 0.0
        for k in Int((20 / binHz).rounded(.up))..<Int(20000 / binHz) {
            let m = (re[k] * re[k] + im[k] * im[k]).squareRoot()
            let h = Double(k) * binHz / f0
            let near = abs(h - h.rounded()) * f0 / binHz <= 6 && h.rounded() >= 1
            if near { top = max(top, m) } else { worst = max(worst, m) }
        }
        return 20 * log10(max(worst, 1e-12) / max(top, 1e-12))
    }
}
