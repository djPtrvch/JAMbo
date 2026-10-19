import Foundation
import Observation

/// MIDI LEARN (S13b): режим, выбранная цель, TURN / PRESS (что выбирает тап по ручке), последний источник.
@Observable
final class MidiLearnState {
    var on: Bool = false
    var target: MidiTarget? = nil
    var press: Bool = false
    var last: String = ""
}

/// Ход маппингов вне интерфейса: состояния TOGGLE, нажатые MIDI-кнопки (отпускание — той же кнопке), жест энкодера.
struct MidiRuntime {
    var toggles = MidiToggles()
    var down: Set<String> = []
    var gesture: DispatchWorkItem? = nil
    /// STEP n: момент нажатия по индексу шага (быстрое отпускание ставит или снимает триг).
    var stepDown: [Int: Double] = [:]
}
