import SwiftUI

// Панда-пасхалка на месте полос уровня в окне MIX: SHIFT + тап по окну — панда, ещё раз — полосы. Не в проекте.
// Состояние — каждый кадр из модели (игра, REC, темп, звук на дорожке Voice), доли — по аудио-часам секвенсора
// (PlayClock — что слышно сейчас): смена BPM на ходу не сбивает раскачивание с долей.

extension AppModel {
    /// Состояние панды сейчас.
    func pandaState() -> PandaState {
        return PandaState(isPlaying: playing, isRecording: recOn, bpm: project.bpm, voiceActive: voiceSounds())
    }

    /// На дорожке Voice (по имени, без учёта регистра) слышен звук: уровень выше −50 dBFS, дорожка не заглушена.
    func voiceSounds() -> Bool {
        guard let t = project.tracks.firstIndex(where: { $0.name.lowercased() == "voice" }), project.audible(t) else {
            return false
        }
        let level: Float = meters.bars(t, stereo: false).first?.level ?? 0
        return MeterState.frac(level) > 0.17
    }

    /// Доли, которые слышны сейчас (аудио-часы секвенсора с поправкой на задержку выхода); nil — стоит.
    func heardBeat() -> Double? {
        let c = audio.core.sequencer.clock.read()
        guard c.playing, c.stepFrames > 0 else { return nil }
        let heard: Double = audio.hostNow() - audio.outputLatency
        let frame: Double = c.blockFrame + (heard - c.blockHost) * AudioCore.sampleRate
        let tick: Double = Double(c.nextTick) - (c.nextFrame - frame) / c.stepFrames
        return tick / TempoGrid.stepsPerBeat
    }
}

/// Окно панды: панда во всю ширину, под ней с небольшим отступом — JAMbo by PTRVCH (нежирным).
struct PandaWindow: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            DancingPanda(stateProvider: { model.pandaState() }, beatPhaseProvider: { model.heardBeat() },
                         accent: theme.accent, rec: theme.rec)
            Text("JAMbo by PTRVCH")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(theme.dim)
            Spacer(minLength: 0)
        }
        .padding(10)
        .allowsHitTesting(false)
    }
}
