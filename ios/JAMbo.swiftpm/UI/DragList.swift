import SwiftUI

/// Список со своей прокруткой (без ScrollView) — для списков, где строки переставляют удержанием (ReorderDrag): свои
/// папки библиотеки, пресеты EQ и модулей мастера. Как колонка страниц: один жест с первого касания; палец пошёл по
/// вертикали раньше удержания — прокрутка (с инерцией), строка стоит 0,4 с — она поднимается и переносится, список
/// стоит (locked). ScrollView в iOS 18 и жест строки с первого касания мешают друг другу: работает только одно из двух.
/// Справа — тонкая полупрозрачная полоса, как у MenuScroll.
struct DragList<Content: View>: View {
    /// Перенос строк: строка поднята — список не прокручивается; прокрутка — тап по строке при отпускании не срабатывает.
    let reorder: ReorderState
    let content: Content
    @State private var offset: CGFloat = 0
    @State private var start: CGFloat? = nil
    /// Направление жеста: 0 — ещё не ясно, 1 — по вертикали (прокрутка), −1 — вбок или перенос строки.
    @State private var axis: Int = 0
    @State private var contentH: CGFloat = 0
    @State private var boxH: CGFloat = 0
    @Environment(\.theme) private var theme

    init(reorder: ReorderState, @ViewBuilder content: () -> Content) {
        self.reorder = reorder
        self.content = content()
    }

    private var maxOffset: CGFloat {
        return max(0, contentH - boxH)
    }

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                contentH = h
                offset = min(offset, max(0, h - boxH))
            }
            .offset(y: -offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                boxH = h
                offset = min(offset, max(0, contentH - h))
            }
            .simultaneousGesture(scroll)
            .overlay(alignment: .topTrailing) { bar }
    }

    private var scroll: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if reorder.active {
                    axis = -1
                    return
                }
                if start == nil {
                    start = offset
                    axis = 0
                }
                let dx: CGFloat = v.translation.width
                let dy: CGFloat = v.translation.height
                if axis == 0 && (abs(dx) > 8 || abs(dy) > 8) { axis = abs(dy) >= abs(dx) ? 1 : -1 }
                guard axis == 1, let s = start else { return }
                reorder.ended = Date.timeIntervalSinceReferenceDate
                offset = min(maxOffset, max(0, s - dy))
            }
            .onEnded { v in
                let s: CGFloat? = start
                let a: Int = axis
                start = nil
                axis = 0
                guard a == 1, !reorder.active, let s0 = s else { return }
                reorder.ended = Date.timeIntervalSinceReferenceDate
                // Инерция: туда, куда указывает скорость пальца.
                let target: CGFloat = min(maxOffset, max(0, s0 - v.predictedEndTranslation.height))
                withAnimation(.easeOut(duration: 0.45)) { offset = target }
            }
    }

    @ViewBuilder
    private var bar: some View {
        if contentH > boxH + 1 && boxH > 0 {
            let thumb: CGFloat = max(24, boxH * boxH / contentH)
            let at: CGFloat = maxOffset > 0 ? offset / maxOffset : 0
            Capsule().fill(theme.text.opacity(0.35))
                .frame(width: 3, height: thumb)
                .offset(y: at * (boxH - thumb))
                .allowsHitTesting(false)
        }
    }
}
