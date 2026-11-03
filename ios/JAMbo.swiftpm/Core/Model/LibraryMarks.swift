import Foundation

// Нарезка и варпинг сэмплов в библиотеке (решение пользователя 3.11): маркеры нарезки и метки WARP, поставленные в
// редакторе, запоминаются по ключу сэмпла (ключ — по содержимому: тот же файл — тот же ключ) и подставляются, когда
// этот сэмпл загружают на дорожку, где своих маркеров и меток у него нет (другая дорожка, другой проект, IMPORT).

public struct SampleMarks: Codable, Equatable, Sendable {
    public var slices: [SliceMark]
    public var warp: WarpInfo?

    public init(slices: [SliceMark] = [], warp: WarpInfo? = nil) {
        self.slices = slices
        self.warp = warp
    }

    public var isEmpty: Bool { return slices.isEmpty && (warp?.isEmpty ?? true) }
}

extension Library {
    /// Запомнить нарезку и варпинг сэмпла key (пусто — забыть); true — изменилось.
    @discardableResult
    public mutating func remember(_ key: String, _ m: SampleMarks) -> Bool {
        if key.isEmpty { return false }
        let now: SampleMarks? = m.isEmpty ? nil : m
        if marks[key] == now { return false }
        marks[key] = now
        return true
    }
}

extension Track {
    /// Нарезка и варпинг сэмпла key у дорожки.
    public func sampleMarks(_ key: String) -> SampleMarks {
        let w: WarpInfo = warpInfo(key)
        return SampleMarks(slices: sliceMarks(key), warp: w.isEmpty ? nil : w)
    }

    /// Запомненные в библиотеке — сэмплу key, если своих маркеров и меток у дорожки нет.
    public mutating func applyMarks(_ key: String, _ m: SampleMarks?) {
        guard let m = m, !key.isEmpty, sampleMarks(key).isEmpty else { return }
        putMarks(key, m.slices)
        if let w = m.warp { putWarp(key, w) }
    }
}
