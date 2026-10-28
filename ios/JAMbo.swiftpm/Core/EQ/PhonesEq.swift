import Foundation

// Коррекция наушников (решение пользователя): EQ в самом конце выхода — после мастера, громкости выхода, референса
// и прослушивания, то есть на всё, что слышно в наушниках. Настройка устройства, а не проекта: одна на приложение
// (UserDefaults), в проект, UNDO, экспорт песни, запись мастера и стемы не попадает. Окно — тап по MASTER EQ.
// Полосы — те же, что у EQ канала, без M/S и DYN; перед EQ — предусиление: минус подъём кривой (как Preamp у AutoEQ),
// чтобы коррекция не перегружала выход.

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

    /// Переход на 10 полос: пресет с именем профиля Sony, подогнанный прежде под 8 полос, — заменить точным.
    public mutating func upgradeSonyXM4() -> Bool {
        let p: EqPreset = EqPresetBook.sonyXM4
        guard let i = list.firstIndex(where: { $0.name == p.name }), list[i].count < p.count else { return false }
        list[i] = p
        return true
    }
}

/// Коррекция наушников в колбэке: предусиление (плавно, 20 мс) и EqUnit. Параметры — от интерфейса через очередь
/// номеров заранее выделенных буферов (без выделений в колбэке).
public final class PhonesEq: @unchecked Sendable {
    static let slots = 8
    static let size = EqSpec.stride + 1
    let unit: EqUnit
    /// Буферы параметров: EqSpec.fill и предусиление (усиление) последним значением.
    private let ring: UnsafeMutablePointer<Double>
    private let queue = SPSCQueue<Int>(capacity: 16, filler: -1)
    private var nextSlot = 0
    /// Действующие параметры (копия в колбэке).
    private let cur: UnsafeMutablePointer<Double>
    private var gain: Float = 1
    private let glide: Float
    /// Экспорт песни идёт (1): коррекция не применяется.
    public let paused = AtomicCounter()

    public init(sampleRate: Double) {
        unit = EqUnit(sampleRate: sampleRate)
        ring = .allocate(capacity: PhonesEq.slots * PhonesEq.size)
        ring.initialize(repeating: 0, count: PhonesEq.slots * PhonesEq.size)
        cur = .allocate(capacity: PhonesEq.size)
        cur.initialize(repeating: 0, count: PhonesEq.size)
        cur[EqSpec.stride] = 1
        glide = Float(1 - exp(-1 / (0.02 * sampleRate)))
    }

    deinit {
        ring.deallocate()
        cur.deallocate()
    }

    /// Новые полосы (основной поток); nil или BYPASS — без коррекции.
    public func publish(_ eq: Eq?) {
        let p: UnsafeMutablePointer<Double> = ring + nextSlot * PhonesEq.size
        EqSpec.fill(p, eq)
        let pre: Double = eq.map { EqSpec.preamp($0) } ?? 0
        p[EqSpec.stride] = pow(10, pre / 20)
        _ = queue.push(nextSlot)
        nextSlot = (nextSlot + 1) % PhonesEq.slots
    }

    /// Блок на месте (колбэк).
    @inline(__always)
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, _ n: Int) {
        var latest: Int = -1
        while let k = queue.pop() { latest = k }
        if latest >= 0 { cur.update(from: ring + latest * PhonesEq.size, count: PhonesEq.size) }
        let target: Float = paused.load() != 0 ? 1 : Float(cur[EqSpec.stride])
        var g: Float = gain
        if g != 1 || target != 1 {
            let a: Float = glide
            var i = 0
            while i < n {
                g += (target - g) * a
                left[i] *= g
                right[i] *= g
                i += 1
            }
            if abs(g - target) < 1e-6 { g = target }
            gain = g
        }
        if paused.load() != 0 { return }
        unit.process(left: left, right: right, frames: n, params: UnsafePointer(cur))
    }
}
