import Foundation

/// MIDI-клок (S13e): SEND — по таймеру UI (drain) планировщик ClockPlan ставит тики, Start и Stop на 100 мс вперёд,
/// MidiHost шлёт их с метками времени. Моменты — когда слышен звук (время блока + задержка выхода) + MIDI OFFSET.
/// RECEIVE — ClockFollower: темп клока (точный — в звук, округлённый — в BPM проекта, без UNDO), старт по Start на
/// первом тике, поправка фазы раз на шаг; свои шаги звучат на MIDI OFFSET позже тиков.
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

    /// Сообщение реального времени с входа (время прихода at).
    func midiRealtime(_ kind: MidiKind, at: Double) {
        let s: SyncSettings = settings.sync
        guard s.clock && s.source == .receive else { return }
        var action: ClockFollower.Action? = nil
        if kind == .clock {
            action = midiRun.follower.tick(at: at)
            if let b = midiRun.follower.tempo {
                // Звук — по точному темпу клока, BPM проекта — округлённый.
                audio.core.events.push(.tempo(b))
                setClockBpm(b)
            }
        } else if s.midiStartStop {
            action = midiRun.follower.transport(kind, at: at, playing: playing)
        }
        guard let a = action else { return }
        switch a {
        case .start(let t):
            midiRun.follower.started(at: t)
            midiRun.clockWasPlaying = true
            midiRun.clockRefStep = -1
            startPlay(atFrame: frameHeard(at: t + Double(s.midiOffset) / 1000))
        case .stop:
            if playing { togglePlay() }
        }
    }

    /// Каждый кадр при RECEIVE: клок пропал — свой темп; старт своей кнопкой — шаг 0 на ближайшем тике; поправка
    /// фазы следующего шага (один раз на шаг).
    func tickClockFollow() {
        let s: SyncSettings = settings.sync
        let f: ClockFollower = midiRun.follower
        guard s.clock && s.source == .receive else {
            if f.last > 0 { midiRun.follower.lose() }
            return
        }
        let now: Double = HostClock().now()
        if f.last > 0 && now - f.last > ClockFollower.timeout {
            midiRun.follower.lose()
            audio.core.events.push(.tempo(project.bpm))
            return
        }
        let offset: Double = Double(s.midiOffset) / 1000
        let grid: ClockPlan.Grid? = clockGrid()
        // PLAY нажат, но колбэк ещё не начал игру (сетки нет) — прежнее состояние.
        defer { if grid != nil || !playing { midiRun.clockWasPlaying = playing } }
        guard let g = grid, f.alive(now: now) else {
            midiRun.clockRefStep = -1
            return
        }
        // Своя игра началась или клок вернулся после пропажи (переподключили устройство) — шаг 0 к ближайшему тику.
        if !midiRun.clockWasPlaying || !f.anchored {
            let t0: Double = g.time - Double(g.step) * g.stepDur
            midiRun.follower.started(at: t0 - offset)
        }
        if g.step == midiRun.clockRefStep { return }
        guard let t = midiRun.follower.stepTime(g.step) else { return }
        midiRun.clockRefStep = g.step
        audio.core.events.push(.clockPhase(step: g.step, frame: Double(frameHeard(at: t + offset))))
    }

    /// Кадр ядра, который будет слышен в момент хоста t.
    private func frameHeard(at t: Double) -> Int64 {
        let c = audio.core.sequencer.clock.read()
        if c.blockHost <= 0 { return Int64(audio.core.framesRendered) }
        let f: Double = c.blockFrame + (t - audio.outputLatency - c.blockHost) * AudioCore.sampleRate
        return Int64(f.rounded())
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
