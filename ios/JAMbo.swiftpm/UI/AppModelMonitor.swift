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

    /// CORRECT CURVE текущего профиля (10 полос, как у PHONE CURVE).
    var correctEq: Eq {
        var e = Eq()
        guard let d = correctCurves[phonesName], let b = try? JSONDecoder().decode([EqBand?].self, from: d) else { return e }
        let top: [EqBand?] = Array(b.prefix(EqSpec.bands))
        e.bands = top + [EqBand?](repeating: nil, count: EqSpec.bands - top.count)
        return e
    }

    func setCorrectEq(_ e: Eq) {
        monitorRecord()
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
        setMonitor(record: false) { $0.editCorrect = on }
    }

    /// Пункт TRANSLATION: выбранный, иначе первый; Off (ни тембра, ни пространства) — nil.
    var translationPreset: TranslationPreset? {
        let p: TranslationPreset? = translations.first { $0.name == monitor.translation } ?? translations.first
        guard let q = p, !q.filters.isEmpty || q.room != nil || (q.mono ?? false) else { return nil }
        return q
    }

    /// Цепочка прослушивания меняет звук (значок наушников над CPU, 8.11): коррекция не в BYPASS и есть что-то из
    /// PHONE CURVE (при CORRECTION > 0), CORRECT CURVE, SPACE (не Off), MONO, SUB. BYPASS выключает всё сразу.
    var monitorAudible: Bool {
        if !phonesEq.on { return false }
        let curve: Bool = monitor.strength > 0 && phonesEq.bands.contains { $0?.on ?? false }
        let correct: Bool = correctEq.bands.contains { $0?.on ?? false }
        return curve || correct || translationPreset != nil || monitor.mono || monitor.sub
    }

    /// Выбрать пункт TRANSLATION: тембр — сразу, пространство (комната пункта) — в фоне.
    func setTranslation(_ name: String) {
        setMonitor { $0.translation = name }
        syncRoom()
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

    /// Пространство пункта TRANSLATION (комната из rooms.json); нет — nil.
    var roomInfo: RoomInfo? {
        guard let r = translationPreset?.room else { return nil }
        return rooms.first { $0.name == r }
    }

    /// У пункта есть пространство.
    var roomOn: Bool { return roomInfo != nil }

    /// Свёртка комнаты пункта — звуку (при запуске, выборе пункта, UNDO): импульсы и отклик — в фоне, затем в звук
    /// (переход 40 мс).
    func syncRoom() {
        syncHead()
        let stage: RoomStage = audio.core.monitor.room
        guard let info = roomInfo else {
            stage.set(nil)
            roomLoaded = nil
            publishMonitor()
            return
        }
        if roomLoaded?.name == info.name { return }
        Task.detached(priority: .userInitiated) {
            guard let d = AppModel.resource((info.file as NSString).deletingPathExtension, "wav"),
                  let ir = RoomIR(name: info.name, wav: d, gainDb: info.gainDb, direct: info.direct) else { return }
            // HEAD: набор прямой части по углам поворота головы (нет файла — свёртка без HEAD).
            var head: RoomIR? = nil
            if !info.headFile.isEmpty, let hd = AppModel.resource((info.headFile as NSString).deletingPathExtension, "wav") {
                head = RoomIR(name: info.name, wav: hd, gainDb: info.headGainDb, direct: 0)
            }
            let conv = RoomConv(ir: ir, head: head, from: info.headFrom, step: info.headStep)
            let resp: RoomResponse = ir.response(sampleRate: AudioCore.sampleRate)
            await MainActor.run {
                guard self.roomInfo?.name == info.name else { return }
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

    /// record false — не правка (выбор кривой): без UNDO.
    func setMonitor(record: Bool = true, _ change: (inout MonitorSettings) -> Void) {
        if record { monitorRecord() }
        var m: MonitorSettings = monitor
        change(&m)
        monitor = m
        UserDefaults.standard.set(m.plist, forKey: AppModel.monitorKey)
        publishMonitor()
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

    // MARK: — поля монитора по ключу: 0 TRANSLATION, 1 CORRECTION, 5 AMBIENCE

    func monitorField(_ k: Int) -> MonitorFieldInfo {
        let s: MonitorSettings = monitor
        switch k {
        case 0: return MonitorFieldInfo(label: "SPACE", value: translationPreset?.name ?? "Off", enabled: true, px: 30)
        case 1: return MonitorFieldInfo(label: "CORRECTION", value: String(format: "%.0f %%", s.strength * 100), enabled: true, px: 2)
        default:
            let t: String = s.ambienceDb <= MonitorSpec.ambienceMin ? "−∞ dB" : String(format: "%.1f dB", s.ambienceDb)
            return MonitorFieldInfo(label: "AMBIENCE", value: t, enabled: roomOn, px: 2)
        }
    }

    /// Значение поля в пунктах движения пальца.
    func monitorUnits(_ k: Int) -> Double {
        let s: MonitorSettings = monitor
        switch k {
        case 0: return -Double(translations.firstIndex { $0.name == s.translation } ?? 0)
        case 1: return (s.strength * 100).rounded()
        default: return (s.ambienceDb * 2).rounded()
        }
    }

    func setMonitorUnits(_ k: Int, _ v: Double) {
        switch k {
        case 0:
            let names: [String] = translations.map { $0.name }
            let n: Int = names.count
            if n == 0 { return }
            let name: String = names[((-Int(v)) % n + n) % n]
            if name != monitor.translation { setTranslation(name) }
        case 1: setMonitor { $0.strength = Swift.max(0, Swift.min(100, v)) / 100 }
        default: setMonitor { $0.ambienceDb = Swift.max(MonitorSpec.ambienceMin, Swift.min(0, v / 2)) }
        }
    }

    /// Двойной тап — по умолчанию (у TRANSLATION — ничего).
    func resetMonitorField(_ k: Int) {
        switch k {
        case 1: setMonitor { $0.strength = 1 }
        case 5: setMonitor { $0.ambienceDb = -6 }
        default: break
        }
    }

    /// Тап: у TRANSLATION — меню под полем.
    func monitorFieldTap(_ k: Int, _ r: CGRect) {
        guard k == 0 else { return }
        translationMenu = translationMenu == nil ? r : nil
    }
}

/// Подпись, значение, доступность и шаг пальца поля монитора.
struct MonitorFieldInfo {
    let label: String
    let value: String
    let enabled: Bool
    let px: CGFloat
}

/// Снимок окна коррекции наушников для его UNDO: кривые, настройки монитора, имя профиля.
struct MonitorSnap {
    let phones: Eq
    let curves: [String: Data]
    let settings: [String: Any]
    let name: String
}

// UNDO / REDO окна коррекции (решение пользователя): своя история — коррекция не часть проекта; пока окно открыто,
// кнопки UNDO и REDO верхней панели работают с ней. Жест (палец на поле или точке) — одна запись.
extension AppModel {
    static let monitorUndoMax = 100

    var undoEnabled: Bool { return phonesShown ? !monitorUndo.isEmpty : canUndo }
    var redoEnabled: Bool { return phonesShown ? !monitorRedo.isEmpty : canRedo }

    func monitorSnap() -> MonitorSnap {
        return MonitorSnap(phones: phonesEq, curves: correctCurves, settings: monitor.plist, name: phonesName)
    }

    /// Запись перед правкой (в жесте — только первая).
    func monitorRecord() {
        if monitorGesture == 2 { return }
        if monitorGesture == 1 { monitorGesture = 2 }
        monitorUndo.append(monitorSnap())
        if monitorUndo.count > AppModel.monitorUndoMax { monitorUndo.removeFirst() }
        if !monitorRedo.isEmpty { monitorRedo.removeAll() }
    }

    func monitorUndoStep() {
        guard let s = monitorUndo.popLast() else { return }
        monitorRedo.append(monitorSnap())
        monitorRestore(s)
    }

    func monitorRedoStep() {
        guard let s = monitorRedo.popLast() else { return }
        monitorUndo.append(monitorSnap())
        monitorRestore(s)
    }

    private func monitorRestore(_ s: MonitorSnap) {
        let ud = UserDefaults.standard
        phonesEq = s.phones
        ud.set(try? JSONEncoder().encode(s.phones), forKey: AppModel.phonesEqKey)
        correctCurves = s.curves
        ud.set(s.curves, forKey: AppModel.correctCurvesKey)
        monitor = MonitorSettings(plist: s.settings)
        ud.set(monitor.plist, forKey: AppModel.monitorKey)
        phonesName = s.name
        ud.set(s.name, forKey: AppModel.phonesNameKey)
        eqBand = -1
        publishMonitor()
        syncRoom()
    }
}

