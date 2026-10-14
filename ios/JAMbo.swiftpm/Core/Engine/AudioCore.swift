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

    public let sequencer = Sequencer(sampleRate: AudioCore.sampleRate, bpm: 120)
    /// Снимки паттернов: новые — в колбэк, прежние — обратно (освобождаются в основном потоке).
    private let snapshots = SPSCQueue<Unmanaged<SeqSnapshot>?>(capacity: 64, filler: nil)
    private let retired = SPSCQueue<Unmanaged<SeqSnapshot>?>(capacity: 256, filler: nil)
    private var current: Unmanaged<SeqSnapshot>?

    private let tone = TestTone(sampleRate: AudioCore.sampleRate)
    /// Счётчик кадров колбэка — основа транспорта с точностью до отсчёта.
    public private(set) var sampleTime: Int64 = 0

    public init() {}

    /// Новый снимок паттернов (основной поток, после каждой правки).
    public func publish(_ project: Project) {
        releaseRetired()
        let snap = Unmanaged.passRetained(SeqSnapshot(project))
        if !snapshots.push(snap) { snap.release() }
    }

    /// Освободить снимки, которые колбэк больше не использует (основной поток).
    public func releaseRetired() {
        while let item = retired.pop() {
            item?.release()
        }
    }

    @inline(__always)
    public func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        while let event = events.pop() {
            apply(event)
        }
        takeSnapshots()
        left.update(repeating: 0, count: frames)
        right.update(repeating: 0, count: frames)
        tone.render(frames: frames, left: left, right: right)
        sequencer.process(blockStart: sampleTime, frames: frames, left: left, right: right)
        sampleTime += Int64(frames)
        frameCounter.store(Int(sampleTime))
    }

    @inline(__always)
    private func takeSnapshots() {
        while let item = snapshots.pop() {
            guard let snap = item else { continue }
            if let old = current { _ = retired.push(old) }
            current = snap
            sequencer.data = snap._withUnsafeGuaranteedRef { $0.data }
        }
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
        case .play(let on):
            sequencer.set(playing: on, at: sampleTime)
        case .tempo(let bpm):
            sequencer.set(bpm: bpm)
        case .metronome(let on):
            sequencer.metronome = on
        }
    }
}
