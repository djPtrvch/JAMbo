import Foundation

// Файл проекта для «Файлов» (.jambo, S11a; как packProject / unpackProject веба, storage.ts):
// 'JMB1', длина заголовка (uint32, старший байт первым), заголовок JSON { format, version, name, doc,
// samples: [{ key, name, size }] }, затем байты сэмплов подряд. В вебе format 'jambo' (doc — проект веба,
// сэмплы — исходные файлы), в Swift-версии — 'jambo-swift' (doc — Project, сэмплы — свои .caf).

/// Сэмпл в файле проекта: ключ, имя файла, байты.
public struct PackSample: Equatable, Sendable {
    public var key: String
    public var name: String
    public var bytes: Data

    public init(key: String, name: String, bytes: Data) {
        self.key = key
        self.name = name
        self.bytes = bytes
    }
}

/// Содержимое файла .jambo: doc — JSON проекта как есть (читает ProjectFormat или конвертер веба).
public struct ProjectPack: Equatable, Sendable {
    public var format: String
    public var version: Int
    public var name: String
    public var doc: Data
    public var samples: [PackSample]

    public static let magic: String = "JMB1"
    /// Формат файла веба.
    public static let webFormat: String = "jambo"

    public init(format: String, version: Int, name: String, doc: Data, samples: [PackSample]) {
        self.format = format
        self.version = version
        self.name = name
        self.doc = doc
        self.samples = samples
    }

    /// Проект Swift-версии в файл .jambo.
    public static func swift(name: String, doc: Project, samples: [PackSample]) -> ProjectPack? {
        guard let json = try? ProjectFormat.encoder().encode(doc) else { return nil }
        return ProjectPack(format: ProjectFormat.name, version: ProjectFormat.version, name: name, doc: json,
                           samples: samples)
    }

    /// Байты файла; nil — doc не JSON.
    public func encoded() -> Data? {
        guard let docObj = try? JSONSerialization.jsonObject(with: doc, options: [.fragmentsAllowed]) else { return nil }
        var list: [[String: Any]] = []
        for s in samples {
            let item: [String: Any] = ["key": s.key, "name": s.name, "size": s.bytes.count]
            list.append(item)
        }
        let head: [String: Any] = ["format": format, "version": version, "name": name, "doc": docObj, "samples": list]
        guard let header = try? JSONSerialization.data(withJSONObject: head, options: []),
              header.count <= Int(UInt32.max) else { return nil }
        var out = Data(ProjectPack.magic.utf8)
        let len: UInt32 = UInt32(header.count)
        out.append(UInt8((len >> 24) & 0xff))
        out.append(UInt8((len >> 16) & 0xff))
        out.append(UInt8((len >> 8) & 0xff))
        out.append(UInt8(len & 0xff))
        out.append(header)
        for s in samples { out.append(s.bytes) }
        return out
    }

    /// Чтение файла; nil — не файл проекта или файл обрезан. Сэмплы — срезы без копирования всего файла.
    public static func decode(_ data: Data) -> ProjectPack? {
        let base: Int = data.startIndex
        let total: Int = data.count
        if total < 8 || String(decoding: data.subdata(in: base..<(base + 4)), as: UTF8.self) != magic { return nil }
        let b0: Int = Int(data[base + 4]) << 24
        let b1: Int = Int(data[base + 5]) << 16
        let b2: Int = Int(data[base + 6]) << 8
        let len: Int = b0 | b1 | b2 | Int(data[base + 7])
        if len > total - 8 { return nil }
        let header: Data = data.subdata(in: (base + 8)..<(base + 8 + len))
        guard let obj = try? JSONSerialization.jsonObject(with: header, options: []),
              let head = obj as? [String: Any],
              let docObj = head["doc"],
              let doc = try? JSONSerialization.data(withJSONObject: docObj, options: [.fragmentsAllowed]) else { return nil }
        let format: String = head["format"] as? String ?? webFormat
        let version: Int = number(head["version"]) ?? 1
        let name: String = head["name"] as? String ?? ""
        let list: [Any] = head["samples"] as? [Any] ?? []
        var samples: [PackSample] = []
        var pos: Int = 8 + len
        for item in list {
            guard let s = item as? [String: Any], let key = s["key"] as? String,
                  let size = number(s["size"]), size >= 0, size <= total - pos else { return nil }
            let sname: String = s["name"] as? String ?? "sample.wav"
            let bytes: Data = data.subdata(in: (base + pos)..<(base + pos + size))
            samples.append(PackSample(key: key, name: sname, bytes: bytes))
            pos += size
        }
        return ProjectPack(format: format, version: version, name: name, doc: doc, samples: samples)
    }

    /// Целое из JSON (Int или Double без дробной части).
    static func number(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double, d.rounded() == d, abs(d) < 9e15 { return Int(d) }
        return nil
    }

    /// Файл веба (проект нужно конвертировать).
    public var isWeb: Bool { return format == ProjectPack.webFormat }

    /// Проект Swift-версии из файла (миграция и repair — как у файлов приложения); веб или чужой формат — nil.
    public func swiftProject() -> Project? {
        if format != ProjectFormat.name { return nil }
        let info = ProjectInfo(id: "", name: name, updated: 0)
        guard let infoJson = try? ProjectFormat.encoder().encode(info),
              let infoObj = try? JSONSerialization.jsonObject(with: infoJson, options: []),
              let docObj = try? JSONSerialization.jsonObject(with: doc, options: [.fragmentsAllowed]) else { return nil }
        let file: [String: Any] = ["format": format, "version": version, "info": infoObj, "doc": docObj]
        guard let data = try? JSONSerialization.data(withJSONObject: file, options: []) else { return nil }
        return ProjectFormat.decode(data)?.doc
    }

    /// Проект из файла любого формата: веб — конвертер (WebProject), Swift — как есть; иначе nil.
    public func project() -> Project? {
        return isWeb ? WebProject.convert(doc) : swiftProject()
    }

    /// Сэмплы, нужные проекту p, с ключами Swift-версии (у веба — без 's:'); лишние (свои таблицы WTABLE) — нет.
    public func samples(for p: Project) -> [PackSample] {
        let need: Set<String> = p.sampleKeys
        var out: [PackSample] = []
        for s in samples {
            var x = s
            x.key = WebProject.key(s.key)
            if need.contains(x.key) && !out.contains(where: { $0.key == x.key }) { out.append(x) }
        }
        return out
    }

    /// WAV своих таблиц WTABLE проекта p (ключи без 's:'): в Tables, не в Samples.
    public func tables(for p: Project) -> [PackSample] {
        let need: Set<String> = p.tableKeys
        var out: [PackSample] = []
        for s in samples {
            var x = s
            x.key = WebProject.key(s.key)
            if need.contains(x.key) && !out.contains(where: { $0.key == x.key }) { out.append(x) }
        }
        return out
    }
}
