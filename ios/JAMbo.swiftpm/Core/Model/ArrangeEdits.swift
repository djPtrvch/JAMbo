import Foundation

// Правки аранжировки (S15, docs/ai/arranger.md). Блоки одной дорожки не перекрываются и лежат по порядку: новый или
// перенесённый блок заменяет перекрытую часть, сдвигает остальные только INSERT. Каждое действие — одна запись UNDO
// (вызывает UI).

extension Track {
    /// Длина прохода клипа k в шагах транспорта (с учётом скорости); пустая ячейка — такт.
    public func clipSteps(_ k: Int) -> Int {
        guard clipFilled(k), let c = clips[k] else { return ArrGrid.stepsPerBar }
        return Swift.max(1, c.passTicks)
    }

    /// Убрать участок [from, to) таймлайна: блоки внутри уходят, перекрытые укорачиваются, блок шире участка
    /// делится на две части (правая продолжает клип с того же места — offset).
    public mutating func clearArrange(from: Int, to: Int) {
        if to <= from { return }
        var out: [ArrBlock] = []
        for b in blocks {
            if b.end <= from || b.start >= to {
                out.append(b)
                continue
            }
            if b.start < from {
                var left: ArrBlock = b
                left.length = from - b.start
                out.append(left)
            }
            if b.end > to {
                let cut: Int = to - b.start
                out.append(ArrBlock(clip: b.clip, start: to, length: b.end - to, offset: b.offset + cut))
            }
        }
        blocks = out
    }

    /// Поставить блок: перекрытая часть других заменяется. Номер блока после сортировки.
    @discardableResult
    public mutating func placeBlock(_ b: ArrBlock) -> Int {
        var n: ArrBlock = b
        n.start = Swift.max(0, n.start)
        n.length = Swift.max(1, n.length)
        clearArrange(from: n.start, to: n.end)
        blocks.append(n)
        sortBlocks()
        return blocks.firstIndex(of: n) ?? 0
    }

    /// Новый блок клипа k на позиции at (длина — проход клипа).
    @discardableResult
    public mutating func addBlock(clip k: Int, at: Int) -> Int {
        return placeBlock(ArrBlock(clip: k, start: at, length: clipSteps(k)))
    }

    /// Перенос блока i на начало start.
    @discardableResult
    public mutating func moveBlock(_ i: Int, to start: Int) -> Int {
        guard blocks.indices.contains(i) else { return i }
        var b: ArrBlock = blocks.remove(at: i)
        b.start = Swift.max(0, start)
        return placeBlock(b)
    }

    /// Края блока i: новые начало и конец (левый край сдвигает и место в клипе — offset; длиннее клипа — повтор).
    @discardableResult
    public mutating func resizeBlock(_ i: Int, start: Int, end: Int) -> Int {
        guard blocks.indices.contains(i) else { return i }
        var b: ArrBlock = blocks.remove(at: i)
        let s: Int = Swift.max(0, Swift.min(start, end - 1))
        b.offset += s - b.start
        b.start = s
        b.length = Swift.max(1, end - s)
        return placeBlock(b)
    }

    public mutating func deleteBlock(_ i: Int) {
        if blocks.indices.contains(i) { blocks.remove(at: i) }
    }

    /// DUPLICATE: копия блока i сразу справа от него.
    @discardableResult
    public mutating func duplicateBlock(_ i: Int) -> Int {
        guard blocks.indices.contains(i) else { return i }
        var b: ArrBlock = blocks[i]
        b.start = b.end
        return placeBlock(b)
    }

    /// PASTE в меню блока: скопированный блок — сразу после блока i.
    @discardableResult
    public mutating func pasteBlock(after i: Int, _ b: ArrBlock) -> Int {
        guard blocks.indices.contains(i) else { return i }
        var n: ArrBlock = b
        n.start = blocks[i].end
        return placeBlock(n)
    }

    /// Блоки, которые начинаются не раньше x, сдвигаются на d (блок, через который проходит x, сначала делится).
    public mutating func shiftArrange(after x: Int, by d: Int) {
        if d == 0 { return }
        splitBlock(at: x)
        for k in blocks.indices where blocks[k].start >= x { blocks[k].start += d }
        sortBlocks()
    }

    /// INSERT: блок клипа k в точку at, блоки этой дорожки правее сдвигаются на его длину.
    @discardableResult
    public mutating func insertBlock(clip k: Int, at: Int) -> Int {
        let x: Int = Swift.max(0, at)
        let len: Int = clipSteps(k)
        shiftArrange(after: x, by: len)
        return placeBlock(ArrBlock(clip: k, start: x, length: len))
    }

    /// Протяжка края вставленного блока i при INSERT: новая длина, блоки правее сдвигаются вслед.
    @discardableResult
    public mutating func resizeInserted(_ i: Int, length: Int) -> Int {
        guard blocks.indices.contains(i) else { return i }
        let b: ArrBlock = blocks[i]
        let n: Int = Swift.max(1, length)
        let d: Int = n - b.length
        if d == 0 { return i }
        if d > 0 {
            shiftArrange(after: b.end, by: d)
        } else {
            clearArrange(from: b.start + n, to: b.end)
            for k in blocks.indices where blocks[k].start >= b.end { blocks[k].start += d }
            sortBlocks()
        }
        var m: ArrBlock = b
        m.length = n
        guard let j = blocks.firstIndex(where: { $0.start == b.start && $0.clip == b.clip }) else { return placeBlock(m) }
        blocks[j] = m
        return j
    }

    /// Блоки дорожки ещё раз — после последнего (DUPLICATE в меню дорожки).
    public mutating func duplicateBlocks() {
        guard let first = blocks.first, let last = blocks.map({ $0.end }).max() else { return }
        let d: Int = last - first.start
        let copy: [ArrBlock] = blocks.map { ArrBlock(clip: $0.clip, start: $0.start + d, length: $0.length, offset: $0.offset) }
        blocks.append(contentsOf: copy)
        sortBlocks()
    }

    /// Номера клипов в блоках после правки строк сетки (nil — клипа нет, блок удаляется).
    public mutating func remapBlocks(_ map: (Int) -> Int?) {
        var out: [ArrBlock] = []
        for var b in blocks {
            guard let k = map(b.clip) else { continue }
            b.clip = k
            out.append(b)
        }
        blocks = out
    }

    /// Конец последнего блока (0 — блоков нет).
    public var arrangeEnd: Int { return blocks.map { $0.end }.max() ?? 0 }

    /// После чтения: клипы в пределах, длины ≥ 1, по порядку, без перекрытий; цвет в палитре.
    public mutating func repairBlocks() {
        if color < 0 || color >= ArrPalette.count { color = ArrPalette.defaultColor }
        let saved: [ArrBlock] = blocks.filter { $0.clip >= 0 && $0.clip < Params.patternSlots }
        blocks = []
        for b in saved.sorted(by: { $0.start < $1.start }) { placeBlock(b) }
    }

    /// Разрезать блок, через который проходит x (на краю блока — ничего).
    public mutating func splitArrange(at x: Int) {
        splitBlock(at: x)
        sortBlocks()
    }

    private mutating func splitBlock(at x: Int) {
        guard let k = blocks.firstIndex(where: { $0.start < x && $0.end > x }) else { return }
        let b: ArrBlock = blocks[k]
        let cut: Int = x - b.start
        blocks[k].length = cut
        blocks.append(ArrBlock(clip: b.clip, start: x, length: b.end - x, offset: b.offset + cut))
    }

    private mutating func sortBlocks() {
        blocks.sort { $0.start < $1.start }
    }
}

extension Project {
    /// Конец аранжировки: конец последнего блока всех дорожек.
    public var arrangeEnd: Int { return tracks.map { $0.arrangeEnd }.max() ?? 0 }

    /// PASTE в меню дорожки: блоки заменяют блоки дорожки i (в том числе пустой).
    public mutating func pasteBlocks(_ i: Int, _ list: [ArrBlock]) {
        guard tracks.indices.contains(i) else { return }
        tracks[i].blocks = []
        for b in list { tracks[i].placeBlock(b) }
    }

    /// SPLIT в меню диапазона: блоки дорожки t разрезаются на границах [a, b) (правая часть продолжает клип).
    public mutating func splitArrange(track t: Int, _ a: Int, _ b: Int) {
        guard tracks.indices.contains(t) else { return }
        tracks[t].splitArrange(at: a)
        tracks[t].splitArrange(at: b)
    }

    public mutating func setTrackColor(_ i: Int, _ color: Int) {
        guard tracks.indices.contains(i), color >= 0, color < ArrPalette.count else { return }
        tracks[i].color = color
    }

    /// Маркер секции на позиции at (на занятой позиции — заменяет прежний). Номер маркера.
    @discardableResult
    public mutating func addMarker(at: Int, name: String, end: Int? = nil) -> Int {
        let x: Int = Swift.max(0, at)
        arrange.markers.removeAll { $0.at == x }
        var e: Int? = end
        if let v = e, v <= x { e = nil }
        let m = ArrMarker(at: x, name: Project.markerName(name), end: e)
        arrange.markers.append(m)
        arrange.markers.sort { $0.at < $1.at }
        return arrange.markers.firstIndex(of: m) ?? 0
    }

    @discardableResult
    public mutating func moveMarker(_ k: Int, to at: Int) -> Int {
        guard arrange.markers.indices.contains(k) else { return k }
        var m: ArrMarker = arrange.markers.remove(at: k)
        let x: Int = Swift.max(0, at)
        // Секция с концом переезжает целиком.
        if let e = m.end { m.end = e + (x - m.at) }
        m.at = x
        arrange.markers.removeAll { $0.at == m.at }
        arrange.markers.append(m)
        arrange.markers.sort { $0.at < $1.at }
        return arrange.markers.firstIndex(of: m) ?? 0
    }

    public mutating func renameMarker(_ k: Int, _ name: String) {
        if arrange.markers.indices.contains(k) { arrange.markers[k].name = Project.markerName(name) }
    }

    public mutating func setMarkerColor(_ k: Int, _ color: Int) {
        guard arrange.markers.indices.contains(k), color >= 0, color < ArrPalette.count else { return }
        arrange.markers[k].color = color
    }

    public mutating func deleteMarker(_ k: Int) {
        if arrange.markers.indices.contains(k) { arrange.markers.remove(at: k) }
    }

    /// Секция на позиции x: последний маркер не правее x, если x до конца его секции (nil — секции нет).
    public func section(at x: Int) -> Int? {
        guard let k = arrange.markers.lastIndex(where: { $0.at <= x }) else { return nil }
        let m: ArrMarker = arrange.markers[k]
        if let e = sectionEnd(k), x >= e { return nil }
        return m.at <= x ? k : nil
    }

    /// Конец секции k: свой конец (не дальше следующего маркера) или следующий маркер; nil — до конца.
    public func sectionEnd(_ k: Int) -> Int? {
        let list: [ArrMarker] = arrange.markers
        guard k >= 0 && k < list.count else { return nil }
        let next: Int? = k + 1 < list.count ? list[k + 1].at : nil
        if let e = list[k].end {
            if let n = next { return Swift.min(e, n) }
            return e
        }
        return next
    }

    /// Диапазон петли (границы в любом порядке); пустой диапазон петлю выключает.
    public mutating func setLoop(_ a: Int, _ b: Int) {
        arrange.loopFrom = Swift.max(0, Swift.min(a, b))
        arrange.loopTo = Swift.max(0, Swift.max(a, b))
        if !arrange.hasLoop { arrange.loop = false }
    }

    /// TO ARRANGE (S15e): строка k — в аранжировку с позиции at (nil — в конец аранжировки). Длина строки — самый
    /// длинный клип × N (N — повторы строки; LOOP ROW — один проход); все дорожки заполняют её блоками длиной в свой
    /// клип (короткий повторяется, последний блок — до конца строки; пустая ячейка — блоками по такту: допишут паттерн —
    /// зазвучит). Участок дорожек и секции в нём заменяются; секция — имя строки на длину строки. Конец участка; nil —
    /// в строке нет клипов.
    @discardableResult
    public mutating func rowToArrange(_ k: Int, at: Int?) -> Int? {
        guard k >= 0 && k < scenes.count else { return nil }
        let reps: Int = rowLoop ? 1 : Swift.max(1, scenes[k].repeats)
        var lens: [Int] = [Int](repeating: 0, count: tracks.count)
        var longest: Int = 0
        for t in tracks.indices {
            lens[t] = tracks[t].clipSteps(k)
            if tracks[t].clipFilled(k) { longest = Swift.max(longest, lens[t]) }
        }
        if longest == 0 { return nil }
        let start: Int = Swift.max(0, at ?? arrangeEnd)
        let end: Int = start + longest * reps
        for t in tracks.indices where lens[t] > 0 {
            tracks[t].clearArrange(from: start, to: end)
            var x: Int = start
            while x < end {
                let n: Int = Swift.min(lens[t], end - x)
                tracks[t].placeBlock(ArrBlock(clip: k, start: x, length: n))
                x += lens[t]
            }
        }
        arrange.markers.removeAll { $0.at >= start && $0.at < end }
        addMarker(at: start, name: sceneName(k), end: end)
        return end
    }

    public static func markerName(_ s: String) -> String {
        return String(s.trimmingCharacters(in: .whitespaces).prefix(12))
    }
}
