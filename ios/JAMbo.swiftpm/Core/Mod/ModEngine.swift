import Foundation

// Модуляция (как state.ts веба: lfoShape, lfoShaped, advanceLfos, envShape, modulatedNorm) — в колбэке, на блок.
// У каждой дорожки LFO1–3 (идут всегда, независимо от PLAY; Random — новое значение на каждом цикле) и огибающая ENV
// (запускается каждой нотой дорожки в своём кадре, гейт — длина ноты; живая нота — пока держат клавишу).
// Назначение: значение ручки в 0…1 + степень · выход источника (LFO −1…+1, ENV 0…1), с ограничением 0…1.
// Параметры LFO/ENV — ручки дорожки с p-lock играющего шага (MOD).

/// Шкала ручки (как ParamDef) без строк и замыканий — для колбэка.
public struct ParamScale {
    public var min: Double = 0
    public var max: Double = 1
    /// Степень (0 — нет).
    public var curve: Double = 0
    public var exp: Bool = false
    public var stepped: Bool = false
    /// Пунктов у ступенчатой с непрерывным значением (0 — нет).
    public var steps: Int = 0

    public init() {}

    public init(_ p: ParamDef) {
        min = p.min
        max = p.max
        curve = p.curve ?? 0
        exp = p.exp
        stepped = p.kind == .stepped
        steps = p.steps ?? 0
    }

    @inline(__always)
    public func toNorm(_ v: Double) -> Double {
        if exp { return log(v / min) / log(max / min) }
        let lin: Double = Swift.min(1, Swift.max(0, (v - min) / (max - min)))
        if curve > 0 { return pow(lin, 1 / curve) }
        return lin
    }

    @inline(__always)
    public func fromNorm(_ n0: Double) -> Double {
        let n: Double = Swift.min(1, Swift.max(0, n0))
        if steps > 0 {
            let i: Int = Swift.min(steps - 1, Swift.max(0, Int((n * Double(steps)).rounded(.down))))
            return min + (Double(i) + 0.5) / Double(steps) * (max - min)
        }
        if stepped { return (n * (max - min)).rounded() + min }
        if exp { return min * pow(max / min, n) }
        if curve > 0 { return min + pow(n, curve) * (max - min) }
        return min + n * (max - min)
    }
}

/// Цели модуляции дорожки: параметры голоса (VoiceParam), затем Chance, Ratchet (Swing — без LFO/ENV, S12).
public enum ModTarget {
    public static let prob = VoiceParam.count
    public static let ratchet = VoiceParam.count + 1
    public static let count = VoiceParam.count + 2
    public static let ids: [String] = VoiceParam.ids + ["prob", "ratchet"]
}

public final class ModEngine {
    static let tracks = SoundData.maxTracks
    // Номера параметров в Params.modIds: LFOn — 4·(n−1) + (wave, speed, invert, polar), ENV — 12…15.
    static let envAttack = 12, envDecay = 13, envSustain = 14, envRelease = 15

    let sr: Double
    var rng: FxRandom
    /// Фазы и случайные значения LFO (дорожка·3 + n), выход LFO на этот блок.
    let phase: UnsafeMutablePointer<Double>
    let rnd: UnsafeMutablePointer<Double>
    let lfo: UnsafeMutablePointer<Double>
    /// Параметры MOD дорожки на этот блок (с p-lock).
    let p: UnsafeMutablePointer<Double>
    /// ENV: кадр запуска (−1 — не запускалась), конец гейта; живых нот дорожки.
    let envStart: UnsafeMutablePointer<Int64>
    let envGateEnd: UnsafeMutablePointer<Int64>
    let live: UnsafeMutablePointer<Int>
    var data: SoundData?
    /// Выходы источников для интерфейса (кольца): дорожка·4 + (LFO1–3, ENV) — на начало блока.
    public let outs: [AtomicFloat]
    /// Для миниатюр: фазы LFO (дорожка·3 + n), ENV — мс от запуска (−1 — нет) и гейт в мс (живая — 1e9).
    public let phaseOuts: [AtomicFloat]
    public let envOuts: [AtomicFloat]

    public init(sampleRate: Double, seed: UInt32 = FxRandom.seed()) {
        sr = sampleRate
        rng = FxRandom(seed)
        let n = ModEngine.tracks
        phase = .allocate(capacity: n * 3)
        rnd = .allocate(capacity: n * 3)
        lfo = .allocate(capacity: n * 3)
        p = .allocate(capacity: n * Params.modCount)
        envStart = .allocate(capacity: n)
        envGateEnd = .allocate(capacity: n)
        live = .allocate(capacity: n)
        phase.initialize(repeating: 0, count: n * 3)
        rnd.initialize(repeating: 0, count: n * 3)
        lfo.initialize(repeating: 0, count: n * 3)
        p.initialize(repeating: 0, count: n * Params.modCount)
        envStart.initialize(repeating: -1, count: n)
        envGateEnd.initialize(repeating: 0, count: n)
        live.initialize(repeating: 0, count: n)
        outs = (0..<(n * 4)).map { _ in AtomicFloat(0) }
        phaseOuts = (0..<(n * 3)).map { _ in AtomicFloat(0) }
        envOuts = (0..<(n * 2)).map { _ in AtomicFloat(-1) }
        for t in 0..<n {
            for (k, id) in Params.modIds.enumerated() { p[t * Params.modCount + k] = Params.byId[id]?.def ?? 0 }
        }
    }

    deinit {
        phase.deallocate()
        rnd.deallocate()
        lfo.deallocate()
        p.deallocate()
        envStart.deallocate()
        envGateEnd.deallocate()
        live.deallocate()
    }

    /// Форма LFO: wave 0 Sine, 1 Triangle, 2 Saw, 3 Square, иначе Random.
    @inline(__always)
    static func shape(_ wave: Int, _ ph: Double, _ r: Double) -> Double {
        switch wave {
        case 0: return sin(ph * 2 * Double.pi)
        case 1: return ph < 0.25 ? ph * 4 : (ph < 0.75 ? 2 - ph * 4 : ph * 4 - 4)
        case 2: return ph * 2 - 1
        case 3: return ph < 0.5 ? 1 : -1
        default: return r
        }
    }

    /// Начало блока: параметры MOD с p-lock играющего шага, выход LFO и шаг фаз на n отсчётов.
    public func begin(_ d: SoundData, frames n: Int, lockMask: UnsafePointer<UInt16>, lockVal: UnsafePointer<Float>) {
        data = d
        let c = Params.modCount
        let dt: Double = Double(n) / sr
        var t = 0
        while t < d.trackCount {
            let m = lockMask[t]
            // Переход MIX: параметры LFO/ENV — звука, который сейчас действует (клип PREV — старой дорожки).
            let su = d.s(t) * c
            var k = 0
            while k < c {
                let i = t * c + k
                p[i] = m & (UInt16(1) << UInt16(k)) != 0 ? Double(lockVal[i]) : Double(d.mod[su + k])
                k += 1
            }
            var l = 0
            while l < 3 {
                let b = t * c + 4 * l
                let j = t * 3 + l
                let s: Double = ModEngine.shape(Int(p[b].rounded()), phase[j], rnd[j])
                let u: Double = p[b + 3]
                lfo[j] = (s * (1 - u) + ((s + 1) / 2) * u) * (1 - 2 * p[b + 2])
                var ph: Double = phase[j] + dt * p[b + 1]
                if ph >= 1 {
                    ph = ph.truncatingRemainder(dividingBy: 1)
                    rnd[j] = rng.next() * 2 - 1
                }
                phase[j] = ph
                outs[t * 4 + l].store(Float(lfo[j]))
                phaseOuts[j].store(Float(phase[j]))
                l += 1
            }
            t += 1
        }
    }

    /// Выходы ENV для интерфейса — в конце блока (после тригов).
    public func publish(frame: Int64) {
        guard let d = data else { return }
        var t = 0
        while t < d.trackCount {
            outs[t * 4 + 3].store(Float(env(t, frame)))
            let s0 = envStart[t]
            let ms: Double = 1000 / sr
            envOuts[t * 2].store(s0 < 0 ? -1 : Float(Double(frame - s0) * ms))
            envOuts[t * 2 + 1].store(envGateEnd[t] == Int64.max ? 1e9 : Float(Double(envGateEnd[t] - s0) * ms))
            t += 1
        }
    }

    /// Уровень ADSR (0…1) в кадре frame.
    @inline(__always)
    public func env(_ t: Int, _ frame: Int64) -> Double {
        let s0 = envStart[t]
        if s0 < 0 || frame < s0 { return 0 }
        let b = t * Params.modCount
        let a: Double = p[b + ModEngine.envAttack]
        let dd: Double = p[b + ModEngine.envDecay]
        let s: Double = p[b + ModEngine.envSustain] / 100
        let r: Double = p[b + ModEngine.envRelease]
        let ms: Double = 1000 / sr
        let x: Double = Double(frame - s0) * ms
        let gate: Double = envGateEnd[t] == Int64.max ? Double.infinity : Double(envGateEnd[t] - s0) * ms
        @inline(__always) func ads(_ y: Double) -> Double {
            return y < a ? y / a : (y < a + dd ? 1 - (1 - s) * (y - a) / dd : s)
        }
        if x < gate { return ads(x) }
        let rel: Double = x - gate
        return rel < r ? ads(gate) * (1 - rel / r) : 0
    }

    /// Выход источника lfo (1–3 — LFO, 4 — ENV) дорожки t в кадре frame.
    @inline(__always)
    public func source(_ t: Int, _ lfoN: Int, _ frame: Int64) -> Double {
        if lfoN == 4 { return env(t, frame) }
        if lfoN < 1 || lfoN > 3 { return 0 }
        return lfo[t * 3 + lfoN - 1]
    }

    /// Нота дорожки t в кадре frame: ENV с начала; gate — кадров удержания (Int64.max — живая, до отпускания).
    public func trig(track t: Int, at frame: Int64, gate: Int64) {
        envStart[t] = frame
        envGateEnd[t] = gate == Int64.max ? Int64.max : frame + Swift.max(0, gate)
    }

    /// Живая нота: ENV с гейтом до отпускания всех клавиш дорожки.
    public func liveOn(track t: Int, at frame: Int64) {
        live[t] += 1
        trig(track: t, at: frame, gate: Int64.max)
    }

    public func liveOff(track t: Int, at frame: Int64) {
        live[t] = Swift.max(0, live[t] - 1)
        if live[t] == 0 && envStart[t] >= 0 && envGateEnd[t] > frame { envGateEnd[t] = frame }
    }

    /// Значение цели j дорожки t с модуляцией (base — ручка или p-lock); без назначения — base.
    @inline(__always)
    public func value(_ t: Int, _ j: Int, _ base: Double, _ frame: Int64) -> Double {
        guard let d = data else { return base }
        let i = d.s(t) * ModTarget.count + j
        let src = Int(d.asSrc[i])
        if src == 0 { return base }
        let sc = d.scale[i]
        let n: Double = sc.toNorm(base) + Double(d.asAmt[i]) * source(t, src, frame)
        return sc.fromNorm(Swift.min(1, Swift.max(0, n)))
    }

    /// Есть ли у дорожки назначения (быстрая проверка в голосе).
    @inline(__always)
    public func modulated(_ t: Int) -> Bool {
        guard let d = data else { return false }
        return d.asAny[d.s(t)] != 0
    }
}
