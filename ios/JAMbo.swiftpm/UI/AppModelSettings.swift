import Foundation

/// Вкладки SETTINGS (S9d; отличия от веба: без SAMPLE RATE и BUFFER SIZE, BACKGROUND и SCALE; APPEARANCE — вкладка;
/// новые MIX, MORPH, LEVEL — решение пользователя).
/// Порядок — решение пользователя: AUDIO ENGINE, OUTPUT, APPEARANCE — нижним рядом.
enum SettingsTab: String, CaseIterable {
    case record = "RECORD"
    case sampler = "SAMPLER"
    case sidechain = "DUCK"
    case mix = "MIX"
    case morph = "MORPH"
    case level = "LEVEL"
    case engine = "AUDIO ENGINE"
    case output = "OUTPUT"
    case appearance = "APPEARANCE"
    case defaults = "DEFAULTS"
    case arrange = "ARRANGE"
}

/// Настройки приложения (общие для проектов, UserDefaults): применяются сразу.
extension AppModel {
    func setMuteTails(_ on: Bool) {
        updateSettings { s in s.muteTails = on }
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
