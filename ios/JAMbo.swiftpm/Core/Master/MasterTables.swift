import Foundation

// Таблицы мастера — как при загрузке public/saturator-worklet.js и public/limiter-worklet.js. Оверсэмплер 4× и
// антипроизводная tanh — общие с Drive (DriveTables: тот же oversampler.js и та же таблица Симпсона); здесь —
// антипроизводная EDGE, компенсация громкости сатуратора (3 типа × шаг 0,1 dB до 24 dB) и FIR true peak лимитера
// (окно Блэкмана, фазы Float32, как Float32Array веба). Строятся один раз (shared, вне колбэка).

public final class MasterTables: @unchecked Sendable {
    static let tubeBias: Double = 0.35
    static let refPeak: Double = 0.25
    static let maxDriveDb: Double = 24
    static let compStepDb: Double = 0.1
    /// Шагов компенсации (24 / 0,1).
    static let compN = 240
    /// Лимитер: отводов на фазу и задержка FIR (центр ядра, входных отсчётов).
    static let limTaps = 12
    static let limFirDelay = 6

    public static let shared = MasterTables()

    let d: DriveTables
    /// Антипроизводная (F) и значения (D) EDGE на [0, 12].
    let edgeF: UnsafeMutablePointer<Double>
    let edgeD: UnsafeMutablePointer<Double>
    let edgeMax: Double
    /// Компенсация сатуратора: 3 типа × (compN + 2).
    let comp: UnsafeMutablePointer<Double>
    /// Фазы true peak лимитера: 4 × 12 (значения Float32, хранятся как Double).
    let limPhases: UnsafeMutablePointer<Double>

    init(drive: DriveTables = .shared) {
        d = drive
        let tn = DriveTables.tableN
        edgeF = UnsafeMutablePointer<Double>.allocate(capacity: tn + 2)
        edgeD = UnsafeMutablePointer<Double>.allocate(capacity: tn + 2)
        DriveTables.makeTable(edgeF, edgeD) { MasterTables.edgeY($0) }
        edgeMax = edgeF[tn]
        let cn = MasterTables.compN + 2
        comp = UnsafeMutablePointer<Double>.allocate(capacity: 3 * cn)
        comp.initialize(repeating: 0, count: 3 * cn)
        let tb: Double = drive.tb, td: Double = drive.td
        let shapes: [(Double) -> Double] = [
            { tanh($0) },
            { (tanh($0 + MasterTables.tubeBias) - tb) / td },
            { MasterTables.edgeY($0) },
        ]
        for t in 0..<3 { MasterTables.makeComp(comp + t * cn, shapes[t]) }
        limPhases = UnsafeMutablePointer<Double>.allocate(capacity: 4 * MasterTables.limTaps)
        MasterTables.makeLimFir(limPhases)
    }

    static func edgeY(_ u: Double) -> Double { return u / sqrt(sqrt(1 + u * u * u * u)) }

    /// Кривая окна сатуратора (TRANSFER, curveFn веба без BIAS и OUTPUT): выход нелинейности type при входе x и DRIVE
    /// driveDb, делённый на компенсацию громкости c (та же таблица, что в колбэке). Без TONE и MIX.
    public func satCurve(_ type: Int, driveDb: Double, _ x: Double) -> Double {
        let top: Double = Double(MasterTables.compN) * MasterTables.compStepDb
        let dB: Double = Swift.max(0, Swift.min(top, driveDb))
        let g: Double = pow(10, dB / 20)
        let ci: Double = dB / MasterTables.compStepDb
        let i0: Int = Swift.min(MasterTables.compN, Int(ci.rounded(.down)))
        let fr: Double = ci - Double(i0)
        let tp: Int = Swift.max(0, Swift.min(2, type))
        let base: Int = tp * (MasterTables.compN + 2)
        let c: Double = comp[base + i0] + (comp[base + i0 + 1] - comp[base + i0]) * fr
        let u: Double = x * g
        var y: Double = MasterTables.edgeY(u)
        if tp == 0 { y = tanh(u) }
        if tp == 1 { y = (tanh(u + MasterTables.tubeBias) - d.tb) / d.td }
        return y / Swift.max(1e-9, c)
    }

    /// c = пик выхода кривой на синусе refPeak · g (постоянная составляющая убрана), делённый на refPeak.
    static func makeComp(_ t: UnsafeMutablePointer<Double>, _ f: (Double) -> Double) {
        let P = 512
        for i in 0...compN {
            let g: Double = pow(10, (Double(i) * compStepDb) / 20)
            var v = [Double](repeating: 0, count: P)
            var mean: Double = 0
            for k in 0..<P {
                v[k] = f(refPeak * g * sin((2 * Double.pi * Double(k)) / Double(P)))
                mean += v[k]
            }
            mean /= Double(P)
            var pk: Double = 0
            for k in 0..<P { pk = Swift.max(pk, abs(v[k] - mean)) }
            t[i] = pk / refPeak
        }
        t[compN + 1] = t[compN]
    }

    /// Полифазный FIR лимитера: окно Блэкмана × sinc, каждая фаза нормирована к 1 (в Float32, как в вебе).
    static func makeLimFir(_ out: UnsafeMutablePointer<Double>) {
        let taps = limTaps
        let n = 4 * taps
        let c = 4 * (taps / 2)
        var h = [Double](repeating: 0, count: n)
        for k in 0..<n {
            let dd = Double(k - c)
            let x: Double = dd / 4
            let sinc: Double = x == 0 ? 1 : sin(Double.pi * x) / (Double.pi * x)
            let r: Double = (Double.pi * dd) / Double(c + 1)
            let w: Double = 0.42 + 0.5 * cos(r) + 0.08 * cos(2 * r)
            h[k] = sinc * w
        }
        for p in 0..<4 {
            var f = [Float](repeating: 0, count: taps)
            var sum: Double = 0
            for j in 0..<taps {
                f[j] = Float(h[j * 4 + p])
                sum += Double(f[j])
            }
            for j in 0..<taps { out[p * taps + j] = Double(Float(Double(f[j]) / sum)) }
        }
    }
}
