import AVFoundation
import CryptoKit
import Foundation

/// Сэмплы приложения: в памяти (SampleData по ключу) и на диске — Application Support/Samples/<ключ>.caf
/// (float32, 48 кГц; проекты ссылаются на ключ — S9). Ключ — по содержимому файла (SHA-256), сэмпл хранится один раз.
/// Декодирование — вне основного потока; регистрация и снимки — в основном.
final class SampleStore {
    private(set) var samples: [String: SampleData] = [:]
    let dir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        dir = base.appendingPathComponent("Samples", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Загруженный файл: ключ, имя, данные, высота (только для индикации).
    struct Loaded {
        let key: String
        let name: String
        let data: SampleData
        let root: Int?
    }

    func data(_ key: String) -> SampleData? {
        return samples[key]
    }

    /// Зарегистрировать (основной поток).
    func add(_ key: String, _ data: SampleData) {
        samples[key] = data
    }

    /// Файл с iPad (из «Файлов»): прочитать, привести к 48 кГц float32, сохранить копию. nil — не аудио.
    static func decode(_ url: URL, dir: URL) -> Loaded? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let bytes = try? Data(contentsOf: url), !bytes.isEmpty else { return nil }
        let key = SampleStore.key(bytes)
        let dest = dir.appendingPathComponent("\(key).caf")
        // Уже лежит на диске — читаем свою копию.
        if let file = try? AVAudioFile(forReading: dest), let data = read(file) {
            return Loaded(key: key, name: url.lastPathComponent, data: data, root: PitchDetect.root(data))
        }
        guard let file = try? AVAudioFile(forReading: url), let data = read(file) else { return nil }
        write(data, to: dest)
        return Loaded(key: key, name: url.lastPathComponent, data: data, root: PitchDetect.root(data))
    }

    /// Сэмпл проекта с диска по ключу (S9b); нет файла — nil (дорожка без звука).
    static func read(key: String, dir: URL) -> SampleData? {
        let url = dir.appendingPathComponent("\(key).caf")
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return read(file)
    }

    /// Сэмпл из файла проекта .jambo (S11a): байты исходного файла (веб) или своей копии .caf (Swift) — в
    /// Samples/<ключ>.caf. Уже лежит — не трогается. Ключ — только буквы и цифры (имя файла), иначе false.
    static func importPacked(_ s: PackSample, dir: URL) -> Bool {
        if s.key.isEmpty || !s.key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) { return false }
        let dest = dir.appendingPathComponent("\(s.key).caf")
        if let file = try? AVAudioFile(forReading: dest), file.length > 0 { return true }
        // AVAudioFile читает только файл: байты — во временный файл с расширением исходного.
        let ext: String = (s.name as NSString).pathExtension.isEmpty ? "wav" : (s.name as NSString).pathExtension
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(s.key).\(ext)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard (try? s.bytes.write(to: tmp, options: .atomic)) != nil,
              let file = try? AVAudioFile(forReading: tmp), let data = read(file) else { return false }
        write(data, to: dest)
        return true
    }

    /// Байты своей копии сэмпла (Samples/<ключ>.caf) для EXPORT; нет файла — nil.
    static func packed(key: String, dir: URL) -> Data? {
        return try? Data(contentsOf: dir.appendingPathComponent("\(key).caf"))
    }

    /// Отредактированная копия (TRIM, NORMALIZE, MONO): ключ по её отсчётам, копия на диске.
    static func store(_ data: SampleData, dir: URL) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(bytes: data.left, count: data.frames * 4))
        if data.channels == 2 { hasher.update(data: Data(bytes: data.right, count: data.frames * 4)) }
        let key = hex(hasher.finalize())
        write(data, to: dir.appendingPathComponent("\(key).caf"))
        return key
    }

    static func key(_ bytes: Data) -> String {
        return hex(SHA256.hash(data: bytes))
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        let s: String = digest.map { String(format: "%02x", $0) }.joined()
        return String(s.prefix(24))
    }

    /// Файл → float32 48 кГц, не больше двух каналов.
    static func read(_ file: AVAudioFile) -> SampleData? {
        let src = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let input = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: frames) else { return nil }
        do { try file.read(into: input) } catch { return nil }
        let buffer: AVAudioPCMBuffer
        if src.sampleRate == AudioCore.sampleRate && src.commonFormat == .pcmFormatFloat32 && !src.isInterleaved {
            buffer = input
        } else {
            guard let converted = convert(input) else { return nil }
            buffer = converted
        }
        guard let ch = buffer.floatChannelData else { return nil }
        let n = Int(buffer.frameLength)
        if n == 0 { return nil }
        let l = Array(UnsafeBufferPointer(start: ch[0], count: n))
        let r: [Float]? = buffer.format.channelCount >= 2 ? Array(UnsafeBufferPointer(start: ch[1], count: n)) : nil
        return SampleData(left: l, right: r)
    }

    private static func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let src = input.format
        let channels: AVAudioChannelCount = min(2, max(1, src.channelCount))
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioCore.sampleRate,
                                      channels: channels, interleaved: false),
              let conv = AVAudioConverter(from: src, to: fmt) else { return nil }
        conv.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        let ratio: Double = AudioCore.sampleRate / src.sampleRate
        let cap = AVAudioFrameCount(Double(input.frameLength) * ratio) + 4096
        guard let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: cap) else { return nil }
        let fed = FeedFlag()
        var error: NSError?
        let status = conv.convert(to: out, error: &error) { _, state in
            if fed.done {
                state.pointee = .endOfStream
                return nil
            }
            fed.done = true
            state.pointee = .haveData
            return input
        }
        if status == .error { return nil }
        return out
    }

    /// Записать float32 48 кГц (CAF).
    static func write(_ data: SampleData, to url: URL) {
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioCore.sampleRate,
                                      channels: AVAudioChannelCount(data.channels), interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(data.frames)),
              let ch = buf.floatChannelData else { return }
        buf.frameLength = AVAudioFrameCount(data.frames)
        ch[0].update(from: data.left, count: data.frames)
        if data.channels == 2 { ch[1].update(from: data.right, count: data.frames) }
        guard let file = try? AVAudioFile(forWriting: url, settings: fmt.settings, commonFormat: .pcmFormatFloat32,
                                          interleaved: false) else { return }
        try? file.write(from: buf)
    }
}

/// Вход конвертера отдан (блок входа — @Sendable: флаг в классе, а не в захваченной переменной).
final class FeedFlag: @unchecked Sendable {
    var done = false
}
