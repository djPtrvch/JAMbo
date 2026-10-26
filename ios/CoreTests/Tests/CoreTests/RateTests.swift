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

    private func project(rate: Double, tstr: Bool, bpm: Double = 120) -> Project {
        var p = Project()
        p.tracks[0].addSamples(["k"])
        p.tracks[0].vol = 0
        p.tracks[0].params["decay"] = 4000
        p.tracks[0].params["rate"] = rate
        p.tracks[0].params[Params.rateModeId] = tstr ? 1 : 0
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
        XCTAssertEqual(Params.rate.label, "Rate PTCH")
        XCTAssertEqual(Params.rateTstr.label, "Rate TSTR")
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
        let core = AudioCore(master: false)
        core.publish(project(rate: 50, tstr: true), samples: ["k": sine(441, seconds: 2)])
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
        let core = AudioCore(master: false)
        var p = project(rate: 100, tstr: true, bpm: 60)
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
        let core = AudioCore(master: false)
        core.publish(project(rate: -100, tstr: true), samples: ["k": sine(441, seconds: 2)])
        core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        let o = render(core, frames: 100000)
        XCTAssertEqual(crossings(o, 20000, 48000), 441, accuracy: 3)
        XCTAssertEqual(Double(lastSound(o)), 96000, accuracy: 600)
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
