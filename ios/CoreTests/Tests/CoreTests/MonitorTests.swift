import XCTest
@testable import Core

/// Headphone Monitor (фаза 1): приёмка по ТЗ — бит-в-бит без обработки, АЧХ коррекции, экспорт, маршруты
/// референса, частоты дискретизации, битые профили и пресеты.
final class MonitorTests: XCTestCase {
    static let block = 256

    private func sony() -> Eq {
        var e = Eq()
        e.apply(EqPresetBook.sonyXM4, tracks: 0)
        return e
    }

    private func presets() -> [TranslationPreset] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("JAMbo.swiftpm/Resources/TranslationPresets.json")
        return TranslationPreset.list(try? Data(contentsOf: url))
    }

    /// Прогон: blocks блоков сигнала f(t, канал) через цепочку; выход целиком.
    private func run(_ c: MonitorChain, blocks: Int, raw: Bool = false,
                     _ f: (Int, Int) -> Float) -> (l: [Float], r: [Float], inL: [Float], inR: [Float]) {
        let n = MonitorTests.block
        var outL: [Float] = [], outR: [Float] = [], inL: [Float] = [], inR: [Float] = []
        var l = [Float](repeating: 0, count: n), r = [Float](repeating: 0, count: n)
        var t = 0
        for _ in 0..<blocks {
            for i in 0..<n {
                l[i] = f(t + i, 0)
                r[i] = f(t + i, 1)
            }
            inL += l
            inR += r
            c.process(&l, &r, n, raw: raw)
            outL += l
            outR += r
            t += n
        }
        return (outL, outR, inL, inR)
    }

    /// Усиление на частоте hz (dB): синус в обоих каналах, амплитуда по корреляции на последних 0,5 с.
    private func gain(_ c: MonitorChain, hz: Double, sr: Double, amp: Double = 0.1, right: Bool = false) -> Double {
        let blocks: Int = Int(sr * 1.5) / MonitorTests.block
        let o = run(c, blocks: blocks) { t, _ in Float(amp * sin(2 * Double.pi * hz * Double(t) / sr)) }
        let y: [Float] = right ? o.r : o.l
        let n: Int = Int(sr * 0.5)
        var s: Double = 0, k: Double = 0
        for i in (y.count - n)..<y.count {
            let w: Double = 2 * Double.pi * hz * Double(i) / sr
            s += Double(y[i]) * sin(w)
            k += Double(y[i]) * cos(w)
        }
        let a: Double = 2 * (s * s + k * k).squareRoot() / Double(n)
        return 20 * log10(a / amp)
    }

    private func noise(_ seed: UInt64) -> (Int, Int) -> Float {
        return { t, ch in
            var x: UInt64 = seed &+ UInt64(t * 2 + ch) &* 0x9E3779B97F4A7C15
            x ^= x >> 31
            x = x &* 0xBF58476D1CE4E5B9
            x ^= x >> 29
            return Float(Double(x % 100000) / 100000 - 0.5) * 0.8
        }
    }

    private func chain(_ eq: Eq?, _ m: MonitorSettings, correct: Eq? = nil, preset: TranslationPreset? = nil,
                       sr: Double = 48000) -> (MonitorChain, [Double]) {
        let c = MonitorChain(sampleRate: sr)
        let p: [Double] = MonitorDesign.make(eq: eq, settings: m, correct: correct, preset: preset, sampleRate: sr)
        c.publish(p)
        return (c, p)
    }

    /// Strength 0 — выход бит в бит равен входу; Bypass после перехода — тоже.
    func testNeutralAndBypassBitExact() {
        var m = MonitorSettings()
        m.strength = 0
        let (c, p) = chain(sony(), m)
        XCTAssertEqual(p[MonitorSpec.compAt], 1)
        let o = run(c, blocks: 50, noise(1))
        XCTAssertEqual(o.l, o.inL)
        XCTAssertEqual(o.r, o.inR)
        // Bypass при полной обработке: после кроссфейда — вход.
        var full = MonitorSettings()
        full.translation = "Phone"
        full.sub = true
        var off: Eq = sony()
        off.on = false
        let (b, _) = chain(sony(), full, correct: MonitorTests.curve([100, 400, 1500, 8000], [2, -2, 1, 3]), preset: presets().first { $0.name == "Phone" })
        _ = run(b, blocks: 20, noise(2))
        b.publish(MonitorDesign.make(eq: off, settings: full, correct: MonitorTests.curve([100, 400, 1500, 8000], [2, -2, 1, 3]),
                                     preset: presets().first { $0.name == "Phone" }, sampleRate: 48000))
        _ = run(b, blocks: 10, noise(3))
        let o2 = run(b, blocks: 20, noise(4))
        XCTAssertEqual(o2.l, o2.inL)
        XCTAssertEqual(o2.r, o2.inR)
    }

    /// Strength 100 %: измеренная АЧХ совпадает с расчётной по профилю (с компенсацией) в пределах 0,1 dB.
    func testCorrectionResponse() {
        var m = MonitorSettings()
        let e: Eq = sony()
        let (c, p) = chain(e, m)
        let comp: Double = 20 * log10(p[MonitorSpec.compAt])
        XCTAssertNotEqual(comp, 0)
        for hz in [40.0, 105, 143, 1000, 2289, 5144, 6715, 12000] {
            var want: Double = comp
            for case let b? in e.bands { want += EqCoeffs.response(b, hz: hz) }
            XCTAssertEqual(gain(c, hz: hz, sr: 48000), want, accuracy: 0.1, "\(hz) Hz")
        }
        // Половина Strength — усиления фильтров вдвое меньше (в dB).
        m.strength = 0.5
        let p2: [Double] = MonitorDesign.make(eq: e, settings: m, correct: nil, preset: nil, sampleRate: 48000)
        var half = e
        for k in 0..<half.bands.count { half.bands[k]?.gain *= 0.5 }
        var want: Double = 0
        for case let b? in half.bands { want += EqCoeffs.response(b, hz: 2289) }
        XCTAssertEqual(MonitorDesign.response(p2, hz: 2289, sampleRate: 48000), want, accuracy: 1e-6)
    }

    /// Усиление одного фильтра — не больше ±12 dB.
    func testFilterClamp() {
        var e = Eq()
        e.bands[0] = EqBand(type: EqSpec.bell, freq: 1000, gain: 18, q: 1)
        var m = MonitorSettings()
        let p: [Double] = MonitorDesign.make(eq: e, settings: m, correct: nil, preset: nil, sampleRate: 48000)
        XCTAssertEqual(MonitorDesign.response(p, hz: 1000, sampleRate: 48000), 12, accuracy: 1e-6)
    }

    /// Translation: пресеты из JSON; Phone — моно, срез низа, компенсация вверх (≤ 12 dB); Sub-check — соло НЧ.
    func testTranslationAndSub() {
        let list: [TranslationPreset] = presets()
        XCTAssertEqual(list.map { $0.name }, ["Off", "Studio", "Home Hi-Fi", "Car", "Club", "Small Speakers", "Phone", "Earbuds"])
        // Пространство пунктов — комнаты rooms.json; у Off, Phone и Earbuds — нет.
        XCTAssertEqual(list.map { $0.room ?? "-" }, ["-", "Studio", "Home", "Car", "Club", "Desk", "-", "-"])
        guard let phone = list.first(where: { $0.name == "Phone" }) else { return XCTFail() }
        var m = MonitorSettings()
        let p: [Double] = MonitorDesign.make(eq: nil, settings: m, correct: nil, preset: phone, sampleRate: 48000)
        XCTAssertEqual(p[MonitorSpec.monoAt], 1)
        XCTAssertLessThan(MonitorDesign.response(p, hz: 60, sampleRate: 48000), -20)
        let comp: Double = 20 * log10(p[MonitorSpec.compAt])
        XCTAssertGreaterThan(comp, 0)
        XCTAssertLessThanOrEqual(comp, 12)
        // Small Speakers: HPF 4-го порядка — 24 dB/окт ниже среза (на 110 Гц — −3 dB и подъём 2,5 кГц не мешает).
        guard let small = list.first(where: { $0.name == "Small Speakers" }) else { return XCTFail() }
        let ps: [Double] = MonitorDesign.make(eq: nil, settings: m, correct: nil, preset: small, sampleRate: 48000)
        XCTAssertEqual(MonitorDesign.response(ps, hz: 110, sampleRate: 48000), -3.01, accuracy: 0.1)
        XCTAssertEqual(MonitorDesign.response(ps, hz: 55, sampleRate: 48000), -24.1, accuracy: 0.5)
        // Sub-check: 120 Гц — −3 dB, 1 кГц — глубоко вниз.
        m.sub = true
        let pb: [Double] = MonitorDesign.make(eq: nil, settings: m, correct: nil, preset: nil, sampleRate: 48000)
        XCTAssertEqual(MonitorDesign.response(pb, hz: 120, sampleRate: 48000), -3.01, accuracy: 0.05)
        XCTAssertLessThan(MonitorDesign.response(pb, hz: 1000, sampleRate: 48000), -70)
        // Mono: левый канал — в оба поровну.
        var mm = MonitorSettings()
        mm.mono = true
        let (c, _) = chain(nil, mm)
        let o = run(c, blocks: 40) { _, ch in ch == 0 ? 0.5 : 0 }
        XCTAssertEqual(o.l.last ?? 0, o.r.last ?? 1, accuracy: 1e-6)
    }

    /// Настройки — словарём UserDefaults: туда и обратно, неверные значения — в пределы.
    func testSettingsPlist() {
        var m = MonitorSettings()
        m.strength = 0.4
        m.translation = "Car"
        m.mono = true
        m.editCorrect = true
        m.refMonitor = false
        m.refTrim = -3.5
        let back = MonitorSettings(plist: m.plist)
        XCTAssertEqual(back.strength, 0.4)
        XCTAssertEqual(back.translation, "Car")
        XCTAssertTrue(back.mono)
        XCTAssertTrue(back.editCorrect)
        XCTAssertFalse(back.refMonitor)
        XCTAssertEqual(back.refTrim, -3.5)
        let bad = MonitorSettings(plist: ["ambienceDb": 500, "refTrim": -40, "mono": "x"])
        XCTAssertEqual(bad.ambienceDb, 0)
        XCTAssertEqual(bad.translation, "Studio")
        XCTAssertEqual(bad.refTrim, -12)
        XCTAssertFalse(bad.mono)
        XCTAssertEqual(MonitorSettings(plist: nil).strength, 1)
    }

    /// CORRECT CURVE: полосы сверх 10 тоже звучат, усиление — полностью (без CORRECTION).
    func testCorrectCurve() {
        var m = MonitorSettings()
        m.strength = 0
        let hz: [Double] = (0..<14).map { 50 * pow(1.6, Double($0)) }
        let c: Eq = MonitorTests.curve(hz, hz.map { _ in 1.0 })
        XCTAssertEqual(c.bands.count, 14)
        let p: [Double] = MonitorDesign.make(eq: sony(), settings: m, correct: c, preset: nil, sampleRate: 48000)
        var want: Double = 0
        for case let b? in c.bands { want += EqCoeffs.response(b, hz: 1000) }
        XCTAssertEqual(MonitorDesign.response(p, hz: 1000, sampleRate: 48000), want, accuracy: 1e-6)
        XCTAssertGreaterThan(want, 1.5)
    }

    /// Кривая из bell-полос (Q 1); больше 10 — массив растёт.
    static func curve(_ hz: [Double], _ g: [Double]) -> Eq {
        var e = Eq()
        e.bands = hz.indices.map { EqBand(type: EqSpec.bell, freq: hz[$0], gain: g[$0], q: 1) }
        return e
    }

    /// Лимитер: громкий вход — выход не выше −0,5 dBFS (цепочка с коррекцией; нейтральная уходит из сигнала).
    func testLimiter() {
        var m = MonitorSettings()
        let (c, _) = chain(sony(), m)
        let o = run(c, blocks: 40) { t, _ in Float(2 * sin(2 * Double.pi * 200 * Double(t) / 48000)) }
        // После перехода (25 мс) — не выше потолка.
        let peak: Float = (o.l.suffix(4800) + o.r.suffix(4800)).map { abs($0) }.max() ?? 0
        XCTAssertLessThanOrEqual(Double(peak), pow(10, -0.5 / 20) + 1e-6)
        XCTAssertGreaterThan(Double(peak), pow(10, -0.5 / 20) - 0.01)
        XCTAssertLessThan(c.limitGain.load(), 1)
    }

    /// Громкий бас (9.11, треск на бочке и басе): ровный синус 50 Гц выше потолка — усиление ровное, выход —
    /// неискажённый синус (остаток после подгонки синуса ≤ −60 dB).
    func testLimiterBassClean() {
        let m = MonitorSettings()
        let (c, _) = chain(sony(), m)
        let sr: Double = 48000
        let o = run(c, blocks: 600) { t, _ in Float(1.6 * sin(2 * Double.pi * 50 * Double(t) / sr)) }
        let y: [Float] = Array(o.l.suffix(48000))
        let t0: Int = o.l.count - 48000
        var ss: Double = 0, cc: Double = 0
        for (i, v) in y.enumerated() {
            let w: Double = 2 * Double.pi * 50 * Double(t0 + i) / sr
            ss += Double(v) * sin(w)
            cc += Double(v) * cos(w)
        }
        let a: Double = 2 * ss / Double(y.count), b: Double = 2 * cc / Double(y.count)
        var err: Double = 0, sig: Double = 0
        for (i, v) in y.enumerated() {
            let w: Double = 2 * Double.pi * 50 * Double(t0 + i) / sr
            let fit: Double = a * sin(w) + b * cos(w)
            err += pow(Double(v) - fit, 2)
            sig += fit * fit
        }
        let db: Double = 10 * log10(err / sig)
        print(String(format: "limiter, 50 Hz above ceiling: distortion %.1f dB", db))
        XCTAssertLessThan(db, -60)
        let peak: Float = y.map { abs($0) }.max() ?? 0
        XCTAssertLessThanOrEqual(Double(peak), pow(10, -0.5 / 20) + 1e-6)
    }

    /// 44,1 и 96 кГц: коэффициенты по частоте, АЧХ — как расчётная.
    func testSampleRates() {
        var m = MonitorSettings()
        for sr in [44100.0, 96000.0] {
            let (c, p) = chain(sony(), m, sr: sr)
            let comp: Double = 20 * log10(p[MonitorSpec.compAt])
            for hz in [143.0, 2289, 6715] {
                let want: Double = MonitorDesign.response(p, hz: hz, sampleRate: sr) + comp
                XCTAssertEqual(gain(c, hz: hz, sr: sr), want, accuracy: 0.1, "\(sr) \(hz)")
            }
        }
    }

    /// Пустой и битый профиль, битый JSON — без падений; парсер: PK/LSC/HSC/LS/HS, OFF, пробелы и регистр.
    func testBrokenAndParser() {
        XCTAssertEqual(PhonesProfile.parse("garbage\n\u{0}\nFilter: ON").count, 0)
        XCTAssertEqual(TranslationPreset.list(Data("{bad".utf8)).count, 0)
        XCTAssertEqual(TranslationPreset.list(nil).count, 0)
        let empty: [Double] = MonitorDesign.make(eq: Eq(), settings: MonitorSettings(), correct: nil, preset: nil,
                                                 sampleRate: 48000)
        XCTAssertEqual(empty.count, MonitorSpec.size)
        let text = """
        Preamp: -6.1 dB
          filter 1:  on  pk  fc 100 hz  gain -2.5 db  q 1.41
        Filter 2: OFF PK Fc 200 Hz Gain 3 dB Q 1
        Filter 3: ON LSC Fc 105 Hz Gain 4.0 dB Q 0.70
        Filter 4: ON HSC Fc 10000 Hz Gain -1.0 dB Q 0.70
        Filter\t5: ON LS Fc 80 Hz Gain 1 dB
        Filter 6: ON HS Fc 9000 Hz Gain 2 dB
        """
        let f = PhonesProfile.parse(text)
        XCTAssertEqual(f.map { $0.type }, [EqSpec.bell, EqSpec.lowShelf, EqSpec.highShelf, EqSpec.lowShelf, EqSpec.highShelf])
        XCTAssertEqual(f[0].gain, -2.5)
        XCTAssertEqual(f[0].q, 1.41)
        XCTAssertEqual(f[0].freq, 100)
        // Смена профиля и частоты на ходу — без NaN.
        let c = MonitorChain(sampleRate: 48000)
        c.publish(MonitorDesign.make(eq: sony(), settings: MonitorSettings(), correct: nil, preset: nil, sampleRate: 48000))
        _ = run(c, blocks: 5, noise(6))
        c.publish(MonitorDesign.make(eq: Eq(), settings: MonitorSettings(), correct: nil, preset: nil, sampleRate: 48000))
        c.publish([1, 2, 3])
        let o = run(c, blocks: 5, noise(7))
        XCTAssertFalse(o.l.contains { !$0.isFinite })
    }

    /// Смена параметров на ходу — без щелчков: скачок между отсчётами не больше, чем у самого синуса (с запасом).
    func testSmoothChanges() {
        let hz: Double = 1500
        let f: (Int, Int) -> Float = { t, _ in Float(0.3 * sin(2 * Double.pi * hz * Double(t) / 48000)) }
        let maxStep: Double = 0.3 * 2 * Double.pi * hz / 48000
        let c = MonitorChain(sampleRate: 48000)
        var m = MonitorSettings()
        var out: [Float] = []
        var t0 = 0
        let steps: [(inout MonitorSettings, inout Eq) -> Void] = [
            { _, _ in }, { m, _ in m.mono = true },
            { m, _ in m.strength = 0 }, { m, _ in m.strength = 1 }, { _, e in e.on = false }, { _, e in e.on = true },
        ]
        var e: Eq = sony()
        for s in steps {
            s(&m, &e)
            c.publish(MonitorDesign.make(eq: e, settings: m, correct: nil, preset: nil, sampleRate: 48000))
            let o = run(c, blocks: 20) { t, ch in f(t + t0, ch) }
            out += o.l
            t0 += 20 * MonitorTests.block
        }
        var worst: Double = 0
        for i in 1..<out.count { worst = max(worst, Double(abs(out[i] - out[i - 1]))) }
        XCTAssertLessThan(worst, maxStep * 2.2)
    }

    /// Экспорт: при включённой цепочке (пауза на экспорт) выход колбэка бит в бит равен выходу без неё — сверка
    /// съёмов до и после цепочки в одном AudioCore (два экземпляра не сравнить: у FX случайный seed).
    func testExportBitExact() {
        func render(paused: Bool) -> (pre: [Float], post: [Float]) {
            let core = AudioCore(master: true)
            var p = Project()
            p.tracks[0].addSamples(["s"])
            let s = SampleData(left: (0..<48000).map { Float(0.5 * sin(2 * Double.pi * 220 * Double($0) / 48000)) }, right: nil)
            core.publish(p, samples: ["s": s])
            var m = MonitorSettings()
            m.translation = "Car"
            core.monitor.publish(MonitorDesign.make(eq: self.sony(), settings: m, correct: MonitorTests.curve([100, 8000], [3, -3]),
                                                    preset: self.presets().first { $0.name == "Car" }, sampleRate: 48000))
            core.monitor.paused.store(paused ? 1 : 0)
            core.spectra.channel.store(EqSpec.phonesChannel)
            var bl = [Float](repeating: 0, count: 256), br = [Float](repeating: 0, count: 256)
            for _ in 0..<4 { core.render(frames: 256, left: &bl, right: &br) }
            core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
            for _ in 0..<60 { core.render(frames: 256, left: &bl, right: &br) }
            let n = SpectrumTap.capacity
            return (Array(UnsafeBufferPointer(start: core.spectra.pre.buf, count: n)),
                    Array(UnsafeBufferPointer(start: core.spectra.post.buf, count: n)))
        }
        let exported = render(paused: true)
        XCTAssertGreaterThan(exported.pre.map { abs($0) }.max() ?? 0, 0.01)
        XCTAssertEqual(exported.post, exported.pre)
        let monitored = render(paused: false)
        XCTAssertNotEqual(monitored.post, monitored.pre)
    }

    /// Маршруты референса (4 сочетания): референс проходит ровно через выбранные блоки; переход — без щелчков.
    func testRefRoutingMatrix() {
        let n = MonitorTests.block
        let hz: Double = 1500
        var m = MonitorSettings()
        let mon: [Double] = MonitorDesign.make(eq: nil, settings: m, correct: MonitorTests.curve([1500], [3]), preset: nil, sampleRate: 48000)
        let monDb: Double = MonitorDesign.response(mon, hz: hz, sampleRate: 48000) + 20 * log10(mon[MonitorSpec.compAt])
        XCTAssertGreaterThan(abs(monDb), 0.5)
        let masterGain: Float = 0.5
        func level(_ thruMaster: Bool, _ thruMonitor: Bool, switchAt: Int? = nil) -> (db: Double, jump: Double) {
            let ref = RefPlayer()
            let chain = MonitorChain(sampleRate: 48000)
            chain.publish(mon)
            let levels = Levels()
            ref.throughMaster.store(thruMaster ? 1 : 0)
            ref.throughMonitor.store(thruMonitor ? 1 : 0)
            var l = [Float](repeating: 0, count: n), r = [Float](repeating: 0, count: n)
            var out: [Float] = []
            for b in 0..<200 {
                if b == switchAt {
                    ref.throughMaster.store(thruMaster ? 0 : 1)
                    ref.throughMonitor.store(thruMonitor ? 0 : 1)
                }
                for i in 0..<n {
                    let v = Float(0.2 * sin(2 * Double.pi * hz * Double(b * n + i) / 48000))
                    ref.outL[i] = v
                    ref.outR[i] = v
                    // Микс — тишина (в B не слышен).
                    l[i] = 0
                    r[i] = 0
                }
                ref.mixPre(refB: true, &l, &r, n: n, levels: levels)
                for i in 0..<n {
                    l[i] *= masterGain
                    r[i] *= masterGain
                }
                ref.mixPost(&l, &r, n: n)
                let raw: Bool = ref.throughMonitor.load() == 0
                chain.process(&l, &r, n, raw: raw)
                out += l
            }
            let tail: [Float] = Array(out.suffix(9600))
            let peak: Double = Double(tail.map { abs($0) }.max() ?? 0)
            var jump: Double = 0
            for i in 1..<out.count { jump = max(jump, Double(abs(out[i] - out[i - 1]))) }
            return (20 * log10(peak / 0.2), jump)
        }
        let master: Double = 20 * log10(Double(masterGain))
        for thruMaster in [false, true] {
            for thruMonitor in [false, true] {
                let want: Double = (thruMaster ? master : 0) + (thruMonitor ? monDb : 0)
                XCTAssertEqual(level(thruMaster, thruMonitor).db, want, accuracy: 0.05, "\(thruMaster) \(thruMonitor)")
                // Переключение на ходу: скачок не больше синуса с запасом.
                let maxStep: Double = 0.2 * 2 * Double.pi * hz / 48000 * 1.5
                XCTAssertLessThan(level(thruMaster, thruMonitor, switchAt: 100).jump, maxStep * 1.6)
            }
        }
    }

    /// Short-term громкость микса и интегральная файла (подгонка референса): синус 1 кГц −20 dBFS ≈ −20 LUFS.
    func testLoudness() {
        let n = 48000 * 6
        let s: [Float] = (0..<n).map { Float(0.1 * sin(2 * Double.pi * 1000 * Double($0) / 48000)) }
        let lufs: Double = s.withUnsafeBufferPointer { b in
            Loudness.integrated(left: b.baseAddress!, right: b.baseAddress!, frames: n)
        }
        // Синус 0,1 в обоих каналах: средний квадрат 0,005 на канал, сумма каналов 0,01 (−20 dB), −0,691 и K-фильтр
        // на 1 кГц (около +0,4).
        XCTAssertEqual(lufs, -20.3, accuracy: 0.3)
        let m = Loudness(sampleRate: 48000)
        m.source.store(0)
        _ = m.listens(0)
        s.withUnsafeBufferPointer { b in
            var at = 0
            while at < n {
                m.process(b.baseAddress! + at, b.baseAddress! + at, 256)
                m.end(256)
                at += 256
            }
        }
        XCTAssertEqual(Double(m.shortTerm.load()), lufs, accuracy: 0.3)
    }
}

/// Нагрузка фазы 1 (отладочная сборка): полная цепочка — профиль 10 полос, Translation, CORRECT CURVE, Mono.
final class MonitorLoadTests: XCTestCase {
    func testLoad() {
        var e = Eq()
        e.apply(EqPresetBook.sonyXM4, tracks: 0)
        var m = MonitorSettings()
        m.mono = true
        let car = TranslationPreset(name: "Car", mono: nil, filters: [
            .init(type: "LS", freq: 100, gain: 4, q: nil, order: nil),
            .init(type: "PK", freq: 250, gain: -2, q: 1, order: nil),
            .init(type: "LP", freq: 16000, gain: nil, q: nil, order: nil),
        ])
        let c = MonitorChain(sampleRate: 48000)
        c.publish(MonitorDesign.make(eq: e, settings: m, correct: MonitorTests.curve([100, 400, 1500, 4000, 8000], [1, -1, 1, -1, 1]), preset: car, sampleRate: 48000))
        var l = [Float](repeating: 0.1, count: 256), r = [Float](repeating: -0.1, count: 256)
        for _ in 0..<50 { c.process(&l, &r, 256, raw: false) }
        let blocks = 2000
        let t0 = Date()
        for _ in 0..<blocks { c.process(&l, &r, 256, raw: false) }
        let per: Double = Date().timeIntervalSince(t0) / Double(blocks)
        let share: Double = per / (256.0 / 48000) * 100
        print(String(format: "monitor chain: %.1f µs на блок 256 (%.2f %% времени блока)", per * 1e6, share))
    }
}
