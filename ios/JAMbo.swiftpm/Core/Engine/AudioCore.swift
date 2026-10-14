/// Весь звук приложения: один render на блок, вызывается из колбэка AVAudioSourceNode (Audio/AudioHost.swift).
/// В render — только то, что разрешено правилами колбэка (ios/CLAUDE.md): без выделений, блокировок, ARC и print.
public final class AudioCore: @unchecked Sendable {
    /// Частота ядра: всегда 48 кГц (системный микшер приводит к частоте устройства).
    public static let sampleRate: Double = 48000

    /// UI → аудио.
    public let events = SPSCQueue<CoreEvent>(capacity: 1024, filler: .none)
    /// Нагрузка колбэка для индикатора CPU.
    public let cpu = CPUMeter(sampleRate: AudioCore.sampleRate)
    /// Сколько кадров посчитано с запуска (меняет только колбэк; UI читает для диагностики).
    private let frameCounter = AtomicCounter()
    public var framesRendered: Int { return frameCounter.load() }

    private let tone = TestTone(sampleRate: AudioCore.sampleRate)
    /// Счётчик кадров колбэка — основа транспорта с точностью до отсчёта.
    public private(set) var sampleTime: Int64 = 0

    public init() {}

    @inline(__always)
    public func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        while let event = events.pop() {
            apply(event)
        }
        tone.render(frames: frames, left: left, right: right)
        sampleTime += Int64(frames)
        frameCounter.tryStore(Int(sampleTime))
    }

    @inline(__always)
    private func apply(_ event: CoreEvent) {
        switch event {
        case .none:
            break
        case .tone(let on):
            tone.set(on: on)
        case .toneFrequency(let hz):
            tone.set(frequency: Double(hz))
        }
    }
}
