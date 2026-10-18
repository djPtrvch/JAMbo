import Foundation

// EQ дорожек в колбэке (как engine.ts веба: EQ стоит до эффектов — у сухого сигнала и у каждого посыла голоса своя
// копия EQ дорожки с теми же полосами): на дорожку один EqUnit с 4 линиями — шина дорожки и шины посылов Reverb,
// Delay, Drive; дальше — Sidechain, громкость микшера, mute/solo (Sampler.mix). Дорожка без голосов, у которой
// хвост фильтров ещё звучит, считается дальше (тишина на входе). Спектры EQ (Spectra) — шина дорожки до и после
// её EQ. Экземпляры создаются вне колбэка.

public final class TrackEqs {
    public static let lanes = 4
    let units: UnsafeMutablePointer<EqUnit>

    public init(sampleRate: Double) {
        units = .allocate(capacity: SoundData.maxTracks)
        for t in 0..<SoundData.maxTracks {
            (units + t).initialize(to: EqUnit(sampleRate: sampleRate, lanes: TrackEqs.lanes))
        }
    }

    deinit {
        units.deinitialize(count: SoundData.maxTracks)
        units.deallocate()
    }

    @inline(__always)
    public func unit(_ t: Int) -> EqUnit { return units[t] }

    /// Хвост EQ дорожки t ещё звучит (в какой-нибудь линии).
    @inline(__always)
    func ringing(_ t: Int) -> Bool {
        let u = units[t]
        var k = 0
        while k < TrackEqs.lanes {
            if u.ringing(k) { return true }
            k += 1
        }
        return false
    }
}

extension Sampler {
    /// Дорожки без голосов в этом блоке, у которых звучит хвост EQ: шины — с нуля, дорожка считается.
    func wakeEqs(_ d: SoundData, _ n: Int) {
        guard let e = eqs else { return }
        var t = 0
        while t < d.trackCount {
            if used[t] == 0 && e.ringing(t) {
                (busL + t * Sampler.maxFrames).update(repeating: 0, count: n)
                (busR + t * Sampler.maxFrames).update(repeating: 0, count: n)
                var k = 0
                while k < 3 {
                    (sendL + (t * 3 + k) * Sampler.maxFrames).update(repeating: 0, count: n)
                    (sendR + (t * 3 + k) * Sampler.maxFrames).update(repeating: 0, count: n)
                    k += 1
                }
                used[t] = 1
            }
            t += 1
        }
    }

    /// Дорожка t молчит: EQ без звука принимает набор полос и значения; спектры этой дорожки — тишина.
    func idleEq(_ t: Int, _ d: SoundData, _ n: Int) {
        eqs?.unit(t).idle(params: d.eq + t * EqSpec.stride)
        guard let s = spectra else { return }
        if s.channel.load() == t {
            s.pre.pushSilence(n)
            s.post.pushSilence(n)
        }
        if s.compareTrack.load() == t { s.compare.pushSilence(n) }
    }

    /// EQ дорожки t на месте: шина дорожки и (если есть шины эффектов) шины посылов.
    func trackEq(_ t: Int, _ d: SoundData, _ n: Int, sends: Bool) {
        guard let e = eqs else { return }
        let u = e.unit(t)
        let mf = Sampler.maxFrames
        u.laneL[0] = busL + t * mf
        u.laneR[0] = busR + t * mf
        var k = 0
        while k < 3 {
            u.laneL[k + 1] = sends ? sendL + (t * 3 + k) * mf : nil
            u.laneR[k + 1] = sends ? sendR + (t * 3 + k) * mf : nil
            k += 1
        }
        let shown: Bool = spectra?.channel.load() == t
        if shown, let s = spectra { s.pre.push(busL + t * mf, busR + t * mf, n) }
        u.process(frames: n, params: d.eq + t * EqSpec.stride)
        if shown, let s = spectra { s.post.push(busL + t * mf, busR + t * mf, n) }
        if let s = spectra, s.compareTrack.load() == t { s.compare.push(busL + t * mf, busR + t * mf, n) }
    }
}
