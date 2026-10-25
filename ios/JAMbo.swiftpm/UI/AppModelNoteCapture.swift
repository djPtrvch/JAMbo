import Foundation

// Capture (как в Live): ноты, сыгранные без REC, запоминаются у каждой дорожки; ▲ + ▼ ставит последнюю фразу
// выбранной дорожки в её играющий клип (одна запись UNDO).

/// Нота, сыгранная без REC: касание, с игрой ли (тик транспорта), время нажатия и отпускания (с), ноты, сила.
struct CapturedKey {
    let id: Int
    let playing: Bool
    let tick: Int
    let t0: Double
    var t1: Double?
    let notes: [Int]
    let velocity: Double?
}

extension AppModel {
    /// Запомненных нажатий у дорожки (старые уходят; фраза — не длиннее 8 страниц).
    static let captureKeep: Int = 512

    func captureDown(id: Int, track ti: Int, notes: [Int], velocity: Double?) {
        guard ti >= 0 && ti < captureLog.count else { return }
        let tick: Int? = heardTick()
        let key = CapturedKey(id: id, playing: tick != nil, tick: tick ?? 0, t0: Date.timeIntervalSinceReferenceDate,
                              t1: nil, notes: notes, velocity: velocity)
        var log: [CapturedKey] = captureLog[ti]
        if log.count >= AppModel.captureKeep { log.removeFirst(log.count - AppModel.captureKeep + 1) }
        log.append(key)
        captureLog[ti] = log
    }

    func captureUp(id: Int, track ti: Int) {
        guard ti >= 0 && ti < captureLog.count else { return }
        guard let i = captureLog[ti].lastIndex(where: { $0.id == id && $0.t1 == nil }) else { return }
        captureLog[ti][i].t1 = Date.timeIntervalSinceReferenceDate
    }

    /// ▲ + ▼: фраза выбранной дорожки — в её играющий клип. Нечего ловить — ничего не происходит.
    func captureNotes() {
        let ti: Int = selectedTrack
        guard channel == .track && ti < captureLog.count && ti < project.tracks.count else { return }
        let tr = project.tracks[ti]
        guard let clip = tr.clips[tr.slot] else { return }
        let playingNow: Bool = heardTick() != nil
        let log: [CapturedKey] = captureLog[ti].filter { $0.playing == playingNow }
        guard let first = log.first else { return }
        let now: Double = Date.timeIntervalSinceReferenceDate
        let stepSeconds: Double = 60 / project.bpm / 4
        let start: Int = live.trackStart[ti]
        var all: [PhraseNote] = []
        for k in log {
            let len: Int = RecordClock.length(seconds: (k.t1 ?? now) - k.t0, stepSeconds: stepSeconds)
            var step: Int
            if playingNow {
                step = AppModel.patternStep(k.tick - start, speed: clip.speed)
            } else {
                let d: Double = (k.t0 - first.t0) / stepSeconds
                step = Int(settings.record.quantize ? d.rounded() : d.rounded(.down))
            }
            all.append(PhraseNote(step: step, notes: k.notes, velocity: k.velocity, len: len))
        }
        var phrase: [PhraseNote] = NoteCapture.phrase(all)
        // Без игры фраза начинается с шага 1.
        if !playingNow, let s0 = phrase.first?.step {
            for i in phrase.indices { phrase[i].step -= s0 }
        }
        if phrase.isEmpty { return }
        edit { p in AppModel.inPlaying(&p.tracks[ti]) { t in _ = t.capture(phrase) } }
        captureLog[ti].removeAll()
        captureFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.captureFlash = false }
    }

    /// Шаг паттерна по тику от начала клипа (без счёта по кругу), со скоростью клипа (как Clip.localStep).
    static func patternStep(_ o: Int, speed: Int) -> Int {
        if speed > 0 { return o * 2 }
        return o >> (-speed)
    }
}
