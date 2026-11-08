import XCTest
@testable import Core

/// Room (Headphone Monitor, фаза 2): разбор импульсов, свёртка против прямой FIR, Ambience, Off бит в бит, смена
/// комнат без разрывов и утечек, компенсация громкости, задержка, нагрузка.
final class RoomTests: XCTestCase {
    static let res = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("JAMbo.swiftpm/Resources")

    static func rooms() -> [RoomInfo] {
        return RoomInfo.list(try? Data(contentsOf: res.appendingPathComponent("rooms.json")))
    }

    static func ir(_ k: Int) -> RoomIR {
        let r: RoomInfo = rooms()[k]
        let d = try! Data(contentsOf: res.appendingPathComponent(r.file))
        return RoomIR(name: r.name, wav: d, gainDb: r.gainDb, direct: r.direct)!
    }

    private func noise(_ n: Int, _ seed: UInt64) -> [Float] {
        var x: UInt64 = seed
        return (0..<n).map { _ in
            x = x &* 6364136223846793005 &+ 1442695040888963407
            return Float(Double(x >> 33) / Double(1 << 31) - 0.5) * 0.5
        }
    }

    /// Через RoomStage блоками по 256 (Double, как в цепочке).
    private func run(_ st: RoomStage, _ l: [Float], _ r: [Float], block: Int = 256,
                     switches: [Int: () -> Void] = [:]) -> (l: [Float], r: [Float]) {
        var ol: [Float] = [], or: [Float] = []
        var bl = [Double](repeating: 0, count: block), br = [Double](repeating: 0, count: block)
        var at = 0
        var b = 0
        while at + block <= l.count {
            switches[b]?()
            for i in 0..<block { bl[i] = Double(l[at + i]); br[i] = Double(r[at + i]) }
            st.process(&bl, &br, block)
            ol += bl.map { Float($0) }
            or += br.map { Float($0) }
            at += block
            b += 1
        }
        return (ol, or)
    }

    func testRoomsAndWav() {
        let list = RoomTests.rooms()
        XCTAssertEqual(list.map { $0.name }, ["Studio", "Home", "Car", "Club", "Desk", "StudioRaw", "StudioHalf"])
        for k in 0..<list.count {
            let ir = RoomTests.ir(k)
            XCTAssertGreaterThan(ir.frames, 1000)
            XCTAssertLessThanOrEqual(ir.frames, RoomIR.maxFrames)
            XCTAssertEqual(ir.direct, 128)
            print(String(format: "room %@: %.1f ms", ir.name, Double(ir.frames) / 48))
        }
        XCTAssertNil(RoomIR.parseWav(Data("junk".utf8)))
        XCTAssertNil(RoomIR(name: "x", wav: Data([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0]), gainDb: 0, direct: 128))
        XCTAssertEqual(RoomInfo.list(Data("{".utf8)).count, 0)
    }

    /// Свёртка = прямая FIR (задержка 128) с ошибкой ≤ −120 dB; Ambience 0 — только прямая часть.
    func testMatchesDirectFir() {
        let ir = RoomTests.ir(2)
        for amb in [Float(1), 0] {
            let st = RoomStage(sampleRate: 48000)
            st.ambience.store(amb)
            st.set(RoomConv(ir: ir))
            let n = 256 * 60
            let l = noise(n, 1), r = noise(n, 2)
            let o = run(st, l, r)
            let fr = ir.frames
            var err: Double = 0, sig: Double = 0
            for t in 4000..<(n - 256) {
                var el: Double = 0, er: Double = 0
                for k in 0..<fr where t - 128 - k >= 0 {
                    let g: Double = k < ir.direct ? 1 : Double(amb)
                    let xl: Double = Double(l[t - 128 - k]), xr: Double = Double(r[t - 128 - k])
                    el += g * (Double(ir.h[k]) * xl + Double(ir.h[2 * fr + k]) * xr)
                    er += g * (Double(ir.h[fr + k]) * xl + Double(ir.h[3 * fr + k]) * xr)
                }
                err += pow(Double(o.l[t]) - el, 2) + pow(Double(o.r[t]) - er, 2)
                sig += el * el + er * er
            }
            let db: Double = 10 * log10(err / sig)
            print(String(format: "room conv error (ambience %.0f): %.1f dB", amb, db))
            XCTAssertLessThan(db, -120)
        }
    }

    /// Off — выход бит в бит равен входу; после Off из комнаты — тоже.
    func testOffBitExact() {
        let st = RoomStage(sampleRate: 48000)
        let l = noise(256 * 40, 3), r = noise(256 * 40, 4)
        let o = run(st, l, r)
        XCTAssertEqual(o.l, l)
        XCTAssertEqual(o.r, r)
        let o2 = run(st, l, r, switches: [0: { st.set(RoomConv(ir: RoomTests.ir(0))) }, 12: { st.set(nil) }])
        XCTAssertEqual(Array(o2.l.suffix(256 * 10)), Array(l.suffix(256 * 10)))
        st.drain()
    }

    /// Смена комнат, Ambience и Off на ходу (в том числе быстро, много раз) — без разрывов и утечек.
    func testSwitchSmoothAndNoLeaks() {
        let st = RoomStage(sampleRate: 48000)
        let n = 256 * 400
        let hz: Double = 300
        let l: [Float] = (0..<n).map { Float(0.3 * sin(2 * Double.pi * hz * Double($0) / 48000)) }
        let irs: [RoomIR] = (0..<3).map { RoomTests.ir($0) }
        weak var probe: RoomConv? = nil
        var sw: [Int: () -> Void] = [:]
        for b in stride(from: 0, to: 300, by: 3) {
            sw[b] = {
                let c = RoomConv(ir: irs[b % 3])
                if b == 0 { probe = c }
                st.set(b % 7 == 0 ? nil : c)
                st.ambience.store(Float(b % 5) / 4)
                st.drain()
            }
        }
        let o = run(st, l, l, switches: sw)
        // Самый большой скачок между соседними отсчётами — порядка шага синуса, умноженного на усиление комнаты.
        var jump: Float = 0
        for i in 1..<o.l.count { jump = max(jump, abs(o.l[i] - o.l[i - 1])) }
        let sineStep: Float = Float(0.3 * 2 * Double.pi * hz / 48000)
        print(String(format: "room switch: max jump %.4f (sine step %.4f)", jump, sineStep))
        XCTAssertLessThan(jump, sineStep * 8)
        st.set(nil)
        _ = run(st, l, l)
        st.drain()
        XCTAssertNil(probe, "отработавшие свёртки освобождены")
    }

    /// Level compensation: розовый шум с комнатой и без — разница громкости не больше ±1 dB.
    func testLevelCompensation() {
        let n = 48000 * 4
        // Розовый шум: белый в спектре · 1/√f.
        let pink: [Float] = RoomTests.pink(n)
        for k in 0..<RoomTests.rooms().count {
            let ir = RoomTests.ir(k)
            let resp = ir.response(sampleRate: 48000)
            for amb in [0.0, 0.5, 1.0] {
                var m = MonitorSettings()
                let p = MonitorDesign.make(eq: nil, settings: m, correct: nil, preset: nil, room: resp, ambience: amb,
                                           sampleRate: 48000)
                let c = MonitorChain(sampleRate: 48000)
                c.publish(p)
                c.room.ambience.store(Float(amb))
                c.room.set(RoomConv(ir: ir))
                var bl = [Float](repeating: 0, count: 256), br = bl
                var e: Double = 0, e0: Double = 0
                var at = 0
                while at + 256 <= n {
                    for i in 0..<256 { bl[i] = pink[at + i]; br[i] = pink[at + i] }
                    c.process(&bl, &br, 256, raw: false)
                    if at > 48000 {
                        for i in 0..<256 {
                            e += Double(bl[i] * bl[i] + br[i] * br[i])
                            e0 += 2 * Double(pink[at + i] * pink[at + i])
                        }
                    }
                    at += 256
                }
                let db: Double = 10 * log10(e / e0)
                print(String(format: "room %@ ambience %.1f: level %+.2f dB (comp %+.2f dB)", ir.name, amb, db,
                             20 * log10(p[MonitorSpec.compAt])))
                XCTAssertEqual(db, 0, accuracy: 1.0)
            }
        }
    }

    /// Розовый шум (−3 dB на октаву) ровно в полосе компенсации 20 Гц…20 кГц, RMS 0,1.
    static func pink(_ n: Int) -> [Float] {
        // Точно: спектр 1/√f со случайными фазами в полосе 20 Гц…20 кГц (та же, что у компенсации), обратное БПФ.
        var size = 1024
        while size < n { size *= 2 }
        let fft = PvFFT(size: size)
        let bins: Int = size / 2 + 1
        var re = [Float](repeating: 0, count: bins), im = re
        var x: UInt64 = 99
        for k in 1..<bins {
            let hz: Double = Double(k) * 48000 / Double(size)
            if hz < 20 || hz > 20000 { continue }
            x = x &* 6364136223846793005 &+ 1442695040888963407
            let ph: Double = Double(x >> 11) / Double(1 << 53) * 2 * Double.pi
            let m: Double = 1 / hz.squareRoot()
            re[k] = Float(m * cos(ph))
            im[k] = Float(m * sin(ph))
        }
        var t = [Float](repeating: 0, count: size)
        re.withUnsafeMutableBufferPointer { r in
            im.withUnsafeMutableBufferPointer { i in
                t.withUnsafeMutableBufferPointer { o in fft.inverse(r.baseAddress!, i.baseAddress!, o.baseAddress!) }
            }
        }
        var e: Double = 0
        for i in 0..<n { e += Double(t[i] * t[i]) }
        let g: Float = Float(0.1 / (e / Double(n)).squareRoot())
        return (0..<n).map { t[$0] * g }
    }

    /// Задержка — 128 отсчётов; нагрузка свёртки самой длинной комнаты — Club, 1 с (отладочная сборка, без vDSP на Linux).
    func testLatencyAndLoad() {
        let ir = RoomTests.ir(3)
        let st = RoomStage(sampleRate: 48000)
        st.ambience.store(1)
        st.set(RoomConv(ir: ir))
        var imp = [Float](repeating: 0, count: 256 * 40)
        imp[256 * 20] = 1
        let o = run(st, imp, [Float](repeating: 0, count: imp.count))
        let first: Int = (0..<o.l.count).first { abs(o.l[$0]) > 1e-6 } ?? -1
        let irFirst: Int = (0..<ir.frames).first { abs(ir.h[$0]) > 1e-6 } ?? 0
        XCTAssertEqual(first - 256 * 20 - irFirst, 128)
        var bl = [Double](repeating: 0.1, count: 256), br = bl
        let t0 = Date()
        let blocks = 400
        for _ in 0..<blocks { st.process(&bl, &br, 256) }
        let per: Double = Date().timeIntervalSince(t0) / Double(blocks)
        print(String(format: "room conv %@: %.0f µs на блок 256 (%.1f %% времени блока, Linux, без vDSP)", ir.name, per * 1e6,
                     per / (256.0 / 48000) * 100))
        st.set(nil)
        st.drain()
    }
}
