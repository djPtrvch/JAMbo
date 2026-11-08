import Foundation

// Коррекция наушников (решение пользователя): профиль — полосы EQ (как у EQ канала, без M/S и DYN), звучит в
// монитор-цепочке (Core/Monitor, Headphone Monitor) в самом конце выхода. Настройка устройства, а не проекта: одна на
// приложение (UserDefaults), в проект, UNDO, экспорт песни, запись мастера и стемы не попадает. Окно — тап по MASTER EQ.
// Preamp — только для файла профиля (EXPORT); уровень в цепочке ведёт Level compensation.

extension EqSpec {
    /// Канал спектров EQ на экране для окна коррекции (до и после неё); не совпадает ни с дорожкой, ни с мастером.
    public static let phonesChannel = -2

    /// Предусиление коррекции, dB (≤ 0): минус наибольший подъём кривой EQ в 20 Гц…20 кГц, с округлением до 0,1 dB.
    public static func preamp(_ eq: Eq) -> Double {
        guard eq.on else { return 0 }
        let bands: [EqBand] = eq.bands.compactMap { $0 }.filter { $0.on }
        if bands.isEmpty { return 0 }
        let n = 256
        let hz: [Double] = (0..<n).map { i in freqMin * pow(freqMax / freqMin, Double(i) / Double(n - 1)) }
        var sum: [Double] = [Double](repeating: 0, count: n)
        for b in bands {
            let r: [Double] = EqCoeffs.response(b, hz: hz)
            for i in 0..<n { sum[i] += r[i] }
        }
        let peak: Double = sum.max() ?? 0
        return peak > 0 ? -(peak * 10).rounded(.up) / 10 : 0
    }
}

extension EqPresetBook {
    /// Профиль Sony WH-1000XM4 (закрытые, по замерам oratory1990 из AutoEQ — 10 фильтров и Preamp −6,1 dB):
    /// все 10 фильтров как есть, по частоте (у shelf Q 0,71). Кладётся в список пресетов коррекции один раз,
    /// его можно удалить.
    public static let sonyXM4: EqPreset = {
        let bell: Int = EqSpec.bell
        let bands: [EqBand?] = [
            EqBand(type: bell, freq: 56, gain: 1.2, q: 1.19),
            EqBand(type: EqSpec.lowShelf, freq: 105, gain: -4.2, q: 0.71),
            EqBand(type: bell, freq: 143, gain: -5.2, q: 1.1),
            EqBand(type: bell, freq: 407, gain: 1.7, q: 3.14),
            EqBand(type: bell, freq: 576, gain: -1.2, q: 3.55),
            EqBand(type: bell, freq: 1007, gain: 1.0, q: 3.41),
            EqBand(type: bell, freq: 2289, gain: 6.1, q: 1.57),
            EqBand(type: bell, freq: 5144, gain: -3.2, q: 6.0),
            EqBand(type: bell, freq: 6715, gain: 3.0, q: 5.99),
            EqBand(type: EqSpec.highShelf, freq: 10000, gain: -1.0, q: 0.71),
        ]
        return EqPreset(name: "Sony WH-1000XM4", bands: bands)
    }()

    /// Профиль AIAIAI TMA-2 Studio Wireless+ (8.11; набор: динамики S05, амбушюры E08, оголовье H10, передатчик X01).
    /// Отдельного замера в AutoEQ нет — взят TMA-2 HD Wireless (oratory1990): те же S05 и E08, другое оголовье.
    /// 10 фильтров как есть, по частоте (Preamp файла −6,4 dB); кладётся в список один раз, его можно удалить.
    public static let tma2Studio: EqPreset = {
        let bell: Int = EqSpec.bell
        let bands: [EqBand?] = [
            EqBand(type: bell, freq: 78, gain: -8.8, q: 0.21),
            EqBand(type: EqSpec.lowShelf, freq: 105, gain: 8.8, q: 0.7),
            EqBand(type: bell, freq: 717, gain: 3.5, q: 1.78),
            EqBand(type: bell, freq: 1190, gain: -1.4, q: 4.66),
            EqBand(type: bell, freq: 1812, gain: 0.8, q: 3.68),
            EqBand(type: bell, freq: 2660, gain: 5.8, q: 1.11),
            EqBand(type: bell, freq: 4847, gain: 1.2, q: 6.0),
            EqBand(type: bell, freq: 6361, gain: -1.5, q: 6.0),
            EqBand(type: bell, freq: 9107, gain: 6.1, q: 2.44),
            EqBand(type: EqSpec.highShelf, freq: 10000, gain: -0.2, q: 0.7),
        ]
        return EqPreset(name: "AIAIAI TMA-2 Studio Wireless+", bands: bands)
    }()

    /// Переход на 10 полос: пресет с именем профиля Sony, подогнанный прежде под 8 полос, — заменить точным.
    public mutating func upgradeSonyXM4() -> Bool {
        let p: EqPreset = EqPresetBook.sonyXM4
        guard let i = list.firstIndex(where: { $0.name == p.name }), list[i].count < p.count else { return false }
        list[i] = p
        return true
    }
}
