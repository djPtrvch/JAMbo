import XCTest
@testable import Core

/// Очередь снимков паттернов полна (колбэк стоит): невлезший снимок отправляется заново следующей публикацией.
final class SnapshotQueueTests: XCTestCase {
    func testDroppedSnapshotIsResent() {
        let core = AudioCore(master: false)
        var p = Project()
        core.publish(p)
        // Колбэк не идёт: ещё 63 правки заполняют очередь (64 места), следующая в неё не помещается.
        for i in 0..<63 {
            p.tracks[0].stopped = (i % 2 == 0)
            core.publish(p)
        }
        p.tracks[1].stopped = true
        core.publish(p)
        let left = UnsafeMutablePointer<Float>.allocate(capacity: 256)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: 256)
        defer { left.deallocate(); right.deallocate() }
        core.render(frames: 256, left: left, right: right)
        XCTAssertEqual(core.sequencer.data?.stopped[1], 0, "снимок с правкой не поместился в очередь")
        // Звук вернулся; публикация без правки паттерна (поворот ручки) досылает паттерны.
        core.publish(p)
        core.render(frames: 256, left: left, right: right)
        XCTAssertEqual(core.sequencer.data?.stopped[1], 1)
    }
}
