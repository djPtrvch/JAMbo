import Foundation

/// MIDI-клок (S13e): SEND — по таймеру UI (drain) планировщик ClockPlan ставит тики, Start и Stop на 100 мс вперёд,
/// MidiHost шлёт их с метками времени. Моменты — когда слышен звук (время блока + задержка выхода) + MIDI OFFSET.
extension AppModel {
    func tickMidiClock() {
        let s: SyncSettings = settings.sync
        guard s.clock && s.source == .send && midi.started else {
            if midiRun.clockPlan.last != nil { midiRun.clockPlan.reset() }
            return
        }
        let clock = HostClock()
        let now: Double = clock.now()
        let offset: Double = Double(s.midiOffset) / 1000
        // Отрицательный сдвиг — планировать дальше вперёд, чтобы тики уходили заранее.
        let ahead: Double = 0.1 + max(0, -offset)
        let r = midiRun.clockPlan.update(now: now, bpm: project.bpm, play: clockGrid(), startStop: s.midiStartStop,
                                         lookahead: ahead)
        if r.flush { midi.flush(s.clockOut) }
        if r.events.isEmpty { return }
        var out: [(at: UInt64, word: UInt32)] = []
        for e in r.events {
            let word: UInt32 = MidiMessage.ump(status: e.kind.status, 0, 0)
            out.append((at: clock.ticks(seconds: e.time + offset), word: word))
        }
        midi.sendTimed(out, to: s.clockOut)
    }

    /// Сетка шагов из колбэка (PlayClock) во времени хоста, когда слышен звук; nil — не играет.
    private func clockGrid() -> ClockPlan.Grid? {
        let c = audio.core.sequencer.clock.read()
        guard c.playing && c.blockHost > 0 else { return nil }
        let sr: Double = AudioCore.sampleRate
        let t: Double = c.blockHost + (c.nextFrame - c.blockFrame) / sr + audio.outputLatency
        return ClockPlan.Grid(step: c.nextTick, time: t, stepDur: c.stepFrames / sr)
    }
}
