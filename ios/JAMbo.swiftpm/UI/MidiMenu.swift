import SwiftUI

/// Вкладки меню MIDI (18.11, решение пользователя): GENERAL — общее, DEVICES — устройства со своими маппингами.
enum MidiTab: String, CaseIterable {
    case general = "GENERAL"
    case devices = "DEVICES"
}

/// Бутерброд → MIDI (S13a): стрелка назад и «MIDI», вкладки, ниже — с чертой — открытая вкладка; открытое устройство —
/// вложенное меню (стрелка назад и имя устройства).
struct MidiMenuPage: View {
    let model: AppModel
    let back: () -> Void
    let close: () -> Void

    private var tab: MidiTab { return model.midiLearn.tab }

    var body: some View {
        let dev: String? = model.midiLearn.tab == .devices ? model.midiLearn.device : nil
        let m: AppModel = model
        let back: () -> Void = self.back
        return VStack(alignment: .leading, spacing: 8) {
            MenuBackHeader(title: dev ?? "MIDI", caps: dev == nil) {
                if dev != nil { m.midiLearn.device = nil } else { back() }
            }
            MenuScroll {
                VStack(alignment: .leading, spacing: 8) {
                    if dev == nil {
                        tabs
                        Divider().overlay(theme.line).padding(.vertical, 6)
                    }
                    section(dev)
                }
                .padding(.trailing, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(MidiDeviceAlerts(model: model))
    }

    private func section(_ dev: String?) -> AnyView {
        if let d = dev { return AnyView(MidiDevicePage(model: model, name: d, close: close)) }
        switch tab {
        case .general:
            return AnyView(MidiGeneralTab(model: model, close: close))
        case .devices:
            return AnyView(MidiDevicesTab(model: model))
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

/// GENERAL: MIDI LEARN, KNOB PRESS, Bluetooth MIDI. Вход и выход нот — только у дорожек (меню звука → MIDI; 8.11).
struct MidiGeneralTab: View {
    let model: AppModel
    let close: () -> Void

    var body: some View {
        let m: AppModel = model
        let close: () -> Void = self.close
        let touch: Bool = m.settings.midi.pressTouch
        var rows: [FormRow] = [
            .choices([MenuChoice(title: "MIDI LEARN", current: false) {
                close()
                m.setLearn(true)
            }]),
            .note("MIDI LEARN: tap a knob or button on screen, then move a control. The mapping is saved to the device the control belongs to (DEVICES). Knobs are mapped by position in the 4×4 grid and follow the current mode (track, FX, MOD, MIX, MST); switch to PRESS to map a knob’s push button. Double-tap a target to open MIDI MAP. Hold a step to p-lock, hold LFO/ENV to set modulation."),
            // Нажатие ручки (18.11, решение пользователя): TOUCH — как палец, MIDI MAP — Action маппинга.
            .label("KNOB PRESS"),
            .choices([MenuChoice(title: "TOUCH", current: touch) { m.setMidi { $0.pressTouch = true } },
                      MenuChoice(title: "MIDI MAP", current: !touch) { m.setMidi { $0.pressTouch = false } }]),
            .note("TOUCH: a knob’s push button works like a finger on the knob — press to touch, press twice for a double tap; with SHIFT held, a press is SHIFT + tap and holding it 1 s saves the knob’s default. MIDI MAP: each push button runs its own Action set in MIDI MAP — Reset, Param or any button."),
            .note("Note input and output are set on each track: sound menu → MIDI. By default tracks do not receive notes."),
        ]
        rows += bluetooth
        return FormRows(rows: rows)
    }

    /// BLUETOOTH MIDI (S13f): CONNECT и ADVERTISE — системные окна; без capability Bluetooth — неактивны.
    private var bluetooth: [FormRow] {
        let on: Bool = BluetoothMidi.available
        return [
            .label("BLUETOOTH MIDI"),
            .choices([
                MenuChoice(title: "CONNECT", enabled: on, current: false) { BluetoothMidi.connect() },
                MenuChoice(title: "ADVERTISE", enabled: on, current: false) { BluetoothMidi.advertise() },
            ]),
            .note(on ? "CONNECT: find and connect Bluetooth MIDI devices (tap a connected one to disconnect). ADVERTISE: make this iPad visible to other devices as a Bluetooth MIDI device. Connected devices appear in DEVICES."
                  : "Bluetooth access is not enabled in this build."),
        ]
    }
}

/// DEVICES: встроенные (JAMboPAD) и свои (появляются сами при подключении нового входа). Рычажок — вкл./выкл.
/// (включённых — сколько угодно, маппинги работают вместе); тап — страница устройства; свайп влево — карандаш и
/// корзина, у встроенного — RESTORE (изогнутая стрелка); первым — EXPORT файлом. Внизу — IMPORT.
struct MidiDevicesTab: View {
    let model: AppModel

    var body: some View {
        let list: [MidiDevice] = model.settings.midi.devices
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(list, id: \.name) { d in
                MidiDeviceRow(model: model, device: d)
            }
            MenuChoiceButtons(items: [MenuChoice(title: "IMPORT", current: false) { model.chooseDeviceFiles() }])
                .padding(.top, 4)
            SettingsNote(text: "Turn on the devices you play with: each keeps its own mappings, and all devices that are on work together. A new MIDI device appears here when you connect it. Tap a device to see its mappings and settings; swipe left to export it to a file, rename or delete it (built-in: restore the original mappings). IMPORT loads a device file (.json).")
                .padding(.vertical, 6)
        }
    }
}

/// Строка устройства: рычажок слева, имя, подключено ли и число маппингов.
struct MidiDeviceRow: View {
    let model: AppModel
    let device: MidiDevice

    var body: some View {
        let m: AppModel = model
        let d: MidiDevice = device
        let own: Bool = d.controller == nil
        var r = SwipeRow(title: d.name, subtitle: connected ? "Connected" : "Not connected", meta: "\(d.mappings.count)",
                         height: 48, tap: { m.midiLearn.device = d.name },
                         rename: own ? { m.midiLearn.renaming = d.name } : nil,
                         delete: { if own { m.removeDevice(d.name) } else { m.restoreDevice(d.name) } })
        r.export = { m.exportDevice(d.name) }
        if !own {
            r.delIcon = "arrow.counterclockwise"
            r.delTint = d.modified ? Color(hex: 0x8e8e93) : theme.meterTrack
        }
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { d.on }, set: { m.setDeviceOn(d.name, $0) }))
                .labelsHidden()
                .tint(theme.accent)
            r
        }
    }

    private var connected: Bool {
        return model.midi.inputs.contains { device.owns($0.name) } || model.midi.outputs.contains { device.owns($0.name) }
    }
}

/// Страница устройства: вкл./выкл., настройки контроллера (JAMboPAD), кроссфейдер, маппинги (✕ — удалить, тап — окно
/// MIDI MAP), CLEAR ALL.
struct MidiDevicePage: View {
    let model: AppModel
    let name: String
    let close: () -> Void

    var body: some View {
        guard let d = model.settings.midi.device(name) else { return AnyView(EmptyView()) }
        let m: AppModel = model
        let maps: [MidiMapping] = d.mappings.filter { $0.target != MidiTarget.crossfader }
        let name: String = self.name
        var rows: [FormRow] = [.toggle("DEVICE ON", d.on) { m.setDeviceOn(name, $0) }]
        if !d.on { rows.append(.note("The device is off: its mappings do not work. Turn it on to use and edit them.")) }
        if d.controller is JamboPad { rows += JamboPadSection.rows(model) }
        rows.append(.view(AnyView(crossfader(d))))
        rows.append(.label("MAPPINGS (\(maps.count))"))
        if maps.isEmpty { rows.append(.note("No mappings yet: use MIDI LEARN (GENERAL) and move a control on this device.")) }
        for x in maps { rows.append(.view(AnyView(row(x, on: d.on)))) }
        rows.append(.choices([MenuChoice(title: "CLEAR ALL", enabled: !maps.isEmpty, red: !maps.isEmpty, current: false) { m.clearDevice(name) }]))
        return AnyView(FormRows(rows: rows))
    }

    private func row(_ x: MidiMapping, on: Bool) -> some View {
        let m: AppModel = model
        let close: () -> Void = self.close
        return MidiMapRow(mapping: x, device: x.input == nil ? "" : m.midiPortName(x.input, inputs: true, none: ""),
                          place: m.placeLabel(x), open: {
            guard on else { return }
            close()
            m.openMapFromList(x)
        }, remove: { m.removeMapping(x) })
        .opacity(on ? 1 : 0.5)
    }

    /// Кроссфейдер перехода MIX — строка закреплена (решение пользователя): маппинг или «Not mapped»; тап — окно MIDI MAP.
    private func crossfader(_ d: MidiDevice) -> AnyView {
        if let x = d.mappings.first(where: { $0.target == MidiTarget.crossfader }) { return AnyView(row(x, on: d.on)) }
        let m: AppModel = model
        let close: () -> Void = self.close
        return AnyView(MidiMapLine(label: "XFADER", value: "Not mapped") {
            guard d.on else { return }
            close()
            m.openMap(MidiTarget.crossfader, back: true)
        })
    }
}

/// Устройства: переименование своего (системное окно ввода, до 40 знаков), EXPORT (окно сохранения в «Файлы»),
/// IMPORT с занятым именем — REPLACE / ADD COPY, непрочитанные файлы — окно с OK.
struct MidiDeviceAlerts: ViewModifier {
    let model: AppModel
    @State private var text: String = ""

    func body(content: Content) -> some View {
        content
            .onChange(of: model.midiLearn.renaming) { _, n in
                if let n = n { text = n }
            }
            .inputAlert("RENAME", shown: shown, text: $text) {
                if let from = model.midiLearn.renaming { model.renameDevice(from, to: text) }
                model.midiLearn.renaming = nil
            }
            .fileMover(isPresented: exportShown, file: model.midiLearn.exported) { _ in model.midiLearn.exported = nil }
            .confirmationDialog(pendingTitle, isPresented: pendingShown, titleVisibility: .visible) {
                Button("Replace") { model.importPending(replace: true) }
                Button("Add copy") { model.importPending(replace: false) }
                Button("Cancel", role: .cancel) { model.midiLearn.pending = nil }
            }
            .noticeAlert("MIDI devices", shown: noteShown, message: model.midiLearn.note ?? "", cancel: false) {
                model.midiLearn.note = nil
            }
    }

    private var pendingTitle: String {
        return "\(model.midiLearn.pending?.name ?? "") already exists"
    }

    private var pendingShown: Binding<Bool> {
        Binding(get: { model.midiLearn.pending != nil }, set: { if !$0 { model.midiLearn.pending = nil } })
    }

    private var exportShown: Binding<Bool> {
        Binding(get: { model.midiLearn.exported != nil }, set: { if !$0 { model.midiLearn.exported = nil } })
    }

    private var noteShown: Binding<Bool> {
        Binding(get: { model.midiLearn.note != nil }, set: { if !$0 { model.midiLearn.note = nil } })
    }

    private var shown: Binding<Bool> {
        Binding(get: { model.midiLearn.renaming != nil }, set: { if !$0 { model.midiLearn.renaming = nil } })
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

/// Строка маппинга: источник (и вход, если свой) → цель, тип управления и условие; ✕ — удалить.
struct MidiMapRow: View {
    let mapping: MidiMapping
    let device: String
    let place: String?
    let open: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.src.label + (device.isEmpty ? "" : "  ·  " + device)).font(.system(size: 12, weight: .bold)).foregroundStyle(theme.text)
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

/// JAMboPAD (два SMC-PAD со своей прошивкой) — на странице устройства: разъём MIDI OUT пэдов (SET_MIDI_OUT — сразу на
/// все SMC-PAD). Гамма уходит пэдам сама, пока устройство включено.
enum JamboPadSection {
    static func rows(_ model: AppModel) -> [FormRow] {
        let m: AppModel = model
        let ms: MidiSettings = model.settings.midi
        let titles: [String] = ["OFF", "CLOCK", "ALL"]
        var thru: [MenuChoice] = []
        for k in 0..<titles.count {
            thru.append(MenuChoice(title: titles[k], current: ms.padThru == k) { m.setPadMidiOut(thru: k) })
        }
        let pads: Int = model.controllerOutputs(JamboPad()).count
        let toggle: (Bool) -> Void = { (on: Bool) in m.setPadMidiOut(controls: on) }
        return [
            .label("PAD MIDI OUT"),
            .choices(thru),
            .toggle("PAD MESSAGES TO MIDI OUT", ms.padControls, toggle),
            .note((pads == 0 ? "No pads connected. " : "Pads connected: \(pads). ") + "MIDI OUT: what the pads pass from JAMbo to their 3.5 mm jack — CLOCK: clock, start and stop; ALL: everything JAMbo sends them. Scale, key note and keyboard octave are sent to the pads automatically (over USB); a key note or scale picked on a pad changes ROOT or SCALE. The mappings follow the pads’ default layout; change them to match yours, the arrow (swipe left in DEVICES) restores them."),
        ]
    }
}
