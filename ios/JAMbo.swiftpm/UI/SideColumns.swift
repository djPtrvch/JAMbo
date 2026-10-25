import SwiftUI

/// Левая колонка: окно сэмпла, стрелки звука (папка дорожки), LFO1, LFO2, LFO3, ENV (при MST — кнопки мастера).
struct LeftColumn: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: Layout.gap) {
            // Над окном (решение пользователя: высотой с верхнюю миниатюру паттернов — строка кнопок, в аранжировщике её
            // закрывают его кнопки): у дорожки — стрелки папки, при MIX — ● MASTER; при MST строки нет — индикация
            // мастера выше.
            if model.channel == .track {
                FolderArrows(model: model).frame(height: model.barH)
            } else if model.channel == .mix {
                MasterRecButton(model: model).frame(height: model.barH).midiTarget(model, "ARM MST")
            }
            SampleWindow(model: model)
            if model.channel == .master {
                // По цепочке (решение пользователя, в вебе CLIP, LIM / SAT, COMP): SAT снизу слева, над ним COMP,
                // справа от него CLIP, под CLIP — LIM.
                ButtonPair(left: MasterButton(model: model, module: MasterScope.comp),
                           right: MasterButton(model: model, module: MasterScope.clip))
                ButtonPair(left: MasterButton(model: model, module: MasterScope.sat),
                           right: MasterButton(model: model, module: MasterScope.lim))
            } else {
                ButtonPair(left: SourceButton(model: model, title: "LFO1", source: 1).midiTarget(model, "LFO1"),
                           right: SourceButton(model: model, title: "LFO2", source: 2).midiTarget(model, "LFO2"))
                ButtonPair(left: SourceButton(model: model, title: "LFO3", source: 3).midiTarget(model, "LFO3"),
                           right: SourceButton(model: model, title: "ENV", source: 4).midiTarget(model, "ENV"))
            }
        }
        .onGeometryChange(for: CGRect.self) { g in g.frame(in: .named("root")) } action: { r in
            if model.leftFrame != r { model.leftFrame = r }
        }
    }
}

/// Стрелки ◀ ▶ под окном сэмпла: соседний звук папки дорожки (с зажатым шагом — звук шага); между ними n / всего.
struct FolderArrows: View {
    let model: AppModel
    @Environment(\.theme) private var theme

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

/// ● MASTER — запись мастера (S11d: конечный выход после громкости выхода, по правилам стемов; ARM MST — S12).
/// Дизайн как у ●: красная окантовка, горит, пока готова или пишет.
struct MasterRecButton: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let on: Bool = model.stemLit(StemRing.master)
        return HStack(spacing: 8) {
            Circle().fill(on ? Color.white : theme.rec).frame(width: 10, height: 10)
            Text("MASTER").font(.system(size: 13, weight: .semibold)).tracking(1)
                .foregroundStyle(on ? Color.white : theme.rec)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(on ? theme.rec : theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
        .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.rec, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { model.stemTap(StemRing.master) }
    }
}

/// Правая колонка: миниатюры страниц (при MIX — пустое окно), под ними MOD и FX, SHIFT и MORPH (MORPH, FX, MOD — S4;
/// MOD и MORPH поменяны местами — решение пользователя).
struct RightColumn: View {
    let model: AppModel

    var body: some View {
        // При MST — скоп на месте миниатюр, кнопки точек съёма COMP, CLIP, LIM на месте MORPH, FX, MOD.
        if model.channel == .master {
            VStack(spacing: Layout.gap) {
                MasterScopeView(model: model)
                ButtonPair(left: ScopeButton(model: model, tap: MasterScope.comp),
                           right: ScopeButton(model: model, tap: MasterScope.clip))
                ButtonPair(left: ShiftButton(model: model), right: ScopeButton(model: model, tap: MasterScope.lim))
            }
        } else {
            VStack(spacing: Layout.gap) {
                if model.channel == .mix { MixPagesBlank() } else { PagesColumn(model: model) }
                ButtonPair(left: PageButton(model: model, title: "MOD", page: .mod).midiTarget(model, "MOD"),
                           right: PageButton(model: model, title: "FX", page: .fx).midiTarget(model, "FX"))
                ButtonPair(left: ShiftButton(model: model),
                           right: MorphButton(model: model).midiTarget(model, "MORPH"))
            }
        }
    }
}

/// Место миниатюр страниц при MIX: пустое окно без подписей.
struct MixPagesBlank: View {
    @Environment(\.theme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: Layout.radius).fill(theme.panel)
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
    @Environment(\.theme) private var theme

    var body: some View {
        let fg: Color = accent ? theme.onAccent : (lit ? theme.bg : (enabled ? theme.text : theme.off))
        let bg: Color = accent ? theme.accent : (lit ? theme.text : theme.panel2)
        return Text(title)
            .font(.system(size: 13, weight: .semibold))
            .tracking(1)
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(bg, in: RoundedRectangle(cornerRadius: Layout.radius))
    }
}

/// MORPH: тап включает и выключает режим (жёлтая — включён; при касании сразу видно, каким станет режим, без белой
/// подсветки); удержание + UNDO — сбросить изменения режима, отпускание тогда режим не переключает. SHIFT + двойной
/// тап — ALL TRACKS вкл./выкл. (по умолчанию включён): пока выключен, внутри чёрная линия контура, как у FX и MOD
/// в режиме toggle.
struct MorphButton: View {
    let model: AppModel

    var body: some View {
        let shown: Bool = model.morphHeld && !model.morphUsed && !model.shiftHeld ? !model.morph : model.morph
        let all: Bool = model.settings.morphAll
        return SideButton(title: "MORPH", accent: shown)
            .overlay(
                RoundedRectangle(cornerRadius: Layout.radius)
                    .inset(by: 3)
                    .stroke(all ? Color.clear : Color.black, lineWidth: 1)
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
    @Environment(\.theme) private var theme

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
                    .onChanged { _ in if !model.shiftHeld { model.shiftHeld = true } }
                    .onEnded { _ in model.shiftHeld = false }
            )
    }
}
