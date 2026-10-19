import XCTest
@testable import Core

/// S12, этап 4: SUB — моно-бас (OSC1 + OSC2 октавой ниже), проверка по свойствам.
final class SubEngineTests: XCTestCase {
    private static let tables = JamboTables()

    private func render(note: Double, _ k: [Double], frames: Int = 24000) -> [Float] {
        let v = JamboVoice(tables: SubEngineTests.tables, sampleRate: 48000)
        v.trigger(engine: Jambo.sub, note: note, k[0], k[1], k[2], k[3], decay: 500, now: 0, tau: 0)
        var out = [Float](repeating: 0, count: frames)
        out.withUnsafeMutableBufferPointer { b in
            var pos = 0
            while pos < frames {
                let n = min(24, frames - pos)
                v.render(b.baseAddress! + pos, n, driftRatio: 1)
                pos += n
            }
        }
        return out
    }

    func testTable() {
        let e = SynthEngines.engine(24)
        XCTAssertEqual(e?.name, "SUB")
        XCTAssertEqual(e?.decay, false)
        XCTAssertTrue(Jambo.mono(Jambo.sub))
        let g = Params.grid(sound: "mi:24")
        XCTAssertEqual(g[0].steps, 3)
        XCTAssertEqual(g[0].format(100.0 / 6), "Triangle")
        XCTAssertEqual(g[0].format(90), "Square")
        XCTAssertEqual([g[4].label, g[8].label, g[12].label], ["Sub", "Fat", "Grit"])
        var t = Track(index: 0)
        t.setSynth(24)
        XCTAssertEqual(t.params["timbre"], 40, "SUB при выборе — 40 %")
        XCTAssertEqual(t.params["morph"], 0)
        XCTAssertEqual(t.params["p4"], 0)
    }

    /// Ручки 0 / 50 / 100 %, ноты C0–C6: NaN нет, пик ≤ 0 dBFS.
    func testFiniteAndPeak() {
        var worst: Float = 0
        for note in [12.0, 36, 60, 84] {
            for w in [0.1, 0.5, 0.9] {
                for a in [0.0, 0.5, 1] {
                    let x = render(note: note, [w, a, 1 - a, a], frames: 12000)
                    XCTAssertFalse(x.contains { !$0.isFinite })
                    worst = max(worst, x.map(abs).max() ?? 0)
                }
            }
        }
        print(String(format: "SUB peak: %.1f dBFS", 20 * log10(worst)))
        XCTAssertLessThanOrEqual(worst, 1)
    }

    /// Key Reset: каждая нота звучит одинаково (фазы с нуля).
    func testKeyReset() {
        let a = render(note: 36, [0.5, 0.4, 0, 0], frames: 4800)
        let b = render(note: 36, [0.5, 0.4, 0, 0], frames: 4800)
        XCTAssertEqual(a, b)
        XCTAssertLessThan(abs(a[0]), 0.01, "вход ноты плавный")
    }

    /// Новая нота на звучащей SUB: фазы генераторов продолжаются (сброс давал щелчок), буфер децимации не сбрасывается —
    /// стык на уровне движка без скачка.
    func testPhaseGoesOn() {
        let v = JamboVoice(tables: SubEngineTests.tables, sampleRate: 48000)
        v.trigger(engine: Jambo.sub, note: 36, 0.5, 0.4, 0, 0, decay: 500, now: 0, tau: 0)
        var out = [Float](repeating: 0, count: 12000)
        out.withUnsafeMutableBufferPointer { b in
            var pos = 0
            while pos < 12000 {
                if pos == 6000 { v.trigger(engine: Jambo.sub, note: 43, 0.5, 0.4, 0, 0, decay: 500, now: 0, tau: 0) }
                let n = min(24, 12000 - pos)
                v.render(b.baseAddress! + pos, n, driftRatio: 1)
                pos += n
            }
        }
        var steady: Float = 0
        for i in 2000..<6000 { steady = max(steady, abs(out[i] - out[i - 1])) }
        for i in 9000..<12000 { steady = max(steady, abs(out[i] - out[i - 1])) }
        var seam: Float = 0
        for i in 6000..<6200 { seam = max(seam, abs(out[i] - out[i - 1])) }
        XCTAssertLessThanOrEqual(seam, steady * 1.2 + 1e-4)
    }

    /// SUB 100 % — только нижний осциллятор: основная частота — октавой ниже.
    func testSubOctave() {
        func hz(_ x: [Float]) -> Double {
            var first = -1.0, last = -1.0, count = 0
            for i in 4800..<(x.count - 1) where x[i] <= 0 && x[i + 1] > 0 {
                let t = Double(i) + Double(-x[i] / (x[i + 1] - x[i]))
                if first < 0 { first = t }
                last = t
                count += 1
            }
            return Double(count - 1) / ((last - first) / 48000)
        }
        // Треугольник A2 (110 Гц): OSC1 — 110, OSC2 — 55.
        XCTAssertEqual(hz(render(note: 45, [0.1, 0, 0, 0], frames: 48000)), 110, accuracy: 0.5)
        XCTAssertEqual(hz(render(note: 45, [0.1, 1, 0, 0], frames: 48000)), 55, accuracy: 0.5)
    }

    /// GRIT: 0 — прозрачно (пик как без насыщения), 100 % — больше гармоник при том же пике.
    func testGrit() {
        let clean = render(note: 45, [0.1, 0, 0, 0])
        let dirty = render(note: 45, [0.1, 0, 0, 1])
        func rms(_ x: [Float]) -> Float { (x[4800...].map { $0 * $0 }.reduce(0, +) / Float(x.count - 4800)).squareRoot() }
        XCTAssertGreaterThan(rms(dirty), rms(clean) * 1.2, "насыщение — плотнее")
        XCTAssertLessThanOrEqual(dirty.map(abs).max() ?? 2, 1)
    }

    /// Алиасинг: пила C6 (только OSC1) — посторонние составляющие ниже −60 dBc.
    func testAliasing() {
        let x = render(note: 84, [0.5, 0, 0, 0], frames: 4800 + 16384)
        let db = SynthKnobsTests.nonHarmonicDbc(Array(x[4800..<(4800 + 16384)]), f0: 440 * pow(2, 15 / 12.0))
        print(String(format: "SUB saw C6 aliasing: %.1f dBc", db))
        XCTAssertLessThan(db, -60)
    }

    /// Новая нота на звучащей (моно): без щелчка — в голосах синта огибающая с текущего уровня, в движке — хвост
    /// прошлой ноты за ~2 мс.
    func testLegatoWithoutClick() throws {
        let c = AudioCore(master: false)
        var p = Project()
        p.tracks[0].setSynth(24)
        p.tracks[0].vol = 0
        c.installSynth()
        c.publish(p)
        c.events.push(.noteOn(track: 0, note: 36, id: 1, velocity: 1))
        var l = [Float](repeating: 0, count: 256), r = l
        var y: [Float] = []
        for _ in 0..<40 {
            c.render(frames: 256, left: &l, right: &r)
            y += l
        }
        c.events.push(.noteOn(track: 0, note: 43, id: 2, velocity: 1))
        for _ in 0..<60 {
            c.render(frames: 256, left: &l, right: &r)
            y += l
        }
        // Крутизна самих нот: старой — до стыка, новой (выше на квинту) — после установления.
        var steady: Float = 0
        for i in 4000..<10240 { steady = max(steady, abs(y[i] - y[i - 1])) }
        for i in 16000..<25000 { steady = max(steady, abs(y[i] - y[i - 1])) }
        var seam: Float = 0
        for i in 10240..<10900 { seam = max(seam, abs(y[i] - y[i - 1])) }
        XCTAssertLessThanOrEqual(seam, steady * 1.5 + 1e-4)
        XCTAssertEqual(c.sampler.synth?.activeCount, 1, "моно: один голос")
    }

    /// Секвенсор ставит ноты заранее (на будущий кадр): монофоничный голос доигрывает прошлую ноту до кадра новой,
    /// а не молчит с вызова — иначе обрыв хвоста перед каждой нотой (щелчок, найден на iPad). Сцена с iPad: SUB,
    /// треугольник, Attack 0, Decay 500 мс, ноты через 3–4 шага при 126 BPM.
    func testNoGapBeforeSequencedNote() {
        let c = AudioCore(master: false)
        var p = Project()
        p.bpm = 126
        p.tracks[0].setSynth(24)
        p.tracks[0].vol = 0
        p.tracks[0].params["timbre"] = 36
        p.tracks[0].params["morph"] = 43
        p.tracks[0].params["attack"] = 0
        p.tracks[0].params["decay"] = 500
        for s in [4, 7, 10, 14] {
            p.tracks[0].pages[0][s].on = true
            p.tracks[0].pages[0][s].notes = [48]
        }
        c.installSynth()
        c.publish(p)
        c.events.push(.tempo(126))
        c.events.push(.play(true))
        var l = [Float](repeating: 0, count: 256), r = l
        var y: [Float] = []
        for _ in 0..<720 {
            c.render(frames: 256, left: &l, right: &r)
            y += l
        }
        // Верхние частоты — вторая разность: на стыках не больше, чем у атаки после тишины (первая нота).
        var hf = [Float](repeating: 0, count: y.count)
        for i in 2..<y.count { hf[i] = abs(y[i] - 2 * y[i - 1] + y[i - 2]) }
        let step = Int((48000 * 60 / 126.0 / 4).rounded())
        let first: Float = hf[(4 * step - 100)..<(4 * step + 400)].max() ?? 0
        for s in [7, 10, 14, 20, 23, 26, 30] {
            let w: Float = hf[(s * step - 500)..<(s * step + 400)].max() ?? 0
            XCTAssertLessThanOrEqual(w, first * 1.2, "шаг \(s): стык без обрыва")
        }
    }

    /// Нагрузка: 8 голосов, 1 с.
    func testLoad() {
        let t0 = Date()
        for k in 0..<8 { _ = render(note: 36 + Double(k), [0.5, 0.4, 0.5, 0.5], frames: 48000) }
        print(String(format: "SUB: 8 voices — %.1f%% of one core", Date().timeIntervalSince(t0) * 100))
    }
}
