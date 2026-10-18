import Foundation

// EQ канала (как Eq и EqBand в src/state.ts, константы — EQ_* в params.ts): 8 мест под полосы (nil — полосы нет).
// EQ дорожки — Track.eq (один на все её клипы, переезжает вместе с дорожкой), EQ мастера — Project.masterEq.
// Dynamic и M/S — S7.

public struct EqBand: Codable, Equatable, Sendable {
    public var on: Bool = true
    /// Индекс в EqSpec.types.
    public var type: Int
    public var freq: Double
    public var gain: Double
    public var q: Double
    /// Индекс в EqSpec.slopes (low cut, high cut).
    public var slope: Int = 0

    public init(on: Bool = true, type: Int, freq: Double, gain: Double, q: Double, slope: Int = 0) {
        self.on = on
        self.type = type
        self.freq = freq
        self.gain = gain
        self.q = q
        self.slope = slope
    }
}

public struct Eq: Codable, Equatable, Sendable {
    public var on: Bool = true
    public var bands: [EqBand?] = [EqBand?](repeating: nil, count: EqSpec.bands)

    public init() {}

    /// Полоса k (nil — нет места или полосы).
    public func band(_ k: Int) -> EqBand? {
        return k >= 0 && k < bands.count ? bands[k] : nil
    }
}

public enum EqSpec {
    /// Типы полос (как EQ_TYPES веба; индексы хранятся в проектах).
    public static let types = ["Bell", "Low Shelf", "High Shelf", "Low Cut", "High Cut", "Notch"]
    public static let bell = 0, lowShelf = 1, highShelf = 2, lowCut = 3, highCut = 4, notch = 5
    /// Порядок типов в меню и в поле TYPE: bell, low cut, high cut, затем остальные.
    public static let typeOrder = [0, 3, 4, 1, 2, 5]
    /// Крутизна среза, dB/окт (каскад из 1, 2 или 4 биквадов).
    public static let slopes = [12, 24, 48]
    public static let bands = 8
    public static let freqMin: Double = 20
    public static let freqMax: Double = 20000
    public static let gainMax: Double = 18
    public static let qMin: Double = 0.1
    public static let qMax: Double = 18
    public static let qDef: Double = 1

    public static func isCut(_ type: Int) -> Bool { return type == lowCut || type == highCut }
    /// Усиление не применяется к cut и notch.
    public static func hasGain(_ type: Int) -> Bool { return type <= highShelf }

    /// Число биквадов в каскаде полосы.
    public static func stages(_ b: EqBand) -> Int {
        return isCut(b.type) ? slopes[Swift.max(0, Swift.min(b.slope, slopes.count - 1))] / 12 : 1
    }

    /// Q для фильтра: у low cut / high cut, как в Web Audio, — в dB (резонанс).
    public static func filterQ(_ b: EqBand) -> Double {
        return isCut(b.type) ? 20 * log10(b.q) : b.q
    }

    // Параметры EQ для колбэка (снимок звука): на канал stride значений Double — [0] включён ли EQ, затем на полосу
    // [тип (−1 — нет или выключена), каскад, частота, усиление (0 у cut и notch), Q фильтра].
    public static let bandStride = 5
    public static let stride = 1 + bands * bandStride

    /// Каналы снимка: дорожки 0…maxTracks−1, мастер — maxTracks.
    public static let channels = Params.maxTracks + 1
    public static let masterChannel = Params.maxTracks

    static func fill(_ p: UnsafeMutablePointer<Double>, _ eq: Eq?) {
        p.initialize(repeating: 0, count: stride)
        guard let eq = eq else { return }
        p[0] = eq.on ? 1 : 0
        for k in 0..<bands {
            let o = 1 + k * bandStride
            guard let b = eq.band(k), b.on, eq.on else {
                p[o] = -1
                continue
            }
            p[o] = Double(b.type)
            p[o + 1] = Double(stages(b))
            p[o + 2] = b.freq
            p[o + 3] = hasGain(b.type) ? b.gain : 0
            p[o + 4] = filterQ(b)
        }
    }
}

// Правки EQ (как addEqBand, setEqBand… в state.ts). Канал: дорожка 0… или EqSpec.masterChannel.
extension Project {
    public func eq(_ ch: Int) -> Eq {
        if ch == EqSpec.masterChannel { return masterEq }
        return ch >= 0 && ch < tracks.count ? tracks[ch].eq : Eq()
    }

    mutating func withEq(_ ch: Int, _ f: (inout Eq) -> Void) {
        if ch == EqSpec.masterChannel {
            f(&masterEq)
        } else if ch >= 0 && ch < tracks.count {
            f(&tracks[ch].eq)
        }
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { return Swift.max(lo, Swift.min(hi, v)) }

    /// Новая bell-полоса в первом свободном месте; −1, если мест нет.
    @discardableResult
    public mutating func addEqBand(_ ch: Int, freq: Double, gain: Double) -> Int {
        guard let k = eq(ch).bands.firstIndex(where: { $0 == nil }) else { return -1 }
        let b = EqBand(type: EqSpec.bell, freq: Project.clamp(freq, EqSpec.freqMin, EqSpec.freqMax),
                       gain: Project.clamp(gain, -EqSpec.gainMax, EqSpec.gainMax), q: EqSpec.qDef)
        withEq(ch) { $0.bands[k] = b }
        return k
    }

    /// Значения полосы: частота, усиление (округление до 0,1 dB), Q.
    public mutating func setEqBand(_ ch: Int, _ k: Int, freq: Double? = nil, gain: Double? = nil, q: Double? = nil) {
        withEq(ch) { e in
            guard var b = e.band(k) else { return }
            if let f = freq { b.freq = Project.clamp(f, EqSpec.freqMin, EqSpec.freqMax) }
            if let g = gain { b.gain = (Project.clamp(g, -EqSpec.gainMax, EqSpec.gainMax) * 10).rounded() / 10 }
            if let v = q { b.q = Project.clamp(v, EqSpec.qMin, EqSpec.qMax) }
            e.bands[k] = b
        }
    }

    public mutating func setEqType(_ ch: Int, _ k: Int, _ type: Int) {
        let n = EqSpec.types.count
        withEq(ch) { e in
            guard var b = e.band(k) else { return }
            b.type = ((type % n) + n) % n
            e.bands[k] = b
        }
    }

    public mutating func setEqSlope(_ ch: Int, _ k: Int, _ slope: Int) {
        withEq(ch) { e in
            guard var b = e.band(k) else { return }
            b.slope = Swift.max(0, Swift.min(slope, EqSpec.slopes.count - 1))
            e.bands[k] = b
        }
    }

    /// Двойной тап по точке: включить или выключить полосу.
    public mutating func toggleEqBand(_ ch: Int, _ k: Int) {
        withEq(ch) { e in
            guard var b = e.band(k) else { return }
            b.on.toggle()
            e.bands[k] = b
        }
    }

    public mutating func deleteEqBand(_ ch: Int, _ k: Int) {
        withEq(ch) { e in
            if k >= 0 && k < e.bands.count { e.bands[k] = nil }
        }
    }

    /// BYPASS: выключение EQ канала.
    public mutating func toggleEq(_ ch: Int) {
        withEq(ch) { $0.on.toggle() }
    }
}
