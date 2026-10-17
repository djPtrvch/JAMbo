// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/fx/diffuser.h (с fx_engine.h, формат 12 бит), overdrive.h.

/// Diffuser: цепочка all-pass с модуляцией (PARTICLE). FxEngine<8192, FORMAT_12_BIT> развёрнут вручную:
/// линии задержки — смещения base в общем кольце, длины 126, 180, 269, 444, 1653, 2010, 3411.
final class Diffuser {
    private static let size: Int32 = 8192
    private static let mask: Int32 = 8191
    // base линий: ap1, ap2, ap3, ap4, dapa, dapb, del (base_k = base_{k−1} + length_{k−1} + 1).
    private static let ap1: Int32 = 0, ap1Len: Int32 = 126
    private static let ap2: Int32 = 127, ap2Len: Int32 = 180
    private static let ap3: Int32 = 308, ap3Len: Int32 = 269
    private static let ap4: Int32 = 578
    private static let dapa: Int32 = 1023, dapaLen: Int32 = 1653
    private static let dapb: Int32 = 2677, dapbLen: Int32 = 2010
    private static let del: Int32 = 4688

    private let buffer: UnsafeMutablePointer<UInt16>
    private var writePtr: Int32 = 0
    private var lfo = CosineOscillator()
    private var lpDecay: Float = 0

    init() {
        buffer = .allocate(capacity: Int(Diffuser.size))
        buffer.initialize(repeating: 0, count: Int(Diffuser.size))
        lfo.initApproximate(0.3 / 48000 * 32)
        lpDecay = 0
    }

    deinit { buffer.deallocate() }

    func reset() {
        buffer.update(repeating: 0, count: Int(Diffuser.size))
        writePtr = 0
    }

    @inline(__always) private func decompress(_ v: UInt16) -> Float { Float(Int16(bitPattern: v)) / 4096 }

    @inline(__always) private func compress(_ v: Float) -> UInt16 {
        UInt16(bitPattern: Int16(stmClip16(Int32(truncatingIfNeeded: stmInt(v * 4096)))))
    }

    func process(_ amount: Float, _ rt: Float, _ inOut: UnsafeMutablePointer<Float>, _ size: Int) {
        let kap: Float = 0.625
        let klp: Float = 0.75
        let m = Diffuser.mask
        var lp = lpDecay
        for i in 0..<size {
            // engine_.Start(&c).
            writePtr -= 1
            if writePtr < 0 { writePtr += Diffuser.size }
            let wp = writePtr
            let lfoValue = (wp & 31) == 0 ? lfo.next() : lfo.value
            var acc: Float = 0
            var previousRead: Float = 0

            @inline(__always) func readTail(_ base: Int32, _ length: Int32, _ scale: Float) {
                let r = decompress(buffer[Int((wp + base + length - 1) & m)])
                previousRead = r
                acc += r * scale
            }
            @inline(__always) func write(_ base: Int32, _ scale: Float) {
                buffer[Int((wp + base) & m)] = compress(acc)
                acc *= scale
            }
            @inline(__always) func writeAllPass(_ base: Int32, _ scale: Float) {
                write(base, scale)
                acc += previousRead
            }
            @inline(__always) func interpolate(_ base: Int32, _ offsetIn: Float, _ amplitude: Float, _ scale: Float) {
                let offset = offsetIn + amplitude * lfoValue
                let integral = Int32(truncatingIfNeeded: stmInt(offset))
                let fractional = offset - Float(integral)
                let a = decompress(buffer[Int((wp + integral + base) & m)])
                let b = decompress(buffer[Int((wp + integral + base + 1) & m)])
                let x = a + (b - a) * fractional
                previousRead = x
                acc += x * scale
            }

            acc += inOut[i]
            readTail(Diffuser.ap1, Diffuser.ap1Len, kap)
            writeAllPass(Diffuser.ap1, -kap)
            readTail(Diffuser.ap2, Diffuser.ap2Len, kap)
            writeAllPass(Diffuser.ap2, -kap)
            readTail(Diffuser.ap3, Diffuser.ap3Len, kap)
            writeAllPass(Diffuser.ap3, -kap)
            interpolate(Diffuser.ap4, 400, 43, kap)
            writeAllPass(Diffuser.ap4, -kap)
            interpolate(Diffuser.del, 3070, 340, rt)
            lp += klp * (acc - lp)
            acc = lp
            readTail(Diffuser.dapa, Diffuser.dapaLen, -kap)
            writeAllPass(Diffuser.dapa, kap)
            readTail(Diffuser.dapb, Diffuser.dapbLen, kap)
            writeAllPass(Diffuser.dapb, -kap)
            write(Diffuser.del, 2)
            let wet = acc
            inOut[i] += amount * (wet - inOut[i])
        }
        lpDecay = lp
        flushDenormal(&lpDecay)
    }
}

/// Overdrive: мягкое ограничение с подстройкой усиления (KICK).
struct Overdrive {
    private var preGain: Float = 0
    private var postGain: Float = 0

    mutating func initialize() {
        preGain = 0
        postGain = 0
    }

    @inline(__always) mutating func process(_ drive: Float, _ inOut: UnsafeMutablePointer<Float>, _ size: Int) {
        let drive2 = drive * drive
        let preGainA = drive * 0.5
        let preGainB = drive2 * drive2 * drive * 24
        let pre = preGainA + (preGainB - preGainA) * drive2
        let driveSquashed = drive * (2 - drive)
        let post = 1 / stmSoftClip(0.33 + driveSquashed * (pre - 0.33))
        var preModulation = ParameterInterpolator(preGain, pre, size)
        var postModulation = ParameterInterpolator(postGain, post, size)
        for i in 0..<size {
            let s = preModulation.next() * inOut[i]
            inOut[i] = stmSoftClip(s) * postModulation.next()
        }
        preGain = preModulation.value
        postGain = postModulation.value
    }
}
