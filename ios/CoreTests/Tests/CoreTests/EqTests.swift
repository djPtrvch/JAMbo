import XCTest
@testable import Core

/// EQ по эталонам eq_* (EqChain веба в Chromium; EqSelfTest) и правки EQ.
final class EqTests: XCTestCase {
    func testGolden() throws {
        let cases = try EqSelfTest.loadCases(GoldenPaths.goldenDir)
        XCTAssertEqual(cases.count, 22)
        for c in cases {
            let r = try EqSelfTest.run(c, GoldenPaths.goldenDir)
            print(String(format: "%@: samples %.1f dB, bands ±%.3f dB, rms %.1f dBFS",
                         c.file, r.sampleErrorDb, r.maxBandDiffDb, r.rmsDb))
            XCTAssertTrue(r.ok, "\(c.file): samples \(r.sampleErrorDb) dB, bands \(r.maxBandDiffDb) dB")
        }
    }
}

extension EqTests {
    /// Нагрузка (отладочная сборка, доля одного ядра): 1 с шума блоками по 256 — 8 bell без изменений и 8 bell,
    /// которые тянут каждый блок (сглаживание всё время); low cut 48 (4 ступени).
    func testLoad() {
        let n = 256, blocks = 48000 / 256
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n), r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let p = UnsafeMutablePointer<Double>.allocate(capacity: EqSpec.stride)
        defer { l.deallocate(); r.deallocate(); p.deallocate() }
        var rnd = FxRandom(3)
        func time(_ name: String, _ eqAt: (Int) -> Eq) {
            let u = EqUnit(sampleRate: 48000)
            let t0 = Date()
            for b in 0..<blocks {
                for i in 0..<n {
                    l[i] = Float(rnd.next() - 0.5)
                    r[i] = Float(rnd.next() - 0.5)
                }
                EqSpec.fill(p, eqAt(b))
                u.process(left: l, right: r, frames: n, params: p)
            }
            print(String(format: "load %@: %.1f %%", name, Date().timeIntervalSince(t0) * 100))
        }
        func bells(_ f: Double) -> Eq {
            var e = Eq()
            for k in 0..<8 { e.bands[k] = EqBand(type: EqSpec.bell, freq: f * Double(k + 1), gain: 3, q: 1) }
            return e
        }
        time("8 bells") { _ in bells(100) }
        time("8 bells moving") { b in bells(100 + Double(b % 50)) }
        func msBells(_ f: Double) -> Eq {
            var e = bells(f)
            for k in 0..<8 { e.bands[k]?.ms = 1 + k % 2 }
            return e
        }
        time("8 bells M/S") { _ in msBells(100) }
        time("8 bells M/S moving") { b in msBells(100 + Double(b % 50)) }
        time("low cut 48") { _ in
            var e = Eq()
            e.bands[0] = EqBand(type: EqSpec.lowCut, freq: 80, gain: 0, q: 1, slope: 2)
            return e
        }
    }
}

/// Правки EQ (как state.ts веба), EQ в звуке: дорожка (сухой сигнал и посылы), мастер, хвост фильтров.
final class EqRoutingTests: XCTestCase {
    func testEdits() {
        var p = Project()
        let m = EqSpec.masterChannel
        XCTAssertEqual(p.addEqBand(0, freq: 5, gain: 30), 0)
        XCTAssertEqual(p.tracks[0].eq.bands[0], EqBand(type: EqSpec.bell, freq: 20, gain: 18, q: 1))
        for k in 1..<EqSpec.bands { XCTAssertEqual(p.addEqBand(0, freq: 1000, gain: 0), k) }
        XCTAssertEqual(p.addEqBand(0, freq: 1000, gain: 0), -1, "мест нет")
        p.setEqBand(0, 0, freq: 30000, gain: -3.14159, q: 50)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.freq, 20000)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.gain, -3.1)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.q, 18)
        p.setEqType(0, 0, -1)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.type, EqSpec.notch)
        p.setEqSlope(0, 0, 5)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.slope, 2)
        p.setEqMs(0, 0, 1)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.ms, 1)
        p.setEqMs(0, 0, 7)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.ms, 2)
        p.toggleEqBand(0, 0)
        XCTAssertEqual(p.tracks[0].eq.bands[0]?.on, false)
        p.deleteEqBand(0, 3)
        XCTAssertNil(p.tracks[0].eq.bands[3])
        XCTAssertEqual(p.addEqBand(0, freq: 100, gain: 0), 3, "первое свободное место")
        p.toggleEq(0)
        XCTAssertFalse(p.tracks[0].eq.on)
        XCTAssertEqual(p.addEqBand(m, freq: 100, gain: 6), 0)
        XCTAssertEqual(p.masterEq.bands[0]?.gain, 6)
        XCTAssertNil(p.tracks[1].eq.bands[0], "EQ дорожек свои")
        // EQ переезжает и копируется вместе с дорожкой.
        p.moveTrack(0, 2)
        XCTAssertEqual(p.tracks[2].eq.bands[1]?.freq, 1000)
    }

    /// Снимок: выключенная полоса и BYPASS — «нет полосы»; у cut и notch усиление 0, Q среза — в dB.
    func testFill() {
        var e = Eq()
        e.bands[0] = EqBand(type: EqSpec.lowCut, freq: 100, gain: 6, q: 2, slope: 2)
        e.bands[1] = EqBand(on: false, type: EqSpec.bell, freq: 100, gain: 6, q: 2)
        e.bands[2] = EqBand(type: EqSpec.bell, freq: 100, gain: 6, q: 2, ms: 2)
        let p = UnsafeMutablePointer<Double>.allocate(capacity: EqSpec.stride)
        defer { p.deallocate() }
        EqSpec.fill(p, e)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: p, count: 10)), [1, Double(EqSpec.lowCut), 4, 100, 0, 20 * log10(2.0), 0, -1, -24, -6])
        XCTAssertEqual(p[1 + EqSpec.bandStride], -1)
        XCTAssertEqual(p[1 + 2 * EqSpec.bandStride + 5], 2, "режим SIDE")
        e.on = false
        EqSpec.fill(p, e)
        XCTAssertEqual(p[1], -1)
    }

    /// АЧХ для кривой: bell +6 dB на своей частоте, notch — провал, high shelf −8 dB у 20 кГц, low cut 48 — 4 ступени.
    func testResponse() {
        XCTAssertEqual(EqCoeffs.response(EqBand(type: EqSpec.bell, freq: 1000, gain: 6, q: 1), hz: 1000), 6, accuracy: 1e-9)
        XCTAssertLessThan(EqCoeffs.response(EqBand(type: EqSpec.notch, freq: 1000, gain: 0, q: 4), hz: 1000), -100)
        XCTAssertEqual(EqCoeffs.response(EqBand(type: EqSpec.highShelf, freq: 6000, gain: -8, q: 1), hz: 20000), -8, accuracy: 0.3)
        let one = EqCoeffs.response(EqBand(type: EqSpec.lowCut, freq: 1000, gain: 0, q: 1, slope: 0), hz: 200)
        let four = EqCoeffs.response(EqBand(type: EqSpec.lowCut, freq: 1000, gain: 0, q: 1, slope: 2), hz: 200)
        XCTAssertEqual(four, 4 * one, accuracy: 1e-9)
    }

    private func render(_ core: AudioCore, frames: Int) -> [Float] {
        var out: [Float] = []
        var bl = [Float](repeating: 0, count: 256), br = [Float](repeating: 0, count: 256)
        while out.count < frames {
            core.render(frames: 256, left: &bl, right: &br)
            out += bl
        }
        return out
    }

    private func rms(_ x: ArraySlice<Float>) -> Double {
        return sqrt(x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(1, x.count)))
    }

    /// Синус 100 Гц на дорожке 0 (1 с) с EQ edit; master — через мастер (EQ мастера).
    private func run(master: Bool = false, sends: [String: Double] = [:], frames: Int = 36000,
                     _ edit: (inout Project) -> Void) -> [Float] {
        let core = AudioCore(master: master)
        var p = Project()
        p.tracks[0].addSamples(["s"])
        p.tracks[0].vol = 0
        for (id, v) in sends { p.tracks[0].params[id] = v }
        edit(&p)
        let s = SampleData(left: (0..<48000).map { Float(0.5 * sin(2 * Double.pi * 100 * Double($0) / 48000)) }, right: nil)
        core.publish(p, samples: ["s": s])
        // Кроссфейд введения полос (40 мс, как в вебе) — до ноты.
        _ = render(core, frames: 4096)
        core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        return render(core, frames: frames)
    }

    private func lowCut(_ e: inout Eq) {
        e.bands[0] = EqBand(type: EqSpec.lowCut, freq: 4000, gain: 0, q: 0.7, slope: 2)
    }

    /// EQ дорожки — на сухом сигнале и на посыле (в вебе — копия EQ на каждом посыле).
    func testTrackEqOnDryAndSends() {
        let dry = rms(run { _ in }[12000..<24000])
        let cut = rms(run { self.lowCut(&$0.tracks[0].eq) }[12000..<24000])
        XCTAssertGreaterThan(dry, 0.1)
        XCTAssertLessThan(20 * log10(cut / dry), -80)
        // Delay 100 % (повторы через 0,25 с поверх ноты; окно — между повторами щелчка начала ноты, он проходит
        // low cut): посыл тоже без 100 Гц.
        let echo = rms(run(sends: ["delay": 100]) { _ in }[13000..<23000])
        let echoCut = rms(run(sends: ["delay": 100]) { self.lowCut(&$0.tracks[0].eq) }[13000..<23000])
        XCTAssertGreaterThan(echo, dry * 1.2, "повторы слышны")
        XCTAssertLessThan(20 * log10(echoCut / echo), -80)
        // BYPASS — как без EQ.
        let byp = run { self.lowCut(&$0.tracks[0].eq); $0.tracks[0].eq.on = false }
        let ref = run { _ in }
        XCTAssertEqual(rms(byp[12000..<24000]), rms(ref[12000..<24000]), accuracy: 1e-6)
    }

    /// EQ мастера — перед SAT (весь сигнал дорожек).
    func testMasterEq() {
        let dry = rms(run(master: true) { _ in }[12000..<24000])
        let cut = rms(run(master: true) { self.lowCut(&$0.masterEq) }[12000..<24000])
        XCTAssertGreaterThan(dry, 0.1)
        XCTAssertLessThan(20 * log10(cut / dry), -80)
    }

    /// Хвост фильтров звучит и после того, как голос дорожки кончился; затихнув, EQ больше не считается.
    func testRingingTail() {
        let core = AudioCore(master: false)
        var p = Project()
        p.tracks[0].addSamples(["k"])
        p.tracks[0].vol = 0
        p.tracks[0].params["decay"] = 0
        p.tracks[0].eq.bands[0] = EqBand(type: EqSpec.bell, freq: 200, gain: 18, q: 18)
        let s = SampleData(left: (0..<480).map { Float(sin(2 * Double.pi * 200 * Double($0) / 48000)) }, right: nil)
        core.publish(p, samples: ["k": s])
        // Кроссфейд введения полосы (40 мс) прошёл.
        _ = render(core, frames: 4096)
        core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        // Bell +18 dB, Q 18: спад ~6 dB за 53 мс, до порога −180 dB — около 1,6 с.
        let o = render(core, frames: 144000)
        let last = o.lastIndex { abs($0) > 1e-12 } ?? 0
        XCTAssertGreaterThan(rms(o[9600..<14400]), 1e-3, "звон через 0,2 с после короткого сэмпла (голос уже кончился)")
        XCTAssertFalse(core.trackEqs.ringing(0), "хвост затих")
        XCTAssertGreaterThan(last, 48000)
        XCTAssertLessThan(last, 120000, "затихло")
    }
}

extension EqTests {
    /// SELF-TEST: код EQ не занят движками, FX и мастером.
    func testSelfTestName() {
        let code = EqSelfTest.code
        XCTAssertNotNil(EqSelfTest.engineNames[code])
        XCTAssertNil(MasterSelfTest.engineNames[code])
        XCTAssertNil(FxSelfTest.engineNames[code])
        XCTAssertNil(JamboSelfTest.engineNames[code])
        XCTAssertGreaterThanOrEqual(code, SynthEngines.count)
    }
}

/// Спектры EQ: БПФ против прямого ДПФ, синус — пик в своём бине (как AnalyserNode), съём в колбэке.
final class SpectrumTests: XCTestCase {
    func testRealFFTMatchesDFT() {
        let n = 256
        var rnd = FxRandom(9)
        let x: [Float] = (0..<n).map { _ in Float(rnd.next() * 2 - 1) }
        let fft = RealFFT(size: n)
        let re = UnsafeMutablePointer<Float>.allocate(capacity: n / 2), im = UnsafeMutablePointer<Float>.allocate(capacity: n / 2)
        defer { re.deallocate(); im.deallocate() }
        x.withUnsafeBufferPointer { fft.forward($0.baseAddress!, re, im) }
        for k in 0..<n / 2 {
            var sr: Double = 0, si: Double = 0
            for i in 0..<n {
                let a = -2 * Double.pi * Double(k * i) / Double(n)
                sr += Double(x[i]) * cos(a)
                si += Double(x[i]) * sin(a)
            }
            XCTAssertEqual(Double(re[k]), sr, accuracy: 1e-3, "re \(k)")
            XCTAssertEqual(Double(im[k]), si, accuracy: 1e-3, "im \(k)")
        }
    }

    /// Синус 1 кГц амплитуды 1 на бине: |X|/N с окном Блэкмана = 0,42/2 → −13,6 dB (как у AnalyserNode).
    func testSineBin() {
        let a = SpectrumAnalyzer()
        let bin = 100
        let f: Double = Double(bin) * 48000 / 4096
        let x: [Float] = (0..<4096).map { Float(sin(2 * Double.pi * f * Double($0) / 48000)) }
        for _ in 0..<40 { a.analyze(x) }
        XCTAssertEqual(Double(a.db[bin]), 20 * log10(0.21), accuracy: 0.01)
        XCTAssertLessThan(a.db[bin + 10], -100)
    }

    /// Съём: EQ дорожки 0 на экране — до и после EQ; low cut 4 кГц на синусе 100 Гц — после EQ тихо.
    func testTapsInCallback() {
        let core = AudioCore(master: true)
        var p = Project()
        p.tracks[0].addSamples(["s"])
        p.tracks[0].eq.bands[0] = EqBand(type: EqSpec.lowCut, freq: 4000, gain: 0, q: 0.7, slope: 2)
        let s = SampleData(left: (0..<48000).map { Float(0.5 * sin(2 * Double.pi * 100 * Double($0) / 48000)) }, right: nil)
        core.publish(p, samples: ["s": s])
        core.spectra.channel.store(0)
        var bl = [Float](repeating: 0, count: 256), br = [Float](repeating: 0, count: 256)
        for _ in 0..<16 { core.render(frames: 256, left: &bl, right: &br) }
        core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        for _ in 0..<40 { core.render(frames: 256, left: &bl, right: &br) }
        func peak(_ tap: SpectrumTap) -> Float {
            let a = SpectrumAnalyzer()
            a.analyze(tap)
            return (0..<SpectrumAnalyzer.bins).map { a.db[$0] }.max() ?? -240
        }
        XCTAssertGreaterThan(peak(core.spectra.pre), -40)
        XCTAssertLessThan(peak(core.spectra.post), -100)
        // Окно коррекции наушников: съём — конечный выход до и после коррекции (через мастер — тоже после EQ дорожки).
        core.spectra.channel.store(EqSpec.phonesChannel)
        for _ in 0..<40 { core.render(frames: 256, left: &bl, right: &br) }
        XCTAssertLessThan(peak(core.spectra.pre), -100)
    }

    /// Нагрузка анализа (отладочная сборка): 4 спектра — как кадр EQ с основным, сравнением и выходом.
    func testAnalyzeLoad() {
        let a = SpectrumAnalyzer()
        let tap = SpectrumTap()
        let t0 = Date()
        for _ in 0..<120 { a.analyze(tap) }
        print(String(format: "spectrum: %.2f ms на спектр", Date().timeIntervalSince(t0) * 1000 / 120))
    }
}
