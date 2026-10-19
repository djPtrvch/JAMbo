import AVFoundation
import Foundation

/// Аудиосессия 48 кГц и один AVAudioSourceNode, в колбэке которого считается весь звук (AudioCore.render).
final class AudioHost {
    let core = AudioCore()
    let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var observers: [NSObjectProtocol] = []
    private(set) var lastError: String = ""
    /// Запись входа (tap на узле входа) — Audio/InputCapture.swift.
    let input = InputCapture()

    init() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            self?.handleInterruption(note)
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restart()
        })
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    /// Запуск звука (при старте приложения и возврате из фона).
    func start() {
        do {
            trace("audio: session")
            try configureSession()
            trace("audio: node")
            if source == nil { attachSource() }
            trace("audio: engine start")
            if !engine.isRunning { try engine.start() }
            trace("audio: running")
            lastError = ""
        } catch {
            lastError = error.localizedDescription
            trace("audio error: \(lastError)")
        }
    }

    /// Остановка (уход в фон: фонового звука в Playgrounds нет — ТЗ 0.2).
    func stop() {
        engine.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func restart() {
        engine.stop()
        start()
    }

    func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        if InputCapture.granted {
            // Доступ к входу дан (S11e, решение пользователя): сессия всегда в режиме записи — REC без перерыва звука,
            // внешние входы видны в меню. Выход — в динамик (или подключённое устройство).
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        } else {
            try session.setCategory(.playback, mode: .default, options: [])
        }
        try session.setPreferredSampleRate(AudioCore.sampleRate)
        try session.setPreferredIOBufferDuration(256.0 / AudioCore.sampleRate)
        try session.setActive(true)
    }

    private func attachSource() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: AudioCore.sampleRate, channels: 2) else { return }
        let core = self.core
        let clock = HostClock()
        let node = AVAudioSourceNode(format: format) { _, timestamp, frameCount, bufferList -> OSStatus in
            let start = mach_absolute_time()
            // Время хоста, когда блок начнёт звучать (без задержки выхода — её добавляет интерфейс).
            let valid: Bool = timestamp.pointee.mFlags.contains(.hostTimeValid)
            let hostTicks: UInt64 = valid ? timestamp.pointee.mHostTime : start
            let host: Double = clock.nanoseconds(hostTicks) / 1e9
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let frames = Int(frameCount)
            if buffers.count >= 2,
               let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
               let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
                core.render(frames: frames, left: left, right: right, host: host)
            }
            let elapsed: UInt64 = mach_absolute_time() - start
            core.cpu.measure(ns: clock.nanoseconds(elapsed), frames: frames)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        source = node
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .ended { start() }
    }

    /// Время хоста сейчас (с) и задержка выхода (с) — для записи нот: что слышно сейчас.
    func hostNow() -> Double {
        return HostClock().now()
    }

    var outputLatency: Double {
        return AVAudioSession.sharedInstance().outputLatency
    }

    /// Фактическое состояние звука — строка «Now:» в DIAGNOSTICS.
    var statusLine: String {
        let s = AVAudioSession.sharedInstance()
        let rate = String(format: "%.1f kHz", s.sampleRate / 1000)
        let buffer = Int((s.ioBufferDuration * s.sampleRate).rounded())
        let latency = String(format: "%.1f ms", s.outputLatency * 1000)
        let state = engine.isRunning ? "running" : "stopped"
        var line = "\(rate) · buffer \(buffer) · output latency \(latency) · \(state)"
        if abs(s.sampleRate - AudioCore.sampleRate) > 1 { line += " (48 kHz requested)" }
        return line
    }
}

/// Перевод тиков mach_absolute_time в наносекунды (без выделений — годится для колбэка).
struct HostClock {
    /// Сейчас, секунды хоста (та же шкала, что host у блока).
    func now() -> Double {
        return nanoseconds(mach_absolute_time()) / 1e9
    }

    private let scale: Double

    init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        scale = Double(info.numer) / Double(info.denom)
    }

    @inline(__always)
    func nanoseconds(_ ticks: UInt64) -> Double {
        return Double(ticks) * scale
    }
}
