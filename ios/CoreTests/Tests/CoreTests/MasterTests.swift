import XCTest
@testable import Core

/// Мастер по эталонам mst_* (рендер worklet'ов веба; MasterSelfTest).
final class MasterTests: XCTestCase {
    private func check(_ proc: String, count: Int) throws {
        let all = try MasterSelfTest.loadCases(PlaitsGolden.goldenDir)
        let cases = all.cases.filter { $0.proc == proc }
        XCTAssertEqual(cases.count, count)
        for c in cases {
            let r = try MasterSelfTest.run(c, all, PlaitsGolden.goldenDir)
            print(String(format: "%@: samples %.1f dB, bands ±%.3f dB, rms %.1f dBFS",
                         c.file, r.sampleErrorDb, r.maxBandDiffDb, r.rmsDb))
            XCTAssertTrue(r.ok, "\(c.file): samples \(r.sampleErrorDb) dB, bands \(r.maxBandDiffDb) dB")
        }
    }

    func testSaturator() throws { try check("saturator", count: 5) }
    func testGlue() throws { try check("glue", count: 4) }
    func testClipper() throws { try check("clipper", count: 4) }
    func testLimiter() throws { try check("limiter", count: 4) }
    func testChain() throws { try check("chain", count: 2) }

    /// SELF-TEST: у каждого случая — код и имя, не занятые движками и FX.
    func testSelfTestNames() throws {
        let all = try MasterSelfTest.loadCases(PlaitsGolden.goldenDir)
        XCTAssertEqual(all.cases.count, 19)
        for c in all.cases {
            let code = try XCTUnwrap(MasterSelfTest.codes[c.proc], c.file)
            XCTAssertNotNil(MasterSelfTest.engineNames[code])
            XCTAssertNil(FxSelfTest.engineNames[code])
            XCTAssertNil(JamboSelfTest.engineNames[code])
        }
    }

    /// Лимитер: синус 0 dBFS, GAIN +6, CEILING −1 — пик выхода не выше −1 dBFS, GR около 7 dB; bypass — выход = вход
    /// с задержкой lookahead.
    func testLimiterCeiling() {
        let n = 128
        let lim = MasterLimiter(sampleRate: 48000)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n), r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        var peak: Float = 0
        for b in 0..<375 {
            for i in 0..<n {
                let v = Float(sin(2 * Double.pi * 1000 * Double(b * n + i) / 48000))
                l[i] = v
                r[i] = v
            }
            lim.process(inL: l, inR: r, outL: l, outR: r, frames: n, gain: 6, ceiling: -1, lookahead: 3, rel: 150,
                        auto: false, bypass: false)
            if b > 10 { for i in 0..<n { peak = max(peak, abs(l[i])) } }
        }
        XCTAssertLessThanOrEqual(20 * log10(Double(peak)), -1.0 + 1e-3)
        XCTAssertEqual(lim.frameGr, 7, accuracy: 0.3)
    }

    /// Цепочка по умолчанию: тишина остаётся тишиной (без NaN и денормалов на выходе).
    func testChainSilence() {
        let n = 256
        let chain = MasterChain(sampleRate: 48000)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n), r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        let p = UnsafeMutablePointer<Double>.allocate(capacity: MasterChain.Index.count)
        defer { p.deallocate() }
        for (k, v) in MasterChain.defaults.enumerated() { p[k] = v }
        for _ in 0..<200 {
            l.update(repeating: 0, count: n)
            r.update(repeating: 0, count: n)
            chain.process(left: l, right: r, frames: n, params: p)
        }
        for i in 0..<n { XCTAssertLessThan(abs(l[i]), 1e-12) }
    }

    /// AudioCore: дорожки идут через мастер — задержка SAT 33 + CLIP 32 + LIM (3 мс = 144) + 10 = 219 отсчётов;
    /// с INPUT лимитера +24 dB выход не выше CEILING (−1 dBFS); BYPASS всех модулей — задержка та же.
    func testAudioCoreThroughMaster() {
        func run(_ master: Bool, _ edit: (inout Project) -> Void) -> [Float] {
            let core = AudioCore(master: master)
            var p = Project()
            p.tracks[0].addSamples(["k"])
            p.tracks[0].vol = 0
            edit(&p)
            core.publish(p, samples: ["k": SampleData(left: [Float](repeating: 1, count: 48000), right: nil)])
            var out: [Float] = []
            var bl = [Float](repeating: 0, count: 256), br = [Float](repeating: 0, count: 256)
            // Сначала 2048 кадров тишины: сглаживание параметров и переходы BYPASS (20 мс) закончились.
            for _ in 0..<8 { core.render(frames: 256, left: &bl, right: &br) }
            core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
            for _ in 0..<40 {
                core.render(frames: 256, left: &bl, right: &br)
                out += bl
            }
            return out
        }
        // Середина атаки (1 мс до 0,707): пульсации FIR оверсэмплеров перед фронтом её не задевают.
        func first(_ x: [Float]) -> Int { return x.firstIndex { abs($0) > 0.3 } ?? -1 }
        let dry = run(false) { _ in }
        let wet = run(true) { _ in }
        XCTAssertEqual(first(wet) - first(dry), 219)
        let hot = run(true) { $0.master["lim.input"] = 24 }
        XCTAssertLessThanOrEqual(hot.map { abs($0) }.max() ?? 0, Float(pow(10, -1.0 / 20)) + 1e-5)
        XCTAssertGreaterThan(hot.map { abs($0) }.max() ?? 0, 0.85)
        let byp = run(true) { $0.satBypass = true; $0.cmpBypass = true; $0.clipBypass = true; $0.limBypass = true }
        XCTAssertEqual(first(byp) - first(dry), 219)
        XCTAssertEqual(byp[first(byp) + 3000], dry[first(dry) + 3000], accuracy: 1e-5, "bypass — выход = вход")
    }

    /// Нагрузка (отладочная сборка тестов, доля одного ядра): 1 с шума через каждый модуль блоками по 256.
    func testLoad() {
        let n = 256, blocks = 48000 / 256
        let iL = UnsafeMutablePointer<Float>.allocate(capacity: n), iR = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let oL = UnsafeMutablePointer<Float>.allocate(capacity: n), oR = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { iL.deallocate(); iR.deallocate(); oL.deallocate(); oR.deallocate() }
        var rnd = FxRandom(3)
        for i in 0..<n {
            iL[i] = Float(rnd.next() - 0.5)
            iR[i] = Float(rnd.next() - 0.5)
        }
        let c = MasterChain(sampleRate: 48000)
        func time(_ name: String, _ body: () -> Void) {
            let t0 = Date()
            for _ in 0..<blocks { body() }
            print(String(format: "load %@: %.1f %%", name, Date().timeIntervalSince(t0) * 100))
        }
        time("sat") { c.sat.process(inL: iL, inR: iR, outL: oL, outR: oR, frames: n, drive: 12, type: 0, tone: 0, mix: 100, focus: 20) }
        time("glue") {
            c.glue.process(inL: iL, inR: iR, outL: oL, outR: oR, frames: n, thr: -10, att: 10, rel: 400, auto: false,
                           makeup: 0, ratio: 2, knee: 6, mix: 100, schpf: 90, bypass: false)
        }
        time("clip") { c.clip.process(inL: iL, inR: iR, outL: oL, outR: oR, frames: n, drive: 6, ceiling: -1, softness: 30, bass: 100, bypass: false) }
        time("lim") { c.lim.process(inL: iL, inR: iR, outL: oL, outR: oR, frames: n, gain: 6, ceiling: -1, lookahead: 3, rel: 150, auto: false, bypass: false) }
    }

    /// Ручки MST: шкалы как MASTER_GRID веба (шаг 0,1 dB, AUTO в последних 8 % RELEASE, OFF в первых 5 % BASS),
    /// id и значения по умолчанию — как у цепочки.
    func testMasterKnobs() {
        let byId: [String: ParamDef] = Dictionary(uniqueKeysWithValues: Params.masterGrid.map { ($0.id, $0) })
        XCTAssertEqual(Params.masterGrid.count, 16)
        let defs = MasterChain.defaultValues()
        for p in Params.masterGrid {
            XCTAssertTrue(p.noLock)
            XCTAssertEqual(defs[p.id] ?? .nan, p.def, accuracy: 1e-9, p.id)
        }
        let rel = byId["cmp.release"]!
        XCTAssertEqual(rel.fromNorm(1), MasterChain.autoValue)
        XCTAssertEqual(rel.fromNorm(0.93), MasterChain.autoValue)
        XCTAssertEqual(rel.toNorm(MasterChain.autoValue), 1)
        XCTAssertEqual(rel.fromNorm(0.92 * rel.toNorm(400) / 0.92), 400, accuracy: 1e-6)
        XCTAssertEqual(rel.fromNorm(0), 20, accuracy: 1e-9)
        let bass = byId["clip.bass"]!
        XCTAssertEqual(bass.fromNorm(0.04), 0)
        XCTAssertEqual(bass.toNorm(0), 0)
        XCTAssertEqual(bass.fromNorm(0.05), 20, accuracy: 1e-9)
        XCTAssertEqual(bass.toNorm(300), 1, accuracy: 1e-9)
        let thr = byId["cmp.threshold"]!
        let v: Double = thr.fromNorm(0.123)
        XCTAssertEqual((v * 10).rounded() / 10, v, accuracy: 1e-9)
        XCTAssertEqual(thr.fromNorm(thr.toNorm(-10)), -10, accuracy: 1e-9)
        XCTAssertEqual(byId["sat.type"]!.format(2), "EDGE")
        XCTAssertEqual(Params.masterDb(1.25), "+1.2\ndB")
        XCTAssertEqual(Params.masterMs(MasterChain.autoValue), "AUTO")
    }
}
