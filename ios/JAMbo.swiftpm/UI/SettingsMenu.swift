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
            MenuBackHeader(title: "SETTINGS", back: back)
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

    /// Открытая вкладка — AnyView (S14: 11 веток switch давали глубоко вложенный тип и много кода у компилятора).
    private var section: AnyView {
        switch model.settingsTab {
        case .engine: return AnyView(EngineSettings(model: model))
        case .record: return AnyView(RecordSettingsView(model: model))
        case .sampler: return AnyView(SamplerSettings(model: model))
        case .sidechain: return AnyView(SidechainSettings(model: model))
        case .output: return AnyView(OutputSettings(model: model))
        case .appearance: return AnyView(AppearanceSettings(model: model))
        case .mix: return AnyView(MixSettings(model: model))
        case .morph: return AnyView(MorphSettings(model: model))
        case .level: return AnyView(LevelSettings(model: model))
        case .defaults: return AnyView(DefaultsSettings(model: model))
        case .arrange: return AnyView(ArrangeSettings(model: model))
        }
    }
}

/// ARRANGE (S15): TRACKS — FIX (по умолчанию: кнопки EXPANDED / COMPACT под измерителем) или SCALE (масштаб строк
/// двумя пальцами по вертикали); FOLLOW PLAYHEAD; ROW REPEATS — клипы строки
/// в аранжировку на длину × повторы строки. Шаг сетки — в меню кнопки сетки аранжировщика.
struct ArrangeSettings: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        let scale: Bool = m.settings.arrangeScale
        return FormRows(rows: [
            .label("TRACKS"),
            .choices([MenuChoice(title: "FIX", current: !scale) { m.setArrScale(false) },
                      MenuChoice(title: "SCALE", current: scale) { m.setArrScale(true) }]),
            .note("FIX: track height by the buttons under the level meter — EXPANDED (8 tracks fill the window, more tracks scroll) or COMPACT (all tracks fit the window). SCALE: pinch vertically with two fingers to resize the tracks."),
            .toggle("FOLLOW PLAYHEAD", m.settings.arrangeFollow) { v in m.updateSettings { $0.arrangeFollow = v } },
            .note("ON: while playing, the arranger scrolls to keep the playhead in view."),
            .toggle("ROW REPEATS", m.settings.arrangeRepeats) { v in m.updateSettings { $0.arrangeRepeats = v } },
            .note("ON: clips go to the arrangement as long as the row repeats (×4 on a 1-bar clip — a 4-bar block). OFF: one pass."),
        ])
    }
}

/// AUDIO ENGINE: фактическая частота, буфер и задержка (строка «Now:», раз в 0,5 с); BACKGROUND AUDIO.
struct EngineSettings: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        let now: AnyView = AnyView(TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            SettingsNote(text: "Now: \(m.audio.statusLine)")
        })
        return FormRows(rows: [
            .view(now),
            .note("Always 48 kHz with a 256-sample buffer; iPadOS may choose another buffer."),
            .toggle("BACKGROUND AUDIO", m.settings.backgroundAudio) { m.setBackgroundAudio($0) },
            .note("ON: the sound keeps playing when JAMbo is in the background or the screen is locked. OFF: the sound stops."),
        ])
    }
}

/// Громкость метронома (как SWING в меню клавиатуры): полоса, тап и протягивание (0…200 %, 100 % — прежний уровень).
struct MetronomeSlider: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let v: Double = model.settings.metronomeVol
        let n: Double = v / 200
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("METRONOME").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.text)
                Spacer()
                Text("\(Int(v))%").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(theme.text)
            }
            GeometryReader { g in
                bar(g.size.width, n)
                    .contentShape(Rectangle())
                    .gesture(drag(g.size.width))
            }
            .frame(height: 24)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private func bar(_ w: CGFloat, _ n: Double) -> some View {
        let x: CGFloat = w * CGFloat(n)
        return ZStack(alignment: .leading) {
            Capsule().fill(theme.meterTrack).frame(height: 6)
            Capsule().fill(theme.accent).frame(width: max(6, x), height: 6)
            Circle().fill(Color.white).frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .offset(x: min(max(0, x - 11), w - 22))
        }
        .frame(maxHeight: .infinity)
    }

    private func drag(_ w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let k: Double = Double(min(max(0, g.location.x / max(1, w)), 1))
                model.setMetronomeVol(k * 200)
            }
    }
}

/// RECORD: QUANTIZE, STEP SWIPE (OVERDUB — в меню клавиатуры; AUTOMATION RECORDING — с автоматизацией).
struct RecordSettingsView: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        let paint: Bool = m.settings.stepPaint
        return FormRows(rows: [
            .toggle("QUANTIZE", m.settings.record.quantize) { m.setQuantize($0) },
            .note("ON: a note played with REC lands on the nearest step. OFF: on the step where it was played."),
            .label("ARRANGE REC START"),
            .choices([MenuChoice(title: "PLAYHEAD", current: !m.settings.record.arrFromStart) { m.updateSettings { $0.record.arrFromStart = false } },
                      MenuChoice(title: "BEGINNING", current: m.settings.record.arrFromStart) { m.updateSettings { $0.record.arrFromStart = true } }]),
            .note("Live recording into the arrangement (hold ARRANGE + tap REC, then PLAY in the pattern grid): PLAYHEAD — from the playhead. BEGINNING — always from the start of the timeline."),
            .label("STEP SWIPE"),
            .choices([MenuChoice(title: "LENGTH", current: !paint) { m.updateSettings { $0.stepPaint = false } },
                      MenuChoice(title: "PAINT", current: paint) { m.updateSettings { $0.stepPaint = true } }]),
            .note("Sliding a finger along the steps: LENGTH — one long note from the first step. PAINT — a trig on every step you pass."),
            .view(AnyView(MetronomeSlider(model: m))),
            .note("Click volume: 100% — the usual level, up to 200%."),
        ])
    }
}

/// SAMPLER: STRETCH — алгоритм таймстретча RATE (NORMAL по умолчанию, BEAT); SLICE NOTES — ноты маркеров нарезки по
/// хроматической клавиатуре или по гамме; PITCH (S12; ещё — SHIFT + тап по ручке Pitch); CLEAR SAMPLE LOCKS (S11b).
struct SamplerSettings: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        let st: AppSettings = m.settings
        return FormRows(rows: [
            .label("STRETCH"),
            .choices([MenuChoice(title: "NORMAL", current: !st.stretchBeat) { m.setStretchBeat(false) },
                      MenuChoice(title: "BEAT", current: st.stretchBeat) { m.setStretchBeat(true) }]),
            .note("Rate knob in Stretch mode keeps the pitch while the speed changes. NORMAL — for any material: tones stay clean, hits stay sharp. BEAT — lighter, for drum loops."),
            .label("SLICE NOTES"),
            .choices([MenuChoice(title: "CHROMATIC", current: st.sliceMap == .chromatic) { m.setSliceMap(.chromatic) },
                      MenuChoice(title: "SCALE", current: st.sliceMap == .scale) { m.setSliceMap(.scale) }]),
            .note("Markers in the sample editor play their slice from a piano key. CHROMATIC: markers go up by semitone from C3 (C3, C#3, D3…). SCALE: markers follow the notes of the selected scale from its root note in octave 3; the marker notes change with the scale."),
            .label("PITCH"),
            .choices([MenuChoice(title: "SMOOTH", current: !st.pitchSemitones) { m.updateSettings { $0.pitchSemitones = false } },
                      MenuChoice(title: "SEMITONES", current: st.pitchSemitones) { m.updateSettings { $0.pitchSemitones = true } }]),
            .note("How the sample Pitch knob and its step locks turn: SMOOTH — any value, SEMITONES — whole semitones. Hold SHIFT while turning for the other mode. LFO and ENV stay smooth."),
            .toggle("CLEAR SAMPLE LOCKS", st.clearSampleLocks) { m.setClearSampleLocks($0) },
            .note("ON: loading sounds from the library onto a track removes its sample locks — those steps play the track sound at their own note. Preset locks stay. OFF: sample locks keep their samples."),
        ])
    }
}

/// SIDECHAIN: приглушаются ли посылы Reverb, Delay, Drive тем же Sidechain, что и выход дорожки. MUTE TAILS убран
/// (решение пользователя): хвосты эффектов заглушённой дорожки всегда доигрывают.
struct SidechainSettings: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        return FormRows(rows: [
            .label("DUCK SENDS"),
            .toggle("REVERB", m.scSend(0)) { m.setScSend(0, $0) },
            .toggle("DELAY", m.scSend(1)) { m.setScSend(1, $0) },
            .toggle("DRIVE", m.scSend(2)) { m.setScSend(2, $0) },
            .note("ON: the send level of the effect is ducked by Duck too. Effect tails keep playing. OFF: the send is not ducked."),
        ])
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

/// APPEARANCE: тема SYSTEM (как на iPad), LIGHT, DARK; MASTER FX DISPLAY SCALE — масштаб дисплеев окон модулей
/// мастера (48, 32, 16 dB);
/// FX ANIMATION — картинки FX в окне сэмпла.
struct AppearanceSettings: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        let themes: [MenuChoice] = Appearance.allCases.map { (a: Appearance) -> MenuChoice in
            MenuChoice(title: a.rawValue, current: m.appearance == a) { m.setAppearance(a) }
        }
        let scales: [MenuChoice] = AppSettings.displayScales.map { (d: Int) -> MenuChoice in
            MenuChoice(title: "\(d) dB", current: m.settings.displayScale == d) { m.updateSettings { $0.displayScale = d } }
        }
        return FormRows(rows: [
            .label("THEME"),
            .choices(themes),
            .note("SYSTEM follows the iPad setting."),
            .label("MASTER FX DISPLAY SCALE"),
            .choices(scales),
            .note("Zoom of the level displays in the master effect windows (COMP, CLIP, LIM): from 0 dBFS down to −48, −32 or −16 dB."),
            .toggle("FX ANIMATION", m.settings.fxPictures) { m.setFxPictures($0) },
            .note("While an FX knob is turned, the sample window shows a picture of the effect."),
        ])
    }
}

/// MIX: переходы между проектами (действуют с переходами MIX, S10).
struct MixSettings: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        return FormRows(rows: [
            .toggle("CHANGE KEY", m.settings.mixKey) { m.setMixKey($0) },
            .note("ON: on a MIX transition the scale and root note change to the new project. OFF: the scale and root note stay as they are."),
            .toggle("CROSSFADER", m.settings.mixCrossfader) { m.setMixCrossfader($0) },
            .note("ON: the crossfader between projects sets the tempo (only the tempo). OFF: no crossfader; the tempo follows the old pattern."),
        ])
    }
}

/// MORPH: ручки на все дорожки или на выбранную; возврат после выключения режима.
struct MorphSettings: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        let ret: [MenuChoice] = (0..<MorphReturn.names.count).map { (k: Int) -> MenuChoice in
            MenuChoice(title: MorphReturn.names[k], current: m.settings.morphReturn == k) { m.setMorphReturn(k) }
        }
        return FormRows(rows: [
            .toggle("ALL TRACKS", m.settings.morphAll) { m.setMorphAll($0) },
            .note("ON: in MORPH a knob changes its parameter on every track that has it (each track moves by the same amount from its own value). OFF: only the selected track."),
            .label("RETURN"),
            .choices(ret),
            .note("How fast the knobs glide back when MORPH is turned off: OFF — at once, or over 1/4 bar to 2 bars at the current tempo."),
        ])
    }
}

/// LEVEL: регулятор громкости справа у дорожки — ABSOLUTE или RELATIVE.
struct LevelSettings: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        let rel: Bool = m.settings.levelRelative
        return FormRows(rows: [
            .label("TRACK LEVEL FADER"),
            .choices([MenuChoice(title: "ABSOLUTE", current: !rel) { m.setLevelRelative(false) },
                      MenuChoice(title: "RELATIVE", current: rel) { m.setLevelRelative(true) }]),
            .note("ABSOLUTE: the fader on the right is the track volume in MIX. RELATIVE: the fader trims the track down from its MIX volume — it cannot go above the MIX volume (for example −10 dB), down to silence; when the MIX volume changes, the trimmed level moves with it. The trim is kept with the track and only works in RELATIVE."),
        ])
    }
}

/// DEFAULTS: свои значения ручек, модулей мастера и EQ по умолчанию (KnobDefaults) — как запомнить и сбросить; забыть все.
struct DefaultsSettings: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        let n: Int = m.knobDefaultsCount
        return FormRows(rows: [
            .label("KNOB DEFAULTS"),
            .note("SHIFT + hold a knob: its value becomes the default (the knob shows SAVED). Double tap a knob: back to its default; double tap again: back to the factory value. Your defaults are used by NEW projects and ADD TRACK; saved projects stay as they are. Sound knobs keep their own defaults for the sampler and for each synth engine."),
            .note("SAVE DEFAULT in PRESETS of SAT, COMP, CLIP and LIM: all settings of the module become its default. SAVE DEFAULT in master EQ PRESETS: the bands become the master EQ of new projects."),
            .note(n == 0 ? "No saved defaults." : "Saved defaults: \(n)."),
            .choices([MenuChoice(title: "FORGET ALL", enabled: n > 0, red: true, current: false) { m.clearKnobDefaults() }]),
        ])
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

/// Шапка вложенного меню: стрелка назад и название — один стиль во всех меню (CLAUDE.md, «Шрифты в меню»):
/// 15 pt, жирный, заглавные, без разрядки; имя (проекта, дорожки) — как введено (caps: false).
struct MenuBackHeader: View {
    let title: String
    var caps: Bool = true
    let back: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Button(action: back) {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.text).frame(width: 40, height: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(caps ? title.uppercased() : title).font(.system(size: 15, weight: .bold))
                .lineLimit(1).foregroundStyle(theme.text)
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
