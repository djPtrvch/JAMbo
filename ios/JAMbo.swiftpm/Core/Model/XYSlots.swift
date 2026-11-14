// Режим XY (на пробу, SETTINGS → MORPH → XY PADS): у каждой дорожки четыре площадки, у каждой оси X и Y — одна из
// 16 ручек дорожки (Track.xy).

extension Track {
    /// Осей: 4 площадки × (X, Y); ось k — площадка k / 2, X — чётные.
    public static let xyAxes: Int = 8

    /// Ручка оси k (0…15); nil — не назначена.
    public func xySlot(_ k: Int) -> Int? {
        guard k >= 0 && k < xy.count else { return nil }
        let s: Int = xy[k]
        return s >= 0 && s < 16 ? s : nil
    }

    /// Назначить ось k на ручку slot (nil — снять).
    public mutating func setXYSlot(_ k: Int, _ slot: Int?) {
        guard k >= 0 && k < Track.xyAxes else { return }
        var a: [Int] = xy
        while a.count < Track.xyAxes { a.append(-1) }
        a[k] = slot ?? -1
        xy = a.allSatisfy { $0 < 0 } ? [] : a
    }
}
