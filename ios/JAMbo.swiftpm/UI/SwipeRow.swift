import SwiftUI
import UniformTypeIdentifiers

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

/// Перетаскивание строк списка (пресеты EQ и модулей мастера, свои папки библиотеки; решение пользователя): системное
/// перетаскивание iPad — удержание строки поднимает её карточку, строка под пальцем подсвечивается, отпустили — элемент
/// встаёт на её место. Жесты SwiftUI и UIKit на строке в iOS 18 не годятся: DragGesture в ScrollView забирает касание у
/// прокрутки, удержание снаружи строки не начинается, пока возможен тап внутри. Тап сразу после переноса не срабатывает.
@Observable
final class ReorderState {
    /// Поднятая строка (−1 — ничего) и строка, над которой палец (−1 — ни над какой).
    var from: Int = -1
    var to: Int = -1
    /// Время конца переноса — тап по строке в это же касание не срабатывает.
    @ObservationIgnored var ended: Double = 0

    /// Тап по строке разрешён (не только что перенесли).
    var tapAllowed: Bool {
        return Date.timeIntervalSinceReferenceDate - ended > 0.3
    }
}

struct ReorderDrag: ViewModifier {
    let index: Int
    let count: Int
    let state: ReorderState
    let move: (Int, Int) -> Void
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        let target: Bool = state.to == index && state.from >= 0 && state.from != index
        let s: ReorderState = state
        let k: Int = index
        return content
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.accent, lineWidth: target ? 2 : 0))
            .onDrag {
                s.from = k
                s.to = -1
                return NSItemProvider(object: NSString(string: "jambo-row-\(k)"))
            }
            .onDrop(of: [UTType.plainText], delegate: ReorderDrop(index: index, count: count, state: state, move: move))
    }
}

/// Строка — место переноса: палец над ней — подсветка, отпустили — move(from, сюда).
struct ReorderDrop: DropDelegate {
    let index: Int
    let count: Int
    let state: ReorderState
    let move: (Int, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        return state.from >= 0
    }

    func dropEntered(info: DropInfo) {
        state.to = index
    }

    func dropExited(info: DropInfo) {
        if state.to == index { state.to = -1 }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let from: Int = state.from
        state.from = -1
        state.to = -1
        state.ended = Date.timeIntervalSinceReferenceDate
        guard from >= 0, from < count, from != index else { return from >= 0 }
        move(from, index)
        return true
    }
}
