import XCTest
@testable import Core

final class QueueTests: XCTestCase {
    func testOrderAndCapacity() {
        let q = SPSCQueue<Int>(capacity: 5, filler: 0) // → 8
        for i in 0..<8 { XCTAssertTrue(q.push(i)) }
        XCTAssertFalse(q.push(99), "полная очередь не принимает")
        for i in 0..<8 { XCTAssertEqual(q.pop(), i) }
        XCTAssertNil(q.pop())
    }

    func testWrapAround() {
        let q = SPSCQueue<CoreEvent>(capacity: 4, filler: .none)
        for round in 0..<100 {
            XCTAssertTrue(q.push(.toneFrequency(Float(round))))
            XCTAssertTrue(q.push(.tone(on: round % 2 == 0)))
            guard case .toneFrequency(let f)? = q.pop() else { return XCTFail() }
            XCTAssertEqual(f, Float(round))
            guard case .tone(let on)? = q.pop() else { return XCTFail() }
            XCTAssertEqual(on, round % 2 == 0)
        }
        XCTAssertEqual(q.count, 0)
    }

    /// Писатель и читатель в разных потоках: всё дошло по порядку.
    func testTwoThreads() {
        let q = SPSCQueue<Int>(capacity: 64, filler: 0)
        let n = 200_000
        let done = expectation(description: "writer")
        Thread.detachNewThread {
            var i = 0
            while i < n { if q.push(i) { i += 1 } }
            done.fulfill()
        }
        var next = 0
        while next < n { if let v = q.pop() { XCTAssertEqual(v, next); next += 1 } }
        wait(for: [done], timeout: 10)
    }

    func testAtomicFloat() {
        let a = AtomicFloat(0.5)
        XCTAssertEqual(a.load(), 0.5)
        a.store(-3.25)
        XCTAssertEqual(a.load(), -3.25)
    }
}
