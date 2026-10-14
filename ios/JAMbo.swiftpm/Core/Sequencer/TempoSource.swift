// Источник такта (как src/tempoSource.ts веба): темп и фаза, по которым секвенсор ставит шаги.
// Сейчас один источник — внутренний; LinkTempoSource (Ableton Link) появится позже.
// Время — секунды часов звука (кадры ядра / 48000), доля — четверть, шаг — 1/4 доли.

public enum TempoGrid {
    /// Долей в такте: граница такта — запуск паттернов и строк, акцент метронома.
    public static let quantumBeats = 4.0
    /// Шагов (1/16) в доле.
    public static let stepsPerBeat = 4.0

    public static func isBarStart(_ beat: Double) -> Bool {
        let q = beat / quantumBeats
        return abs(q - q.rounded()) < 1e-9
    }
}

public protocol TempoSource: AnyObject {
    var tempo: Double { get }
    /// Доля (от начала игры) в момент time, с.
    func beatAt(_ time: Double) -> Double
    /// Момент, с, для доли beat.
    func timeAt(_ beat: Double) -> Double
}

/// Свой источник: темп и точка отсчёта — доля b0 в момент t0. Смена темпа не сдвигает долю.
/// Живёт в аудиопотоке (меняется только там).
public final class InternalTempoSource: TempoSource {
    private var t0: Double = 0
    private var b0: Double = 0
    public private(set) var tempo: Double

    public init(bpm: Double) {
        tempo = bpm
    }

    public func beatAt(_ time: Double) -> Double {
        return b0 + (time - t0) * tempo / 60
    }

    public func timeAt(_ beat: Double) -> Double {
        return t0 + (beat - b0) * 60 / tempo
    }

    /// Старт: доля 0 — в момент at.
    public func start(at: Double) {
        t0 = at
        b0 = 0
    }

    /// С доли beat действует новый темп; момент этой доли считается по прежнему — доля не прыгает.
    public func retempo(_ bpm: Double, fromBeat beat: Double) {
        if bpm == tempo { return }
        t0 = timeAt(beat)
        b0 = beat
        tempo = bpm
    }

    /// Темп без игры — сразу.
    public func set(_ bpm: Double) {
        tempo = bpm
    }
}
