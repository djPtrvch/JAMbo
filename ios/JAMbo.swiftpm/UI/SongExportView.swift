import SwiftUI

/// Окно EXPORT SONG: формат, разрядность или качество, частота; длина песни; EXPORT — полоса хода и CANCEL;
/// готовый файл — окно сохранения в «Файлы».
struct SongExportView: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let st: SongExportState = model.songExport
        return VStack(alignment: .leading, spacing: 8) {
            options.disabled(st.running).opacity(st.running ? 0.4 : 1)
            SettingsNote(text: lengthText)
            if st.running { running(st) } else { start }
            if st.failed { Text("Can’t export the song.").font(.system(size: 12)).foregroundStyle(theme.rec) }
        }
        .frame(maxWidth: 440, alignment: .leading)
        .fileMover(isPresented: fileShown, file: model.songExport.file) { _ in model.songExport.file = nil }
    }

    @ViewBuilder
    private var options: some View {
        let f: SongFormat = model.songFormat
        FieldLabel(title: "FORMAT")
        HStack(spacing: 4) {
            MenuItem(title: "WAV", current: f.kind == .wav) { model.songFormat.kind = .wav }
            MenuItem(title: "M4A", current: f.kind == .m4a) { model.songFormat.kind = .m4a }
        }
        if f.kind == .m4a {
            FieldLabel(title: "QUALITY")
            HStack(spacing: 4) {
                MenuItem(title: "AAC 256", current: f.quality == .aac256) { model.songFormat.quality = .aac256 }
                MenuItem(title: "AAC 320", current: f.quality == .aac320) { model.songFormat.quality = .aac320 }
                MenuItem(title: "LOSSLESS", current: f.quality == .lossless) { model.songFormat.quality = .lossless }
            }
        }
        if f.kind == .wav || f.quality == .lossless { bitDepth(f) }
        FieldLabel(title: "SAMPLE RATE")
        HStack(spacing: 4) {
            MenuItem(title: "44.1 KHZ", current: f.rate == 44100) { model.songFormat.rate = 44100 }
            MenuItem(title: "48 KHZ", current: f.rate == 48000) { model.songFormat.rate = 48000 }
        }
    }

    @ViewBuilder
    private func bitDepth(_ f: SongFormat) -> some View {
        FieldLabel(title: "BIT DEPTH")
        HStack(spacing: 4) {
            MenuItem(title: "16", current: f.bits == 16) { model.songFormat.bits = 16 }
            MenuItem(title: "24", current: f.bits == 24) { model.songFormat.bits = 24 }
            // ALAC — до 24 бит.
            if f.kind == .wav { MenuItem(title: "32 FLOAT", current: f.bits == 32) { model.songFormat.bits = 32 } }
        }
    }

    private var start: some View {
        MenuItem(title: "EXPORT", enabled: model.songSteps > 0) { model.exportSong() }
    }

    private func running(_ st: SongExportState) -> some View {
        HStack(spacing: 8) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(theme.meterTrack)
                    RoundedRectangle(cornerRadius: 3).fill(theme.accent).frame(width: g.size.width * CGFloat(st.progress))
                }
            }
            .frame(height: 9)
            MenuItem(title: "CANCEL") { model.cancelSong() }.frame(width: 110)
        }
    }

    /// Длина песни (мин:сек) и хвост; пустая аранжировка — подсказка.
    private var lengthText: String {
        if model.songSteps <= 0 { return "The arrangement is empty: put clips on the timeline first." }
        let s: Int = Int(model.songSeconds.rounded())
        let t: String = String(format: "%d:%02d", s / 60, s % 60)
        return "The whole arrangement from the start, \(t), plus effect tails until silence (up to 10 s). Loop and REF are off while exporting."
    }

    private var fileShown: Binding<Bool> {
        Binding(get: { model.songExport.file != nil }, set: { if !$0 { model.songExport.file = nil } })
    }
}
