import AVFoundation
import Foundation
import Synchronization
import os

/// Проверка многоядерного режима (17.11, спайк перед эффектами на каждой дорожке): сколько стоит разнести работу
/// колбэка по нескольким потокам реального времени в аудио-группе (Audio Workgroup) выхода.
/// Нагрузка — N настоящих Reverb (FxReverb) на шуме, результат никуда не идёт. Режимы по 4 с: колбэк один, затем
/// с 1, 2 и 3 помощниками. Задания (по одному Reverb) разбирают по очереди колбэк и помощники через атомарный счётчик:
/// помощник не проснулся — всё досчитает колбэк. Строки результата — в SETTINGS → AUDIO ENGINE.
/// После решения по многоядерному режиму файл и кнопки удаляются.
final class MultiCoreSpike: @unchecked Sendable {
    static let maxJobs: Int = 16
    static let maxFrames: Int = 4096
    static let helpers: Int = 3
    /// Режимы: число помощников; −1 — разогрев (не считается).
    static let modes: [Int] = [-1, 0, 1, 2, 3]
    static let modeSec: Double = 4
    static let warmSec: Double = 1

    private let reverbs: UnsafeMutablePointer<FxReverb>
    private let noiseL: UnsafeMutablePointer<Float>
    private let noiseR: UnsafeMutablePointer<Float>
    private let outL: UnsafeMutablePointer<Float>
    private let outR: UnsafeMutablePointer<Float>
    private let modeList: UnsafeMutablePointer<Int>
    private let modeCount: Int

    /// 0 — выкл., 1 — идёт, 2 — готово.
    private let state = Atomic<Int>(0)
    private let next = Atomic<Int>(0)
    private let done = Atomic<Int>(0)
    private let quit = Atomic<Int>(0)
    private let helperJobs = Atomic<Int>(0)
    private let joinedOk = Atomic<Int>(0)
    private let joinFailed = Atomic<Int>(0)
    private let rtFailed = Atomic<Int>(0)
    private var sems: [DispatchSemaphore] = []
    private let semPtr: UnsafeMutablePointer<DispatchSemaphore?>

    // Пишет только колбэк (интерфейс читает раз в 0,5 с — гонка безвредна для замера).
    private var jobs: Int = 8
    private var frames: Int = 0
    private var mode: Int = 0
    private var modeFrames: Int = 0
    private let sumNs: UnsafeMutablePointer<Double>
    private let maxNs: UnsafeMutablePointer<Double>
    private let totalSum: UnsafeMutablePointer<Double>
    private let blocks: UnsafeMutablePointer<Int>
    private let over: UnsafeMutablePointer<Int>
    private let byHelpers: UnsafeMutablePointer<Int>
    private let stuck: UnsafeMutablePointer<Int>

    private(set) var maxThreads: Int = 0
    private(set) var loadJobs: Int = 0
    private(set) var note: String = ""

    private let scale: Double
    private let sr: Double = AudioCore.sampleRate

    init() {
        reverbs = UnsafeMutablePointer<FxReverb>.allocate(capacity: MultiCoreSpike.maxJobs)
        for k in 0..<MultiCoreSpike.maxJobs {
            (reverbs + k).initialize(to: FxReverb(sampleRate: AudioCore.sampleRate, seed: UInt32(1000 + k)))
        }
        let n: Int = MultiCoreSpike.maxFrames
        noiseL = UnsafeMutablePointer<Float>.allocate(capacity: n)
        noiseR = UnsafeMutablePointer<Float>.allocate(capacity: n)
        var seed: UInt32 = 12345
        for i in 0..<n {
            seed = seed &* 1664525 &+ 1013904223
            noiseL[i] = Float(Int32(bitPattern: seed)) / Float(Int32.max) * 0.25
            seed = seed &* 1664525 &+ 1013904223
            noiseR[i] = Float(Int32(bitPattern: seed)) / Float(Int32.max) * 0.25
        }
        outL = UnsafeMutablePointer<Float>.allocate(capacity: n * MultiCoreSpike.maxJobs)
        outR = UnsafeMutablePointer<Float>.allocate(capacity: n * MultiCoreSpike.maxJobs)
        outL.initialize(repeating: 0, count: n * MultiCoreSpike.maxJobs)
        outR.initialize(repeating: 0, count: n * MultiCoreSpike.maxJobs)
        let ml = MultiCoreSpike.modes
        modeCount = ml.count
        modeList = UnsafeMutablePointer<Int>.allocate(capacity: ml.count)
        for (k, v) in ml.enumerated() { (modeList + k).initialize(to: v) }
        let c: Int = ml.count
        sumNs = UnsafeMutablePointer<Double>.allocate(capacity: c)
        maxNs = UnsafeMutablePointer<Double>.allocate(capacity: c)
        totalSum = UnsafeMutablePointer<Double>.allocate(capacity: c)
        blocks = UnsafeMutablePointer<Int>.allocate(capacity: c)
        over = UnsafeMutablePointer<Int>.allocate(capacity: c)
        byHelpers = UnsafeMutablePointer<Int>.allocate(capacity: c)
        stuck = UnsafeMutablePointer<Int>.allocate(capacity: c)
        semPtr = UnsafeMutablePointer<DispatchSemaphore?>.allocate(capacity: MultiCoreSpike.helpers)
        semPtr.initialize(repeating: nil, count: MultiCoreSpike.helpers)
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        scale = Double(info.numer) / Double(info.denom)
        clearStats()
    }

    var running: Bool { return state.load(ordering: .acquiring) == 1 }

    private func clearStats() {
        for k in 0..<modeCount {
            sumNs[k] = 0
            maxNs[k] = 0
            totalSum[k] = 0
            blocks[k] = 0
            over[k] = 0
            byHelpers[k] = 0
            stuck[k] = 0
        }
    }

    /// Запуск (главный поток): помощники входят в аудио-группу выхода и ждут заданий.
    func start(jobs j: Int, workgroup: WorkGroup?) {
        if state.load(ordering: .acquiring) == 1 { return }
        quit.store(0, ordering: .releasing)
        joinedOk.store(0, ordering: .relaxed)
        joinFailed.store(0, ordering: .relaxed)
        rtFailed.store(0, ordering: .relaxed)
        helperJobs.store(0, ordering: .relaxed)
        clearStats()
        jobs = max(1, min(MultiCoreSpike.maxJobs, j))
        loadJobs = jobs
        mode = 0
        modeFrames = 0
        maxThreads = 0
        note = ""
        if let wg = workgroup {
            maxThreads = Int(os_workgroup_max_parallel_threads(wg, nil))
        } else {
            note = "no workgroup"
        }
        sems = []
        for k in 0..<MultiCoreSpike.helpers {
            let s = DispatchSemaphore(value: 0)
            sems.append(s)
            semPtr[k] = s
            let t = Thread { [unowned self] in self.helperLoop(s, workgroup) }
            t.name = "JAMbo helper \(k + 1)"
            t.qualityOfService = .userInteractive
            t.stackSize = 1 << 19
            t.start()
        }
        state.store(1, ordering: .releasing)
        let total: Double = MultiCoreSpike.warmSec + MultiCoreSpike.modeSec * Double(modeCount - 1) + 1
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in self?.shutdown() }
    }

    /// Остановить помощников (главный поток, после всех режимов).
    private func shutdown() {
        if state.load(ordering: .acquiring) == 1 { state.store(2, ordering: .releasing) }
        quit.store(1, ordering: .releasing)
        for s in sems { s.signal() }
        sems = []
    }

    private func helperLoop(_ sem: DispatchSemaphore, _ wg: WorkGroup?) {
        if !makeRealtime() { rtFailed.wrappingAdd(1, ordering: .relaxed) }
        var token = os_workgroup_join_token_s()
        var joined = false
        if let g = wg {
            let r: Int32 = os_workgroup_join(g, &token)
            if r == 0 {
                joined = true
                joinedOk.wrappingAdd(1, ordering: .relaxed)
            } else {
                joinFailed.wrappingAdd(1, ordering: .relaxed)
            }
        }
        while quit.load(ordering: .acquiring) == 0 {
            sem.wait()
            if quit.load(ordering: .acquiring) != 0 { break }
            let n: Int = runJobs()
            if n > 0 { helperJobs.wrappingAdd(n, ordering: .relaxed) }
        }
        if joined, let g = wg { os_workgroup_leave(g, &token) }
    }

    /// Поток реального времени (как аудиопоток): период — блок 256 отсчётов, расчёт — до половины.
    private func makeRealtime() -> Bool {
        let periodNs: Double = 256 / sr * 1e9
        let toTicks: Double = 1 / scale
        var policy = thread_time_constraint_policy_data_t(
            period: UInt32(periodNs * toTicks),
            computation: UInt32(periodNs * 0.5 * toTicks),
            constraint: UInt32(periodNs * toTicks),
            preemptible: 1)
        let count = mach_msg_type_number_t(MemoryLayout<thread_time_constraint_policy_data_t>.size
                                           / MemoryLayout<integer_t>.size)
        let r: kern_return_t = withUnsafeMutablePointer(to: &policy) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { q in
                thread_policy_set(pthread_mach_thread_np(pthread_self()),
                                  thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY), q, count)
            }
        }
        return r == KERN_SUCCESS
    }

    /// Разобрать задания (любой поток); вернуть, сколько сделано.
    private func runJobs() -> Int {
        let total: Int = jobs
        let n: Int = frames
        var mine: Int = 0
        while true {
            let j: Int = next.wrappingAdd(1, ordering: .acquiringAndReleasing).oldValue
            if j >= total { break }
            let off: Int = j * MultiCoreSpike.maxFrames
            reverbs[j].process(inL: noiseL, inR: noiseR, outL: outL + off, outR: outR + off, frames: n,
                               size: 30, decay: 1.5, tone: 0, lowcut: 20, predelay: 0)
            mine += 1
            done.wrappingAdd(1, ordering: .acquiringAndReleasing)
        }
        return mine
    }

    /// Колбэк: после AudioCore.render. start — mach-время начала колбэка.
    func run(frames f: Int, start: UInt64) {
        if state.load(ordering: .acquiring) != 1 { return }
        if mode >= modeCount { return }
        let n: Int = min(f, MultiCoreSpike.maxFrames)
        let helpers: Int = max(0, modeList[mode])
        let t0: UInt64 = mach_absolute_time()
        frames = n
        done.store(0, ordering: .relaxed)
        let before: Int = helperJobs.load(ordering: .relaxed)
        next.store(0, ordering: .releasing)
        for k in 0..<helpers { semPtr[k]?.signal() }
        _ = runJobs()
        let total: Int = jobs
        // Ждать помощников, не дольше 20 мс (застрял — в счёт stuck).
        var spins: Int = 0
        var late = false
        while done.load(ordering: .acquiring) < total {
            spins += 1
            if spins & 1023 == 0 {
                let waited: Double = Double(mach_absolute_time() - t0) * scale
                if waited > 20e6 {
                    late = true
                    break
                }
            }
        }
        let t1: UInt64 = mach_absolute_time()
        let partNs: Double = Double(t1 - t0) * scale
        let allNs: Double = Double(t1 - start) * scale
        let budgetNs: Double = Double(n) / sr * 1e9
        let m: Int = mode
        if modeList[m] >= 0 {
            sumNs[m] += partNs
            if partNs > maxNs[m] { maxNs[m] = partNs }
            totalSum[m] += allNs
            blocks[m] += 1
            if allNs > budgetNs { over[m] += 1 }
            if late { stuck[m] += 1 }
        }
        // Задания помощников за блок (поздние — в счёт следующего, мелочь).
        let after: Int = helperJobs.load(ordering: .relaxed)
        if modeList[m] >= 0 { byHelpers[m] += after - before }
        modeFrames += n
        let sec: Double = modeList[m] < 0 ? MultiCoreSpike.warmSec : MultiCoreSpike.modeSec
        // Помощник застрял на задании — следующий блок дал бы тот же Reverb двум потокам: проверка кончается.
        if late {
            state.store(2, ordering: .releasing)
            return
        }
        if Double(modeFrames) >= sec * sr {
            mode += 1
            modeFrames = 0
            if mode >= modeCount { state.store(2, ordering: .releasing) }
        }
    }

    /// Строки результата (интерфейс).
    var lines: [String] {
        let st: Int = state.load(ordering: .acquiring)
        if st == 0 { return ["Not run yet."] }
        var out: [String] = []
        var head: String = st == 1 ? "Running… (\(loadJobs) reverbs)" : "Done (\(loadJobs) reverbs)"
        head += " · workgroup threads \(maxThreads) · joined \(joinedOk.load(ordering: .relaxed))"
        let jf: Int = joinFailed.load(ordering: .relaxed)
        if jf > 0 { head += " · join failed \(jf)" }
        let rf: Int = rtFailed.load(ordering: .relaxed)
        if rf > 0 { head += " · realtime failed \(rf)" }
        if !note.isEmpty { head += " · " + note }
        out.append(head)
        let budgetMs: Double = 256 / sr * 1000
        for k in 0..<modeCount where modeList[k] >= 0 {
            let b: Int = blocks[k]
            if b == 0 { continue }
            let avg: Double = sumNs[k] / Double(b) / 1e6
            let peak: Double = maxNs[k] / 1e6
            let all: Double = totalSum[k] / Double(b) / 1e6
            let share: Int = Int((Double(byHelpers[k]) / Double(b * max(1, loadJobs)) * 100).rounded())
            let h: Int = modeList[k]
            var s: String = h == 0 ? "1 thread" : "1 + \(h) helper" + (h > 1 ? "s" : "")
            s += String(format: ": reverbs %.2f ms (peak %.2f) · callback %.0f%% of block", avg, peak, all / budgetMs * 100)
            s += " · by helpers \(share)% · overruns \(over[k])"
            if stuck[k] > 0 { s += " · stuck \(stuck[k])" }
            out.append(s)
        }
        return out
    }
}
