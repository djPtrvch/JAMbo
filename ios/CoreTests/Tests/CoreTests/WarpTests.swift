import XCTest
@testable import Core

/// WARP: карта времени, AUTO WARP, правка меток, хранение и звук голоса в Rate Stretch.
final class WarpTests: XCTestCase {
    private let sr: Double = 48000

    func testMapBothWaysAndOutside() {
        // 120 BPM: доля — 24000 отсчётов; метки: отсчёт 26400 → доля 1, 48000 → доля 2.
        let info = WarpInfo(marks: [WarpMark(at: 26400.0 / 96000, beat: 1), WarpMark(at: 0.5, beat: 2)])
        let map = WarpMap(info, frames: 96000, bpm: 120)
        XCTAssertEqual(map.beat(26400), 1, accuracy: 1e-9)
        XCTAssertEqual(map.beat(37200), 1.5, accuracy: 1e-9)
        XCTAssertEqual(map.beat(72000), 3, accuracy: 1e-9, "после последней — по BPM файла")
        XCTAssertEqual(map.beat(2400), 0, accuracy: 1e-9, "до первой — по BPM файла")
        for b in stride(from: -0.5, through: 4, by: 0.25) {
            XCTAssertEqual(map.beat(map.position(b)), b, accuracy: 1e-9)
        }
        let none = WarpMap(WarpInfo(), frames: 96000, bpm: 120)
        XCTAssertEqual(none.beat(36000), 1.5, accuracy: 1e-9)
        XCTAssertEqual(WarpMap.bpm(nil, detected: 0), 120)
        XCTAssertEqual(WarpMap.bpm(WarpInfo(bpm: 98), detected: 125), 98)
    }

    func testAutoSnapsToGrid() {
        // 120 BPM, сетка 1/16 (0,25 доли = 6000 отсчётов).
        let onsets: [Double] = [10, 6500, 11000, 12100, 30500]
        let m = WarpMap.auto(onsets: onsets, frames: 48000, bpm: 120, grid: 0.25)
        XCTAssertEqual(m.map { $0.beat }, [0, 0.25, 0.5, 1.25], "12100 попала на ту же долю, что 11000 — без метки")
        XCTAssertEqual(m[1].at * 48000, 6500, accuracy: 1e-6)
    }

    func testEditsAndCoding() throws {
        var t = Track(index: 0)
        let key = "k"
        // Новая метка — на своей доле (звук не меняется).
        let i = t.addWarp(key, at: 0.25, frames: 96000, detectedBpm: 120)
        XCTAssertEqual(i, 0)
        XCTAssertEqual(t.warpInfo(key).marks[0].beat, 1, accuracy: 1e-9)
        XCTAssertNil(t.addWarp(key, at: 0.25 + 10.0 / 96000, frames: 96000, detectedBpm: 120), "вплотную — нет")
        t.addWarp(key, at: 0.75, frames: 96000, detectedBpm: 120)
        // Доля — между соседями.
        t.moveWarp(key, 0, beat: 5)
        XCTAssertEqual(t.warpInfo(key).marks[0].beat, 3 - WarpMap.minBeat, accuracy: 1e-9)
        t.setWarpBpm(key, 1000)
        XCTAssertEqual(t.warpInfo(key).bpm, WarpMap.bpmMax)
        // В проекте и в звуке клипа (TrackSound).
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(Track.self, from: data)
        XCTAssertEqual(back.warps, t.warps)
        XCTAssertEqual(t.sound.warps, t.warps)
        var u = Track(index: 0)
        u.sound = t.sound
        XCTAssertEqual(u.warps, t.warps)
        // CLEAR WARP — метки, свой BPM остаётся; без меток и BPM — записи нет.
        t.clearWarp(key)
        XCTAssertEqual(t.warpInfo(key).marks.count, 0)
        XCTAssertEqual(t.warpInfo(key).bpm, WarpMap.bpmMax)
        t.setWarpBpm(key, Double?.none)
        XCTAssertNil(t.warps[key])
        t.deleteWarp(key, 0)
        // Прежний файл без поля warps.
        let old = try JSONDecoder().decode(TrackSound.self, from: JSONEncoder().encode(Track(index: 0).sound))
        XCTAssertNil(old.warps)
    }

    // MARK: — звук

    /// Удары 0, 0,5, 1,1, 1,5 с (третий — поздно: доля 2,2; по сетке 1/4 — на долю 2); 2 с — луп 120 BPM.
    private func hits() -> SampleData {
        let n = 96000
        var x = [Float](repeating: 0, count: n)
        for at in [0, 24000, 52800, 72000] {
            for i in 0..<480 where at + i < n { x[at + i] = Float(0.8 * exp(-Double(i) / 60) * sin(Double(i) * 0.9)) }
        }
        return SampleData(left: x, right: nil)
    }

    /// Начала ударов в выходе (громкость за 2 мс выше порога после тишины 50 мс).
    private func hitTimes(_ o: [Float]) -> [Int] {
        var out: [Int] = []
        var quiet = 0
        for i in 0..<o.count {
            if abs(o[i]) > 0.05 {
                if quiet > 2400 || out.isEmpty && quiet == i { out.append(i) }
                quiet = 0
            } else {
                quiet += 1
            }
        }
        return out
    }

    private func play(_ s: SampleData, warp: Bool, beat: Bool, pitchMode: Bool = false, preview: Bool = false) -> [Int] {
        var p = Project()
        p.tracks[0].addSamples(["k"])
        p.tracks[0].vol = 0
        p.tracks[0].params["attack"] = 0
        p.tracks[0].params["decay"] = 4000
        p.tracks[0].params["rate"] = 100
        p.tracks[0].params[Params.rateModeId] = pitchMode ? 0 : 1
        p.bpm = 120
        if warp {
            p.tracks[0].setWarpBpm("k", 120)
            p.tracks[0].autoWarp("k", onsets: s.onsets.list, frames: s.frames, detectedBpm: s.loopBpm, grid: 1)
        }
        let core = AudioCore(master: false)
        core.publish(p, samples: ["k": s], stretchBeat: beat)
        if preview {
            core.events.push(.warpPreview(track: 0, hash: SoundKey.hash("k")))
        } else {
            core.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        }
        var o = [Float](repeating: 0, count: 90000)
        var bl = [Float](repeating: 0, count: 256), br = bl
        var pos = 0
        while pos < o.count {
            core.render(frames: 256, left: &bl, right: &br)
            for i in 0..<256 where pos + i < o.count { o[pos + i] = bl[i] }
            pos += 256
        }
        return hitTimes(o)
    }

    func testWarpPutsLateHitOnBeat() {
        let s = hits()
        for beat in [false, true] {
            let plain = play(s, warp: false, beat: beat)
            XCTAssertEqual(plain.count, 4, "\(plain)")
            if plain.count == 4 { XCTAssertEqual(Double(plain[2]), 52800, accuracy: 600, "без меток — как в файле") }
            let w = play(s, warp: true, beat: beat)
            XCTAssertEqual(w.count, 4, "\(w)")
            guard w.count == 4 else { continue }
            for (k, want) in [0, 24000, 48000, 72000].enumerated() {
                XCTAssertEqual(Double(w[k]), Double(want), accuracy: 600, "удар \(k) на доле (\(beat ? "BEAT" : "NORMAL"))")
            }
        }
    }

    /// ▶ WARP: дорожка в Rate Pitch — по карте (удар на доле); обычная нота той же дорожки — как в файле.
    func testWarpPreviewOnPitchTrack() {
        let s = hits()
        let note = play(s, warp: true, beat: false, pitchMode: true)
        XCTAssertEqual(note.count, 4, "\(note)")
        if note.count == 4 { XCTAssertEqual(Double(note[2]), 52800, accuracy: 600, "Rate Pitch — без варпинга") }
        let pv = play(s, warp: true, beat: false, pitchMode: true, preview: true)
        XCTAssertEqual(pv.count, 4, "\(pv)")
        if pv.count == 4 { XCTAssertEqual(Double(pv[2]), 48000, accuracy: 600, "▶ WARP — по карте") }
    }
}
