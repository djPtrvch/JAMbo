import SwiftUI

/// Вторая строка кнопок под верхней панелью — пока открыт аранжировщик (S15c, решения пользователя): слева квадратные
/// значки — сетка (ячейка; тап — меню шага), магнит, LOOP (как LOOP ROW сетки паттернов), AUTO (синусоида с точками),
/// возврат всех дорожек к таймлайну (стрелка к черте, как в Logic Pro); справа — INSERT, STEPS, REF, A/B. Высота — как у
/// строки окон EQ и модулей мастера.
struct ArrangeBar: View {
    static let height: CGFloat = 48
    let model: AppModel

    var body: some View {
        let a: Arrangement = model.project.arrange
        let side: CGFloat = ArrangeBar.height
        return HStack(spacing: Layout.gap) {
            ArrGridField(model: model).frame(width: side)
            ArrBarButton(on: a.snap, enabled: true, action: { model.toggleArrSnap() }) { c in ArrMagnetIcon(color: c) }
                .frame(width: side)
            ArrBarButton(on: a.loop, enabled: a.hasLoop, action: { model.toggleArrLoop() }) { c in
                Image(systemName: "repeat").font(.system(size: 18, weight: .semibold)).foregroundStyle(c)
            }
            .frame(width: side)
            ArrBarButton(on: false, enabled: false, action: {}) { c in ArrWaveIcon(color: c) }.frame(width: side)
            ArrReturnAll(model: model).frame(width: side)
            Spacer(minLength: 0)
            ArrBarText(title: "INSERT", on: model.arrInsert, enabled: true) { model.toggleArrInsert() }
                .frame(width: Layout.topButton)
            ArrBarText(title: "STEPS", on: a.hideSteps, enabled: true) { model.toggleArrSteps() }.frame(width: Layout.topButton)
            ArrBarText(title: "REF", on: false, enabled: false) {}.frame(width: Layout.topButton)
            ArrBarText(title: "A/B", on: false, enabled: false) {}.frame(width: Layout.topButton)
            // Правый край — как у ARRANGE (над измерителем справа ничего нет).
            Color.clear.frame(width: Layout.meterWidth)
        }
        .frame(height: ArrangeBar.height)
    }
}

/// Шаг сетки: тап — меню 1 BAR, 1/2, 1/4, 1 STEP.
struct ArrGridField: View {
    let model: AppModel
    @State private var frame: CGRect = .zero
    @Environment(\.theme) private var theme

    var body: some View {
        let a: Arrangement = model.project.arrange
        return ArrGridIcon(color: theme.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { frame = $0 }
        .contentShape(Rectangle())
        .onTapGesture {
            model.choice = ChoiceState(options: ArrGrid.names, columns: 4, current: a.grid, anchor: frame,
                                       pick: { model.setArrGrid($0) })
        }
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
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
    }
}

/// Все дорожки — к таймлайну: жёлтая, пока хоть одна играет сетку.
struct ArrReturnAll: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let on: Bool = model.anyOffTimeline
        return Image(systemName: "arrow.left.to.line")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(on ? theme.onAccent : theme.off)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(on ? theme.accent : theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
        .contentShape(Rectangle())
        .onTapGesture { model.returnToArrange(-1) }
    }
}

/// Значок магнита: подкова (дуга и две ножки) с полюсами-накладками на концах, наклонена, как 🧲.
struct ArrMagnetIcon: View {
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2 + 3)
            let r: CGFloat = 6.5
            let leg: CGFloat = 5
            var body = Path()
            body.move(to: CGPoint(x: c.x - r, y: c.y - leg))
            body.addLine(to: CGPoint(x: c.x - r, y: c.y))
            body.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            body.addLine(to: CGPoint(x: c.x + r, y: c.y - leg))
            ctx.stroke(body, with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .butt))
            let tipH: CGFloat = 4
            let tipY: CGFloat = c.y - leg - tipH - 1.5
            let left = CGRect(x: c.x - r - 2.5, y: tipY, width: 5, height: tipH)
            let right = CGRect(x: c.x + r - 2.5, y: tipY, width: 5, height: tipH)
            ctx.fill(Path(roundedRect: left, cornerRadius: 1), with: .color(color))
            ctx.fill(Path(roundedRect: right, cornerRadius: 1), with: .color(color))
        }
        .frame(width: 28, height: 28)
        .rotationEffect(.degrees(-45))
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

/// Значок сетки: одна ячейка (квадрат), без надписи.
struct ArrGridIcon: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .stroke(color, lineWidth: 2)
            .frame(width: 16, height: 16)
    }
}
