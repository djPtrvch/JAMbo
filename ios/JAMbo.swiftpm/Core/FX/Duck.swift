import Foundation

// Sidechain — перенос public/duck-worklet.js 1:1: огибающая приглушения e (0…1; 1 — полное приглушение), один экземпляр
// на проект, входа нет. Громкость дорожки = 1 − amount·e (amount — ручка 3.4 Sidechain, у источника 0).
// Триги источника приходят заранее (trig: кадр, attack, release, curve) и ждут в очереди по кадру; flush — остановка:
// будущие триги отменяются (текущий возврат досчитывается). Attack — линейно от текущего e до 1 за max(1 мс, ATTACK)
// (повторный триг — с текущего e), release — (1 − u)^q за RELEASE, q = 2·4^((50 − CURVE)/50); после RELEASE e = 0.
// Очередь — фиксированный массив (без выделений в колбэке).

public final class FxDuck {
    static let minAttackMs: Double = 1
    static let qBase: Double = 2
    static let qRange: Double = 4
    static let reportFrames = 512
    static let reportFloor: Double = 0.001
    static let maxQueue = 256

    let sr: Double
    /// Текущее e.
    public private(set) var e: Double = 0
    var stage = 0
    var pos: Double = 0
    var e0: Double = 0
    var A: Double = 1
    var R: Double = 1
    var q: Double = 2
    // Очередь тригов по кадру: кадр, attack (мс), release (мс), curve (0…100).
    let qFrame = UnsafeMutablePointer<Int64>.allocate(capacity: FxDuck.maxQueue)
    let qAttack = UnsafeMutablePointer<Double>.allocate(capacity: FxDuck.maxQueue)
    let qRelease = UnsafeMutablePointer<Double>.allocate(capacity: FxDuck.maxQueue)
    let qCurve = UnsafeMutablePointer<Double>.allocate(capacity: FxDuck.maxQueue)
    var count = 0
    var sinceReport = 0
    var reported: Double = 0
    /// Индикация (как сообщение { e } веба): раз в 512 отсчётов, пока e > 0.001, и раз при возврате к 0.
    public private(set) var meter: Double = 0

    public init(sampleRate: Double) {
        sr = sampleRate
        qFrame.initialize(repeating: 0, count: FxDuck.maxQueue)
        qAttack.initialize(repeating: 0, count: FxDuck.maxQueue)
        qRelease.initialize(repeating: 0, count: FxDuck.maxQueue)
        qCurve.initialize(repeating: 0, count: FxDuck.maxQueue)
    }

    deinit {
        qFrame.deallocate()
        qAttack.deallocate()
        qRelease.deallocate()
        qCurve.deallocate()
    }

    /// Триг источника в кадре frame (вставка по кадру; переполнение — самый ранний выбрасывается).
    public func trig(frame: Int64, attack: Double, release: Double, curve: Double) {
        if count >= FxDuck.maxQueue { removeFirst() }
        var k = count
        while k > 0 && qFrame[k - 1] > frame {
            qFrame[k] = qFrame[k - 1]
            qAttack[k] = qAttack[k - 1]
            qRelease[k] = qRelease[k - 1]
            qCurve[k] = qCurve[k - 1]
            k -= 1
        }
        qFrame[k] = frame
        qAttack[k] = attack.isFinite ? attack : 0
        qRelease[k] = release.isFinite ? release : 0
        qCurve[k] = curve.isFinite ? curve : 50
        count += 1
    }

    /// Остановка: будущие триги отменяются.
    public func flush() { count = 0 }

    func removeFirst() {
        var k = 1
        while k < count {
            qFrame[k - 1] = qFrame[k]
            qAttack[k - 1] = qAttack[k]
            qRelease[k - 1] = qRelease[k]
            qCurve[k - 1] = qCurve[k]
            k += 1
        }
        count -= 1
    }

    /// Math.round: половина — вверх.
    static func jsRound(_ x: Double) -> Double { return (x + 0.5).rounded(.down) }

    /// Триг: attack с текущего e.
    func start(_ attack: Double, _ release: Double, _ curve: Double) {
        stage = 1
        pos = 0
        e0 = e
        A = Swift.max(1, FxDuck.jsRound((Swift.max(FxDuck.minAttackMs, attack) / 1000) * sr))
        R = Swift.max(1, FxDuck.jsRound((Swift.max(0, release) / 1000) * sr))
        let c: Double = Swift.min(100, Swift.max(0, curve))
        q = FxDuck.qBase * pow(FxDuck.qRange, (50 - c) / 50)
    }

    /// Блок n отсчётов с кадра f0: e в out (перезаписывает).
    public func process(blockStart f0: Int64, out: UnsafeMutablePointer<Float>, frames n: Int) {
        if stage == 0 && (count == 0 || qFrame[0] >= f0 + Int64(n)) {
            out.update(repeating: 0, count: n)
            return
        }
        var i = 0
        while i < n {
            // Триги этого отсчёта (опоздавшие — в первом отсчёте блока).
            while count > 0 && qFrame[0] <= f0 + Int64(i) {
                let a = qAttack[0], r = qRelease[0], c = qCurve[0]
                removeFirst()
                start(a, r, c)
            }
            var v: Double = e
            if stage == 1 {
                pos += 1
                v = e0 + (1 - e0) * Swift.min(1, pos / A)
                if pos >= A {
                    stage = 2
                    pos = 0
                    v = 1
                }
            } else if stage == 2 {
                pos += 1
                let u: Double = pos / R
                if u >= 1 {
                    v = 0
                    stage = 0
                } else {
                    v = pow(1 - u, q)
                }
            }
            if !(v >= 0) { v = 0 } else if v > 1 { v = 1 }
            e = v
            out[i] = Float(v)
            i += 1
        }
        report(n)
    }

    func report(_ n: Int) {
        sinceReport += n
        let due: Bool = e > FxDuck.reportFloor ? sinceReport >= FxDuck.reportFrames : reported > FxDuck.reportFloor
        if due {
            sinceReport = 0
            reported = e
            meter = e > FxDuck.reportFloor ? e : 0
        }
    }
}
