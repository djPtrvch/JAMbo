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
