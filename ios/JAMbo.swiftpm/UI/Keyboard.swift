import SwiftUI

/// Клавиатура: слева CHORD и бутерброд, клавиши гаммы (с CHORD — подписи аккордов), справа ▲ ▼ октавы.
/// Столбцы — как шаги секвенсора. Мультитач.
struct KeyboardPanel: View {
    let model: AppModel
    let layout: Layout

    var body: some View {
        let _ = RedrawMeter.hit(.keyboard)
        HStack(spacing: Layout.stepGap) {
            VStack(spacing: Layout.gap) {
                ChordButton(model: model).frame(height: layout.keyHeight(model.project.scale)).midiTarget(model, "CHORD")
                BurgerButton { model.pianoMenuOpen.toggle() }.frame(maxHeight: .infinity)
            }
            .frame(width: layout.step)
            KeyRow(model: model)
                .onGeometryChange(for: CGRect.self) { g in g.frame(in: .named("root")) } action: { r in
                    if model.keysFrame != r { model.keysFrame = r }
                }
            OctavePair(model: model).frame(width: layout.step)
        }
        .frame(height: layout.pianoHeight(model.project.scale))
    }
}

/// Клавиши: имя ноты внизу (с CHORD — аккорд и римская ступень, «Em · i»); корневая чуть светлее; выбранные — белый
/// контур; нажатые и звучащие — белая заливка.
struct KeyRow: View {
    let model: AppModel
    @State private var touches: [SpatialEventCollection.Event.ID: Int] = [:]

    static let gap: CGFloat = 3

    var body: some View {
        let count: Int = model.keyCount
        let shown: Set<Int> = model.shownNotes
        let lit: Set<Int> = model.pressedNotes.union(model.playingNotes).union(model.heldNotes)
        return GeometryReader { geo in
            HStack(spacing: KeyRow.gap) {
                ForEach(0..<count, id: \.self) { k in
                    key(k, shown: shown, lit: lit).midiMarks(model, [.button("KEY \(k + 1)")])
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
        let chord: Bool = model.chordOn
        return Text(chord ? model.chordKeyLabel(k) : Params.noteName(n))
            .font(.system(size: 11))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 2)
            .foregroundStyle(fg)
            .padding(.bottom, 6)
            .tile(bg, radius: 6, alignment: .bottom)
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
        // MIDI LEARN: тап выбирает клавишу целью (нота не звучит).
        if model.midiLearn.on {
            touches[e.id] = Int.min
            model.learnTap(.button("KEY \(k + 1)"))
            return
        }
        guard let notes = model.keyNotes(k) else { return }
        let id: Int = e.id.hashValue
        touches[e.id] = id
        // Сила (KEY VELOCITY): по толчку iPad (акселерометр); без датчика — по месту на клавише (верх — тихо, низ — громко).
        let y: Double = Double(min(1, max(0, e.location.y / max(1, height))))
        model.keyPress(id: id, notes: notes, fallback: 0.2 + 0.8 * y)
    }

    private func up(_ eid: SpatialEventCollection.Event.ID) {
        guard let id = touches.removeValue(forKey: eid) else { return }
        model.keyRelease(id: id)
    }
}

/// CHORD: тап — вкл./выкл. текущего режима (с SHIFT — случайная прогрессия или ритм на выбранные страницы); режим
/// ARP — только рычажок ARPEGGIATOR в меню под CHORD (свайпа нет, 7.11); долгое нажатие — окно типов аккорда,
/// направлений арпеджио или стилей ритма. Слово (CHORD или ARP) и под ним тип — вместе по центру кнопки.
struct ChordButton: View {
    let model: AppModel
    /// Палец на кнопке (RANDOM — моментальная: горит, пока нажата).
    @State private var pressed: Bool = false

    var body: some View {
        let on: Bool = model.randomButton ? pressed : model.chordButtonOn
        let names: [String] = model.chordTypeNames
        let k: Int = min(names.count - 1, max(0, model.chordTypeIndex))
        let word: String = model.chordWord
        let sub: String = !model.arpMode && model.styleTrack ? model.drumGrooveName : names[k]
        return VStack(spacing: 2) {
            Text(word).font(.system(size: 12, weight: .semibold)).tracking(1)
            // Ударная дорожка с выключенным SETTINGS → RANDOM → DRUMS: стиля нет, слово остаётся на месте.
            Text(sub).font(.system(size: 10)).opacity(!model.arpMode && model.drumTrack && !model.settings.randomDrums ? 0 : 1)
        }
        .foregroundStyle(on ? theme.bg : theme.text)
        .tile(on ? theme.text : theme.panel2)
        .contentShape(Rectangle())
        .onTapGesture { model.chordTap() }
        .onLongPressGesture(minimumDuration: 0.5, perform: { model.chordMenuOpen = true },
                            onPressingChanged: { p in pressed = p })
    }
}

/// Стрелки октавы ▲ ▼ (мультитач): одна стрелка меняет октаву при отпускании; нажали вторую, пока зажата первая, —
/// Capture (октава не меняется).
struct OctavePair: View {
    let model: AppModel
    /// Касание → стрелка (0 — ▲, 1 — ▼).
    @State private var touches: [SpatialEventCollection.Event.ID: Int] = [:]
    /// Оба пальца уже дали Capture — отпускание октаву не меняет.
    @State private var captured: Bool = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: Layout.stepGap) {
                OctaveButton(title: "▲", lit: model.captureFlash).midiTarget(model, "OCTAVE ▲")
                OctaveButton(title: "▼", lit: model.captureFlash).midiTarget(model, "OCTAVE ▼")
            }
            .contentShape(Rectangle())
            .gesture(fingers(height: geo.size.height))
        }
    }

    private func fingers(height: CGFloat) -> some Gesture {
        SpatialEventGesture(coordinateSpace: .local)
            .onChanged { events in
                for e in events {
                    if case .active = e.phase {
                        if touches[e.id] == nil { down(e, height: height) }
                    } else {
                        up(e.id)
                    }
                }
            }
            .onEnded { events in
                for e in events { up(e.id) }
            }
    }

    private func down(_ e: SpatialEventCollection.Event, height: CGFloat) {
        if model.midiLearn.on { return }
        let arrow: Int = e.location.y < height / 2 ? 0 : 1
        if touches.values.contains(1 - arrow) {
            captured = true
            model.captureNotes()
        }
        touches[e.id] = arrow
    }

    private func up(_ eid: SpatialEventCollection.Event.ID) {
        guard let arrow = touches.removeValue(forKey: eid) else { return }
        if !captured {
            model.setOctave(model.octave + (arrow == 0 ? 1 : -1))
        }
        if touches.isEmpty { captured = false }
    }
}

struct OctaveButton: View {
    let title: String
    var lit: Bool = false

    var body: some View {
        Text(title)
            .font(.system(size: 14))
            .foregroundStyle(lit ? theme.bg : theme.text)
            .tile(lit ? theme.text : theme.panel2)
    }
}
