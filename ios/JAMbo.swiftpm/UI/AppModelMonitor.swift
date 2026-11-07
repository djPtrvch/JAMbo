import Foundation

/// Headphone Monitor (ТЗ, фаза 1): настройки монитор-цепочки (UserDefaults «monitor»), Trim профиля коррекции
/// («phonesTrims», по имени профиля), пресеты Translation (Resources/TranslationPresets.json), маршруты референса и
/// подгонка его громкости к миксу. Bypass — BYPASS окна коррекции (phonesEq.on).
extension AppModel {
    static let monitorKey = "monitor"
    static let phonesTrimsKey = "phonesTrims"

    static func loadMonitor() -> MonitorSettings {
        return MonitorSettings(plist: UserDefaults.standard.dictionary(forKey: AppModel.monitorKey))
    }

    /// Пресеты Translation из ресурсов (в корне пакета или в папке Resources); нет файла — только Off (без фильтров).
    static func loadTranslations() -> [TranslationPreset] {
        let b: Bundle = Bundle.main
        let url: URL? = b.url(forResource: "TranslationPresets", withExtension: "json")
            ?? b.url(forResource: "TranslationPresets", withExtension: "json", subdirectory: "Resources")
        let list: [TranslationPreset] = TranslationPreset.list(url.flatMap { try? Data(contentsOf: $0) })
        return list.isEmpty ? [TranslationPreset(name: "Off", mono: nil, filters: [])] : list
    }

    static func loadTrims() -> [String: [Double]] {
        return UserDefaults.standard.dictionary(forKey: AppModel.phonesTrimsKey) as? [String: [Double]] ?? [:]
    }

    /// Trim текущего профиля (5 полос, dB).
    var phonesTrim: [Double] {
        let t: [Double] = phonesTrims[phonesName] ?? []
        return (0..<MonitorSpec.trimHz.count).map { $0 < t.count ? t[$0] : 0 }
    }

    func setPhonesTrim(_ k: Int, _ db: Double) {
        guard k >= 0 && k < MonitorSpec.trimHz.count else { return }
        var t: [Double] = phonesTrim
        t[k] = (Swift.max(-MonitorSpec.trimMax, Swift.min(MonitorSpec.trimMax, db)) * 10).rounded() / 10
        phonesTrims[phonesName] = t
        UserDefaults.standard.set(phonesTrims, forKey: AppModel.phonesTrimsKey)
        publishMonitor()
    }

    /// Пресет Translation: выбранный, иначе первый (Studio — по умолчанию).
    var translationPreset: TranslationPreset? {
        let p: TranslationPreset? = translations.first { $0.name == monitor.translation } ?? translations.first
        return (p?.filters.isEmpty ?? true) ? nil : p
    }

    /// Параметры цепочки по текущим настройкам.
    func monitorDesign() -> [Double] {
        return MonitorDesign.make(eq: phonesEq, settings: monitor, trim: phonesTrim, preset: translationPreset,
                                  sampleRate: AudioCore.sampleRate)
    }

    /// Level compensation, dB (показ в окне коррекции).
    var monitorComp: Double {
        let p: [Double] = monitorDesign()
        return 20 * log10(p[MonitorSpec.compAt])
    }

    /// Цепочка и маршруты референса — звуку.
    func publishMonitor() {
        let core: AudioCore = audio.core
        core.monitor.publish(monitorDesign())
        core.ref.throughMaster.store(monitor.refMaster ? 1 : 0)
        core.ref.throughMonitor.store(monitor.refMonitor ? 1 : 0)
    }

    func setMonitor(_ change: (inout MonitorSettings) -> Void) {
        var m: MonitorSettings = monitor
        change(&m)
        monitor = m
        UserDefaults.standard.set(m.plist, forKey: AppModel.monitorKey)
        publishMonitor()
    }

    /// TRANSLATION: следующий (step 1) или предыдущий пресет по кругу.
    func stepTranslation(_ step: Int) {
        let names: [String] = translations.map { $0.name }
        if names.isEmpty { return }
        let i: Int = names.firstIndex(of: monitor.translation) ?? 0
        let j: Int = ((i + step) % names.count + names.count) % names.count
        setMonitor { $0.translation = names[j] }
    }

    /// Референс идёт мимо монитор-цепочки (значок RAW на A/B).
    var refRaw: Bool { return !monitor.refMonitor }

    /// Подгонка громкости референса (кадр метров): пока слышен микс (A), короткая громкость микса против интегральной
    /// громкости файла; в B — последняя (не плывёт); плюс ручная подстройка ±12 dB.
    func tickRefMatch() {
        let core: AudioCore = audio.core
        if !refBActive, let ref = refLufs, ref.lufs.isFinite, ref.key == project.arrange.ref?.key {
            let st: Double = Double(core.levels.mixLoudness.shortTerm.load())
            if st.isFinite { refMatchDb = Swift.max(-24, Swift.min(24, st - ref.lufs)) }
        }
        let db: Double = (monitor.refMatch ? refMatchDb : 0) + monitor.refTrim
        let g: Float = db == 0 ? 1 : Float(pow(10, db / 20))
        if core.ref.matchGain.load() != g { core.ref.matchGain.store(g) }
    }

    /// Интегральная громкость файла референса — в фоне, один раз на файл.
    func ensureRefLufs(_ key: String, _ s: SampleData) {
        if refLufs?.key == key || refLufsPending == key { return }
        refLufsPending = key
        Task.detached(priority: .utility) {
            let r: UnsafeMutablePointer<Float> = s.channels > 1 ? s.right : s.left
            let l: Double = Loudness.integrated(left: UnsafePointer(s.left), right: UnsafePointer(r), frames: s.frames)
            await MainActor.run {
                self.refLufsPending = ""
                self.refLufs = (key, l)
            }
        }
    }
}
