import SwiftUI

/// Строка кнопок аранжировщика (решения пользователя): высотой со строку стрелок над превью и миниатюрами
/// (AppModel.barH) — и закрывает её. Слева, по ширине превью, — сетка (меню GRID и SNAP TO GRID), TRIM (ножницы), курсор в начало
/// (стрелка к черте), LOOP; справа, по ширине колонки миниатюр, — AUTO (синусоида с точками), KNOBS (окно ручек),
/// STEPS (значок секвенсора), REF. Шаг сетки — в SETTINGS → ARRANGE.
struct ArrangeBar: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let a: Arrangement = model.project.arrange
        return HStack(spacing: Layout.gap) {
            HStack(spacing: Layout.gap) {
                // Сетка (решение пользователя, на месте магнита): тап — меню шага сетки и SNAP TO GRID.
                ArrBarButton(on: model.arrMenu == .grid, enabled: true, action: { model.arrMenu = .grid }) { c in
                    Image(systemName: "squareshape.split.3x3").font(.system(size: 18, weight: .semibold)).foregroundStyle(c)
                }
                ArrBarButton(on: false, enabled: true, action: { model.arrTrim() }) { c in
                    Image(systemName: "scissors").font(.system(size: 18, weight: .semibold)).foregroundStyle(c)
                }
                ArrReturnAll(model: model)
                ArrBarButton(on: a.loop, enabled: a.hasLoop, action: { model.toggleArrLoop() }) { c in
                    Image(systemName: "repeat").font(.system(size: 18, weight: .semibold)).foregroundStyle(c)
                }
            }
            .frame(width: Layout.leftColumn)
            .background(cover)
            Spacer(minLength: 0)
            HStack(spacing: Layout.gap) {
                // Запись (REC + PLAY + AUTO) — красная обводка.
                ArrBarButton(on: model.arrAuto, enabled: true, ring: model.arrKnobRec, action: { model.toggleArrAuto() }) { c in
                    ArrWaveIcon(color: c)
                }
                ArrBarButton(on: model.arrKnobs, enabled: true, action: { model.arrKnobs.toggle() }) { c in
                    Image(systemName: "dial.medium").font(.system(size: 20, weight: .semibold)).foregroundStyle(c)
                }
                ArrBarButton(on: !a.hideSteps, enabled: true, action: { model.toggleArrSteps() }) { c in ArrStepsIcon(color: c) }
                ArrBarText(title: "REF", on: model.arrRefShown, enabled: true) { model.toggleArrRef() }
            }
            .frame(width: Layout.leftColumn)
            .background(cover)
            // Место измерителя справа (как в окне дорожки).
            Color.clear.frame(width: Layout.meterWidth)
        }
    }

    /// Ровный фон под кнопками (решение пользователя): закрывает строку стрелок папки и страниц и ● MASTER, в том числе
    /// в зазорах между кнопками; вниз не выходит — белая обводка играющих миниатюр (на 3 pt над верхней) видна.
    private var cover: some View {
        Rectangle().fill(theme.bg).padding(.horizontal, -5).padding(.top, -5)
    }
}

/// Значок STEPS: строка шагов секвенсора (квадратики, два горят).
struct ArrStepsIcon: View {
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let side: CGFloat = 5
            let gap: CGFloat = 2
            let n: Int = 4
            let w: CGFloat = CGFloat(n) * side + CGFloat(n - 1) * gap
            let x0: CGFloat = (size.width - w) / 2
            let y: CGFloat = (size.height - side) / 2
            var k: Int = 0
            while k < n {
                let r = CGRect(x: x0 + CGFloat(k) * (side + gap), y: y, width: side, height: side)
                let p = Path(roundedRect: r, cornerRadius: 1)
                if k % 2 == 0 { ctx.fill(p, with: .color(color)) } else { ctx.stroke(p, with: .color(color), lineWidth: 1) }
                k += 1
            }
        }
        .frame(width: 30, height: 20)
    }
}

/// Кнопка-надпись второй строки: включённая — горит (как PATTERNS); неактивная — серая.
struct ArrBarText: View {
    let title: String
    let on: Bool
    let enabled: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let lit: Bool = on && enabled
        let fg: Color = !enabled ? theme.off : (on ? theme.bg : theme.text)
        let bg: Color = lit ? theme.text : theme.panel2
        return Text(title)
            .font(.system(size: 12, weight: .semibold))
            .tracking(1)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(bg, in: RoundedRectangle(cornerRadius: Layout.radius))
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
    }
}

/// Кнопка-значок второй строки (магнит, AUTO).
struct ArrBarButton<Icon: View>: View {
    let on: Bool
    let enabled: Bool
    var ring: Bool = false
    let action: () -> Void
    let icon: (Color) -> Icon
    @Environment(\.theme) private var theme

    var body: some View {
        let lit: Bool = on && enabled
        let fg: Color = !enabled ? theme.off : (on ? theme.bg : theme.text)
        let bg: Color = lit ? theme.text : theme.panel2
        return icon(fg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(bg, in: RoundedRectangle(cornerRadius: Layout.radius))
            // Запись — красный контур толще (решение пользователя: 3 pt, как запись мастера).
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).strokeBorder(ring ? theme.rec : Color.clear, lineWidth: 3))
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
    }
}

/// Курсор в самое начало таймлайна (при игре — сразу).
struct ArrReturnAll: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        Image(systemName: "arrow.left.to.line")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
            .contentShape(Rectangle())
            .onTapGesture { model.arrToStart() }
    }
}

/// Значок AUTO: синусоида с точками.
struct ArrWaveIcon: View {
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let w: CGFloat = 22
            let x0: CGFloat = (size.width - w) / 2
            let mid: CGFloat = size.height / 2
            var p = Path()
            var k: Int = 0
            while k <= 22 {
                let x: CGFloat = x0 + CGFloat(k)
                let y: CGFloat = mid - 5 * CGFloat(sin(Double(k) / 22 * 2 * Double.pi))
                if k == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                k += 1
            }
            ctx.stroke(p, with: .color(color), lineWidth: 1.5)
            for f in [0.25, 0.75] {
                let x: CGFloat = x0 + CGFloat(f) * w
                let y: CGFloat = mid - 5 * CGFloat(sin(f * 2 * Double.pi))
                ctx.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)), with: .color(color))
            }
        }
        .frame(width: 30, height: 24)
    }
}


/// Кнопки под измерителем аранжировщика (решения пользователя), квадратные шириной с измеритель: при FIX (SETTINGS →
/// ARRANGE) — EXPANDED (8 строк на окно) и COMPACT (все дорожки на окно); ниже — карандаш: рисование кривой в окне AUTO
/// (неактивен, пока AUTO выключена).
struct ArrSideButtons: View {
    let model: AppModel
    let side: CGFloat

    var body: some View {
        let compact: Bool = model.settings.arrangeCompact
        return VStack(spacing: Layout.gap) {
            if !model.settings.arrangeScale {
                ArrBarButton(on: !compact, enabled: true, action: { model.setArrCompact(false) }) { c in
                    Image(systemName: "rectangle.expand.vertical").font(.system(size: 14, weight: .semibold)).foregroundStyle(c)
                }
                .frame(width: side, height: side)
                ArrBarButton(on: compact, enabled: true, action: { model.setArrCompact(true) }) { c in
                    Image(systemName: "rectangle.compress.vertical").font(.system(size: 14, weight: .semibold)).foregroundStyle(c)
                }
                .frame(width: side, height: side)
            }
            ArrBarButton(on: model.arrDraw, enabled: model.arrAuto, action: { model.arrDraw.toggle() }) { c in
                Image(systemName: "pencil").font(.system(size: 15, weight: .semibold)).foregroundStyle(c)
            }
            .frame(width: side, height: side)
        }
    }
}
