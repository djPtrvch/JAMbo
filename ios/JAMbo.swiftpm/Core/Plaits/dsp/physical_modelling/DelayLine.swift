// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/physical_modelling/delay_line.h (DelayLine<float, max_delay>; max_delay — степень двойки,
// поэтому % max_delay беззнаковой арифметики оригинала — то же, что & (max_delay − 1)).

struct DelayLine {
    private let line: UnsafeMutablePointer<Float>
    private let maxDelay: Int
    private let mask: Int
    private var writePtr = 0

    /// Буфер выделяется здесь (в оригинале — из BufferAllocator движка).
    init(_ maxDelay: Int) {
        self.maxDelay = maxDelay
        mask = maxDelay - 1
        line = plaitsAllocate(maxDelay)
    }

    func deallocate() { line.deallocate() }

    mutating func reset() {
        line.update(repeating: 0, count: maxDelay)
        writePtr = 0
    }

    @inline(__always) mutating func write(_ sample: Float) {
        // Денормалы не копятся в кольце (затухающая струна).
        line[writePtr] = abs(sample) < 1e-20 ? 0 : sample
        writePtr = (writePtr - 1 + maxDelay) & mask
    }

    @inline(__always) mutating func allpass(_ sample: Float, _ delay: Int, _ coefficient: Float) -> Float {
        let read = line[(writePtr + delay) & mask]
        let w = sample + coefficient * read
        write(w)
        return -w * coefficient + read
    }

    @inline(__always) func read(_ delay: Float) -> Float {
        let integral = stmInt(delay)
        let fractional = delay - Float(integral)
        let a = line[(writePtr + integral) & mask]
        let b = line[(writePtr + integral + 1) & mask]
        return a + (b - a) * fractional
    }

    /// Read(int): целая задержка (Read(14) в StringEngine).
    @inline(__always) func read(_ delay: Int) -> Float { line[(writePtr + delay) & mask] }

    @inline(__always) func readHermite(_ delay: Float) -> Float {
        let integral = stmInt(delay)
        let f = delay - Float(integral)
        let t = writePtr + integral + maxDelay
        let xm1 = line[(t - 1) & mask]
        let x0 = line[t & mask]
        let x1 = line[(t + 1) & mask]
        let x2 = line[(t + 2) & mask]
        let c = (x1 - xm1) * 0.5
        let v = x0 - x1
        let w = c + v
        let a = w + v + (x2 - x0) * 0.5
        let bNeg = w + a
        return (((a * f) - bNeg) * f + c) * f + x0
    }
}
