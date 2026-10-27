import Foundation

// ZIP (S11c, как zip.ts веба): EXPORT папки библиотеки — один .zip с подпапками, сэмплами, пресетами и таблицами;
// IMPORT .zip — папки восстанавливаются. Запись — без сжатия (аудио почти не сжимается), имена в UTF-8; чтение —
// без сжатия и deflate (Inflate), так открываются и архивы из «Файлов». Служебные файлы macOS пропускаются.

public struct ZipEntry: Equatable, Sendable {
    /// Путь в архиве; «/» на конце — папка (без данных).
    public var path: String
    public var data: Data

    public init(path: String, data: Data) {
        self.path = path
        self.data = data
    }

    public var isFolder: Bool { return path.hasSuffix("/") }
}

public enum Zip {
    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xffffffff
        let t = crcTable
        d.withUnsafeBytes { raw in
            for b in raw.bindMemory(to: UInt8.self) { c = t[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
        }
        return c ^ 0xffffffff
    }

    static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
    static func le32(_ v: Int) -> [UInt8] { le16(v & 0xffff) + le16((v >> 16) & 0xffff) }

    /// Дата и время DOS.
    static func dosTime(_ d: Date) -> (Int, Int) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        let time: Int = ((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) >> 1)
        let date: Int = ((Swift.max(1980, c.year ?? 1980) - 1980) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1)
        return (time, date)
    }

    /// Архив без сжатия.
    public static func write(_ entries: [ZipEntry], date: Date = Date()) -> Data {
        let (time, day) = dosTime(date)
        var out = Data()
        var central = Data()
        for e in entries {
            let name = Data(e.path.utf8)
            let crc = Int(crc32(e.data))
            let offset = out.count
            out.append(contentsOf: le32(0x04034b50) + le16(20) + le16(0x0800) + le16(0) + le16(time) + le16(day))
            out.append(contentsOf: le32(crc) + le32(e.data.count) + le32(e.data.count) + le16(name.count) + le16(0))
            out.append(name)
            out.append(e.data)
            central.append(contentsOf: le32(0x02014b50) + le16(20) + le16(20) + le16(0x0800) + le16(0) + le16(time))
            central.append(contentsOf: le16(day) + le32(crc) + le32(e.data.count) + le32(e.data.count) + le16(name.count))
            central.append(contentsOf: le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset))
            central.append(name)
        }
        let at = out.count
        out.append(central)
        out.append(contentsOf: le32(0x06054b50) + le16(0) + le16(0) + le16(entries.count) + le16(entries.count))
        out.append(contentsOf: le32(central.count) + le32(at) + le16(0))
        return out
    }

    /// Предел распакованного файла: сэмпл 10 мин стерео float 32 — ~230 МБ.
    public static let fileLimit = 512 << 20
    /// Предел всего распакованного архива.
    public static let totalLimit = 2 << 30

    /// Итог чтения: записи (nil — не ZIP или распакованное больше totalLimit), пропущено файлов больше fileLimit,
    /// архив больше totalLimit.
    public struct Reading {
        public var entries: [ZipEntry]?
        public var skippedLarge: Int = 0
        public var tooLarge: Bool = false
    }

    /// Файлы и папки архива; не ZIP или распакованное больше totalLimit — nil. Сжатые не deflate, битые записи
    /// и файлы больше fileLimit пропускаются.
    public static func read(_ data: Data, fileLimit: Int = fileLimit, totalLimit: Int = totalLimit) -> [ZipEntry]? {
        return check(data, fileLimit: fileLimit, totalLimit: totalLimit).entries
    }

    /// Как read, с тем, что пропущено по пределам (для предупреждения при импорте).
    public static func check(_ data: Data, fileLimit: Int = fileLimit, totalLimit: Int = totalLimit) -> Reading {
        var res = Reading()
        let b: [UInt8] = [UInt8](data)
        let n = b.count
        func u16(_ o: Int) -> Int { o + 2 <= n ? Int(b[o]) | (Int(b[o + 1]) << 8) : 0 }
        func u32(_ o: Int) -> Int { u16(o) | (u16(o + 2) << 16) }
        var e = n - 22
        while e >= 0 && u32(e) != 0x06054b50 { e -= 1 }
        if e < 0 { return res }
        let count = u16(e + 10)
        var p = u32(e + 16)
        var out: [ZipEntry] = []
        var total = 0
        for _ in 0..<count {
            if p + 46 > n || u32(p) != 0x02014b50 { break }
            let method = u16(p + 10)
            let csize = u32(p + 20)
            let nlen = u16(p + 28)
            let xlen = u16(p + 30)
            let clen = u16(p + 32)
            let loc = u32(p + 42)
            guard p + 46 + nlen <= n else { break }
            let path = String(decoding: b[(p + 46)..<(p + 46 + nlen)], as: UTF8.self)
            p += 46 + nlen + xlen + clen
            if path.hasPrefix("__MACOSX/") { continue }
            if path.hasSuffix("/") {
                out.append(ZipEntry(path: path, data: Data()))
                continue
            }
            if (path.split(separator: "/").last ?? "").hasPrefix(".") { continue }
            guard loc + 30 <= n else { continue }
            let start = loc + 30 + u16(loc + 26) + u16(loc + 28)
            guard start + csize <= n else { continue }
            let raw = Data(b[start..<(start + csize)])
            var file: Data? = nil
            if method == 0 {
                file = csize <= fileLimit ? raw : nil
                if file == nil { res.skippedLarge += 1 }
            } else if method == 8 {
                var big = false
                let room: Int = totalLimit - total
                file = Inflate.inflate(raw, limit: Swift.min(fileLimit, room), tooLarge: &big)
                if big {
                    if room < fileLimit {
                        res.tooLarge = true
                        return res
                    }
                    res.skippedLarge += 1
                }
            }
            guard let d = file else { continue }
            total += d.count
            if total > totalLimit {
                res.tooLarge = true
                return res
            }
            out.append(ZipEntry(path: path, data: d))
        }
        res.entries = out
        return res
    }
}
