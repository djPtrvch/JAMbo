import SwiftUI

/// Аранжировщик (S15d): маркеры секций, петля, INSERT. Каждое действие — одна запись UNDO; перетаскивание маркера
/// и протяжка петли — внутри жеста (beginGesture / endGesture).
extension AppModel {
    // MARK: — маркеры

    /// ADD SECTION в меню диапазона: секция ровно на выделенный диапазон и окно с именем.
    func arrSectionAtRange(anchor: CGPoint) {
        let at: Int = project.arrange.loopFrom
        let end: Int = project.arrange.loopTo
        var k: Int = 0
        edit { p in k = p.addMarker(at: at, name: "", end: end) }
        arrMenu = .marker(index: k, anchor: anchor)
    }

    /// Перетаскивание маркера (внутри жеста): новое место с магнитом; номер маркера после сортировки.
    func arrMoveMarker(_ k: Int, to x: Int) -> Int {
        let list: [ArrMarker] = project.arrange.markers
        guard k >= 0 && k < list.count else { return k }
        let at: Int = project.arrange.snapped(x)
        if list[k].at == at { return k }
        var i: Int = k
        edit { p in i = p.moveMarker(k, to: at) }
        return i
    }

    func arrMarker(_ k: Int) -> ArrMarker? {
        let list: [ArrMarker] = project.arrange.markers
        return k >= 0 && k < list.count ? list[k] : nil
    }

    func arrRenameMarker(_ k: Int, _ name: String) {
        guard let m = arrMarker(k), m.name != Project.markerName(name) else { return }
        edit { p in p.renameMarker(k, name) }
    }

    func arrSetMarkerColor(_ k: Int, _ c: Int) {
        edit { p in p.setMarkerColor(k, c) }
    }

    func arrDeleteMarker(_ k: Int) {
        edit { p in p.deleteMarker(k) }
    }

    /// SPLIT: блоки выбранной дорожки разрезаются по краям выделенного диапазона.
    func arrSplitRange() {
        let a: Arrangement = project.arrange
        guard a.hasLoop, channel == .track else { return }
        let t: Int = selectedTrack
        edit { p in p.splitArrange(track: t, a.loopFrom, a.loopTo) }
        arrSel = nil
    }

    /// TRIM (ножницы, решение пользователя): блок под курсором разрезается на две части — у выбранного блока (его
    /// дорожка), иначе у выбранной дорожки.
    func arrTrim() {
        let t: Int = arrSel?.track ?? (channel == .track ? selectedTrack : -1)
        guard t >= 0 && t < project.tracks.count else { return }
        let x: Int = arrNow
        guard project.tracks[t].blocks.contains(where: { $0.start < x && $0.end > x }) else { return }
        edit { p in p.tracks[t].splitArrange(at: x) }
        arrSel = nil
    }

    // MARK: — петля

    /// Диапазон петли (внутри жеста протяжки): границы уже с магнитом; пустой — петля выключена.
    func arrSetLoop(_ a: Int, _ b: Int) {
        let lo: Int = min(a, b)
        let hi: Int = max(a, b)
        let cur: Arrangement = project.arrange
        if cur.loopFrom == lo && cur.loopTo == hi { return }
        edit { p in p.setLoop(lo, hi) }
    }

    // MARK: — INSERT

    func toggleArrInsert() {
        arrInsert.toggle()
        arrInserted = nil
        arrMenu = nil
    }

    /// Вставка клипа k в точку x дорожки t: блоки дорожки правее сдвигаются на его длину.
    func arrInsertBlock(track t: Int, clip k: Int, at x: Int) {
        guard t >= 0 && t < project.tracks.count else { return }
        let at: Int = project.arrange.snapped(x)
        var i: Int = 0
        edit { p in i = p.tracks[t].insertBlock(clip: k, at: at) }
        let sel = ArrSel(track: t, block: i)
        arrSel = sel
        arrInserted = sel
    }

    /// Протяжка правого края вставленного блока (внутри жеста): длина с магнитом, сдвиг пересчитывается от base.
    func arrResizeInserted(track t: Int, base: [ArrBlock], index: Int, end: Int) {
        guard t >= 0 && t < project.tracks.count, index >= 0, index < base.count else { return }
        let b: ArrBlock = base[index]
        var e: Int = project.arrange.snapped(end)
        if e <= b.start { e = b.start + (project.arrange.snap ? project.arrange.gridSteps : 1) }
        var i: Int = index
        edit { p in
            p.tracks[t].blocks = base
            i = p.tracks[t].resizeInserted(index, length: e - b.start)
        }
        let sel = ArrSel(track: t, block: i)
        arrSel = sel
        arrInserted = sel
    }

    // MARK: — SEND TO ARRANGE (S15e)

    /// Журнал запусков в сетке за последние 32 такта — блоками в конец аранжировки или с курсора; одна запись UNDO.
    func sendToArrange(atCursor: Bool) {
        let r = live.journal.take(now: max(0, live.tick))
        let at: Int? = atCursor ? arrCursor : nil
        edit { p in p.sendToArrange(r.blocks, length: r.length, at: at) }
    }

    // MARK: — запись с AUTO (S15e)

    /// Идёт запись аранжировки: REC + PLAY + AUTO.
    var arrRecording: Bool { return recOn && playing && arrAuto }

    func toggleArrAuto() {
        arrAuto.toggle()
        syncArrRecord()
    }

    /// Запись начинается и кончается по REC, PLAY и AUTO: from — позиция курсора на PLAY (иначе — текущая);
    /// на конце отрезки ложатся в проект одной записью UNDO.
    func syncArrRecord(from: Int? = nil) {
        let want: Bool = arrRecording
        if want && !live.recorder.active {
            live.beginRecord(project, at: from ?? live.arrPos, arrange: from != nil && arrangeView)
        } else if !want && live.recorder.active {
            let segs: [ArrRecorder.Seg] = live.finishRecord()
            if !segs.isEmpty { edit { p in p.applyRecording(segs) } }
            flushAutoTakes(all: true)
        }
    }
}
