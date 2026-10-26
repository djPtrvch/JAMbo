import Darwin
import Foundation

/// Замер интерфейса (S14c): пересчёты body основных видов и кадры TimelineView метров в секунду и время главного
/// потока (интерфейс и drain, % одного ядра; без системного сервера отрисовки). Считается только пока DIAGNOSTICS
/// закрыто (окно закрывает экран — под ним SwiftUI не рисует): RESET, закрыть окно, сценарий, открыть — прочитать.
/// Не наблюдаемый — счёт сам перерисовок не вызывает. Только главный поток.
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

    private var counts: [Int] = [Int](repeating: 0, count: Kind.allCases.count)
    /// Окно DIAGNOSTICS открыто — счёт стоит.
    private var paused: Bool = false
    /// Время замера (с) и процессора главного потока (нс) до текущего отрезка; начало отрезка.
    private var measured: Double = 0
    private var cpuMeasured: UInt64 = 0
    private var runStart: Double = Date.timeIntervalSinceReferenceDate
    private var cpuStart: UInt64 = RedrawMeter.cpuNs()

    /// Вызов — первой строкой body (или кадра TimelineView).
    @discardableResult
    static func hit(_ k: Kind) -> Bool {
        let m: RedrawMeter = shared
        if !m.paused { m.counts[k.rawValue] += 1 }
        return true
    }

    func reset() {
        var k: Int = 0
        while k < counts.count {
            counts[k] = 0
            k += 1
        }
        measured = 0
        cpuMeasured = 0
        runStart = Date.timeIntervalSinceReferenceDate
        cpuStart = RedrawMeter.cpuNs()
    }

    /// DIAGNOSTICS открыли: отрезок замера закрыт.
    func pause() {
        if paused { return }
        paused = true
        measured += Date.timeIntervalSinceReferenceDate - runStart
        cpuMeasured += RedrawMeter.cpuNs() &- cpuStart
    }

    /// DIAGNOSTICS закрыли: новый отрезок.
    func resume() {
        if !paused { return }
        paused = false
        runStart = Date.timeIntervalSinceReferenceDate
        cpuStart = RedrawMeter.cpuNs()
    }

    /// Время замера, с.
    private var span: Double {
        return measured + (paused ? 0 : Date.timeIntervalSinceReferenceDate - runStart)
    }

    /// «18.0% of one core · 12.3 s measured».
    var mainLine: String {
        let s: Double = span
        if s < 0.5 { return "measuring… (close this window)" }
        let cpu: UInt64 = cpuMeasured + (paused ? 0 : RedrawMeter.cpuNs() &- cpuStart)
        let pct: Double = Double(cpu) / 1e9 / s * 100
        return String(format: "%.1f%% of one core · %.1f s measured (window closed)", pct, s)
    }

    /// Средние в секунду: «1210/s: Knob 960 · Meter 60 · …» — по убыванию, без нулей; сумма — первой.
    var line: String {
        let s: Double = span
        if s < 0.5 { return "measuring…" }
        var items: [(name: String, rate: Double)] = []
        var total: Double = 0
        for k in 0..<counts.count {
            let r: Double = Double(counts[k]) / s
            if r < 0.5 { continue }
            items.append((RedrawMeter.names[k], r))
            total += r
        }
        items.sort { $0.rate > $1.rate }
        if items.isEmpty { return "none" }
        let parts: [String] = items.map { "\($0.name) \(Int($0.rate.rounded()))" }
        return "\(Int(total.rounded()))/s: " + parts.joined(separator: " · ")
    }

    /// Время процессора потока, который зовёт (главного), нс.
    static func cpuNs() -> UInt64 {
        return clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    }
}
