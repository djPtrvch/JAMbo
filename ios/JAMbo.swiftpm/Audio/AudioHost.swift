import AVFoundation
import Foundation

/// Аудиосессия 48 кГц и один AVAudioSourceNode, в колбэке которого считается весь звук (AudioCore.render).
final class AudioHost {
    let core = AudioCore()
    let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var observers: [NSObjectProtocol] = []
    private var restartWork: DispatchWorkItem? = nil
    /// Счёт перезапусков движка: звук стоял — шаги секвенсора отстали от MIDI-клока (привязать заново).
    private(set) var restarts: Int = 0
    private var latency: Double = -1
    /// Диагностика тормозов с USB-аудио (строка «Now:»): смены маршрута; прошлый замер скорости колбэка.
    private(set) var routeChanges: Int = 0
    private var rateHost: Double = 0
    private var rateFrames: Int = 0
    private var speed: Double = 0
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
            self?.scheduleRestart()
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] _ in
            self?.routeChanges += 1
            self?.refreshLatency()
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
            refreshLatency()
            trace("audio: running")
            lastError = ""
        } catch {
            lastError = error.localizedDescription
            trace("audio error: \(lastError)")
        }
    }

    /// Остановка (уход в фон при выключенном BACKGROUND AUDIO).
    func stop() {
        engine.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Смена конфигурации (подключили или отключили USB-аудио — Digitakt и т. п., наушники): уведомления приходят
    /// пачкой, и перезапуск на каждое останавливал звук несколько раз подряд (секвенсор тормозил, экран замирал).
    /// Перезапуск — один, через 0,3 с после последнего уведомления.
    private func scheduleRestart() {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.restart() }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Только движок: сессия уже настроена (категория и частота те же). Не запустился — полная настройка.
    func restart() {
        restartWork = nil
        restarts += 1
        engine.stop()
        do {
            if source == nil { attachSource() }
            try engine.start()
            refreshLatency()
            lastError = ""
        } catch {
            start()
        }
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

    /// Задержка выхода для расчётов (клок, MIDI OUT, запись нот) — запомненная при запуске звука и смене маршрута:
    /// система с USB-аудио (Digitakt) отдаёт то 1, то 11 мс, и моменты шагов дёргались бы на каждом кадре.
    var outputLatency: Double {
        if latency < 0 { latency = AVAudioSession.sharedInstance().outputLatency }
        return latency
    }

    /// Перечитать задержку выхода (маршрут сменился или звук перезапущен).
    private func refreshLatency() {
        latency = AVAudioSession.sharedInstance().outputLatency
    }

    /// Скорость колбэка: отсчётов за время с прошлого замера к 48 000 в секунду, % (100 — звук идёт вовремя; меньше —
    /// колбэк зовут реже, секвенсор тормозит). Замер не чаще раза в 0,4 с.
    private func renderSpeed() -> Int {
        let now: Double = HostClock().now()
        let frames: Int = core.framesRendered
        if rateHost > 0 && now - rateHost >= 0.4 {
            speed = Double(frames - rateFrames) / (now - rateHost) / AudioCore.sampleRate
        }
        if rateHost == 0 || now - rateHost >= 0.4 {
            rateHost = now
            rateFrames = frames
        }
        return Int((speed * 100).rounded())
    }

    /// Фактическое состояние звука — строка «Now:» в DIAGNOSTICS.
    var statusLine: String {
        let s = AVAudioSession.sharedInstance()
        let rate = String(format: "%.1f kHz", s.sampleRate / 1000)
        let buffer = Int((s.ioBufferDuration * s.sampleRate).rounded())
        // Сейчас у системы и (в скобках, если другая) — по которой считаются клок и MIDI OUT.
        var lat = String(format: "%.1f ms", s.outputLatency * 1000)
        let used: Double = outputLatency
        if abs(used - s.outputLatency) > 0.0005 { lat += String(format: " (using %.1f ms)", used * 1000) }
        let state = engine.isRunning ? "running" : "stopped"
        var line = "\(rate) · buffer \(buffer) · output latency \(lat) · \(state)"
        if abs(s.sampleRate - AudioCore.sampleRate) > 1 { line += " (48 kHz requested)" }
        let out: String = s.currentRoute.outputs.map { $0.portName }.joined(separator: ", ")
        let inp: String = s.currentRoute.inputs.map { $0.portName }.joined(separator: ", ")
        line += " · out: \(out.isEmpty ? "-" : out) · in: \(inp.isEmpty ? "-" : inp)"
        line += " · restarts \(restarts) · route changes \(routeChanges) · audio speed \(renderSpeed())%"
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

    /// Секунды хоста → такты mach (метки времени CoreMIDI); прошлое — 0 (сразу).
    func ticks(seconds: Double) -> UInt64 {
        let t: Double = seconds * 1e9 / scale
        return t > 0 ? UInt64(t) : 0
    }
}
