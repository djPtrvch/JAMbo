import Foundation

// Картинки FX в окне сэмпла (пока регулируют ручки FX, docs/ai/fx-eq.md «Анимация FX»): геометрия в долях 0…1
// и в единицах поля 64×64 (как иконки движков), рисует UI (FxPreview). Формы — по тем же формулам, что в звуке: кривые Drive (FxDrive.shapeY, CRUSH), возврат
// Duck (FxDuck: (1 − u)^q, q = 2·4^((50 − CURVE)/50)), частоты фильтров (Params.delayFilterFreq).

public enum FxPicture {
    // MARK: — поле и огибающая фильтра

    /// Поле картинки — как у иконок движков (EngineIcons, 64×64; иконки ударных — 4…60 × 6…58): по ширине 4…60,
    /// по высоте 6…58.
    public static let x0: Double = 4
    public static let x1: Double = 60
    public static let top: Double = 6
    public static let bottom: Double = 58
    /// Низ огибающей фильтра — −30 dB.
    public static let floorDb: Double = -30

    /// Доля ширины для частоты hz (лог 20 Гц — 20 кГц).
    public static func freqX(_ hz: Double) -> Double {
        let h: Double = Swift.min(20000, Swift.max(20, hz))
        return log(h / 20) / log(1000.0)
    }

    /// Срез: low — срез НЧ (HP), иначе срез ВЧ (LP); hz — частота среза.
    public struct Cut: Equatable {
        public let low: Bool
        public let hz: Double
        public var x: Double { return FxPicture.freqX(hz) }
    }

    /// LOW CUT реверба (20–2000 Гц): на 20 Гц — без среза.
    public static func reverbCut(_ hpf: Double) -> Cut? {
        if hpf <= 20.5 { return nil }
        return Cut(low: true, hz: hpf)
    }

    /// FILTER дилея: влево LP (срез ВЧ), вправо HP (срез НЧ), в центре OFF.
    public static func delayCut(_ v: Double) -> Cut? {
        let f = Params.delayFilterFreq(v)
        if f.type == 0 { return nil }
        return Cut(low: f.type > 0, hz: f.hz)
    }

    /// LOW CUT Drive: ≤ 25 Гц — OFF.
    public static func driveCut(_ hz: Double) -> Cut? {
        if hz <= Params.driveLowCutOff { return nil }
        return Cut(low: true, hz: hz)
    }

    /// Ослабление (dB, ≤ 0) фильтра 2-го порядка (Баттерворт, как RBJ с Q = 1/√2) на частоте f.
    public static func cutDb(_ c: Cut, _ f: Double) -> Double {
        let r: Double = c.low ? f / c.hz : c.hz / f
        let r4: Double = r * r * r * r
        return 10 * log10(r4 / (1 + r4))
    }

    /// Огибающая фильтра в единицах поля: n + 1 точек (x, y) слева направо; 0 dB — верх поля, −30 dB и ниже — низ.
    public static func cutEnvelope(_ c: Cut, _ n: Int = 112) -> [(x: Double, y: Double)] {
        var out: [(x: Double, y: Double)] = []
        out.reserveCapacity(n + 1)
        for i in 0...n {
            let u: Double = Double(i) / Double(n)
            let f: Double = 20 * pow(1000, u)
            let db: Double = Swift.max(floorDb, cutDb(c, f))
            out.append((x: x0 + (x1 - x0) * u, y: top + (bottom - top) * db / floorDb))
        }
        return out
    }

    // MARK: — Reverb

    /// Куб: размер (доля меньшей стороны), непрозрачность граней, число контуров DECAY и шаг между ними (доля размера).
    public struct Reverb: Equatable {
        public let size: Double
        public let fill: Double
        public let contours: Int
        public let spread: Double
    }

    public static func reverb(size: Double, decay: Double, tone: Double) -> Reverb {
        let s: Double = Swift.min(1, Swift.max(0, size / 100))
        let d: Double = log(Swift.min(20, Swift.max(0.1, decay)) / 0.1) / log(200.0)
        let t: Double = Swift.min(1, Swift.max(0, (tone + 100) / 200))
        let n: Int = Int((d * 6).rounded())
        return Reverb(size: 0.25 + 0.3 * s, fill: 0.08 + 0.62 * t, contours: n, spread: 0.06 + 0.1 * d)
    }

    // MARK: — Delay

    /// Повтор: x — доля ширины, h — высота (доля), a — яркость, side — сдвиг линии по SPREAD: −1 вверх (L), +1 вниз (R).
    public struct Echo: Equatable {
        public let x: Double
        public let h: Double
        public let a: Double
        public let side: Int
    }

    /// Шаг TIME в долях ширины: ступени по темпу — по логарифму длительности (1/32 … 1 bar), свободно — по ходу ручки
    /// (он уже логарифмический по мс).
    public static func delayStep(time: Double, synced: Bool) -> Double {
        let t: Double
        if synced {
            let k: Int = Swift.min(Params.delayDivs.count - 1, Swift.max(0, Int(time.rounded())))
            t = log(Params.delayDivs[k].beats / 0.125) / log(32.0)
        } else {
            t = Swift.min(1, Swift.max(0, time / Params.dlyFreeTop))
        }
        return 0.05 + 0.4 * t
    }

    /// Повторы, которые помещаются: первый — полной высоты, каждый следующий × FEEDBACK (при 100 % — почти той же
    /// высоты); тише 3 % не рисуются.
    public static func delayEchoes(time: Double, synced: Bool, feedback: Double) -> [Echo] {
        let dx: Double = delayStep(time: time, synced: synced)
        let fb: Double = Swift.min(0.97, Swift.max(0, feedback / 100))
        var out: [Echo] = []
        var x: Double = dx
        var h: Double = 1
        var k: Int = 0
        while x <= 1.0001 && h >= 0.03 && out.count < 40 {
            out.append(Echo(x: x, h: h, a: 0.25 + 0.75 * h, side: k % 2 == 0 ? -1 : 1))
            x += dx
            h *= fb
            k += 1
        }
        return out
    }

    // MARK: — Drive

    /// Отсчётов на рисунок (два периода): CRUSH держит отсчёт по-настоящему (повтор до 16 отсчётов), поэтому период —
    /// 64 отсчёта; остальным — гуще (FOLD на большом DRIVE складывается много раз).
    public static let crushPoints = 128
    public static let drivePoints = 600
    /// Уровень синуса на входе (−6 dBFS).
    public static let driveInput: Double = 0.5
    static let tubeBias: Double = 0.35

    /// Кривая TYPE 0–4 (как FxDrive.shapeY).
    public static func shape(_ type: Int, _ u: Double) -> Double {
        switch type {
        case 0: return tanh(u)
        case 1: return u > 1 ? 1 : (u < -1 ? -1 : u)
        case 2:
            let tb: Double = tanh(tubeBias)
            return (tanh(u + tubeBias) - tb) / (1 - tb * tb)
        case 3: return u < 0 ? -(1 - exp(u)) : 1 - exp(-u)
        default: return sin(u)
        }
    }

    /// Два периода синуса через TYPE и DRIVE, значения −1…1 (TUBE ужат до ±1).
    public static func driveWave(type: Int, drive: Double) -> [Double] {
        let D: Double = Swift.min(1, Swift.max(0, drive / 100))
        if type >= 5 { return crushWave(D) }
        let g: Double = pow(10, 36 * D / 20)
        let n: Int = drivePoints
        // Низ TUBE — (−1 − tb)/(1 − tb²) ≈ −1,51: ужат ровно до −1.
        let tb: Double = tanh(tubeBias)
        let scale: Double = type == 2 ? (1 - tb * tb) / (1 + tb) : 1
        var out: [Double] = []
        out.reserveCapacity(n + 1)
        for i in 0...n {
            let x: Double = driveInput * sin(4 * Double.pi * Double(i) / Double(n))
            out.append(shape(type, g * x) * scale)
        }
        return out
    }

    /// CRUSH (как в FxDrive): квантование шагом 2^(1 − B), B = 12 − 9·D, повтор отсчёта 1 + round(15·D²).
    static func crushWave(_ D: Double) -> [Double] {
        let step: Double = pow(2, 1 - (12 - 9 * D))
        let hold: Int = 1 + Int((15 * D * D + 0.5).rounded(.down))
        let n: Int = crushPoints
        var out: [Double] = []
        out.reserveCapacity(n + 1)
        var q: Double = 0
        var left: Int = 0
        for i in 0...n {
            if left <= 0 {
                let x: Double = driveInput * sin(4 * Double.pi * Double(i) / Double(n))
                q = step * (x / step + 0.5).rounded(.down)
                if q > 1 - step { q = 1 - step } else if q < -1 { q = -1 }
                left = hold
            }
            left -= 1
            out.append(q)
        }
        return out
    }

    /// Чистый синус для сравнения (те же два периода).
    public static func cleanWave(_ n: Int) -> [Double] {
        return (0...n).map { i in driveInput * sin(4 * Double.pi * Double(i) / Double(n)) }
    }

    // MARK: — Duck

    /// Раскладка огибающей по ширине (доли): ровно до a0, спуск до a1, возврат до r1, дальше ровно. Ось нелинейная:
    /// ширина спуска — по логарифму ATTACK (0,1–100 мс), возврата — по логарифму RELEASE (10–1000 мс).
    public struct Duck: Equatable {
        public let a0: Double
        public let a1: Double
        public let r1: Double
        public let q: Double
    }

    public static func duck(attack: Double, release: Double, curve: Double) -> Duck {
        let a: Double = log(Swift.min(100, Swift.max(0.1, attack)) / 0.1) / log(1000.0)
        let r: Double = log(Swift.min(1000, Swift.max(10, release)) / 10) / log(100.0)
        let a0: Double = 0.08
        let a1: Double = a0 + 0.04 + 0.22 * a
        let r1: Double = a1 + 0.2 + 0.46 * r
        let c: Double = curve.isFinite ? curve : 50
        let q: Double = 2 * pow(4, (50 - c) / 50)
        return Duck(a0: a0, a1: a1, r1: r1, q: q)
    }

    /// Громкость 0…1 в доле ширины x (спуск — прямая, как нарастание e; возврат — 1 − (1 − u)^q).
    public static func duckVolume(_ d: Duck, _ x: Double) -> Double {
        if x <= d.a0 { return 1 }
        if x < d.a1 { return 1 - (x - d.a0) / (d.a1 - d.a0) }
        if x < d.r1 {
            let u: Double = (x - d.a1) / (d.r1 - d.a1)
            return 1 - pow(1 - u, d.q)
        }
        return 1
    }

    /// Точка Duck: доля ширины в момент t (с): проход за 1,6 с, пауза вверху 0,4 с.
    public static let duckRun: Double = 1.6
    public static let duckPause: Double = 0.4

    public static func duckDot(_ t: Double) -> Double {
        let p: Double = duckRun + duckPause
        let f: Double = t - p * (t / p).rounded(.down)
        return f >= duckRun ? 0 : f / duckRun
    }
}
