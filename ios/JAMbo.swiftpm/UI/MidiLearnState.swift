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
    // Свойства простых типов — вручную, без макроса (как в AppModel, AppModelObserved.swift; S14, объём сборки).
    private func put<T>(_ slot: ReferenceWritableKeyPath<MidiLearnState, T>, _ value: T, _ notify: Bool) {
        if notify {
            _$observationRegistrar.willSet(self, keyPath: slot)
            self[keyPath: slot] = value
            _$observationRegistrar.didSet(self, keyPath: slot)
        } else {
            self[keyPath: slot] = value
        }
    }

    @ObservationIgnored private var _on: Bool = false
    var on: Bool {
        get { access(keyPath: \._on); return _on }
        set { put(\._on, newValue, observedChanged(_on, newValue)) }
    }
    @ObservationIgnored private var _target: MidiTarget? = nil
    var target: MidiTarget? {
        get { access(keyPath: \._target); return _target }
        set { put(\._target, newValue, observedChanged(_target, newValue)) }
    }
    @ObservationIgnored private var _press: Bool = false
    var press: Bool {
        get { access(keyPath: \._press); return _press }
        set { put(\._press, newValue, observedChanged(_press, newValue)) }
    }
    @ObservationIgnored private var _last: String = ""
    var last: String {
        get { access(keyPath: \._last); return _last }
        set { put(\._last, newValue, observedChanged(_last, newValue)) }
    }
    /// Открытая вкладка меню MIDI.
    @ObservationIgnored private var _tab: MidiTab = .devices
    var tab: MidiTab {
        get { access(keyPath: \._tab); return _tab }
        set { put(\._tab, newValue, observedChanged(_tab, newValue)) }
    }
    /// Окно MIDI MAP: цель (nil — закрыто), условие, маппинг которого правит окно, страница, положение.
    @ObservationIgnored private var _mapTarget: MidiTarget? = nil
    var mapTarget: MidiTarget? {
        get { access(keyPath: \._mapTarget); return _mapTarget }
        set { put(\._mapTarget, newValue, observedChanged(_mapTarget, newValue)) }
    }
    @ObservationIgnored private var _pinned: String? = nil
    var pinned: String? {
        get { access(keyPath: \._pinned); return _pinned }
        set { put(\._pinned, newValue, observedChanged(_pinned, newValue)) }
    }
    @ObservationIgnored private var _mapPage: MidiMapPage = .main
    var mapPage: MidiMapPage {
        get { access(keyPath: \._mapPage); return _mapPage }
        set { put(\._mapPage, newValue, observedChanged(_mapPage, newValue)) }
    }
    @ObservationIgnored private var _mapPos: CGPoint? = nil
    var mapPos: CGPoint? {
        get { access(keyPath: \._mapPos); return _mapPos }
        set { put(\._mapPos, newValue, observedChanged(_mapPos, newValue)) }
    }
    /// Окно открыто из списка маппингов — после закрытия снова меню MIDI (reopenMenu ловит экран).
    @ObservationIgnored private var _mapBack: Bool = false
    var mapBack: Bool {
        get { access(keyPath: \._mapBack); return _mapBack }
        set { put(\._mapBack, newValue, observedChanged(_mapBack, newValue)) }
    }
    @ObservationIgnored private var _reopenMenu: Bool = false
    var reopenMenu: Bool {
        get { access(keyPath: \._reopenMenu); return _reopenMenu }
        set { put(\._reopenMenu, newValue, observedChanged(_reopenMenu, newValue)) }
    }
    @ObservationIgnored private var _presetInput: MidiPresetInput? = nil
    var presetInput: MidiPresetInput? {
        get { access(keyPath: \._presetInput); return _presetInput }
        set { put(\._presetInput, newValue, observedChanged(_presetInput, newValue)) }
    }
    var presets: MidiPresetBook = MidiPresetBook.decode(UserDefaults.standard.data(forKey: "midiPresets"))
    /// Последний тап по цели в LEARN (двойной — окно MIDI MAP).
    @ObservationIgnored var lastTap: (target: MidiTarget, at: Double)? = nil
}

/// Ход маппингов вне интерфейса: состояния TOGGLE, нажатые MIDI-кнопки (отпускание — той же кнопке), жест энкодера.
struct MidiRuntime {
    var toggles = MidiToggles()
    var down: Set<String> = []
    var gesture: DispatchWorkItem? = nil
    /// Чей поворот идёт (энкодер) — другой начинает новую запись UNDO.
    var gestureKey: String = ""
    /// STEP n: момент нажатия по индексу шага (быстрое отпускание ставит или снимает триг).
    var stepDown: [Int: Double] = [:]
    /// PAGE n: зажатые страницы (по порядку нажатия) — диапазон играющих.
    var pagesDown: [Int] = []
    /// Последнее нажатие ручки по позиции (двойное — двойной тап).
    var pressTap: [Int: Double] = [:]
    /// Нажатия ручек с SHIFT (режим TOUCH, 18.11): отпустили без поворота — SHIFT + тап; держат 1 с — значение по
    /// умолчанию (как пальцем); номер — поколение нажатия (отложенное запоминание проверяет, что нажатие то же).
    var pressShift: [Int: Int] = [:]
    var pressSerial: Int = 0
    /// Обратная связь (S13d): отправленные значения, последнее сообщение с источника (без эха), поколение выходов MidiHost.
    var feedback = MidiFeedback()
    var feedbackHold: [MidiSource: Double] = [:]
    var feedbackGen: Int = -1
    /// Контроллеры (JamboPad): отправленное состояние и поколение выходов при отправке.
    var controllerState: ControllerState? = nil
    var controllerGen: Int = -1
    /// MIDI-клок (S13e): SEND — планировщик; RECEIVE — входящий клок, шаг последней поправки фазы, игра на
    /// прошлом кадре (старт своей кнопкой — шаг 0 на ближайшем тике).
    var clockPlan = ClockPlan()
    var follower = ClockFollower()
    /// Вход, с которого пришёл последний тик клока (RECEIVE; при одновременной отдаче клок на это устройство не уходит).
    var clockSource: Int32 = 0
    var clockRefStep: Int = -1
    var clockWasPlaying: Bool = false
    /// AudioHost.restarts при последней привязке шагов к клоку.
    var clockAudioRestarts: Int = 0
}
