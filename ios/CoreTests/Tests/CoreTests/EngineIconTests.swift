import XCTest
@testable import Core

/// Иконки движков 0–18 против эталона веба (ios/tools/icons/golden.mjs: SVG из src/engineIcons.ts).
/// Пути сравниваются по командам и числам: в вебе координаты округлены до 0,1 (toFixed), поэтому допуск 0,051.
final class EngineIconTests: XCTestCase {
    private struct Golden: Decodable {
        let engine: Int
        let v: [String: Double]
        let els: [El]
    }

    private struct El: Decodable {
        let fill: Bool
        let op: Double?
        let dash: Bool
        let d: String?
        let c: [Double]?
        let tx: [TextPart]?
    }

    /// Текст в эталоне: [строка, x, y, размер].
    private enum TextPart: Decodable {
        case s(String)
        case n(Double)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .s(s) } else { self = .n(try c.decode(Double.self)) }
        }
    }

    private static let goldenURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("tools/icons/engine_icons_golden.json")

    /// Команды пути веба: буквы и числа по порядку.
    private func tokens(_ d: String) -> (String, [Double]) {
        var letters = ""
        var nums: [Double] = []
        var cur = ""
        func flush() {
            if !cur.isEmpty, let n = Double(cur) { nums.append(n) }
            cur = ""
        }
        for ch in d {
            if ch.isLetter && ch != "e" {
                flush()
                letters.append(ch == "z" ? "Z" : ch)
            } else if ch == " " || ch == "," {
                flush()
            } else if ch == "-" && !cur.isEmpty && !cur.hasSuffix("e") {
                flush()
                cur = "-"
            } else {
                cur.append(ch)
            }
        }
        flush()
        return (letters, nums)
    }

    private func tokens(_ cmds: [IconCmd]) -> (String, [Double]) {
        var letters = ""
        var nums: [Double] = []
        for c in cmds {
            switch c {
            case .move(let x, let y): letters += "M"; nums += [x, y]
            case .line(let x, let y): letters += "L"; nums += [x, y]
            case .hTo(let x): letters += "H"; nums.append(x)
            case .vTo(let y): letters += "V"; nums.append(y)
            case .hBy(let x): letters += "h"; nums.append(x)
            case .vBy(let y): letters += "v"; nums.append(y)
            case .arc(let r, let large, let x, let y, _, _, _, _): letters += "A"; nums += [r, r, 0, large ? 1 : 0, 1, x, y]
            case .arcBy(let rx, let ry, let large, let sweep, let dx, let dy):
                letters += "a"; nums += [rx, ry, 0, large ? 1 : 0, sweep ? 1 : 0, dx, dy]
            case .close: letters += "Z"
            }
        }
        return (letters, nums)
    }

    func testIconsMatchWeb() throws {
        // В эталоне веба есть и иконки движков Mutable Instruments (0–15) — их в приложении нет (S12).
        let all = try JSONDecoder().decode([Golden].self, from: Data(contentsOf: EngineIconTests.goldenURL))
        let cases = all.filter { SynthEngines.engine($0.engine) != nil }
        XCTAssertEqual(cases.count, 15)
        for g in cases {
            let v = IconValues(h: g.v["h"] ?? 0.5, t: g.v["t"] ?? 0.5, m: g.v["m"] ?? 0.5, d: g.v["d"] ?? 0.5)
            let els = EngineIcons.elements(g.engine, v)
            let name = "engine \(g.engine) h\(v.h) t\(v.t) m\(v.m)"
            XCTAssertEqual(els.count, g.els.count, name)
            for (k, (a, b)) in zip(els, g.els).enumerated() {
                let at = "\(name) el \(k)"
                XCTAssertEqual(a.fill, b.fill, at)
                XCTAssertEqual(a.dash, b.dash, at)
                XCTAssertEqual(a.opacity == nil, b.op == nil, at)
                if let x = a.opacity, let y = b.op { XCTAssertEqual(x, y, accuracy: 0.006, at) }
                if let d = b.d {
                    let (wl, wn) = tokens(d)
                    let (sl, sn) = tokens(a.cmds)
                    XCTAssertEqual(sl, wl, at)
                    XCTAssertEqual(sn.count, wn.count, at)
                    for (x, y) in zip(sn, wn) where abs(x - y) > 0.051 {
                        XCTFail("\(at): \(x) vs \(y)")
                        break
                    }
                } else if let c = b.c {
                    let s = try XCTUnwrap(a.circle, at)
                    XCTAssertEqual(s.0, c[0], accuracy: 0.051, at)
                    XCTAssertEqual(s.1, c[1], accuracy: 0.051, at)
                    XCTAssertEqual(s.2, c[2], accuracy: 1e-9, at)
                } else if let tx = b.tx {
                    guard case .s(let str) = tx[0], case .n(let x) = tx[1], case .n(let y) = tx[2],
                          case .n(let size) = tx[3] else { return XCTFail(at) }
                    XCTAssertEqual(a.text, str, at)
                    XCTAssertEqual(a.textX, x, at)
                    XCTAssertEqual(a.textY, y, at)
                    XCTAssertEqual(a.textSize, size, at)
                }
            }
        }
    }
}
