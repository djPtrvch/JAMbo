import AVFoundation
import Foundation

/// Формат экспорта песни: WAV (16 / 24 / 32 float) или M4A (AAC 256 / 320 kbps или ALAC без потерь); 44,1 или 48 кГц.
struct SongFormat: Equatable {
    enum Kind: Equatable { case wav, m4a }
    enum Quality: Equatable { case aac256, aac320, lossless }

    var kind: Kind = .wav
    var bits: Int = 24
    var rate: Double = 48000
    var quality: Quality = .aac320

    var ext: String { return kind == .wav ? "wav" : "m4a" }

    /// Настройки файла AVAudioFile.
    var settings: [String: Any] {
        var s: [String: Any] = [AVSampleRateKey: rate, AVNumberOfChannelsKey: 2]
        switch kind {
        case .wav:
            s[AVFormatIDKey] = kAudioFormatLinearPCM
            s[AVLinearPCMBitDepthKey] = bits
            s[AVLinearPCMIsFloatKey] = bits == 32
            s[AVLinearPCMIsBigEndianKey] = false
            s[AVLinearPCMIsNonInterleaved] = false
        case .m4a:
            switch quality {
            case .lossless:
                s[AVFormatIDKey] = kAudioFormatAppleLossless
                s[AVEncoderBitDepthHintKey] = min(bits, 24)
            case .aac256, .aac320:
                s[AVFormatIDKey] = kAudioFormatMPEG4AAC
                s[AVEncoderBitRateKey] = quality == .aac256 ? 256_000 : 320_000
            }
        }
        return s
    }
}

/// Экспорт песни быстрее реального времени: вывод на динамик стоит (AudioHost.exporting), AudioCore.render
/// зовётся подряд на фоновом потоке; аранжировка играет с начала до конца, затем хвосты эффектов — пока звук не
/// стихнет ниже −90 dB (не дольше 10 с). 48 кГц движка → частота файла — AVAudioConverter.
final class SongExporter: @unchecked Sendable {
    /// Отмена из интерфейса.
    let cancelled = AtomicCounter()
    static let block: Int = 256
    static let chunk: Int = 4096
    static let tailMax: Double = 10
    static let quiet: Float = 0.0000316

    /// Перед PLAY: команды и снимки дошли до движка, переход A/B референса доиграл (не пишется).
    func preroll(_ core: AudioCore) {
        let n: Int = SongExporter.block
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        var k: Int = 0
        while k < 40 {
            core.render(frames: n, left: l, right: r)
            k += 1
        }
    }

    /// Песня в файл url; expected — ожидаемая длина без хвоста (кадры 48 кГц, для полосы хода). true — записан.
    func run(_ core: AudioCore, fmt: SongFormat, url: URL, expected: Int, progress: @escaping (Double) -> Void) -> Bool {
        let src: AVAudioFormat? = AVAudioFormat(standardFormatWithSampleRate: AudioCore.sampleRate, channels: 2)
        guard let srcFmt = src,
              let file = try? AVAudioFile(forWriting: url, settings: fmt.settings, commonFormat: .pcmFormatFloat32, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: srcFmt, frameCapacity: AVAudioFrameCount(SongExporter.chunk)),
              let ch = buf.floatChannelData else { return false }
        let dstFmt: AVAudioFormat = file.processingFormat
        let conv: AVAudioConverter? = dstFmt.sampleRate == srcFmt.sampleRate ? nil : AVAudioConverter(from: srcFmt, to: dstFmt)
        let ratio: Double = dstFmt.sampleRate / srcFmt.sampleRate
        let outCap: AVAudioFrameCount = AVAudioFrameCount(Double(SongExporter.chunk) * ratio) + 64
        let out: AVAudioPCMBuffer? = conv == nil ? nil : AVAudioPCMBuffer(pcmFormat: dstFmt, frameCapacity: outCap)
        let limit: Int = expected * 2 + Int(AudioCore.sampleRate * 60)
        let tailFrames: Int = Int(AudioCore.sampleRate * SongExporter.tailMax)
        var done: Int = 0
        var tail: Int = -1
        var quietChunks: Int = 0
        var lastShown: Double = -1
        while true {
            if cancelled.load() > 0 { return false }
            var f: Int = 0
            while f < SongExporter.chunk {
                core.render(frames: SongExporter.block, left: ch[0] + f, right: ch[1] + f)
                f += SongExporter.block
            }
            buf.frameLength = AVAudioFrameCount(SongExporter.chunk)
            if !write(buf, file, conv, out) { return false }
            done += SongExporter.chunk
            if tail < 0 && !core.sequencer.playing { tail = 0 }
            if tail >= 0 {
                tail += SongExporter.chunk
                quietChunks = SongExporter.peak(ch, SongExporter.chunk) < SongExporter.quiet ? quietChunks + 1 : 0
                if quietChunks >= 3 || tail >= tailFrames { break }
            }
            if done > limit { break }
            let p: Double = min(0.99, Double(done) / Double(max(1, expected)))
            if p - lastShown >= 0.01 {
                lastShown = p
                progress(p)
            }
        }
        if let c = conv, let o = out { flush(c, o, file) }
        progress(1)
        return true
    }

    private static func peak(_ ch: UnsafePointer<UnsafeMutablePointer<Float>>, _ n: Int) -> Float {
        var m: Float = 0
        var i: Int = 0
        while i < n {
            let a: Float = abs(ch[0][i])
            let b: Float = abs(ch[1][i])
            if a > m { m = a }
            if b > m { m = b }
            i += 1
        }
        return m
    }

    private func write(_ buf: AVAudioPCMBuffer, _ file: AVAudioFile, _ conv: AVAudioConverter?, _ out: AVAudioPCMBuffer?) -> Bool {
        guard let c = conv, let o = out else {
            return (try? file.write(from: buf)) != nil
        }
        var given: Bool = false
        var err: NSError? = nil
        o.frameLength = 0
        let status = c.convert(to: o, error: &err) { _, st in
            if given {
                st.pointee = .noDataNow
                return nil
            }
            given = true
            st.pointee = .haveData
            return buf
        }
        if status == .error { return false }
        if o.frameLength > 0 { return (try? file.write(from: o)) != nil }
        return true
    }

    private func flush(_ c: AVAudioConverter, _ o: AVAudioPCMBuffer, _ file: AVAudioFile) {
        var k: Int = 0
        while k < 8 {
            var err: NSError? = nil
            o.frameLength = 0
            let status = c.convert(to: o, error: &err) { _, st in
                st.pointee = .endOfStream
                return nil
            }
            if o.frameLength > 0 { _ = try? file.write(from: o) }
            if status != .haveData { return }
            k += 1
        }
    }
}
