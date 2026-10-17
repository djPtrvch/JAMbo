// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// Движки Plaits голосов синта (как слоты jambo_voices.cc: у каждого голоса свои 16 движков, смена движка —
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
    private let swarm: UnsafeMutablePointer<SwarmEngine>
    private let noise: UnsafeMutablePointer<NoiseEngine>
    private let particle: UnsafeMutablePointer<ParticleEngine>
    private let string: UnsafeMutablePointer<StringEngine>
    private let modal: UnsafeMutablePointer<ModalEngine>
    private let bassDrum: UnsafeMutablePointer<BassDrumEngine>
    private let snareDrum: UnsafeMutablePointer<SnareDrumEngine>
    private let hiHat: UnsafeMutablePointer<HiHatEngine>
    /// Генератор шума stmlib: в вебе — один на экземпляр wasm (дорожку); здесь — на дорожку.
    private let randoms: [StmRandom]

    /// count голосов; perTrack — голосов дорожки (общий генератор шума).
    /// Свои движки JAMbo (DRUM, ANALOG, FM): голос на слот, таблицы — общие.
    let jamboTables = JamboTables()
    private let jambo: UnsafeMutablePointer<JamboVoice>

    init(_ r: PlaitsResources, count: Int, perTrack: Int, sampleRate: Double = 48000) {
        self.count = count
        jambo = .allocate(capacity: count)
        for v in 0..<count { (jambo + v).initialize(to: JamboVoice(tables: jamboTables, sampleRate: sampleRate)) }
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
        swarm = .allocate(capacity: count)
        noise = .allocate(capacity: count)
        particle = .allocate(capacity: count)
        string = .allocate(capacity: count)
        modal = .allocate(capacity: count)
        bassDrum = .allocate(capacity: count)
        snareDrum = .allocate(capacity: count)
        hiHat = .allocate(capacity: count)
        for v in 0..<count {
            (va + v).initialize(to: VirtualAnalogEngine(resources: r))
            (ws + v).initialize(to: WaveshapingEngine(resources: r))
            (fm + v).initialize(to: FMEngine(resources: r))
            (grain + v).initialize(to: GrainEngine(resources: r))
            (additive + v).initialize(to: AdditiveEngine(resources: r))
            (wavetable + v).initialize(to: WavetableEngine(resources: r))
            (chord + v).initialize(to: ChordEngine(resources: r))
            let random = randoms[v / perTrack]
            (speech + v).initialize(to: SpeechEngine(resources: r, random: random))
            (swarm + v).initialize(to: SwarmEngine(resources: r, random: random))
            (noise + v).initialize(to: NoiseEngine(resources: r, random: random))
            (particle + v).initialize(to: ParticleEngine(resources: r, random: random))
            (string + v).initialize(to: StringEngine(resources: r, random: random))
            (modal + v).initialize(to: ModalEngine(resources: r, random: random))
            (bassDrum + v).initialize(to: BassDrumEngine(resources: r, random: random))
            (snareDrum + v).initialize(to: SnareDrumEngine(resources: r, random: random))
            (hiHat + v).initialize(to: HiHatEngine(resources: r, random: random))
        }
    }

    deinit {
        jambo.deinitialize(count: count); jambo.deallocate()
        va.deinitialize(count: count); va.deallocate()
        ws.deinitialize(count: count); ws.deallocate()
        fm.deinitialize(count: count); fm.deallocate()
        grain.deinitialize(count: count); grain.deallocate()
        additive.deinitialize(count: count); additive.deallocate()
        wavetable.deinitialize(count: count); wavetable.deallocate()
        chord.deinitialize(count: count); chord.deallocate()
        speech.deinitialize(count: count); speech.deallocate()
        swarm.deinitialize(count: count); swarm.deallocate()
        noise.deinitialize(count: count); noise.deallocate()
        particle.deinitialize(count: count); particle.deallocate()
        string.deinitialize(count: count); string.deallocate()
        modal.deinitialize(count: count); modal.deallocate()
        bassDrum.deinitialize(count: count); bassDrum.deallocate()
        snareDrum.deinitialize(count: count); snareDrum.deallocate()
        hiHat.deinitialize(count: count); hiHat.deallocate()
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
        case 7: speech[v].loadUserData(); speech[v].reset()
        case 8: swarm[v].loadUserData(); swarm[v].reset()
        case 9: noise[v].loadUserData(); noise[v].reset()
        case 10: particle[v].loadUserData(); particle[v].reset()
        case 11: string[v].loadUserData(); string[v].reset()
        case 12: modal[v].loadUserData(); modal[v].reset()
        case 13: bassDrum[v].loadUserData(); bassDrum[v].reset()
        case 14: snareDrum[v].loadUserData(); snareDrum[v].reset()
        case 15: hiHat[v].loadUserData(); hiHat[v].reset()
        default: break  // свои движки — trigger при ноте
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
        case 7: speech[v].render(p, out, aux, n, &enveloped)
        case 8: swarm[v].render(p, out, aux, n, &enveloped)
        case 9: noise[v].render(p, out, aux, n, &enveloped)
        case 10: particle[v].render(p, out, aux, n, &enveloped)
        case 11: string[v].render(p, out, aux, n, &enveloped)
        case 12: modal[v].render(p, out, aux, n, &enveloped)
        case 13: bassDrum[v].render(p, out, aux, n, &enveloped)
        case 14: snareDrum[v].render(p, out, aux, n, &enveloped)
        case 15: hiHat[v].render(p, out, aux, n, &enveloped)
        default: break
        }
    }

    // MARK: — свои движки (номера ≥ SynthEngines.firstJambo)

    /// Нота своего движка в голосе v (trigger в worklet); now — абсолютный кадр, tau — время дорожки с дрейфом.
    @inline(__always)
    func jamboTrigger(_ v: Int, _ e: Int, note: Double, _ p1: Double, _ p2: Double, _ p3: Double, decay: Double,
                      now: Double, tau: Double) {
        jambo[v].trigger(engine: e, note: note, p1, p2, p3, decay: decay, now: now, tau: tau)
    }

    /// Ручки звучащей ноты (mod в worklet; сглаживание — в голосе).
    @inline(__always)
    func jamboSet(_ v: Int, note: Double, _ p1: Double, _ p2: Double, _ p3: Double, decay: Double) {
        jambo[v].set(note: note, p1, p2, p3, decay: decay)
    }

    @inline(__always)
    func jamboRender(_ v: Int, _ out: UnsafeMutablePointer<Float>, _ n: Int, driftRatio: Double) {
        jambo[v].render(out, n, driftRatio: driftRatio)
    }

    /// Голос молчал: хвоста DRUM для стыка нет (vo.last = 0 в worklet).
    @inline(__always)
    func jamboSilent(_ v: Int) {
        jambo[v].last = 0
    }
}
