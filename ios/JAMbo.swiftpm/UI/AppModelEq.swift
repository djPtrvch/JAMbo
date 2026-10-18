import Foundation

/// Меню полосы EQ (долгое нажатие по точке, тап по TYPE): полоса, точка, у которой открыть, и поле EQ, в котором
/// меню помещается (координаты «root»).
struct EqMenuState: Equatable {
    let band: Int
    let anchor: CGPoint
    let bounds: CGRect
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
        eqMenu = nil
        if eqView {
            patternView = false
            editorOpen = false
        }
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
