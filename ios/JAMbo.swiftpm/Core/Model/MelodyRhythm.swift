import Foundation

// Случайные партии мелодических дорожек (SHIFT + CHORD; docs/ai/sequencer.md, «Пианоролл»): роль дорожки
// определяется сама (движок, имя сэмпла, октава клавиатуры, CHORD, ARP); партии — по стилю проекта: Techno —
// TechnoRun.swift, остальные стили — StyleParts.swift и StyleRoles.swift.

public enum MelodyRhythm {
    /// Роль мелодической дорожки.
    public enum Role: Int, Sendable, CaseIterable { case bass, lead, keys, pad, arp }

    public static let roleNames: [String] = ["Bass", "Lead", "Keys", "Pad", "Arp"]

    /// Октава клавиатуры, с которой и ниже дорожка — BASS (C2 и ниже).
    public static let bassOctave: Int = 2

    static let bassWords: [String] = ["bass", "808", "sub", "reese"]
    /// PAD — пэды, подклады, текстуры и эффекты.
    static let padWords: [String] = ["pad", "atmo", "drone", "string", "ambient", "choir", "texture", "fx", "noise",
                                     "riser", "sweep", "soundscape", "swell"]
    /// Клавишные — LEAD без CHORD (не BASS в низкой октаве); KEYS — только в режиме CHORD.
    static let keysWords: [String] = ["chord", "keys", "piano", "stab", "organ", "rhodes", "epiano", "clav", "wurli"]
    /// LEAD — по имени и в низкой октаве (иначе октава C2 и ниже дала бы BASS).
    static let leadWords: [String] = ["lead", "pluck", "melody", "arp"]

    /// Типы партии в окне CHORD (SETTINGS → RANDOM → SHOW PART TYPE): BASS; LEAD — мелодия и клавишные (KEYS);
    /// PAD — пэды, подклады, текстуры, эффекты.
    public static let partNames: [String] = ["BASS", "LEAD", "PAD"]

    /// Номер типа партии роли (ARP — nil).
    public static func partIndex(_ r: Role) -> Int? {
        switch r {
        case .bass: return 0
        case .lead, .keys: return 1
        case .pad: return 2
        case .arp: return nil
        }
    }

    /// Роль с выбранным в окне CHORD типом партии part (−1 — сама): LEAD в режиме CHORD — KEYS; ARP не меняется.
    public static func role(_ auto: Role, part: Int, chord: Bool) -> Role {
        if auto == .arp || part < 0 { return auto }
        if part == 0 { return .bass }
        if part == 2 { return .pad }
        return chord ? .keys : .lead
    }

    /// Звук пэда: движок TEXTURE, GRANULAR или сэмпл со словом из padWords в имени файла (и без слова из bassWords).
    public static func isPadSound(sample: String, name: String) -> Bool {
        if let e = SynthKey.engine(sample) { return e == Jambo.texture || e == Jambo.granular }
        if sample.isEmpty { return false }
        let w: String = DrumRhythm.words(name).joined(separator: " ")
        return !bassWords.contains(where: { w.contains($0) }) && padWords.contains(where: { w.contains($0) })
    }

    /// Роль по звуку дорожки: ARP — арпеджиатор включён; звук пэда (TEXTURE, GRANULAR; сэмпл со словом pad, atmo… в
    /// имени файла name, не bass) — PAD и с CHORD, и без него (без CHORD — одна длинная нота вместо аккорда); другой
    /// звук в режиме CHORD — KEYS; SUB — BASS; сэмпл — по словам в имени (bass, lead…; клавишные без CHORD — LEAD);
    /// иначе по октаве клавиатуры: до C2 — BASS, выше — LEAD.
    public static func role(sample: String, name: String = "", octave: Int, chord: Bool, arp: Bool) -> Role {
        if arp { return .arp }
        if isPadSound(sample: sample, name: name) { return .pad }
        if chord { return .keys }
        if let e = SynthKey.engine(sample) {
            if e == Jambo.sub { return .bass }
        } else if !sample.isEmpty {
            let name: String = DrumRhythm.words(name).joined(separator: " ")
            if bassWords.contains(where: { name.contains($0) }) { return .bass }
            if leadWords.contains(where: { name.contains($0) }) { return .lead }
            // Клавишные без CHORD — LEAD (аккорды — только в режиме CHORD), и в низкой октаве.
            if keysWords.contains(where: { name.contains($0) }) { return .lead }
        }
        return octave <= bassOctave ? .bass : .lead
    }

    static func pick(_ items: [Int], _ weights: [Double], using g: inout Rng) -> Int {
        let total: Double = weights.reduce(0, +)
        var x: Double = Double.random(in: 0..<Swift.max(total, 0.000001), using: &g)
        for (i, w) in weights.enumerated() {
            if x < w { return items[i] }
            x -= w
        }
        return items.last ?? 0
    }
}
