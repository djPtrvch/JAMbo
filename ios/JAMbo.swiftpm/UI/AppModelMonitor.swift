import Foundation

/// Headphone Monitor (ТЗ, фаза 1): настройки монитор-цепочки (UserDefaults «monitor»), CORRECT CURVE профиля
/// («correctCurves», по имени профиля), пресеты Translation (Resources/TranslationPresets.json), маршруты референса и
/// подгонка его громкости к миксу. Bypass — BYPASS окна коррекции (phonesEq.on).
extension AppModel {
    static let monitorKey = "monitor"
    static let correctCurvesKey = "correctCurves"

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

    /// CORRECT CURVE каждого профиля: имя профиля → полосы (JSON [EqBand]; Codable Eq обрезает до 10 полос).
    static func loadCorrectCurves() -> [String: Data] {
        return UserDefaults.standard.dictionary(forKey: AppModel.correctCurvesKey) as? [String: Data] ?? [:]
    }

    /// CORRECT CURVE текущего профиля (полос сколько угодно).
    var correctEq: Eq {
        var e = Eq()
        guard let d = correctCurves[phonesName], let b = try? JSONDecoder().decode([EqBand?].self, from: d) else { return e }
        e.bands = b + [EqBand?](repeating: nil, count: Swift.max(0, EqSpec.bands - b.count))
        return e
    }

    func setCorrectEq(_ e: Eq) {
        var b: [EqBand?] = e.bands
        while let last = b.last, last == nil, b.count > EqSpec.bands { b.removeLast() }
        correctCurves[phonesName] = try? JSONEncoder().encode(b)
        UserDefaults.standard.set(correctCurves, forKey: AppModel.correctCurvesKey)
        publishMonitor()
    }

    /// PHONE CURVE / CORRECT CURVE: какую кривую править (выбор точки сбрасывается).
    func setEditCorrect(_ on: Bool) {
        if monitor.editCorrect == on { return }
        eqBand = -1
        stopEqListen()
        setMonitor { $0.editCorrect = on }
    }

    /// Пресет Translation: выбранный, иначе первый (Studio — по умолчанию).
    var translationPreset: TranslationPreset? {
        let p: TranslationPreset? = translations.first { $0.name == monitor.translation } ?? translations.first
        return (p?.filters.isEmpty ?? true) ? nil : p
    }

    /// Параметры цепочки по текущим настройкам (с комнатой — когда её отклик готов).
    func monitorDesign() -> [Double] {
        let resp: RoomResponse? = roomOn ? roomLoaded?.resp : nil
        return MonitorDesign.make(eq: phonesEq, settings: monitor, correct: correctEq, preset: translationPreset,
                                  room: resp, ambience: MonitorSpec.ambience(monitor.ambienceDb),
                                  sampleRate: AudioCore.sampleRate)
    }

    // MARK: — Room (фаза 2)

    /// Комнаты из ресурсов (rooms.json и WAV); нет файлов — пусто (в меню только Off).
    static func loadRooms() -> [RoomInfo] {
        return RoomInfo.list(AppModel.resource("rooms", "json"))
    }

    static func resource(_ name: String, _ ext: String) -> Data? {
        let b: Bundle = Bundle.main
        let url: URL? = b.url(forResource: name, withExtension: ext)
            ?? b.url(forResource: name, withExtension: ext, subdirectory: "Resources")
        return url.flatMap { try? Data(contentsOf: $0) }
    }

    /// Комната включена (выбрана и есть в списке).
    var roomOn: Bool { return monitor.room != "Off" && rooms.contains { $0.name == monitor.room } }

    /// Выбрать комнату (Off — обход): импульсы и отклик — в фоне, затем в звук (переход 40 мс).
    func setRoom(_ name: String) {
        setMonitor { $0.room = name }
        syncRoom()
    }

    /// Свёртка выбранной комнаты — звуку (при запуске и при выборе).
    func syncRoom() {
        let stage: RoomStage = audio.core.monitor.room
        guard roomOn, let info = rooms.first(where: { $0.name == monitor.room }) else {
            stage.set(nil)
            roomLoaded = nil
            publishMonitor()
            return
        }
        if roomLoaded?.name == info.name { return }
        Task.detached(priority: .userInitiated) {
            guard let d = AppModel.resource((info.file as NSString).deletingPathExtension, "wav"),
                  let ir = RoomIR(name: info.name, wav: d, gainDb: info.gainDb, direct: info.direct) else { return }
            let conv = RoomConv(ir: ir)
            let resp: RoomResponse = ir.response(sampleRate: AudioCore.sampleRate)
            await MainActor.run {
                guard self.monitor.room == info.name else { return }
                self.roomLoaded = (info.name, resp)
                stage.set(conv)
                self.publishMonitor()
            }
        }
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
        core.monitor.room.ambience.store(Float(MonitorSpec.ambience(monitor.ambienceDb)))
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
