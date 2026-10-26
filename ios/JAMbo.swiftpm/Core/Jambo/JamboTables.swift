import Foundation

// Свои движки JAMbo (как public/jambo-synth-worklet.js веба): константы и таблицы. Таблицы считаются один раз
// (вне колбэка) в Double, как JS, и хранятся во Float (как Float32Array в worklet).

enum Jambo {
    static let drum = 16
    static let analog = 17
    static let fm = 18
    static let wtable = 19
    /// Ударные (S12, этап 3).
    static let snare = 20
    static let hat = 21
    static let clap = 22
    static let perc = 23

    /// SUB (этап 4): моно-бас.
    static let sub = 24
    static let subOut = 0.58
    /// FAT: расстройка OSC2 до 35 центов.
    static let subFat = 35.0

    /// TEXTURE и GRANULAR (ТЗ «Texture и Granular»): моно (слот 0), стерео-выход.
    static let texture = 25
    static let granular = 26

    /// Монофоничный движок (слот 0): ударные (KICK, 20–23), SUB, TEXTURE и GRANULAR.
    @inline(__always) static func mono(_ e: Int) -> Bool { return e == drum || (e >= snare && e <= granular) }
    /// Стерео-выход движка (TEXTURE, GRANULAR): фильтр голоса по двум каналам, Pan — баланс.
    @inline(__always) static func stereo(_ e: Int) -> Bool { return e == texture || e == granular }

    // HAT: средний тон ряда 808 (геометрическое среднее шести частот), уровень выхода.
    static let hatMean = 416.4
    static let hatOut = 1.4
    // CLAP: интервал вспышек, мс; уровень выхода.
    static let clapGapMin = 2.0
    static let clapGapMax = 25.0
    static let clapOut = 2.4

    /// TONE CLAP: 700 → 3000 Гц, кривая x^1.69 (на 50 % ≈ 1.1 кГц).
    static func clapTone(_ n: Double) -> Double {
        return 700 * pow(3000.0 / 700, pow(Swift.min(1, Swift.max(0, n)), 1.69))
    }

    /// TUNE SNARE (120–400 Гц), HAT (±1 октава к 808), PERC (60 Гц–2 кГц) по ручке 0…1.
    static func snareTune(_ n: Double) -> Double { return 120 * pow(400.0 / 120, n) }
    static func percTune(_ n: Double) -> Double { return 60 * pow(2000.0 / 60, n) }

    /// Мода k набора PERC: 0 — мембрана, 1 — брусок, 2 — металл (808 cowbell 540 + 800 Гц и нечётные гармоники);
    /// отношение частоты и уровень. Без коллекций — зовётся в колбэке.
    @inline(__always) static func percMode(_ set: Int, _ k: Int) -> (r: Double, a: Double) {
        switch set * 6 + k {
        case 0: return (1, 1)
        case 1: return (1.59, 0.7)
        case 2: return (2.14, 0.5)
        case 3: return (2.30, 0.4)
        case 4: return (2.65, 0.3)
        case 5: return (2.92, 0.25)
        case 6: return (1, 1)
        case 7: return (2.76, 0.5)
        case 8: return (5.40, 0.3)
        case 9: return (8.93, 0.2)
        case 10: return (13.34, 0.1)
        case 11: return (18.64, 0.06)
        case 12: return (1, 1)
        case 13: return (1.4815, 0.9)
        case 14: return (3, 0.33)
        case 15: return (4.4444, 0.3)
        case 16: return (5, 0.2)
        default: return (7.4074, 0.18)
        }
    }

    /// Мода k PERC по MATERIAL m (0 — мембрана, 0.5 — брусок, 1 — металл; между — плавно, отношения — в логарифме)
    /// и уровень с учётом HIT (палка — ярче высокие моды).
    @inline(__always) static func percModeAt(_ m: Double, _ hit: Double, _ k: Int) -> (r: Double, a: Double) {
        let x = Swift.min(1, Swift.max(0, m))
        let set = x < 0.5 ? 0 : 1
        let u = x < 0.5 ? x * 2 : (x - 0.5) * 2
        let lo = percMode(set, k), hi = percMode(set + 1, k)
        let r = exp(log(lo.r) + (log(hi.r) - log(lo.r)) * u)
        let a = (lo.a + (hi.a - lo.a) * u) * pow(0.55 + 0.45 * hit, Double(k))
        return (r, a)
    }

    /// Кусок голоса (BLOCK worklet), кадров.
    static let block = 24
    /// Плавный вход новой ноты (кроме DRUM), кадров: ~1,3 мс.
    static let fadeIn = 64
    /// Сглаживание ручек при смене на лету, с.
    static let smooth = 0.005

    // DRUM
    static let drumPitchMin = 30.0
    static let drumPitchMax = 100.0
    static let drumT60 = 6.9
    static let drumDecayMax = 1000.0
    static let drumDeclick = 0.002
    /// Длина клика при CLICK 50 % (S12: CLICK 0 → 100 % — 3 → 1 мс).
    static let drumClick = 0.002
    static let drumSine = 0.7
    static let drumOut = 0.85

    // ANALOG
    static let analogDetune = 60.0
    static let analogDrift = 3.0
    static let analogDriftRate = 2.0
    static let analogOut = 0.62
    static let analogWaveXf = 0.005

    // WTABLE
    /// Расстройка UNISON до S12 (по ручке 1.3, 25…100 % → 0…40 центов) — для перевода старых проектов.
    static let wtUnisonOld = 40.0
    /// DETUNE (1.4, S12): 0 → 60 центов.
    static let wtDetune = 60.0
    static let wtSide = 0.708
    static let wtOut = 0.5

    // FM
    /// Отношения, к которым ручка RATIO «прилипает» (±2 %); без массива — fmRatio зовётся в колбэке.
    @inline(__always) static func fmSnap(_ i: Int) -> Double {
        switch i {
        case 0: return 0.5
        case 1: return 1
        case 2: return 1.5
        case 3: return 2
        case 4: return 3
        case 5: return 4
        case 6: return 5
        case 7: return 6
        case 8: return 7
        default: return 8
        }
    }
    static let fmIndex = 10.0
    static let fmFeedback = 0.35
    static let fmOut = 0.7

    /// Полуполосный фильтр децимации ×2 (окно Блэкмана–Харриса), нечётная длина.
    static let hbLen = 63

    static let sinN = 4096
    static let waveSteps = 64

    /// RATIO движка FM по ручке 0…1: 0.5 → 8 логарифмически, с привязкой (±2 %) к fmSnap.
    static func fmRatio(_ n: Double) -> Double {
        let r = 0.5 * pow(16, Swift.min(1, Swift.max(0, n)))
        var i = 0
        while i < 10 {
            let t = fmSnap(i)
            if abs(r / t - 1) <= 0.02 { return t }
            i += 1
        }
        return r
    }

    /// PITCH DRUM по ручке 0…1, Гц.
    static func drumPitch(_ n: Double) -> Double {
        drumPitchMin * pow(drumPitchMax / drumPitchMin, Swift.min(1, Swift.max(0, n)))
    }

    /// Пункт WAVE (ручка 0…1, четыре пункта).
    @inline(__always) static func waveIndex(_ v: Double) -> Int {
        Swift.min(3, Swift.max(0, Int((v * 4).rounded(.down))))
    }
}

/// Таблицы своих движков (указатели — колбэк не читает Swift-массивы).
public final class JamboTables {
    /// Синус 4096 + 1 точек (Float, как Float32Array).
    let sine: UnsafeMutablePointer<Float>
    /// Те же значения в Double (S14b: в отладочной сборке Double(Float) на каждом отсчёте — вызов функции).
    let sineD: UnsafeMutablePointer<Double>
    /// Полуполосный фильтр: ненулевые отводы — центр и нечётные от него; симметричен — hbHK[j] при отводах
    /// центр ∓ (2j + 1), j = 0…15, центр — hbCK (значения Float в Double; jHalf / dHalf — 16 слагаемых без цикла, S14b).
    let hbHK: UnsafeMutablePointer<Double>
    let hbCK: Double
    /// Нормировка пика смеси соседних форм ANALOG: [сегмент 0…2][шаг 0…64].
    let waveGain: UnsafeMutablePointer<Float>
    /// Нормировка чистых форм (синус, треугольник, пила, квадрат).
    let shapeGain: UnsafeMutablePointer<Float>

    public init() {
        let tau = Double.pi * 2
        sine = .allocate(capacity: Jambo.sinN + 1)
        for i in 0...Jambo.sinN { sine[i] = Float(sin(tau * Double(i) / Double(Jambo.sinN))) }
        sineD = .allocate(capacity: Jambo.sinN + 1)
        for i in 0...Jambo.sinN { sineD[i] = Double(sine[i]) }

        // Коэффициенты: sinc · окно, нормировка по сумме; только центр и нечётные отводы (чётные — нули).
        let len = Jambo.hbLen
        let c = (len - 1) / 2
        var all = [Double](repeating: 0, count: len)
        var sum = 0.0
        for n in 0..<len {
            let k = Double(n - c)
            let sinc = k == 0 ? 0.5 : sin(Double.pi * k / 2) / (Double.pi * k)
            let x = Double(n) / Double(len - 1)
            let w = 0.35875 - 0.48829 * cos(tau * x) + 0.14128 * cos(2 * tau * x) - 0.01168 * cos(3 * tau * x)
            all[n] = sinc * w
            sum += all[n]
        }
        var idx: [Int] = []
        var kk: [Float] = []
        for n in 0..<len where (n - c) % 2 != 0 {
            idx.append(n)
            kk.append(Float(all[n] / sum))
        }
        idx.append(c)
        kk.append(Float(all[c] / sum))
        // Пары: коэффициент нижнего отвода c − (2j + 1) (верхний симметричен); развёрнутая свёртка — для 63 отводов.
        let hbN: Int = idx.count
        precondition(len == 63 && hbN == 33, "jHalf / dHalf развёрнуты для 63 отводов")
        hbHK = .allocate(capacity: 16)
        for i in 0..<(hbN - 1) where idx[i] < c {
            hbHK[(c - idx[i] - 1) / 2] = Double(kk[i])
        }
        hbCK = Double(kk[hbN - 1])

        // Пик смеси соседних форм (кроссфейд равной мощности, нормированный по сумме амплитуд) — по сетке.
        func shape(_ k: Int, _ ph: Double) -> Double {
            if k == 0 { return sin(tau * ph) }
            if k == 1 { return 1 - 4 * abs(ph < 0.75 ? ph - 0.25 : ph - 1.25) }
            if k == 2 { return 1 - 2 * ph }
            return ph < 0.5 ? 1 : -1
        }
        let steps = Jambo.waveSteps
        waveGain = .allocate(capacity: 3 * (steps + 1))
        for seg in 0..<3 {
            for st in 0...steps {
                let wf = Double(st) / Double(steps)
                let ca = cos(wf * Double.pi / 2), cb = sin(wf * Double.pi / 2)
                var pk = 0.0
                for i in 0..<2048 {
                    let ph = Double(i) / 2048
                    pk = Swift.max(pk, abs((ca * shape(seg, ph) + cb * shape(seg + 1, ph)) / (ca + cb)))
                }
                waveGain[seg * (steps + 1) + st] = Float(1 / pk)
            }
        }
        shapeGain = .allocate(capacity: 4)
        shapeGain[0] = waveGain[0]
        shapeGain[1] = waveGain[steps + 1]
        shapeGain[2] = waveGain[2 * (steps + 1)]
        shapeGain[3] = waveGain[3 * (steps + 1) - 1]
    }

    deinit {
        sine.deallocate()
        sineD.deallocate()
        hbHK.deallocate()
        waveGain.deallocate()
        shapeGain.deallocate()
    }
}

/// Дрейф ANALOG (общий на дорожку): центы, цель, множитель частоты, время дорожки с дрейфом (кадров) и генератор
/// (xorshift32 веба; состояние — Int 0…2³²−1, в отладке без обобщённых преобразований UInt32).
struct JamboDrift {
    var drift = 0.0
    var driftTo = 0.0
    var ratio = 1.0
    var tau = 0.0
    var rnd = 33333

    @inline(__always) static func xorshift(_ r0: Int) -> Int {
        let m = 0xFFFF_FFFF
        var r = r0
        r ^= (r << 13) & m
        r ^= r >> 17
        r ^= (r << 5) & m
        return r
    }

    /// Начало блока process() из frames кадров: новая цель дрейфа (в среднем раз в 0,5 с), плавный ход за 0,7 с.
    mutating func begin(_ frames: Int, _ sr: Double) {
        rnd = JamboDrift.xorshift(rnd)
        if Double(rnd) / 4294967296 < Jambo.analogDriftRate * Double(frames) / sr {
            rnd = JamboDrift.xorshift(rnd)
            driftTo = (Double(rnd) / 4294967296 * 2 - 1) * Jambo.analogDrift
        }
        drift += (driftTo - drift) * Double(frames) / (0.7 * sr)
        ratio = pow(2, drift / 1200)
    }

    /// Конец блока: время дорожки с дрейфом.
    mutating func end(_ frames: Int) {
        tau += Double(frames) * ratio
    }
}
