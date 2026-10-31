import SwiftUI

/// Выбранный блок аранжировщика: дорожка и номер блока.
struct ArrSel: Equatable {
    let track: Int
    let block: Int
}

/// Меню аранжировщика: блока (двойной тап по блоку), места на дорожке (двойной тап по пустому) и дорожки (двойной
/// тап по заголовку); anchor — точка в координатах окна аранжировщика.
enum ArrMenuState: Equatable {
    case block(track: Int, block: Int, anchor: CGPoint)
    case lane(track: Int, at: Int, anchor: CGPoint)
    case track(track: Int, anchor: CGPoint)
    /// Окно маркера (S15d): имя, цвет, курсор сюда, DELETE.
    case marker(index: Int, anchor: CGPoint)
    /// INSERT: клипы дорожки для вставки в точку at.
    case insert(track: Int, at: Int, anchor: CGPoint)
    /// Строка REF (S15g): LOAD (другой файл), DELETE.
    case ref
    /// Выделение из сетки положили поверх блоков (AppModelCarry): HERE, INSERT, TO END.
    case drop(anchor: CGPoint)
    /// Кнопка сетки (решение пользователя): шаг сетки и SNAP TO GRID.
    case grid
    /// Двойной тап по линейке: на секции — RENAME, SPLIT, DELETE SECTION; вне — ADD SECTION, SPLIT.
    case ruler(anchor: CGPoint)
}

/// Вид таймлайна: ширина шага (nil — 16 тактов на ширину), прокрутка по X и по Y (pt), высота строки (nil — по режиму
/// EXPANDED / COMPACT; своя — только при SCALE, масштаб двумя пальцами по вертикали). Не хранится в проекте и не входит
/// в UNDO.
struct ArrPort: Equatable {
    var stepW: CGFloat? = nil
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowH: CGFloat? = nil
}

/// Палитра дорожек и маркеров (20 цветов, одна в обеих темах; текст на них — #111111) — номер в ArrPalette. В выборе
/// (17) — серые, жёлтые, оранжевые, красные; 3 — прежний, убран из выбора; 16 — белый; 17 — по умолчанию.
enum ArrColors {
    static let all: [Color] = [
        Color(hex: 0x464649), Color(hex: 0x5E6166), Color(hex: 0x8E9298), Color(hex: 0xB8902A), Color(hex: 0xD0D3D7),
        Color(hex: 0xFAF0A8), Color(hex: 0xF0D55A), Color(hex: 0xCDA830), Color(hex: 0xA67C1A), Color(hex: 0xF5964A),
        Color(hex: 0xBF5F24), Color(hex: 0x733519), Color(hex: 0xEC746E), Color(hex: 0xDC5468), Color(hex: 0xCF4747),
        Color(hex: 0xA33048), Color(hex: 0xE0DCD4), Color(hex: 0xB5B0A8), Color(hex: 0x7D2A2A), Color(hex: 0x6A2430),
    ]
    static let text: Color = Color(hex: 0x111111)

    static func color(_ k: Int) -> Color {
        return all[max(0, min(k, all.count - 1))]
    }
}

/// Аранжировщик (S15, docs/ai/arranger.md): окно на месте центра; правки блоков — через Core (ArrangeEdits), каждое
/// действие — одна запись UNDO, перетаскивание — одна запись на жест.
extension AppModel {
    func toggleArrange() {
        if arrangeView {
            closeArrange()
            return
        }
        patternView = false
        browser = nil
        editorOpen = false
        eqView = false
        eqMenu = nil
        closeRoll()
        closeMasterWindow()
        arrangeView = true
    }

    func closeArrange() {
        // Вне аранжировщика слышен проект (A).
        let wasB: Bool = refBActive
        arrangeView = false
        if wasB { publishAudio() }
        arrMenu = nil
        arrSel = nil
        arrInsert = false
        arrInserted = nil
    }

    /// Курсор на экране: при игре — из колбэка, без игры — поставленный.
    var arrNow: Int { return playing ? live.arrPos : arrCursor }

    /// Дорожка идёт по таймлайну (без игры — все).
    func arrFollowing(_ t: Int) -> Bool {
        if !playing { return true }
        return t >= 0 && t < live.following.count && live.following[t]
    }

    /// Тап по номерам тактов: курсор на ближайшую линию сетки (действует со следующего PLAY).
    func setArrCursor(_ x: Int) {
        arrCursor = project.arrange.snapped(x)
        // Во время игры курсор переходит сразу (со следующего шага).
        if playing { audio.core.events.push(.seekArrange(arrCursor)) }
    }

    /// Кнопка со стрелкой к черте: курсор в самое начало таймлайна.
    func arrToStart() {
        arrCursor = 0
        if playing { audio.core.events.push(.seekArrange(0)) }
    }

    /// Возврат дорожки к таймлайну (t < 0 — всех), сразу с позиции курсора.
    func returnToArrange(_ t: Int) {
        guard playing else { return }
        audio.core.events.push(.returnToArrange(track: t))
    }

    var anyOffTimeline: Bool {
        if !playing { return false }
        for t in 0..<project.tracks.count where !arrFollowing(t) { return true }
        return false
    }

    // MARK: — вторая строка: сетка, магнит, петля, STEPS

    func setArrGrid(_ k: Int) {
        edit { p in p.arrange.grid = max(0, min(k, ArrGrid.steps.count - 1)) }
    }

    /// SETTINGS → ARRANGE → TRACKS: FIX или SCALE; свой масштаб строк сбрасывается.
    func setArrScale(_ on: Bool) {
        updateSettings { $0.arrangeScale = on }
        arrPort.rowH = nil
    }

    /// Дорожки прокручиваются по вертикали: EXPANDED или свой масштаб строк (SCALE).
    var arrRowsScroll: Bool { return settings.arrangeExpanded || arrPort.rowH != nil }

    /// Кнопки EXPANDED / COMPACT под измерителем (при FIX): режим строк, свой масштаб строк сбрасывается.
    func setArrCompact(_ on: Bool) {
        updateSettings { $0.arrangeCompact = on }
        arrPort.rowH = nil
        arrPort.y = 0
    }

    /// FOLLOW PLAYHEAD (решение пользователя): при игре плейхед ушёл за правый край окна (или левее левого) — окно
    /// перелистывается: плейхед — у левого края (десятая часть ширины). Зовётся из таймера модели (60 Гц).
    func arrFollowPlayhead() {
        guard arrangeView && playing && settings.arrangeFollow, clipCarry == nil else { return }
        let w: CGFloat = arrTimelineFrame.width
        if w <= 0 { return }
        let step: CGFloat = ArrMetrics.clampStep(arrPort.stepW ?? w / 256, width: w)
        let x: CGFloat = CGFloat(arrNowX) * step - arrPort.x
        if x >= 0 && x <= w - 24 { return }
        var port: ArrPort = arrPort
        port.x = max(0, CGFloat(arrNowX) * step - w * 0.1)
        if port != arrPort { arrPort = port }
    }

    func toggleArrSnap() {
        edit { p in p.arrange.snap.toggle() }
    }

    func toggleArrLoop() {
        guard project.arrange.hasLoop else { return }
        edit { p in p.arrange.loop.toggle() }
    }

    /// STEPS включили — AUTO выключается (решение пользователя: кнопки переключают друг друга).
    func toggleArrSteps() {
        edit { p in p.arrange.hideSteps.toggle() }
        if !project.arrange.hideSteps && arrAuto {
            arrAuto = false
            syncArrRecord()
        }
    }

    /// Сколько снизу окна аранжировщика закрыто (STEPS или AUTO — три нижние дорожки): дорожки прокручиваются из-под низа.
    var arrInset: CGFloat { return arrangeView && (arrAuto || !project.arrange.hideSteps) ? arrLowerH + ArrMetrics.gap : 0 }

    /// STEPS выключена: строка дорожек, секвенсор и клавиатура скрыты (только пока открыт аранжировщик).
    var arrStepsHidden: Bool { return arrangeView && project.arrange.hideSteps }

    // MARK: — блоки

    /// Имя клипа на блоке: имя строки сетки (без имени — номер).
    func arrClipName(_ k: Int) -> String {
        return project.sceneName(k)
    }

    /// Клипы дорожки для меню места (заполненные ячейки её столбца).
    func arrClips(_ t: Int) -> [Int] {
        guard t >= 0 && t < project.tracks.count else { return [] }
        let tr = project.tracks[t]
        return (0..<project.visibleRows).filter { tr.clipFilled($0) }
    }

    func arrAddBlock(track t: Int, clip k: Int, at x: Int) {
        guard t >= 0 && t < project.tracks.count else { return }
        let s: Int = project.arrange.snapped(x)
        var i: Int = 0
        edit { p in i = p.tracks[t].addBlock(clip: k, at: s) }
        arrSel = ArrSel(track: t, block: i)
    }

    func arrBlock(_ s: ArrSel?) -> ArrBlock? {
        guard let s = s, s.track >= 0, s.track < project.tracks.count else { return nil }
        let b = project.tracks[s.track].blocks
        return s.block >= 0 && s.block < b.count ? b[s.block] : nil
    }

    func arrCopyBlock(_ s: ArrSel) {
        arrBlockClipboard = arrBlock(s)
    }

    func arrPasteBlock(after s: ArrSel) {
        guard let b = arrBlockClipboard, arrBlock(s) != nil else { return }
        var i: Int = 0
        edit { p in i = p.tracks[s.track].pasteBlock(after: s.block, b) }
        arrSel = ArrSel(track: s.track, block: i)
    }

    /// PASTE в меню места: скопированный блок — на это место (в том числе на пустую дорожку).
    func arrPasteBlock(track t: Int, at x: Int) {
        guard let b = arrBlockClipboard, t >= 0, t < project.tracks.count else { return }
        var n: ArrBlock = b
        n.start = project.arrange.snapped(x)
        var i: Int = 0
        edit { p in i = p.tracks[t].placeBlock(n) }
        arrSel = ArrSel(track: t, block: i)
    }

    func arrDuplicateBlock(_ s: ArrSel) {
        guard arrBlock(s) != nil else { return }
        var i: Int = 0
        edit { p in i = p.tracks[s.track].duplicateBlock(s.block) }
        arrSel = ArrSel(track: s.track, block: i)
    }

    // MARK: — группа (выделение рамкой)

    /// Блок s — в выделенной рамкой группе (от двух блоков).
    func arrInGroup(_ s: ArrSel) -> Bool {
        return arrGroup.count >= 2 && arrGroup.contains(s)
    }

    private var arrGroupList: [(track: Int, block: Int)] {
        return arrGroup.map { (track: $0.track, block: $0.block) }
    }

    private func setGroup(_ list: [(track: Int, block: Int)]) {
        arrGroup = list.map { ArrSel(track: $0.track, block: $0.block) }
        arrSel = nil
    }

    /// Перенос группы (отпустили поднятый блок группы): сдвиг d шагов, одна запись UNDO.
    func arrMoveGroup(by d: Int) {
        if d == 0 || arrGroup.count < 2 { return }
        let g = arrGroupList
        var out: [(track: Int, block: Int)] = []
        edit { p in out = p.moveBlocks(g, by: d) }
        setGroup(out)
    }

    /// DUPLICATE группы: копии сразу за ней, выделены копии.
    func arrDuplicateGroup() {
        let g = arrGroupList
        var out: [(track: Int, block: Int)] = []
        edit { p in out = p.duplicateBlocks(g) }
        setGroup(out)
    }

    /// DELETE группы: блоки убираются (правые не смыкаются — решение пользователя), с ними — автоматизация их дорожек
    /// на их месте.
    func arrDeleteGroup() {
        let g = arrGroupList
        var spans: [(track: Int, from: Int, to: Int)] = []
        for s in arrGroup {
            if let b = arrBlock(s) { spans.append((s.track, b.start, b.end)) }
        }
        edit { p in
            p.deleteBlocks(g)
            for r in spans where r.track < p.tracks.count { p.tracks[r.track].clearAuto(from: Double(r.from), to: Double(r.to)) }
        }
        arrGroup = []
        arrSel = nil
    }

    /// DELETE блока: правые не смыкаются (решение пользователя), автоматизация дорожки на месте блока — тоже убирается.
    func arrDeleteBlock(_ s: ArrSel) {
        guard let b = arrBlock(s) else { return }
        edit { p in
            p.tracks[s.track].deleteBlock(s.block)
            p.tracks[s.track].clearAuto(from: Double(b.start), to: Double(b.end))
        }
        arrSel = nil
    }

    /// Перенос блока (отпустили поднятый блок): начало — с магнитом.
    func arrMoveBlock(_ s: ArrSel, to x: Int) {
        guard arrBlock(s) != nil else { return }
        let start: Int = project.arrange.snapped(x)
        var i: Int = s.block
        edit { p in i = p.tracks[s.track].moveBlock(s.block, to: start) }
        arrSel = ArrSel(track: s.track, block: i)
    }

    /// Протяжка края (внутри жеста beginGesture / endGesture): блоки дорожки — от base, края — с магнитом.
    func arrResizeBlock(track t: Int, base: [ArrBlock], index: Int, start: Int, end: Int) {
        guard t >= 0 && t < project.tracks.count, index >= 0, index < base.count else { return }
        let a: Int = project.arrange.snapped(start)
        var b: Int = project.arrange.snapped(end)
        if b <= a { b = a + (project.arrange.snap ? project.arrange.gridSteps : 1) }
        var i: Int = index
        edit { p in
            p.tracks[t].blocks = base
            i = p.tracks[t].resizeBlock(index, start: a, end: b)
        }
        arrSel = ArrSel(track: t, block: i)
    }

    // MARK: — меню дорожки

    func arrCopyTrack(_ t: Int) {
        guard t >= 0 && t < project.tracks.count else { return }
        arrTrackClipboard = project.tracks[t].blocks
    }

    func arrPasteTrack(_ t: Int) {
        guard let list = arrTrackClipboard else { return }
        edit { p in p.pasteBlocks(t, list) }
        arrSel = nil
    }

    func arrDuplicateTrack(_ t: Int) {
        guard t >= 0 && t < project.tracks.count else { return }
        edit { p in p.tracks[t].duplicateBlocks() }
    }

    func arrSetTrackColor(_ t: Int, _ c: Int) {
        edit { p in p.setTrackColor(t, c) }
    }
}
