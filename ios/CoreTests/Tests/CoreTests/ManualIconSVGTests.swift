import XCTest
@testable import Core

/// Иконки движков для мануала (docs/manual, раздел 5.4): SVG 64×64 так же, как их рисует SynthWindow.draw
/// (волна и контур — квадратичными кривыми через точки). Основной цвет — var(--text), серый — var(--icon2).
/// Запуск: MANUAL_ICONS=путь.json swift test --filter ManualIconSVGTests → {номер движка: SVG без обёртки}.
final class ManualIconSVGTests: XCTestCase {
    private func f(_ x: Double) -> String { return String(format: "%.1f", x) }

    private func smooth(_ pts: [(Double, Double)]) -> String {
        var s = ""
        let n = pts.count
        if n < 2 { return s }
        var i = 1
        while i < n - 1 {
            let p = pts[i], q = pts[i + 1]
            s += "Q\(f(p.0)) \(f(p.1)) \(f((p.0 + q.0) / 2)) \(f((p.1 + q.1) / 2))"
            i += 1
        }
        s += "L\(f(pts[n - 1].0)) \(f(pts[n - 1].1))"
        return s
    }

    private func wave(_ e: IconElement) -> String {
        let n = min(e.wave.count, e.waveBot.count)
        let dx = (e.waveX1 - e.waveX0) / Double(n - 1)
        let top = (0..<n).map { (e.waveX0 + Double($0) * dx, e.wave[$0]) }
        let bot = (0..<n).reversed().map { (e.waveX0 + Double($0) * dx, e.waveBot[$0]) }
        return "M\(f(top[0].0)) \(f(top[0].1))" + smooth(top) + "L\(f(bot[0].0)) \(f(bot[0].1))" + smooth(bot) + "Z"
    }

    private func contour(_ rects: [IconRect]) -> String {
        var s = ""
        var run: [IconRect] = []
        func flush() {
            guard let a = run.first, let b = run.last else { return }
            if run.count == 1 {
                s += "M\(f(a.x)) \(f(a.y))h\(f(a.w))v\(f(a.h))h\(f(-a.w))Z"
                run.removeAll()
                return
            }
            var top = [(a.x, a.y)]
            var bot = [(b.x + b.w, b.y + b.h)]
            for r in run { top.append((r.x + r.w / 2, r.y)) }
            top.append((b.x + b.w, b.y))
            for r in run.reversed() { bot.append((r.x + r.w / 2, r.y + r.h)) }
            bot.append((a.x, a.y + a.h))
            s += "M\(f(top[0].0)) \(f(top[0].1))" + smooth(top) + "L\(f(bot[0].0)) \(f(bot[0].1))" + smooth(bot) + "Z"
            run.removeAll()
        }
        for r in rects {
            if let p = run.last, abs(r.x - (p.x + p.w)) > 0.3 { flush() }
            run.append(r)
        }
        flush()
        return s
    }

    private func rects(_ rs: [IconRect]) -> String {
        return rs.map { r in
            "<rect x=\"\(f(r.x))\" y=\"\(f(r.y))\" width=\"\(f(r.w))\" height=\"\(f(r.h))\" rx=\"\(f(min(r.w, r.h) / 2))\"/>"
        }.joined()
    }

    private func cmds(_ cs: [IconCmd]) -> String {
        var s = ""
        for c in cs {
            switch c {
            case .move(let x, let y): s += "M\(f(x)) \(f(y))"
            case .line(let x, let y): s += "L\(f(x)) \(f(y))"
            case .hTo(let x): s += "H\(f(x))"
            case .vTo(let y): s += "V\(f(y))"
            case .hBy(let x): s += "h\(f(x))"
            case .vBy(let y): s += "v\(f(y))"
            case .close: s += "Z"
            case .arc(let r, let large, let x, let y, _, _, _, _): s += "A\(f(r)) \(f(r)) 0 \(large ? 1 : 0) 1 \(f(x)) \(f(y))"
            case .arcBy(let rx, let ry, let large, let sweep, let dx, let dy):
                s += "a\(f(rx)) \(f(ry)) 0 \(large ? 1 : 0) \(sweep ? 1 : 0) \(f(dx)) \(f(dy))"
            }
        }
        return s
    }

    /// Ручки для примера (как в прототипе docs/icons/prototype; ANALOG — A Sine, B Saw).
    static let sets: [(Int, IconValues)] = [
        (16, IconValues(h: 0.5, t: 0.5, m: 0.3, q: 0.5, d: 0.5)),
        (20, IconValues(h: 0.5, t: 0.5, m: 0.5, q: 0.4, d: 0.5)),
        (21, IconValues(h: 0.5, t: 0.5, m: 0.5, q: 0.2, d: 0.4)),
        (22, IconValues(h: 0.5, t: 0.6, m: 0.5, q: 0.5, d: 0.5)),
        (23, IconValues(h: 0.5, t: 0.3, m: 0.3, q: 0.5, d: 0.5)),
        (17, IconValues(h: 0, t: 2.0 / 3, m: 0.3, q: 0.5, d: 0.5)),
        (24, IconValues(h: 0.5, t: 0.4, m: 0.25, q: 0.2, d: 0.5)),
        (18, IconValues(h: 0.5, t: 0.4, m: 0.5, q: 0.5, d: 0.5)),
        (19, IconValues(h: 0.3, t: 0, m: 0.5, q: 0.35, d: 0.5)),
        (25, IconValues(h: 0.4, t: 0.3, m: 0.3, q: 0, d: 0.5)),
        (26, IconValues(h: 0.08, t: 0.62, m: 0.6, q: 0.25, d: 0.5)),
    ]

    func svg(_ els: [IconElement]) -> String {
        var s = ""
        for el in els {
            let fill = el.ink == .secondary ? "var(--icon2)" : "var(--text)"
            let op = el.opacity.map { " fill-opacity=\"\(f($0))\"" } ?? ""
            if let t = el.text {
                s += "<text x=\"\(f(el.textX))\" y=\"\(f(el.textY))\" text-anchor=\"middle\" font-size=\"\(f(el.textSize))\" font-weight=\"600\" font-family=\"ui-monospace,monospace\" fill=\"\(fill)\"\(op)>\(t)</text>"
            } else if !el.wave.isEmpty {
                s += "<path d=\"\(wave(el))\" fill=\"\(fill)\"\(op)/>"
            } else if !el.rects.isEmpty {
                s += el.contour ? "<path d=\"\(contour(el.rects))\" fill=\"\(fill)\"\(op)/>" : "<g fill=\"\(fill)\"\(op)>\(rects(el.rects))</g>"
            } else if let c = el.circle {
                s += "<circle cx=\"\(f(c.0))\" cy=\"\(f(c.1))\" r=\"\(f(c.2))\" "
                s += el.fill ? "fill=\"\(fill)\"\(op)/>" : "fill=\"none\" stroke=\"\(fill)\" stroke-width=\"\(f(EngineIcons.stroke))\"/>"
            } else if el.fill {
                s += "<path d=\"\(cmds(el.cmds))\" fill=\"\(fill)\"\(op)/>"
            } else {
                let dash = el.dash ? " stroke-dasharray=\"2 2.4\"" : ""
                let sop = el.opacity.map { " stroke-opacity=\"\(f($0))\"" } ?? ""
                s += "<path d=\"\(cmds(el.cmds))\" fill=\"none\" stroke=\"\(fill)\" stroke-width=\"\(f(EngineIcons.stroke))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"\(dash)\(sop)/>"
            }
        }
        return s
    }

    func testDump() throws {
        guard let out = ProcessInfo.processInfo.environment["MANUAL_ICONS"] else { return }
        var res: [String: String] = [:]
        for (e, v) in ManualIconSVGTests.sets { res[String(e)] = svg(EngineIcons.elements(e, v)) }
        try JSONSerialization.data(withJSONObject: res, options: [.sortedKeys]).write(to: URL(fileURLWithPath: out))
    }
}
