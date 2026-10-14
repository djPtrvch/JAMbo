import SwiftUI

/// Пианоролл: слева CHORD и бутерброд, клавиши гаммы (с CHORD — квадратные и строка прогрессии под ними),
/// справа ▲ ▼ октавы. Столбцы — как шаги секвенсора. Мультитач.
struct PianoRoll: View {
    let model: AppModel
    let layout: Layout

    var body: some View {
        HStack(spacing: Layout.stepGap) {
            VStack(spacing: Layout.gap) {
                ChordButton(model: model).frame(height: layout.keySide(model.project.scale))
                BurgerButton { model.pianoMenuOpen.toggle() }.frame(maxHeight: .infinity)
            }
            .frame(width: layout.step)
            keyArea
            VStack(spacing: Layout.stepGap) {
                OctaveButton(title: "▲") { model.setOctave(model.octave + 1) }
                OctaveButton(title: "▼") { model.setOctave(model.octave - 1) }
            }
            .frame(width: layout.step)
        }
        .frame(height: layout.pianoHeight(model.project.scale))
    }

    @ViewBuilder
    private var keyArea: some View {
        if model.chordMode[model.selectedTrack] {
            VStack(spacing: Layout.gap) {
                KeyRow(model: model).frame(height: layout.keySide(model.project.scale))
                ProgressionRow(model: model, layout: layout).frame(height: 44)
            }
        } else {
            KeyRow(model: model)
        }
    }
}

/// Клавиши: имя ноты внизу; корневая чуть светлее; выбранные — белый контур; нажатые и звучащие — белая заливка.
struct KeyRow: View {
    let model: AppModel
    @State private var touches: [SpatialEventCollection.Event.ID: Int] = [:]
    @Environment(\.theme) private var theme

    static let gap: CGFloat = 3

    var body: some View {
        let count: Int = model.keyCount
        let shown: Set<Int> = model.shownNotes
        let lit: Set<Int> = model.pressedNotes.union(model.playingNotes)
        return GeometryReader { geo in
            HStack(spacing: KeyRow.gap) {
                ForEach(0..<count, id: \.self) { k in
                    key(k, shown: shown, lit: lit)
                }
            }
            .contentShape(Rectangle())
            .gesture(fingers(width: geo.size.width, height: geo.size.height, count: count))
        }
    }

    private func key(_ k: Int, shown: Set<Int>, lit: Set<Int>) -> some View {
        let n: Int = model.keyNote(k)
        let isRoot: Bool = Scales.wrap(n, 12) == model.project.root
        let on: Bool = lit.contains(n)
        let bg: Color = on ? theme.text : (isRoot ? theme.root : theme.panel)
        let fg: Color = on ? theme.bg : (shown.contains(n) || isRoot ? theme.text : theme.dim)
        return Text(Params.noteName(n))
            .font(.system(size: 11))
            .foregroundStyle(fg)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .background(bg, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(shown.contains(n) && !on ? theme.text : Color.clear, lineWidth: 1))
    }

    private func fingers(width: CGFloat, height: CGFloat, count: Int) -> some Gesture {
        SpatialEventGesture(coordinateSpace: .local)
            .onChanged { events in
                for e in events {
                    if case .active = e.phase {
                        if touches[e.id] == nil { down(e, width: width, height: height, count: count) }
                    } else {
                        up(e.id)
                    }
                }
            }
            .onEnded { events in
                for e in events { up(e.id) }
            }
    }

    private func down(_ e: SpatialEventCollection.Event, width: CGFloat, height: CGFloat, count: Int) {
        let cell: CGFloat = (width + KeyRow.gap) / CGFloat(max(1, count))
        let k: Int = min(count - 1, max(0, Int(e.location.x / cell)))
        guard let notes = model.keyNotes(k) else { return }
        let id: Int = e.id.hashValue
        touches[e.id] = id
        // Сила (VELOCITY): палец — по месту на клавише (верх — тихо, низ — громко).
        let y: Double = Double(min(1, max(0, e.location.y / max(1, height))))
        model.keyDown(id: id, notes: notes, velocity: 0.2 + 0.8 * y)
    }

    private func up(_ eid: SpatialEventCollection.Event.ID) {
        guard let id = touches.removeValue(forKey: eid) else { return }
        model.keyUp(id: id)
    }
}

/// Строка под клавишами (CHORD): PROGRESSION шириной 3 клавиши и аккорды прогрессии по 2 клавиши
/// (не помещаются — делят оставшееся место поровну).
struct ProgressionRow: View {
    let model: AppModel
    let layout: Layout
    @State private var chipTouches: [SpatialEventCollection.Event.ID: Int] = [:]
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let count: Int = model.keyCount
            let keyW: CGFloat = (geo.size.width - KeyRow.gap * CGFloat(count - 1)) / CGFloat(count)
            let progW: CGFloat = 3 * keyW + 2 * KeyRow.gap
            HStack(spacing: KeyRow.gap) {
                ProgressionField(model: model).frame(width: progW)
                chips(width: geo.size.width - progW - KeyRow.gap, keyW: keyW)
            }
        }
    }

    private func chips(width: CGFloat, keyW: CGFloat) -> some View {
        let degrees: [Int] = model.progressionDegrees
        let n: Int = degrees.count
        let full: CGFloat = 2 * keyW + KeyRow.gap
        let w: CGFloat = min(full, (width - KeyRow.gap * CGFloat(n - 1)) / CGFloat(n))
        let lit: Set<Int> = model.pressedNotes.union(model.playingNotes)
        return HStack(spacing: KeyRow.gap) {
            ForEach(0..<n, id: \.self) { c in
                chip(c, lit: lit).frame(width: w)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .gesture(fingers(cell: w + KeyRow.gap, count: n))
    }

    private func chip(_ c: Int, lit: Set<Int>) -> some View {
        let notes: [Int] = model.chipNotes(c) ?? []
        let on: Bool = !notes.isEmpty && notes.allSatisfy { lit.contains($0) }
        return Text(model.chipName(c))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(on ? theme.bg : theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? theme.text : theme.panel, in: RoundedRectangle(cornerRadius: 6))
    }

    private func fingers(cell: CGFloat, count: Int) -> some Gesture {
        SpatialEventGesture(coordinateSpace: .local)
            .onChanged { events in
                for e in events {
                    if case .active = e.phase {
                        if chipTouches[e.id] == nil {
                            let c: Int = Int(e.location.x / cell)
                            guard c >= 0 && c < count, let notes = model.chipNotes(c) else { continue }
                            let id: Int = e.id.hashValue
                            chipTouches[e.id] = id
                            model.keyDown(id: id, notes: notes, velocity: 1)
                        }
                    } else if let id = chipTouches.removeValue(forKey: e.id) {
                        model.keyUp(id: id)
                    }
                }
            }
            .onEnded { events in
                for e in events {
                    if let id = chipTouches.removeValue(forKey: e.id) { model.keyUp(id: id) }
                }
            }
    }
}

/// PROGRESSION: палец вверх-вниз — 24 px на пункт; тап — меню.
struct ProgressionField: View {
    let model: AppModel

    var body: some View {
        let names: [String] = Scales.progressions.map { $0.name }
        let i: Int = model.progression[model.selectedTrack]
        return DragField(label: "PROGRESSION", value: names[i], pxPerUnit: 24,
                         get: { Double(model.progression[model.selectedTrack]) },
                         set: { model.setProgression(Int($0)) },
                         tap: { frame in model.choice = ChoiceState(options: names, columns: 2, current: i, anchor: frame,
                                                                     pick: { model.setProgression($0) }) },
                         undoable: false, model: model)
    }
}

struct ChordButton: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let on: Bool = model.chordMode[model.selectedTrack]
        return Text("CHORD")
            .font(.system(size: 12, weight: .semibold))
            .tracking(1)
            .foregroundStyle(on ? theme.bg : theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? theme.text : theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
            .contentShape(Rectangle())
            .onTapGesture { model.toggleChord() }
    }
}

struct OctaveButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .font(.system(size: 14))
            .foregroundStyle(theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.panel2, in: RoundedRectangle(cornerRadius: Layout.radius))
            .contentShape(Rectangle())
            .onTapGesture { action() }
    }
}
