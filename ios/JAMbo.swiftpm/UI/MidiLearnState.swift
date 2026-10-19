import CoreGraphics
import Foundation
import Observation

/// Страница окна MIDI MAP: главная (строки) или выбор на месте списка.
enum MidiMapPage: Equatable {
    case main
    case port
    case event
    case control
    case encoder
    case channel
    case range
    case feedback
    case cond
    case action
    case preset

    var title: String {
        switch self {
        case .main: return "MIDI map"
        case .port: return "Input port"
        case .event: return "Event type"
        case .control: return "Control type"
        case .encoder: return "Encoder"
        case .channel: return "Channel"
        case .range: return "Range"
        case .feedback: return "Feedback port"
        case .cond: return "Condition"
        case .action: return "Action"
        case .preset: return "Preset"
        }
    }
}

/// Ввод имени пресета маппингов (системное окно).
enum MidiPresetInput: Equatable {
    case save
    case rename(String)
}

/// MIDI LEARN (S13b) и окно MIDI MAP (S13c): режим, выбранная цель, TURN / PRESS (что выбирает тап по ручке),
/// последний источник; окно — цель, закреплённое условие, страница, положение (до перезапуска), пресеты маппингов.
@Observable
final class MidiLearnState {
    var on: Bool = false
    var target: MidiTarget? = nil
    var press: Bool = false
    var last: String = ""
    /// Открытая вкладка меню MIDI.
    var tab: MidiTab = .devices
    /// Окно MIDI MAP: цель (nil — закрыто), условие, маппинг которого правит окно, страница, положение.
    var mapTarget: MidiTarget? = nil
    var pinned: String? = nil
    var mapPage: MidiMapPage = .main
    var mapPos: CGPoint? = nil
    /// Окно открыто из списка маппингов — после закрытия снова меню MIDI (reopenMenu ловит экран).
    var mapBack: Bool = false
    var reopenMenu: Bool = false
    var presetInput: MidiPresetInput? = nil
    var presets: MidiPresetBook = MidiPresetBook.decode(UserDefaults.standard.data(forKey: "midiPresets"))
    /// Последний тап по цели в LEARN (двойной — окно MIDI MAP).
    @ObservationIgnored var lastTap: (target: MidiTarget, at: Double)? = nil
}

/// Ход маппингов вне интерфейса: состояния TOGGLE, нажатые MIDI-кнопки (отпускание — той же кнопке), жест энкодера.
struct MidiRuntime {
    var toggles = MidiToggles()
    var down: Set<String> = []
    var gesture: DispatchWorkItem? = nil
    /// STEP n: момент нажатия по индексу шага (быстрое отпускание ставит или снимает триг).
    var stepDown: [Int: Double] = [:]
    /// Последнее нажатие ручки по позиции (двойное — двойной тап).
    var pressTap: [Int: Double] = [:]
    /// Обратная связь (S13d): отправленные значения, последнее сообщение с источника (без эха), поколение выходов MidiHost.
    var feedback = MidiFeedback()
    var feedbackHold: [MidiSource: Double] = [:]
    var feedbackGen: Int = -1
}
