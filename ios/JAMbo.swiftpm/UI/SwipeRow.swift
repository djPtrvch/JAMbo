import SwiftUI

/// Строка списка (как в списках iPad; пресеты модулей мастера и EQ, проекты): тап — действие; свайп влево открывает
/// справа кнопки — карандаш на сером (RENAME) и корзина на красном (DELETE), без rename — только корзина; строка
/// сужается, имя остаётся видно; свайп вправо или тап по открытой строке — закрыть. Решение пользователя (S9):
/// везде одно такое меню.
struct SwipeRow: View {
    static let button: CGFloat = 52
    let title: String
    let subtitle: String?
    /// Справа (у проектов — темп, нота, гамма); у открытой строки не видно.
    let meta: String?
    /// Цвет текста (Autosave — жёлтый); current — строка горит акцентом (текущий проект).
    let tint: Color?
    let current: Bool
    let height: CGFloat
    let tap: () -> Void
    let rename: (() -> Void)?
    let delete: () -> Void
    @State private var offset: CGFloat = 0
    @State private var open: Bool = false
    @Environment(\.theme) private var theme

    init(title: String, subtitle: String? = nil, meta: String? = nil, tint: Color? = nil, current: Bool = false,
         height: CGFloat = 44, tap: @escaping () -> Void, rename: (() -> Void)? = nil,
         delete: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.meta = meta
        self.tint = tint
        self.current = current
        self.height = height
        self.tap = tap
        self.rename = rename
        self.delete = delete
    }

    private var reveal: CGFloat {
        return rename == nil ? SwipeRow.button : 2 * SwipeRow.button + 4
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            actions.opacity(offset < -1 ? 1 : 0)
            label
                .padding(.trailing, max(0, -offset))
                .gesture(swipe)
                .onTapGesture {
                    if open { close() } else { tap() }
                }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var fg: Color {
        if current { return theme.onAccent }
        return tint ?? theme.text
    }

    private var label: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                if let s = subtitle {
                    Text(s).font(.system(size: 12)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let m = meta, offset > -1 {
                Text(m).font(.system(size: 12)).lineLimit(1).opacity(0.65)
            }
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(current ? theme.accent : theme.panel, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private var actions: some View {
        HStack(spacing: 4) {
            if let r = rename {
                icon("pencil", Color(hex: 0x8e8e93)) {
                    close()
                    r()
                }
            }
            icon("trash", theme.rec) {
                close()
                delete()
            }
        }
    }

    private func icon(_ name: String, _ bg: Color, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: SwipeRow.button, height: height)
                .background(bg, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    /// Горизонтальный свайп (вертикальный — прокрутка списка, HorizontalSwipe).
    private var swipe: HorizontalSwipe {
        HorizontalSwipe(changed: { dx in
            let base: CGFloat = open ? -reveal : 0
            let x: CGFloat = base + dx
            offset = min(0, max(-reveal - 24, x))
        }, ended: {
            let show: Bool = offset < -reveal / 2
            open = show
            withAnimation(.easeOut(duration: 0.2)) { offset = show ? -reveal : 0 }
        })
    }

    private func close() {
        open = false
        withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
    }
}
