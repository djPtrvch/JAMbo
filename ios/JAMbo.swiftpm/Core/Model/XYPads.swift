// Режим XY (на пробу, SETTINGS → MORPH → XY PADS): страница ручек дорожки — четыре площадки XY, у каждой две оси.

/// Ось площадки XY: ручка slot (0…15) страницы page (0 — дорожка, 1 — FX, 2 — MOD, 3 — мастер) дорожки track
/// (Track.id — ось остаётся у дорожки при перестановке); amount — степень −1…+1 (весь ход площадки × amount —
/// доля хода ручки; знак — направление).
public struct XYAxis: Codable, Equatable, Sendable {
    public var track: Int
    public var page: Int
    public var slot: Int
    public var amount: Double

    public init(track: Int, page: Int, slot: Int, amount: Double) {
        self.track = track
        self.page = page
        self.slot = slot
        self.amount = amount
    }

    /// Осей: 4 площадки × (X, Y); ось k — площадка k / 2, X — чётные.
    public static let count: Int = 8
}

extension Project {
    /// Ось k (nil — не назначена).
    public func xyAxis(_ k: Int) -> XYAxis? {
        return k >= 0 && k < xy.count ? xy[k] : nil
    }

    public mutating func setXYAxis(_ k: Int, _ a: XYAxis?) {
        guard k >= 0 && k < XYAxis.count else { return }
        while xy.count < XYAxis.count { xy.append(nil) }
        xy[k] = a
    }
}
