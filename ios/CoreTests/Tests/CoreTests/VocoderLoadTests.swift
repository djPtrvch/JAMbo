import XCTest
@testable import Core

/// Нагрузка таймстретча NORMAL: кадры голосов разнесены по блокам колбэка, звук — тот же, что без раннего расчёта.
final class VocoderLoadTests: XCTestCase {
    /// Аккорд с ударами через 0,25 с (атаки сэмпла — куски тянутся отдельно).
    private func source() -> (SampleData, [Float]) {
        let n = 96000
        var x = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / 48000
            x[i] = Float(0.2 * sin(2 * .pi * 220 * t) + 0.2 * sin(2 * .pi * 329.6 * t))
        }
        var k = 12000
        while k < n {
            for i in 0..<480 where k + i < n { x[k + i] += Float(0.8 * exp(-Double(i) / 60) * sin(Double(i) * 0.9)) }
            k += 12000
        }
        return (SampleData(left: x, right: nil), x)
    }

    /// voices голосов с одного отсчёта, скорость speed; блоки по block (кусками 32, как Sampler): выход голосов и
    /// число кадров в каждом блоке.
    private func run(_ voc: Vocoder, block: Int, voices: Int, speed: Double, blocks: Int) -> ([[Float]], [Int]) {
        let (sd, x) = source()
        var src = x
        let ons = sd.onsets
        voc.block = block
        for v in 0..<voices { voc.start(v, dir: 1) }
        var out = [[Float]](repeating: [], count: voices)
        var perBlock: [Int] = []
        var pos = [Double](repeating: 0, count: voices)
        let frames = src.count
        src.withUnsafeMutableBufferPointer { p in
            withExtendedLifetime(sd) {
                let sp = p.baseAddress!
                for b in 0..<blocks {
                    let before = voc.framesDone
                    var i = 0
                    while i < block {
                        for v in 0..<voices {
                            voc.fill(v, sp, sp, frames, false, pos[v], speed, 1, 32, 0, 0, Double(frames - 1),
                                     ons.at, ons.count, Int64(b * block + i))
                            for j in 0..<32 { out[v].append(voc.outL[j]) }
                            pos[v] += speed * 32
                        }
                        i += 32
                    }
                    perBlock.append(voc.framesDone - before)
                }
            }
        }
        return (out, perBlock)
    }

    func testFramesSpreadAcrossBlocks() {
        let blocks = 300
        let (spread, nSpread) = run(Vocoder(slots: 4), block: 256, voices: 4, speed: 0.5, blocks: blocks)
        // Блок 512 = hop: раннего расчёта нет — эталон звука и нагрузки.
        let (plain, nPlain) = run(Vocoder(slots: 4), block: 512, voices: 4, speed: 0.5, blocks: blocks / 2)
        // Без разнесения 4 голоса с одного отсчёта считают кадры в одном блоке; с разнесением — не больше 2 на блок
        // (кроме блоков с атаками сэмпла: там голоса начинают кусок заново).
        let plainPeak = nPlain.max() ?? 0
        XCTAssertGreaterThanOrEqual(plainPeak, 4)
        let heavy = nSpread.filter { $0 > 2 }.count
        XCTAssertLessThan(heavy, blocks / 20, "кадры голосов разнесены по блокам: \(nSpread.prefix(40))")
        XCTAssertEqual(nSpread.reduce(0, +), nPlain.reduce(0, +), accuracy: 8, "кадров столько же")
        // Звук тот же (ранний кадр — по той же скорости).
        for v in 0..<4 {
            var err: Double = 0, sig: Double = 0
            for i in 0..<min(spread[v].count, plain[v].count) {
                let d = Double(spread[v][i] - plain[v][i])
                err += d * d
                sig += Double(plain[v][i] * plain[v][i])
            }
            XCTAssertGreaterThan(sig, 1)
            let snr: Double = 10 * log10(sig / max(1e-12, err))
            XCTAssertGreaterThan(snr, 60, "голос \(v): звук с ранним расчётом тот же (\(snr) dB)")
        }
    }
}
