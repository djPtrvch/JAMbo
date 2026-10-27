import SwiftUI

/// Кнопка записи аранжировки — под STEPS в столбце справа от сетки паттернов (решение пользователя): только значок.
/// Включена — горит красным; пока играет сетка, её запуски клипов пишутся на таймлайн с курсора аранжировщика.
struct GridArrRecButton: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let on: Bool = model.arrRecArm
        return GridArrRecIcon(blocks: on ? Color.white : theme.text, dot: on ? Color.white : theme.rec)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? theme.rec : theme.panel2, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { model.toggleArrRec() }
    }
}

/// Значок: блоки аранжировки лесенкой (три строки) и точка записи справа.
struct GridArrRecIcon: View {
    let blocks: Color
    let dot: Color

    var body: some View {
        Canvas { ctx, size in
            let h: CGFloat = 4
            let gap: CGFloat = 2
            let w: CGFloat = 12
            let step: CGFloat = 4
            let r: CGFloat = 4
            let total: CGFloat = w + 2 * step + 4 + 2 * r
            let x0: CGFloat = (size.width - total) / 2
            let y0: CGFloat = (size.height - (3 * h + 2 * gap)) / 2
            var k: Int = 0
            while k < 3 {
                let rect = CGRect(x: x0 + CGFloat(k) * step, y: y0 + CGFloat(k) * (h + gap), width: w, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(blocks))
                k += 1
            }
            let cx: CGFloat = x0 + w + 2 * step + 4 + r
            let c = CGRect(x: cx - r, y: size.height / 2 - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: c), with: .color(dot))
        }
        .frame(width: 34, height: 20)
    }
}
