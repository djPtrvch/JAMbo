import SwiftUI

/// Кнопка в стиле веба: скруглённый прямоугольник панели, жирная подпись; горит акцентом, когда active.
struct InkButton: View {
    let title: String
    var active: Bool = false
    var height: CGFloat = 48
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(active ? theme.onAccent : theme.text)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(active ? theme.accent : theme.panel, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// Квадратная кнопка-крестик ✕ — закрыть окно (справа в верхней строке).
struct CloseButton: View {
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Text("✕")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.text)
                .frame(width: 48, height: 48)
                .background(theme.panel, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// Бутерброд — только полоски, без фона.
struct BurgerButton: View {
    let action: () -> Void
    @Environment(\.theme) private var theme

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
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
