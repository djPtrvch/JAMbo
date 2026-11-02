// Голоса своих движков JAMbo: KICK, ANALOG, FM, WTABLE, SUB — JamboVoice; SNARE, HAT, CLAP, PERC — JamboDrumVoice;
// TEXTURE — TextureVoice (стерео, только первый слот дорожки: движок моно), GRANULAR — GranularVoice (стерео, полифоничен:
// голос на слот, дрейф и лимит зёрен — GrainTrack дорожки). Голос каждого вида на слот, таблицы — общие. Создаются
// вне колбэка.

final class JamboBank {
    let count: Int
    let jamboTables = JamboTables()
    private let jambo: UnsafeMutablePointer<JamboVoice>
    private let drums: UnsafeMutablePointer<JamboDrumVoice>
    /// TEXTURE — на первый слот дорожки (слот / perTrack).
    private let texture: UnsafeMutablePointer<TextureVoice>
    /// GRANULAR — на слот; общее дорожки — grainTracks.
    private let granular: UnsafeMutablePointer<GranularVoice>
    private let grainTracks: UnsafeMutablePointer<GrainTrack>
    private let tracks: Int
    private let perTrack: Int
    /// Вид голоса в слоте: 0 — JamboVoice, 1 — ударный 20–23 (JamboDrumVoice), 2 — TEXTURE, 3 — GRANULAR.
    private let kind: UnsafeMutablePointer<UInt8>

    init(count: Int, sampleRate: Double = 48000, perTrack: Int = 1) {
        self.count = count
        self.perTrack = perTrack
        jambo = .allocate(capacity: count)
        drums = .allocate(capacity: count)
        kind = .allocate(capacity: count)
        kind.initialize(repeating: 0, count: count)
        for v in 0..<count {
            (jambo + v).initialize(to: JamboVoice(tables: jamboTables, sampleRate: sampleRate))
            (drums + v).initialize(to: JamboDrumVoice(tables: jamboTables, sampleRate: sampleRate))
        }
        let tracks = (count + perTrack - 1) / perTrack
        self.tracks = tracks
        texture = .allocate(capacity: tracks)
        grainTracks = .allocate(capacity: tracks)
        for t in 0..<tracks {
            (texture + t).initialize(to: TextureVoice(sampleRate: sampleRate, seed: t + 1))
            (grainTracks + t).initialize(to: GrainTrack(rnd: ((t + 1) &* 40503 + 11) & 0xFFFF_FFFF | 1))
        }
        granular = .allocate(capacity: count)
        for v in 0..<count {
            (granular + v).initialize(to: GranularVoice(sampleRate: sampleRate, seed: v + 1, track: grainTracks + v / perTrack))
        }
    }

    deinit {
        jambo.deinitialize(count: count)
        jambo.deallocate()
        drums.deinitialize(count: count)
        drums.deallocate()
        kind.deallocate()
        texture.deinitialize(count: tracks)
        texture.deallocate()
        granular.deinitialize(count: count)
        granular.deallocate()
        grainTracks.deallocate()
    }

    /// Нота своего движка в голосе v (trigger в worklet); now — абсолютный кадр, tau — время дорожки с дрейфом.
    @inline(__always)
    func jamboTrigger(_ v: Int, _ e: Int, note: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ p4: Double,
                      decay: Double, now: Double, tau: Double) {
        if e >= Jambo.snare && e <= Jambo.perc {
            kind[v] = 1
            drums[v].trigger(engine: e, p1, p2, p3, p4, decay: decay)
            return
        }
        if e == Jambo.texture {
            kind[v] = 2
            texture[v / perTrack].trigger(note: note, p1, p2, p3, p4)
            return
        }
        if e == Jambo.granular {
            kind[v] = 3
            granular[v].trigger(note: note, p1, p2, p3, p4)
            return
        }
        kind[v] = 0
        jambo[v].trigger(engine: e, note: note, p1, p2, p3, p4, decay: decay, now: now, tau: tau)
    }

    /// Ручки звучащей ноты (mod в worklet; сглаживание — в голосе).
    @inline(__always)
    func jamboSet(_ v: Int, note: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ p4: Double, decay: Double) {
        let k = kind[v]
        if k == 1 {
            drums[v].set(p1, p2, p3, p4, decay: decay)
            return
        }
        if k == 2 {
            texture[v / perTrack].set(note: note, p1, p2, p3, p4)
            return
        }
        if k == 3 {
            granular[v].set(note: note, p1, p2, p3, p4)
            return
        }
        jambo[v].set(note: note, p1, p2, p3, p4, decay: decay)
    }

    @inline(__always)
    func jamboRender(_ v: Int, _ out: UnsafeMutablePointer<Float>, _ n: Int, driftRatio: Double, table: WtRef) {
        if kind[v] == 1 {
            drums[v].render(out, n)
            return
        }
        jambo[v].render(out, n, driftRatio: driftRatio, table: table)
    }

    /// Голос молчал: хвоста KICK для стыка нет (vo.last = 0 в worklet).
    @inline(__always)
    func jamboSilent(_ v: Int) {
        jambo[v].last = 0
        drums[v].last = 0
        granular[v].silence()
        if v % perTrack == 0 { texture[v / perTrack].silence() }
    }

    /// Стерео-движок (TEXTURE, GRANULAR — со своим сэмплом src): левый канал — в outL, правый — в outR; window —
    /// кадров окна активности.
    @inline(__always)
    func stereoRender(_ v: Int, _ outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>, _ n: Int,
                      window: Int, src: GrainSrc) {
        if kind[v] == 3 {
            granular[v].render(outL, outR, n, window: window, src: src)
            return
        }
        texture[v / perTrack].render(outL, outR, n, window: window)
    }

    /// Начало блока n кадров: дрейф GRANULAR каждой дорожки и число её нот с открытым окном запуска (active — голоса
    /// SynthVoices).
    @inline(__always)
    func granularBegin(_ n: Int, sampleRate: Double, active: UnsafeMutablePointer<UInt8>) {
        let dt: Double = Double(n) / sampleRate
        var t = 0
        while t < tracks {
            var c = 0
            var any = false
            var v = t * perTrack
            let end = Swift.min(count, v + perTrack)
            while v < end {
                if kind[v] == 3 && active[v] != 0 {
                    any = true
                    if granular[v].spawning { c += 1 }
                }
                v += 1
            }
            grainTracks[t].notes = c
            if any { grainTracks[t].advance(dt) }
            t += 1
        }
    }
}
