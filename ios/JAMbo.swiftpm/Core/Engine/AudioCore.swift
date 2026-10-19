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
    /// Шины общих эффектов (Reverb, Delay, Drive) и Sidechain.
    public let fx = FxRack(sampleRate: AudioCore.sampleRate)
    /// LFO1–3 и ENV дорожек.
    public let mod = ModEngine(sampleRate: AudioCore.sampleRate)
    /// EQ дорожек (сухой сигнал и посылы).
    public let trackEqs = TrackEqs(sampleRate: AudioCore.sampleRate)
    /// Сдвиги динамических полос EQ для экрана.
    public let eqDyn = EqDynLevels()
    /// Спектры EQ (до и после EQ показанного канала, сравниваемая дорожка, выход мастера).
    public let spectra = Spectra()
    /// Пики дорожек и выхода мастера, приглушение Sidechain, LUFS показанного канала (измеритель и метры MIX).
    public let levels = Levels()
    /// Цепочка мастера (сумма дорожек и FX → EQ → SAT → COMP → CLIP → LIM); тест-тон, метроном и прослушивание — мимо неё,
    /// как в вебе. Без мастера (useMaster false) — тесты, которые сверяют выход по отсчётам.
    public let master = MasterChain(sampleRate: AudioCore.sampleRate)
    private let useMaster: Bool
    private let masterL = UnsafeMutablePointer<Float>.allocate(capacity: AudioCore.maxFrames)
    private let masterR = UnsafeMutablePointer<Float>.allocate(capacity: AudioCore.maxFrames)
    static let maxFrames = 4096
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

    public init(master: Bool = true) {
        useMaster = master
        masterL.initialize(repeating: 0, count: AudioCore.maxFrames)
        masterR.initialize(repeating: 0, count: AudioCore.maxFrames)
        sequencer.sampler = sampler
        sampler.fx = fx
        sampler.mixLockMask = sequencer.mixLockMask
        sampler.mixLockGain = sequencer.mixLockGain
        sampler.mod = mod
        sampler.eqs = trackEqs
        sampler.spectra = spectra
        sampler.levels = levels
        self.master.spectra = spectra
        // Источники T1…T16 динамических полос EQ мастера — выходы дорожек.
        self.master.eq.trackL = sampler.outL
        self.master.eq.trackR = sampler.outR
        self.master.eq.trackStride = Sampler.maxFrames
        sampler.eqDyn = eqDyn
        self.master.eqDyn = eqDyn
        sequencer.mod = mod
    }

    deinit {
        masterL.deallocate()
        masterR.deallocate()
    }

    /// Новые снимки (основной поток, после каждой правки): звук — всегда (дёшево), паттерны — если изменились.
    /// samples — загруженные сэмплы по ключу, map — SLICE NOTES.
    public func publish(_ project: Project, samples: [String: SampleData] = [:], map: SliceMap = .chromatic, octave: Int = 3,
                        tables: [String: WtTable] = [:], scSends: SidechainSends = SidechainSends(),
                        muteTails: Bool = false, levelRelative: Bool = true, master: [Double]? = nil,
                        extra: [String] = []) {
        releaseRetired()
        if lastSeq == nil || !SeqSnapshot.same(lastSeq!, project) {
            lastSeq = project
            let snap = Unmanaged.passRetained(SeqSnapshot(project))
            if !snapshots.push(snap) { snap.release() }
        }
        let snd = Unmanaged.passRetained(SoundSnapshot(project, samples: samples, map: map, octave: octave, tables: tables,
                                                             scSends: scSends, muteTails: muteTails,
                                                             levelRelative: levelRelative,
                                                             slots: sequencer.launcher.slot, master: master,
                                                             extra: extra))
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
        // FX на блок: значения клипа с p-lock играющих шагов, источник Sidechain.
        if let d = sampler.sound {
            mod.begin(d, frames: frames, lockMask: sequencer.modLockMask, lockVal: sequencer.modLockVal)
            fx.begin(d, lockMask: sequencer.fxLockMask, lockVal: sequencer.fxLockVal, mod: mod, frame: sampleTime)
        }
        sampler.bpm = sequencer.bpm
        while let event = events.pop() {
            apply(event)
        }
        left.update(repeating: 0, count: frames)
        right.update(repeating: 0, count: frames)
        tone.render(frames: frames, left: left, right: right)
        sequencer.process(blockStart: sampleTime, frames: frames, left: left, right: right, host: host)
        renderMix(frames, left, right)
        mod.publish(frame: sampleTime + Int64(frames))
        sampleTime += Int64(frames)
        frameCounter.store(Int(sampleTime))
    }

    /// Дорожки и FX → мастер → выход (к тону и метроному); затем прослушивание (мимо мастера).
    @inline(__always)
    private func renderMix(_ frames: Int, _ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>) {
        guard let d = sampler.sound else { return }
        let n = Swift.min(frames, AudioCore.maxFrames)
        _ = levels.begin()
        defer { levels.commit(frames: n) }
        if useMaster {
            masterL.update(repeating: 0, count: n)
            masterR.update(repeating: 0, count: n)
            sampler.render(blockStart: sampleTime, frames: n, left: masterL, right: masterR)
            master.process(left: masterL, right: masterR, frames: n, params: d.master,
                           eqParams: d.eq + EqSpec.masterChannel * EqSpec.stride)
            // Конечный выход мастера (после громкости выхода).
            if spectra.outOn.load() != 0 { spectra.out.push(masterL, masterR, n) }
            meterMaster(n)
            master.scope.gonio(masterL, masterR, n)
            var i = 0
            while i < n {
                left[i] += masterL[i]
                right[i] += masterR[i]
                i += 1
            }
        } else {
            sampler.render(blockStart: sampleTime, frames: n, left: left, right: right)
        }
        sampler.renderPreview(n, left, right)
    }

    /// Пики выхода мастера в блоке и его громкость, если измеритель показывает мастер.
    @inline(__always)
    private func meterMaster(_ n: Int) {
        let l = masterL, r = masterR
        var pl: Float = 0, pr: Float = 0
        var i = 0
        while i < n {
            let al: Float = l[i] < 0 ? -l[i] : l[i]
            let ar: Float = r[i] < 0 ? -r[i] : r[i]
            if al > pl { pl = al }
            if ar > pr { pr = ar }
            i += 1
        }
        let m = levels.current(Levels.master)
        m[0] = pl
        m[1] = pr
        if levels.loudness.listens(Levels.master) { levels.loudness.process(UnsafePointer(l), UnsafePointer(r), n) }
    }

    @inline(__always)
    private func takeSnapshots() {
        while let item = synthQueue.pop() {
            guard let s = item else { continue }
            let v = s.takeRetainedValue()
            v.mod = mod
            sampler.synth = v
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
            // Стоп: будущие триги Sidechain отменяются.
            if !on { fx.flush() }
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
            mod.liveOn(track: t, at: sampleTime)
            sampler.noteOn(track: t, note: n, liveId: id, velocity: v, at: sampleTime)
        case .noteOff(let t, let id):
            mod.liveOff(track: t, at: sampleTime)
            sampler.release(track: t, liveId: id, at: sampleTime)
        case .preview(let h, let a, let b):
            sampler.preview(hash: h, a: a, b: b, at: sampleTime)
        case .previewStop:
            sampler.stopPreview()
        case .presetNote(let t, let n, let h, let locks):
            sampler.presetNote(track: t, note: n, hash: h, locks: locks, at: sampleTime)
        }
    }
}
