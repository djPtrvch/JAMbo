import Foundation

/// MIDI дорожек (меню звука → MIDI): правка с UNDO, выходы для MidiOutPump (каждый кадр UI), ноты с входов —
/// на дорожки по их входу (TrackMidi).
extension AppModel {
    /// Правка MIDI выбранной дорожки (одна запись UNDO). Держащиеся ноты отпускаются на прежний выход (MidiOutPlan).
    func editTrackMidi(_ change: (inout TrackMidi) -> Void) {
        editTrack { t in change(&t.midi) }
    }

    /// Выходы дорожек, задержка выхода и MIDI OFFSET — в MidiOutPump; поток запускается с первым выходом.
    func tickMidiOut() {
        var routes: [MidiOutRoute?] = []
        var any: Bool = false
        for tr in project.tracks {
            if let d = tr.midi.outDevice {
                routes.append(MidiOutRoute(dest: d, channel: tr.midi.outChannel - 1))
                any = true
            } else {
                routes.append(nil)
            }
        }
        if midiOutPump == nil {
            if !any { return }
            let p = MidiOutPump(core: audio.core, host: midi)
            p.start()
            midiOutPump = p
        }
        midiOutPump?.update(routes: routes, latency: audio.outputLatency, offset: Double(settings.sync.midiOffset) / 1000)
    }

    /// Нота с входа source (не назначенная): как клавиша на каждой дорожке, вход которой её принимает.
    func midiNote(_ msg: MidiMessage, source: Int32) {
        if msg.kind == .noteOff {
            for t in 0..<Params.maxTracks {
                let id: Int = MidiSettings.keyId(track: t, channel: msg.channel, note: msg.data1)
                if keyHolds[id] != nil { keyUp(id: id) }
            }
            return
        }
        guard msg.kind == .noteOn else { return }
        let v: Double = MidiSettings.velocity(msg.data2, sensitive: settings.velocity)
        for t in TrackMidi.tracks(project, source: source, channel: msg.channel, selected: selectedTrack) {
            let id: Int = MidiSettings.keyId(track: t, channel: msg.channel, note: msg.data1)
            // Повторный Note On без Note Off — прежняя нота отпускается.
            if keyHolds[id] != nil { keyUp(id: id) }
            keyDown(id: id, notes: [msg.data1], velocity: v, track: t)
        }
    }
}
