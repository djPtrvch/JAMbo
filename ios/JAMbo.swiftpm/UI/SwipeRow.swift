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

/// Перетаскивание строк списка пресетов (EQ и модулей мастера, решение пользователя): удержание строки (0,4 с) —
/// строка поднимается и едет за пальцем, остальные расступаются; отпустили — пресет встаёт на новое место. Пока
/// тянут, список не прокручивается; тап сразу после перетаскивания не загружает пресет.
@Observable
final class ReorderState {
    /// Тянется строка (−1 — ничего) и сдвиг пальца по вертикали.
    var from: Int = -1
    var dy: CGFloat = 0
    /// Время конца перетаскивания — тап по строке в это же касание не срабатывает.
    @ObservationIgnored var ended: Double = 0

    var active: Bool { return from >= 0 }

    /// Тап по строке разрешён (не тянут и не только что отпустили).
    var tapAllowed: Bool {
        return from < 0 && Date.timeIntervalSinceReferenceDate - ended > 0.3
    }

    func target(_ count: Int, pitch: CGFloat) -> Int {
        let shift: Int = Int((dy / pitch).rounded())
        return min(count - 1, max(0, from + shift))
    }

    /// Сдвиг строки k: тянущаяся — за пальцем, между старым и новым местом — на строку в сторону.
    func offset(_ k: Int, _ count: Int, pitch: CGFloat) -> CGFloat {
        if from < 0 { return 0 }
        if k == from { return dy }
        let t: Int = target(count, pitch: pitch)
        if from < k && k <= t { return -pitch }
        if t <= k && k < from { return pitch }
        return 0
    }
}

struct ReorderDrag: ViewModifier {
    let index: Int
    let count: Int
    let state: ReorderState
    /// Шаг строк: высота строки и зазор.
    var pitch: CGFloat = 48
    let move: (Int, Int) -> Void
    /// Касание идёт (сбрасывается и при отмене жеста — тогда строка встаёт, куда дотянули).
    @GestureState private var touching: Bool = false
    /// Касание (как в колонке страниц, PagesColumn): метка начала (0 — нет) и сдвиг пальца до удержания.
    @State private var downAt: Double = 0
    @State private var moved: Bool = false

    func body(content: Content) -> some View {
        let lifted: Bool = state.from == index
        let y: CGFloat = state.offset(index, count, pitch: pitch)
        return content
            .scaleEffect(lifted ? 1.06 : 1)
            .shadow(color: .black.opacity(lifted ? 0.5 : 0), radius: 8)
            .offset(y: y)
            .zIndex(lifted ? 1 : 0)
            .animation(lifted ? nil : .easeOut(duration: 0.15), value: y)
            .simultaneousGesture(gesture)
            .onChange(of: touching) { _, t in if !t { finish() } }
    }

    /// Как перенос страницы в колонке страниц: касание с первого пикселя; палец 0,4 с почти на месте (до 8 pt) —
    /// строка поднимается и дальше идёт за пальцем, соседи расступаются; сдвинулся раньше — это прокрутка списка
    /// (пока строка поднята, список не прокручивается).
    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($touching) { _, s, _ in s = true }
            .onChanged { v in
                if downAt == 0 { arm() }
                if state.from == index {
                    state.dy = v.translation.height
                    return
                }
                if abs(v.translation.height) > 8 || abs(v.translation.width) > 8 { moved = true }
            }
            .onEnded { _ in finish() }
    }

    /// Начало касания: через 0,4 с без сдвига — строка поднята.
    private func arm() {
        let t: Double = Date.timeIntervalSinceReferenceDate
        downAt = t
        moved = false
        let s: ReorderState = state
        let k: Int = index
        Later.run(0.4) {
            guard downAt == t, !moved, s.from < 0 else { return }
            s.from = k
            s.dy = 0
        }
    }

    private func finish() {
        downAt = 0
        guard state.from == index else { return }
        let to: Int = state.target(count, pitch: pitch)
        let from: Int = state.from
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            state.from = -1
            state.dy = 0
            state.ended = Date.timeIntervalSinceReferenceDate
            if to != from { move(from, to) }
        }
    }
}
