// Голос синтезатора на движках Plaits — как wasm/plaits/jambo_voices.cc (один слот).
// Все движки голоса создаются заранее (не на аудиопотоке); при смене движка — reset(), как в Plaits.
// Огибающую, Level, фильтр и панораму делает цепочка голоса (как сэмпл); LPG Plaits не используется.

/// stmlib/dsp/limiter.h.
struct PlaitsLimiter {
    var peak: Float = 0.5
    mutating func process(_ preGain: Float, _ buf: UnsafeMutablePointer<Float>, _ size: Int) {
        for i in 0..<size {
            let s = buf[i] * preGain
            slope(&peak, abs(s), 0.05, 0.00002)
            let gain: Float = peak <= 1 ? 1 : 1 / peak
            buf[i] = s * gain * 0.8
        }
    }
}

public final class PlaitsVoice {
    /// Число движков Plaits (классические 16; пока перенесены не все — остальные молчат).
    public static let engineCount = 16
    static let gains: [Float] = [0.8, 0.7, 0.6, 0.7, 0.8, 0.6, 0.8, -0.7, -3.0, -1.0, -2.0, -1.0, -1.0, 0.8, 0.8, 0.8]
    static let auxGains: [Float] = [0.8, 0.6, 0.6, 0.6, 0.8, 0.6, 0.8, 0.8, 1.0, -1.0, 1.0, 0.8, 0.8, 0.8, 0.8, 0.8]

    let lut: PlaitsLUT
    let random = PlaitsRandom()
    private var engines: [PlaitsEngine?]
    private(set) var engine = 0
    private var rising = false, gate = false
    private var note: Float = 48, harmonics: Float = 0.5, timbre: Float = 0.5, morph: Float = 0.5, accent: Float = 0.8
    private var auxMix: Float = 0
    private var limiter = PlaitsLimiter(), auxLimiter = PlaitsLimiter()
    let out = plaitsBuffer(kMaxBlockSize)
    let aux = plaitsBuffer(kMaxBlockSize)
    /// Результат render().
    public let output = plaitsBuffer(kMaxBlockSize)

    public init(lut: PlaitsLUT) {
        self.lut = lut
        engines = [
            VirtualAnalogEngine(lut), WaveshapingEngine(lut), FMEngine(lut), GrainEngine(lut),
            AdditiveEngine(lut),
        ]
        while engines.count < Self.engineCount { engines.append(nil) }
        engines[0]?.reset()
    }

    /// Параметры: движок 0…15, нота (MIDI), harmonics/timbre/morph 0…1, aux — доля выхода AUX.
    public func set(engine e: Int, note: Float, harmonics: Float, timbre: Float, morph: Float, accent: Float, aux: Float) {
        let e = (e < 0 || e >= Self.engineCount) ? 0 : e
        if e != engine {
            engine = e
            engines[e]?.reset()
            limiter = PlaitsLimiter()
            auxLimiter = PlaitsLimiter()
        }
        auxMix = min(max(aux, 0), 1)
        self.note = note
        self.harmonics = harmonics
        self.timbre = timbre
        self.morph = morph
        self.accent = accent
    }

    public func trigger() { rising = true; gate = true }
    public func release() { gate = false }

    /// Рассчитать size (≤ 24) отсчётов в output.
    public func render(_ size: Int) {
        guard let e = engines[engine] else {
            output.update(repeating: 0, count: size)
            rising = false
            return
        }
        var p = EngineParameters()
        p.trigger = (rising ? triggerRisingEdge : triggerLow) | (gate ? triggerHigh : triggerLow)
        rising = false
        p.note = note
        p.harmonics = harmonics
        p.timbre = timbre
        p.morph = morph
        p.accent = accent
        var enveloped = engine >= 11
        e.render(p, out, aux, size, &enveloped)
        post(&limiter, Self.gains[engine], out, size)
        post(&auxLimiter, Self.auxGains[engine], aux, size)
        let a = auxMix
        for i in 0..<size {
            let v = out[i] * (1 - a) + aux[i] * a
            output[i] = v > 1 ? 1 : (v < -1 ? -1 : v)
        }
    }

    private func post(_ l: inout PlaitsLimiter, _ g: Float, _ buf: UnsafeMutablePointer<Float>, _ size: Int) {
        var gain = g
        if gain < 0 {
            l.process(-gain, buf, size)
            gain = 1
        }
        for i in 0..<size { buf[i] *= gain }
    }
}
