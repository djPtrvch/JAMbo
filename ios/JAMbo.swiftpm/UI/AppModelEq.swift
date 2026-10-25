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

    var eqTarget: Eq { return project.eq(eqChannel) }

    /// Имя канала над MIX: дорожка или MASTER.
    var eqTargetName: String { return channel == .track ? track.name : "MASTER" }

    var selectedBand: EqBand? { return eqTarget.band(eqBand) }

    /// Кнопка EQ: центр экрана — EQ или обратно (PATTERNS и редактор сэмпла закрываются).
    func toggleEqView() {
        eqView.toggle()
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

    /// Спектр выхода показан (EQ мастера, включён тапом по надписи).
    var eqOutShown: Bool { return eqView && channel != .track && eqOutOn }

    /// Тап по имени канала: у дорожки — меню дорожек для сравнения, у мастера — спектр выхода (как в вебе).
    func eqNameTapped() {
        if channel == .track {
            eqCompareMenu.toggle()
        } else {
            eqOutOn.toggle()
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
        s.channel.store(eqView ? eqChannel : -1)
        s.compareTrack.store(eqCompareShown ?? -1)
        s.outOn.store(eqOutShown ? 1 : 0)
    }

    /// Двойной тап по пустому месту: новая bell-полоса, она же выбрана.
    func addEqBand(freq: Double, gain: Double) {
        let ch = eqChannel
        var k = -1
        edit { k = $0.addEqBand(ch, freq: freq, gain: gain) }
        if k >= 0 { eqBand = k }
    }

    /// Значения полосы k (внутри жеста — одна запись UNDO на жест).
    func setEqBand(_ k: Int, freq: Double? = nil, gain: Double? = nil, q: Double? = nil) {
        let ch = eqChannel
        edit { $0.setEqBand(ch, k, freq: freq, gain: gain, q: q) }
    }

    func setEqType(_ k: Int, _ type: Int) {
        let ch = eqChannel
        edit { $0.setEqType(ch, k, type) }
    }

    /// Режим M/S полосы k: 0 STEREO, 1 MID, 2 SIDE.
    func setEqMs(_ k: Int, _ ms: Int) {
        let ch = eqChannel
        edit { $0.setEqMs(ch, k, ms) }
    }

    /// Источник динамической полосы k: −1 OFF, 0 SELF, n — дорожка n.
    func setEqDyn(_ k: Int, _ src: Int) {
        let ch = eqChannel
        edit { $0.setEqDyn(ch, k, src) }
    }

    /// THRESHOLD и RANGE динамической полосы k (внутри жеста — одна запись UNDO на жест).
    func setEqDynParams(_ k: Int, thr: Double? = nil, range: Double? = nil) {
        let ch = eqChannel
        edit { $0.setEqDynParams(ch, k, thr: thr, range: range) }
    }

    /// Сдвиги динамических полос показанного канала сейчас, dB (0 — полоса не динамическая или выключена).
    func eqDynOffsets() -> [Double] {
        let e: Eq = eqTarget
        let ch: Int = eqChannel
        let levels: EqDynLevels = audio.core.eqDyn
        return (0..<EqSpec.bands).map { k in
            guard e.on, let b = e.band(k), b.on, EqSpec.dynOn(b) else { return 0 }
            return Double(levels.offset(ch, k))
        }
    }

    /// Есть ли у показанного канала включённые динамические полосы (тогда точки и кривая двигаются).
    var eqHasDyn: Bool {
        let e: Eq = eqTarget
        if !e.on { return false }
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
        let ch = eqChannel
        edit { $0.setEqSlope(ch, k, slope) }
    }

    func toggleEqBand(_ k: Int) {
        let ch = eqChannel
        edit { $0.toggleEqBand(ch, k) }
    }

    func deleteEqBand(_ k: Int) {
        let ch = eqChannel
        edit { $0.deleteEqBand(ch, k) }
        if eqBand == k { eqBand = -1 }
    }

    // MARK: — пресеты EQ (UserDefaults «eqPresets»)

    func saveEqPreset(name: String, over: Int? = nil) {
        eqPresets.save(name: name, eq: eqTarget, over: over)
        storeEqPresets()
    }

    /// Загрузить пресет k в EQ показанного канала (одна запись UNDO); выбор полосы сбрасывается.
    func loadEqPreset(_ k: Int) {
        guard k >= 0 && k < eqPresets.list.count else { return }
        let ch = eqChannel
        let p: EqPreset = eqPresets.list[k]
        edit { $0.applyEqPreset(ch, p) }
        eqBand = -1
    }

    func renameEqPreset(_ k: Int, to name: String) {
        eqPresets.rename(k, to: name)
        storeEqPresets()
    }

    func deleteEqPreset(_ k: Int) {
        eqPresets.delete(k)
        storeEqPresets()
    }

    private func storeEqPresets() {
        UserDefaults.standard.set(eqPresets.encode(), forKey: "eqPresets")
    }

    static func loadEqPresets() -> EqPresetBook {
        return EqPresetBook.decode(UserDefaults.standard.data(forKey: "eqPresets"))
    }

    /// BYPASS: выключение EQ канала.
    func toggleEqBypass() {
        let ch = eqChannel
        edit { $0.toggleEq(ch) }
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

/// Прослушивание полосы (как Alt + перетаскивание в FabFilter Pro-Q): SHIFT + палец на точке — канал звучит только в
/// области полосы (EqListen), пока палец на точке; перетаскивание ведёт частоту фильтра.
extension AppModel {
    func startEqListen(_ k: Int) {
        eqListenBand = k
        syncEqListen()
    }

    /// Фильтр прослушивания — по текущим значениям полосы (после каждого сдвига точки).
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
        eqListenBand = -1
        audio.core.eqListen.channel.store(-1)
    }
}
