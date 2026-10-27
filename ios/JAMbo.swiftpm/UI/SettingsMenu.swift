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
        case .defaults: DefaultsSettings(model: model)
        case .arrange: ArrangeSettings(model: model)
        }
    }
}

/// ARRANGE (S15): вид дорожек аранжировщика — EXPANDED (по умолчанию: 8 дорожек на высоту окна, больше — прокрутка) или
/// COMPACT (все на высоту окна); GRID — шаг сетки таймлайна (1 BAR, 1/2, 1/4, 1 STEP); ROW REPEATS — клипы строки в
/// аранжировку на длину × повторы строки.
struct ArrangeSettings: View {
    let model: AppModel

    var body: some View {
        let on: Bool = model.settings.arrangeExpanded
        return VStack(alignment: .leading, spacing: 8) {
            FieldLabel(title: "TRACKS")
            HStack(spacing: 4) {
                MenuItem(title: "EXPANDED", current: on) { model.updateSettings { $0.arrangeCompact = false } }
                MenuItem(title: "COMPACT", current: !on) { model.updateSettings { $0.arrangeCompact = true } }
            }
            SettingsNote(text: "EXPANDED: 8 tracks fill the arranger window, more tracks scroll. COMPACT: all tracks fit the arranger window.")
            // Шаг сетки таймлайна (решение пользователя: из строки аранжировщика — сюда); у проекта, с UNDO.
            FieldLabel(title: "GRID")
            HStack(spacing: 4) {
                ForEach(0..<ArrGrid.names.count, id: \.self) { k in
                    MenuItem(title: ArrGrid.names[k], current: model.project.arrange.grid == k) { model.setArrGrid(k) }
                }
            }
            ToggleRow(title: "ROW REPEATS", isOn: model.settings.arrangeRepeats) { v in model.updateSettings { $0.arrangeRepeats = v } }
            SettingsNote(text: "ON: clips go to the arrangement as long as the row repeats (×4 on a 1-bar clip — a 4-bar block). OFF: one pass.")
        }
    }
}

/// AUDIO ENGINE: фактическая частота, буфер и задержка (строка «Now:», раз в 0,5 с); BACKGROUND AUDIO.
struct EngineSettings: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                SettingsNote(text: "Now: \(model.audio.statusLine)")
            }
            SettingsNote(text: "Always 48 kHz with a 256-sample buffer; iPadOS may choose another buffer.")
            ToggleRow(title: "BACKGROUND AUDIO", isOn: model.settings.backgroundAudio) { model.setBackgroundAudio($0) }
            SettingsNote(text: "ON: the sound keeps playing when JAMbo is in the background or the screen is locked. OFF: the sound stops.")
        }
    }
}

/// RECORD: QUANTIZE, STEP SWIPE (OVERDUB — в меню клавиатуры; AUTOMATION RECORDING — с автоматизацией).
struct RecordSettingsView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToggleRow(title: "QUANTIZE", isOn: model.settings.record.quantize) { model.setQuantize($0) }
            SettingsNote(text: "ON: a note played with REC lands on the nearest step. OFF: on the step where it was played.")
            FieldLabel(title: "STEP SWIPE")
            HStack(spacing: 4) {
                MenuItem(title: "LENGTH", current: !model.settings.stepPaint) { model.updateSettings { $0.stepPaint = false } }
                MenuItem(title: "PAINT", current: model.settings.stepPaint) { model.updateSettings { $0.stepPaint = true } }
            }
            SettingsNote(text: "Sliding a finger along the steps: LENGTH — one long note from the first step. PAINT — a trig on every step you pass.")
        }
    }
}

/// SAMPLER: STRETCH — алгоритм таймстретча RATE (NORMAL по умолчанию, BEAT); SLICE NOTES — ноты маркеров нарезки по
/// хроматической клавиатуре или по гамме; PITCH (S12; ещё — SHIFT + тап по ручке Pitch); CLEAR SAMPLE LOCKS (S11b).
struct SamplerSettings: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(title: "STRETCH")
            HStack(spacing: 4) {
                MenuItem(title: "NORMAL", current: !model.settings.stretchBeat) { model.setStretchBeat(false) }
                MenuItem(title: "BEAT", current: model.settings.stretchBeat) { model.setStretchBeat(true) }
            }
            SettingsNote(text: "Rate knob in Stretch mode keeps the pitch while the speed changes. NORMAL — for any material: tones stay clean, hits stay sharp. BEAT — lighter, for drum loops.")
            FieldLabel(title: "SLICE NOTES")
            HStack(spacing: 4) {
                MenuItem(title: "CHROMATIC", current: model.settings.sliceMap == .chromatic) { model.setSliceMap(.chromatic) }
                MenuItem(title: "SCALE", current: model.settings.sliceMap == .scale) { model.setSliceMap(.scale) }
            }
            SettingsNote(text: "Markers in the sample editor play their slice from a piano key. CHROMATIC: markers go up by semitone from C3 (C3, C#3, D3…). SCALE: markers follow the notes of the selected scale from its root note in octave 3; the marker notes change with the scale.")
            FieldLabel(title: "PITCH")
            HStack(spacing: 4) {
                MenuItem(title: "SEMITONES", current: model.settings.pitchSemitones) { model.updateSettings { $0.pitchSemitones = true } }
                MenuItem(title: "SMOOTH", current: !model.settings.pitchSemitones) { model.updateSettings { $0.pitchSemitones = false } }
            }
            SettingsNote(text: "Sample Pitch knob and its step locks: SEMITONES — whole semitones, SMOOTH — any value. LFO and ENV stay smooth. SHIFT + tap on the Pitch knob switches it too.")
            ToggleRow(title: "CLEAR SAMPLE LOCKS", isOn: model.settings.clearSampleLocks) { model.setClearSampleLocks($0) }
            SettingsNote(text: "ON: loading sounds from the library onto a track removes its sample locks — those steps play the track sound at their own note. Preset locks stay. OFF: sample locks keep their samples.")
        }
    }
}

/// SIDECHAIN: приглушаются ли посылы Reverb, Delay, Drive тем же Sidechain, что и выход дорожки; MUTE TAILS
/// (в вебе — в AUDIO ENGINE; здесь — решение пользователя).
struct SidechainSettings: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(title: "DUCK SENDS")
            ToggleRow(title: "REVERB", isOn: model.scSend(0)) { model.setScSend(0, $0) }
            ToggleRow(title: "DELAY", isOn: model.scSend(1)) { model.setScSend(1, $0) }
            ToggleRow(title: "DRIVE", isOn: model.scSend(2)) { model.setScSend(2, $0) }
            SettingsNote(text: "ON: the send level of the effect is ducked by Duck too. Effect tails keep playing. OFF: the send is not ducked.")
            FieldLabel(title: "MUTE").padding(.top, 8)
            ToggleRow(title: "MUTE TAILS", isOn: model.settings.muteTails) { model.setMuteTails($0) }
            SettingsNote(text: "OFF: when you mute a track, the echoes already in Delay keep ringing out. ON: if the muted track was the only one sending to Delay, its echoes stop at once. Reverb tails always ring out.")
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

/// APPEARANCE: тема SYSTEM (как на iPad), LIGHT, DARK; FX ANIMATION — картинки FX в окне сэмпла.
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
            ToggleRow(title: "FX ANIMATION", isOn: model.settings.fxPictures) { model.setFxPictures($0) }
            SettingsNote(text: "While an FX knob is turned, the sample window shows a picture of the effect.")
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
            SettingsNote(text: "ABSOLUTE: the fader on the right is the track volume in MIX. RELATIVE: the fader trims the track down from its MIX volume — it cannot go above the MIX volume (for example −10 dB), down to silence; when the MIX volume changes, the trimmed level moves with it. The trim is kept with the track and only works in RELATIVE.")
        }
    }
}

/// DEFAULTS: свои значения ручек по умолчанию (KnobDefaults) — как запомнить и сбросить; забыть все.
struct DefaultsSettings: View {
    let model: AppModel

    var body: some View {
        let n: Int = model.knobDefaultsCount
        return VStack(alignment: .leading, spacing: 8) {
            FieldLabel(title: "KNOB DEFAULTS")
            SettingsNote(text: "SHIFT + hold a knob: its value becomes the default (the knob shows SAVED). Double tap a knob: back to its default; double tap again: back to the factory value. Your defaults are used by NEW projects and ADD TRACK; saved projects stay as they are. Sound knobs keep their own defaults for the sampler and for each synth engine.")
            SettingsNote(text: n == 0 ? "No saved defaults." : "Saved defaults: \(n).")
            HStack(spacing: 4) {
                MenuItem(title: "FORGET ALL", enabled: n > 0, red: true) { model.clearKnobDefaults() }
            }
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
