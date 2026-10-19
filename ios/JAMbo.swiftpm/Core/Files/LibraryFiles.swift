import Foundation

// Файлы библиотеки (S11c, как libio.ts веба): EXPORT — сэмпл WAV (32-бит float, 48 кГц — своя копия сэмпла;
// решение пользователя), пресет — .jambopreset ({ jambo: 'preset', preset }), таблица WTABLE — исходный WAV,
// папка или выбор — .zip; IMPORT — аудио, .jambopreset и .zip (папки восстанавливаются в открытой папке).

public enum WavFile {
    /// WAV 32-бит float (WAVE_FORMAT_IEEE_FLOAT, с блоком fact), моно или стерео.
    public static func float32(left: [Float], right: [Float]?, sampleRate: Int = 48000) -> Data {
        let ch = right == nil ? 1 : 2
        let frames = left.count
        let dataBytes = frames * ch * 4
        var out = Data()
        func s(_ t: String) { out.append(contentsOf: Array(t.utf8)) }
        func u16(_ v: Int) { out.append(contentsOf: [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)]) }
        func u32(_ v: Int) { u16(v & 0xffff); u16((v >> 16) & 0xffff) }
        s("RIFF"); u32(4 + 26 + 12 + 8 + dataBytes); s("WAVE")
        s("fmt "); u32(18); u16(3); u16(ch); u32(sampleRate); u32(sampleRate * ch * 4); u16(ch * 4); u16(32); u16(0)
        s("fact"); u32(4); u32(frames)
        s("data"); u32(dataBytes)
        var body = [Float](repeating: 0, count: frames * ch)
        if let r = right {
            for i in 0..<frames {
                body[2 * i] = left[i]
                body[2 * i + 1] = i < r.count ? r[i] : 0
            }
        } else {
            body = left
        }
        body.withUnsafeBytes { raw in out.append(contentsOf: raw) }
        return out
    }
}

public enum PresetFile {
    public static let ext = "jambopreset"

    public static func encode(_ p: SynthPreset) -> Data {
        guard let pj = try? JSONEncoder().encode(p), let obj = try? JSONSerialization.jsonObject(with: pj),
              let data = try? JSONSerialization.data(withJSONObject: ["jambo": "preset", "preset": obj], options: [])
        else { return Data() }
        return data
    }

    /// Пресет из файла (веба или своего); не пресет — nil. Без имени — имя файла.
    public static func decode(_ data: Data, fallback: String) -> SynthPreset? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let p = obj["preset"] as? [String: Any], p["sound"] is String, p["params"] is [String: Any],
              let pd = try? JSONSerialization.data(withJSONObject: p),
              var preset = try? JSONDecoder().decode(SynthPreset.self, from: pd) else { return nil }
        if preset.name.isEmpty { preset.name = fallback }
        // Своя таблица веба ('wt:s:…') — ключ Swift.
        if let t = preset.table { preset.table = WebProject.table(t) }
        return preset
    }
}

/// Байты содержимого для EXPORT: сэмпл (WAV) и таблица (исходный WAV) по ключу; нет — nil.
public struct LibraryBytes {
    public let sample: (String) -> Data?
    public let table: (String) -> Data?

    public init(sample: @escaping (String) -> Data?, table: @escaping (String) -> Data?) {
        self.sample = sample
        self.table = table
    }
}

extension Library {
    /// Имя файла: без «\ / : * ? " < > |», пустое — untitled.
    public static func safe(_ s: String) -> String {
        let bad: Set<Character> = ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]
        var out = ""
        for ch in s { out.append(bad.contains(ch) ? "_" : ch) }
        let t = out.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "untitled" : t
    }

    /// Имя файла узла (сэмпл и таблица — .wav, пресет — .jambopreset).
    public static func fileName(_ n: LibNode) -> String {
        switch n.kind {
        case .sample: return safe((n.name as NSString).deletingPathExtension) + ".wav"
        case .table: return safe(n.name) + ".wav"
        case .preset: return safe(n.name) + "." + PresetFile.ext
        case .folder: return safe(n.name)
        }
    }

    /// Файл одного узла (не папки); нет данных — nil.
    public func file(_ n: LibNode, _ bytes: LibraryBytes) -> Data? {
        switch n.kind {
        case .sample: return n.key.flatMap(bytes.sample)
        case .table: return n.key.flatMap { WavetableKey.parseUser($0)?.wav }.flatMap(bytes.table)
        case .preset: return n.preset.map(PresetFile.encode)
        case .folder: return nil
        }
    }

    /// Записи архива узла: папка — со всем содержимым (и пустыми подпапками), путь от prefix.
    public func entries(_ n: LibNode, prefix: String, _ bytes: LibraryBytes) -> [ZipEntry] {
        if n.kind != .folder {
            guard let d = file(n, bytes) else { return [] }
            return [ZipEntry(path: prefix + Library.fileName(n), data: d)]
        }
        let dir: String = prefix + Library.fileName(n) + "/"
        var out: [ZipEntry] = [ZipEntry(path: dir, data: Data())]
        for c in children(n.id) { out += entries(c, prefix: dir, bytes) }
        return out
    }

    /// Содержимое папки id (корень — Library.root) без самой папки.
    public func entries(inside id: String, _ bytes: LibraryBytes) -> [ZipEntry] {
        var out: [ZipEntry] = []
        for c in children(id) { out += entries(c, prefix: "", bytes) }
        return out
    }

    /// Папка name внутри parent (есть — она, нет — новая).
    public mutating func folderIn(_ parent: String, _ name: String) -> String {
        if let f = nodes.first(where: { $0.parent == parent && $0.kind == .folder && $0.name == name }) { return f.id }
        return createFolder(parent, name).id
    }

    /// IMPORT архива в папку into: папки создаются, пресеты добавляются; аудио — возвращается (папка, имя файла,
    /// байты) для декодирования. Таблицы из архива — как сэмплы (как в вебе).
    public mutating func importZip(_ entries: [ZipEntry], into: String) -> (presets: Int, audio: [(String, String, Data)]) {
        var presets = 0
        var audio: [(String, String, Data)] = []
        for e in entries {
            let parts: [String] = e.path.split(separator: "/").map(String.init)
            if parts.isEmpty { continue }
            let dirs: [String] = e.isFolder ? parts : Array(parts.dropLast())
            var dir: String = into
            for p in dirs { dir = folderIn(dir, p) }
            if e.isFolder { continue }
            let file: String = parts.last ?? ""
            if file.lowercased().hasSuffix("." + PresetFile.ext) {
                let base: String = String(file.dropLast(PresetFile.ext.count + 1))
                if let p = PresetFile.decode(e.data, fallback: base) {
                    addPreset(dir, p)
                    presets += 1
                }
            } else {
                audio.append((dir, file, e.data))
            }
        }
        return (presets, audio)
    }
}
