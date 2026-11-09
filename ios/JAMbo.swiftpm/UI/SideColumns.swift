import SwiftUI

/// Левая колонка: окно сэмпла, стрелки звука (папка дорожки), LFO1, LFO2, LFO3, ENV (при MST — кнопки мастера).
struct LeftColumn: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: Layout.gap) {
            LeftTop(model: model)
            if model.channel == .master {
                // По цепочке (решение пользователя, в вебе CLIP, LIM / SAT, COMP): SAT снизу слева, над ним COMP,
                // справа от него CLIP, под CLIP — LIM.
                AnyView(VStack(spacing: Layout.gap) {
                    ButtonPair(left: MasterButton(model: model, module: MasterScope.comp),
                               right: MasterButton(model: model, module: MasterScope.clip))
                    ButtonPair(left: MasterButton(model: model, module: MasterScope.sat),
                               right: MasterButton(model: model, module: MasterScope.lim))
                })
            } else if model.channel == .mix {
                // MIX (8.11): LFO и ENV при MIX ничего не делают — пустое поле на месте всей группы.
                AnyView(EmptyGroup())
            } else {
                AnyView(VStack(spacing: Layout.gap) {
                    ButtonPair(left: SourceButton(model: model, title: "LFO1", source: 1).midiTarget(model, "LFO1"),
                               right: SourceButton(model: model, title: "LFO2", source: 2).midiTarget(model, "LFO2"))
                    ButtonPair(left: SourceButton(model: model, title: "LFO3", source: 3).midiTarget(model, "LFO3"),
                               right: SourceButton(model: model, title: "ENV", source: 4).midiTarget(model, "ENV"))
                })
            }
        }
        .onGeometryChange(for: CGRect.self) { g in g.frame(in: .named("root")) } action: { r in
            if model.leftFrame != r { model.leftFrame = r }
        }
    }
}

/// Верх левой колонки (решение пользователя: строка кнопок — первая из 9 равных строк колонки, вровень со стрелками
/// страниц справа; окно — 8 строк, вровень с миниатюрами; в аранжировщике строку закрывают его кнопки): у дорожки —
/// стрелки папки, при MIX — ● MASTER; при MST строки нет — индикация мастера выше.
struct LeftTop: View {
    let model: AppModel

    var body: some View {
        let bar: CGFloat = model.barH
        let channel: Channel = model.channel
        return VStack(spacing: Layout.barGap) {
            if channel == .track {
                AnyView(FolderArrows(model: model).frame(height: bar))
            } else if channel == .mix {
                AnyView(MasterRecButton(model: model).frame(height: bar).midiTarget(model, "ARM MST"))
            }
            SampleWindow(model: model)
        }
    }
}

/// Верх правой колонки: строка стрелок страниц и 8 миниатюр; при MIX — скоп мастера на всю высоту.
struct RightTop: View {
    let model: AppModel

    var body: some View {
        let bar: CGFloat = model.barH
        let mix: Bool = model.channel == .mix
        return VStack(spacing: Layout.barGap) {
            if mix {
                // Скоп мастера того же размера, что при MST (решение пользователя 3.11): гониометр и осциллоскоп — только
                // форма волны мастера, без точек съёма COMP, CLIP, LIM; пустой строки сверху нет.
                AnyView(MasterScopeView(model: model, taps: false))
            } else {
                AnyView(VStack(spacing: Layout.barGap) {
                    PageArrows(model: model).frame(height: bar)
                    PagesColumn(model: model)
                })
            }
        }
    }
}

/// Стрелки ◀ ▶ под окном сэмпла: соседний звук папки дорожки (с зажатым шагом — звук шага); между ними n / всего.
struct FolderArrows: View {
    let model: AppModel

    var body: some View {
        let total: Int = model.track.folder.items.count
        return HStack(spacing: Layout.gap) {
            SideButton(title: "◀", enabled: total > 0).frame(width: 56)
                .contentShape(Rectangle())
                .onTapGesture { model.folderArrow(-1) }
            Text(model.folderLabel).font(.system(size: 11)).monospacedDigit().foregroundStyle(theme.dim).frame(maxWidth: .infinity)
            SideButton(title: "▶", enabled: total > 0).frame(width: 56)
                .contentShape(Rectangle())
                .onTapGesture { model.folderArrow(1) }
        }
    }
}

/// Стрелки страниц ◀ ▶ ▲ ▼ над миниатюрами (решение пользователя: перенесены из меню страницы) — для открытой
/// страницы: если она в белой обводке — сдвигают все играющие страницы, иначе только её. ▲ ▼ — ноты на октаву,
/// с SHIFT — на одну ноту гаммы.
struct PageArrows: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: Layout.gap) {
            arrow("◀", .left)
            arrow("▶", .right)
            arrow("▲", .up)
            arrow("▼", .down)
        }
    }

    private func arrow(_ title: String, _ action: AppModel.PageAction) -> some View {
        SideButton(title: title)
            .contentShape(Rectangle())
            .onTapGesture { tap(action) }
    }

    private func tap(_ arrow: AppModel.PageAction) {
        var action: AppModel.PageAction = arrow
        if model.shiftHeld && arrow == .up { action = .noteUp }
        if model.shiftHeld && arrow == .down { action = .noteDown }
        let last: Int = model.seq.pages.count - 1
        let page: Int = model.viewPage < last ? model.viewPage : last
        model.pageAction(action, page: page < 0 ? 0 : page)
    }
}

/// ● MASTER — запись мастера (S11d: конечный выход после громкости выхода, по правилам стемов; ARM MST — S12).
/// Дизайн как у ●: красная окантовка, горит, пока готова или пишет.
struct MasterRecButton: View {
    let model: AppModel

    var body: some View {
        let on: Bool = model.stemLit(StemRing.master)
        return HStack(spacing: 8) {
            Circle().fill(on ? Color.white : theme.rec).frame(width: 10, height: 10)
            Text("MASTER").font(.system(size: 13, weight: .semibold)).tracking(1)
                .foregroundStyle(on ? Color.white : theme.rec)
        }
        .tile(on ? theme.rec : theme.panel2)
        .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.rec, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { model.stemTap(StemRing.master) }
    }
}

/// Правая колонка: строка стрелок страниц ◀ ▶ ▲ ▼ (при MIX — пусто), под ней миниатюры страниц (при MIX — пустое
/// окно), под ними FX и MOD, SHIFT и MORPH (MORPH, FX, MOD — S4; MOD и MORPH, затем FX и MOD поменяны местами —
/// решения пользователя).
struct RightColumn: View {
    let model: AppModel

    var body: some View {
        // При MST — скоп на месте миниатюр, кнопки точек съёма COMP, CLIP, LIM на месте MORPH, FX, MOD.
        if model.channel == .master {
            AnyView(VStack(spacing: Layout.gap) {
                MasterScopeView(model: model)
                ButtonPair(left: ScopeButton(model: model, tap: MasterScope.comp),
                           right: ScopeButton(model: model, tap: MasterScope.clip))
                ButtonPair(left: ShiftButton(model: model), right: ScopeButton(model: model, tap: MasterScope.lim))
            })
        } else if model.channel == .mix {
            // MIX (8.11): FX, MOD, SHIFT, MORPH при MIX не нужны — пустое поле на месте всей группы.
            AnyView(VStack(spacing: Layout.gap) {
                RightTop(model: model)
                EmptyGroup()
            })
        } else {
            AnyView(VStack(spacing: Layout.gap) {
                RightTop(model: model)
                // FX слева, MOD справа (решение пользователя).
                ButtonPair(left: PageButton(model: model, title: "FX", page: .fx).midiTarget(model, "FX"),
                           right: PageButton(model: model, title: "MOD", page: .mod).midiTarget(model, "MOD"))
                ButtonPair(left: ShiftButton(model: model),
                           right: MorphButton(model: model).midiTarget(model, "MORPH"))
            })
        }
    }
}

/// Пустое поле на месте группы из двух пар кнопок (MIX): фон панели, без подписей.
struct EmptyGroup: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Layout.radius)
            .fill(theme.panel)
            .frame(height: 2 * Layout.pairHeight + Layout.gap)
    }
}

/// Две кнопки в ряд высотой 56.
struct ButtonPair<L: View, R: View>: View {
    let left: L
    let right: R

    var body: some View {
        HStack(spacing: Layout.gap) {
            left
            right
        }
        .frame(height: Layout.pairHeight)
    }
}

struct SideButton: View {
    let title: String
    var enabled: Bool = true
    var lit: Bool = false
    /// Горит жёлтым (MORPH включён).
    var accent: Bool = false

    var body: some View {
        let fg: Color = accent ? theme.onAccent : (lit ? theme.bg : (enabled ? theme.text : theme.off))
        let bg: Color = accent ? theme.accent : (lit ? theme.text : theme.panel2)
        return Text(title)
            .font(.system(size: 13, weight: .semibold))
            .tracking(1)
            .foregroundStyle(fg)
            .tile(bg)
    }
}

/// MORPH: тап включает и выключает режим (жёлтая — включён; при касании сразу видно, каким станет режим, без белой
/// подсветки); удержание + UNDO — сбросить изменения режима, отпускание тогда режим не переключает. Включён тапом
/// (выбранная дорожка) — внутри чёрная линия контура, как у FX и MOD в режиме toggle; пока держат SHIFT + MORPH
/// (все дорожки) — без линии.
struct MorphButton: View {
    let model: AppModel

    var body: some View {
        let shown: Bool = model.morphHeld && !model.morphUsed && !model.shiftHeld ? !model.morph : model.morph
        // Чёрная линия: режим на выбранной дорожке (не держат SHIFT + MORPH).
        let line: Bool = shown && !model.morphAllHeld
        return SideButton(title: "MORPH", accent: shown)
            .overlay(
                RoundedRectangle(cornerRadius: Layout.radius)
                    .inset(by: 3)
                    .stroke(line ? Color.black : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !model.morphHeld { model.morphPress() } }
                    .onEnded { _ in model.morphRelease() }
            )
    }
}

/// FX и MOD: удержание или (SHIFT + двойной тап) режим toggle — тогда внутри вторая чёрная линия контура.
struct PageButton: View {
    let model: AppModel
    let title: String
    let page: GridPage
    @State private var pressed = false

    var body: some View {
        let latch: Bool = model.latched(page)
        return SideButton(title: title, lit: model.pageOn(page))
            .overlay(
                // Концентрично контуру кнопки: тот же радиус минус отступ (inset уменьшает радиус сам).
                RoundedRectangle(cornerRadius: Layout.radius)
                    .inset(by: 3)
                    .stroke(latch ? Color.black : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed {
                            pressed = true
                            model.pagePress(page)
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        model.pageRelease(page)
                    }
            )
    }
}

/// LFO1–3, ENV — удержание (назначение на ручки); белый контур — пока палец держит ручку с этим источником.
struct SourceButton: View {
    let model: AppModel
    let title: String
    let source: Int

    var body: some View {
        let outlined: Bool = model.fingerSources.contains(source)
        return HoldButton(title: title, held: model.heldSources.contains(source)) { on in model.setSource(source, held: on) }
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(outlined ? theme.text : Color.clear, lineWidth: 1))
    }
}

/// Кнопка удержания (FX, MOD, LFO, ENV): пока зажата — белая (в светлой теме — чёрная).
struct HoldButton: View {
    let title: String
    let held: Bool
    let set: (Bool) -> Void

    var body: some View {
        SideButton(title: title, lit: held)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !held { set(true) } }
                    .onEnded { _ in set(false) }
            )
    }
}

/// SHIFT — удержание: пока зажата — белая (в светлой теме — чёрная); с двойным тапом по ручке — снять все p-lock.
struct ShiftButton: View {
    let model: AppModel

    var body: some View {
        SideButton(title: "SHIFT", lit: model.shiftHeld)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !model.shiftHeld { model.shiftPressed() } }
                    .onEnded { _ in model.shiftReleased() }
            )
    }
}
