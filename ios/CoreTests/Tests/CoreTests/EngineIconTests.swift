import XCTest
@testable import Core

/// Превью-иконки движков 16–24 против прототипа (ios/tools/icons/golden.mjs: заливки функций draw из
/// docs/icons/prototype/engine-previews-prototype.html на записывающем canvas) и на сетке значений ручек.
final class EngineIconTests: XCTestCase {
    private struct Golden: Decodable {
        let engine: Int
        let v: [String: Double]
        let hx: Double?
        let ops: [Op]
    }

    private struct Op: Decodable {
        let ink: String
        let a: Double
        let r: [[Double]]
        let poly: [[Double]]
        let text: [TextPart]?
    }

    /// Текст в эталоне: [строка, x, y].
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
        .deletingLastPathComponent().appendingPathComponent("tools/icons/engine_previews_golden.json")

    private static let engines = [16, 17, 18, 19, 20, 21, 22, 23, 24]

    /// Точки контура (move и line; close не считается).
    private func points(_ cmds: [IconCmd]) -> [(Double, Double)] {
        var p: [(Double, Double)] = []
        for c in cmds {
            switch c {
            case .move(let x, let y), .line(let x, let y): p.append((x, y))
            default: break
            }
        }
        return p
    }

    private func visible(_ els: [IconElement]) -> [IconElement] {
        return els.filter { !$0.rects.isEmpty || !$0.cmds.isEmpty || $0.text != nil }
    }

    func testPreviewsMatchPrototype() throws {
        let all = try JSONDecoder().decode([Golden].self, from: Data(contentsOf: EngineIconTests.goldenURL))
        XCTAssertEqual(Set(all.map { $0.engine }), Set(EngineIconTests.engines))
        for g in all {
            let v = IconValues(h: g.v["h"]!, t: g.v["t"]!, m: g.v["m"]!, q: g.v["q"]!, d: g.v["d"]!)
            var els = visible(EngineIcons.elements(g.engine, v, hx: g.hx))
            // HAT: отрезки линий склеиваются тем же правилом, что в эталоне (mergeRuns в golden.mjs).
            if g.engine == Jambo.hat, els.count == 2 { els[1].rects = mergeRuns(els[1].rects) }
            let name = "engine \(g.engine) \(g.v) hx \(String(describing: g.hx))"
            XCTAssertEqual(els.count, g.ops.count, name)
            for (k, (a, b)) in zip(els, g.ops).enumerated() {
                let at = "\(name) op \(k)"
                XCTAssertEqual(a.ink == .secondary ? "s" : "p", b.ink, at)
                XCTAssertEqual(a.opacity ?? 1, b.a, accuracy: 0.0002, at)
                if let tx = b.text {
                    guard case .s(let str) = tx[0], case .n(let x) = tx[1], case .n(let y) = tx[2] else { return XCTFail(at) }
                    XCTAssertEqual(a.text, str, at)
                    XCTAssertEqual(a.textX, x, at)
                    XCTAssertEqual(a.textY, y, at)
                    continue
                }
                XCTAssertEqual(a.rects.count, b.r.count, at)
                for (ra, rb) in zip(a.rects, b.r) {
                    let d = [ra.x - rb[0], ra.y - rb[1], ra.w - rb[2], ra.h - rb[3]].map { abs($0) }.max() ?? 0
                    if d > 0.002 { XCTFail("\(at): \(ra) vs \(rb)"); break }
                }
                let pa = points(a.cmds)
                XCTAssertEqual(pa.count, b.poly.count, at)
                for (p, q) in zip(pa, b.poly) where abs(p.0 - q[0]) > 0.002 || abs(p.1 - q[1]) > 0.002 {
                    XCTFail("\(at): \(p) vs \(q)")
                    break
                }
            }
        }
    }

    /// Соседние прямоугольники с тем же x, касающиеся или перекрытые по y, — один (как mergeRuns в golden.mjs).
    private func mergeRuns(_ rects: [IconRect]) -> [IconRect] {
        var out: [IconRect] = []
        for r in rects {
            if var p = out.last, abs(p.x - r.x) < 1e-3, r.y <= p.y + p.h + 1e-3 {
                p.h = max(p.y + p.h, r.y + r.h) - p.y
                out[out.count - 1] = p
            } else {
                out.append(r)
            }
        }
        return out
    }

    /// Всё конечно и внутри поля 64×64.
    private func checkBounds(_ els: [IconElement], _ at: String) {
        func inside(_ x: Double, _ y: Double) -> Bool { return x.isFinite && y.isFinite && x >= 0 && x <= 64 && y >= 0 && y <= 64 }
        for el in els {
            if let a = el.opacity { XCTAssertTrue(a.isFinite && a >= 0 && a <= 1, "\(at) opacity \(a)") }
            for r in el.rects {
                let ok = inside(r.x, r.y) && inside(r.x + r.w, r.y + r.h) && r.w >= 0 && r.h >= 0
                if !ok { return XCTFail("\(at): \(r)") }
            }
            for (x, y) in points(el.cmds) where !inside(x, y) { return XCTFail("\(at): \(x) \(y)") }
            if el.text != nil { XCTAssertTrue(inside(el.textX, el.textY), at) }
        }
    }

    /// Сетка: по 4 значения на ручку 1.1–1.4, Decay 0 / 0.5 / 1 — без NaN и выхода за 64×64; у ударных — и с подсветкой.
    func testGridFiniteInField() {
        let knob: [Double] = [0, 1.0 / 3, 2.0 / 3, 1]
        for e in EngineIconTests.engines {
            for h in knob { for t in knob { for m in knob { for q in knob { for d in [0.0, 0.5, 1] {
                let v = IconValues(h: h, t: t, m: m, q: q, d: d)
                let at = "engine \(e) h\(h) t\(t) m\(m) q\(q) d\(d)"
                let els = EngineIcons.elements(e, v)
                XCTAssertFalse(visible(els).isEmpty, at)
                checkBounds(els, at)
                if d == 0.5 && (h == 0 || h == 1) { checkBounds(EngineIcons.elements(e, v, hx: 30), at + " hx") }
            } } } } }
        }
    }

    /// Иконка живая: каждая ручка (и Decay у ударных и FM) меняет картинку.
    func testEachKnobChangesIcon() {
        func sig(_ els: [IconElement]) -> String { return "\(els.map { $0.rects })\(els.map { $0.cmds })\(els.map { $0.opacity })" }
        let decay: Set<Int> = [16, 18, 20, 21, 22, 23]
        for e in EngineIconTests.engines {
            let base = IconValues(h: 0.5, t: 0.5, m: 0.5, q: 0.5, d: 0.5)
            let s0 = sig(EngineIcons.elements(e, base))
            var knobs: [WritableKeyPath<IconValues, Double>] = [\.h, \.t, \.m, \.q]
            if decay.contains(e) { knobs.append(\.d) }
            for kp in knobs {
                var v = base
                v[keyPath: kp] = 0.9
                XCTAssertNotEqual(sig(EngineIcons.elements(e, v)), s0, "engine \(e) \(kp)")
            }
        }
    }

    /// WTABLE по таблице дорожки: BASIC, POSITION 0 — синус (четверть периода — пик); иконка в поле.
    func testTableFrame() {
        let f = EngineIcons.tableFrame(WtTable.builtin("BASIC"))
        XCTAssertEqual(f(0, 0.25), 1, accuracy: 0.05)
        XCTAssertEqual(f(0, 1.25), 1, accuracy: 0.05)
        for pos in [0.0, 0.5, 1] {
            for warp in [0.0, 0.7] {
                checkBounds(EngineIcons.wtableIcon(IconValues(h: pos, t: warp, m: 1, q: 1), f), "table \(pos) \(warp)")
            }
        }
    }

    /// Для снапшота (ios/tools/icons/snapshot.mjs): ICON_DUMP=путь — элементы на наборах ручек снапшота в JSON.
    func testDumpForSnapshot() throws {
        guard let out = ProcessInfo.processInfo.environment["ICON_DUMP"] else { return }
        let sets = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: out + ".in"))) as! [[String: Any]]
        var res: [[String: Any]] = []
        for c in sets {
            let v = c["v"] as! [Double]
            let iv = IconValues(h: v[0], t: v[1], m: v[2], q: v[3], d: v[4])
            let els = EngineIcons.elements(c["engine"] as! Int, iv, hx: c["hx"] as? Double)
            res.append(["els": els.map { e -> [String: Any] in
                var d: [String: Any] = ["ink": e.ink == .secondary ? "s" : "p", "a": e.opacity ?? 1]
                d["r"] = e.rects.map { [$0.x, $0.y, $0.w, $0.h] }
                d["poly"] = points(e.cmds).map { [$0.0, $0.1] }
                if let t = e.text { d["text"] = [t, e.textX, e.textY, e.textSize] }
                return d
            }])
        }
        try JSONSerialization.data(withJSONObject: res).write(to: URL(fileURLWithPath: out))
    }
}
