import Foundation

// Случайное арпеджио (SHIFT + тап по CHORD в режиме ARP; docs/ai/sequencer.md, «Арпеджиатор»): фигура из звуков
// аккорда (не только вверх-вниз: через звук, альберти, педаль, октавные скачки…), ритм по стилю проекта с паузами,
// акценты, разные длины нот, вариации по тактам и разбег в конце.

extension Arp {
    /// Фигуры: номер звука аккорда + 10 × октава (звук за пределами аккорда — следующей октавой).
    static let figures: [[Int]] = [
        [0, 1, 2, 3],             // 0 вверх
        [0, 2, 1, 3],             // 1 через звук
        [0, 2, 1, 2],             // 2 альберти
        [0, 1, 0, 2, 0, 3],       // 3 педаль на корне
        [0, 1, 2, 3, 2, 1],       // 4 волна
        [0, 10, 1, 11, 2, 12],    // 5 октавные скачки
        [0, 2, 1, 3, 2, 4],       // 6 терции вверх
        [3, 1, 2, 0],             // 7 ломаная вниз
        [0, 1, 2, 10, 2, 1],      // 8 с верхом октавой выше
        [0, 0, 2, 1, 0, 3],       // 9 повтор корня
    ]

    /// Фигуры, близкие к направлению окна ARP (Up, Down, Up-Down, Down-Up, Random, Order); Down — фигуры вверх
    /// в обратном порядке.
    static let families: [[Int]] = [[0, 1, 5, 6, 8], [0, 1, 5, 6, 8], [4, 8, 2], [4, 8, 2],
                                    Array(0..<10), [0, 3, 9, 2]]

    /// Ритм по стилю (DrumRhythm.Groove): вероятность ноты в доле шага арпеджио (16 долей на такт при 1/16).
    static let rhythms: [String] = [
        "x3xx93x6x3xx93x6", "x999x999x999x999", "x.85x46.x3867.x5", "x293x394x293x596",  // house, techno, breaks, dnb
        "x5786859x5786859", "x.57.64.x.65.734", "x2x2x2x2x2x2x2x6", "x.3.5.3.7.3.5.32",  // trap, rnb, pop, ambient
    ]

    /// Доля нот, которые тянутся до следующей (legato), по стилю.
    static let legatos: [Double] = [0.15, 0.05, 0.2, 0.25, 0.2, 0.35, 0.2, 0.6]

    /// Фигура для направления dir: 70 % — из близких, 30 % — любая; Down и Down-Up — задом наперёд.
    static func figure<G: RandomNumberGenerator>(dir: Int, using g: inout G) -> [Int] {
        let fam: [Int] = families[clampDir(dir)]
        let near: Bool = Double.random(in: 0..<1, using: &g) < 0.7
        let k: Int = near ? (fam.randomElement(using: &g) ?? 0) : Int.random(in: 0..<figures.count, using: &g)
        let f: [Int] = figures[k]
        return dir == down || dir == downUp ? f.reversed() : f
    }

    /// Нота фигуры: звук t (по модулю — с октавой выше) аккорда chord, октава o; выше OCTAVES — вниз в пределы.
    static func figureNote(_ code: Int, chord: [Int], shift: Int, octaves: Int) -> Int {
        let n: Int = Swift.max(1, chord.count)
        let t: Int = code % 10
        var o: Int = code / 10 + t / n + shift
        o = Swift.min(o, clampOctaves(octaves) - 1)
        let m: Int = chord[t % n] + 12 * Swift.max(0, o)
        return Swift.min(127, m)
    }

    /// Случайное арпеджио на total шагов по аккордам chords (поровну): фигура (по направлению dir), ритм стиля style
    /// (по bpm — вариант) с шагом RATE; такт — один рисунок долей, следующие такты — одна доля переставлена, при
    /// OCTAVES 2–3 — часть тактов октавой выше; фигура с новым аккордом — сначала или продолжается (наугад на
    /// весь рисунок); последний такт — разбег вверх в последних 4 долях. Velocity: доли 100 %, остальные 65–85 %,
    /// изредка тихие; длина — по GATE, часть нот legato (до следующей).
    public static func randomSteps<G: RandomNumberGenerator>(_ chords: [[Int]], steps total: Int, dir: Int,
                                                             octaves: Int, rate: Int, gate: Double, style: Int,
                                                             bpm: Double, using g: inout G) -> [ArpStepNote] {
        if chords.isEmpty || total <= 0 { return [] }
        let gr: Int = DrumRhythm.groove(style, bpm: bpm).rawValue
        let every: Int = gridSteps[clampRate(rate)]
        let slots: Int = Swift.max(1, total / every)
        let perBar: Int = Swift.max(1, Params.stepsPerPage / every)
        let probs: [Double] = DrumRhythm.pat(rhythms[gr])
        var mask: [Bool] = (0..<perBar).map { i in
            i == 0 || Double.random(in: 0..<1, using: &g) < probs[(i * every) % 16]
        }
        let fig: [Int] = figure(dir: dir, using: &g)
        let restart: Bool = Bool.random(using: &g)
        let bars: Int = (slots + perBar - 1) / perBar
        let baseLen: Int = Swift.max(1, Int((clampGate(gate) * Double(every)).rounded()))
        let legato: Double = legatos[gr]
        var hits: [(slot: Int, note: Int, vel: Double)] = []
        var k: Int = 0
        var lastChord: Int = -1
        for bar in 0..<bars {
            if bar > 0 && perBar > 1 {
                let i: Int = Int.random(in: 1..<perBar, using: &g)
                mask[i].toggle()
            }
            let shift: Int = octaves > 1 && bar % 2 == 1 && Bool.random(using: &g) ? 1 : 0
            for i in 0..<perBar {
                let slot: Int = bar * perBar + i
                if slot >= slots { break }
                let step: Int = slot * every
                let ci: Int = Swift.min(chords.count - 1, step * chords.count / total)
                if ci != lastChord {
                    lastChord = ci
                    if restart { k = 0 }
                }
                let fill: Bool = bar == bars - 1 && bars > 1 && i >= perBar - 4
                if !mask[i] && !fill { continue }
                let chord: [Int] = chords[ci]
                if chord.isEmpty { continue }
                let code: Int = fill ? (i - (perBar - 4)) + 1 : fig[k % fig.count]
                k += 1
                let note: Int = figureNote(code, chord: chord, shift: shift, octaves: octaves)
                var v: Double = step % 4 == 0 ? DrumRhythm.velFull : Double.random(in: 82...108, using: &g).rounded()
                if step % 4 != 0 && Double.random(in: 0..<1, using: &g) < 0.12 { v = Double.random(in: 55...70, using: &g).rounded() }
                hits.append((slot, note, v))
            }
        }
        var out: [ArpStepNote] = []
        for (j, h) in hits.enumerated() {
            let step: Int = h.slot * every
            let next: Int = j + 1 < hits.count ? hits[j + 1].slot * every : total
            let gap: Int = Swift.max(1, next - step)
            let long: Bool = Double.random(in: 0..<1, using: &g) < legato
            let len: Int = long ? gap : Swift.min(gap, baseLen)
            out.append(ArpStepNote(step: step, note: h.note, len: len, vel: h.vel))
        }
        return out
    }
}
