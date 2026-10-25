import Foundation

// Проект после чтения (S9a, как normalizeDoc веба): размеры массивов и номера — в пределах, которые ждут
// секвенсор и UI; новые параметры дорожек, FX и мастера — значения по умолчанию.

extension Project {
    public mutating func repair() {
        if version < 3 { migrateSwing() }
        if version < 4 { migrateSynthKnobs() }
        version = Swift.max(version, 5)
        if !bpm.isFinite { bpm = 120 }
        bpm = Swift.min(Params.bpmMax, Swift.max(Params.bpmMin, bpm))
        scale = Project.clamp(scale, 0, Scales.all.count - 1)
        root = Project.clamp(root, 0, 11)
        fx = Params.fxDefaults().merging(fx) { _, v in v }
        master = MasterChain.defaultValues().merging(master) { _, v in v }
        if tracks.count > Params.maxTracks { tracks.removeLast(tracks.count - Params.maxTracks) }
        while tracks.count < Params.trackCount { tracks.append(Track(index: tracks.count)) }
        let n: Int = tracks.count
        for i in 0..<n { tracks[i].repair(tracks: n) }
        let names: [String] = ["MIX", "MST"]
        if chanSeqs.count > names.count { chanSeqs.removeLast(chanSeqs.count - names.count) }
        while chanSeqs.count < names.count { chanSeqs.append(Track.channel(names[chanSeqs.count])) }
        for k in 0..<names.count {
            chanSeqs[k].name = names[k]
            chanSeqs[k].repair(tracks: n)
        }
        masterEq.repair(tracks: n)
        if scenes.count > Params.patternSlots { scenes.removeLast(scenes.count - Params.patternSlots) }
        while scenes.count < Params.patternSlots { scenes.append(SceneRow()) }
        for k in 0..<scenes.count { scenes[k].repeats = Swift.max(1, scenes[k].repeats) }
        rows = Project.clamp(rows, 1, Params.patternSlots)
        arrStart = Project.clamp(arrStart, 0, Params.patternSlots - 1)
        for i in tracks.indices { tracks[i].repairBlocks() }
        arrange.repair()
    }

    /// Версия 3 (S12): Swing — значение дорожки; p-lock swing на шагах и назначения LFO/ENV на swing снимаются
    /// (у дорожек, MIX и MST, звуков перехода MIX). Velocity — прежний level, переносить нечего.
    mutating func migrateSwing() {
        let strip: (inout Track) -> Void = { t in
            t.assigns["swing"] = nil
            if t.home != nil { t.home!.assigns["swing"] = nil }
            for k in 0..<t.clips.count {
                guard var c = t.clips[k] else { continue }
                if c.src != nil { c.src!.assigns["swing"] = nil }
                for p in 0..<c.pages.count {
                    for s in 0..<c.pages[p].count {
                        c.pages[p][s].locks["swing"] = nil
                        if let sl = c.pages[p][s].soundLocks { c.pages[p][s].soundLocks = sl.filter { $0 != "swing" } }
                    }
                }
                t.clips[k] = c
            }
        }
        for i in 0..<tracks.count { strip(&tracks[i]) }
        for i in 0..<chanSeqs.count { strip(&chanSeqs[i]) }
    }

    static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
        return Swift.min(hi, Swift.max(lo, v))
    }

    /// Ключи сэмплов, на которые ссылается проект (звук и папки дорожек, свой звук шагов, маркеры нарезки);
    /// ключи синтов и встроенных таблиц («mi:…», «builtin:…») — не сэмплы.
    public var sampleKeys: Set<String> {
        var keys = Set<String>()
        for t in tracks {
            keys.insert(t.sample)
            keys.formUnion(t.folder.sampleKeys)
            keys.formUnion(t.slices.keys)
            // Переход MIX: звук старой дорожки у клипа PREV и свой звук дорожки, пока играет PREV.
            for snd in ([t.home] + t.clips.map { $0?.src }) {
                guard let snd = snd else { continue }
                keys.insert(snd.sample)
                keys.formUnion(snd.folder.sampleKeys)
                keys.formUnion(snd.slices.keys)
            }
            for c in t.clips {
                guard let c = c else { continue }
                for page in c.pages {
                    for s in page { if let k = s.sound { keys.insert(k) } }
                }
            }
        }
        return keys.filter { !$0.isEmpty && !$0.contains(":") }
    }
}

extension Project {
    /// Ключи WAV своих таблиц WTABLE (S11b4): у дорожек, в пресетах их папок, у звуков перехода MIX.
    public var tableKeys: Set<String> {
        var keys = Set<String>()
        let add: (String?) -> Void = { t in
            if let t = t, let u = WavetableKey.parseUser(t) { keys.insert(u.wav) }
        }
        for t in tracks {
            var sounds: [TrackSound] = [t.sound]
            if let h = t.home { sounds.append(h) }
            for c in t.clips { if let s = c?.src { sounds.append(s) } }
            for snd in sounds {
                add(snd.table)
                for it in snd.folder.items { add(it.preset?.table) }
            }
        }
        return keys
    }
}

extension Track {
    /// Дорожка (или MIX, MST) проекта из n дорожек.
    mutating func repair(tracks n: Int) {
        params = Params.defaults().merging(params) { _, v in v }
        // Звук движка, которого нет (Mutable Instruments, mi:0…mi:15), — пустой (S12).
        if SynthKey.isRemoved(sample) { sample = "" }
        if let h = home, SynthKey.isRemoved(h.sample) { home!.sample = "" }
        for k in 0..<clips.count {
            if let s = clips[k]?.src, SynthKey.isRemoved(s.sample) { clips[k]!.src!.sample = "" }
        }
        if clips.count > Params.patternSlots { clips.removeLast(clips.count - Params.patternSlots) }
        while clips.count < Params.patternSlots { clips.append(nil) }
        for k in 0..<clips.count where clips[k] != nil { clips[k]!.repair() }
        slot = Project.clamp(slot, 0, Params.patternSlots - 1)
        open = Project.clamp(open, 0, Params.patternSlots - 1)
        folder.index = Project.clamp(folder.index, -1, folder.items.count - 1)
        if !vol.isFinite { vol = Params.volDef }
        trim = trim.isFinite ? Swift.min(0, Swift.max(Params.volMin, trim)) : 0
        eq.repair(tracks: n)
    }
}

extension Clip {
    mutating func repair() {
        if pages.isEmpty { pages = [Track.emptyPage()] }
        if pages.count > Params.maxPages { pages.removeLast(pages.count - Params.maxPages) }
        let n: Int = Params.stepsPerPage
        for p in 0..<pages.count {
            if pages[p].count > n { pages[p].removeLast(pages[p].count - n) }
            while pages[p].count < n { pages[p].append(Step()) }
            for s in 0..<n { pages[p][s].repair() }
        }
        length = Project.clamp(length, 1, pages.count * n)
        playTo = Project.clamp(playTo, 0, pages.count - 1)
        playFrom = Project.clamp(playFrom, 0, playTo)
        if let s = scale { scale = Project.clamp(s, 0, Scales.all.count - 1) }
        if let r = root { root = Project.clamp(r, 0, 11) }
        if let r = rate { rate = r == 0 ? nil : Project.clamp(r, -4, 1) }
    }
}

extension Step {
    /// Длины и velocity нот — параллельно notes (иначе снимаются); при lens len — самая длинная.
    mutating func repair() {
        len = Swift.max(1, len)
        // Пресет-лок движка, которого нет, снимается вместе с его p-lock: шаг играет звук дорожки.
        if let snd = sound, SynthKey.isRemoved(snd) {
            for k in soundLocks ?? [] { locks[k] = nil }
            sound = nil
            soundLocks = nil
        }
        if let l = lens {
            if l.count == notes.count && !l.isEmpty {
                let fixed: [Int] = l.map { Swift.max(1, $0) }
                lens = fixed
                len = fixed.max() ?? len
            } else {
                lens = nil
            }
        }
        if let v = vels, v.count != notes.count || v.isEmpty { vels = nil }
    }
}

extension Eq {
    /// Места под полосы; номера в пределах таблиц; источник Dynamic — существующая дорожка (иначе OFF).
    mutating func repair(tracks n: Int) {
        if bands.count > EqSpec.bands { bands.removeLast(bands.count - EqSpec.bands) }
        while bands.count < EqSpec.bands { bands.append(nil) }
        for k in 0..<bands.count {
            guard var b = bands[k] else { continue }
            b.type = Project.clamp(b.type, 0, EqSpec.types.count - 1)
            b.slope = Project.clamp(b.slope, 0, EqSpec.slopes.count - 1)
            b.ms = Project.clamp(b.ms, 0, EqSpec.msModes.count - 1)
            if b.dyn > n || b.dyn < -1 { b.dyn = -1 }
            bands[k] = b
        }
    }
}
