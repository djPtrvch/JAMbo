// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// Движки Plaits голосов синта (как слоты jambo_voices.cc: у каждого голоса свои 8 движков, смена движка —
// LoadUserData и Reset). Создаются вне колбэка; в колбэке — вызовы по номеру через switch (без коллекций).

final class SynthEngineBank {
    let count: Int
    private let va: UnsafeMutablePointer<VirtualAnalogEngine>
    private let ws: UnsafeMutablePointer<WaveshapingEngine>
    private let fm: UnsafeMutablePointer<FMEngine>
    private let grain: UnsafeMutablePointer<GrainEngine>
    private let additive: UnsafeMutablePointer<AdditiveEngine>
    private let wavetable: UnsafeMutablePointer<WavetableEngine>
    private let chord: UnsafeMutablePointer<ChordEngine>
    private let speech: UnsafeMutablePointer<SpeechEngine>
    /// Генератор шума stmlib: в вебе — один на экземпляр wasm (дорожку); здесь — на дорожку.
    private let randoms: [StmRandom]

    /// count голосов; perTrack — голосов дорожки (общий генератор шума).
    init(_ r: PlaitsResources, count: Int, perTrack: Int) {
        self.count = count
        let tracks = (count + perTrack - 1) / perTrack
        randoms = (0..<tracks).map { _ in StmRandom() }
        va = .allocate(capacity: count)
        ws = .allocate(capacity: count)
        fm = .allocate(capacity: count)
        grain = .allocate(capacity: count)
        additive = .allocate(capacity: count)
        wavetable = .allocate(capacity: count)
        chord = .allocate(capacity: count)
        speech = .allocate(capacity: count)
        for v in 0..<count {
            (va + v).initialize(to: VirtualAnalogEngine(resources: r))
            (ws + v).initialize(to: WaveshapingEngine(resources: r))
            (fm + v).initialize(to: FMEngine(resources: r))
            (grain + v).initialize(to: GrainEngine(resources: r))
            (additive + v).initialize(to: AdditiveEngine(resources: r))
            (wavetable + v).initialize(to: WavetableEngine(resources: r))
            (chord + v).initialize(to: ChordEngine(resources: r))
            (speech + v).initialize(to: SpeechEngine(resources: r, random: randoms[v / perTrack]))
        }
    }

    deinit {
        va.deinitialize(count: count); va.deallocate()
        ws.deinitialize(count: count); ws.deallocate()
        fm.deinitialize(count: count); fm.deallocate()
        grain.deinitialize(count: count); grain.deallocate()
        additive.deinitialize(count: count); additive.deallocate()
        wavetable.deinitialize(count: count); wavetable.deallocate()
        chord.deinitialize(count: count); chord.deallocate()
        speech.deinitialize(count: count); speech.deallocate()
    }

    /// Выбор движка e в голосе v (set() в jambo_voices.cc): LoadUserData(nullptr), затем Reset.
    @inline(__always)
    func select(_ v: Int, _ e: Int) {
        switch e {
        case 0: va[v].loadUserData(); va[v].reset()
        case 1: ws[v].loadUserData(); ws[v].reset()
        case 2: fm[v].loadUserData(); fm[v].reset()
        case 3: grain[v].loadUserData(); grain[v].reset()
        case 4: additive[v].loadUserData(); additive[v].reset()
        case 5: wavetable[v].loadUserData(); wavetable[v].reset()
        case 6: chord[v].loadUserData(); chord[v].reset()
        default: speech[v].loadUserData(); speech[v].reset()
        }
    }

    @inline(__always)
    func render(_ v: Int, _ e: Int, _ p: EngineParameters, _ out: UnsafeMutablePointer<Float>,
                _ aux: UnsafeMutablePointer<Float>, _ n: Int) {
        var enveloped = false
        switch e {
        case 0: va[v].render(p, out, aux, n, &enveloped)
        case 1: ws[v].render(p, out, aux, n, &enveloped)
        case 2: fm[v].render(p, out, aux, n, &enveloped)
        case 3: grain[v].render(p, out, aux, n, &enveloped)
        case 4: additive[v].render(p, out, aux, n, &enveloped)
        case 5: wavetable[v].render(p, out, aux, n, &enveloped)
        case 6: chord[v].render(p, out, aux, n, &enveloped)
        default: speech[v].render(p, out, aux, n, &enveloped)
        }
    }
}
