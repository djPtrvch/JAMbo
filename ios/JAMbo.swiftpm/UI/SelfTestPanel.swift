import SwiftUI
import Observation

/// Прогон самотеста своих движков (KICK, ANALOG, FM, WTABLE), эффектов, мастера и EQ вне основного потока; результаты — по мере готовности.
@Observable
final class SelfTestRunner {
    private(set) var results: [Golden.Result] = []
    private(set) var total: Int = 0
    private(set) var running: Bool = false
    private(set) var seconds: Double = 0
    private(set) var error: String = ""

    func run() {
        if running { return }
        running = true
        results = []
        error = ""
        seconds = 0
        Task.detached(priority: .userInitiated) {
            let start = Date()
            let bundle = Bundle.main
            guard let golden = Golden.directory(of: "jambo_cases.json", in: bundle,
                                                subdirectories: ["golden", "Resources/golden"]) else {
                await MainActor.run { self.finish("Resources not found (golden cases).", start) }
                return
            }
            let jambo = try? JamboSelfTest.loadCases(golden)
            let fx = try? FxSelfTest.loadCases(golden)
            let mst = try? MasterSelfTest.loadCases(golden)
            let eqs = try? EqSelfTest.loadCases(golden)
            var count: Int = jambo.map { JamboSelfTest.usable($0).count } ?? 0
            count += fx?.cases.count ?? 0
            count += mst?.cases.count ?? 0
            count += eqs?.count ?? 0
            await MainActor.run { self.total = count }
            if let jb = jambo {
                let tables = JamboTables()
                var wavetables: [String: WtTable] = [:]
                for c in JamboSelfTest.usable(jb) {
                    do {
                        let r = try JamboSelfTest.run(c, jb, golden, tables: tables, wavetables: &wavetables)
                        await MainActor.run { self.results.append(r) }
                    } catch {
                        await MainActor.run { self.finish("Cannot read \(c.file).", start) }
                        return
                    }
                }
            }
            if let fx = fx {
                for c in fx.cases {
                    do {
                        let r = try FxSelfTest.run(c, fx, golden)
                        await MainActor.run { self.results.append(r) }
                    } catch {
                        await MainActor.run { self.finish("Cannot read \(c.file).", start) }
                        return
                    }
                }
            }
            if let mst = mst {
                for c in mst.cases {
                    do {
                        let r = try MasterSelfTest.run(c, mst, golden)
                        await MainActor.run { self.results.append(r) }
                    } catch {
                        await MainActor.run { self.finish("Cannot read \(c.file).", start) }
                        return
                    }
                }
            }
            for c in eqs ?? [] {
                do {
                    let r = try EqSelfTest.run(c, golden)
                    await MainActor.run { self.results.append(r) }
                } catch {
                    await MainActor.run { self.finish("Cannot read \(c.file).", start) }
                    return
                }
            }
            await MainActor.run { self.finish("", start) }
        }
    }

    private func finish(_ message: String, _ start: Date) {
        error = message
        seconds = Date().timeIntervalSince(start)
        running = false
    }

    var passed: Int { results.filter { $0.ok }.count }
}

/// SELF-TEST в DIAGNOSTICS: движки синта и эффекты против эталонов веба (по отсчётам ≤ −60 dB или полосы ±0,5 dB).
struct SelfTestPanel: View {
    @State private var runner = SelfTestRunner()
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                InkButton(title: runner.running ? "RUNNING…" : "RUN SELF-TEST", active: runner.running) {
                    runner.run()
                }
                .frame(width: 220)
                summary
            }
            Text("Synth engines, FX, master and EQ vs. web reference: samples ≤ −60 dB or 1/3-octave bands within ±0.5 dB.")
                .font(.system(size: 12)).foregroundStyle(theme.dim)
            MenuScroll {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(runner.results.enumerated()), id: \.offset) { _, r in
                        SelfTestRow(result: r)
                    }
                }
                .padding(.trailing, 8)
            }
        }
    }

    private var summary: some View {
        let failed: Int = runner.results.count - runner.passed
        let text: String = summaryText()
        return VStack(alignment: .leading, spacing: 2) {
            Text(text).font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(failed > 0 ? theme.rec : theme.text)
            if !runner.error.isEmpty {
                Text(runner.error).font(.system(size: 12)).foregroundStyle(theme.rec)
            }
        }
    }
}

extension SelfTestPanel {
    /// «n/N PASS · k/N done · t s»; до первого прогона — «Not run yet.».
    fileprivate func summaryText() -> String {
        if runner.total == 0 && !runner.running { return "Not run yet." }
        let done: Int = runner.results.count
        var text: String = "\(runner.passed)/\(runner.total) PASS · \(done)/\(runner.total) done"
        if !runner.running {
            text += String(format: " · %.1f s", runner.seconds)
        }
        return text
    }
}

/// Строка таблицы: движок, случай, ошибка по отсчётам, полосы, итог.
private struct SelfTestRow: View {
    let result: Golden.Result
    @Environment(\.theme) private var theme

    /// Имя по коду: свои движки 16–19, FX 32–35, мастер 36–40, EQ 41.
    static func name(_ code: Int) -> String {
        if let n = JamboSelfTest.engineNames[code] { return n }
        if let n = FxSelfTest.engineNames[code] { return n }
        if let n = EqSelfTest.engineNames[code] { return n }
        return MasterSelfTest.engineNames[code] ?? "?"
    }

    var body: some View {
        let name: String = SelfTestRow.name(result.engine)
        let samples: String = String(format: "%.1f dB", result.sampleErrorDb)
        let bands: String = String(format: "±%.3f dB", result.maxBandDiffDb)
        HStack(spacing: 12) {
            cell(name, 90, theme.text)
            cell(result.file, 170, theme.dim)
            cell(samples, 80, result.sampleErrorDb <= -60 ? theme.text : theme.dim)
            cell(bands, 90, result.maxBandDiffDb <= 0.5 ? theme.text : theme.dim)
            cell(result.ok ? "PASS" : "FAIL", 50, result.ok ? theme.text : theme.rec)
        }
        .frame(height: 22)
    }

    private func cell(_ text: String, _ width: CGFloat, _ color: Color) -> some View {
        Text(text).font(.system(size: 12, weight: .bold)).monospacedDigit()
            .foregroundStyle(color).frame(width: width, alignment: .leading)
    }
}
