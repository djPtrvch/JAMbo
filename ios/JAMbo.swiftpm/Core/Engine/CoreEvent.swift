/// Сообщение от интерфейса в аудиоколбэк (через SPSCQueue). Только простые значения — без ссылок.
public enum CoreEvent: Sendable {
    case none
    /// Тест-тон (DIAGNOSTICS): включить или выключить.
    case tone(on: Bool)
    /// Тест-тон: частота в Гц.
    case toneFrequency(Float)
    /// PLAY: старт с начала следующего блока или стоп.
    case play(Bool)
    /// PLAY по MIDI-клоку (S13e): шаг 0 — в кадре frame (может быть чуть в прошлом — сетка встаёт на тик).
    case playAt(frame: Int64)
    /// Шаг step по MIDI-клоку должен звучать в кадре frame: фаза подтягивается на 25 % ошибки.
    case clockPhase(step: Int, frame: Double)
    /// Темп, BPM.
    case tempo(Double)
    /// Метроном.
    case metronome(Bool)
    /// Тап по ячейке сетки во время игры: ячейка или Launcher.stop.
    case launch(track: Int, slot: Int)
    /// Тап по строке во время игры; atPass — в конце прохода строки (стрелки SWITCH).
    case scene(row: Int, atPass: Bool)
    /// Строки сетки переставили во время игры: активные ячейки и остановки — снова из снимка проекта.
    case adoptPlay
    /// Аранжировщик (S15): PLAY в окне аранжировщика (on) с позиции from (шаги); возврат дорожки к таймлайну
    /// (track < 0 — всех); переход MIX — все дорожки в сетку.
    case arrange(on: Bool, from: Int)
    case returnToArrange(track: Int)
    case leaveArrange
    /// Курсор аранжировки на позицию (шаги): при игре — со следующего шага.
    case seekArrange(Int)
    /// Автоматизация (S15f): ручка цели target (ArrAutoTarget) дорожки под пальцем — кривая не действует.
    case autoHold(track: Int, target: Int, on: Bool)
    /// Дорожку переставили (MIX) во время игры: ход дорожек (активная ячейка, остановка, ожидание, начало прохода)
    /// переезжает вместе с ними — играют дальше без паузы.
    case moveTrack(from: Int, to: Int)
    /// Живая нота с клавиатуры (id — касание; velocity 1 — без p-lock Level) и её отпускание.
    case noteOn(track: Int, note: Int, id: Int, velocity: Float)
    case noteOff(track: Int, id: Int)
    /// ▶ редактора сэмпла: отрезок a…b (доли) сэмпла hash; стоп.
    case preview(hash: UInt64, a: Double, b: Double)
    case previewStop
    /// ▶ редактора в режиме WARP: сэмпл hash целиком нотой дорожки — в Rate Stretch по карте, в темпе проекта.
    case warpPreview(track: Int, hash: UInt64)
    /// ▶ пресета в библиотеке (S11b): одна нота дорожки звуком hash (движок пресета) с p-lock его ручек.
    case presetNote(track: Int, note: Int, hash: UInt64, locks: NoteLocks)
    /// Запись стемов (S11d): готовность канала (дорожка или StemRing.master); тап по ● во время записи — дописать
    /// до конца прохода; PLAY во время записи — дописать всё и остановиться (ничего не пишется — стоп сразу).
    case stemArm(channel: Int, on: Bool)
    case stemFinish(channel: Int)
    case stopAfterStems
    /// REC редактора сэмпла (S11e): запись выхода дорожки или мастера (StemRing.master) — канал StemRing.capture,
    /// не дольше Capture.maxFrames; стоп.
    case captureStart(source: Int)
    case captureStop
}

/// P-lock ноты без коллекций: маска по VoiceParam и значения (17 — VoiceParam.count).
public struct NoteLocks: Sendable {
    public var mask: VoiceMask = 0
    public var vals: (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float,
                      Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    public init() {}

    /// Ручки пресета (id → значение) в p-lock голоса (основной поток).
    public init(_ params: [String: Double]) {
        for (id, v) in params {
            guard let k = VoiceParam.ids.firstIndex(of: id) else { continue }
            mask |= VoiceMask(1) << VoiceMask(k)
            withUnsafeMutableBytes(of: &vals) { raw in
                raw.bindMemory(to: Float.self)[k] = Float(v)
            }
        }
    }
}
