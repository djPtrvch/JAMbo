import Foundation

// Кроссфейдер перехода MIX (S10c, как setCrossfade, blendRecord, blendEq веба; отличие от веба — всё плавно,
// без переключений на середине): темп, громкости дорожек, выход, мастер и EQ мастера от старого проекта (0)
// к новому (1). Ступенчатое ведётся через нейтральное: BYPASS — долей глушения, разный TYPE сатуратора — через
// сухой сигнал на середине, полоса EQ, которой нет с одной стороны, — усилением к 0 dB или частотой к краю.

/// Смесь: общие настройки для проекта (ручки, поля; BYPASS — ближайший) и параметры мастера для колбэка
/// (MasterChain.Index; BYPASS — доля глушения 0…1).
public struct MixBlend: Equatable, Sendable {
    public var globals: MixGlobals
    public var master: [Double]
}

extension MixTransition {
    /// Положение кроссфейдера t (0 — OLD, 1 — NEW).
    public func blend(_ t0: Double) -> MixBlend {
        let t: Double = Swift.max(0, Swift.min(1, t0))
        let a = from
        let b = to
        var g = b
        g.bpm = (MixTransition.lerp(a.bpm, b.bpm, t) * 10).rounded() / 10
        let n = Swift.max(a.vols.count, b.vols.count)
        g.vols = (0..<n).map { i in MixTransition.lerp(MixTransition.at(a.vols, i, b.vols), MixTransition.at(b.vols, i, a.vols), t) }
        g.trims = (0..<n).map { i in MixTransition.lerp(MixTransition.at(a.trims, i, b.trims), MixTransition.at(b.trims, i, a.trims), t) }
        g.outVol = MixTransition.lerp(a.outVol, b.outVol, t)
        g.master = MixTransition.blendMaster(a.master, b.master, t)
        g.satBypass = t < 0.5 ? a.satBypass : b.satBypass
        g.cmpBypass = t < 0.5 ? a.cmpBypass : b.cmpBypass
        g.clipBypass = t < 0.5 ? a.clipBypass : b.clipBypass
        g.limBypass = t < 0.5 ? a.limBypass : b.limBypass
        g.masterEq = MixTransition.blendEq(a.masterEq, b.masterEq, t)
        if t <= 0 { g = a }
        if t >= 1 { g = b }
        // Параметры колбэка: из смеси, BYPASS — плавно.
        var p = Project()
        p.tracks = []
        g.apply(to: &p)
        var m = [Double](repeating: 0, count: MasterChain.Index.count)
        m.withUnsafeMutableBufferPointer { MasterChain.fill($0.baseAddress!, p) }
        let I = MasterChain.Index.self
        let byp = { (x: Bool, y: Bool) -> Double in MixTransition.lerp(x ? 1 : 0, y ? 1 : 0, t) }
        var sat: Double = byp(a.satBypass, b.satBypass)
        let ta: Double = a.master["sat.type"] ?? 0
        let tb: Double = b.master["sat.type"] ?? 0
        if ta != tb {
            // Разный TYPE: к середине — сухой сигнал, на середине TYPE меняется, дальше — обратно.
            let v: Double = abs(1 - 2 * t)
            sat = 1 - (1 - sat) * v
            m[I.satType] = t < 0.5 ? ta : tb
        }
        m[I.satBypass] = sat
        m[I.cmpBypass] = byp(a.cmpBypass, b.cmpBypass)
        m[I.clipBypass] = byp(a.clipBypass, b.clipBypass)
        m[I.limBypass] = byp(a.limBypass, b.limBypass)
        // У краёв — ровно настройки проекта.
        if t <= 0 || t >= 1 {
            var q = Project()
            q.tracks = []
            (t <= 0 ? a : b).apply(to: &q)
            m.withUnsafeMutableBufferPointer { MasterChain.fill($0.baseAddress!, q) }
        }
        return MixBlend(globals: g, master: m)
    }

    static func lerp(_ x: Double, _ y: Double, _ t: Double) -> Double {
        return x + (y - x) * t
    }

    static func at(_ v: [Double], _ i: Int, _ other: [Double]) -> Double {
        if i < v.count { return v[i] }
        return i < other.count ? other[i] : 0
    }

    /// Параметры мастера: числа — плавно; RELEASE AUTO с одной стороны и TYPE сатуратора — на середине
    /// (TYPE звучит через сухой сигнал — см. blend).
    static func blendMaster(_ a: [String: Double], _ b: [String: Double], _ t: Double) -> [String: Double] {
        var out: [String: Double] = [:]
        for (id, _) in MasterChain.ids {
            let x: Double = a[id] ?? b[id] ?? 0
            let y: Double = b[id] ?? x
            let auto: Bool = x >= MasterChain.autoValue || y >= MasterChain.autoValue
            if id == "sat.type" || auto {
                out[id] = t < 0.5 ? x : y
            } else {
                out[id] = lerp(x, y, t)
            }
        }
        return out
    }

    /// EQ мастера: полоса, которая есть в обоих (тот же тип, крутизна, M/S), меняет частоту, усиление и Q; полоса
    /// с одной стороны вводится и выводится — bell и shelf усилением от 0 dB, cut и notch частотой от края;
    /// разные полосы на одном месте — старая выводится к середине, новая вводится после неё.
    static func blendEq(_ a: Eq, _ b: Eq, _ t: Double) -> Eq {
        var out = Eq()
        out.on = a.on || b.on
        for k in 0..<EqSpec.bands {
            let x: EqBand? = a.on ? a.band(k).flatMap { $0.on ? $0 : nil } : nil
            let y: EqBand? = b.on ? b.band(k).flatMap { $0.on ? $0 : nil } : nil
            if let x = x, let y = y {
                if x.type == y.type && x.slope == y.slope && x.ms == y.ms {
                    var r: EqBand = t < 0.5 ? x : y
                    r.freq = geo(x.freq, y.freq, t)
                    r.gain = lerp(x.gain, y.gain, t)
                    r.q = geo(x.q, y.q, t)
                    out.bands[k] = r
                } else {
                    out.bands[k] = t < 0.5 ? fade(x, 2 * t) : fade(y, 2 - 2 * t)
                }
            } else if let x = x {
                out.bands[k] = fade(x, t)
            } else if let y = y {
                out.bands[k] = fade(y, 1 - t)
            }
        }
        return out
    }

    /// Полоса, выведенная на долю u (0 — как есть, 1 — не слышна).
    static func fade(_ b: EqBand, _ u: Double) -> EqBand {
        var r = b
        if EqSpec.hasGain(b.type) {
            r.gain = b.gain * (1 - u)
        } else {
            r.freq = geo(b.freq, edge(b), u)
        }
        return r
    }

    /// Край, за которым cut и notch не слышны: low cut — 20 Гц, high cut — 20 кГц, notch — ближайший.
    static func edge(_ b: EqBand) -> Double {
        if b.type == EqSpec.lowCut { return EqSpec.freqMin }
        if b.type == EqSpec.highCut { return EqSpec.freqMax }
        let mid: Double = (EqSpec.freqMin * EqSpec.freqMax).squareRoot()
        return b.freq < mid ? EqSpec.freqMin : EqSpec.freqMax
    }

    static func geo(_ x: Double, _ y: Double, _ t: Double) -> Double {
        if x <= 0 || y <= 0 { return lerp(x, y, t) }
        return x * pow(y / x, t)
    }
}
