import XCTest
import Synchronization
@testable import Core

/// Многоядерный режим (MULTICORE): с помощниками звук тот же, что в один поток (отсчёт в отсчёт), задания не теряются
/// и не считаются дважды.
final class RenderPoolTests: XCTestCase {
    final class Counter: RenderJobs {
        let hits = UnsafeMutablePointer<Int>.allocate(capacity: 64)
        let total = Atomic<Int>(0)
        init() { hits.initialize(repeating: 0, count: 64) }
        func runJob(_ j: Int) {
            hits[j] += 1
            total.wrappingAdd(1, ordering: .relaxed)
        }
    }

    func testEveryJobOnce() {
        let pool = RenderPool()
        let c = Counter()
        pool.start(3) { return {} }
        var block = 0
        while block < 2000 {
            let n: Int = 2 + block % 14
            c.hits.update(repeating: 0, count: 64)
            pool.run(n, c)
            for j in 0..<n where c.hits[j] != 1 { XCTFail("блок \(block): задание \(j) — \(c.hits[j]) раз") }
            block += 1
        }
        pool.stop()
    }

    /// Тяжёлый проект: синты дорожек на помощниках — шины дорожек и посылов те же, что без них (выход целиком не
    /// сравнить: у Reverb каждого ядра свой случайный засев).
    func testSameSoundWithHelpers() {
        compareWithHelpers(HeavyLoadTests.heavyProject())
    }

    /// EQ дорожек, которые не слушают другие (динамическая полоса — от своей дорожки), — задания пула до микшера:
    /// звук тот же.
    func testSameSoundWithParallelEqs() {
        var p = HeavyLoadTests.heavyProject()
        for t in 0..<8 {
            let bell: Int = p.addEqBand(t, freq: 1200, gain: -4)
            p.setEqDyn(t, bell, t + 1)
            p.setEqDynParams(t, bell, thr: -30, range: -9)
            for k in p.tracks[t].eq.bands.indices where p.tracks[t].eq.bands[k]?.dyn ?? 0 != t + 1 {
                p.setEqDyn(t, k, 0)
            }
            XCTAssertFalse(EqSpec.listensToTrack(p, t, 8))
        }
        compareWithHelpers(p)
    }

    private func compareWithHelpers(_ project: Project) {
        let a = make(project), b = make(project)
        var bl = [Float](repeating: 0, count: 256)
        var br = [Float](repeating: 0, count: 256)
        // Первый блок ставит синт и цель пула; помощники — после.
        a.render(frames: 256, left: &bl, right: &br)
        b.render(frames: 256, left: &bl, right: &br)
        b.pool.start(3) { return {} }
        var diff: Float = 0
        var peak: Float = 0
        let mf: Int = 4096
        var k = 0
        while k < 2 * 48000 / 256 {
            a.render(frames: 256, left: &bl, right: &br)
            b.render(frames: 256, left: &bl, right: &br)
            let sa = a.sampler, sb = b.sampler
            for t in 0..<8 {
                for i in 0..<256 {
                    let j: Int = t * mf + i
                    diff = max(diff, abs(sa.busL[j] - sb.busL[j]), abs(sa.busR[j] - sb.busR[j]))
                    peak = max(peak, abs(sa.busL[j]))
                    for s in 0..<3 {
                        let q: Int = (t * 3 + s) * mf + i
                        diff = max(diff, abs(sa.sendL[q] - sb.sendL[q]), abs(sa.sendR[q] - sb.sendR[q]))
                    }
                }
            }
            k += 1
        }
        b.pool.stop()
        XCTAssertEqual(diff, 0, "звук с помощниками отличается")
        XCTAssertGreaterThan(peak, 0.01, "звук есть")
    }

    private func make(_ project: Project) -> AudioCore {
        let core = AudioCore()
        core.installSynth()
        var samples: [String: SampleData] = [:]
        for t in 4..<8 { samples["s\(t)"] = HeavyLoadTests.sample(t) }
        core.publish(project, samples: samples)
        core.events.push(.play(true))
        return core
    }
}
