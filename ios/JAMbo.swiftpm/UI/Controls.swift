import SwiftUI

/// Кнопка в стиле веба: скруглённый прямоугольник панели, жирная подпись; горит акцентом, когда active.
struct InkButton: View {
    let title: String
    var active: Bool = false
    var height: CGFloat = 48
    /// «A/B» — в две строки с линией (окно стилей); иначе «/» — часть подписи (1/8, 1/16).
    var split: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(active ? theme.onAccent : theme.text)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(active ? theme.accent : theme.panel, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    /// Подпись «A/B» (стили Breaks/D&B, Trap/R&B) — в две строки, между ними горизонтальная линия.
    private var label: AnyView {
        let parts: [Substring] = split ? title.split(separator: "/", maxSplits: 1) : [Substring(title)]
        if parts.count < 2 { return AnyView(Text(title).lineLimit(1).minimumScaleFactor(0.7)) }
        let ink: Color = active ? theme.onAccent : theme.text
        return AnyView(VStack(spacing: 4) {
            Text(String(parts[0])).lineLimit(1).minimumScaleFactor(0.7)
            Rectangle().fill(ink.opacity(0.5)).frame(height: 1).padding(.horizontal, 10)
            Text(String(parts[1])).lineLimit(1).minimumScaleFactor(0.7)
        })
    }
}

/// Квадратная кнопка-крестик ✕ — закрыть окно (справа в верхней строке).
struct CloseButton: View {
    /// Сторона: в строке кнопок окон на месте центра — barH (квадрат во всю высоту строки).
    var side: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("✕")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.text)
                .frame(width: side, height: side)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// Бутерброд — только полоски, без фона.
struct BurgerButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().fill(theme.text).frame(width: 22, height: 2)
                }
            }
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Заголовок раздела меню (menu-head в вебе: 12 px, жирный, разрядка).
struct MenuHead: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
