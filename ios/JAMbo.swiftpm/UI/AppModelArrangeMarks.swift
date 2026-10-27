import SwiftUI

/// Аранжировщик (S15d): маркеры секций, петля, INSERT. Каждое действие — одна запись UNDO; перетаскивание маркера
/// и протяжка петли — внутри жеста (beginGesture / endGesture).
extension AppModel {
    // MARK: — маркеры

    /// Шаг таймлайна под точкой (координаты таймлайна).
    private func arrStepAt(_ anchor: CGPoint) -> Int {
        let m: ArrMetrics = arrMetrics(arrTimelineFrame.size)
        return max(0, Int(m.step(at: anchor.x).rounded(.down)))
    }

    /// Секция под точкой (nil — нет).
    func arrSectionAt(anchor: CGPoint) -> Int? {
        return project.section(at: arrStepAt(anchor))
    }

    /// Диапазон под точкой таймлайна: выделенный, если точка в нём, иначе секция под ней, иначе такт.
    private func arrRangeAt(_ anchor: CGPoint) -> (from: Int, to: Int) {
        let x: Int = arrStepAt(anchor)
        let a: Arrangement = project.arrange
        if a.hasLoop && x >= a.loopFrom && x < a.loopTo { return (a.loopFrom, a.loopTo) }
        if let k = project.section(at: x) {
            let at: Int = project.arrange.markers[k].at
            return (at, project.sectionEnd(k) ?? at + ArrMetrics.stepsPerBar)
        }
        let bar: Int = ArrMetrics.stepsPerBar
        let s: Int = x / bar * bar
        return (s, s + bar)
    }

    /// ADD SECTION в меню линейки: новая секция на диапазоне под пальцем (выделенном или такте) и её окно (имя).
    func arrSectionHere(anchor: CGPoint) {
        let r = arrRangeAt(anchor)
        var k: Int = 0
        edit { p in k = p.addMarker(at: r.from, name: "", end: r.to) }
        arrMenu = .marker(index: k, anchor: anchor)
    }

    /// SPLIT в меню линейки: блоки выбранной дорожки режутся по краям диапазона под пальцем.
    func arrSplitAt(anchor: CGPoint) {
        let r = arrRangeAt(anchor)
        guard channel == .track else { return }
        let t: Int = selectedTrack
        edit { p in p.splitArrange(track: t, r.from, r.to) }
        arrSel = nil
    }

    /// Край секции k за пальцем (левый — начало, правый — конец; с магнитом; внутри жеста — одна запись UNDO).
    func arrMarkerEdge(_ k: Int, left: Bool, to x: Int) {
        let list: [ArrMarker] = project.arrange.markers
        guard k >= 0 && k < list.count else { return }
        let v: Int = project.arrange.snapped(x)
        if left {
            if list[k].at != v { edit { p in p.setMarkerStart(k, v) } }
        } else if project.sectionEnd(k) != v {
            edit { p in p.setMarkerEnd(k, v) }
        }
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

    // MARK: — запись аранжировки из сетки и запись ручек

    /// Идёт запись аранжировки: кнопка записи под STEPS сетки включена и играет сетка (не таймлайн).
    var arrRecording: Bool { return arrRecArm && playing && !arrPlay }

    /// Идёт запись ручек в кривые: REC + PLAY + AUTO при игре по таймлайну.
    var arrKnobRec: Bool { return recOn && playing && arrAuto && arrPlay }

    /// Играет таймлайн: клипы и строки в сетке не запускаются (сетка и аранжировщик разделены).
    var timelineLock: Bool { return playing && arrPlay }

    func toggleArrAuto() {
        arrAuto.toggle()
        syncArrRecord()
    }

    func toggleArrRec() {
        arrRecArm.toggle()
        syncArrRecord()
    }

    /// Запись начинается и кончается по кнопке записи и PLAY: from — позиция курсора на PLAY (иначе — текущая);
    /// на конце отрезки ложатся в проект одной записью UNDO, повороты ручек — в кривые до конца записи (ручки —
    /// прежние). Запись ручек кончилась — куски в кривые.
    func syncArrRecord(from: Int? = nil) {
        let want: Bool = arrRecording
        if want && !live.recorder.active {
            live.beginRecord(project, at: from ?? live.arrPos, arrange: false)
        } else if !want && live.recorder.active {
            let end: Double = Double(live.recorder.pos + 1)
            let segs: [ArrRecorder.Seg] = live.finishRecord()
            // Клипы, mute / solo и ручки — одна запись UNDO.
            beginGesture()
            defer { endGesture() }
            if !segs.isEmpty { edit { p in p.applyRecording(segs) } }
            if !autoTakes.isEmpty { flushAutoTakes(all: true, end: end) }
        }
        if !arrKnobRec && !arrRecording && !autoTakes.isEmpty { flushAutoTakes(all: true) }
    }
}
