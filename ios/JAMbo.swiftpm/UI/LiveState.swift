import Foundation
import Observation

/// Ход игры: позиция шага каждой дорожки, мигание дорожек, доля метронома.
@Observable
final class LiveState {
    /// Дорожки, затем последовательности MIX и MST (SeqData.maxTracks + c).
    private(set) var playPos: [Int] = [Int](repeating: -1, count: Params.maxTracks + SeqData.chans)
    private(set) var flashing: [Bool] = [Bool](repeating: false, count: Params.maxTracks)
    /// Доля от старта (для полосы фазы и мигания метронома); −1 — стоп.
    private(set) var beat: Int = -1
    private(set) var beatFlash: Bool = false
    private(set) var beatAccent: Bool = false
    @ObservationIgnored private var flashUntil: [Double] = [Double](repeating: 0, count: Params.maxTracks)
    @ObservationIgnored private var beatUntil: Double = 0
    /// Слышна ли дорожка (mute / solo) — задаёт модель.
    @ObservationIgnored var audible: (Int) -> Bool = { _ in true }

    /// Ожидание у дорожек (Launcher.none / stop / ячейка), начало прохода, играющая и ожидающая строки.
    private(set) var queued: [Int] = [Int](repeating: Launcher.none, count: Params.maxTracks)
    @ObservationIgnored private(set) var trackStart: [Int] = [Int](repeating: 0, count: Params.maxTracks)
    private(set) var sceneRow: Int = -1
    @ObservationIgnored private(set) var sceneStart: Int = 0
    @ObservationIgnored private(set) var sceneLen: Int = 16
    private(set) var sceneQueued: Int = -1
    /// Растёт, когда прошёл шаг (для полос хода в сетке паттернов).
    private(set) var stepSerial: Int = 0
    /// Аранжировщик (S15): курсор (шаги) и дорожки, которые идут по таймлайну.
    private(set) var arrPos: Int = 0
    private(set) var following: [Bool] = [Bool](repeating: false, count: Params.maxTracks)

    func drain(_ queue: SPSCQueue<SeqOut>, now: Double, onStep: (Int, Int) -> Void, onPlay: (SeqOut) -> Void) {
        while let e = queue.pop() {
            switch e {
            case .none:
                break
            case .step(let t, let pos):
                if playPos[t] != pos { playPos[t] = pos }
                if t == 0 { stepSerial &+= 1 }
                if pos >= 0 { onStep(t, pos) }
            case .trig(let t, _):
                // Заглушённая дорожка играет дальше, но не мигает.
                if !audible(t) { continue }
                flashUntil[t] = now + 0.09
                if !flashing[t] { flashing[t] = true }
            case .clip(let t, _, _, let start):
                trackStart[t] = start
                if queued[t] != Launcher.none { queued[t] = Launcher.none }
                onPlay(e)
            case .queue(let t, let v):
                queued[t] = v
            case .scene(let row, let start, let len):
                sceneRow = row
                sceneStart = start
                sceneLen = len
            case .sceneQueue(let row):
                sceneQueued = row
            case .ended:
                onPlay(e)
            case .arrange(let pos):
                if arrPos != pos { arrPos = pos }
            case .follow(let t, let on):
                if t < following.count && following[t] != on { following[t] = on }
            case .beat(let accent):
                beat += 1
                beatAccent = accent
                beatFlash = true
                beatUntil = now + 0.09
            }
        }
        for t in 0..<Params.maxTracks where flashing[t] && now >= flashUntil[t] {
            flashing[t] = false
        }
        if beatFlash && now >= beatUntil { beatFlash = false }
    }

    /// Дорожка from встала на место to: ход, ожидание и позиция шага переезжают с ней (как Launcher.move).
    func moveTrack(_ from: Int, _ to: Int) {
        let n: Int = Params.maxTracks
        if from == to || from < 0 || to < 0 || from >= n || to >= n { return }
        func mv<T>(_ a: inout [T]) {
            let x: T = a.remove(at: from)
            a.insert(x, at: to)
        }
        mv(&queued)
        mv(&trackStart)
        mv(&playPos)
        mv(&following)
        mv(&flashing)
        mv(&flashUntil)
    }

    func stopped() {
        beat = -1
        beatFlash = false
        for t in 0..<Params.maxTracks {
            queued[t] = Launcher.none
            trackStart[t] = 0
            if following[t] { following[t] = false }
        }
        sceneRow = -1
        sceneQueued = -1
    }

    /// Без игры тап ставит ожидание сразу (интерфейс), чтобы мигание было видно до PLAY.
    func setQueued(_ t: Int, _ v: Int) {
        queued[t] = v
    }
}
