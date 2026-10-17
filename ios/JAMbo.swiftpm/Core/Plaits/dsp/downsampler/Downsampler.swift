// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/downsampler/4x_downsampler.h.

let kOversampling = 4

/// Дециматор 4×: КИХ на 8 отсчётов (две половины по 4). В C++ деструктор пишет head_ обратно в *state;
/// здесь — явно: `state = d.head`.
struct Downsampler {
    private(set) var head: Float
    private var tail: Float = 0
    private let fir: UnsafePointer<Float>

    @_transparent init(_ state: Float, _ fir: UnsafePointer<Float>) {
        head = state
        self.fir = fir
    }

    @_transparent mutating func accumulate(_ i: Int, _ sample: Float) {
        head += sample * fir[3 - (i & 3)]
        tail += sample * fir[i & 3]
    }

    @_transparent mutating func read() -> Float {
        let value = head
        head = tail
        tail = 0
        return value
    }
}
