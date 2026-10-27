import XCTest
@testable import Core

/// RATE сэмпла (1.4): PTCH — скорость со сменой высоты, реверс левее центра; TSTR — таймстретч (высота прежняя,
/// скорость — темп проекта к темпу файла и RATE).
final class RateTests: XCTestCase {
    private func render(_ core: AudioCore, frames: Int) -> [Float] {
        var l = [Float](repeating: 0, count: frames)
        var pos = 0
        var bl = [Float](repeating: 0, count: 256)
        var br = [Float](repeating: 0, count: 256)
        while pos < frames {
            let n = min(256, frames - pos)
            core.render(frames: n, left: &bl, right: &br)
            for i in 0..<n { l[pos + i] = bl[i] }
            pos += n
        }
        return l
    }

    private func project(rate: Double, tstr: Bool, bpm: Double = 120, beat: Bool = false) -> Project {
        var p = Project()
        p.tracks[0].addSamples(["k"])
        p.tracks[0].vol = 0
        p.tracks[0].params["decay"] = 4000
        p.tracks[0].params["rate"] = rate
        p.tracks[0].params[Params.rateModeId] = tstr ? 1 : 0
        p.tracks[0].params[Params.stretchBeatId] = beat ? 1 : 0
        p.bpm = bpm
        return p
    }

    private func sine(_ hz: Double, seconds: Double) -> SampleData {
        let n = Int(seconds * 48000)
        return SampleData(left: (0..<n).map { Float(0.5 * sin(2 * Double.pi * hz * Double($0) / 48000)) }, right: nil)
    }

    /// Положительных переходов через ноль на отрезке.
    private func crossings(_ x: [Float], _ from: Int, _ count: Int) -> Int {
        var c = 0
        for i in from + 1..<from + count where x[i - 1] < 0 && x[i] >= 0 { c += 1 }
        return c
    }

    private func rms(_ x: [Float], _ from: Int, _ count: Int) -> Float {
        var s: Float = 0
        for i in from..<from + count { s += x[i] * x[i] }
        return (s / Float(count)).squareRoot()
    }

    /// Последний слышный отсчёт.
    private func lastSound(_ x: [Float]) -> Int {
        var i = x.count - 1
        while i > 0 && abs(x[i]) < 1e-4 { i -= 1 }
        return i
    }

    func testGridAndDefaults() {
        XCTAssertEqual(Params.trackGrid[12].id, "rate")
        XCTAssertEqual(Params.byId["rate"]!.def, 100)
        XCTAssertEqual(Params.defaults()["rate"], 100)
        XCTAssertEqual(Params.rate.label, "Rate Pitch")
        XCTAssertEqual(Params.rateTstr.label, "Rate Stretch")
        XCTAssertEqual(KnobDefaults.companion("rate"), Params.rateModeId)
    }

    func testLoopTempoByLength() {
        XCTAssertEqual(TempoDetect.loopBpm(SampleData(left: [Float](repeating: 0, count: 96000), right: nil)), 120,
                       accuracy: 1e-9, "2 с — такт при 120")
        XCTAssertEqual(TempoDetect.loopBpm(SampleData(left: [Float](repeating: 0, count: 144000), right: nil)), 160,
                       accuracy: 1e-9, "3 с — 2 такта при 160")
        XCTAssertEqual(TempoDetect.loopBpm(SampleData(left: [Float](repeating: 0, count: 24000), right: nil)), 0,
                       "короче такта — темп не учитывается")
    }

    /// PTCH 50 %: вдвое медленнее и на октаву ниже.
    func testPitchModeHalfSpeed() {
        let core = AudioCore(master: false)
        core.publish(project(rate: 50, tstr: false), samples: ["k": sine(441, seconds: 1)])
        core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        let o = render(core, frames: 110000)
        XCTAssertEqual(crossings(o, 20000, 48000), 220, accuracy: 2, "на октаву ниже")
        XCTAssertEqual(Double(lastSound(o)), 96000, accuracy: 300, "звучит вдвое дольше")
    }

    /// PTCH левее центра — реверс от конца отрезка.
    func testPitchModeReverse() {
        let core = AudioCore(master: false)
        let n = 48000
        let ramp = SampleData(left: (0..<n).map { Float($0) / Float(n) }, right: nil)
        core.publish(project(rate: -100, tstr: false), samples: ["k": ramp])
        core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        let o = render(core, frames: 50000)
        let c: Float = Float(cos(Double.pi / 4))
        XCTAssertEqual(o[2000] / c, Float(n - 2001) / Float(n), accuracy: 0.01, "идёт от конца к началу")
        XCTAssertGreaterThan(o[2000], o[30000])
        XCTAssertEqual(Double(lastSound(o)), Double(n), accuracy: 200)
        XCTAssertEqual(core.sampler.activeCount, 0)
    }

    /// TSTR 50 %: вдвое дольше, высота прежняя.
    func testStretchKeepsPitch() {
        stretchKeepsPitch(beat: false)
        stretchKeepsPitch(beat: true)
    }

    private func stretchKeepsPitch(beat: Bool) {
        let core = AudioCore(master: false)
        core.publish(project(rate: 50, tstr: true, beat: beat), samples: ["k": sine(441, seconds: 2)])
        core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        let o = render(core, frames: 200000)
        XCTAssertEqual(crossings(o, 20000, 48000), 441, accuracy: 3, "высота не меняется")
        XCTAssertEqual(crossings(o, 120000, 48000), 441, accuracy: 3)
        XCTAssertEqual(Double(lastSound(o)), 192000, accuracy: 600, "звучит вдвое дольше")
        // Ровный уровень без провалов между зёрнами.
        let a = rms(o, 30000, 4800), b = rms(o, 100000, 4800)
        XCTAssertEqual(a, b, accuracy: a * 0.05)
        XCTAssertEqual(a, Float(0.5 / 2.0.squareRoot()) * Float(cos(Double.pi / 4)), accuracy: 0.02)
    }

    /// TSTR в темпе проекта: луп 2 с (120 BPM) в проекте 60 BPM — вдвое дольше, той же высоты; Pitch +12 —
    /// октава вверх без смены длины.
    func testStretchFollowsTempoAndPitch() {
        stretchFollowsTempoAndPitch(beat: false)
        stretchFollowsTempoAndPitch(beat: true)
    }

    private func stretchFollowsTempoAndPitch(beat: Bool) {
        let core = AudioCore(master: false)
        var p = project(rate: 100, tstr: true, bpm: 60, beat: beat)
        p.tracks[0].params["pitch"] = 12
        core.publish(p, samples: ["k": sine(441, seconds: 2)])
        core.events.push(.tempo(60))
        _ = render(core, frames: 256)
        core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        let o = render(core, frames: 200000)
        XCTAssertEqual(crossings(o, 20000, 48000), 882, accuracy: 4, "октава вверх")
        XCTAssertEqual(Double(lastSound(o)), 192000, accuracy: 600, "60 BPM к 120 — вдвое дольше")
    }

    /// TSTR, RATE левее центра — реверс той же высоты.
    func testStretchReverse() {
        stretchReverse(beat: false)
        stretchReverse(beat: true)
    }

    private func stretchReverse(beat: Bool) {
        let core = AudioCore(master: false)
        core.publish(project(rate: -100, tstr: true, beat: beat), samples: ["k": sine(441, seconds: 2)])
        core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        let o = render(core, frames: 100000)
        XCTAssertEqual(crossings(o, 20000, 48000), 441, accuracy: 3)
        XCTAssertEqual(Double(lastSound(o)), 96000, accuracy: 600)
    }

    /// NORMAL при 100 % в темпе файла — почти тот же сигнал (аккорд из трёх нот, стерео с разной фазой каналов).
    func testVocoderNearIdentity() {
        let n = 96000
        var lf = [Float](repeating: 0, count: n), rf = lf
        for i in 0..<n {
            let x = Double(i) / 48000
            lf[i] = Float(0.2 * sin(2 * .pi * 220 * x) + 0.2 * sin(2 * .pi * 277.2 * x) + 0.2 * sin(2 * .pi * 329.6 * x))
            rf[i] = Float(0.2 * sin(2 * .pi * 220 * x + 1) + 0.2 * sin(2 * .pi * 277.2 * x + 2) + 0.2 * sin(2 * .pi * 329.6 * x))
        }
        let core = AudioCore(master: false)
        var p = project(rate: 100, tstr: true)
        p.tracks[0].params["attack"] = 0
        core.publish(p, samples: ["k": SampleData(left: lf, right: rf)])
        core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        var l = [Float](repeating: 0, count: 60000), r = l
        var pos = 0
        var bl = [Float](repeating: 0, count: 256), br = bl
        while pos < 60000 {
            core.render(frames: 256, left: &bl, right: &br)
            for i in 0..<256 where pos + i < 60000 { l[pos + i] = bl[i]; r[pos + i] = br[i] }
            pos += 256
        }
        // Стерео дорожки по центру: L·1, R·1 (StereoPanner в центре).
        var err: Double = 0, sig: Double = 0
        for i in 4000..<58000 {
            err += Double((l[i] - lf[i]) * (l[i] - lf[i]) + (r[i] - rf[i]) * (r[i] - rf[i]))
            sig += Double(lf[i] * lf[i] + rf[i] * rf[i])
        }
        XCTAssertEqual(SampleData(left: lf, right: rf).onsets.count, 0, "у ровного аккорда атак нет")
        let snr: Double = 10 * log10(sig / max(1e-12, err))
        XCTAssertGreaterThan(snr, 30, "NORMAL в темпе файла — почти без искажений (\(snr) dB)")
        XCTAssertEqual(l[100], lf[100], accuracy: 0.02, "начало ноты — без задержки")
    }

    /// NORMAL 50 %: удары (щелчки через 0,25 с) остаются короткими, без предэха, и встают через 0,5 с; атаки сэмпла
    /// находятся за 1 мс до удара.
    func testVocoderKeepsHits() {
        let n = 96000
        var x = [Float](repeating: 0, count: n)
        var k = 0
        while k < n {
            for i in 0..<480 where k + i < n { x[k + i] = Float(0.8 * exp(-Double(i) / 60) * sin(Double(i) * 0.9)) }
            k += 12000
        }
        let ol = SampleData(left: x, right: nil).onsets
        XCTAssertEqual(ol.count, 7, "удары после первого (первый — начало ноты)")
        for i in 0..<ol.count { XCTAssertEqual(ol.at[i], Double((i + 1) * 12000 - 48), accuracy: 16) }
        let core = AudioCore(master: false)
        let p = project(rate: 50, tstr: true)
        core.publish(p, samples: ["k": SampleData(left: x, right: nil)])
        core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        let o = render(core, frames: 192000)
        // Энергия вокруг удара (±10 мс) против энергии между ударами.
        for hit in [24000, 48000, 72000, 96000] {
            let on = rms(o, hit - 240, 1200)
            let off = rms(o, hit + 6000, 6000)
            let pre = rms(o, hit - 1440, 1200)
            XCTAssertGreaterThan(on, off * 8, "удар у \(hit) — короткий")
            XCTAssertGreaterThan(on, pre * 30, "удар у \(hit) не слышен раньше себя")
        }
    }

    /// RATE — цель p-lock и автоматизации (параметр голоса).
    func testRateIsVoiceParam() {
        XCTAssertEqual(VoiceParam.ids[VoiceParam.rate], "rate")
        XCTAssertEqual(VoiceParam.ids.count, VoiceParam.count)
        XCTAssertNotNil(ArrAutoTarget.index("rate"))
        let l = NoteLocks(["rate": -40])
        XCTAssertEqual(l.mask, VoiceMask(1) << VoiceMask(VoiceParam.rate))
    }
}
