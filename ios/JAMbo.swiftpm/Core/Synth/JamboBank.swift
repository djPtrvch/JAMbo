// Голоса своих движков JAMbo: KICK, ANALOG, FM, WTABLE — JamboVoice; SNARE, HAT, CLAP, PERC — JamboDrumVoice.
// Голос каждого вида на слот, таблицы — общие. Создаются вне колбэка.

final class JamboBank {
    let count: Int
    let jamboTables = JamboTables()
    private let jambo: UnsafeMutablePointer<JamboVoice>
    private let drums: UnsafeMutablePointer<JamboDrumVoice>
    /// 1 — в слоте звучит ударный 20–23 (JamboDrumVoice).
    private let isDrum: UnsafeMutablePointer<UInt8>

    init(count: Int, sampleRate: Double = 48000) {
        self.count = count
        jambo = .allocate(capacity: count)
        drums = .allocate(capacity: count)
        isDrum = .allocate(capacity: count)
        isDrum.initialize(repeating: 0, count: count)
        for v in 0..<count {
            (jambo + v).initialize(to: JamboVoice(tables: jamboTables, sampleRate: sampleRate))
            (drums + v).initialize(to: JamboDrumVoice(tables: jamboTables, sampleRate: sampleRate))
        }
    }

    deinit {
        jambo.deinitialize(count: count)
        jambo.deallocate()
        drums.deinitialize(count: count)
        drums.deallocate()
        isDrum.deallocate()
    }

    /// Нота своего движка в голосе v (trigger в worklet); now — абсолютный кадр, tau — время дорожки с дрейфом.
    @inline(__always)
    func jamboTrigger(_ v: Int, _ e: Int, note: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ p4: Double,
                      decay: Double, now: Double, tau: Double) {
        if e >= Jambo.snare && e <= Jambo.perc {
            isDrum[v] = 1
            drums[v].trigger(engine: e, p1, p2, p3, p4, decay: decay)
            return
        }
        isDrum[v] = 0
        jambo[v].trigger(engine: e, note: note, p1, p2, p3, p4, decay: decay, now: now, tau: tau)
    }

    /// Ручки звучащей ноты (mod в worklet; сглаживание — в голосе).
    @inline(__always)
    func jamboSet(_ v: Int, note: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ p4: Double, decay: Double) {
        if isDrum[v] != 0 {
            drums[v].set(p1, p2, p3, p4, decay: decay)
            return
        }
        jambo[v].set(note: note, p1, p2, p3, p4, decay: decay)
    }

    @inline(__always)
    func jamboRender(_ v: Int, _ out: UnsafeMutablePointer<Float>, _ n: Int, driftRatio: Double, table: WtRef) {
        if isDrum[v] != 0 {
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
    }
}
