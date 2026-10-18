import Foundation

// Таблицы Drive и 4× оверсэмплера — как при загрузке public/oversampler.js и public/drive-worklet.js:
// ядро FIR (окно Кайзера) и его фазы, антипроизводные tanh и FUZZ (Симпсон, шаг 1/32 до 12), компенсация громкости
// по типу и DRIVE (шаг 0,1 dB). Строятся один раз (shared — при создании первого Drive, вне колбэка);
// Drive читает их через указатели.

public final class DriveTables: @unchecked Sendable {
    // Оверсэмплер (oversampler.js).
    static let oversample = 4
    static let firLen = 129
    static let kaiserBeta: Double = 9
    static let phaseLen = 33
    static let ph0Delay = 16
    static let decC = 64
    // Drive (DRIVE_CONST).
    static let driveDb: Double = 36
    static let tubeBias: Double = 0.35
    static let refPeak: Double = 0.25
    static let foldHarm = 12
    static let foldTrimDb: Double = 0.4
    static let compStepDb: Double = 0.1
    static let tableMax: Double = 12
    static let tableStep: Double = 1.0 / 32
    /// Отсчётов таблицы антипроизводной (12 / (1/32)).
    static let tableN = 384
    /// Шагов компенсации (36 / 0,1).
    static let compN = 360

    public static let shared = DriveTables()

    /// Фазы 1–3 интерполятора (по 33 отвода, усиление 4); фаза 0 — задержка на 16 с усилением ph0Gain.
    let phases: UnsafeMutablePointer<Double>
    let ph0Gain: Double
    /// Децимация: половина симметричного ядра (64) и центр.
    let decHalf: UnsafeMutablePointer<Double>
    let decMid: Double
    /// Антипроизводные (F) и значения (D) tanh и FUZZ на [0, 12] (tableN + 2).
    let tanhF: UnsafeMutablePointer<Double>
    let tanhD: UnsafeMutablePointer<Double>
    let fuzzF: UnsafeMutablePointer<Double>
    let fuzzD: UnsafeMutablePointer<Double>
    let tanhMax: Double
    let fuzzMax: Double
    /// tanh(bias), 1 − tanh², F(bias) — для TUBE.
    let tb: Double
    let td: Double
    let lcB: Double
    /// Компенсация громкости: 5 типов × (compN + 2).
    let comp: UnsafeMutablePointer<Double>

    init() {
        // Ядро ФНЧ на Найквисте исходной частоты (окно Кайзера), в отсчётах 4× частоты.
        let n = DriveTables.firLen
        var h = [Double](repeating: 0, count: n)
        let c: Double = Double(n - 1) / 2
        let fc: Double = 0.5 / Double(DriveTables.oversample)
        var sum: Double = 0
        for k in 0..<n {
            let d: Double = Double(k) - c
            let sinc: Double = d == 0 ? 2 * fc : sin(2 * Double.pi * fc * d) / (Double.pi * d)
            let r: Double = d / c
            let w: Double = DriveTables.besselI0(DriveTables.kaiserBeta * sqrt(Swift.max(0, 1 - r * r)))
                / DriveTables.besselI0(DriveTables.kaiserBeta)
            h[k] = sinc * w
            sum += h[k]
        }
        for k in 0..<n { h[k] /= sum }
        let pl = DriveTables.phaseLen
        phases = UnsafeMutablePointer<Double>.allocate(capacity: 4 * pl)
        phases.initialize(repeating: 0, count: 4 * pl)
        for p in 0..<4 {
            var k = p, j = 0
            while k < n {
                phases[p * pl + j] = h[k] * 4
                k += 4
                j += 1
            }
        }
        ph0Gain = h[(n - 1) / 2] * 4
        decHalf = UnsafeMutablePointer<Double>.allocate(capacity: DriveTables.decC)
        for j in 0..<DriveTables.decC { decHalf[j] = h[j] }
        decMid = h[DriveTables.decC]
        // Антипроизводные.
        let tn = DriveTables.tableN
        tanhF = UnsafeMutablePointer<Double>.allocate(capacity: tn + 2)
        tanhD = UnsafeMutablePointer<Double>.allocate(capacity: tn + 2)
        fuzzF = UnsafeMutablePointer<Double>.allocate(capacity: tn + 2)
        fuzzD = UnsafeMutablePointer<Double>.allocate(capacity: tn + 2)
        DriveTables.makeTable(tanhF, tanhD) { tanh($0) }
        DriveTables.makeTable(fuzzF, fuzzD) { DriveTables.fuzzY($0) }
        tanhMax = tanhF[tn]
        fuzzMax = fuzzF[tn]
        tb = tanh(DriveTables.tubeBias)
        td = 1 - tb * tb
        lcB = DriveTables.tableF(tanhF, tanhD, tanhMax, DriveTables.tubeBias)
        // Компенсация громкости.
        let cn = DriveTables.compN + 2
        comp = UnsafeMutablePointer<Double>.allocate(capacity: 5 * cn)
        comp.initialize(repeating: 0, count: 5 * cn)
        let tbv = tb, tdv = td
        let shapes: [(Double) -> Double] = [
            { tanh($0) },
            { $0 > 1 ? 1 : ($0 < -1 ? -1 : $0) },
            { (tanh($0 + DriveTables.tubeBias) - tbv) / tdv },
            { DriveTables.fuzzY($0) },
            { sin($0) },
        ]
        for type in 0..<5 { DriveTables.makeComp(comp + type * cn, type, shapes[type]) }
    }

    static func besselI0(_ x: Double) -> Double {
        var s: Double = 1
        var t: Double = 1
        for k in 1..<30 {
            t *= pow(x / (2 * Double(k)), 2)
            s += t
        }
        return s
    }

    static func fuzzY(_ u: Double) -> Double { return u < 0 ? -(1 - exp(u)) : 1 - exp(-u) }

    /// Таблица антипроизводной нечётной кривой y на [0, 12] (Симпсон по ячейке) и её значений (для Эрмита).
    static func makeTable(_ F: UnsafeMutablePointer<Double>, _ D: UnsafeMutablePointer<Double>, _ y: (Double) -> Double) {
        let n = tableN
        let st: Double = tableStep
        F.initialize(repeating: 0, count: n + 2)
        D.initialize(repeating: 0, count: n + 2)
        for i in 0...n {
            D[i] = y(Double(i) * st)
            if i == 0 { continue }
            let a: Double = Double(i - 1) * st
            let m = 16
            let hh: Double = st / Double(m)
            var s: Double = y(a) + y(a + st)
            for k in 1..<m { s += Double(k % 2 == 1 ? 4 : 2) * y(a + Double(k) * hh) }
            F[i] = F[i - 1] + (s * hh) / 3
        }
        F[n + 1] = F[n]
        D[n + 1] = D[n]
    }

    /// F(|u|) по таблице (кубический Эрмит); за 12 кривая ≈ 1 — F растёт линейно.
    static func tableF(_ F: UnsafeMutablePointer<Double>, _ D: UnsafeMutablePointer<Double>, _ fmax: Double,
                       _ u: Double) -> Double {
        let a: Double = u < 0 ? -u : u
        if a >= tableMax { return fmax + (a - tableMax) }
        let x: Double = a * 32
        let i = Int(x)
        let t: Double = x - Double(i), t2: Double = t * t, t3: Double = t2 * t
        let h: Double = tableStep
        return (2 * t3 - 3 * t2 + 1) * F[i] + (t3 - 2 * t2 + t) * h * D[i] + (-2 * t3 + 3 * t2) * F[i + 1]
            + (t3 - t2) * h * D[i + 1]
    }

    /// Оставить в периоде v (P отсчётов) только гармоники 1…H (ряд Фурье).
    static func bandLimit(_ v: inout [Double], _ H: Int) {
        let P = v.count
        var cs = [Double](repeating: 0, count: P)
        var sn = [Double](repeating: 0, count: P)
        for k in 0..<P {
            cs[k] = cos(2 * Double.pi * Double(k) / Double(P))
            sn[k] = sin(2 * Double.pi * Double(k) / Double(P))
        }
        var a = [Double](repeating: 0, count: H + 1)
        var b = [Double](repeating: 0, count: H + 1)
        for h in 1...H {
            var sa: Double = 0, sb: Double = 0
            var j = 0
            for k in 0..<P {
                sa += v[k] * cs[j]
                sb += v[k] * sn[j]
                j = (j + h) % P
            }
            a[h] = (2 * sa) / Double(P)
            b[h] = (2 * sb) / Double(P)
        }
        for k in 0..<P {
            var s: Double = 0
            var j = k
            for h in 1...H {
                s += a[h] * cs[j] + b[h] * sn[j]
                j = (j + k) % P
            }
            v[k] = s
        }
    }

    /// Компенсация громкости типа: синус refPeak · g через кривую, постоянная составляющая убрана;
    /// c = √(пик-отношение · RMS-отношение).
    static func makeComp(_ t: UnsafeMutablePointer<Double>, _ type: Int, _ f: (Double) -> Double) {
        let P = 1024
        let rIn: Double = refPeak / 1.4142135623730951
        for i in 0...compN {
            let g: Double = pow(10, (Double(i) * compStepDb) / 20)
            var v = [Double](repeating: 0, count: P)
            var mean: Double = 0
            for k in 0..<P {
                v[k] = f(refPeak * g * sin(2 * Double.pi * Double(k) / Double(P)))
                mean += v[k]
            }
            mean /= Double(P)
            var pk: Double = 0, ss: Double = 0
            for k in 0..<P {
                let d: Double = v[k] - mean
                pk = Swift.max(pk, abs(d))
                ss += d * d
            }
            if type == 4 {
                bandLimit(&v, foldHarm)
                ss = 0
                for k in 0..<P { ss += v[k] * v[k] }
            }
            t[i] = sqrt((pk / refPeak) * (sqrt(ss / Double(P)) / rIn)) * (type == 4 ? pow(10, foldTrimDb / 20) : 1)
        }
        t[compN + 1] = t[compN]
    }
}
