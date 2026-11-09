import AVFoundation
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

    /// Выбрать пункт TRANSLATION: тембр — сразу, пространство (комната пункта) — в фоне. Есть профиль пункта —
    /// AMBIENCE, EAR TONE, CORRECTION и CORRECT CURVE из него; нет — остаются текущие.
    func setTranslation(_ name: String) {
        let p: MonitorProfile? = monitor.spaces[name]
        setMonitor { m in
            m.translation = name
            if let q = p {
                m.ambienceDb = q.ambienceDb
                m.raw = q.raw
                m.strength = q.strength
            }
        }
        if let q = p {
            correctCurves[phonesName] = q.correct
            UserDefaults.standard.set(correctCurves, forKey: AppModel.correctCurvesKey)
            publishMonitor()
        }
        syncRoom()
    }

    /// Удержание пункта в меню SPACE: текущие AMBIENCE, EAR TONE, CORRECTION и CORRECT CURVE — его профиль (пункт
    /// становится выбранным); на секунду SAVED.
    func saveSpace(_ name: String) {
        let prof = MonitorProfile(ambienceDb: monitor.ambienceDb, raw: monitor.raw, strength: monitor.strength,
                                  correct: correctCurves[phonesName])
        setMonitor { m in
            m.spaces[name] = prof
            m.translation = name
        }
        syncRoom()
        spaceSaved = name
        Later.run(1.0) {
            if self.spaceSaved == name { self.spaceSaved = nil }
        }
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
        return resourceURL(name, ext).flatMap { try? Data(contentsOf: $0) }
    }

    static func resourceURL(_ name: String, _ ext: String) -> URL? {
        let b: Bundle = Bundle.main
        return b.url(forResource: name, withExtension: ext)
            ?? b.url(forResource: name, withExtension: ext, subdirectory: "Resources")
    }

    /// Пространство пункта TRANSLATION (комната из rooms.json); нет — nil.
    var roomInfo: RoomInfo? {
        guard let r = translationPreset?.room else { return nil }
        return rooms.first { $0.name == r }
    }

    /// У пункта есть пространство.
    var roomOn: Bool { return roomInfo != nil }

    /// Свёртка комнаты пункта — звуку (при запуске, выборе пункта, EAR TONE, UNDO): импульсы — один раз на комнату, смесь
    /// по EAR TONE, свёртка и отклик — в фоне, затем в звук (переход 40 мс). Пока идёт сборка, новая не начинается — по её
    /// окончании синхронизация повторяется (EAR TONE при движении пальца не копит очередь).
    func syncRoom() {
        syncHead()
        let stage: RoomStage = audio.core.monitor.room
        guard let info = roomInfo else {
            stage.set(nil)
            roomLoaded = nil
            publishMonitor()
            return
        }
        let raw: Double = (monitor.raw * 100).rounded() / 100
        let key: String = info.name + "@" + String(raw)
        if roomLoaded?.name == key || roomBuilding { return }
        roomBuilding = true
        let cached: RoomSet? = roomSet?.name == info.name ? roomSet : nil
        DispatchQueue.global(qos: .userInitiated).async {
            var failed: [String] = []
            let set: RoomSet? = cached ?? RoomSet.load(info, failed: &failed)
            let bad: [String] = failed
            var conv: RoomConv? = nil
            var resp: RoomResponse? = nil
            if let s = set {
                let ir: RoomIR = s.ir.mixed(flat: s.flat, raw: raw)
                let head: RoomIR? = s.head?.mixed(flat: s.flatHead, raw: raw)
                conv = RoomConv(ir: ir, head: head, from: info.headFrom, step: info.headStep)
                conv?.setHighpass(hz: info.hpHz, order: info.hpOrder, sampleRate: AudioCore.sampleRate)
                resp = ir.response(sampleRate: AudioCore.sampleRate)
                resp?.highpass(hz: info.hpHz, order: info.hpOrder)
            }
            DispatchQueue.main.async {
                self.roomBuilding = false
                // Файл комнаты не прочитался — сообщение (общее окно ошибок, как у записи), а не тихо без комнаты.
                if !bad.isEmpty { self.sampleRec.error = "Room files could not be read: " + bad.joined(separator: ", ") }
                guard let s = set, let c = conv, let r = resp else { return }
                self.roomSet = s
                if self.roomInfo?.name == info.name {
                    self.roomLoaded = (key, r)
                    stage.set(c)
                    self.publishMonitor()
                }
                self.syncRoom()
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

    // MARK: — поля монитора по ключу: 0 TRANSLATION, 1 CORRECTION, 5 AMBIENCE, 6 EAR TONE

    func monitorField(_ k: Int) -> MonitorFieldInfo {
        let s: MonitorSettings = monitor
        switch k {
        case 0: return MonitorFieldInfo(label: "SPACE", value: translationPreset?.name ?? "Off", enabled: true, px: 30)
        case 1: return MonitorFieldInfo(label: "CORRECTION", value: String(format: "%.0f %%", s.strength * 100), enabled: true, px: 2)
        case 6: return MonitorFieldInfo(label: "EAR TONE", value: String(format: "%.0f %%", s.raw * 100), enabled: roomOn, px: 2)
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
        case 6: return (s.raw * 100).rounded()
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
        case 6:
            setMonitor { $0.raw = Swift.max(0, Swift.min(100, v)) / 100 }
            syncRoom()
        default: setMonitor { $0.ambienceDb = Swift.max(MonitorSpec.ambienceMin, Swift.min(0, v / 2)) }
        }
    }

    /// Двойной тап — по умолчанию (у TRANSLATION — ничего).
    func resetMonitorField(_ k: Int) {
        switch k {
        case 1: setMonitor { $0.strength = 1 }
        case 5: setMonitor { $0.ambienceDb = -6 }
        case 6:
            setMonitor { $0.raw = 1 }
            syncRoom()
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


/// Импульсы комнаты для EAR TONE и HEAD TRACK: с окраской уха (ir, head) и выровненные (flat, flatHead; нет — nil).
final class RoomSet: @unchecked Sendable {
    let name: String
    let ir: RoomIR
    let flat: RoomIR?
    let head: RoomIR?
    let flatHead: RoomIR?

    init(name: String, ir: RoomIR, flat: RoomIR?, head: RoomIR?, flatHead: RoomIR?) {
        self.name = name
        self.ir = ir
        self.flat = flat
        self.head = head
        self.flatHead = flatHead
    }

    /// Из ресурсов (файлы rooms.json); нет импульсов комнаты — nil.
    /// failed — файлы из rooms.json, которые не прочитались (пустое имя файла — набора нет, это не ошибка).
    static func load(_ i: RoomInfo, failed: inout [String]) -> RoomSet? {
        let ir: RoomIR? = RoomSet.audio(i.name, i.file, i.gainDb, i.direct, &failed)
        let flat: RoomIR? = RoomSet.audio(i.name, i.flatFile, i.flatGainDb, i.direct, &failed)
        let head: RoomIR? = RoomSet.audio(i.name, i.headFile, i.headGainDb, 0, &failed)
        let flatHead: RoomIR? = RoomSet.audio(i.name, i.flatHeadFile, i.flatHeadGainDb, 0, &failed)
        guard let main = ir else { return nil }
        return RoomSet(name: i.name, ir: main, flat: flat, head: head, flatHead: flatHead)
    }

    /// Импульс из ресурсов (9.11: ALAC в CAF, без потерь) через AVAudioFile: 4 канала, 48 кГц, float по каналам —
    /// те же значения, что из WAV; не прочитался — nil и имя в failed.
    private static func audio(_ name: String, _ file: String, _ gain: Double, _ direct: Int,
                              _ failed: inout [String]) -> RoomIR? {
        if file.isEmpty { return nil }
        let ns: NSString = file as NSString
        var ir: RoomIR? = nil
        if let url = AppModel.resourceURL(ns.deletingPathExtension, ns.pathExtension),
           let f = try? AVAudioFile(forReading: url),
           let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)),
           (try? f.read(into: buf)) != nil, let ch = buf.floatChannelData {
            let n: Int = Int(buf.frameLength)
            let c: Int = Int(buf.format.channelCount)
            var planar = [Float](repeating: 0, count: n * c)
            for k in 0..<c {
                for i in 0..<n { planar[k * n + i] = ch[k][i] }
            }
            ir = RoomIR(name: name, planar: planar, channels: c, rate: Int(buf.format.sampleRate), gainDb: gain,
                        direct: direct)
        }
        if ir == nil { failed.append(file) }
        return ir
    }
}
