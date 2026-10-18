import SwiftUI

/// Левая колонка: окно сэмпла, стрелки звука (папка дорожки), LFO1, LFO2, LFO3, ENV (S4 — серые).
struct LeftColumn: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: Layout.gap) {
            SampleWindow(model: model)
            if model.channel == .track {
                FolderArrows(model: model).frame(height: 36)
            }
            ButtonPair(left: SideButton(title: "LFO1", enabled: false), right: SideButton(title: "LFO2", enabled: false))
            ButtonPair(left: SideButton(title: "LFO3", enabled: false), right: SideButton(title: "ENV", enabled: false))
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

/// Правая колонка: миниатюры страниц, под ними MORPH и FX, SHIFT и MOD (MORPH, FX, MOD — S4).
struct RightColumn: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: Layout.gap) {
            PagesColumn(model: model)
            ButtonPair(left: SideButton(title: "MORPH", enabled: false), right: HoldButton(title: "FX", held: model.fxHeld) { on in
                model.fxHeld = on
            })
            ButtonPair(left: ShiftButton(model: model), right: SideButton(title: "MOD", enabled: false))
        }
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
        .frame(height: 56)
    }
}

struct SideButton: View {
    let title: String
    var enabled: Bool = true
    var lit: Bool = false
    @Environment(\.theme) private var theme

    var body: some View {
        let fg: Color = lit ? theme.bg : (enabled ? theme.text : theme.off)
        return Text(title)
            .font(.system(size: 13, weight: .semibold))
            .tracking(1)
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(lit ? theme.text : theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
    }
}

/// Кнопка удержания (FX, позже MOD): пока зажата — белая (в светлой теме — чёрная).
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

/// Измеритель уровня справа (S5) — пока пустые полосы.
struct MeterColumn: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3).fill(theme.meterTrack).frame(width: 9)
            RoundedRectangle(cornerRadius: 3).fill(theme.meterTrack).frame(width: 9)
        }
        .padding(.vertical, 24)
        .frame(width: Layout.meterWidth)
    }
}
