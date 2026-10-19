import Foundation

/// MIDI (S13a): сообщения с входов. Ноты играют как клавиатура (с REC — записываются, длина — по Note Off);
/// маппинги — S13b, клок — S13e.
extension AppModel {
    func startMidi() {
        midi.onMessage = { [weak self] msg, source in self?.midiMessage(msg, source: source) }
        midi.start()
    }

    func midiMessage(_ msg: MidiMessage, source: Int32) {
        let ms: MidiSettings = settings.midi
        guard ms.accepts(source: source) else { return }
        if msg.isRealtime { return }
        let id: Int = MidiSettings.keyId(channel: msg.channel, note: msg.data1)
        if msg.kind == .noteOff {
            keyUp(id: id)
            return
        }
        guard msg.kind == .noteOn else { return }
        guard let t = ms.noteTrack(msg, selected: selectedTrack, tracks: project.tracks.count) else { return }
        // Повторный Note On без Note Off — прежняя нота отпускается.
        if keyHolds[id] != nil { keyUp(id: id) }
        let v: Double = MidiSettings.velocity(msg.data2, sensitive: settings.velocity)
        keyDown(id: id, notes: [msg.data1], velocity: v, track: t)
    }

    func setMidi(_ change: (inout MidiSettings) -> Void) {
        updateSettings { s in change(&s.midi) }
    }
}
