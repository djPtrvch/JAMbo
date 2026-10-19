import SwiftUI

/// Поле с подписью над значением: палец вверх-вниз — pxPerUnit на пункт (вверх — больше); тап — меню (tap получает
/// рамку поля в координатах экрана «root»). undoable — поворот одной записью в UNDO.
struct DragField: View {
    let label: String
    let value: String
    let pxPerUnit: CGFloat
    let get: () -> Double
    let set: (Double) -> Void
    let tap: (CGRect) -> Void
    var undoable: Bool = true
    let model: AppModel
    @State private var start: Double? = nil
    @State private var moved: Bool = false
    @State private var frame: CGRect = .zero
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 9)).tracking(0.8).foregroundStyle(theme.dim)
            Text(value).font(.system(size: 15)).lineLimit(1).foregroundStyle(theme.text)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(start != nil ? theme.panel2 : theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { frame = $0 }
        .gesture(drag)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if start == nil {
                    start = get()
                    moved = false
                    if undoable { model.beginGesture() }
                }
                let dy: CGFloat = g.translation.height
                if abs(dy) > 10 { moved = true }
                if moved, let s = start {
                    set(s + (-dy / pxPerUnit).rounded())
                }
            }
            .onEnded { _ in
                if undoable { model.endGesture() }
                start = nil
                if !moved { tap(frame) }
            }
    }
}

/// Меню выбора пункта (SCALE, ROOT, PROGRESSION): сетка кнопок под полем (не помещается — над ним); тап мимо — закрыть.
struct ChoiceMenu: View {
    let model: AppModel
    let state: ChoiceState
    let screen: CGSize
    @Environment(\.theme) private var theme

    var body: some View {
        let width: CGFloat = CGFloat(state.columns) * 104
        let rows: Int = (state.options.count + state.columns - 1) / state.columns
        let height: CGFloat = CGFloat(rows) * 48 + 12
        let x: CGFloat = min(max(8, state.anchor.minX), screen.width - width - 8)
        let below: Bool = state.anchor.maxY + 6 + height < screen.height
        let y: CGFloat = below ? state.anchor.maxY + 6 : max(8, state.anchor.minY - 6 - height)
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.choice = nil }
            grid
                .padding(6)
                .frame(width: width)
                .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
                .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .offset(x: x, y: y)
        }
    }

    private var grid: some View {
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: state.columns)
        return LazyVGrid(columns: cols, spacing: 4) {
            ForEach(0..<state.options.count, id: \.self) { i in
                InkButton(title: state.options[i], active: i == state.current, height: 44) {
                    model.choice = nil
                    state.pick(i)
                }
            }
        }
    }
}

/// Меню клавиатуры (бутерброд под CHORD): 1 OCTAVE / 2 OCTAVES, KEY VELOCITY и SWING; правее кнопки, снизу вверх,
/// не выше строки шагов, шириной 4 шага.
struct PianoMenu: View {
    let model: AppModel
    let layout: Layout
    let screen: CGSize
    @Environment(\.theme) private var theme

    var body: some View {
        let width: CGFloat = 4 * layout.step + 3 * Layout.stepGap
        let x: CGFloat = 12 + layout.step + Layout.stepGap
        return ZStack(alignment: .bottomLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.pianoMenuOpen = false }
            content
                .padding(10)
                .frame(width: width)
                .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
                .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .padding(.leading, x)
                .padding(.bottom, 8)
        }
        .frame(width: screen.width, height: screen.height, alignment: .bottomLeading)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                InkButton(title: "1 OCTAVE", active: model.settings.pianoOctaves == 1, height: 44) {
                    model.updateSettings { $0.pianoOctaves = 1 }
                }
                InkButton(title: "2 OCTAVES", active: model.settings.pianoOctaves == 2, height: 44) {
                    model.updateSettings { $0.pianoOctaves = 2 }
                }
            }
            ToggleRow(title: "KEY VELOCITY", isOn: model.settings.velocity) { v in model.updateSettings { $0.velocity = v } }
            Text(model.settings.velocity
                 ? "Tap harder — louder: the iPad motion sensor feels each tap. Scales the track Velocity; REC writes it as the note velocity."
                 : "Keys play at the track Velocity.")
                .font(.system(size: 11))
                .foregroundStyle(theme.dim)
            SwingSlider(model: model)
        }
    }
}

/// Вкл./выкл. в меню — рычажок, как в iOS (строка 48, подпись слева, жёлтый — включён).
struct ToggleRow: View {
    let title: String
    let isOn: Bool
    let change: (Bool) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { change($0) })) {
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(theme.text)
        }
        .tint(theme.accent)
        .frame(minHeight: 48)
        .padding(.horizontal, 4)
    }
}

/// SWING дорожки (S12): ползунок с процентами (50–75 %), палец вбок; один жест — одна запись в UNDO.
struct SwingSlider: View {
    let model: AppModel
    @Environment(\.theme) private var theme
    @State private var dragging: Bool = false

    var body: some View {
        let p: ParamDef = Params.swing
        let v: Double = model.trackSwing
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SWING").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.text)
                Spacer()
                Text(p.format(v)).font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(theme.text)
            }
            GeometryReader { g in
                bar(g.size.width, p.toNorm(v))
                    .contentShape(Rectangle())
                    .gesture(drag(g.size.width))
            }
            .frame(height: 24)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private func bar(_ w: CGFloat, _ n: Double) -> some View {
        let x: CGFloat = w * CGFloat(n)
        return ZStack(alignment: .leading) {
            Capsule().fill(theme.meterTrack).frame(height: 6)
            Capsule().fill(theme.accent).frame(width: max(6, x), height: 6)
            Circle().fill(Color.white).frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .offset(x: min(max(0, x - 11), w - 22))
        }
        .frame(maxHeight: .infinity)
    }

    private func drag(_ w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if !dragging {
                    dragging = true
                    model.beginGesture()
                }
                let n: Double = Double(min(max(0, g.location.x / max(1, w)), 1))
                model.setSwing(Params.swing.fromNorm(n).rounded())
            }
            .onEnded { _ in
                dragging = false
                model.endGesture()
            }
    }
}
