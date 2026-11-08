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
    /// Тональность после meta своим цветом (PROJECTS: близость по квинтовому кругу); nil — без неё.
    var key: (String, Color)? = nil
    /// Цвет текста (Autosave — жёлтый); current — строка горит акцентом (текущий проект).
    let tint: Color?
    let current: Bool
    let height: CGFloat
    let tap: () -> Void
    let rename: (() -> Void)?
    let delete: () -> Void
    /// Удержание и перетаскивание (порядок пресетов, ReorderState.hold); у остальных списков — нет.
    let hold: HoldDrag
    @State private var offset: CGFloat = 0
    @State private var open: Bool = false

    init(title: String, subtitle: String? = nil, meta: String? = nil, tint: Color? = nil, current: Bool = false,
         height: CGFloat = 44, tap: @escaping () -> Void, rename: (() -> Void)? = nil,
         delete: @escaping () -> Void, hold: HoldDrag = HoldDrag.off) {
        self.title = title
        self.subtitle = subtitle
        self.meta = meta
        self.tint = tint
        self.current = current
        self.height = height
        self.tap = tap
        self.rename = rename
        self.delete = delete
        self.hold = hold
    }

    private var reveal: CGFloat {
        return rename == nil ? SwipeRow.button : 2 * SwipeRow.button + 4
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            actions.opacity(offset < -1 ? 1 : 0)
            label
                .padding(.trailing, max(0, -offset))
                .gesture(gesture)
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
                if let k = key {
                    (Text(m + " · ").foregroundStyle(fg.opacity(0.65)) + Text(k.0).foregroundStyle(k.1))
                        .font(.system(size: 12)).lineLimit(1)
                } else {
                    Text(m).font(.system(size: 12)).lineLimit(1).opacity(0.65)
                }
            }
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 12)
        .modifier(Tile(current ? theme.accent : theme.panel, radius: 8, alignment: .leading))
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

    /// Свайп вбок и удержание (перетаскивание) — одним распознавателем; вертикальное движение — прокрутка списка.
    private var gesture: RowGesture {
        RowGesture(swipeChanged: { dx in
            let base: CGFloat = open ? -reveal : 0
            let x: CGFloat = base + dx
            offset = min(0, max(-reveal - 24, x))
        }, swipeEnded: {
            let show: Bool = offset < -reveal / 2
            open = show
            withAnimation(.easeOut(duration: 0.2)) { offset = show ? -reveal : 0 }
        }, hold: hold)
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

    /// Удержание строки k (HoldDrag в SwipeRow): поднять, вести за пальцем, отпустили — на новое место.
    func hold(_ k: Int, _ count: Int, pitch: CGFloat = 48, move: @escaping (Int, Int) -> Void) -> HoldDrag {
        return HoldDrag(began: { [weak self] in
            guard let s = self, s.from < 0 else { return }
            s.from = k
            s.dy = 0
        }, changed: { [weak self] dy in
            guard let s = self, s.from == k else { return }
            s.dy = dy
        }, ended: { [weak self] in
            self?.finish(k, count, pitch: pitch, move: move)
        })
    }

    func finish(_ k: Int, _ count: Int, pitch: CGFloat, move: (Int, Int) -> Void) {
        guard from == k else { return }
        let to: Int = target(count, pitch: pitch)
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            from = -1
            dy = 0
            ended = Date.timeIntervalSinceReferenceDate
            if to != k { move(k, to) }
        }
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

/// Вид перетаскиваемой строки: поднятая — крупнее, с тенью, за пальцем; соседи расступаются. Жест — ReorderState.hold.
struct ReorderDrag: ViewModifier {
    let index: Int
    let count: Int
    let state: ReorderState
    /// Шаг строк: высота строки и зазор.
    var pitch: CGFloat = 48

    func body(content: Content) -> some View {
        let lifted: Bool = state.from == index
        let y: CGFloat = state.offset(index, count, pitch: pitch)
        return content
            .scaleEffect(lifted ? 1.03 : 1)
            .shadow(color: .black.opacity(lifted ? 0.4 : 0), radius: 8, y: 3)
            .offset(y: y)
            .zIndex(lifted ? 1 : 0)
            .animation(lifted ? nil : .easeOut(duration: 0.15), value: y)
    }
}
