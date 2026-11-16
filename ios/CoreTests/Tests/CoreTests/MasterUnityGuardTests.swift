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

    /// Лимитер: UNITY при INPUT +12 — выход на 12 dB тише, OUT индикации и GR — те же; без UNITY — бит в бит прежний.
    func testLimiterUnity() {
        let a = MasterLimiter(sampleRate: sr), b = MasterLimiter(sampleRate: sr)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n), r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let l2 = UnsafeMutablePointer<Float>.allocate(capacity: n), r2 = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { [l, r, l2, r2].forEach { $0.deallocate() } }
        var pa: Double = 0, pb: Double = 0
        for k in 0..<400 {
            fill(l, r, k, 0.5)
            fill(l2, r2, k, 0.5)
            a.process(inL: l, inR: r, outL: l, outR: r, frames: n, gain: 12, ceiling: -1, lookahead: 3, rel: 150,
                      auto: false, bypass: 0)
            b.process(inL: l2, inR: r2, outL: l2, outR: r2, frames: n, gain: 12, ceiling: -1, lookahead: 3, rel: 150,
                      auto: false, bypass: 0, unity: true)
            if k > 100 {
                pa = max(pa, peak(l))
                pb = max(pb, peak(l2))
            }
        }
        XCTAssertEqual(20 * log10(pb / pa), -12, accuracy: 0.01)
        XCTAssertEqual(a.frameGr, b.frameGr, accuracy: 1e-9)
        XCTAssertEqual(a.frameOut, b.frameOut, accuracy: 1e-9)
    }

    /// Клиппер: UNITY при INPUT +6 — выход на 6 dB тише, OUT индикации тот же.
    func testClipperUnity() {
        let a = MasterClipper(sampleRate: sr), b = MasterClipper(sampleRate: sr)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n), r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let l2 = UnsafeMutablePointer<Float>.allocate(capacity: n), r2 = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { [l, r, l2, r2].forEach { $0.deallocate() } }
        var pa: Double = 0, pb: Double = 0
        for k in 0..<300 {
            fill(l, r, k, 0.5)
            fill(l2, r2, k, 0.5)
            a.process(inL: l, inR: r, outL: l, outR: r, frames: n, drive: 6, ceiling: -1, softness: 30, bass: 0,
                      bypass: 0)
            b.process(inL: l2, inR: r2, outL: l2, outR: r2, frames: n, drive: 6, ceiling: -1, softness: 30, bass: 0,
                      bypass: 0, unity: true)
            if k > 100 {
                pa = max(pa, peak(l))
                pb = max(pb, peak(l2))
            }
        }
        XCTAssertEqual(20 * log10(pb / pa), -6, accuracy: 0.01)
        XCTAssertEqual(a.frameOut, b.frameOut, accuracy: 1e-9)
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
