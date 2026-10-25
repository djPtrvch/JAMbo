import Foundation

// Цепочка мастера (как engine.ts веба): сумма дорожек и эффектов → EQ мастера → сатуратор → компрессор →
// клиппер → лимитер → громкость выхода. Параметры — плоский массив Double в порядке MasterChain.Index
// (колбэк не читает Swift-коллекции): из снимка звука (Project.master) или из самотеста. BYPASS сатуратора — MIX 0
// (как sendDynamics веба), у остальных — свой кроссфейд 10 мс. Всё в колбэке: буферы выделены при создании.

public final class MasterChain {
    /// Номера параметров в массиве значений.
    public enum Index {
        public static let satDrive = 0, satType = 1, satTone = 2, satMix = 3, satFocus = 4, satBypass = 5
        public static let cmpThr = 6, cmpAtt = 7, cmpRel = 8, cmpAuto = 9, cmpMakeup = 10, cmpRatio = 11, cmpKnee = 12
        public static let cmpMix = 13, cmpSchpf = 14, cmpBypass = 15
        public static let clipDrive = 16, clipCeiling = 17, clipSoftness = 18, clipBass = 19, clipBypass = 20
        public static let limGain = 21, limCeiling = 22, limLookahead = 23, limRel = 24, limAuto = 25, limBypass = 26
        /// Громкость выхода — усиление (Params.volGain).
        public static let outGain = 27
        public static let count = 28
    }

    /// Значения по умолчанию (как ручки и поля веба; bypass выключены).
    public static let defaults: [Double] = [
        0, 0, 0, 100, 20, 0,
        -10, 10, 400, 0, 0, 2, 6, 100, 90, 0,
        0, -1, 30, 0, 0,
        0, -1, 3, 150, 0, 0,
        1,
    ]

    /// Параметры мастера в проекте (id как в вебе) и их номера; RELEASE компрессора и лимитера ≥ autoValue — AUTO
    /// (как AUTO_VALUE в params.ts).
    public static let ids: [(id: String, index: Int)] = [
        ("sat.drive", Index.satDrive), ("sat.type", Index.satType), ("sat.tone", Index.satTone),
        ("sat.mix", Index.satMix), ("sat.focus", Index.satFocus),
        ("cmp.threshold", Index.cmpThr), ("cmp.attack", Index.cmpAtt), ("cmp.release", Index.cmpRel),
        ("cmp.makeup", Index.cmpMakeup), ("cmp.ratio", Index.cmpRatio), ("cmp.knee", Index.cmpKnee),
        ("cmp.mix", Index.cmpMix), ("cmp.schpf", Index.cmpSchpf),
        ("clip.drive", Index.clipDrive), ("clip.ceiling", Index.clipCeiling), ("clip.softness", Index.clipSoftness),
        ("clip.bass", Index.clipBass),
        ("lim.input", Index.limGain), ("lim.ceiling", Index.limCeiling), ("lim.lookahead", Index.limLookahead),
        ("lim.release", Index.limRel),
    ]
    public static let autoValue: Double = 1e9
    /// ATTACK компрессора нового проекта — 30 мс (решение пользователя; в вебе 10). Эталоны считаются от defaults веба.
    public static let newAttack: Double = 30
    /// RELEASE при AUTO (как sendDynamics веба: rel 400, auto true).
    static let autoRel: Double = 400

    public static func defaultValues() -> [String: Double] {
        var d: [String: Double] = [:]
        for (id, k) in ids { d[id] = defaults[k] }
        d["cmp.attack"] = newAttack
        return d
    }

    /// Значения проекта → массив параметров колбэка (основной поток, при построении снимка звука).
    static func fill(_ p: UnsafeMutablePointer<Double>, _ project: Project) {
        p.initialize(from: defaults, count: Index.count)
        for (id, k) in ids { if let v = project.master[id] { p[k] = v } }
        for (rel, auto) in [(Index.cmpRel, Index.cmpAuto), (Index.limRel, Index.limAuto)] where p[rel] >= autoValue {
            p[rel] = autoRel
            p[auto] = 1
        }
        p[Index.satBypass] = project.satBypass ? 1 : 0
        p[Index.cmpBypass] = project.cmpBypass ? 1 : 0
        p[Index.clipBypass] = project.clipBypass ? 1 : 0
        p[Index.limBypass] = project.limBypass ? 1 : 0
        p[Index.outGain] = Params.volGain(project.outVol)
    }

    public let sat: MasterSaturator
    public let glue: MasterGlue
    public let clip: MasterClipper
    public let lim: MasterLimiter
    public let eq: EqUnit
    /// Сдвиги динамических полос для экрана (ставит AudioCore).
    public var eqDyn: EqDynLevels?
    /// Прослушивание полосы EQ мастера (после EQ, до сатуратора).
    public var eqListen: EqListen?
    /// Кадры индикации COMP / CLIP / LIM.
    public let compTele = DynTele()
    public let clipTele = DynTele()
    public let limTele = DynTele()
    /// Точки съёма скопа (после SAT, COMP, CLIP, LIM; гониометр пишет AudioCore).
    public let scope = MasterScope()
    /// Спектр окна сатуратора: вход и выход сатуратора (моно), пишутся, только пока satOn ≠ 0 (окно SAT открыто).
    public let satIn = SpectrumTap()
    public let satOut = SpectrumTap()
    public let satOn = AtomicCounter()
    /// Точки съёма спектров EQ мастера (до и после EQ; ставит AudioCore).
    public var spectra: Spectra?
    /// Замеры колбэка по разделам (S14a; задаёт AudioCore): EQ мастера — в раздел EQ.
    public var profile: RenderProfile?

    /// Громкость выхода: текущее усиление (−1 — ещё не задано: сразу целевое) и шаг сглаживания (10 мс, как громкость
    /// дорожки в SamplerMix).
    private var outCur: Float = -1
    private let outK: Float

    public init(sampleRate: Double) {
        outK = Float(1 - exp(-1 / (0.01 * sampleRate)))
        sat = MasterSaturator(sampleRate: sampleRate)
        glue = MasterGlue(sampleRate: sampleRate)
        clip = MasterClipper(sampleRate: sampleRate)
        lim = MasterLimiter(sampleRate: sampleRate)
        eq = EqUnit(sampleRate: sampleRate)
    }

    /// Блок n отсчётов на месте (left, right), параметры p — MasterChain.Index, eqParams — EQ мастера (EqSpec.fill).
    public func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames n: Int,
                        params p: UnsafePointer<Double>, eqParams: UnsafePointer<Double>? = nil) {
        let I = Index.self
        if let e = eqParams {
            let shown: Bool = spectra?.channel.load() == EqSpec.masterChannel
            if shown, let s = spectra { s.pre.push(left, right, n) }
            eq.process(left: left, right: right, frames: n, params: e)
            eqDyn?.publish(EqSpec.masterChannel, eq)
            if shown, let s = spectra { s.post.push(left, right, n) }
            eqListen?.process(EqSpec.masterChannel, eq, n)
            profile?.lap(RenderProfile.eq)
        }
        let satShown: Bool = satOn.load() != 0
        if satShown { satIn.push(left, right, n) }
        sat.process(inL: left, inR: right, outL: left, outR: right, frames: n, drive: p[I.satDrive], type: p[I.satType],
                    tone: p[I.satTone], mix: p[I.satMix] * (1 - p[I.satBypass]), focus: p[I.satFocus])
        if satShown { satOut.push(left, right, n) }
        let sm: Int = scope.mask.load()
        scope.tap(MasterScope.sat, sm, left, right, n)
        glue.process(inL: left, inR: right, outL: left, outR: right, frames: n, thr: p[I.cmpThr], att: p[I.cmpAtt],
                     rel: p[I.cmpRel], auto: p[I.cmpAuto] >= 0.5, makeup: p[I.cmpMakeup], ratio: p[I.cmpRatio],
                     knee: p[I.cmpKnee], mix: p[I.cmpMix], schpf: p[I.cmpSchpf], bypass: p[I.cmpBypass])
        scope.tap(MasterScope.comp, sm, left, right, n)
        clip.process(inL: left, inR: right, outL: left, outR: right, frames: n, drive: p[I.clipDrive],
                     ceiling: p[I.clipCeiling], softness: p[I.clipSoftness], bass: p[I.clipBass],
                     bypass: p[I.clipBypass])
        scope.tap(MasterScope.clip, sm, left, right, n)
        lim.process(inL: left, inR: right, outL: left, outR: right, frames: n, gain: p[I.limGain],
                    ceiling: p[I.limCeiling], lookahead: p[I.limLookahead], rel: p[I.limRel], auto: p[I.limAuto] >= 0.5,
                    bypass: p[I.limBypass])
        scope.tap(MasterScope.lim, sm, left, right, n)
        applyOut(left, right, n, Float(p[I.outGain]))
        compTele.push(frames: glue.frames, inPeak: glue.frameIn, gr: glue.frameGr, outPeak: glue.frameOut, det: glue.frameDet)
        clipTele.push(frames: clip.frames, inPeak: clip.frameIn, gr: clip.frameGr, outPeak: clip.frameOut, det: -240)
        limTele.push(frames: lim.frames, inPeak: lim.frameIn, gr: lim.frameGr, outPeak: lim.frameOut, det: -240)
    }

    /// Громкость выхода (после лимитера, до гониометра и измерителя): плавно к цели; на цели и при 1 — без умножения.
    @inline(__always)
    private func applyOut(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int, _ target: Float) {
        var g: Float = outCur < 0 ? target : outCur
        let k: Float = outK
        if g == target {
            outCur = g
            if g == 1 { return }
            var i = 0
            while i < n {
                l[i] *= g
                r[i] *= g
                i += 1
            }
            return
        }
        var i = 0
        while i < n {
            g += (target - g) * k
            l[i] *= g
            r[i] *= g
            i += 1
        }
        // Остаток меньше 1e-6 — на цели (иначе умножение на каждом блоке навсегда).
        let rest: Float = target - g
        if rest < 1e-6 && rest > -1e-6 { g = target }
        outCur = g
    }
}
