import Foundation
import Observation

// REC в редакторе сэмпла (S11e, как sampleedit.ts веба): тап — меню RECORD FROM (вход, дорожка, мастер), выбор сразу
// начинает запись; тап во время записи — стоп; не дольше 60 с (и при закрытом окне). Записанное (CAF float 32,
// имя «источник чч-мм-сс») встаёт на дорожку, выбранную при начале записи (одна запись UNDO), копия — в RECORDINGS.

/// Источник записи.
enum RecSource: Equatable {
    case input(uid: String)
    case channel(Int)
}

/// Идущая запись: дорожка, имя источника, вход или колбэк, начало (секунды отсчёта Date).
struct RecTake: Equatable {
    let track: Int
    let name: String
    let input: Bool
    var start: Double
    /// Вход ещё открывается (сессия переходит в режим записи) — тап не останавливает.
    var opening: Bool = false
    /// Нажали ■ — ждём конец записи из колбэка (с момента stopAt).
    var stopping: Bool = false
    var stopAt: Double = 0
}

@Observable
final class SampleRec {
    /// Меню RECORD FROM: рамка кнопки REC («root»); nil — закрыто.
    var menu: CGRect? = nil
    var ports: [InputPort] = []
    var take: RecTake? = nil
    /// Секунд записано (меняется раз в секунду — строка и кнопка).
    var seconds: Int = 0
    var peaks = RecPeaks()
    /// Ошибка начала записи (окно с сообщением).
    var error: String? = nil
    /// Рамка SCALE верхней панели («root»): кнопки редактора сэмпла начинаются от её левого края.
    var scaleFrame: CGRect = .zero
}

extension AppModel {
    /// Тап по REC: во время записи — стоп, иначе меню источника (только у дорожки).
    func tapRec(_ frame: CGRect) {
        if let t = sampleRec.take {
            if !t.opening { stopRec() }
            return
        }
        if channel != .track { return }
        sampleRec.ports = InputCapture.ports()
        sampleRec.menu = frame
    }

    func beginRec(_ src: RecSource, name: String) {
        sampleRec.menu = nil
        if sampleRec.take != nil || channel != .track { return }
        ensureAudio()
        let now: Double = Date.timeIntervalSinceReferenceDate
        sampleRec.peaks = RecPeaks()
        sampleRec.seconds = 0
        switch src {
        case .channel(let c):
            let ring = audio.core.sequencer.stemRing
            ring.prepare()
            if stems.recording.contains(StemRing.capture) { return }
            sampleRec.take = RecTake(track: selectedTrack, name: name, input: false, start: now)
            audio.core.events.push(.captureStart(source: c))
        case .input(let uid):
            sampleRec.take = RecTake(track: selectedTrack, name: name, input: true, start: now, opening: true)
            Task { @MainActor in
                let ok: Bool = await self.audio.beginInput(uid)
                guard self.sampleRec.take != nil else { return }
                if ok {
                    self.sampleRec.take?.opening = false
                    self.sampleRec.take?.start = Date.timeIntervalSinceReferenceDate
                } else {
                    self.sampleRec.take = nil
                    self.sampleRec.error = InputCapture.allowed ? "No access to the audio input"
                        : "Microphone access is not enabled for this app (Swift Playgrounds → App Settings → Capabilities → Microphone)."
                }
            }
        }
    }

    /// ■ (и через 60 с): вход — сразу, дорожка и мастер — когда колбэк допишет блок (drainStems → recDone).
    func stopRec() {
        guard let t = sampleRec.take, !t.opening, !t.stopping else { return }
        if t.input {
            let out = audio.endInput()
            if let o = out { recDone(SampleData(left: o.left, right: o.right)) } else { sampleRec.take = nil }
        } else {
            sampleRec.take?.stopping = true
            sampleRec.take?.stopAt = Date.timeIntervalSinceReferenceDate
            audio.core.events.push(.captureStop)
        }
    }

    /// 60 раз в секунду (drain): время, предел 60 с, пики формы волны.
    func tickRec() {
        guard let t = sampleRec.take, !t.opening else { return }
        let now: Double = Date.timeIntervalSinceReferenceDate
        // Звук не идёт (колбэк не дописал запись за секунду) — запись не зависает, кнопка снова работает.
        if t.stopping {
            if now - t.stopAt > 1 { sampleRec.take = nil }
            return
        }
        let el: Double = now - t.start
        if !t.input && el > 1 && !stems.recording.contains(StemRing.capture) {
            sampleRec.take = nil
            sampleRec.error = "Recording did not start — no audio."
            return
        }
        let s = Int(el)
        if s != sampleRec.seconds { sampleRec.seconds = min(s, Capture.maxSeconds) }
        if t.input {
            audio.input.withBuffer { l, r in sampleRec.peaks.update(left: l, right: r) }
        } else {
            stems.withBuffer(StemRing.capture) { l, r in sampleRec.peaks.update(left: l, right: r) }
        }
        if el >= Double(Capture.maxSeconds) && t.input { stopRec() }
    }

    /// Запись из колбэка кончилась (■ или 60 с).
    func recFromCore(_ data: SampleData) {
        if sampleRec.take?.input == false { recDone(data) }
    }

    /// Записанное — в хранилище сэмплов (в фоне), на дорожку (UNDO) и копия в RECORDINGS.
    private func recDone(_ data: SampleData) {
        guard let t = sampleRec.take else { return }
        sampleRec.take = nil
        let date = Date()
        let name: String = Library.recordingName(t.name, date: date)
        let folder: String = Library.recordingFolderName(project: session.name, date: date)
        let dir = store.dir
        Task.detached(priority: .userInitiated) {
            let key = SampleStore.store(data, dir: dir)
            await MainActor.run {
                self.store.add(key, data)
                self.samplesVersion += 1
                if t.track < self.project.tracks.count {
                    self.edit { p in
                        p.files[key] = name
                        p.tracks[t.track].addRecordedSample(key)
                    }
                }
                self.addRecording(key, name: name, folder: folder)
            }
        }
    }

    /// Уход в фон во время записи входа — запись кончается (сессия уходит из режима записи).
    func endInputRecForBackground() {
        if sampleRec.take?.input == true { stopRec() }
    }
}
