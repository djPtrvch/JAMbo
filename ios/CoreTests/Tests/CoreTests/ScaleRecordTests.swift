import XCTest
@testable import Core

/// Ноты клавиш гаммы = ноты, записанные в шаг и отданные в колбэк (снимок секвенсора).
final class ScaleRecordTests: XCTestCase {
    func testKeyNotesReachSequencer() {
        var outOfRange: [String] = []
        var mismatch = 0
        for scale in 0..<Scales.all.count {
            let steps: [Int] = Scales.all[scale].steps
            for root in 0..<12 {
                for octave in Scales.octaveMin...Scales.topOctave(scale: scale, root: root, octaves: 2, chord: true) {
                    let count: Int = Scales.keyCount(scale: scale, octaves: 2)
                    let keys: [Int] = (0..<count).map { Scales.note(scale: scale, root: root, octave: octave, degree: $0) }
                    for n in keys where !steps.contains(Scales.wrap(n - root, 12)) { mismatch += 1 }
                    let chordTop: Int = Scales.chord(scale: scale, root: root, octave: octave, degree: count - 1).max()!
                    if chordTop > 127 { outOfRange.append("\(Scales.all[scale].short) root \(root) oct \(octave)") }
                    // Запись в шаг и снимок секвенсора.
                    var p = Project()
                    var t = p.tracks[0]
                    let k: Int = min(7, keys.count - 1)
                    t.recordNotes(0, Array(keys[0...k]), merge: false, overdub: false, velocity: nil)
                    p.tracks[0] = t
                    let d = SeqSnapshot(p)
                    let got: [Int] = (0...k).map { Int(d.data.notes[$0]) }
                    XCTAssertEqual(got, Array(keys[0...k]))
                }
            }
        }
        XCTAssertEqual(mismatch, 0, "клавиши — только ноты гаммы")
        XCTAssertEqual(outOfRange, [], "до topOctave ноты и аккорды — не выше 127")
        XCTAssertEqual(Scales.topOctave(scale: 0, root: 0, octaves: 2, chord: false), 7, "C: верх C9 = 120")
        XCTAssertEqual(Scales.topOctave(scale: 0, root: 11, octaves: 2, chord: false), 6, "B: на октаву ниже")
    }
}
