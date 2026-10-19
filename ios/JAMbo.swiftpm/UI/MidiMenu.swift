import SwiftUI

/// Вкладки меню MIDI (MAPPING — S13b).
enum MidiTab: String, CaseIterable {
    case devices = "DEVICES"
    case notes = "NOTES"
}

/// Бутерброд → MIDI (S13a, как ui/midi.ts веба): стрелка назад и «MIDI», вкладки, ниже — с чертой — открытая вкладка.
struct MidiPage: View {
    let model: AppModel
    let back: () -> Void
    @State private var tab: MidiTab = .devices
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuBackHeader(title: "MIDI", back: back)
            MenuScroll {
                VStack(alignment: .leading, spacing: 8) {
                    tabs
                    Divider().overlay(theme.line).padding(.vertical, 6)
                    if tab == .devices { MidiDevicesTab(model: model) } else { MidiNotesTab(model: model) }
                }
                .padding(.trailing, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(MidiTab.allCases, id: \.self) { t in
                MenuItem(title: t.rawValue, current: tab == t) { tab = t }
            }
        }
    }
}

/// DEVICES: вход (ALL INPUTS или один) и выход обратной связи (NONE или один).
struct MidiDevicesTab: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(title: "INPUT")
            if model.midi.inputs.isEmpty { SettingsNote(text: "No MIDI inputs connected.") }
            MidiDeviceList(none: "ALL INPUTS", devices: model.midi.inputs, current: model.settings.midi.input) { id in
                model.setMidi { $0.input = id }
            }
            FieldLabel(title: "FEEDBACK OUTPUT")
            if model.midi.outputs.isEmpty { SettingsNote(text: "No MIDI outputs connected.") }
            MidiDeviceList(none: "NONE", devices: model.midi.outputs, current: model.settings.midi.feedback) { id in
                model.setMidi { $0.feedback = id }
            }
            SettingsNote(text: "Knob values are sent back to this output, so encoder LED rings (Midi Fighter Twister) follow the screen.")
        }
    }
}

/// Список устройств: первый пункт — «все» или «нет» (nil); выбранное, но отключённое — серым с пометкой.
struct MidiDeviceList: View {
    let none: String
    let devices: [MidiEndpoint]
    let current: Int32?
    let pick: (Int32?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MenuItem(title: none, current: current == nil) { pick(nil) }
            ForEach(devices) { d in
                MenuItem(title: d.name, current: current == d.id) { pick(d.id) }
            }
            if let c = current, !devices.contains(where: { $0.id == c }) {
                MenuItem(title: "NOT CONNECTED", enabled: false, current: true) {}
            }
        }
    }
}

/// NOTES: канал нот (ALL, 1–16) и куда идут ноты (выбранная дорожка или канал N → дорожка N).
struct MidiNotesTab: View {
    let model: AppModel

    var body: some View {
        let s: MidiSettings = model.settings.midi
        let route: String = "CH 1–\(Params.maxTracks) → TRACKS"
        return VStack(alignment: .leading, spacing: 8) {
            FieldLabel(title: "NOTE CHANNEL")
            channels(s.noteChannel)
            FieldLabel(title: "NOTES PLAY")
            HStack(spacing: 4) {
                MenuItem(title: "SELECTED TRACK", current: s.noteRoute == .selected) { model.setMidi { $0.noteRoute = .selected } }
                MenuItem(title: route, current: s.noteRoute == .channel) { model.setMidi { $0.noteRoute = .channel } }
            }
            SettingsNote(text: "Notes from MIDI inputs play like the keyboard (and are recorded with REC). With \(route), channel N plays track N.")
        }
    }

    private func channels(_ current: Int) -> some View {
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)
        return LazyVGrid(columns: cols, spacing: 4) {
            ForEach(0..<17, id: \.self) { c in
                MenuItem(title: c == 0 ? "ALL" : "\(c)", current: current == c) { model.setMidi { $0.noteChannel = c } }
            }
        }
    }
}
