import SwiftUI

/// Меню звука дорожки (тап по окну сэмпла, как в вебе): закрывает всю левую колонку — от верха окна сэмпла до низа
/// кнопок LFO; кнопки движков — высотой с LOAD (40) сверху, группа LOAD · SAVE — внизу, между ними пустое место.
/// Две колонки движков: DRUMS (KICK, SNARE, HAT, CLAP, PERC; под ними SAMPLER) и SYNTH (ANALOG, SUB, FM, WTABLE,
/// TEXTURE, GRANULAR): тап —
/// движок дорожки, с зажатыми шагами — их звук; группа LOAD SAMPLE · PRESET · MIDI:
/// LOAD (браузер библиотеки, S11b), MIDI (вход и выход нот дорожки — TrackMidiPage на месте меню; для зажатых шагов
/// на этом месте TRACK — вернуть звук дорожки),
/// SAVE (пресет синта в библиотеку) и TABLE (у дорожки с WTABLE — браузер в LOAD TABLE; у GRANULAR на его месте
/// SOURCE — браузер сэмплов, тап ставит сэмпл GRANULAR). STRETCH — алгоритм таймстретча RATE в режиме Stretch у сэмплера:
/// NORMAL (фазовый вокодер, по умолчанию) или BEAT (для ударных лупов).
struct SoundMenu: View {
    let model: AppModel
    let state: SoundMenuState
    @State private var midiPage: Bool = false
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if midiPage {
                TrackMidiPage(model: model) { midiPage = false }
            } else {
                engines
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
        .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }

    private var engines: some View {
        let steps: Bool = !state.steps.isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            if steps {
                Text("STEP " + state.steps.map { String($0 + 1) }.joined(separator: ", "))
                    .font(.system(size: 10, weight: .bold)).tracking(0.4).foregroundStyle(theme.dim)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
            HStack(alignment: .top, spacing: 4) {
                column("DRUMS", SynthEngines.drums, sampler: true, steps: steps)
                column("SYNTH", SynthEngines.synths, sampler: false, steps: steps)
            }
            Spacer(minLength: 0)
            title("STRETCH")
            stretchRow(steps)
            title("LOAD SAMPLE · PRESET · MIDI")
            loadGroup(steps)
        }
    }

    /// Заголовки одного размера: длинный LOAD SAMPLE · PRESET · MIDI помещается без ужатия (иначе он мельче DRUMS
    /// и SYNTH).
    private func title(_ s: String) -> some View {
        Text(s).font(.system(size: 10, weight: .bold)).tracking(0.4).foregroundStyle(theme.dim)
            .lineLimit(1)
            .fixedSize()
            .frame(maxWidth: .infinity)
    }

    /// ids — номера движков колонки (имена — из таблицы движков).
    private func column(_ name: String, _ ids: [Int], sampler: Bool, steps: Bool) -> some View {
        let engine: Int = SynthKey.engine(model.track.sample) ?? -1
        return VStack(spacing: 4) {
            title(name)
            ForEach(ids, id: \.self) { id in
                let label: String = SynthEngines.engine(id)?.name ?? "?"
                cell(label, enabled: true, current: !steps && engine == id) {
                    let s = state.steps
                    close()
                    model.pickSynth(id, steps: s)
                }
            }
            if sampler {
                cell("SAMPLER", enabled: !steps, current: !steps && model.track.sample.isEmpty) {
                    close()
                    model.cleanSampler()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func cell(_ label: String, enabled: Bool, current: Bool = false, _ action: @escaping () -> Void) -> some View {
        let fg: Color = !enabled ? theme.off : (current ? theme.onAccent : theme.text)
        return Button(action: action) {
            Text(label).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(current ? theme.accent : theme.panel, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func loadGroup(_ steps: Bool) -> some View {
        let hasSample: Bool = !model.track.sample.isEmpty && SynthKey.engine(model.track.sample) == nil
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                MenuItem(title: "LOAD", current: !steps && hasSample) {
                    let s = state.steps
                    model.openBrowser(.load(steps: s))
                }
                MenuItem(title: steps ? "TRACK" : "MIDI", current: !steps && model.track.midi.sends) {
                    if !steps {
                        midiPage = true
                        return
                    }
                    let s = state.steps
                    close()
                    model.stepSoundToTrack(s)
                }
            }
            HStack(spacing: 4) {
                MenuItem(title: "SAVE", enabled: !steps && synth) { model.openBrowser(.savePreset) }
                // У GRANULAR на месте TABLE — SOURCE (сэмпл, из которого читаются зёрна).
                if granular {
                    MenuItem(title: "SOURCE", enabled: !steps) { model.openBrowser(.source) }
                } else {
                    MenuItem(title: "TABLE", enabled: !steps && wtable) { model.openBrowser(.loadTable) }
                }
            }
        }
    }

    private func stretchRow(_ steps: Bool) -> some View {
        let on: Bool = !steps && !synth
        let beat: Bool = model.stretchBeat
        return HStack(spacing: 4) {
            MenuItem(title: "NORMAL", enabled: on, current: on && !beat) { model.setStretchBeat(false) }
            MenuItem(title: "BEAT", enabled: on, current: on && beat) { model.setStretchBeat(true) }
        }
    }

    /// Дорожка играет синт (SAVE — пресет в библиотеку).
    private var synth: Bool {
        SynthKey.engine(model.track.sample) != nil
    }

    /// Дорожка играет GRANULAR (на месте TABLE — SOURCE).
    private var granular: Bool {
        SynthKey.engine(model.track.sample) == Jambo.granular
    }

    /// Дорожка играет WTABLE (кнопка TABLE активна).
    private var wtable: Bool {
        SynthKey.engine(model.track.sample) == Jambo.wtable
    }

    private func close() {
        model.soundMenu = nil
    }
}
