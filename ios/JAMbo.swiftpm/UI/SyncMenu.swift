import SwiftUI

/// Бутерброд → SYNC (S13e, как ui/sync.ts веба): GENERAL — SYNC QUANTUM; MIDI CLOCK — вкл./выкл., SEND / RECEIVE,
/// выход или вход клока, SYNC START/STOP, MIDI OFFSET. Раздел ABLETON LINK скрыт до этапа 9 (S14, перед App Store: неработающей
/// функции на виду быть не должно); настройки Link по-прежнему хранятся в SyncSettings.
struct SyncMenuPage: View {
    let model: AppModel
    let back: () -> Void

    private var s: SyncSettings { return model.settings.sync }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuBackHeader(title: "SYNC", back: back)
            MenuScroll {
                VStack(alignment: .leading, spacing: 8) {
                    general
                    Divider().overlay(theme.line).padding(.vertical, 6)
                    SyncClockSection(model: model)
                }
                .padding(.trailing, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var general: some View {
        let m: AppModel = model
        let q0: Int = s.quantum
        let quanta: [MenuChoice] = SyncSettings.quanta.map { (q: Int) -> MenuChoice in
            MenuChoice(title: q > 1 ? "\(q) BARS" : "1 BAR", current: q0 == q) { m.setSync { $0.quantum = q } }
        }
        return FormRows(rows: [
            .head("GENERAL"),
            .label("SYNC QUANTUM"),
            .choices(quanta),
            .note("Phrase length in bars for lining up the start with other devices."),
        ])
    }
}

/// MIDI CLOCK: вкл./выкл., SEND и RECEIVE (по отдельности или вместе, 8.11), выходы (SEND, несколько) и вход
/// (RECEIVE), SYNC START/STOP, MIDI OFFSET.
struct SyncClockSection: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        let s: SyncSettings = m.settings.sync
        var rows: [FormRow] = [
            .head("MIDI CLOCK"),
            .toggle("MIDI CLOCK SYNC", s.clock) { on in m.setSync { $0.clock = on } },
            .toggle("SEND CLOCK", s.send) { on in m.setSync { $0.send = on } },
        ]
        if s.send {
            rows.append(.label("CLOCK OUTPUTS"))
            if m.midi.outputs.isEmpty { rows.append(.note("No MIDI outputs connected.")) }
            rows.append(.view(AnyView(ClockOutputList(model: m))))
        }
        rows.append(.toggle("RECEIVE CLOCK", s.receive) { on in m.setSync { $0.receive = on } })
        if s.receive {
            rows.append(.label("CLOCK INPUT"))
            if m.midi.inputs.isEmpty { rows.append(.note("No MIDI inputs connected.")) }
            rows.append(.view(AnyView(MidiDeviceList(none: "ALL INPUTS", devices: m.midi.inputs, current: s.clockIn) { id in
                m.setClockIn(id)
            })))
            rows.append(.note(s.send
                ? "The project follows the clock from this input and passes it on to the clock outputs (not back to the device it comes from). Without clock for 0.5 s the own tempo returns."
                : "The project tempo follows the clock from this input; without clock for 0.5 s the own tempo returns."))
        }
        rows.append(.toggle("SYNC START/STOP", s.midiStartStop) { on in m.setSync { $0.midiStartStop = on } })
        rows.append(.view(AnyView(SyncOffsetRow(title: "MIDI OFFSET", value: s.midiOffset) { d in
            m.setSync { $0.midiOffset = SyncSettings.clampOffset($0.midiOffset + d) }
        })))
        rows.append(.note(s.receive
            ? "ON: MIDI Start starts playback on the next clock tick, Continue resumes, Stop stops\(s.send ? "; Start and Stop are passed on" : ""). MIDI OFFSET moves own steps later (+) or earlier (−) than the clock."
            : "ON: PLAY sends MIDI Start, stop sends MIDI Stop. The clock runs all the time while MIDI clock sync is on. MIDI OFFSET moves the sent clock later (+) or earlier (−) to line up with the other device."))
        return FormRows(rows: rows)
    }
}

/// OFFSET: ◀ значение ▶ — шаг 1 ms, удержание стрелки — повтор (через 0,35 с, каждые 50 мс); палец по значению
/// вправо-влево — быстро, 1 ms на 3 px (решение пользователя).
struct SyncOffsetRow: View {
    static let pxPerMs: CGFloat = 3
    let title: String
    let value: Int
    let step: (Int) -> Void
    /// Сколько миллисекунд уже прибавлено текущим жестом (nil — пальца нет).
    @State private var applied: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(title: title)
            HStack(spacing: 4) {
                RepeatArrow(title: "◀") { step(-1) }
                Text((value > 0 ? "+" : "") + "\(value) ms")
                    .font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(theme.text)
                    .frame(width: 100, height: 44)
                    .background(applied != nil ? theme.panel2 : theme.panel, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                    .gesture(swipe)
                RepeatArrow(title: "▶") { step(1) }
            }
        }
    }

    /// Сдвиг вбок (HorizontalSwipe: вертикальное движение — прокрутка меню).
    private var swipe: HorizontalSwipe {
        HorizontalSwipe(changed: { dx in
            let units: Int = Int((dx / SyncOffsetRow.pxPerMs).rounded())
            let done: Int = applied ?? 0
            if units != done { step(units - done) }
            applied = units
        }, ended: { applied = nil })
    }
}

/// Стрелка с повтором при удержании: кнопка (нажатие — по isPressed стиля), а не DragGesture от 0 px — касание,
/// с которого начали прокрутку меню, достаётся прокрутке.
struct RepeatArrow: View {
    let title: String
    let action: () -> Void
    @State private var task: LaterTask? = nil

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold)).foregroundStyle(theme.text)
            .frame(width: 48, height: 36)
            .background(task != nil ? theme.panel2 : theme.panel, in: RoundedRectangle(cornerRadius: Layout.radius))
            .contentShape(Rectangle())
            .overlay {
                Button(action: {}) { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(PressStyle { down in
                        if down {
                            if task == nil { begin() }
                        } else {
                            task?.cancel()
                            task = nil
                        }
                    })
            }
    }

    private func begin() {
        action()
        let a: () -> Void = action
        task = Later.every(0.05, first: 0.35) {
            a()
            return true
        }
    }
}

/// Стиль кнопки, который сообщает о нажатии и отпускании (повтор при удержании); вид — как у содержимого.
struct PressStyle: ButtonStyle {
    let pressed: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, down in pressed(down) }
    }
}

/// CLOCK OUTPUTS: ALL OUTPUTS или любой набор выходов (тап — добавить или убрать; убран последний — снова все).
struct ClockOutputList: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        let s: SyncSettings = m.settings.sync
        let gone: [Int32] = s.clockOuts.filter { id in !m.midi.outputs.contains(where: { $0.id == id }) }
        return VStack(alignment: .leading, spacing: 4) {
            MenuItem(title: "ALL OUTPUTS", current: s.clockOuts.isEmpty) { m.setSync { $0.clockOuts = [] } }
            ForEach(m.midi.outputs) { d in
                MenuItem(title: d.name, current: s.clockOuts.contains(d.id)) { m.setSync { $0.toggleOut(d.id) } }
            }
            if !gone.isEmpty {
                MenuItem(title: "NOT CONNECTED (\(gone.count))", enabled: false, current: true) {}
            }
        }
    }
}
