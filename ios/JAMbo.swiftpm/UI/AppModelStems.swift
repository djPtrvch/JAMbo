import Foundation

// Запись стемов и мастера (S11d, как stems.ts веба): ● у ручки громкости в MIX и ● MASTER под окном при MIX.
// Правила начала и конца — в колбэке (SequencerStems.swift); здесь — кнопки, сбор звука и сохранение:
// стем — сэмпл (Samples/<ключ>.caf) в RECORDINGS библиотеки, в папке «проект дд.мм.гггг», с именем «дорожка чч-мм-сс».

extension AppModel {
    /// Канал горит: готов к записи или пишется.
    func stemLit(_ ch: Int) -> Bool {
        return stemArmed.contains(ch) || stemRecording.contains(ch)
    }

    /// Тап по ●: готовность (повторный — снять); во время записи — дописать до конца прохода, готовность снимается.
    func stemTap(_ ch: Int) {
        ensureAudio()
        let core = audio.core
        if stemRecording.contains(ch) {
            stemArmed.remove(ch)
            core.events.push(.stemFinish(channel: ch))
            return
        }
        if stemArmed.contains(ch) {
            stemArmed.remove(ch)
            core.events.push(.stemArm(channel: ch, on: false))
        } else {
            // Кольцо записи — при первом нажатии (не при запуске).
            core.sequencer.stemRing.prepare()
            stemArmed.insert(ch)
            core.events.push(.stemArm(channel: ch, on: true))
        }
    }

    /// Точка записи на дорожке и на MST: (видна, мигает часто — до конца записи меньше 5 с).
    func stemDot(_ ch: Int) -> (shown: Bool, ending: Bool) {
        guard stemRecording.contains(ch) else { return (false, false) }
        guard let end = stems.endAt[ch] else { return (true, false) }
        let now: Int64 = Int64(audio.core.framesRendered)
        let left: Int64 = end - now
        return (true, left <= Int64(5 * AudioCore.sampleRate))
    }

    /// Сообщения записи из колбэка (60 раз в секунду): начало, звук, конец — готовый стем сохраняется.
    func drainStems() {
        tickRec()
        let done = stems.poll(audio.core.sequencer.stemRing)
        // REC редактора (канал capture) — не стем.
        let now: Set<Int> = stems.recording.subtracting([StemRing.capture])
        if now != stemRecording {
            // Имя дорожки — на момент начала записи.
            for c in now.subtracting(stemRecording) { stemNames[c] = stemBase(c) }
            stemRecording = now
        }
        for s in done {
            if s.channel == StemRing.capture {
                recFromCore(s.data)
                continue
            }
            let base: String = stemNames[s.channel] ?? stemBase(s.channel)
            stemNames[s.channel] = nil
            if s.dropped > 0 { trace("stem \(base): dropped \(s.dropped) frames") }
            saveStem(s.data, base: base)
        }
        // ■ в REC, но записано ничего (стоп в первом же блоке) — запись просто кончается.
        if let t = sampleRec.take, t.stopping, !stems.recording.contains(StemRing.capture) { sampleRec.take = nil }
    }

    private func stemBase(_ ch: Int) -> String {
        if ch == StemRing.master { return "MASTER" }
        return ch < project.tracks.count ? project.tracks[ch].name : "\(ch + 1)"
    }

    /// Стем — в хранилище сэмплов (в фоне), затем в RECORDINGS библиотеки.
    private func saveStem(_ data: SampleData, base: String) {
        let date = Date()
        let name: String = Library.recordingName(base, date: date)
        let folder: String = Library.recordingFolderName(project: session.name, date: date)
        let dir = store.dir
        Task.detached(priority: .utility) {
            let key = SampleStore.store(data, dir: dir)
            await MainActor.run {
                self.store.add(key, data)
                self.samplesVersion += 1
                self.addRecording(key, name: name, folder: folder)
            }
        }
    }

    /// Запись (стем или REC) — в RECORDINGS библиотеки, папка «проект дд.мм.гггг».
    func addRecording(_ key: String, name: String, folder: String) {
        if !libraryLoaded {
            library = libraryStore.load()
            libraryLoaded = true
        }
        libEdit { lib in
            let id: String = lib.recordingsFolder(folder)
            _ = lib.addSample(id, key: key, name: name)
        }
    }
}
