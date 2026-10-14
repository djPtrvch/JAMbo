import SwiftUI

/// Левая колонка: окно сэмпла (S2), стрелки звука, LFO1, LFO2, LFO3, ENV (S4) — пока на местах, серые.
struct LeftColumn: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: Layout.gap) {
            Text("SAMPLE · S2")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundStyle(theme.off)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
                .overlay(RoundedRectangle(cornerRadius: Layout.radius).strokeBorder(theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            HStack(spacing: Layout.gap) {
                SideButton(title: "◀", enabled: false).frame(width: 56)
                Text("— / —").font(.system(size: 11)).foregroundStyle(theme.dim).frame(maxWidth: .infinity)
                SideButton(title: "▶", enabled: false).frame(width: 56)
            }
            .frame(height: 36)
            ButtonPair(left: SideButton(title: "LFO1", enabled: false), right: SideButton(title: "LFO2", enabled: false))
            ButtonPair(left: SideButton(title: "LFO3", enabled: false), right: SideButton(title: "ENV", enabled: false))
        }
    }
}

/// Правая колонка: миниатюры страниц, под ними MORPH и FX, SHIFT и MOD (MORPH, FX, MOD — S4).
struct RightColumn: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: Layout.gap) {
            PagesColumn(model: model)
            ButtonPair(left: SideButton(title: "MORPH", enabled: false), right: SideButton(title: "FX", enabled: false))
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
