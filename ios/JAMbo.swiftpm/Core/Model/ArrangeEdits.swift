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

    /// SPLIT в меню диапазона: блоки всех дорожек разрезаются на границах [a, b) (правая часть продолжает клип).
    public mutating func splitArrange(_ a: Int, _ b: Int) {
        for i in tracks.indices {
            tracks[i].splitArrange(at: a)
            tracks[i].splitArrange(at: b)
        }
    }

    public mutating func setTrackColor(_ i: Int, _ color: Int) {
        guard tracks.indices.contains(i), color >= 0, color < ArrPalette.count else { return }
        tracks[i].color = color
    }

    /// Маркер секции на позиции at (на занятой позиции — заменяет прежний). Номер маркера.
    @discardableResult
    public mutating func addMarker(at: Int, name: String) -> Int {
        let x: Int = Swift.max(0, at)
        arrange.markers.removeAll { $0.at == x }
        let m = ArrMarker(at: x, name: Project.markerName(name))
        arrange.markers.append(m)
        arrange.markers.sort { $0.at < $1.at }
        return arrange.markers.firstIndex(of: m) ?? 0
    }

    @discardableResult
    public mutating func moveMarker(_ k: Int, to at: Int) -> Int {
        guard arrange.markers.indices.contains(k) else { return k }
        var m: ArrMarker = arrange.markers.remove(at: k)
        m.at = Swift.max(0, at)
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

    /// Секция на позиции x: последний маркер не правее x (nil — до первого маркера).
    public func section(at x: Int) -> Int? {
        return arrange.markers.lastIndex { $0.at <= x }
    }

    /// Диапазон петли (границы в любом порядке); пустой диапазон петлю выключает.
    public mutating func setLoop(_ a: Int, _ b: Int) {
        arrange.loopFrom = Swift.max(0, Swift.min(a, b))
        arrange.loopTo = Swift.max(0, Swift.max(a, b))
        if !arrange.hasLoop { arrange.loop = false }
    }

    public static func markerName(_ s: String) -> String {
        return String(s.trimmingCharacters(in: .whitespaces).prefix(12))
    }
}
