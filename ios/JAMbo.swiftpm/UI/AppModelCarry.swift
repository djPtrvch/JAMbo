import SwiftUI

// Перенос клипа из сетки паттернов в аранжировку (решение пользователя): поднятый клип тянут на кнопку ARRANGE —
// открывается аранжировщик (сетка остаётся под ним невидимой, пока палец не отпущен: жест не прерывается), клип
// встаёт блоком на свою дорожку — на свободное место или, на стыке (палец у начала блока), со сдвигом блоков правее.

/// Идёт перенос клипа: ячейка и открыт ли уже аранжировщик (палец — carryPoint, отдельно: меняется каждый кадр).
struct ClipCarry: Equatable {
    let cell: CellRef
    var overArrange: Bool = false
}

/// Куда встанет перенесённый клип: дорожка, начало и длина в шагах, вставка со сдвигом.
struct CarryDrop: Equatable {
    let track: Int
    let start: Int
    let length: Int
    let insert: Bool
}

extension AppModel {
    /// Палец у начала блока ближе этого (pt) — вставка со сдвигом.
    static let carryJunction: CGFloat = 16

    /// Клип тянут (p — палец в координатах «root»): над кнопкой ARRANGE — открыть аранжировщик.
    func carryMove(_ c: CellRef, root p: CGPoint) {
        if clipCarry == nil { clipCarry = ClipCarry(cell: c) }
        carryPoint = p
        guard var carry = clipCarry, !carry.overArrange, arrangeButtonFrame.contains(p) else { return }
        carry.overArrange = true
        browser = nil
        editorOpen = false
        eqView = false
        eqMenu = nil
        cellMenu = nil
        rowMenu = nil
        gridMenuOpen = false
        closeRoll()
        closeMasterWindow()
        arrangeView = true
        clipCarry = carry
    }

    /// Палец отпущен. Аранжировщик не открывался — false (обычный перенос в сетке). Иначе сетка закрывается
    /// (остаётся аранжировщик), над таймлайном — блок (одна запись UNDO).
    func carryEnd(cancelled: Bool) -> Bool {
        guard let c = clipCarry else { return false }
        clipCarry = nil
        if !c.overArrange { return false }
        let drop: CarryDrop? = cancelled ? nil : carryDrop(c)
        patternView = false
        guard let d = drop else { return true }
        let k: Int = c.cell.row
        var i: Int = 0
        edit { p in
            if d.insert { i = p.tracks[d.track].insertBlock(clip: k, at: d.start) } else { i = p.tracks[d.track].addBlock(clip: k, at: d.start) }
        }
        arrGroup = []
        arrSel = ArrSel(track: d.track, block: i)
        return true
    }

    /// Куда встанет клип под пальцем: только над таймлайном (ниже линейки); дорожка — столбец клипа.
    func carryDrop(_ c: ClipCarry) -> CarryDrop? {
        let f: CGRect = arrTimelineFrame
        let pt: CGPoint = carryPoint
        guard c.overArrange, f.contains(pt) else { return nil }
        let t: Int = c.cell.track
        guard t >= 0 && t < project.tracks.count, project.tracks[t].clipFilled(c.cell.row) else { return nil }
        let px: CGFloat = pt.x - f.minX
        let py: CGFloat = pt.y - f.minY
        if py < ArrMetrics.top { return nil }
        let m: ArrMetrics = arrMetrics(f.size)
        let tr: Track = project.tracks[t]
        let len: Int = tr.clipSteps(c.cell.row)
        for b in tr.blocks where abs(m.stepX(Double(b.start)) - px) < AppModel.carryJunction {
            return CarryDrop(track: t, start: b.start, length: len, insert: true)
        }
        let s: Int = project.arrange.snapped(Int(m.step(at: px).rounded(.down)))
        return CarryDrop(track: t, start: max(0, s), length: len, insert: false)
    }

    /// Метрики таймлайна размера size (как у окна аранжировщика).
    func arrMetrics(_ size: CGSize) -> ArrMetrics {
        let p: Project = project
        return ArrMetrics(size: size, port: arrPort, tracks: p.tracks.count, end: p.arrangeEnd,
                          expanded: settings.arrangeExpanded, inset: arrInset, ref: arrRefShown)
    }
}

/// Клип, принесённый из сетки (AppModelCarry): блок с тенью там, где встанет; на стыке — жёлтая черта и значок
/// раздвигания (блоки правее сдвинутся).
struct ArrCarryLayer: View {
    let model: AppModel
    let carry: ClipCarry
    let m: ArrMetrics
    @Environment(\.theme) private var theme

    var body: some View {
        let _ = model.carryPoint
        if let d = model.carryDrop(carry) {
            let p: Project = model.project
            let color: Color = d.track < p.tracks.count ? ArrColors.color(p.tracks[d.track].color) : ArrColors.color(0)
            let r: CGRect = m.rect(d.track, ArrBlock(clip: carry.cell.row, start: d.start, length: d.length))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(d.insert ? 0.5 : 0.85))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.text, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .frame(width: r.width, height: r.height)
                    .shadow(color: Color.black.opacity(0.5), radius: 8, y: 4)
                    .offset(x: r.minX, y: r.minY)
                if d.insert { junction(r) }
            }
            .allowsHitTesting(false)
        }
    }

    /// Стык: жёлтая черта на высоту строки и значок ⟷ над ней.
    private func junction(_ r: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(theme.accent).frame(width: 2, height: r.height + 4).offset(x: r.minX - 1, y: r.minY - 2)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(theme.onAccent)
                .frame(width: 24, height: 18)
                .background(theme.accent, in: Capsule())
                .offset(x: r.minX - 12, y: r.minY + r.height / 2 - 9)
        }
    }
}
