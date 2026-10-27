import Foundation

/// Меню полосы EQ (долгое нажатие по точке, тап по TYPE): полоса, точка, у которой открыть, и поле EQ, в котором
/// меню помещается (координаты «root»).
struct EqMenuState: Equatable {
    let band: Int
    let anchor: CGPoint
    let bounds: CGRect
}

/// Меню PRESETS EQ: кнопка, под которой открыть, и низ поля EQ (координаты «root»).
struct EqPresetMenuState: Equatable {
    let anchor: CGRect
    let bottom: CGFloat
}

/// EQ на месте центра (кнопка EQ, как src/ui/eq.ts веба): канал — выбранная дорожка, при MIX и MST — мастер.
extension AppModel {
    /// Канал EQ: дорожка или EqSpec.masterChannel.
    var eqChannel: Int { return channel == .track ? selectedTrack : EqSpec.masterChannel }

    var eqTarget: Eq { return phonesShown ? phonesEq : project.eq(eqChannel) }

    /// Имя канала над MIX: дорожка, MASTER или CORRECT (коррекция наушников).
    var eqTargetName: String {
        if phonesShown { return "CORRECT" }
        return channel == .track ? track.name : "MASTER"
    }

    /// Окно коррекции наушников (тап по MASTER EQ; при MIX и MST).
    var phonesShown: Bool { return eqView && channel != .track && eqPhones }

    /// Канал на экране для спектров и сброса выбора: дорожка, мастер или коррекция наушников.
    var eqShownChannel: Int { return phonesShown ? EqSpec.phonesChannel : eqChannel }

    /// Правка показанного EQ: канала проекта (UNDO) или коррекции наушников (своя настройка, без UNDO).
    func eqEdit(_ f: (inout Eq) -> Void) {
        if phonesShown {
            var e: Eq = phonesEq
            f(&e)
            if e != phonesEq { setPhonesEq(e) }
            return
        }
        let ch: Int = eqChannel
        edit { $0.withEq(ch, f) }
    }

    var selectedBand: EqBand? { return eqTarget.band(eqBand) }

    /// Кнопка EQ: центр экрана — EQ или обратно (PATTERNS и редактор сэмпла закрываются).
    func toggleEqView() {
        eqView.toggle()
        // Кнопка EQ открывает EQ мастера, а не коррекцию наушников.
        eqPhones = false
        stopEqListen()
        eqMenu = nil
        eqMsMenu = nil
        eqDynMenu = nil
        eqPresetMenu = nil
        eqCompareMenu = false
        if eqView {
            browser = nil
            patternView = false
            editorOpen = false
            closeRoll()
            closeArrange()
            closeMasterWindow()
        }
    }

    /// Сравниваемая дорожка выбранной дорожки (номер; −1 — нет): у каждой дорожки своя, хранится по id дорожек
    /// (перестановка не сбивает, удалённая — нет сравнения).
    var eqCompare: Int {
        guard selectedTrack < project.tracks.count, let id = eqCompares[project.tracks[selectedTrack].id] else { return -1 }
        return project.tracks.firstIndex { $0.id == id } ?? -1
    }

    /// Сравниваемая дорожка, если её спектр сейчас показан (у EQ дорожки, не она сама).
    var eqCompareShown: Int? {
        let c: Int = eqCompare
        if !eqView || channel != .track || c < 0 || c == selectedTrack || c >= project.tracks.count { return nil }
        return c
    }

    /// Тап по имени канала: у дорожки — меню дорожек для сравнения, у мастера — окно коррекции наушников и обратно.
    func eqNameTapped() {
        if channel == .track {
            eqCompareMenu.toggle()
        } else {
            stopEqListen()
            eqMsMenu = nil
            eqDynMenu = nil
            eqPresetMenu = nil
            eqMenu = nil
            eqBand = -1
            eqPhones.toggle()
            syncSpectra()
        }
    }

    /// Сравнение выбранной дорожки: t — дорожка, −1 — OFF.
    func setEqCompare(_ t: Int) {
        if selectedTrack < project.tracks.count {
            let me: Int = project.tracks[selectedTrack].id
            eqCompares[me] = t >= 0 && t < project.tracks.count ? project.tracks[t].id : nil
        }
        eqCompareMenu = false
        syncSpectra()
    }

    /// Что слушают точки съёма спектров: канал EQ на экране, сравниваемая дорожка, выход мастера.
    func syncSpectra() {
        let s: Spectra = audio.core.spectra
        s.channel.store(eqView ? eqShownChannel : -1)
        s.compareTrack.store(eqCompareShown ?? -1)
    }

    /// Двойной тап по пустому месту: новая bell-полоса, она же выбрана.
    func addEqBand(freq: Double, gain: Double) {
        var k = -1
        eqEdit { k = $0.addBand(freq: freq, gain: gain) }
        if k >= 0 { eqBand = k }
    }

    /// Значения полосы k (внутри жеста — одна запись UNDO на жест).
    func setEqBand(_ k: Int, freq: Double? = nil, gain: Double? = nil, q: Double? = nil) {
        eqEdit { $0.setBand(k, freq: freq, gain: gain, q: q) }
        if eqListenBand >= 0 { syncEqListen() }
    }

    func setEqType(_ k: Int, _ type: Int) {
        eqEdit { $0.setType(k, type) }
        if eqListenBand >= 0 { syncEqListen() }
    }

    /// Режим M/S полосы k: 0 STEREO, 1 MID, 2 SIDE.
    func setEqMs(_ k: Int, _ ms: Int) {
        eqEdit { $0.setMs(k, ms) }
        if eqListenBand >= 0 { syncEqListen() }
    }

    /// Источник динамической полосы k: −1 OFF, 0 SELF, n — дорожка n.
    func setEqDyn(_ k: Int, _ src: Int) {
        eqEdit { $0.setDyn(k, src) }
    }

    /// THRESHOLD и RANGE динамической полосы k (внутри жеста — одна запись UNDO на жест).
    func setEqDynParams(_ k: Int, thr: Double? = nil, range: Double? = nil) {
        eqEdit { $0.setDynParams(k, thr: thr, range: range) }
    }

    /// Сдвиги динамических полос показанного канала сейчас, dB (0 — полоса не динамическая или выключена).
    func eqDynOffsets() -> [Double] {
        let e: Eq = eqTarget
        let ch: Int = eqChannel
        let levels: EqDynLevels = audio.core.eqDyn
        let phones: Bool = phonesShown
        return (0..<EqSpec.bands).map { k in
            guard !phones, e.on, let b = e.band(k), b.on, EqSpec.dynOn(b) else { return 0 }
            return Double(levels.offset(ch, k))
        }
    }

    /// Есть ли у показанного канала включённые динамические полосы (тогда точки и кривая двигаются).
    var eqHasDyn: Bool {
        let e: Eq = eqTarget
        if !e.on || phonesShown { return false }
        for case let b? in e.bands where b.on && EqSpec.dynOn(b) { return true }
        return false
    }

    /// Подпись источника: — (cut, notch), OFF, SELF, имя дорожки.
    func eqDynName(_ b: EqBand) -> String {
        if !EqSpec.hasGain(b.type) { return "—" }
        if !EqSpec.dynOn(b) { return "OFF" }
        if b.dyn == 0 { return "SELF" }
        let t: Int = b.dyn - 1
        return t < project.tracks.count ? project.tracks[t].name : "T\(b.dyn)"
    }

    func setEqSlope(_ k: Int, _ slope: Int) {
        eqEdit { $0.setSlope(k, slope) }
    }

    func toggleEqBand(_ k: Int) {
        eqEdit { $0.toggleBand(k) }
    }

    func deleteEqBand(_ k: Int) {
        eqEdit { $0.deleteBand(k) }
        if eqBand == k { eqBand = -1 }
        if eqListenBand >= 0 { syncEqListen() }
    }

    // MARK: — пресеты EQ (UserDefaults «eqPresets»; у коррекции наушников свой список — «phonesPresets»)

    /// Список пресетов показанного EQ.
    var eqBook: EqPresetBook { return phonesShown ? phonesPresets : eqPresets }

    private func editBook(_ f: (inout EqPresetBook) -> Void) {
        if phonesShown {
            f(&phonesPresets)
            UserDefaults.standard.set(phonesPresets.encode(), forKey: AppModel.phonesPresetsKey)
        } else {
            f(&eqPresets)
            UserDefaults.standard.set(eqPresets.encode(), forKey: "eqPresets")
        }
    }

    func saveEqPreset(name: String, over: Int? = nil) {
        let e: Eq = eqTarget
        editBook { $0.save(name: name, eq: e, over: over) }
    }

    /// Загрузить пресет k в показанный EQ (одна запись UNDO); выбор полосы сбрасывается.
    func loadEqPreset(_ k: Int) {
        let book: EqPresetBook = eqBook
        guard k >= 0 && k < book.list.count else { return }
        let p: EqPreset = book.list[k]
        let n: Int = phonesShown ? 0 : project.tracks.count
        eqEdit { $0.apply(p, tracks: n) }
        if phonesShown { setPhonesName(p.name) }
        eqBand = -1
    }

    func renameEqPreset(_ k: Int, to name: String) {
        editBook { $0.rename(k, to: name) }
    }

    func deleteEqPreset(_ k: Int) {
        editBook { $0.delete(k) }
    }

    static func loadEqPresets() -> EqPresetBook {
        return EqPresetBook.decode(UserDefaults.standard.data(forKey: "eqPresets"))
    }

    // MARK: — коррекция наушников (UserDefaults «phonesEq», «phonesPresets»)

    static let phonesEqKey = "phonesEq"
    static let phonesPresetsKey = "phonesPresets"
    static let phonesSeededKey = "phonesSeeded"
    static let phonesNameKey = "phonesName"

    func setPhonesName(_ name: String) {
        phonesName = name
        UserDefaults.standard.set(name, forKey: AppModel.phonesNameKey)
    }

    /// IMPORT в CORRECT PRESETS: выбор текстовых файлов профилей.
    func choosePhonesFiles() {
        eqPresetMenu = nil
        importingPhones = true
        importingProject = false
        importingLibrary = false
        importing = true
    }

    /// Профили из файлов (AutoEQ ParametricEQ.txt, Equalizer APO): каждый — пресет с именем файла (занятое имя —
    /// замена), первый — сразу в коррекцию (BYPASS прежний). Итог — окно с OK.
    func phonesImport(_ urls: [URL]) {
        var added: [String] = []
        var fitted: [String] = []
        var bad: [String] = []
        var first: (Eq, String)? = nil
        for u in urls {
            let access: Bool = u.startAccessingSecurityScopedResource()
            defer { if access { u.stopAccessingSecurityScopedResource() } }
            let text: String? = (try? Data(contentsOf: u)).flatMap { String(data: $0, encoding: .utf8) ?? String(data: $0, encoding: .isoLatin1) }
            let filters: [PhonesProfile.Filter] = text.map { PhonesProfile.parse($0) } ?? []
            if filters.isEmpty {
                bad.append(u.lastPathComponent)
                continue
            }
            let r = PhonesProfile.eq(filters)
            let name: String = PhonesProfile.name(fromFile: u.lastPathComponent)
            let over: Int? = phonesPresets.index(named: name)
            phonesPresets.save(name: name, eq: r.eq, over: over)
            added.append(name)
            if r.fitted { fitted.append("\(name): \(filters.count) filters fitted into 8 bands") }
            if first == nil { first = (r.eq, name) }
        }
        UserDefaults.standard.set(phonesPresets.encode(), forKey: AppModel.phonesPresetsKey)
        if let f = first {
            var c: Eq = f.0
            c.on = phonesEq.on
            setPhonesEq(c)
            setPhonesName(f.1)
            eqBand = -1
        }
        var lines: [String] = []
        if !added.isEmpty { lines.append("Imported: " + added.joined(separator: ", ") + ". Loaded: " + added[0] + ".") }
        lines += fitted
        if !bad.isEmpty { lines.append("No filters found in " + bad.joined(separator: ", ") + ".") }
        phonesNote = lines.joined(separator: "\n")
    }

    /// EXPORT в CORRECT PRESETS: файл — в окно сохранения в «Файлы» (EqView).
    func exportPhones() {
        eqPresetMenu = nil
        phonesExported = phonesExportFile()
    }

    /// Коррекция в текстовый файл AutoEQ (временный).
    func phonesExportFile() -> URL? {
        let dir: URL = FileManager.default.temporaryDirectory.appendingPathComponent("phonesexport", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe: String = phonesName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url: URL = dir.appendingPathComponent(safe + " ParametricEQ.txt")
        let text: String = PhonesProfile.text(phonesEq)
        return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }

    static func loadPhonesEq() -> Eq {
        guard let d = UserDefaults.standard.data(forKey: AppModel.phonesEqKey),
              let e = try? JSONDecoder().decode(Eq.self, from: d) else { return Eq() }
        return e
    }

    /// Список пресетов коррекции; в первый раз в нём — профиль Sony WH-1000XM4 (удалённый больше не появляется).
    static func loadPhonesPresets() -> EqPresetBook {
        let ud = UserDefaults.standard
        var b: EqPresetBook = EqPresetBook.decode(ud.data(forKey: AppModel.phonesPresetsKey))
        if !ud.bool(forKey: AppModel.phonesSeededKey) {
            b.list.insert(EqPresetBook.sonyXM4, at: 0)
            ud.set(b.encode(), forKey: AppModel.phonesPresetsKey)
            ud.set(true, forKey: AppModel.phonesSeededKey)
        }
        return b
    }

    /// Новая коррекция: сохранить и отдать звуку.
    func setPhonesEq(_ e: Eq) {
        phonesEq = e
        UserDefaults.standard.set(try? JSONEncoder().encode(e), forKey: AppModel.phonesEqKey)
        audio.core.phones.publish(e)
    }

    /// Предусиление коррекции (подпись PREAMP), dB.
    var phonesPreamp: Double { return EqSpec.preamp(phonesEq) }

    // MARK: — свой EQ по умолчанию (SAVE DEFAULT в PRESETS; KnobDefaults)

    /// SAVE DEFAULT: полосы показанного EQ — по умолчанию для новых дорожек (EQ дорожки) или проектов (EQ мастера).
    func saveEqDefault() {
        let bands: [EqBand?] = eqTarget.bands
        let master: Bool = channel != .track
        knobDefaults.setEq(bands, master: master)
        UserDefaults.standard.set(knobDefaults.encode(), forKey: AppModel.knobDefaultsKey)
        flashDefault(.eq)
    }

    /// BYPASS: выключение EQ канала.
    func toggleEqBypass() {
        eqEdit { $0.on.toggle() }
    }
}

/// Подписи значений EQ (как fmtHz, fmtGain веба).
enum EqFormat {
    static func hz(_ f: Double) -> String {
        if f < 1000 { return String(format: f < 100 ? "%.1f Hz" : "%.0f Hz", f) }
        return String(format: f < 10000 ? "%.2f kHz" : "%.1f kHz", f / 1000)
    }

    static func gain(_ g: Double) -> String {
        return String(format: "%@%.1f dB", g > 0 ? "+" : "", g)
    }

    static func note(_ f: Double) -> String {
        return Params.noteName(max(0, Int((69 + 12 * log2(f / 440)).rounded())))
    }

    /// M/S: STEREO, MID, SIDE.
    static func ms(_ b: EqBand) -> String {
        return EqSpec.msModes[max(0, min(b.ms, EqSpec.msModes.count - 1))]
    }

    /// TYPE: имя типа, у cut — с крутизной.
    static func type(_ b: EqBand) -> String {
        let name: String = EqSpec.types[b.type]
        return EqSpec.isCut(b.type) ? "\(name) \(EqSpec.slopes[b.slope])" : name
    }

    /// Частота из введённого текста: «440», «440 Hz», «1.5k», «2 kHz»; nil — не число.
    static func parseFreq(_ text: String) -> Double? {
        let s: String = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ",", with: ".")
        var digits: String = ""
        var rest: Substring = Substring(s)
        while let c = rest.first, c.isNumber || c == "." {
            digits.append(c)
            rest = rest.dropFirst()
        }
        guard var v = Double(digits), v > 0 else { return nil }
        if rest.trimmingCharacters(in: .whitespaces).hasPrefix("k") { v *= 1000 }
        return v
    }

    /// Число (запятая — как точка); nil — не число.
    static func parseNum(_ text: String) -> Double? {
        return Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}

/// Прослушивание полосы (как соло полосы в FabFilter Pro-Q): пока держат LISTEN, канал звучит только в области
/// выбранной полосы (EqListen); правки полосы (точка, поля) сразу ведут фильтр.
extension AppModel {
    /// LISTEN нажата (или, пока её держат, выбрана другая точка): слушать выбранную полосу.
    func startEqListen() {
        if phonesShown { return }
        eqListenHeld = true
        eqListenBand = selectedBand != nil ? eqBand : -1
        syncEqListen()
    }

    /// Фильтр прослушивания — по текущим значениям полосы.
    func syncEqListen() {
        let x: EqListen = audio.core.eqListen
        guard eqListenBand >= 0, let b = eqTarget.band(eqListenBand) else {
            x.channel.store(-1)
            return
        }
        let f = EqListen.filter(b)
        x.kind.store(f.kind)
        x.q.store(Float(f.q))
        x.freq.store(Float(b.freq))
        x.ms.store(b.ms)
        x.channel.store(eqChannel)
    }

    func stopEqListen() {
        eqListenHeld = false
        eqListenBand = -1
        audio.core.eqListen.channel.store(-1)
    }
}
