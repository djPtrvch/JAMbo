import SwiftUI

/// PROJECTS → EXPORT SONG (страница бутерброда, того же размера): формат, разрядность или качество, частота, хвост;
/// длина песни; EXPORT — полоса хода и CANCEL; готовый файл — окно сохранения в «Файлы».
struct SongExportPage: View {
    let model: AppModel
    let back: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let st: SongExportState = model.songExport
        return VStack(alignment: .leading, spacing: 8) {
            MenuBackHeader(title: "EXPORT SONG", back: back)
            MenuScroll {
                VStack(alignment: .leading, spacing: 8) {
                    options.disabled(st.running).opacity(st.running ? 0.4 : 1)
                    SettingsNote(text: lengthText)
                    if st.running { running(st) } else { start }
                    if st.failed { Text("Can’t export the song.").font(.system(size: 12)).foregroundStyle(theme.rec) }
                }
                .padding(.trailing, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fileMover(isPresented: fileShown, file: model.songExport.file) { _ in model.songExport.file = nil }
    }

    @ViewBuilder
    private var options: some View {
        let f: SongFormat = model.songFormat
        MenuChoiceRow(label: "FORMAT", items: formatItems(f))
        if f.kind == .m4a { MenuChoiceRow(label: "QUALITY", items: qualityItems(f)) }
        if f.kind == .wav || f.quality == .lossless { MenuChoiceRow(label: "BIT DEPTH", items: bitItems(f)) }
        MenuChoiceRow(label: "SAMPLE RATE", items: rateItems(f))
        MenuChoiceRow(label: "TAIL", items: tailItems(f))
    }

    private func formatItems(_ f: SongFormat) -> [MenuChoice] {
        let m: AppModel = model
        return [MenuChoice(title: "WAV", current: f.kind == .wav) { m.songFormat.kind = .wav },
                MenuChoice(title: "M4A", current: f.kind == .m4a) { m.songFormat.kind = .m4a }]
    }

    private func qualityItems(_ f: SongFormat) -> [MenuChoice] {
        let m: AppModel = model
        return [MenuChoice(title: "AAC 256", current: f.quality == .aac256) { m.songFormat.quality = .aac256 },
                MenuChoice(title: "AAC 320", current: f.quality == .aac320) { m.songFormat.quality = .aac320 },
                MenuChoice(title: "LOSSLESS", current: f.quality == .lossless) { m.songFormat.quality = .lossless }]
    }

    /// ALAC — до 24 бит (32 FLOAT — только у WAV).
    private func bitItems(_ f: SongFormat) -> [MenuChoice] {
        let m: AppModel = model
        var r: [MenuChoice] = [MenuChoice(title: "16", current: f.bits == 16) { m.songFormat.bits = 16 },
                               MenuChoice(title: "24", current: f.bits == 24) { m.songFormat.bits = 24 }]
        if f.kind == .wav { r.append(MenuChoice(title: "32 FLOAT", current: f.bits == 32) { m.songFormat.bits = 32 }) }
        return r
    }

    private func rateItems(_ f: SongFormat) -> [MenuChoice] {
        let m: AppModel = model
        return [MenuChoice(title: "44.1 KHZ", current: f.rate == 44100) { m.songFormat.rate = 44100 },
                MenuChoice(title: "48 KHZ", current: f.rate == 48000) { m.songFormat.rate = 48000 }]
    }

    private func tailItems(_ f: SongFormat) -> [MenuChoice] {
        let m: AppModel = model
        let cur: Double = f.tail ?? -1
        return SongExportPage.tails.map { (t: Double) -> MenuChoice in
            MenuChoice(title: SongExportPage.tailName(t), current: cur == t) { m.songFormat.tail = t < 0 ? nil : t }
        }
    }

    /// Хвост: −1 — AUTO, 0 — OFF, иначе секунды.
    static let tails: [Double] = [-1, 0, 2, 5, 10]

    static func tailName(_ t: Double) -> String {
        if t < 0 { return "AUTO" }
        if t == 0 { return "OFF" }
        return "\(Int(t)) S"
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
        let tail: String = model.songFormat.tail == nil ? "plus effect tails until silence (up to 10 s)"
            : (model.songFormat.tail == 0 ? "cut at the end of the last block" : "plus \(Int(model.songFormat.tail ?? 0)) s of tail")
        return "The whole arrangement from the start, \(t), \(tail). Loop, REF and MIDI out are off while exporting."
    }

    private var fileShown: Binding<Bool> {
        Binding(get: { model.songExport.file != nil }, set: { if !$0 { model.songExport.file = nil } })
    }
}
