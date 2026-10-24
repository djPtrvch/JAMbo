import XCTest
@testable import Core

final class SamplerTests: XCTestCase {
    /// Прогнать ядро: выход L и R.
    private func render(_ core: AudioCore, frames: Int) -> (l: [Float], r: [Float]) {
        var l = [Float](repeating: 0, count: frames)
        var r = [Float](repeating: 0, count: frames)
        var pos = 0
        var bl = [Float](repeating: 0, count: 256)
        var br = [Float](repeating: 0, count: 256)
        while pos < frames {
            let n = min(256, frames - pos)
            core.render(frames: n, left: &bl, right: &br)
            for i in 0..<n {
                l[pos + i] = bl[i]
                r[pos + i] = br[i]
            }
            pos += n
        }
        return (l, r)
    }

    /// Постоянный сигнал 1.0 (моно), 1 с.
    private func dc(_ frames: Int = 48000) -> SampleData {
        return SampleData(left: [Float](repeating: 1, count: frames), right: nil)
    }

    private func project(_ key: String = "k") -> Project {
        var p = Project()
        p.tracks[0].addSamples([key])
        p.tracks[0].vol = 0
        return p
    }

    private let center: Float = Float(cos(Double.pi / 4))

    func testOneStepNoteAttackAndDecay() {
        let core = AudioCore(master: false)
        var p = project()
        p.tracks[0].pages[0][0].on = true
        p.tracks[0].pages[0][0].notes = [48]
        core.publish(p, samples: ["k": dc()])
        core.events.push(.play(true))
        let o = render(core, frames: 20000)
        // Атака 1 мс (48 кадров), затем Decay 500 мс как Release: τ = 125 мс (6000 кадров).
        XCTAssertEqual(o.l[24], center * 0.5, accuracy: 0.02, "середина атаки")
        XCTAssertEqual(o.l[48], center, accuracy: 0.01, "моно по центру — cos(π/4) в каждый канал")
        XCTAssertEqual(o.l[48 + 6000], center * Float(exp(-1.0)), accuracy: 0.01)
        XCTAssertEqual(o.l[100], o.r[100], accuracy: 1e-6)
    }

    /// MIDI OUT дорожки: свой звук молчит, ноты шага и живые — в очередь midiOut (длина, velocity — Level);
    /// заглушённая дорожка молчит и в MIDI; стоп — «всё отпустить».
    func testMidiOutTrackSendsNotesInsteadOfSound() {
        let core = AudioCore(master: false)
        var p = project()
        p.tracks[0].midi.outDevice = 5
        p.tracks[0].pages[0][0].on = true
        p.tracks[0].pages[0][0].notes = [48]
        p.tracks[0].pages[0][0].len = 2
        core.publish(p, samples: ["k": dc()])
        core.events.push(.play(true))
        let o = render(core, frames: 2000)
        XCTAssertLessThan(o.l.map { abs($0) }.max() ?? 1, 1e-6, "свой звук молчит")
        let e = core.sampler.midiOut.pop()
        XCTAssertEqual(e?.kind, MidiNoteOut.on)
        XCTAssertEqual(e?.note, 48)
        XCTAssertEqual(e?.frame, 0)
        // 2 шага на 120 BPM — 12000 кадров; velocity — Level дорожки по умолчанию.
        XCTAssertEqual(e?.length, 12000)
        XCTAssertEqual(Double(e?.velocity ?? 0), Params.byId["level"]?.def ?? -1, accuracy: 0.5)
        core.events.push(.noteOn(track: 0, note: 60, id: 9, velocity: 0.5))
        core.events.push(.noteOff(track: 0, id: 9))
        core.events.push(.play(false))
        _ = render(core, frames: 256)
        var kinds: [UInt8] = []
        var live: MidiNoteOut? = nil
        while let x = core.sampler.midiOut.pop() {
            kinds.append(x.kind)
            if x.kind == MidiNoteOut.on { live = x }
        }
        XCTAssertEqual(kinds, [MidiNoteOut.on, MidiNoteOut.release, MidiNoteOut.allOff])
        XCTAssertEqual(live?.length, -1)
        XCTAssertEqual(live?.liveId, 9)
        p.tracks[0].mute = true
        core.publish(p, samples: ["k": dc()])
        core.events.push(.noteOn(track: 0, note: 60, id: 10, velocity: 1))
        _ = render(core, frames: 256)
        XCTAssertNil(core.sampler.midiOut.pop(), "заглушённая дорожка молчит и в MIDI")
    }

    func testLiveNoteHoldsUntilRelease() {
        let core = AudioCore(master: false)
        core.publish(project(), samples: ["k": dc()])
        core.events.push(.noteOn(track: 0, note: 48, id: 7, velocity: 1))
        var o = render(core, frames: 12000)
        XCTAssertEqual(o.l[11000], center, accuracy: 0.01, "живая нота держит уровень")
        core.events.push(.noteOff(track: 0, id: 7))
        o = render(core, frames: 6000)
        XCTAssertEqual(o.l[5999], center * Float(exp(-1.0)), accuracy: 0.02, "отпустили — Decay как Release")
    }

    func testPitchStartEndAndVolume() {
        let core = AudioCore(master: false)
        var p = project()
        p.tracks[0].params["start"] = 50
        p.tracks[0].params["decay"] = 4000
        p.tracks[0].vol = -10
        core.publish(p, samples: ["k": dc()])
        // Октава вверх — вдвое быстрее: половина сэмпла (24000) за 12000 кадров.
        core.events.push(.noteOn(track: 0, note: 60, id: 1, velocity: 1))
        let o = render(core, frames: 14000)
        let g: Float = center * Float(pow(10.0, -10.0 / 20))
        XCTAssertEqual(o.l[6000], g, accuracy: 0.005, "громкость микшера −10 dB")
        XCTAssertEqual(o.l[11999 - 300], g, accuracy: 0.01)
        XCTAssertEqual(o.l[12500], 0, accuracy: 1e-6, "конец сэмпла — голос замолчал")
        XCTAssertLessThan(abs(o.l[11998]), g * 0.2, "край гаснет за 4 мс")
        XCTAssertEqual(core.sampler.activeCount, 0)
    }

    func testVelocityLevelAndPan() {
        let core = AudioCore(master: false)
        var p = project()
        p.tracks[0].params["pan"] = 64
        core.publish(p, samples: ["k": dc()])
        core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 0.5))
        let o = render(core, frames: 2000)
        // Level = (0.5)^1.5; панорама вправо до упора.
        XCTAssertEqual(o.r[1000], Float(pow(0.5, 1.5)), accuracy: 0.01)
        XCTAssertEqual(o.l[1000], 0, accuracy: 0.001)
    }

    func testMuteGateClosesFast() {
        let core = AudioCore(master: false)
        var p = project()
        let s = dc()
        core.publish(p, samples: ["k": s])
        core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        _ = render(core, frames: 2048)
        p.tracks[0].mute = true
        core.publish(p, samples: ["k": s])
        let o = render(core, frames: 1024)
        XCTAssertLessThan(abs(o.l[480]), 0.001, "гейт закрыт за 10 мс")
        XCTAssertGreaterThan(abs(o.l[0]), 0.3, "без щелчка: гаснет плавно")
        XCTAssertEqual(core.sampler.activeCount, 1, "нота играет дальше")
    }

    func testSlicesPlayMarkedPart() {
        let core = AudioCore(master: false)
        var p = project()
        // Первая половина — 0.5, вторая — 1.0.
        var l = [Float](repeating: 0.5, count: 48000)
        for i in 24000..<48000 { l[i] = 1 }
        p.tracks[0].addSlice("k", at: 0)
        p.tracks[0].addSlice("k", at: 0.5)
        p.tracks[0].params["decay"] = 4000
        core.publish(p, samples: ["k": SampleData(left: l, right: nil)])
        // Маркер 2 — нота C#3 (CHROMATIC), играет вторую половину в исходной высоте.
        core.events.push(.noteOn(track: 0, note: 49, id: 1, velocity: 1))
        core.events.push(.noteOn(track: 0, note: 60, id: 2, velocity: 1))
        let o = render(core, frames: 30000)
        XCTAssertEqual(o.l[1000], center, accuracy: 0.01, "вторая половина; нота без маркера молчит")
        XCTAssertEqual(o.l[25000], 0, accuracy: 1e-6, "до конца сэмпла — 24000 кадров")
        XCTAssertEqual(Slices.notes([SliceMark(at: 0), SliceMark(at: 0.5, note: 48), SliceMark(at: 0.7)], map: .chromatic, scale: 0, root: 0),
                       [49, 48, 51], "назначенная нота занимает своё место по порядку (как sliceNotes веба)")
        XCTAssertEqual(Slices.notes([SliceMark(at: 0), SliceMark(at: 0.3), SliceMark(at: 0.6)], map: .scale, scale: 1, root: 2),
                       [50, 52, 53], "SCALE: ступени минора от D3")
        // От первой клавиши пианоролла: октава 2 — C2, C#2…; SCALE — клавиши по порядку.
        XCTAssertEqual(Slices.notes([SliceMark(at: 0), SliceMark(at: 0.5)], map: .chromatic, scale: 0, root: 0, octave: 2), [36, 37])
        XCTAssertEqual(Slices.notes([SliceMark(at: 0), SliceMark(at: 0.5)], map: .scale, scale: 0, root: 0, octave: 4), [60, 62])
    }

    func testVoiceLimitFadesOldest() {
        let core = AudioCore(master: false)
        core.publish(project(), samples: ["k": dc()])
        for k in 0..<60 { core.events.push(.noteOn(track: 0, note: 48 + k % 12, id: k, velocity: 1)) }
        _ = render(core, frames: 256)
        XCTAssertLessThanOrEqual(core.sampler.activeCount, 64)
        _ = render(core, frames: 2048)
        XCTAssertEqual(core.sampler.activeCount, Sampler.maxVoices, "лишние погасли")
    }

    func testSoundChangeRetriggersHeldNote() {
        let core = AudioCore(master: false)
        var p = project()
        p.tracks[0].addItems(["k2"])
        p.tracks[0].sample = "k"
        let half = SampleData(left: [Float](repeating: 0.5, count: 48000), right: nil)
        let samples = ["k": dc(), "k2": half]
        core.publish(p, samples: samples)
        core.events.push(.noteOn(track: 0, note: 48, id: 3, velocity: 1))
        _ = render(core, frames: 4000)
        p.tracks[0].sample = "k2"
        core.publish(p, samples: samples)
        let o = render(core, frames: 4000)
        XCTAssertEqual(o.l[3000], center * 0.5, accuracy: 0.01, "держащаяся нота звучит новым звуком")
        XCTAssertEqual(core.sampler.activeCount, 1, "один новый голос (прежний погас)")
        core.events.push(.noteOff(track: 0, id: 3))
        _ = render(core, frames: 48000)
        XCTAssertEqual(core.sampler.activeCount, 0, "отпускание действует и на новый голос")
    }

    func testSequencerPlaysStepWithLockAndHold() {
        let core = AudioCore(master: false)
        var p = project()
        p.tracks[0].pages[0][0].on = true
        p.tracks[0].pages[0][0].notes = [48]
        p.tracks[0].pages[0][0].len = 2
        p.tracks[0].pages[0][0].locks["level"] = 127 * pow(0.25, 1 / 1.5)
        core.publish(p, samples: ["k": dc(96000)])
        core.events.push(.play(true))
        let o = render(core, frames: 13000)
        // Шаг 0 в кадре 0, p-lock Level — 0.25; длина 2 шага (12000 кадров) — уровень держится.
        XCTAssertEqual(o.l[100], center * 0.25, accuracy: 0.005)
        XCTAssertEqual(o.l[11900], center * 0.25, accuracy: 0.005)
        XCTAssertLessThan(o.l[12999], center * 0.25 * 0.995, "после удержания — Decay")
    }

    func testStepSoundPlaysOwnSample() {
        let core = AudioCore(master: false)
        var p = project()
        p.tracks[0].addSamplesQuiet(["k2"])
        p.tracks[0].pages[0][0].on = true
        p.tracks[0].pages[0][0].notes = [48]
        p.tracks[0].setStepSound([0], "k2")
        XCTAssertEqual(p.tracks[0].sample, "k")
        let half = SampleData(left: [Float](repeating: 0.5, count: 48000), right: nil)
        core.publish(p, samples: ["k": dc(), "k2": half])
        core.events.push(.play(true))
        let o = render(core, frames: 1000)
        XCTAssertEqual(o.l[48], center * 0.5, accuracy: 0.01)
    }

    func testFilterLowpassAndHighpass() {
        var b = Biquad()
        b.set(type: -1, hz: 1000, qDb: 0, sampleRate: 48000)
        XCTAssertEqual(b.b0 + b.b1 + b.b2, 1 + b.a1 + b.a2, accuracy: 1e-5, "LP: на постоянном токе 0 dB")
        b.set(type: 1, hz: 1000, qDb: 0, sampleRate: 48000)
        XCTAssertEqual(b.b0 + b.b1 + b.b2, 0, accuracy: 1e-6, "HP: постоянный ток не проходит")
        let k = Biquad.knob(-100, reso: 0)
        XCTAssertEqual(k.hz, 30, accuracy: 0.01)
        XCTAssertEqual(Biquad.knob(0, reso: 100).q, 18.7, accuracy: 1e-9)
    }

    func testEditsAndPitch() {
        var l = [Float](repeating: 0, count: 48000)
        var r = [Float](repeating: 0, count: 48000)
        for i in 0..<48000 {
            l[i] = 0.25 * Float(sin(2 * Double.pi * 220 * Double(i) / 48000))
            r[i] = -l[i] * 0.5
        }
        let s = SampleData(left: l, right: r)
        XCTAssertEqual(PitchDetect.root(s), 57, "220 Hz — A3")
        let t = SampleEdit.trim(s, 0.25, 0.75)
        XCTAssertEqual(t.frames, 24000)
        XCTAssertEqual(t.left[0], s.left[12000])
        let n = SampleEdit.normalize(s)
        var peak: Float = 0
        for i in 0..<n.frames { peak = max(peak, abs(n.left[i])) }
        XCTAssertEqual(peak, Float(pow(10.0, -0.1 / 20)), accuracy: 1e-4)
        let m = SampleEdit.mono(s)
        XCTAssertEqual(m.channels, 1)
        XCTAssertEqual(m.left[100], (s.left[100] + s.right[100]) / 2, accuracy: 1e-7)
        XCTAssertNil(PitchDetect.root(SampleData(left: (0..<48000).map { _ in Float.random(in: -0.5...0.5) }, right: nil)), "шум — без высоты")
    }

    /// Короткий сэмпл (0,1 с) и высокие ноты (C7, пила с обертонами выше 12 кГц) — нота определяется; короткий шум — нет.
    func testPitchShortAndHigh() {
        func tone(_ midi: Int, _ sec: Double, saw: Bool) -> SampleData {
            let f: Double = 440 * pow(2, Double(midi - 69) / 12)
            let x: [Float] = (0..<Int(sec * 48000)).map { i in
                let t = Double(i) / 48000
                var v: Double = 0
                for h in 1...(saw ? 12 : 1) { v += sin(2 * Double.pi * f * Double(h) * t) / Double(h) }
                return Float(0.4 * v * exp(-t / (sec / 2)))
            }
            return SampleData(left: x, right: nil)
        }
        XCTAssertEqual(PitchDetect.root(tone(48, 0.1, saw: false)), 48)
        XCTAssertEqual(PitchDetect.root(tone(64, 0.1, saw: true)), 64)
        XCTAssertEqual(PitchDetect.root(tone(91, 1, saw: true)), 91)
        XCTAssertEqual(PitchDetect.root(tone(96, 1, saw: true)), 96)
        XCTAssertNil(PitchDetect.root(SampleData(left: (0..<4800).map { _ in Float.random(in: -0.5...0.5) }, right: nil)))
    }

    func testFolderPagesAndTracks() {
        var t = Track(index: 0)
        t.addSamples(["a", "b"])
        XCTAssertEqual(t.sample, "a")
        t.stepFolder(1)
        XCTAssertEqual(t.sample, "b")
        t.stepFolder(1)
        XCTAssertEqual(t.sample, "a")
        t.pages[0][3].on = true
        t.stepFolderOnSteps([3], 1)
        XCTAssertEqual(t.pages[0][3].sound, "b")
        XCTAssertEqual(t.folderPos(held: 3).0, 2)
        t.replaceSample("a", "a2")
        XCTAssertEqual(t.folder.items, ["a2", "b"])
        t.clearSample()
        XCTAssertEqual(t.sample, "")
        XCTAssertEqual(t.folder.items, ["b"])
        // Перенос страницы: обводка одной перенесённой идёт за ней.
        t.addPage()
        t.addPage()
        t.pages[0][0].notes = [99]
        t.setPlayPages(0, 0)
        t.movePage(0, 2)
        XCTAssertEqual(t.pages[2][0].notes, [99])
        XCTAssertEqual(t.playFrom, 2)
        t.setPlayPages(0, 1)
        t.movePage(2, 0)
        XCTAssertEqual(t.pages[0][0].notes, [99])
        XCTAssertEqual(t.playTo, 1, "обводка нескольких — на месте")
        var p = Project()
        p.addTrack()
        XCTAssertEqual(p.tracks.count, 9)
        XCTAssertEqual(p.tracks[8].name, "9")
        p.tracks[8].name = "Bass"
        p.moveTrack(8, 0)
        XCTAssertEqual(p.tracks[0].name, "Bass")
        XCTAssertEqual(p.tracks[1].name, "1")
        let copy = p.tracks[0]
        p.tracks[3].mute = true
        p.pasteTrack(3, copy)
        XCTAssertEqual(p.tracks[3].name, "3", "имя — своё")
        XCTAssertTrue(p.tracks[3].mute, "mute — свой")
        XCTAssertTrue(p.canDeleteTrack(0))
        p.deleteTrack(0)
        XCTAssertFalse(p.canDeleteTrack(0), "меньше 8 нельзя")
    }

    func testPreviewPlaysAndStops() {
        let core = AudioCore(master: false)
        core.publish(project(), samples: ["k": dc()])
        core.events.push(.preview(hash: SoundKey.hash("k"), a: 0, b: 1))
        var o = render(core, frames: 1000)
        XCTAssertEqual(o.l[500], Sampler.previewGain, accuracy: 1e-5)
        core.events.push(.previewStop)
        o = render(core, frames: 4000)
        XCTAssertLessThan(abs(o.l[3999]), 0.001)
        XCTAssertFalse(core.sampler.previewing)
    }
}

final class SamplerLoadTests: XCTestCase {
    /// Нагрузка: 48 стерео-голосов с фильтром и сменой высоты, 2 с звука.
    func testLoad48Voices() {
        let core = AudioCore(master: false)
        var p = Project()
        let l = (0..<480000).map { Float(sin(Double($0) * 0.05)) }
        let s = SampleData(left: l, right: l)
        p.tracks[0].addSamples(["k"])
        p.tracks[0].params["filter"] = -40
        p.tracks[0].params["reso"] = 30
        p.tracks[0].params["decay"] = 4000
        core.publish(p, samples: ["k": s])
        for k in 0..<48 { core.events.push(.noteOn(track: 0, note: 36 + k % 24, id: k, velocity: 1)) }
        var bl = [Float](repeating: 0, count: 256)
        var br = [Float](repeating: 0, count: 256)
        let t0 = Date()
        for _ in 0..<375 { core.render(frames: 256, left: &bl, right: &br) }
        let sec = Date().timeIntervalSince(t0)
        print("SAMPLER LOAD: 48 voices, 2 s of audio in \(String(format: "%.3f", sec)) s — \(String(format: "%.1f", sec / 2 * 100)) % of one core")
        XCTAssertEqual(core.sampler.activeCount, 48)
    }
}
