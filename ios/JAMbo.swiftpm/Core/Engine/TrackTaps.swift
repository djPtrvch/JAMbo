import Foundation

// Съём сигнала дорожек для индикации MIX (FREQ, DYN; 10.11): колбэк пишет выход каждой дорожки (после громкости и
// Sidechain, до mute/solo, как метры MIX) моно (L + R)/2 в кольца по capacity отсчётов; счётчик записанного общий
// (все дорожки пишутся одним блоком). Пишет, только пока включено (on ≠ 0, ставит интерфейс); спектр и пик/RMS
// считает интерфейс.
public final class TrackTaps: @unchecked Sendable {
    public static let capacity = 8192
    static let mask = capacity - 1
    public static let tracks = SoundData.maxTracks
    let buf: UnsafeMutablePointer<Float>
    /// Всего записано отсчётов (у каждой дорожки).
    public let written = AtomicCounter()
    /// 1 — съём включён.
    public let on = AtomicCounter()

    public init() {
        let n: Int = TrackTaps.capacity * TrackTaps.tracks
        buf = .allocate(capacity: n)
        buf.initialize(repeating: 0, count: n)
    }

    deinit { buf.deallocate() }

    /// Колбэк: блок n отсчётов выходов дорожек 0…count−1 (outL, outR — по stride отсчётов на дорожку); остальные
    /// дорожки — тишина.
    @inline(__always)
    func push(_ outL: UnsafePointer<Float>, _ outR: UnsafePointer<Float>, stride: Int, count: Int, _ n: Int) {
        let w: Int = written.load()
        let m: Int = TrackTaps.mask
        let cap: Int = TrackTaps.capacity
        var t = 0
        while t < TrackTaps.tracks {
            let b = buf + t * cap
            var i = 0
            if t < count {
                let l = outL + t * stride
                let r = outR + t * stride
                while i < n {
                    b[(w + i) & m] = 0.5 * (l[i] + r[i])
                    i += 1
                }
            } else {
                while i < n {
                    b[(w + i) & m] = 0
                    i += 1
                }
            }
            t += 1
        }
        written.store(w + n)
    }

    /// Интерфейс: последние count отсчётов дорожки t (count ≤ capacity).
    public func read(_ t: Int, into out: UnsafeMutablePointer<Float>, count: Int) {
        let w: Int = written.load()
        let b = buf + t * TrackTaps.capacity
        var i = 0
        while i < count {
            out[i] = b[(w - count + i) & TrackTaps.mask]
            i += 1
        }
    }
}
