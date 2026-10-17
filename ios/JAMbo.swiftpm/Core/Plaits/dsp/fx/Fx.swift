// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/fx/diffuser.h (с fx_engine.h, формат 12 бит), overdrive.h.

/// Diffuser: цепочка all-pass с модуляцией (PARTICLE). FxEngine<8192, FORMAT_12_BIT> развёрнут вручную:
/// линии задержки — смещения base в общем кольце, длины 126, 180, 269, 444, 1653, 2010, 3411. Кольцо хранит Float,
/// уже квантованный как 12-битный формат (Clip16(int(x·4096)) / 4096) — те же числа, без распаковки при чтении:
/// в отладочной сборке (Playgrounds) упаковка и распаковка Int16 на каждом обращении перегружали процессор.
final class Diffuser {
    private static let size = 8192
    private static let mask = 8191
    // base линий: ap1, ap2, ap3, ap4, dapa, dapb, del (base_k = base_{k−1} + length_{k−1} + 1); хвост — base + length − 1.
    private static let ap1 = 0, ap1Tail = 125
    private static let ap2 = 127, ap2Tail = 306
    private static let ap3 = 308, ap3Tail = 576
    private static let ap4 = 578
    private static let dapa = 1023, dapaTail = 2675
    private static let dapb = 2677, dapbTail = 4686
    private static let del = 4688

    private let buffer: UnsafeMutablePointer<Float>
    private var writePtr = 0
    private var lfo = CosineOscillator()
    private var lpDecay: Float = 0

    init() {
        buffer = .allocate(capacity: Diffuser.size)
        buffer.initialize(repeating: 0, count: Diffuser.size)
        lfo.initApproximate(0.3 / 48000 * 32)
        lpDecay = 0
    }

    deinit { buffer.deallocate() }

    func reset() {
        buffer.update(repeating: 0, count: Diffuser.size)
        writePtr = 0
    }

    /// DataType<FORMAT_12_BIT>: Decompress(Compress(v)) — отбросить дробь от v·4096, ограничить Int16, / 4096.
    @inline(__always) private static func quantize(_ v: Float) -> Float {
        var x = (v * 4096).rounded(.towardZero)
        if x > 32767 { x = 32767 } else if x < -32768 { x = -32768 }
        return x * (1 / 4096)
    }

    func process(_ amount: Float, _ rt: Float, _ inOut: UnsafeMutablePointer<Float>, _ size: Int) {
        let kap: Float = 0.625
        let klp: Float = 0.75
        let m = Diffuser.mask
        let buf = buffer
        var lp = lpDecay
        var wp = writePtr
        var lfo = self.lfo
        var i = 0
        while i < size {
            // engine_.Start(&c).
            wp -= 1
            if wp < 0 { wp += Diffuser.size }
            let lfoValue = (wp & 31) == 0 ? lfo.next() : lfo.value
            var acc: Float = inOut[i]
            var r: Float
            // ap1, ap2, ap3: Read(TAIL, kap), WriteAllPass(−kap).
            r = buf[(wp + Diffuser.ap1Tail) & m]
            acc += r * kap
            buf[(wp + Diffuser.ap1) & m] = Diffuser.quantize(acc)
            acc = acc * -kap + r
            r = buf[(wp + Diffuser.ap2Tail) & m]
            acc += r * kap
            buf[(wp + Diffuser.ap2) & m] = Diffuser.quantize(acc)
            acc = acc * -kap + r
            r = buf[(wp + Diffuser.ap3Tail) & m]
            acc += r * kap
            buf[(wp + Diffuser.ap3) & m] = Diffuser.quantize(acc)
            acc = acc * -kap + r
            // ap4: Interpolate(400, LFO, 43, kap), WriteAllPass(−kap).
            var offset: Float = 400 + 43 * lfoValue
            var integral = stmInt(offset)
            var fractional = offset - Float(integral)
            var a = buf[(wp + integral + Diffuser.ap4) & m]
            var b = buf[(wp + integral + Diffuser.ap4 + 1) & m]
            r = a + (b - a) * fractional
            acc += r * kap
            buf[(wp + Diffuser.ap4) & m] = Diffuser.quantize(acc)
            acc = acc * -kap + r
            // del: Interpolate(3070, LFO, 340, rt), Lp.
            offset = 3070 + 340 * lfoValue
            integral = stmInt(offset)
            fractional = offset - Float(integral)
            a = buf[(wp + integral + Diffuser.del) & m]
            b = buf[(wp + integral + Diffuser.del + 1) & m]
            r = a + (b - a) * fractional
            acc += r * rt
            lp += klp * (acc - lp)
            acc = lp
            // dapa: Read(TAIL, −kap), WriteAllPass(kap); dapb: Read(TAIL, kap), WriteAllPass(−kap).
            r = buf[(wp + Diffuser.dapaTail) & m]
            acc += r * -kap
            buf[(wp + Diffuser.dapa) & m] = Diffuser.quantize(acc)
            acc = acc * kap + r
            r = buf[(wp + Diffuser.dapbTail) & m]
            acc += r * kap
            buf[(wp + Diffuser.dapb) & m] = Diffuser.quantize(acc)
            acc = acc * -kap + r
            // Write(del, 2), Write(wet, 0).
            buf[(wp + Diffuser.del) & m] = Diffuser.quantize(acc)
            let wet = acc * 2
            inOut[i] += amount * (wet - inOut[i])
            i += 1
        }
        writePtr = wp
        self.lfo = lfo
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
