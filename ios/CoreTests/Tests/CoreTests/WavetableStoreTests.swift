import XCTest
@testable import Core

/// Кэш таблиц WTABLE: все ожидающие получают готовность, предзагрузка, очистка своих таблиц.
final class WavetableStoreTests: XCTestCase {
    func testWaitersAndPrune() {
        let s = WavetableStore()
        let key = WavetableKey.builtin("PWM")
        let a = expectation(description: "first")
        let b = expectation(description: "second")
        XCTAssertNil(s.table(key, done: { a.fulfill() }))
        XCTAssertNil(s.table(key, done: { b.fulfill() }), "строится — второй ждёт тоже")
        wait(for: [a, b], timeout: 30)
        XCTAssertNotNil(s.table(key, done: {}))
        s.prune(keep: [])
        XCTAssertNotNil(s.ready[key], "встроенные остаются")
    }

    func testPreloadBuiltins() {
        let s = WavetableStore()
        s.preloadBuiltins()
        let done = expectation(description: "all")
        func check() {
            if WavetableKey.builtins.allSatisfy({ s.ready[WavetableKey.builtin($0)] != nil }) {
                done.fulfill()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { check() }
            }
        }
        check()
        wait(for: [done], timeout: 60)
    }
}

/// Таблица показа своей таблицы — из WAV, без звуковой: пила 2 кадра → кадры пилы к пику 1, без постоянной.
final class WavetableUserDisplayTests: XCTestCase {
    func testUserDisplayFromSamples() {
        let fs = 256
        var s: [Float] = []
        for f in 0..<2 { for j in 0..<fs { s.append(Float(j) / Float(fs) * (f == 0 ? 1 : 0.5) + 0.3) } }
        let d = WtDisplay.user(s, frameSize: fs)
        XCTAssertEqual(d.data.count, WtDisplay.frames * WtDisplay.size)
        let peak: Float = d.data.map { abs($0) }.max() ?? 0
        XCTAssertEqual(peak, 1, accuracy: 1e-4)
        let row0 = d.data[0..<WtDisplay.size]
        XCTAssertEqual(row0.reduce(0, +) / Float(WtDisplay.size), 0, accuracy: 1e-4, "без постоянной")
        XCTAssertLessThan(row0.first!, row0[row0.startIndex + 200], "пила растёт")
    }
}
