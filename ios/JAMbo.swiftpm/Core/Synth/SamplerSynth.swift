import Foundation

// Sampler ↔ голоса синта: звук «mi:<n>» по ключу и перезапуск держащихся нот синта новым звуком дорожки.

extension Sampler {
    /// Движок синта по ключу звука (−1 — не синт).
    @inline(__always)
    func synthEngine(_ h: UInt64) -> Int {
        if h == 0 { return -1 }
        for e in 0..<SynthEngines.count where synthHash[e] == h { return e }
        return -1
    }

    /// Держащиеся ноты синта дорожки t — новым звуком дорожки (синт или сэмпл).
    func retriggerSynth(_ t: Int, _ now: Int64, _ last: Int) {
        guard let s = synth else { return }
        s.retrigger(t, now, upTo: last) { n, at, gate, mask, vals, live in
            one.pointee = Int16(n)
            for p in 0..<VoiceParam.count { scratch[p] = vals[p] }
            trigger(track: t, at: at, notes: one, count: 1, mask: mask, vals: scratch, hash: 0, gate: gate,
                    own: false, liveId: live, retrig: true)
        }
    }
}
