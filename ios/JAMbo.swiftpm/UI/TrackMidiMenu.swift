import SwiftUI

/// Меню звука → MIDI: вход и выход нот выбранной дорожки (TrackMidi, в проекте, с UNDO). Вход — устройство (ALL INPUTS,
/// одно или NONE) и канал (ALL — играет, только пока дорожка выбрана; 1–16 — всегда). Выход — устройство (NONE —
/// дорожка звучит сама) и канал 1–16; с выходом свой звук дорожки молчит. Стрелка назад — к движкам.
struct TrackMidiPage: View {
    let model: AppModel
    let back: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let m: TrackMidi = model.track.midi
        return VStack(alignment: .leading, spacing: 6) {
            MenuBackHeader(title: "MIDI · \(model.track.name)", caps: false, back: back)
            MenuScroll {
                VStack(alignment: .leading, spacing: 8) {
                    MenuHead(title: "MIDI IN")
                    FieldLabel(title: "DEVICE")
                    inDevices(m)
                    FieldLabel(title: "CHANNEL")
                    MenuItem(title: "ALL", enabled: m.inOn, current: m.inChannel == 0) { set { $0.inChannel = 0 } }
                    channels(m.inChannel, enabled: m.inOn) { c in set { $0.inChannel = c } }
                    SettingsNote(text: "ALL: the track plays notes only while it is selected. 1–16: the track always plays notes of this channel.")
                    Divider().overlay(theme.line).padding(.vertical, 6)
                    MenuHead(title: "MIDI OUT")
                    FieldLabel(title: "DEVICE")
                    MidiDeviceList(none: "NONE", devices: model.midi.outputs, current: m.outDevice) { id in
                        let name: String = model.midi.outputs.first { $0.id == id }?.name ?? ""
                        set { t in
                            t.outDevice = id
                            t.outName = name
                        }
                    }
                    FieldLabel(title: "CHANNEL")
                    channels(m.outChannel, enabled: m.sends) { c in set { $0.outChannel = c } }
                    SettingsNote(text: "With an output the track’s own sound is silent: its notes (steps, piano roll, keyboard, MIDI IN) go to the device.")
                }
                .padding(.trailing, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// ALL INPUTS, устройства, NONE; выбранное, но отключённое — серым.
    private func inDevices(_ m: TrackMidi) -> some View {
        let inputs: [MidiEndpoint] = model.midi.inputs
        return VStack(alignment: .leading, spacing: 4) {
            MenuItem(title: "ALL INPUTS", current: m.inOn && m.inDevice == nil) { setIn(nil, on: true) }
            ForEach(inputs) { d in
                MenuItem(title: d.name, current: m.inOn && m.inDevice == d.id) { setIn(d.id, on: true) }
            }
            if m.inOn, let c = m.inDevice, !inputs.contains(where: { $0.id == c }) {
                MenuItem(title: m.inName.isEmpty ? "NOT CONNECTED" : "\(m.inName) · NOT CONNECTED", enabled: false,
                         current: true) {}
            }
            MenuItem(title: "NONE", current: !m.inOn) { setIn(nil, on: false) }
        }
    }

    private func setIn(_ id: Int32?, on: Bool) {
        let name: String = model.midi.inputs.first { $0.id == id }?.name ?? ""
        set { t in
            t.inOn = on
            t.inDevice = id
            t.inName = name
        }
    }

    /// Каналы 1–16, по 4 в ряд.
    private func channels(_ current: Int, enabled: Bool, _ pick: @escaping (Int) -> Void) -> some View {
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)
        return LazyVGrid(columns: cols, spacing: 4) {
            ForEach(1...16, id: \.self) { c in
                MenuItem(title: "\(c)", enabled: enabled, current: current == c) { pick(c) }
            }
        }
    }

    private func set(_ change: (inout TrackMidi) -> Void) {
        model.editTrackMidi(change)
    }
}
