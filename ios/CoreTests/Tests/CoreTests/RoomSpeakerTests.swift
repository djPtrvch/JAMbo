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
