import SwiftUI

/// Строка кнопок аранжировщика (решения пользователя): высотой со строку стрелок над превью и миниатюрами
/// (AppModel.barH) — и закрывает её. Слева, по ширине превью, — сетка (меню GRID и SNAP TO GRID), TRIM (ножницы), курсор в начало
/// (стрелка к черте), LOOP; справа, по ширине колонки миниатюр, — AUTO (синусоида с точками), KNOBS (окно ручек),
/// STEPS (значок секвенсора), REF. Шаг сетки — в SETTINGS → ARRANGE.
struct ArrangeBar: View {
    let model: AppModel

    var body: some View {
        let a: Arrangement = model.project.arrange
        return HStack(spacing: Layout.gap) {
            HStack(spacing: Layout.gap) {
                // Сетка (решение пользователя, на месте магнита): тап — меню шага сетки и SNAP TO GRID.
                ArrBarButton(on: model.arrMenu == .grid, enabled: true, action: { model.arrMenu = model.arrMenu == .grid ? nil : .grid }) { c in
                    GridIcon(color: c)
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
                ArrBarButton(on: model.arrKnobs && !model.rollView, enabled: true, action: { model.toggleArrKnobs() }) { c in
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
            .modifier(Tile(bg))
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
    }
}

/// Кнопка-значок второй строки (магнит, AUTO).
struct ArrBarButton: View {
    let on: Bool
    let enabled: Bool
    var ring: Bool = false
    let action: () -> Void
    let icon: (Color) -> AnyView

    /// Значок — AnyView: не обобщённый вид, одна копия кода (объём сборки).
    init<Icon: View>(on: Bool, enabled: Bool, ring: Bool = false, action: @escaping () -> Void,
                     icon: @escaping (Color) -> Icon) {
        self.on = on
        self.enabled = enabled
        self.ring = ring
        self.action = action
        self.icon = { c in AnyView(icon(c)) }
    }

    var body: some View {
        let lit: Bool = on && enabled
        let fg: Color = !enabled ? theme.off : (on ? theme.bg : theme.text)
        let bg: Color = lit ? theme.text : theme.panel2
        return icon(fg)
            .modifier(Tile(bg))
            // Запись — красный контур толще (решение пользователя: 3 pt, как запись мастера).
            .overlay(RoundedRectangle(cornerRadius: Layout.radius).strokeBorder(ring ? theme.rec : Color.clear, lineWidth: 3))
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
    }
}

/// Курсор в самое начало таймлайна (при игре — сразу).
struct ArrReturnAll: View {
    let model: AppModel

    var body: some View {
        Image(systemName: "arrow.left.to.line")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(theme.text)
            .modifier(Tile(theme.panel2))
            .contentShape(Rectangle())
            .onTapGesture { model.arrToStart() }
    }
}

/// Значок сетки (решение пользователя, аранжировщик и пианоролл): «решётка» — две вертикальные и две горизонтальные
/// линии, концы выходят за пересечения.
struct GridIcon: View {
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = min(size.width, size.height)
            let x0: CGFloat = (size.width - s) / 2
            let y0: CGFloat = (size.height - s) / 2
            let a: CGFloat = s * 0.32
            let b: CGFloat = s * 0.68
            var p = Path()
            p.move(to: CGPoint(x: x0 + a, y: y0 + 1))
            p.addLine(to: CGPoint(x: x0 + a, y: y0 + s - 1))
            p.move(to: CGPoint(x: x0 + b, y: y0 + 1))
            p.addLine(to: CGPoint(x: x0 + b, y: y0 + s - 1))
            p.move(to: CGPoint(x: x0 + 1, y: y0 + a))
            p.addLine(to: CGPoint(x: x0 + s - 1, y: y0 + a))
            p.move(to: CGPoint(x: x0 + 1, y: y0 + b))
            p.addLine(to: CGPoint(x: x0 + s - 1, y: y0 + b))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .frame(width: 22, height: 22)
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


/// Кнопки под измерителем аранжировщика (решения пользователя), шириной с измеритель; три места одной высоты от
/// низа измерителя до линии Layout.bottomGuard над низом экрана (RootView; ниже — скругление экрана, кнопок нет): при FIX
/// (SETTINGS → ARRANGE) — одна кнопка EXPANDED ↔ COMPACT (8 строк на окно / все дорожки на окно); под ней, только пока AUTO
/// включена, — карандаш (рисование кривой) и корзина (вся автоматизация выбранной дорожки).
struct ArrSideButtons: View {
    let model: AppModel
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let compact: Bool = model.settings.arrangeCompact
        let h: CGFloat = height
        return VStack(spacing: Layout.gap) {
            if !model.settings.arrangeScale {
                // Одна кнопка (решение пользователя): тап — EXPANDED ↔ COMPACT; значок — текущий режим.
                ArrBarButton(on: false, enabled: true, action: { model.setArrCompact(!compact) }) { c in
                    Image(systemName: compact ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(c)
                }
                .frame(width: width, height: h)
            }
            if model.arrAuto {
                ArrBarButton(on: model.arrDraw, enabled: true, action: { model.toggleArrDraw() }) { c in
                    Image(systemName: "pencil").font(.system(size: 15, weight: .semibold)).foregroundStyle(c)
                }
                .frame(width: width, height: h)
                // Корзина (решение пользователя, вместо ластика): вся автоматизация выбранной дорожки — одна запись UNDO.
                ArrBarButton(on: false, enabled: model.arrAutoCanClear, action: { model.arrAutoClearTrack() }) { c in
                    Image(systemName: "trash").font(.system(size: 15, weight: .semibold)).foregroundStyle(c)
                }
                .frame(width: width, height: h)
            }
        }
    }
}
