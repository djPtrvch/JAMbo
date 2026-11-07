import Foundation

// Референс-трек аранжировщика (S15g, docs/ai/arranger.md «REF»): файл играет в своём темпе — место в файле = время
// позиции курсора таймлайна (при текущем темпе) − сдвиг начала файла. Играет, только пока идёт таймлайн; читается
// подряд, скачок курсора (старт, петля, переход, смена темпа) — переход на новое место с кроссфейдом на блок.
// A/B: оба звучат всегда, слышен один (плавно за 20 мс). Референс — мимо модулей мастера или через них
// (throughMaster, Headphone Monitor: переход тоже плавный); через монитор-цепочку или мимо неё — MonitorChain (AudioCore).
// Подгонка громкости к миксу — matchGain (считает интерфейс: LUFS short-term микса против integrated референса).

public final class RefPlayer: @unchecked Sendable {
    /// Расхождение места чтения с местом по курсору, после которого — переход (кадры, 25 мс).
    static let tolerance = 1200
    /// Время перехода A/B и смены пути через мастер (кадры, 20 мс).
    static let abFrames: Float = 960

    /// Звук референса в блоке (после громкости).
    public let outL: UnsafeMutablePointer<Float>
    public let outR: UnsafeMutablePointer<Float>
    /// Место чтения (кадр файла; до начала файла — отрицательное, тишина) и играет ли.
    public private(set) var pos: Int = 0
    public private(set) var active = false
    private var lastLeft: UnsafeMutablePointer<Float>? = nil
    /// Доля референса на выходе (0 — A, 1 — B), плавно к refB.
    public private(set) var ab: Float = 0
    /// Референс через модули мастера (1) или мимо (0) — ставит интерфейс; доля пути через мастер — плавно.
    public let throughMaster = AtomicCounter()
    /// Референс через монитор-цепочку (1, по умолчанию) или мимо (0).
    public let throughMonitor = AtomicCounter()
    /// Подгонка громкости (множитель, ставит интерфейс); в блоке — линейно от прежнего.
    public let matchGain = AtomicFloat(1)
    private var match: Float = 1
    private var thru: Float = 0
    /// Доля референса после мастера (a · (1 − доля через мастер)) по отсчётам блока.
    private let post: UnsafeMutablePointer<Float>

    public init() {
        outL = .allocate(capacity: AudioCore.maxFrames)
        outR = .allocate(capacity: AudioCore.maxFrames)
        outL.initialize(repeating: 0, count: AudioCore.maxFrames)
        outR.initialize(repeating: 0, count: AudioCore.maxFrames)
        post = .allocate(capacity: AudioCore.maxFrames)
        post.initialize(repeating: 0, count: AudioCore.maxFrames)
        throughMonitor.store(1)
    }

    deinit {
        outL.deallocate()
        outR.deallocate()
        post.deallocate()
    }

    /// Место в файле по позиции курсора x (шаги, дробная) при темпе bpm.
    @inline(__always)
    public static func frame(_ d: SoundData, x: Double, bpm: Double) -> Int {
        let sec: Double = x * 15 / Swift.max(1, bpm)
        let f: Double = sec * AudioCore.sampleRate - d.refOffset
        return Int(f.rounded())
    }

    /// Блок n кадров: play — идёт таймлайн, x — позиция курсора в начале блока (шаги).
    @inline(__always)
    public func render(_ d: SoundData, play: Bool, x: Double, bpm: Double, n: Int) {
        outL.update(repeating: 0, count: n)
        outR.update(repeating: 0, count: n)
        let has: Bool = d.refLeft != nil && d.refFrames > 0
        let same: Bool = d.refLeft == lastLeft
        let want: Bool = play && has
        if !want && !active { return }
        let g: Float = d.refGain
        if !same {
            // Другой файл: прежний не читается (его буферы могут уйти), новый — с подъёмом.
            active = false
            lastLeft = d.refLeft
        }
        if !want {
            // Стоп: прежнее место — с затуханием.
            add(d, pos, n, g, 1, -1 / Float(n))
            active = false
            return
        }
        let target: Int = RefPlayer.frame(d, x: x, bpm: bpm)
        if !active {
            pos = target
            add(d, pos, n, g, 0, 1 / Float(n))
            active = true
        } else {
            let dist: Int = target > pos ? target - pos : pos - target
            if dist > RefPlayer.tolerance {
                add(d, pos, n, g, 1, -1 / Float(n))
                pos = target
                add(d, pos, n, g, 0, 1 / Float(n))
            } else {
                add(d, pos, n, g, 1, 0)
            }
        }
        pos += n
        applyMatch(n)
    }

    /// Подгонка громкости: от прежнего множителя к новому линейно за блок.
    @inline(__always)
    private func applyMatch(_ n: Int) {
        let m1: Float = matchGain.load()
        let m0: Float = match
        if m0 == 1 && m1 == 1 { return }
        let dm: Float = (m1 - m0) / Float(n)
        let ol = outL, or = outR
        var k = 0
        while k < n {
            let m: Float = m0 + dm * Float(k + 1)
            ol[k] *= m
            or[k] *= m
            k += 1
        }
        match = m1
    }

    /// Прибавить n кадров файла с места from, громкость g · (a + k·da).
    @inline(__always)
    private func add(_ d: SoundData, _ from: Int, _ n: Int, _ g: Float, _ a: Float, _ da: Float) {
        guard let l = d.refLeft, let r = d.refRight else { return }
        let frames: Int = d.refFrames
        let ol = outL, or = outR
        var e: Float = a
        var k = 0
        while k < n {
            let i: Int = from + k
            if i >= 0 && i < frames {
                let m: Float = g * e
                ol[k] += l[i] * m
                or[k] += r[i] * m
            }
            e += da
            k += 1
        }
    }

    /// До мастера (left, right — вход мастера), a — доля B, m — доля пути через мастер: микс · (1 − a·m) + референс · a·m;
    /// после мастера (mixPost) — выход · (1 − p) + референс · p, p = a·(1 − m) (при m = 0 — как прежде: микс уходит
    /// после мастера). Пики и LUFS референса — в Levels.ref.
    @inline(__always)
    public func mixPre(refB: Bool, _ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, n: Int,
                       levels: Levels) {
        let target: Float = refB ? 1 : 0
        let thruTarget: Float = throughMaster.load() != 0 ? 1 : 0
        let step: Float = 1 / RefPlayer.abFrames
        let ol = outL, or = outR, pp = post
        var a: Float = ab
        var m: Float = thru
        var pl: Float = 0, pr: Float = 0
        var k = 0
        while k < n {
            if a < target {
                a += step
                if a > target { a = target }
            } else if a > target {
                a -= step
                if a < target { a = target }
            }
            if m < thruTarget {
                m += step
                if m > thruTarget { m = thruTarget }
            } else if m > thruTarget {
                m -= step
                if m < thruTarget { m = thruTarget }
            }
            let vl: Float = ol[k]
            let vr: Float = or[k]
            let al: Float = vl < 0 ? -vl : vl
            let ar: Float = vr < 0 ? -vr : vr
            if al > pl { pl = al }
            if ar > pr { pr = ar }
            let am: Float = a * m
            let b: Float = 1 - am
            left[k] = left[k] * b + vl * am
            right[k] = right[k] * b + vr * am
            pp[k] = a - am
            k += 1
        }
        ab = a
        thru = m
        let lv = levels.current(Levels.ref)
        lv[0] = pl
        lv[1] = pr
        if levels.loudness.listens(Levels.ref) { levels.loudness.process(UnsafePointer(ol), UnsafePointer(or), n) }
    }

    /// После мастера: референс мимо мастера (доля post), выход мастера — на остальное.
    @inline(__always)
    public func mixPost(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, n: Int) {
        let ol = outL, or = outR, pp = post
        var k = 0
        while k < n {
            let p: Float = pp[k]
            if p != 0 {
                let b: Float = 1 - p
                left[k] = left[k] * b + ol[k] * p
                right[k] = right[k] * b + or[k] * p
            }
            k += 1
        }
    }
}
