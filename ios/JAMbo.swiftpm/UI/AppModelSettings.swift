import Foundation

/// Вкладки SETTINGS (S9d; отличия от веба: без SAMPLE RATE и BUFFER SIZE, BACKGROUND и SCALE; APPEARANCE — вкладка;
/// новые MIX, MORPH, LEVEL — решение пользователя).
/// Порядок (3.11, решение пользователя) — по рядам из трёх: RECORD, SAMPLER, ARRANGE / MORPH, MIX, RANDOM /
/// LEVEL, DUCK, DEFAULTS / APPEARANCE, AUDIO ENGINE, OUTPUT.
enum SettingsTab: String, CaseIterable {
    case record = "RECORD"
    case sampler = "SAMPLER"
    case arrange = "ARRANGE"
    case morph = "MORPH"
    case mix = "MIX"
    case random = "RANDOM"
    case level = "LEVEL"
    case sidechain = "DUCK"
    case defaults = "DEFAULTS"
    case appearance = "APPEARANCE"
    case engine = "AUDIO ENGINE"
    case output = "OUTPUT"
}

/// Настройки приложения (общие для проектов, UserDefaults): применяются сразу.
extension AppModel {

    /// SAMPLER → STRETCH: таймстретч BEAT (WSOLA) или NORMAL (фазовый вокодер); новые ноты — новым алгоритмом.
    func setStretchBeat(_ on: Bool) {
        updateSettings { s in s.stretchBeat = on }
        publishAudio()
    }

    func setQuantize(_ on: Bool) {
        updateSettings { s in s.record.quantize = on }
    }

    func setOverdub(_ on: Bool) {
        updateSettings { s in s.record.overdub = on }
    }

    /// SIDECHAIN SENDS: k — 0 Reverb, 1 Delay, 2 Drive.
    func setScSend(_ k: Int, _ on: Bool) {
        updateSettings { s in
            if k == 0 { s.scSends.rev = on }
            if k == 1 { s.scSends.dly = on }
            if k == 2 { s.scSends.drv = on }
        }
        publishAudio()
    }

    func scSend(_ k: Int) -> Bool {
        let s: SidechainSends = settings.scSends
        return k == 0 ? s.rev : (k == 1 ? s.dly : s.drv)
    }

    func setLevelRelative(_ on: Bool) {
        updateSettings { s in s.levelRelative = on }
        publishAudio()
    }

    /// SETTINGS → RANDOM: k — 0 DRUMS, 1 CHORDS, 2 STYLE ALL TRACKS, 3 STEPS ALL TRACKS, 4 SAMPLES.
    func setRandom(_ k: Int, _ on: Bool) {
        updateSettings { s in
            switch k {
            case 0: s.randomDrums = on
            case 1: s.randomChords = on
            case 2: s.randomStyleAll = on
            case 4: s.randomSamples = on
            default: s.randomStepsAll = on
            }
        }
    }

    func setMorphAll(_ on: Bool) {
        updateSettings { s in s.morphAll = on }
    }

    func setMorphReturn(_ k: Int) {
        updateSettings { s in s.morphReturn = k }
    }

    func setBackgroundAudio(_ on: Bool) {
        updateSettings { s in s.backgroundAudio = on }
    }

    func setFxPictures(_ on: Bool) {
        updateSettings { s in s.fxPictures = on }
    }

    func setClearSampleLocks(_ on: Bool) {
        updateSettings { s in s.clearSampleLocks = on }
    }

    func setMixKey(_ on: Bool) {
        updateSettings { s in s.mixKey = on }
    }

    func setMixCrossfader(_ on: Bool) {
        updateSettings { s in s.mixCrossfader = on }
    }
}
