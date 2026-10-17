import XCTest
@testable import Core

/// Синт на дорожке (#38): ключи «mi:<n>», сетка ручек движка.
final class SynthTests: XCTestCase {
    func testSynthKey() {
        XCTAssertEqual(SynthKey.key(6), "mi:6")
        XCTAssertEqual(SynthKey.engine("mi:0"), 0)
        XCTAssertEqual(SynthKey.engine("mi:7"), 7)
        XCTAssertNil(SynthKey.engine("mi:8"))
        XCTAssertNil(SynthKey.engine("mi:x"))
        XCTAssertNil(SynthKey.engine(""))
        XCTAssertNil(SynthKey.engine("3f2a9c"))
    }

    func testSynthGrid() {
        let va = Params.grid(sound: "mi:0")
        XCTAssertEqual(va[0].id, "harm")
        XCTAssertEqual(va[0].label, "Detune")
        XCTAssertEqual(va[4].id, "timbre")
        XCTAssertEqual(va[4].label, "Pulse width")
        XCTAssertEqual(va[8].id, "morph")
        XCTAssertEqual(va[12].id, "level")
        XCTAssertEqual(va[1].id, "attack")
        XCTAssertEqual(Params.grid(sound: "")[0].id, "pitch")
        // CHORDS: Harmonics — 11 пунктов, значение — середина пункта.
        let ch = Params.grid(sound: "mi:6")[0]
        XCTAssertEqual(ch.steps, 11)
        XCTAssertEqual(ch.format(ch.fromNorm(0.4)), "m7")
        XCTAssertEqual(ch.fromNorm(0), 100.0 / 22, accuracy: 1e-9)
        XCTAssertEqual(Params.grid(sound: "mi:7")[0].format(50), "Phoneme")
    }

    func testDefaultsAndSetSynth() {
        var t = Track(index: 0)
        XCTAssertEqual(t.params["harm"], 50)
        XCTAssertEqual(t.params["morph"], 50)
        t.setSynth(3)
        XCTAssertEqual(t.sample, "mi:3")
        XCTAssertEqual(Params.grid(sound: t.sample)[0].label, "Formant ratio")
    }
}
