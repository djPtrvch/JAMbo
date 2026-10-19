// Голоса своих движков JAMbo (DRUM, ANALOG, FM, WTABLE): голос на слот, таблицы — общие. Создаются вне колбэка.

final class JamboBank {
    let count: Int
    let jamboTables = JamboTables()
    private let jambo: UnsafeMutablePointer<JamboVoice>

    init(count: Int, sampleRate: Double = 48000) {
        self.count = count
        jambo = .allocate(capacity: count)
        for v in 0..<count { (jambo + v).initialize(to: JamboVoice(tables: jamboTables, sampleRate: sampleRate)) }
    }

    deinit {
        jambo.deinitialize(count: count)
        jambo.deallocate()
    }

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
    func jamboRender(_ v: Int, _ out: UnsafeMutablePointer<Float>, _ n: Int, driftRatio: Double, table: WtRef) {
        jambo[v].render(out, n, driftRatio: driftRatio, table: table)
    }

    /// Голос молчал: хвоста DRUM для стыка нет (vo.last = 0 в worklet).
    @inline(__always)
    func jamboSilent(_ v: Int) {
        jambo[v].last = 0
    }
}
