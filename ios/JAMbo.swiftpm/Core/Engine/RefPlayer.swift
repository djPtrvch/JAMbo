import Foundation

// Референс-трек аранжировщика (S15g, docs/ai/arranger.md «REF»): файл играет в своём темпе — место в файле = время
// позиции курсора таймлайна (при текущем темпе) − сдвиг начала файла. Играет, только пока идёт таймлайн; читается
// подряд, скачок курсора (старт, петля, переход, смена темпа) — переход на новое место с кроссфейдом на блок.
// A/B: оба звучат всегда, слышен один (плавно за ~10 мс); референс — в выход мимо модулей мастера.

public final class RefPlayer: @unchecked Sendable {
    /// Расхождение места чтения с местом по курсору, после которого — переход (кадры, 25 мс).
    static let tolerance = 1200
    /// Время перехода A/B (кадры, 10 мс).
    static let abFrames: Float = 480

    /// Звук референса в блоке (после громкости).
    public let outL: UnsafeMutablePointer<Float>
    public let outR: UnsafeMutablePointer<Float>
    /// Место чтения (кадр файла; до начала файла — отрицательное, тишина) и играет ли.
    public private(set) var pos: Int = 0
    public private(set) var active = false
    private var lastLeft: UnsafeMutablePointer<Float>? = nil
    /// Доля референса на выходе (0 — A, 1 — B), плавно к refB.
    public private(set) var ab: Float = 0

    public init() {
        outL = .allocate(capacity: AudioCore.maxFrames)
        outR = .allocate(capacity: AudioCore.maxFrames)
        outL.initialize(repeating: 0, count: AudioCore.maxFrames)
        outR.initialize(repeating: 0, count: AudioCore.maxFrames)
    }

    deinit {
        outL.deallocate()
        outR.deallocate()
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

    /// Выход блока: мастер (left, right) и референс по доле A/B; пики и LUFS референса — в Levels.ref.
    @inline(__always)
    public func mix(_ d: SoundData, _ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, n: Int,
                    levels: Levels) {
        let target: Float = d.refB ? 1 : 0
        let step: Float = 1 / RefPlayer.abFrames
        let ol = outL, or = outR
        var a: Float = ab
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
            let vl: Float = ol[k]
            let vr: Float = or[k]
            let al: Float = vl < 0 ? -vl : vl
            let ar: Float = vr < 0 ? -vr : vr
            if al > pl { pl = al }
            if ar > pr { pr = ar }
            let b: Float = 1 - a
            left[k] = left[k] * b + vl * a
            right[k] = right[k] * b + vr * a
            k += 1
        }
        ab = a
        let m = levels.current(Levels.ref)
        m[0] = pl
        m[1] = pr
        if levels.loudness.listens(Levels.ref) { levels.loudness.process(UnsafePointer(ol), UnsafePointer(or), n) }
    }
}
