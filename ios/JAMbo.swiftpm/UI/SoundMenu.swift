import SwiftUI

/// Меню звука дорожки (тап по окну сэмпла, как в вебе): закрывает всю левую колонку — от верха окна сэмпла до низа
/// кнопок LFO; кнопки движков — высотой с LOAD (40), под кнопками — пустое место.
/// Две колонки движков: DRUMS (KICK, SNARE, HAT, CLAP, PERC) и SYNTH (ANALOG, FM, WTABLE; под ними SAMPLER): тап —
/// движок дорожки, с зажатыми шагами — их звук; группа LOAD SAMPLE · PRESET · MIDI:
/// LOAD (браузер библиотеки, S11b), MIDI (выход — S12; для зажатых шагов на этом месте TRACK — вернуть звук дорожки),
/// SAVE (пресет синта в библиотеку) и TABLE (у дорожки с WTABLE — браузер в LOAD TABLE).
struct SoundMenu: View {
    let model: AppModel
    let state: SoundMenuState
    @Environment(\.theme) private var theme


    var body: some View {
        let steps: Bool = !state.steps.isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            if steps {
                title("STEP " + state.steps.map { String($0 + 1) }.joined(separator: ", "))
            }
            HStack(alignment: .top, spacing: 4) {
                column("DRUMS", SynthEngines.drums, sampler: false, steps: steps)
                column("SYNTH", SynthEngines.synths, sampler: true, steps: steps)
            }
            title("LOAD SAMPLE · PRESET · MIDI")
            loadGroup(steps)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
        .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }

    private func title(_ s: String) -> some View {
        Text(s).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(theme.dim)
            .lineLimit(1).minimumScaleFactor(0.7)
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
                MenuItem(title: steps ? "TRACK" : "MIDI", enabled: steps) {
                    let s = state.steps
                    close()
                    model.stepSoundToTrack(s)
                }
            }
            HStack(spacing: 4) {
                MenuItem(title: "SAVE", enabled: !steps && synth) { model.openBrowser(.savePreset) }
                MenuItem(title: "TABLE", enabled: !steps && wtable) { model.openBrowser(.loadTable) }
            }
        }
    }

    /// Дорожка играет синт (SAVE — пресет в библиотеку).
    private var synth: Bool {
        SynthKey.engine(model.track.sample) != nil
    }

    /// Дорожка играет WTABLE (кнопка TABLE активна).
    private var wtable: Bool {
        SynthKey.engine(model.track.sample) == Jambo.wtable
    }

    private func close() {
        model.soundMenu = nil
    }
}
