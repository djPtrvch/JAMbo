import XCTest
@testable import Core

/// 16 дорожек с тригами, игра; дорожки удаляются по одной с конца и с начала, снимок публикуется заново — колбэк
/// не падает (зависание на iPad 16.11 при удалении в окне MIX).
final class DeleteTracksPlayingTests: XCTestCase {
    private func run(_ core: AudioCore, _ blocks: Int) {
        var l = [Float](repeating: 0, count: 256)
        var r = [Float](repeating: 0, count: 256)
        for _ in 0..<blocks {
            core.render(frames: 256, left: &l, right: &r)
            while core.sequencer.out.pop() != nil {}
        }
    }

    func testDeleteWhilePlaying() {
        for fromStart in [false, true] {
            var p = Project()
            while p.tracks.count < 16 { p.addTrack() }
            for t in 0..<p.tracks.count {
                if p.tracks[t].clips[0] == nil { continue }
                for k in stride(from: 0, to: 16, by: 2) { p.tracks[t].clips[0]!.pages[0][k].on = true }
            }
            let core = AudioCore()
            core.publish(p)
            core.events.push(.play(true))
            run(core, 40)
            while p.canDeleteTrack(fromStart ? 0 : p.tracks.count - 1) {
                p.deleteTrack(fromStart ? 0 : p.tracks.count - 1)
                core.publish(p)
                run(core, 20)
            }
            XCTAssertEqual(p.tracks.count, Params.trackCount)
        }
    }
}
