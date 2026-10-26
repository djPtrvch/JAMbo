import Foundation

/// Пересчёты видов (S14c): сколько раз в секунду SwiftUI считает body основных видов и кадры TimelineView метров —
/// в среднем с RESET (DIAGNOSTICS закрывает экран: RESET, закрыть окно, сценарий, открыть — прочитать). Не
/// наблюдаемый — счёт сам перерисовок не вызывает. Только главный поток.
final class RedrawMeter {
    enum Kind: Int, CaseIterable {
        case root, topBar, left, knobGrid, knob, right, meter, tracks, seq, keyboard, pages, patterns, arrange, eq,
             masterWin, masterInd, mixMeter, editor, roll
    }

    static let names: [String] = [
        "Root", "TopBar", "Left", "KnobGrid", "Knob", "Right", "Meter", "Tracks", "Seq", "Keyboard", "Pages",
        "Patterns", "Arrange", "EQ", "MstWin", "MstInd", "MixMeter", "Editor", "Roll",
    ]

    static let shared = RedrawMeter()

    /// Пересчётов с последнего RESET и его время (секунды хоста).
    private var counts: [Int] = [Int](repeating: 0, count: Kind.allCases.count)
    private var since: Double = Date.timeIntervalSinceReferenceDate

    /// Вызов — первой строкой body (или кадра TimelineView).
    @discardableResult
    static func hit(_ k: Kind) -> Bool {
        shared.counts[k.rawValue] += 1
        return true
    }

    func reset() {
        var k: Int = 0
        while k < counts.count {
            counts[k] = 0
            k += 1
        }
        since = Date.timeIntervalSinceReferenceDate
    }

    /// Средние в секунду с RESET: «1210/s: Knob 960 · Meter 60 · …» — по убыванию, без нулей; сумма — первой.
    var line: String {
        let span: Double = Date.timeIntervalSinceReferenceDate - since
        if span < 0.5 { return "measuring…" }
        var items: [(name: String, rate: Double)] = []
        var total: Double = 0
        for k in 0..<counts.count {
            let r: Double = Double(counts[k]) / span
            if r < 0.5 { continue }
            items.append((RedrawMeter.names[k], r))
            total += r
        }
        items.sort { $0.rate > $1.rate }
        if items.isEmpty { return "none" }
        let parts: [String] = items.map { "\($0.name) \(Int($0.rate.rounded()))" }
        return "\(Int(total.rounded()))/s: " + parts.joined(separator: " · ")
    }
}
