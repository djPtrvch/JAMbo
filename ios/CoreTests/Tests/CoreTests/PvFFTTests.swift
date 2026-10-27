import XCTest
@testable import Core

/// БПФ фазового вокодера: спектр совпадает с прямым ДПФ, круг вперёд-назад — исходный сигнал (с масштабом gain).
final class PvFFTTests: XCTestCase {
    func testMatchesDftAndRoundTrip() {
        let n = 64
        let f = PvFFT(size: n)
        let x = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let re = UnsafeMutablePointer<Float>.allocate(capacity: n / 2 + 1)
        let im = UnsafeMutablePointer<Float>.allocate(capacity: n / 2 + 1)
        defer { x.deallocate(); re.deallocate(); im.deallocate() }
        var src = [Float](repeating: 0, count: n)
        for i in 0..<n { src[i] = Float(sin(Double(i) * 0.7) + 0.3 * cos(Double(i) * 2.1) + (i % 5 == 0 ? 0.5 : 0)) }
        for i in 0..<n { x[i] = src[i] }
        f.forward(x, re, im)
        for k in 0...n / 2 {
            var sr: Double = 0, si: Double = 0
            for i in 0..<n {
                let a: Double = -2 * Double.pi * Double(k * i) / Double(n)
                sr += Double(src[i]) * cos(a)
                si += Double(src[i]) * sin(a)
            }
            XCTAssertEqual(Double(re[k]), sr, accuracy: 1e-3, "Re \(k)")
            XCTAssertEqual(Double(im[k]), si, accuracy: 1e-3, "Im \(k)")
        }
        f.inverse(re, im, x)
        for i in 0..<n { XCTAssertEqual(x[i] / f.gain, src[i], accuracy: 1e-4) }
    }
}
