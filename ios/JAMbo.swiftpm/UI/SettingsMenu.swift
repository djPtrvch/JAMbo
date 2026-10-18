import AVFoundation
import AVKit
import SwiftUI

/// SETTINGS (S9d, как ui/settings.ts веба): стрелка назад и «Settings»; подпись SECTIONS и вкладки (APPEARANCE — тоже
/// вкладка); ниже — с чертой — открытая вкладка. Всё прокручивается пальцем.
struct SettingsPage: View {
    let model: AppModel
    let back: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuBackHeader(title: "Settings", back: back)
            MenuScroll {
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(title: "SECTIONS")
                    tabs
                    Divider().overlay(theme.line).padding(.vertical, 6)
                    section
                }
                .padding(.trailing, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var tabs: some View {
        let cols: [GridItem] = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4),
                                GridItem(.flexible(), spacing: 4)]
        return LazyVGrid(columns: cols, spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { t in
                MenuItem(title: t.rawValue, current: model.settingsTab == t) { model.settingsTab = t }
            }
        }
    }

    @ViewBuilder
    private var section: some View {
        switch model.settingsTab {
        case .engine: EngineSettings(model: model)
        case .record: RecordSettingsView(model: model)
        case .sampler: SamplerSettings(model: model)
        case .sidechain: SidechainSettings(model: model)
        case .output: OutputSettings(model: model)
        case .appearance: AppearanceSettings(model: model)
        case .mix: MixSettings(model: model)
        case .morph: MorphSettings(model: model)
        case .level: LevelSettings(model: model)
        }
    }
}

/// AUDIO ENGINE: фактическая частота, буфер и задержка (строка «Now:», раз в 0,5 с) и MUTE TAILS.
struct EngineSettings: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                SettingsNote(text: "Now: \(model.audio.statusLine)")
            }
            SettingsNote(text: "Always 48 kHz with a 256-sample buffer; iPadOS may choose another buffer.")
            ToggleRow(title: "MUTE TAILS", isOn: model.settings.muteTails) { model.setMuteTails($0) }
            SettingsNote(text: "OFF: muting a track cuts its sound and sends at once; Reverb and Delay tails ring out. ON: if the muted track is the only one sending to Delay, the Delay repeats are cut too.")
        }
    }
}

/// RECORD: QUANTIZE, OVERDUB (AUTOMATION RECORDING — с автоматизацией, S13).
struct RecordSettingsView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(title: "QUANTIZE", isOn: model.settings.record.quantize) { model.setQuantize($0) }
            SettingsNote(text: "ON: a note played with REC lands on the nearest step. OFF: on the step where it was played.")
            ToggleRow(title: "OVERDUB", isOn: model.settings.record.overdub) { model.setOverdub($0) }
            SettingsNote(text: "ON: new notes are added to the pattern. OFF: steps the recording passes over are cleared, only the new notes stay.")
        }
    }
}

/// SAMPLER: SLICE NOTES — ноты маркеров нарезки по хроматической клавиатуре или по гамме.
struct SamplerSettings: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(title: "SLICE NOTES")
            HStack(spacing: 4) {
                MenuItem(title: "CHROMATIC", current: model.settings.sliceMap == .chromatic) { model.setSliceMap(.chromatic) }
                MenuItem(title: "SCALE", current: model.settings.sliceMap == .scale) { model.setSliceMap(.scale) }
            }
            SettingsNote(text: "Markers in the sample editor play their slice from a piano key. CHROMATIC: markers go up by semitone from C3 (C3, C#3, D3…). SCALE: markers follow the notes of the selected scale from its root note in octave 3; the marker notes change with the scale.")
        }
    }
}

/// SIDECHAIN: приглушаются ли посылы Reverb, Delay, Drive тем же Sidechain, что и выход дорожки.
struct SidechainSettings: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(title: "SIDECHAIN SENDS")
            ToggleRow(title: "REVERB", isOn: model.scSend(0)) { model.setScSend(0, $0) }
            ToggleRow(title: "DELAY", isOn: model.scSend(1)) { model.setScSend(1, $0) }
            ToggleRow(title: "DRIVE", isOn: model.scSend(2)) { model.setScSend(2, $0) }
            SettingsNote(text: "ON: the send level of the effect ducks with the sidechain. Effect tails keep playing. OFF: the send is not ducked.")
        }
    }
}

/// OUTPUT: системный выбор выхода (как в Пункте управления) и текущий выход.
struct OutputSettings: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(title: "OUTPUT")
            HStack(spacing: 8) {
                RoutePicker(tint: theme.text, active: theme.accent)
                    .frame(width: 48, height: 48)
                    .background(theme.panel, in: RoundedRectangle(cornerRadius: 8))
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text(OutputSettings.current()).font(.system(size: 13, weight: .bold)).lineLimit(2)
                        .foregroundStyle(theme.text)
                }
            }
            SettingsNote(text: "Tap the AirPlay icon to choose where the sound goes: the iPad speakers, headphones, Bluetooth, AirPlay or a USB audio interface. The same choice is in Control Center.")
        }
    }

    /// Имя текущего выхода (несколько — через запятую).
    static func current() -> String {
        let outs: [AVAudioSessionPortDescription] = AVAudioSession.sharedInstance().currentRoute.outputs
        if outs.isEmpty { return "No output" }
        return outs.map { $0.portName }.joined(separator: ", ")
    }
}

/// APPEARANCE: тема SYSTEM (как на iPad), LIGHT, DARK.
struct AppearanceSettings: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(title: "THEME")
            HStack(spacing: 4) {
                ForEach(Appearance.allCases, id: \.self) { a in
                    MenuItem(title: a.rawValue, current: model.appearance == a) { model.setAppearance(a) }
                }
            }
            SettingsNote(text: "SYSTEM follows the iPad setting.")
        }
    }
}

/// MIX: переходы между проектами (действуют с переходами MIX, S10).
struct MixSettings: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(title: "CHANGE KEY", isOn: model.settings.mixKey) { model.setMixKey($0) }
            SettingsNote(text: "ON: on a MIX transition the scale and root note change to the new project. OFF: the scale and root note stay as they are.")
            ToggleRow(title: "CROSSFADER", isOn: model.settings.mixCrossfader) { model.setMixCrossfader($0) }
            SettingsNote(text: "ON: the crossfader between projects sets the tempo (only the tempo). OFF: no crossfader; the tempo follows the old pattern.")
        }
    }
}

/// MORPH: ручки на все дорожки или на выбранную; возврат после выключения режима.
struct MorphSettings: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(title: "ALL TRACKS", isOn: model.settings.morphAll) { model.setMorphAll($0) }
            SettingsNote(text: "ON: in MORPH a knob changes its parameter on every track that has it (each track moves by the same amount from its own value). OFF: only the selected track.")
            FieldLabel(title: "RETURN")
            HStack(spacing: 4) {
                ForEach(0..<MorphReturn.names.count, id: \.self) { k in
                    MenuItem(title: MorphReturn.names[k], current: model.settings.morphReturn == k) { model.setMorphReturn(k) }
                }
            }
            SettingsNote(text: "How fast the knobs glide back when MORPH is turned off: OFF — at once, or over 1/4 bar to 2 bars at the current tempo.")
        }
    }
}

/// LEVEL: регулятор громкости справа у дорожки — ABSOLUTE или RELATIVE.
struct LevelSettings: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(title: "TRACK LEVEL FADER")
            HStack(spacing: 4) {
                MenuItem(title: "ABSOLUTE", current: !model.settings.levelRelative) { model.setLevelRelative(false) }
                MenuItem(title: "RELATIVE", current: model.settings.levelRelative) { model.setLevelRelative(true) }
            }
            SettingsNote(text: "ABSOLUTE: the fader on the right is the track volume in MIX. RELATIVE: the fader trims the track down from its MIX volume — the top of the fader is the MIX volume (for example −10 dB), down to silence. The trim is kept with the track and only works in RELATIVE.")
        }
    }
}

/// Кнопка выбора выхода iOS (AVRoutePickerView).
struct RoutePicker: UIViewRepresentable {
    let tint: Color
    let active: Color

    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = false
        v.tintColor = UIColor(tint)
        v.activeTintColor = UIColor(active)
        return v
    }

    func updateUIView(_ v: AVRoutePickerView, context: Context) {
        v.tintColor = UIColor(tint)
        v.activeTintColor = UIColor(active)
    }
}

/// Шапка вложенного меню: стрелка назад и название (PROJECTS, SETTINGS).
struct MenuBackHeader: View {
    let title: String
    let back: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Button(action: back) {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.text).frame(width: 40, height: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1).foregroundStyle(theme.text)
        }
    }
}

/// Подпись поля над переключателями (9 px, --dim).
struct FieldLabel: View {
    let title: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title).font(.system(size: 9, weight: .semibold)).tracking(0.6).foregroundStyle(theme.dim)
    }
}

/// Пояснение в меню (12 px, --dim).
struct SettingsNote: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(theme.dim).fixedSize(horizontal: false, vertical: true)
    }
}
