import Foundation

// IMPORT строк другого проекта (решения пользователя): все строки проекта с тригами — в свободные строки сетки
// после последней заполненной (строка 1 не занимается: при одной строке добавляется новая), сколько поместится.
// Клип дорожки i другого проекта — в столбец i; звук привязан к клипу: если звук столбца другой, клип несёт свой
// (Clip.src — сэмпл или синт, ручки, папка, нарезка, таблица, назначения LFO/ENV, EQ дорожки). Дорожек меньше —
// добавляются (до Params.maxTracks) со звуком дорожки другого проекта. Гамма, нота и FX — свои у каждого клипа.

extension Clip {
    /// Есть ли в клипе триги.
    public var hasTrigs: Bool {
        return pages.contains { $0.contains { $0.on } }
    }
}

extension Project {
    /// Строка k другого проекта не пустая (у какой-нибудь дорожки триги).
    func rowHasTrigs(_ k: Int) -> Bool {
        return tracks.contains { t in t.clipFilled(k) && t.clips[k]!.hasTrigs }
    }

    /// Свои строки после последней строки с тригами (не первая), свободные (без тригов); не хватает — новые.
    func importTargets(_ need: Int) -> [Int] {
        let lim: Int = rowLimit
        var last: Int = 0
        for k in 0..<lim where rowHasTrigs(k) { last = k }
        var out: [Int] = []
        var k: Int = last + 1
        while out.count < need && k < lim {
            if !rowHasTrigs(k) { out.append(k) }
            k += 1
        }
        return out
    }

    /// Импорт строк other: возвращает, сколько строк встало (0 — в other нет строк с тригами или нет места).
    @discardableResult
    public mutating func importRows(from other: Project) -> Int {
        let src: [Int] = (0..<other.visibleRows).filter { other.rowHasTrigs($0) }
        let dst: [Int] = importTargets(src.count)
        let n: Int = Swift.min(src.count, dst.count)
        if n == 0 { return 0 }
        // Дорожки other, у которых есть что ставить, — столбцы; недостающие добавляются со звуком дорожки other.
        var used: Int = 0
        for i in other.tracks.indices where src.prefix(n).contains(where: { r in
            other.tracks[i].clipFilled(r) && other.tracks[i].clips[r]!.hasTrigs
        }) {
            used = i + 1
        }
        while tracks.count < Swift.min(used, Params.maxTracks) {
            var t = Track(index: tracks.count)
            let o: Track = other.tracks[tracks.count]
            t.sound = o.home ?? o.sound
            t.name = o.name
            t.vol = o.vol
            t.stopped = true
            tracks.append(t)
        }
        for j in 0..<n {
            let r: Int = src[j]
            let k: Int = dst[j]
            for i in other.tracks.indices where i < tracks.count {
                let o: Track = other.tracks[i]
                guard var c = o.clipCopy(r), c.hasTrigs else { continue }
                // Звук, которым клип звучал в other; совпадает со звуком столбца — свой не нужен.
                let snd: TrackSound = c.src ?? (o.home ?? o.sound)
                let own: TrackSound = tracks[i].home ?? tracks[i].sound
                c.src = snd == own ? nil : snd
                if c.scale == nil { c.scale = other.scale }
                if c.root == nil { c.root = other.root }
                if c.fx == nil { c.fx = other.fx }
                tracks[i].setClip(k, c)
            }
            scenes[k] = other.scenes[r]
            rows = Swift.max(rows, k + 1)
        }
        // Имена сэмплов и их ноты — из other, если своих нет.
        for (key, name) in other.files where files[key] == nil { files[key] = name }
        for (key, note) in other.roots where roots[key] == nil { roots[key] = note }
        fillRows()
        return n
    }
}
