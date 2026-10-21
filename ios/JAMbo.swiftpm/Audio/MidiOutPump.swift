import Foundation

/// MIDI OUT дорожек: свой поток (таймер 1 мс) разбирает очередь нот колбэка (Sampler.midiOut), MidiOutPlan даёт
/// Note On и Note Off с моментами, когда слышен звук (+ MIDI OFFSET), MidiHost шлёт их с метками времени CoreMIDI.
/// Выходы дорожек, задержку выхода и MIDI OFFSET задаёт главный поток (update) — под замком.
final class MidiOutPump: @unchecked Sendable {
    private let core: AudioCore
    private let host: MidiHost
    private let queue = DispatchQueue(label: "JAMbo.midiOut", qos: .userInteractive)
    private var timer: DispatchSourceTimer? = nil
    private let lock = NSLock()
    private var routes: [MidiOutRoute?] = []
    private var latency: Double = 0
    private var offset: Double = 0
    /// Только в потоке queue.
    private var plan = MidiOutPlan()
    private let clock = HostClock()

    init(core: AudioCore, host: MidiHost) {
        self.core = core
        self.host = host
    }

    func start() {
        if timer != nil { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(1), leeway: .microseconds(500))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    /// Главный поток: выходы дорожек (по номеру), задержка выхода звука и MIDI OFFSET (с).
    func update(routes r: [MidiOutRoute?], latency l: Double, offset o: Double) {
        lock.lock()
        routes = r
        latency = l
        offset = o
        lock.unlock()
    }

    private func tick() {
        lock.lock()
        let r: [MidiOutRoute?] = routes
        let lat: Double = latency
        let off: Double = offset
        lock.unlock()
        let now: Double = clock.now()
        let c = core.sequencer.clock.read()
        let sr: Double = AudioCore.sampleRate
        var sends: [MidiOutPlan.Send] = []
        while let e = core.sampler.midiOut.pop() {
            // Кадр события → момент, когда он слышен (нет времени блока — сейчас).
            var t: Double = now + lat
            if c.blockHost > 0 { t = c.blockHost + (Double(e.frame) - c.blockFrame) / sr + lat }
            let ti: Int = Int(e.track)
            let route: MidiOutRoute? = ti >= 0 && ti < r.count ? r[ti] : nil
            sends += plan.add(e, time: t + off, route: route, sampleRate: sr)
        }
        sends += plan.due(now: now, ahead: 0.02)
        if sends.isEmpty { return }
        var byDest: [Int32: [(at: UInt64, word: UInt32)]] = [:]
        for s in sends {
            byDest[s.dest, default: []].append((at: clock.ticks(seconds: s.time), word: s.word))
        }
        host.sendNotes(byDest)
    }
}
