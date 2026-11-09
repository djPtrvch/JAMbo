import XCTest
@testable import Core

/// Колонки комнат (9.11): срез низа на входе свёртки — по rooms.json (speaker), АЧХ Баттерворта, без него — как прежде.
final class RoomSpeakerTests: XCTestCase {
    /// Мощность выхода (L + R) для синуса hz, после установления.
    private func power(_ conv: RoomConv, _ hz: Double) -> Double {
        let st = RoomStage(sampleRate: 48000)
        st.ambience.store(1)
        st.set(conv)
        let n = 256
        let l = UnsafeMutablePointer<Double>.allocate(capacity: n)
        let r = UnsafeMutablePointer<Double>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        var t = 0
        var sum: Double = 0
        for b in 0..<300 {
            for i in 0..<n {
                let v: Double = 0.25 * sin(2 * Double.pi * hz * Double(t) / 48000)
                l[i] = v
                r[i] = v
                t += 1
            }
            st.process(l, r, n)
            if b >= 200 {
                for i in 0..<n { sum += l[i] * l[i] + r[i] * r[i] }
            }
        }
        return sum
    }

    func testRoomsHaveSpeakers() {
        let rooms = RoomTests.rooms()
        XCTAssertFalse(rooms.isEmpty)
        for r in rooms {
            XCTAssertGreaterThan(r.hpHz, 20, r.name)
            XCTAssertTrue(r.hpOrder == 2 || r.hpOrder == 4, r.name)
        }
    }

    /// Срез низа = Баттерворт (±0,5 dB на 30 и 60 Гц), на 1 кГц без изменений (±0,1 dB).
    func testHighpassMatchesButterworth() {
        let rooms = RoomTests.rooms()
        let k: Int = rooms.firstIndex { $0.name == "Desk" } ?? 0
        let info = rooms[k]
        let ir = RoomTests.ir(k)
        for hz in [30.0, 60.0, 1000.0] {
            let plain = RoomConv(ir: ir)
            let cut = RoomConv(ir: ir)
            cut.setHighpass(hz: info.hpHz, order: info.hpOrder, sampleRate: 48000)
            let db: Double = 10 * log10(power(cut, hz) / power(plain, hz))
            let x: Double = pow(hz / info.hpHz, Double(2 * info.hpOrder))
            let want: Double = 10 * log10(x / (1 + x))
            print(String(format: "%@ speaker high-pass at %.0f Hz: %.2f dB (Butterworth %.2f dB)", info.name, hz, db, want))
            XCTAssertEqual(db, want, accuracy: hz < 100 ? 0.5 : 0.1)
        }
    }

    /// Отклик для компенсации громкости учитывает срез: мощность на низах падает, на 1 кГц — нет.
    func testResponseHighpass() {
        let ir = RoomTests.ir(0)
        var r = ir.response(sampleRate: 48000)
        let lo: Double = r.power(0, 1), mid: Double = r.power(60, 1)
        r.highpass(hz: 85, order: 4)
        XCTAssertLessThan(r.power(0, 1), lo * 0.001)
        XCTAssertEqual(r.power(60, 1), mid, accuracy: mid * 0.01)
    }
}

/// Смена EAR TONE (9.11): новая свёртка берёт историю прежней — во время перехода выход равен кроссфейду двух
/// установившихся свёрток (хвост не обрывается), после перехода — точно новая.
final class RoomSwitchTests: XCTestCase {
    private func render(_ st: RoomStage, _ x: [Double], _ y: [Double], switchAt: Int = -1,
                        _ to: RoomConv? = nil) -> [Double] {
        let n = 256
        let l = UnsafeMutablePointer<Double>.allocate(capacity: n)
        let r = UnsafeMutablePointer<Double>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        var out: [Double] = []
        var b = 0
        while b * n < x.count {
            if b == switchAt, let c = to { st.set(c) }
            for i in 0..<n { l[i] = x[b * n + i]; r[i] = y[b * n + i] }
            st.process(l, r, n)
            for i in 0..<n { out.append(l[i]); out.append(r[i]) }
            b += 1
        }
        return out
    }

    func testEarToneSwitchKeepsTail() {
        let rooms = RoomTests.rooms()
        let k: Int = rooms.firstIndex { $0.name == "Club" } ?? 0
        let info = rooms[k]
        let ir = RoomTests.ir(k)
        let d = try! Data(contentsOf: RoomTests.res.appendingPathComponent(info.flatFile))
        let flat = RoomIR(name: info.name, wav: d, gainDb: info.flatGainDb, direct: info.direct)!
        let other: RoomIR = ir.mixed(flat: flat, raw: 0.3)
        var seed: UInt64 = 7
        let n = 256 * 400
        var x: [Double] = [], y: [Double] = []
        for _ in 0..<n {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            x.append(Double(seed >> 33) / Double(1 << 31) - 0.5)
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            y.append(Double(seed >> 33) / Double(1 << 31) - 0.5)
        }
        func stage(_ c: RoomConv) -> RoomStage {
            let st = RoomStage(sampleRate: 48000)
            st.ambience.store(1)
            st.set(c)
            return st
        }
        let a = render(stage(RoomConv(ir: ir)), x, y)
        let b = render(stage(RoomConv(ir: other)), x, y)
        let sw = render(stage(RoomConv(ir: ir)), x, y, switchAt: 300, RoomConv(ir: other))
        // Переход начинается в блоке 300, длится 1920 отсчётов.
        let start: Int = 300 * 256
        var err: Double = 0, sig: Double = 0
        for t in (start - 512)..<(start + 4096) {
            let f: Double = Swift.min(1, Swift.max(0, Double(t - start + 1) / 1920))
            for c in 0..<2 {
                let want: Double = a[2 * t + c] + (b[2 * t + c] - a[2 * t + c]) * f
                err += pow(sw[2 * t + c] - want, 2)
                sig += want * want
            }
        }
        var e2: Double = 0, s2: Double = 0, e3: Double = 0
        for t in (start + 2000)..<(start + 8000) {
            for c in 0..<2 { e2 += pow(sw[2 * t + c] - b[2 * t + c], 2); s2 += b[2 * t + c] * b[2 * t + c] }
        }
        for t in (start - 4000)..<start {
            for c in 0..<2 { e3 += pow(sw[2 * t + c] - a[2 * t + c], 2) }
        }
        XCTAssertEqual(e3, 0)
        XCTAssertLessThan(10 * log10(e2 / s2), -120)
        let db: Double = 10 * log10(err / sig)
        print(String(format: "EAR TONE switch vs crossfade of settled rooms: %.1f dB", db))
        // Первые 128 отсчётов перехода новая свёртка ещё отдаёт выход прежней (посчитан до смены) — при доле
        // перехода < 7 % это −54 dB; без истории (как было) — −15 dB.
        XCTAssertLessThan(db, -50)
    }
}
