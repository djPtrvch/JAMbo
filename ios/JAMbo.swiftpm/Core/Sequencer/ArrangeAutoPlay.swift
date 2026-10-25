// Автоматизация на таймлайне в колбэке (S15f): каждый блок значение кривой по позиции курсора подставляется вместо
// ручки в снимок звука (параметры голоса, Duck) — дальше p-lock шага и LFO/ENV, как раньше; Chance и Ratchet —
// на момент шага (Sequencer.trig), если на шаге нет их p-lock. Действует только у дорожек, которые идут по таймлайну,
// и только от первой точки кривой до последней; ручка под пальцем (hold) — рукой. Прежнее значение ручки
// запоминается и возвращается, когда кривая перестала действовать (новый снимок звука приносит ручки заново).

public final class ArrAutoPlay {
    static let count = ArrAutoTarget.count
    static let sounds = SoundData.maxTracks * 2
    /// По звуку (номер в таблицах звука) и цели: значение ручки до подстановки, подставлено ли.
    let saved: UnsafeMutablePointer<Float>
    let has: UnsafeMutablePointer<UInt8>
    /// Ручка дорожки под пальцем (дорожка·count + цель): кривая не действует.
    let hold: UnsafeMutablePointer<UInt8>
    private var lastParams: UnsafeMutablePointer<Float>? = nil
    private var anyHas: Bool = false

    init() {
        saved = .allocate(capacity: ArrAutoPlay.sounds * ArrAutoPlay.count)
        has = .allocate(capacity: ArrAutoPlay.sounds * ArrAutoPlay.count)
        hold = .allocate(capacity: SeqData.maxTracks * ArrAutoPlay.count)
        saved.initialize(repeating: 0, count: ArrAutoPlay.sounds * ArrAutoPlay.count)
        has.initialize(repeating: 0, count: ArrAutoPlay.sounds * ArrAutoPlay.count)
        hold.initialize(repeating: 0, count: SeqData.maxTracks * ArrAutoPlay.count)
    }

    deinit {
        saved.deallocate()
        has.deallocate()
        hold.deallocate()
    }

    public func setHold(track t: Int, target j: Int, on: Bool) {
        if t < 0 || t >= SeqData.maxTracks || j < 0 || j >= ArrAutoPlay.count { return }
        hold[t * ArrAutoPlay.count + j] = on ? 1 : 0
    }

    /// Блок: x — позиция курсора (шаги, дробная; −1 — транспорт стоит), follow — дорожки на таймлайне.
    func apply(_ seq: SeqData, _ snd: SoundData, x: Double, follow: UnsafeMutablePointer<Bool>) {
        let n: Int = ArrAutoPlay.count
        if snd.params != lastParams {
            // Новый снимок звука — ручки в нём свои, подставлять заново.
            has.update(repeating: 0, count: ArrAutoPlay.sounds * n)
            lastParams = snd.params
            anyHas = false
        }
        var any: Bool = anyHas
        if !any && x >= 0 {
            var t: Int = 0
            while t < seq.trackCount {
                if seq.autoAny[t] != 0 && follow[t] { any = true }
                t += 1
            }
        }
        if !any { return }
        var still: Bool = false
        let vc: Int = VoiceParam.count
        let mc: Int = ModTarget.count
        var u: Int = 0
        while u < ArrAutoPlay.sounds {
            let t: Int = u % SeqData.maxTracks
            let on: Bool = x >= 0 && t < seq.trackCount && t < snd.trackCount && snd.s(t) == u && follow[t]
                && seq.autoAny[t] != 0
            var j: Int = 0
            while j < ArrAutoPlay.prob {
                let c: Int = u * n + j
                var v: Double = -1
                if on && hold[t * n + j] == 0 { v = seq.auto(t, j, at: x) }
                if v >= 0 {
                    let cur: UnsafeMutablePointer<Float> = j < vc ? snd.params + (u * vc + j) : snd.scAmount + u
                    if has[c] == 0 {
                        saved[c] = cur.pointee
                        has[c] = 1
                    }
                    let value: Double = j < vc ? snd.scale[u * mc + j].fromNorm(v) : v * 100
                    cur.pointee = Float(value)
                    still = true
                } else if has[c] != 0 {
                    let cur: UnsafeMutablePointer<Float> = j < vc ? snd.params + (u * vc + j) : snd.scAmount + u
                    cur.pointee = saved[c]
                    has[c] = 0
                }
                j += 1
            }
            u += 1
        }
        anyHas = still
    }

    static let prob = ArrAutoTarget.prob

    /// Chance или Ratchet (j — ArrAutoTarget.prob / ratchet) дорожки t на шаге x: значение кривой или base.
    @inline(__always)
    func step(_ seq: SeqData, _ snd: SoundData?, _ t: Int, _ j: Int, at x: Double, base: Double) -> Double {
        if seq.autoAny[t] == 0 || hold[t * ArrAutoPlay.count + j] != 0 { return base }
        guard let d = snd else { return base }
        let v: Double = seq.auto(t, j, at: x)
        if v < 0 { return base }
        let mj: Int = j == ArrAutoTarget.prob ? ModTarget.prob : ModTarget.ratchet
        return d.scale[d.s(t) * ModTarget.count + mj].fromNorm(v)
    }
}
