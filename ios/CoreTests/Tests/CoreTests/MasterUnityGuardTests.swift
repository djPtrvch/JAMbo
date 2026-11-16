import XCTest
@testable import Core

/// UNITY клиппера и лимитера и GUARD лимитера (16.11).
final class MasterUnityGuardTests: XCTestCase {
    private let sr: Double = 48000
    private let n: Int = 256

    /// Синус 1 кГц амплитуды amp, блок b.
    private func fill(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ b: Int, _ amp: Double) {
        for i in 0..<n {
            let v = Float(amp * sin(2 * Double.pi * 1000 * Double(b * n + i) / sr))
            l[i] = v
            r[i] = v
        }
    }

    private func peak(_ p: UnsafeMutablePointer<Float>) -> Double {
        var m: Float = 0
        for i in 0..<n { m = max(m, abs(p[i])) }
        return Double(m)
    }

    /// Цепочка с синусом 0,5: выход до UNITY (метры) и после (слышимый звук); unity — MasterScope.clip или lim + 1.
    private func runChain(_ set: (UnsafeMutablePointer<Double>) -> Void, unity: Int) -> (meter: Double, heard: Double) {
        let chain = MasterChain(sampleRate: sr)
        chain.unity.store(unity)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n), r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let p = UnsafeMutablePointer<Double>.allocate(capacity: MasterChain.Index.count)
        defer { l.deallocate(); r.deallocate(); p.deallocate() }
        for (k, v) in MasterChain.defaults.enumerated() { p[k] = v }
        set(p)
        var meter: Double = 0, heard: Double = 0
        for k in 0..<400 {
            fill(l, r, k, 0.5)
            chain.process(left: l, right: r, frames: n, params: p)
            if k > 100 { meter = max(meter, peak(l)) }
            chain.applyUnity(l, r, n)
            if k > 100 { heard = max(heard, peak(l)) }
        }
        return (meter, heard)
    }

    /// UNITY (как Unity Gain в Pro-L 2): слышимый звук −INPUT dB, уровень для метров — прежний; без UNITY — без
    /// изменений; в BYPASS модуля — 0 dB.
    func testUnityAfterMeters() {
        let I = MasterChain.Index.self
        let lim = runChain({ $0[I.limGain] = 12 }, unity: MasterScope.lim + 1)
        XCTAssertEqual(20 * log10(lim.heard / lim.meter), -12, accuracy: 0.01)
        let clip = runChain({ $0[I.clipDrive] = 6 }, unity: MasterScope.clip + 1)
        XCTAssertEqual(20 * log10(clip.heard / clip.meter), -6, accuracy: 0.01)
        let off = runChain({ $0[I.limGain] = 12 }, unity: 0)
        XCTAssertEqual(off.heard, off.meter)
        XCTAssertEqual(lim.meter, off.meter, accuracy: 1e-9)
        let byp = runChain({ $0[I.limGain] = 12; $0[I.limBypass] = 1 }, unity: MasterScope.lim + 1)
        XCTAssertEqual(byp.heard, byp.meter)
    }

    /// GUARD 3 dB: синус 0 dBFS при INPUT +12 (GR ~13 dB) — вход убавляется, GR приходит к пределу; затем тихо
    /// (−24 dBFS) — снижение возвращается к нулю. OFF — вход не трогается.
    func testLimiterGuard() {
        let lim = MasterLimiter(sampleRate: sr), off = MasterLimiter(sampleRate: sr)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n), r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        let perSec: Int = Int(sr) / n
        var grSum: Double = 0, grN: Int = 0
        for k in 0..<(25 * perSec) {
            fill(l, r, k, 1)
            lim.process(inL: l, inR: r, outL: l, outR: r, frames: n, gain: 12, ceiling: -1, lookahead: 3, rel: 150,
                        auto: true, bypass: 0, guardDb: 3)
            fill(l, r, k, 1)
            off.process(inL: l, inR: r, outL: l, outR: r, frames: n, gain: 12, ceiling: -1, lookahead: 3, rel: 150,
                        auto: true, bypass: 0)
            if k > 20 * perSec {
                grSum += lim.frameGr
                grN += 1
            }
        }
        XCTAssertEqual(off.guardCut, 0)
        XCTAssertGreaterThan(off.frameGr, 12)
        XCTAssertGreaterThan(lim.guardCut, 8)
        XCTAssertLessThanOrEqual(lim.guardCut, 12)
        XCTAssertEqual(grSum / Double(grN), 3, accuracy: 1.5)
        for k in 0..<(60 * perSec) {
            fill(l, r, k, 0.063)
            lim.process(inL: l, inR: r, outL: l, outR: r, frames: n, gain: 12, ceiling: -1, lookahead: 3, rel: 150,
                        auto: true, bypass: 0, guardDb: 3)
        }
        XCTAssertEqual(lim.guardCut, 0)
    }

    /// GUARD в проекте: по умолчанию OFF; переход MIX между OFF и пределом — на середине.
    func testGuardParam() throws {
        let p = try XCTUnwrap(Params.byId["lim.guard"])
        XCTAssertEqual(p.format(0), "OFF")
        XCTAssertEqual(p.format(4), "4.0 dB")
        XCTAssertEqual(p.fromNorm(0.02), 0)
        XCTAssertEqual(MasterChain.defaultValues()["lim.guard"], 0)
        let m = MixTransition.blendMaster(["lim.guard": 0], ["lim.guard": 4], 0.4)
        XCTAssertEqual(m["lim.guard"], 0)
        XCTAssertTrue(MasterPresetBook.ids(MasterScope.lim).contains("lim.guard"))
    }
}
