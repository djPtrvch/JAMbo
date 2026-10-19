import Foundation

// Распаковка deflate (RFC 1951, «сырой» поток — как в ZIP, метод 8) на Swift (S11c): архивы из «Файлов» iPad
// и других программ сжаты. Без сторонних библиотек и без Compression (Core собирается и на Linux). Устроено как puff
// Марка Адлера: побитовое чтение, канонические коды Хаффмана по таблицам длин.

public enum Inflate {
    struct Huffman {
        var count: [Int] = [Int](repeating: 0, count: 16)
        var symbol: [Int] = []
    }

    struct Reader {
        let src: [UInt8]
        var pos: Int = 0
        var bitBuf: Int = 0
        var bitCnt: Int = 0

        init(_ src: [UInt8]) { self.src = src }

        mutating func bits(_ need: Int) throws -> Int {
            var val = bitBuf
            while bitCnt < need {
                guard pos < src.count else { throw InflateError.truncated }
                val |= Int(src[pos]) << bitCnt
                pos += 1
                bitCnt += 8
            }
            bitBuf = val >> need
            bitCnt -= need
            return val & ((1 << need) - 1)
        }

        mutating func decode(_ h: Huffman) throws -> Int {
            var code = 0, first = 0, index = 0
            for len in 1...15 {
                code |= try bits(1)
                let c = h.count[len]
                if code - c < first { return h.symbol[index + (code - first)] }
                index += c
                first += c
                first <<= 1
                code <<= 1
            }
            throw InflateError.badCode
        }
    }

    enum InflateError: Error { case truncated, badCode, badBlock }

    static let lenBase: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99,
                                 115, 131, 163, 195, 227, 258]
    static let lenExtra: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    static let distBase: [Int] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025,
                                  1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    static let distExtra: [Int] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12,
                                   12, 13, 13]
    static let order: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    /// Коды по длинам; неполный набор допустим (как в puff), переполненный — ошибка.
    static func build(_ lengths: [Int]) throws -> Huffman {
        var h = Huffman()
        for l in lengths { h.count[l] += 1 }
        if h.count[0] == lengths.count { return h }
        var left = 1
        for len in 1...15 {
            left <<= 1
            left -= h.count[len]
            if left < 0 { throw InflateError.badCode }
        }
        var offs = [Int](repeating: 0, count: 16)
        for len in 1..<15 { offs[len + 1] = offs[len] + h.count[len] }
        h.symbol = [Int](repeating: 0, count: lengths.count)
        for (sym, l) in lengths.enumerated() where l != 0 {
            h.symbol[offs[l]] = sym
            offs[l] += 1
        }
        return h
    }

    /// Распаковать; ошибка в потоке — nil.
    public static func inflate(_ data: Data) -> Data? {
        var r = Reader([UInt8](data))
        var out: [UInt8] = []
        out.reserveCapacity(data.count * 3)
        do {
            var last = 0
            repeat {
                last = try r.bits(1)
                let type = try r.bits(2)
                switch type {
                case 0: try stored(&r, &out)
                case 1: try codes(&r, &out, fixedLen, fixedDist)
                case 2:
                    let (l, d) = try dynamicTables(&r)
                    try codes(&r, &out, l, d)
                default: throw InflateError.badBlock
                }
            } while last == 0
        } catch {
            return nil
        }
        return Data(out)
    }

    static func stored(_ r: inout Reader, _ out: inout [UInt8]) throws {
        r.bitBuf = 0
        r.bitCnt = 0
        guard r.pos + 4 <= r.src.count else { throw InflateError.truncated }
        let len = Int(r.src[r.pos]) | (Int(r.src[r.pos + 1]) << 8)
        let nlen = Int(r.src[r.pos + 2]) | (Int(r.src[r.pos + 3]) << 8)
        r.pos += 4
        if len != (~nlen & 0xffff) { throw InflateError.badBlock }
        guard r.pos + len <= r.src.count else { throw InflateError.truncated }
        out.append(contentsOf: r.src[r.pos..<(r.pos + len)])
        r.pos += len
    }

    static let fixedLen: Huffman = {
        var l = [Int](repeating: 8, count: 288)
        for i in 144..<256 { l[i] = 9 }
        for i in 256..<280 { l[i] = 7 }
        return (try? build(l)) ?? Huffman()
    }()

    static let fixedDist: Huffman = (try? build([Int](repeating: 5, count: 30))) ?? Huffman()

    static func dynamicTables(_ r: inout Reader) throws -> (Huffman, Huffman) {
        let nlen = try r.bits(5) + 257
        let ndist = try r.bits(5) + 1
        let ncode = try r.bits(4) + 4
        if nlen > 286 || ndist > 30 { throw InflateError.badBlock }
        var lengths = [Int](repeating: 0, count: 19)
        for i in 0..<ncode { lengths[order[i]] = try r.bits(3) }
        let lencode = try build(lengths)
        var all = [Int](repeating: 0, count: nlen + ndist)
        var i = 0
        while i < nlen + ndist {
            let sym = try r.decode(lencode)
            if sym < 16 {
                all[i] = sym
                i += 1
                continue
            }
            var len = 0
            var rep = 0
            if sym == 16 {
                if i == 0 { throw InflateError.badBlock }
                len = all[i - 1]
                rep = 3 + (try r.bits(2))
            } else if sym == 17 {
                rep = 3 + (try r.bits(3))
            } else {
                rep = 11 + (try r.bits(7))
            }
            if i + rep > nlen + ndist { throw InflateError.badBlock }
            for _ in 0..<rep {
                all[i] = len
                i += 1
            }
        }
        if all[256] == 0 { throw InflateError.badBlock }
        let l = try build(Array(all[0..<nlen]))
        let d = try build(Array(all[nlen...]))
        return (l, d)
    }

    static func codes(_ r: inout Reader, _ out: inout [UInt8], _ lencode: Huffman, _ distcode: Huffman) throws {
        while true {
            var sym = try r.decode(lencode)
            if sym < 256 {
                out.append(UInt8(sym))
            } else if sym == 256 {
                return
            } else {
                sym -= 257
                if sym >= 29 { throw InflateError.badCode }
                let len = lenBase[sym] + (try r.bits(lenExtra[sym]))
                let ds = try r.decode(distcode)
                if ds >= 30 { throw InflateError.badCode }
                let dist = distBase[ds] + (try r.bits(distExtra[ds]))
                if dist > out.count { throw InflateError.badBlock }
                var from = out.count - dist
                for _ in 0..<len {
                    out.append(out[from])
                    from += 1
                }
            }
        }
    }
}
