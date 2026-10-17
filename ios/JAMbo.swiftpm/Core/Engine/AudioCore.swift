import Foundation

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
    public let sampler = Sampler(sampleRate: AudioCore.sampleRate)
    /// Снимки паттернов и звука: новые — в колбэк, прежние — обратно (освобождаются в основном потоке не раньше
    /// чем через keepAlive с: голоса, которые гаснут, ещё читают их сэмплы).
    private let snapshots = SPSCQueue<Unmanaged<SeqSnapshot>?>(capacity: 64, filler: nil)
    private let retired = SPSCQueue<Unmanaged<SeqSnapshot>?>(capacity: 256, filler: nil)
    private var current: Unmanaged<SeqSnapshot>?
    private let sounds = SPSCQueue<Unmanaged<SoundSnapshot>?>(capacity: 256, filler: nil)
    private let retiredSounds = SPSCQueue<Unmanaged<SoundSnapshot>?>(capacity: 512, filler: nil)
    private var currentSound: Unmanaged<SoundSnapshot>?
    private var waiting: [(time: Double, seq: Unmanaged<SeqSnapshot>?, sound: Unmanaged<SoundSnapshot>?)] = []
    public static let keepAlive: Double = 0.5
    /// Последний снимок паттернов строится заново, только если изменилось то, что в него входит.
    private var lastSeq: Project?

    /// Голоса синта: создаются в основном потоке (installSynth), колбэк забирает их один раз.
    private let synthQueue = SPSCQueue<Unmanaged<SynthVoices>?>(capacity: 2, filler: nil)
    private var synthInstalled = false

    private let tone = TestTone(sampleRate: AudioCore.sampleRate)
    /// Счётчик кадров колбэка — основа транспорта с точностью до отсчёта.
    public private(set) var sampleTime: Int64 = 0

    public init() {
        sequencer.sampler = sampler
    }

    /// Новые снимки (основной поток, после каждой правки): звук — всегда (дёшево), паттерны — если изменились.
    /// samples — загруженные сэмплы по ключу, map — SLICE NOTES.
    public func publish(_ project: Project, samples: [String: SampleData] = [:], map: SliceMap = .chromatic, octave: Int = 3,
                        tables: [String: WtTable] = [:]) {
        releaseRetired()
        if lastSeq == nil || !SeqSnapshot.same(lastSeq!, project) {
            lastSeq = project
            let snap = Unmanaged.passRetained(SeqSnapshot(project))
            if !snapshots.push(snap) { snap.release() }
        }
        let snd = Unmanaged.passRetained(SoundSnapshot(project, samples: samples, map: map, octave: octave, tables: tables))
        if !sounds.push(snd) { snd.release() }
    }

    /// Голоса синта Plaits (основной поток, один раз; таблицы — Resources/plaits). Повторный вызов ничего не делает:
    /// прежние голоса освобождались бы в колбэке.
    public func installSynth(_ resources: PlaitsResources) {
        if synthInstalled { return }
        synthInstalled = true
        let s = Unmanaged.passRetained(SynthVoices(resources: resources, sampleRate: AudioCore.sampleRate))
        if !synthQueue.push(s) { s.release() }
    }

    /// Освободить снимки, которые колбэк больше не использует (основной поток; now — секунды, для задержки).
    public func releaseRetired(now: Double = Date.timeIntervalSinceReferenceDate) {
        while let item = retired.pop() { waiting.append((now, item, nil)) }
        while let item = retiredSounds.pop() { waiting.append((now, nil, item)) }
        var k = 0
        while k < waiting.count {
            if now - waiting[k].time >= AudioCore.keepAlive {
                waiting[k].seq?.release()
                waiting[k].sound?.release()
                waiting.remove(at: k)
            } else {
                k += 1
            }
        }
    }

    @inline(__always)
    /// host — время хоста (с), когда этот блок начнёт звучать (для записи нот с REC); в тестах 0.
    public func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, host: Double = 0) {
        // Сначала снимок проекта, потом команды: PLAY сразу после правки видит новые клипы и строки.
        takeSnapshots()
        while let event = events.pop() {
            apply(event)
        }
        left.update(repeating: 0, count: frames)
        right.update(repeating: 0, count: frames)
        tone.render(frames: frames, left: left, right: right)
        sequencer.process(blockStart: sampleTime, frames: frames, left: left, right: right, host: host)
        sampler.render(blockStart: sampleTime, frames: frames, left: left, right: right)
        sampleTime += Int64(frames)
        frameCounter.store(Int(sampleTime))
    }

    @inline(__always)
    private func takeSnapshots() {
        while let item = synthQueue.pop() {
            guard let s = item else { continue }
            sampler.synth = s.takeRetainedValue()
        }
        while let item = snapshots.pop() {
            guard let snap = item else { continue }
            if let old = current { _ = retired.push(old) }
            current = snap
            sequencer.data = snap._withUnsafeGuaranteedRef { $0.data }
        }
        while let item = sounds.pop() {
            guard let snap = item else { continue }
            if let old = currentSound { _ = retiredSounds.push(old) }
            currentSound = snap
            sampler.adopt(snap._withUnsafeGuaranteedRef { $0.data }, now: sampleTime)
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
        case .launch(let t, let k):
            sequencer.queue(track: t, slot: k)
        case .scene(let row, let atPass):
            sequencer.queueScene(row, atPass: atPass)
        case .adoptPlay:
            sequencer.adoptPlay()
        case .noteOn(let t, let n, let id, let v):
            sampler.noteOn(track: t, note: n, liveId: id, velocity: v, at: sampleTime)
        case .noteOff(let t, let id):
            sampler.release(track: t, liveId: id, at: sampleTime)
        case .preview(let h, let a, let b):
            sampler.preview(hash: h, a: a, b: b, at: sampleTime)
        case .previewStop:
            sampler.stopPreview()
        }
    }
}
