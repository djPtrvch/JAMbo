import SwiftUI

/// Меню звука дорожки (тап по окну сэмпла, как в вебе): закрывает всю левую колонку, кнопки крупные.
/// Три колонки движков — SYNTH (свои: DRUM, ANALOG, FM; WTABLE — S3b #44; под ними SAMPLER), MI SYNTH (Plaits 0–7) и
/// MI DRUMS (Plaits 8–15): тап — движок дорожки, с зажатыми шагами — их звук; группа LOAD SAMPLE · PRESET · MIDI: LOAD (выбор файлов), MIDI (выход — S11;
/// для зажатых шагов на этом месте TRACK — вернуть звук дорожки), SAVE и TABLE (S3/S10).
struct SoundMenu: View {
    let model: AppModel
    let state: SoundMenuState
    @Environment(\.theme) private var theme

    static let synth = ["DRUM", "ANALOG", "FM", "WTABLE"]
    static let miSynth = ["VA", "WAVESHAPE", "FM", "GRAIN", "ADDITIVE", "WAVETABLE", "CHORDS", "SPEECH"]
    static let miDrums = ["SWARM", "NOISE", "PARTICLE", "STRING", "MODAL", "KICK", "SNARE", "HI-HAT"]

    var body: some View {
        let steps: Bool = !state.steps.isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            if steps {
                title("STEP " + state.steps.map { String($0 + 1) }.joined(separator: ", "))
            }
            HStack(alignment: .top, spacing: 4) {
                column("SYNTH", SoundMenu.synth, sampler: true, steps: steps, plaits: SynthEngines.firstJambo)
                column("MI SYNTH", SoundMenu.miSynth, sampler: false, steps: steps, plaits: 0)
                column("MI DRUMS", SoundMenu.miDrums, sampler: false, steps: steps, plaits: SynthEngines.firstDrum)
            }
            title("LOAD SAMPLE · PRESET · MIDI")
            loadGroup(steps)
        }
        .padding(6)
        .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
        .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }

    private func title(_ s: String) -> some View {
        Text(s).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(theme.dim)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
    }

    /// plaits — номер первого движка колонки; движка, которого ещё нет в таблице (WTABLE), — серая кнопка.
    private func column(_ name: String, _ items: [String], sampler: Bool, steps: Bool, plaits: Int? = nil) -> some View {
        let engine: Int = SynthKey.engine(model.track.sample) ?? -1
        return VStack(spacing: 4) {
            title(name)
            ForEach(items.indices, id: \.self) { k in
                if let first = plaits, first + k < SynthEngines.count {
                    cell(items[k], enabled: true, current: !steps && engine == first + k) {
                        let s = state.steps
                        close()
                        model.pickSynth(first + k, steps: s)
                    }
                } else {
                    cell(items[k], enabled: false) {}
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
            Text(label).font(.system(size: 10, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(current ? theme.accent : theme.panel, in: RoundedRectangle(cornerRadius: 6))
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
                    close()
                    model.chooseFiles(steps: s)
                }
                MenuItem(title: steps ? "TRACK" : "MIDI", enabled: steps) {
                    let s = state.steps
                    close()
                    model.stepSoundToTrack(s)
                }
            }
            HStack(spacing: 4) {
                MenuItem(title: "SAVE", enabled: false) {}
                MenuItem(title: "TABLE", enabled: false) {}
            }
        }
    }

    private func close() {
        model.soundMenu = nil
    }
}
