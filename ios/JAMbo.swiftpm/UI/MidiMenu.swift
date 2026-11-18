import SwiftUI

/// Страница меню MIDI (18.11, решение пользователя): general — само меню MIDI (общее и кнопка DEVICES), devices —
/// вложенное меню со списком устройств.
enum MidiTab: String {
    case general
    case devices
}

/// Бутерброд → MIDI (S13a): стрелка назад и «MIDI», кнопка DEVICES на всю ширину, ниже — с чертой — общее; DEVICES и
/// открытое устройство — вложенные меню (стрелка назад — на уровень выше). Все уровни — строками FormRows одного вида
/// (объём сборки: отдельный вид на уровень дороже). Окна: переименование, EXPORT, IMPORT с занятым именем, ошибки IMPORT.
struct MidiMenuPage: View {
    let model: AppModel
    let back: () -> Void
    let close: () -> Void
    @State private var text: String = ""

    var body: some View {
        let ml: MidiLearnState = model.midiLearn
        let m: AppModel = model
        return AnyView(page)
            .onChange(of: ml.renaming) { _, n in
                if let n = n { text = n }
            }
            .inputAlert("RENAME", shown: flag(ml.renaming != nil) { ml.renaming = nil }, text: $text) {
                if let from = ml.renaming { m.renameDevice(from, to: text) }
                ml.renaming = nil
            }
            .fileMover(isPresented: flag(ml.exported != nil) { ml.exported = nil }, file: ml.exported) { _ in ml.exported = nil }
            .confirmationDialog("\(ml.pending?.name ?? "") already exists", isPresented: flag(ml.pending != nil) { ml.pending = nil },
                                titleVisibility: .visible) {
                Button("Replace") { m.importPending(replace: true) }
                Button("Add copy") { m.importPending(replace: false) }
                Button("Cancel", role: .cancel) { ml.pending = nil }
            }
            .noticeAlert("MIDI devices", shown: flag(ml.note != nil) { ml.note = nil }, message: ml.note ?? "", cancel: false) {
                ml.note = nil
            }
    }

    /// Окно показано, пока есть его значение; закрыли — сбросить.
    private func flag(_ on: Bool, _ off: @escaping () -> Void) -> Binding<Bool> {
        return Binding(get: { on }, set: { if !$0 { off() } })
    }

    private var page: some View {
        let devices: Bool = model.midiLearn.tab == .devices
        let dev: String? = devices ? model.midiLearn.device : nil
        let m: AppModel = model
        let back: () -> Void = self.back
        let title: String = dev ?? (devices ? "DEVICES" : "MIDI")
        let rows: [FormRow] = dev.map { deviceRows($0) } ?? (devices ? deviceList : general)
        return VStack(alignment: .leading, spacing: 8) {
            MenuBackHeader(title: title, caps: dev == nil) {
                if dev != nil {
                    m.midiLearn.device = nil
                } else if devices {
                    m.midiLearn.tab = .general
                } else {
                    back()
                }
            }
            MenuScroll {
                FormRows(rows: rows).padding(.trailing, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Само меню MIDI: DEVICES, MIDI LEARN, KNOB PRESS, Bluetooth MIDI. Вход и выход нот — только у дорожек (8.11).
    private var general: [FormRow] {
        let m: AppModel = model
        let close: () -> Void = self.close
        let touch: Bool = m.settings.midi.pressTouch
        let bt: Bool = BluetoothMidi.available
        return [
            // Кнопка DEVICES — на всю ширину, как MIDI LEARN; открывает вложенное меню.
            .choices([MenuChoice(title: "DEVICES", current: false) { m.midiLearn.tab = .devices }]),
            .view(AnyView(Divider().overlay(theme.line).padding(.vertical, 6))),
            .choices([MenuChoice(title: "MIDI LEARN", current: false) {
                close()
                m.setLearn(true)
            }]),
            .note("MIDI LEARN: tap a knob or button on screen, then move a control. The mapping is saved to the device the control belongs to (see DEVICES). Knobs are mapped by position in the 4×4 grid and follow the current mode (track, FX, MOD, MIX, MST); switch to PRESS to map a knob’s push button. Double-tap a target to open MIDI MAP. Hold a step to p-lock, hold LFO/ENV to set modulation."),
            // Нажатие ручки (18.11, решение пользователя): TOUCH — как палец, MIDI MAP — Action маппинга.
            .label("KNOB PRESS"),
            .choices([MenuChoice(title: "TOUCH", current: touch) { m.setMidi { $0.pressTouch = true } },
                      MenuChoice(title: "MIDI MAP", current: !touch) { m.setMidi { $0.pressTouch = false } }]),
            .note("TOUCH: a knob’s push button works like a finger on the knob — press to touch, press twice for a double tap; with SHIFT held, a press is SHIFT + tap and holding it 1 s saves the knob’s default. MIDI MAP: each push button runs its own Action set in MIDI MAP — Reset, Param or any button."),
            .note("Note input and output are set on each track: sound menu → MIDI. By default tracks do not receive notes."),
            // BLUETOOTH MIDI (S13f): CONNECT и ADVERTISE — системные окна; без capability Bluetooth — неактивны.
            .label("BLUETOOTH MIDI"),
            .choices([
                MenuChoice(title: "CONNECT", enabled: bt, current: false) { BluetoothMidi.connect() },
                MenuChoice(title: "ADVERTISE", enabled: bt, current: false) { BluetoothMidi.advertise() },
            ]),
            .note(bt ? "CONNECT: find and connect Bluetooth MIDI devices (tap a connected one to disconnect). ADVERTISE: make this iPad visible to other devices as a Bluetooth MIDI device. Connected devices appear in DEVICES."
                  : "Bluetooth access is not enabled in this build."),
        ]
    }

    /// DEVICES: встроенные (JAMboPAD) и свои (появляются сами при подключении нового входа). Рычажок — вкл./выкл.
    /// (включённых — сколько угодно, маппинги работают вместе); тап — страница устройства; свайп влево — EXPORT,
    /// карандаш и корзина, у встроенного — EXPORT и RESTORE (изогнутая стрелка). Внизу — IMPORT.
    private var deviceList: [FormRow] {
        let m: AppModel = model
        var rows: [FormRow] = []
        for d in model.settings.midi.devices { rows.append(.view(deviceRow(d))) }
        rows.append(.choices([MenuChoice(title: "IMPORT", current: false) { m.chooseDeviceFiles() }]))
        rows.append(.note("Turn on the devices you play with: each keeps its own mappings, and all devices that are on work together. A new MIDI device appears here when you connect it. Tap a device to see its mappings and settings; swipe left to export it to a file, rename or delete it (built-in: restore the original mappings). IMPORT loads a device file (.json)."))
        return rows
    }

    /// Строка устройства: рычажок слева, имя, подключено ли и число маппингов.
    private func deviceRow(_ d: MidiDevice) -> AnyView {
        let m: AppModel = model
        let own: Bool = d.controller == nil
        let linked: Bool = m.midi.inputs.contains { d.owns($0.name) } || m.midi.outputs.contains { d.owns($0.name) }
        var r = SwipeRow(title: d.name, subtitle: linked ? "Connected" : "Not connected", meta: "\(d.mappings.count)",
                         height: 48, tap: { m.midiLearn.device = d.name },
                         rename: own ? { m.midiLearn.renaming = d.name } : nil,
                         delete: { if own { m.removeDevice(d.name) } else { m.restoreDevice(d.name) } })
        r.export = { m.exportDevice(d.name) }
        if !own {
            r.delIcon = "arrow.counterclockwise"
            r.delTint = d.modified ? Color(hex: 0x8e8e93) : theme.meterTrack
        }
        return AnyView(HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { d.on }, set: { m.setDeviceOn(d.name, $0) }))
                .labelsHidden()
                .tint(theme.accent)
            r
        }.id(d.name))
    }

    /// Страница устройства: вкл./выкл., настройки контроллера (JAMboPAD), кроссфейдер, маппинги (✕ — удалить, тап —
    /// окно MIDI MAP), CLEAR ALL.
    private func deviceRows(_ name: String) -> [FormRow] {
        guard let d = model.settings.midi.device(name) else { return [] }
        let m: AppModel = model
        let maps: [MidiMapping] = d.mappings.filter { $0.target != MidiTarget.crossfader }
        var rows: [FormRow] = [.toggle("DEVICE ON", d.on) { m.setDeviceOn(name, $0) }]
        if !d.on { rows.append(.note("The device is off: its mappings do not work. Turn it on to use and edit them.")) }
        if d.controller is JamboPad { rows += JamboPadSection.rows(model) }
        // Кроссфейдер перехода MIX — строка закреплена (решение пользователя): маппинг или «Not mapped».
        if let x = d.mappings.first(where: { $0.target == MidiTarget.crossfader }) {
            rows.append(.view(mapRow(x, on: d.on)))
        } else {
            let close: () -> Void = self.close
            rows.append(.view(AnyView(MidiMapLine(label: "XFADER", value: "Not mapped") {
                guard d.on else { return }
                close()
                m.openMap(MidiTarget.crossfader, back: true)
            })))
        }
        rows.append(.label("MAPPINGS (\(maps.count))"))
        if maps.isEmpty { rows.append(.note("No mappings yet: use MIDI LEARN and move a control on this device.")) }
        for x in maps { rows.append(.view(mapRow(x, on: d.on))) }
        rows.append(.choices([MenuChoice(title: "CLEAR ALL", enabled: !maps.isEmpty, red: !maps.isEmpty, current: false) { m.clearDevice(name) }]))
        return rows
    }

    private func mapRow(_ x: MidiMapping, on: Bool) -> AnyView {
        let m: AppModel = model
        let close: () -> Void = self.close
        return AnyView(MidiMapRow(mapping: x, device: x.input == nil ? "" : m.midiPortName(x.input, inputs: true, none: ""),
                                  place: m.placeLabel(x), open: {
            guard on else { return }
            close()
            m.openMapFromList(x)
        }, remove: { m.removeMapping(x) })
        .opacity(on ? 1 : 0.5))
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

/// JAMboPAD (два SMC-PAD со своей прошивкой) — на странице устройства: у левого и правого пэда свой разъём MIDI OUT
/// (SET_MIDI_OUT — на этот пэд; сторону и нынешнюю настройку пэд сообщает в ответ на HELLO). Гамма уходит пэдам сама,
/// пока устройство включено.
enum JamboPadSection {
    static func rows(_ model: AppModel) -> [FormRow] {
        var rows: [FormRow] = []
        for side in [JamboPad.sideLeft, JamboPad.sideRight] { rows += pad(model, side) }
        let known: Int = model.padOutputs(JamboPad.sideLeft).count + model.padOutputs(JamboPad.sideRight).count
        let waiting: Int = model.controllerOutputs(JamboPad()).count - known
        if waiting > 0 { rows.append(.note("Pads not identified yet: \(waiting) (no reply to HELLO).")) }
        let old: Bool = model.midiLearn.pads.values.contains { !$0.jack }
        if old { rows.append(.note("Update the pad firmware to use its MIDI OUT jack for track notes.")) }
        rows.append(.note("MIDI OUT: what each pad passes from JAMbo to its 3.5 mm jack — CLOCK: clock, start and stop; ALL: everything JAMbo sends to that pad, light feedback included. Track notes: pick JAMboPAD L or R · MIDI OUT as the track’s MIDI OUT device — they reach the jack in any mode. PAD MESSAGES: the pad’s own notes and CC go to the jack too. Each pad keeps its setting. Scale, key note and keyboard octave are sent to the pads automatically (over USB); a key note or scale picked on a pad changes ROOT or SCALE. The mappings follow the pads’ default layout; change them to match yours, the arrow (swipe left in DEVICES) restores them."))
        return rows
    }

    /// Пэд стороны side: подпись, OFF / CLOCK / ALL и рычажок PAD MESSAGES; не подключён — серые.
    private static func pad(_ model: AppModel, _ side: Int) -> [FormRow] {
        let m: AppModel = model
        let name: String = side == JamboPad.sideLeft ? "LEFT" : "RIGHT"
        let on: Bool = !m.padOutputs(side).isEmpty
        let cur: PadOut? = m.midiLearn.pads[side]
        let titles: [String] = ["OFF", "CLOCK", "ALL"]
        var thru: [MenuChoice] = []
        for k in 0..<titles.count {
            thru.append(MenuChoice(title: titles[k], enabled: on, current: on && cur?.thru == k) { m.setPadMidiOut(side, thru: k) })
        }
        var rows: [FormRow] = [.label(name + " PAD MIDI OUT" + (on ? "" : " — NOT CONNECTED")), .choices(thru)]
        if on {
            rows.append(.toggle(name + " PAD MESSAGES TO MIDI OUT", cur?.controls ?? false) { m.setPadMidiOut(side, controls: $0) })
        }
        return rows
    }
}
