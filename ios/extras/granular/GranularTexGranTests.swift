// ОТЛОЖЕНО: тесты GRANULAR из CoreTests/Tests/CoreTests/TexGranVoiceTests.swift (вернуть — в класс TexGranVoiceTests),
// там же — GRANULAR в testCost и testIcons. GranularEngineTests.swift этой папки — в CoreTests/Tests/CoreTests.

    // MARK: — GRANULAR

    func coreWithSample(_ grain: String, samples: [String: SampleData]) -> AudioCore {
        var p = Project()
        p.tracks[0].setSynth(Jambo.granular)
        p.tracks[0].vol = 0
        p.tracks[0].grain = grain
        let c = AudioCore(master: false)
        c.installSynth()
        c.publish(p, samples: samples)
        return c
    }

    /// Со своим сэмплом — звучит (стерео), без него — тишина; NaN нет.
    func testGranularSource() {
        let demo = GranularEngineTests.demo
        let c = coreWithSample("demo", samples: ["demo": demo])
        c.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        let (l, r) = render(c, frames: 48000)
        XCTAssertFalse(l.contains { !$0.isFinite } || r.contains { !$0.isFinite })
        XCTAssertGreaterThan(rms(l), 0.005)
        XCTAssertGreaterThan(rms(r), 0.005)
        let q = coreWithSample("", samples: ["demo": demo])
        q.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        let (l2, _) = render(q, frames: 24000)
        XCTAssertLessThan(rms(l2), 1e-9)
        // Сэмпл есть в проекте, но не загружен — тоже тишина.
        let m = coreWithSample("missing", samples: [:])
        m.events.push(.noteOn(track: 0, note: 48, id: 1, velocity: 1))
        XCTAssertLessThan(rms(render(m, frames: 24000).0), 1e-9)
    }


    /// Фон иконки GRANULAR — огибающая настоящего сэмпла: громкая первая половина и тишина во второй видны на иконке.
    func testGranularIconFollowsSample() {
        let n = 48000
        let left: [Float] = (0..<n).map { i in i < n / 2 ? Float(sin(Double(i) * 0.05)) * 0.5 : 0 }
        let s = SampleData(left: left, right: nil)
        let peaks = EngineIcons.samplePeaks(s)
        XCTAssertEqual(peaks.count, 433)
        XCTAssertEqual(peaks.max() ?? 0, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(peaks[100], 0.9)
        XCTAssertEqual(peaks[400], 0)
        let v = IconValues(h: 0.1, t: 0.3, m: 0.5, q: 0.1)
        let real = EngineIcons.granularIcon(v, peaks: peaks)
        let fake = EngineIcons.granularIcon(v)
        XCTAssertNotEqual("\(real[0].rects)", "\(fake[0].rects)")
        // Серая волна (первый элемент): во второй половине поля столбиков почти нет высоты.
        let right = real[0].rects.filter { $0.x > 40 }
        XCTAssertLessThan(right.map { $0.h }.max() ?? 0, 1.0)
        let leftRects = real[0].rects.filter { $0.x < 25 }
        XCTAssertGreaterThan(leftRects.map { $0.h }.max() ?? 0, 30)
        XCTAssertEqual(EngineIcons.samplePeaks(SampleData(left: [Float](repeating: 0, count: 100), right: nil)).max(), 0)
    }
