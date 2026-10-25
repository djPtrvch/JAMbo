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
    /// Выделенный на линейке диапазон: LOOP (зациклить), SECTION (секция с начала диапазона).
    case range(anchor: CGPoint)
}

/// Вид таймлайна: ширина шага (nil — 16 тактов на ширину), прокрутка по X и по Y (pt). Высота строки — по режиму
/// (ArrMetrics). Не хранится в проекте и не входит в UNDO.
struct ArrPort: Equatable {
    var stepW: CGFloat? = nil
    var x: CGFloat = 0
    var y: CGFloat = 0
}

/// Палитра дорожек и маркеров (20 цветов, одна в обеих темах; текст на них — #111111) — номер в ArrPalette.
enum ArrColors {
    static let all: [Color] = [
        Color(hex: 0xFFF0B0), Color(hex: 0xF0D45C), Color(hex: 0xD9B23A), Color(hex: 0xB8902A), Color(hex: 0x8F6E1E),
        Color(hex: 0xFFD0A3), Color(hex: 0xEBA640), Color(hex: 0xFFB070), Color(hex: 0xF59447), Color(hex: 0xE07A33),
        Color(hex: 0xC2622A), Color(hex: 0xFFB8B0), Color(hex: 0xF58C82), Color(hex: 0xE0607A), Color(hex: 0xE06666),
        Color(hex: 0xC24848), Color(hex: 0xE0DCD4), Color(hex: 0xB5B0A8), Color(hex: 0x8A857E), Color(hex: 0x66625D),
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
        arrangeView = false
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

    func toggleArrSnap() {
        edit { p in p.arrange.snap.toggle() }
    }

    func toggleArrLoop() {
        guard project.arrange.hasLoop else { return }
        edit { p in p.arrange.loop.toggle() }
    }

    func toggleArrSteps() {
        edit { p in p.arrange.hideSteps.toggle() }
    }

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

    func arrDeleteGroup() {
        let g = arrGroupList
        edit { p in p.deleteBlocks(g) }
        arrGroup = []
        arrSel = nil
    }

    func arrDeleteBlock(_ s: ArrSel) {
        guard arrBlock(s) != nil else { return }
        edit { p in p.tracks[s.track].deleteBlock(s.block) }
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
