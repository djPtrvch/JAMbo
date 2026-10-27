import Foundation

// EXPORT SONG (PROJECTS): вся аранжировка с начала до конца и хвосты эффектов — в файл быстрее реального времени
// (Audio/SongExport.swift). Петля и референс (B) на время экспорта выключены, транспорт стоит; готовый файл —
// в «Файлы» системным окном (как EXPORT проекта).

/// Ход экспорта: доля, готовый файл, ошибка.
struct SongExportState: Equatable {
    var progress: Double = 0
    var running: Bool = false
    var file: URL? = nil
    var failed: Bool = false
}

extension AppModel {
    /// Длина песни (шаги таймлайна) и в секундах по BPM.
    var songSteps: Int { return project.arrangeEnd }

    var songSeconds: Double {
        return Double(songSteps) * 60 / (max(1, project.bpm) * 4)
    }

    func exportSong() {
        guard songSteps > 0, !songExport.running else { return }
        if playing { togglePlay() }
        let fmt: SongFormat = songFormat
        let wasLoop: Bool = project.arrange.loop
        let wasB: Bool = arrRefB
        arrRefB = false
        mutatePlay({ p in p.arrange.loop = false }, publish: true)
        let core: AudioCore = audio.core
        let exporter = SongExporter()
        songExporter = exporter
        songExport = SongExportState(progress: 0, running: true, file: nil, failed: false)
        audio.beginExport()
        // Коррекция наушников — только для слуха: в файл не идёт.
        core.phones.paused.store(1)
        exporter.preroll(core)
        core.events.push(.arrange(on: true, from: 0))
        core.events.push(.play(true))
        let expected: Int = Int(songSeconds * AudioCore.sampleRate)
        let url: URL = AppModel.songURL(session.name, fmt.ext)
        DispatchQueue.global(qos: .userInitiated).async {
            let ok: Bool = exporter.run(core, fmt: fmt, url: url, expected: expected) { p in
                DispatchQueue.main.async { self.songExport.progress = p }
            }
            DispatchQueue.main.async {
                self.finishSong(ok ? url : nil, cancelled: exporter.cancelled.load() > 0, loop: wasLoop, refB: wasB)
            }
        }
    }

    func cancelSong() {
        songExporter?.cancelled.store(1)
    }

    private func finishSong(_ url: URL?, cancelled: Bool, loop: Bool, refB: Bool) {
        audio.core.events.push(.play(false))
        audio.core.phones.paused.store(0)
        audio.endExport()
        mutatePlay({ p in p.arrange.loop = loop }, publish: false)
        arrRefB = refB
        publishAudio()
        songExporter = nil
        songExport = SongExportState(progress: url == nil ? 0 : 1, running: false, file: url, failed: url == nil && !cancelled)
    }

    /// Временный файл песни: имя проекта и расширение формата (прежний — убрать).
    static func songURL(_ name: String, _ ext: String) -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("song", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base: String = name.isEmpty ? "Song" : name.replacingOccurrences(of: "/", with: "-")
        return folder.appendingPathComponent(base + "." + ext)
    }
}
