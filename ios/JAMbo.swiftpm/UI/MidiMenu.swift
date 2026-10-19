import SwiftUI

/// Вкладки меню MIDI.
enum MidiTab: String, CaseIterable {
    case devices = "DEVICES"
    case mapping = "MAPPING"
    case notes = "NOTES"
}

/// Бутерброд → MIDI (S13a, как ui/midi.ts веба): стрелка назад и «MIDI», вкладки, ниже — с чертой — открытая вкладка.
struct MidiMenuPage: View {
    let model: AppModel
    let back: () -> Void
    let close: () -> Void
    @Environment(\.theme) private var theme

    private var tab: MidiTab { return model.midiLearn.tab }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuBackHeader(title: "MIDI", back: back)
            MenuScroll {
                VStack(alignment: .leading, spacing: 8) {
                    tabs
                    Divider().overlay(theme.line).padding(.vertical, 6)
                    section
                }
                .padding(.trailing, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var section: some View {
        switch tab {
        case .devices: MidiDevicesTab(model: model)
        case .mapping: MidiMappingTab(model: model, close: close)
        case .notes: MidiNotesTab(model: model)
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(MidiTab.allCases, id: \.self) { t in
                MenuItem(title: t.rawValue, current: tab == t) { model.midiLearn.tab = t }
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
            bluetooth
        }
    }

    /// BLUETOOTH MIDI (S13f): CONNECT и ADVERTISE — системные окна; без capability Bluetooth — неактивны.
    @ViewBuilder
    private var bluetooth: some View {
        let on: Bool = BluetoothMidi.available
        FieldLabel(title: "BLUETOOTH MIDI")
        HStack(spacing: 4) {
            MenuItem(title: "CONNECT", enabled: on) { BluetoothMidi.connect() }
            MenuItem(title: "ADVERTISE", enabled: on) { BluetoothMidi.advertise() }
        }
        if on {
            SettingsNote(text: "CONNECT: find and connect Bluetooth MIDI devices (tap a connected one to disconnect). ADVERTISE: make this iPad visible to other devices as a Bluetooth MIDI device. Connected devices appear in the lists above.")
        } else {
            SettingsNote(text: "Bluetooth access is not enabled in this build.")
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

/// MAPPING: MIDI LEARN (меню закрывается, внизу — полоса LEARN), список маппингов (✕ — удалить), CLEAR ALL.
struct MidiMappingTab: View {
    let model: AppModel
    let close: () -> Void

    var body: some View {
        let maps: [MidiMapping] = model.settings.midi.mappings
        // Кроссфейдер — своей закреплённой строкой выше.
        let rows: [Int] = (0..<maps.count).filter { maps[$0].target != MidiTarget.crossfader }
        return VStack(alignment: .leading, spacing: 8) {
            MenuItem(title: "MIDI LEARN") {
                close()
                model.setLearn(true)
            }
            ToggleRow(title: "KNOB PRESS = TOUCH", isOn: model.settings.midi.pressTouch) { on in model.setMidi { $0.pressTouch = on } }
            SettingsNote(text: "ON: a knob’s push button works like a finger on the knob — press to touch, press twice for a double tap. OFF: it runs the Action set in MIDI MAP.")
            SettingsNote(text: "MIDI LEARN: tap a knob or button on screen, then move a control. Knobs are mapped by position in the 4×4 grid and follow the current mode (track, FX, MOD, MIX, MST); switch to PRESS to map a knob’s push button. Double-tap a target to open MIDI MAP; tap a mapping below to edit it. Hold a step to p-lock, hold LFO/ENV to set modulation.")
            FieldLabel(title: "CROSSFADER")
            crossfader
            FieldLabel(title: "MAPPINGS (\(rows.count))")
            if rows.isEmpty { SettingsNote(text: "No mappings yet.") }
            ForEach(rows, id: \.self) { k in
                MidiMapRow(mapping: maps[k], device: model.midiPortName(maps[k].input, inputs: true, none: "ANY INPUT"),
                           place: model.placeLabel(maps[k]), open: {
                    close()
                    model.openMapFromList(k)
                }, remove: { model.removeMapping(k) })
            }
            MenuItem(title: "CLEAR ALL", enabled: !maps.isEmpty, red: !maps.isEmpty) { model.clearMappings() }
        }
    }
}

extension MidiMappingTab {
    /// Кроссфейдер перехода MIX — строка закреплена (решение пользователя): маппинг или «Not mapped»; тап — окно MIDI MAP.
    @ViewBuilder
    var crossfader: some View {
        let k: Int? = model.settings.midi.mappings.firstIndex { $0.target == MidiTarget.crossfader }
        if let k = k {
            let maps: [MidiMapping] = model.settings.midi.mappings
            MidiMapRow(mapping: maps[k], device: model.midiPortName(maps[k].input, inputs: true, none: "ANY INPUT"),
                       place: nil, open: {
                close()
                model.openMapFromList(k)
            }, remove: { model.removeMapping(k) })
        } else {
            MidiMapLine(label: "XFADER", value: "Not mapped") {
                close()
                model.openMap(MidiTarget.crossfader, back: true)
            }
        }
    }
}

/// Строка маппинга: источник → цель, тип управления и условие; ✕ — удалить.
struct MidiMapRow: View {
    let mapping: MidiMapping
    let device: String
    let place: String?
    let open: () -> Void
    let remove: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.src.label + "  ·  " + device).font(.system(size: 12, weight: .bold)).foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(detail).font(.system(size: 11)).foregroundStyle(theme.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
            MenuItem(title: "✕", red: true, action: remove).frame(width: 40)
        }
        .contentShape(Rectangle())
        .onTapGesture { open() }
    }

    /// Цель (у глобальной ручки — и параметр места), тип управления, условие: GLOBAL, PAGE, CLIPS.
    private var detail: String {
        var s: String = mapping.target.label
        if let p = place { s += " (" + p + ")" }
        s += "  ·  " + mapping.control.title
        switch mapping.cond {
        case .global: s += "  ·  GLOBAL"
        case .page: s += "  ·  PAGE"
        case .clip: s += "  ·  CLIPS"
        }
        return s
    }
}
