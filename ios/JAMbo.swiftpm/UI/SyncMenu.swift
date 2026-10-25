import SwiftUI

/// Бутерброд → SYNC (S13e, как ui/sync.ts веба): GENERAL — SYNC QUANTUM; MIDI CLOCK — вкл./выкл., SEND / RECEIVE,
/// выход клока, SYNC START/STOP, MIDI OFFSET. Раздел ABLETON LINK скрыт до этапа 9 (S14, перед App Store: неработающей
/// функции на виду быть не должно); настройки Link по-прежнему хранятся в SyncSettings.
struct SyncMenuPage: View {
    let model: AppModel
    let back: () -> Void
    @Environment(\.theme) private var theme

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
        VStack(alignment: .leading, spacing: 8) {
            MenuHead(title: "GENERAL")
            FieldLabel(title: "SYNC QUANTUM")
            HStack(spacing: 4) {
                ForEach(SyncSettings.quanta, id: \.self) { q in
                    MenuItem(title: q > 1 ? "\(q) BARS" : "1 BAR", current: s.quantum == q) { model.setSync { $0.quantum = q } }
                }
            }
            SettingsNote(text: "Phrase length in bars for lining up the start with other devices.")
        }
    }
}

/// MIDI CLOCK: вкл./выкл., источник, выход (SEND), SYNC START/STOP, MIDI OFFSET.
struct SyncClockSection: View {
    let model: AppModel

    var body: some View {
        let s: SyncSettings = model.settings.sync
        let send: Bool = s.source == .send
        return VStack(alignment: .leading, spacing: 8) {
            MenuHead(title: "MIDI CLOCK")
            ToggleRow(title: "MIDI CLOCK SYNC", isOn: s.clock) { on in model.setSync { $0.clock = on } }
            FieldLabel(title: "CLOCK SOURCE")
            HStack(spacing: 4) {
                MenuItem(title: "SEND", current: send) { model.setSync { $0.source = .send } }
                MenuItem(title: "RECEIVE", current: !send) { model.setSync { $0.source = .receive } }
            }
            if send {
                FieldLabel(title: "CLOCK OUTPUT")
                if model.midi.outputs.isEmpty { SettingsNote(text: "No MIDI outputs connected.") }
                MidiDeviceList(none: "ALL OUTPUTS", devices: model.midi.outputs, current: s.clockOut) { id in
                    model.setSync { $0.clockOut = id }
                }
            } else {
                SettingsNote(text: "The clock is received from the MIDI input chosen in MIDI → DEVICES. The project tempo follows it; without clock for 0.5 s the own tempo returns.")
            }
            ToggleRow(title: "SYNC START/STOP", isOn: s.midiStartStop) { on in model.setSync { $0.midiStartStop = on } }
            SyncOffsetRow(title: "MIDI OFFSET", value: s.midiOffset) { d in model.setSync { $0.midiOffset = SyncSettings.clampOffset($0.midiOffset + d) } }
            SettingsNote(text: send ? "ON: PLAY sends MIDI Start, stop sends MIDI Stop. The clock runs all the time while MIDI clock sync is on. MIDI OFFSET moves the sent clock later (+) or earlier (−) to line up with the other device."
                         : "ON: MIDI Start starts playback on the next clock tick, Continue resumes, Stop stops. MIDI OFFSET moves own steps later (+) or earlier (−) than the clock.")
        }
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
    @Environment(\.theme) private var theme

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
    @State private var task: Task<Void, Never>? = nil
    @Environment(\.theme) private var theme

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
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            while !Task.isCancelled {
                action()
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
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
