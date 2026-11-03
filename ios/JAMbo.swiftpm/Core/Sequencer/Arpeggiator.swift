// Арпеджиатор в колбэке (docs/ai/sequencer.md, «Арпеджиатор»): живые ноты дорожки с включённым ARP не звучат сами —
// играют по одной, по сетке транспорта (при игре) или от нажатия по темпу (стоит). Без выделения памяти в колбэке:
// все буферы — заранее. Ноты блока — в список событий (emit*), их отдаёт сэмплеру AudioCore.

/// Нота арпеджио для записи (REC, Capture, аранжировка): кадр начала, длина в кадрах и ход транспорта блока.
public struct ArpOut: Sendable {
    public var track: Int32 = 0
    public var note: Int32 = 0
    public var velocity: Float = 1
    public var frame: Double = 0
    public var gateFrames: Double = 0
    public var playing: Bool = false
    public var nextTick: Int = 0
    public var nextFrame: Double = 0
    public var stepFrames: Double = 6000

    public init() {}
}

public final class Arpeggiator: @unchecked Sendable {
    public static let maxHeld = 16
    public static let maxRow = 64
    public static let maxEmit = 128
    /// liveId нот арпеджио дорожки t (касания интерфейса таких не дают).
    public static func noteId(_ t: Int) -> Int { return -1_000_000_000 - t }

    let tracks: Int = SeqData.maxTracks
    // Настройки дорожек.
    let on: UnsafeMutablePointer<Bool>
    let dir: UnsafeMutablePointer<Int32>
    let rate: UnsafeMutablePointer<Double>
    let octaves: UnsafeMutablePointer<Int32>
    let gate: UnsafeMutablePointer<Double>
    let latch: UnsafeMutablePointer<Bool>
    // Зажатые ноты дорожки t: [t * maxHeld + i], по порядку нажатия; pressed — палец ещё держит (LATCH).
    let heldNote: UnsafeMutablePointer<Int32>
    let heldVel: UnsafeMutablePointer<Float>
    let heldId: UnsafeMutablePointer<Int>
    let heldPressed: UnsafeMutablePointer<Bool>
    let heldCount: UnsafeMutablePointer<Int32>
    // Ход: играет ли, кадр следующей ноты, номер в ряду, звучащая нота и кадр её конца (−1 — нет).
    let running: UnsafeMutablePointer<Bool>
    let nextAt: UnsafeMutablePointer<Double>
    let index: UnsafeMutablePointer<Int32>
    let sounding: UnsafeMutablePointer<Bool>
    let offAt: UnsafeMutablePointer<Int64>
    let lastNote: UnsafeMutablePointer<Int32>
    // Ряд нот (скретч на одну дорожку).
    private let row: UnsafeMutablePointer<Int32>
    private let rowVel: UnsafeMutablePointer<Float>
    private var rng: UInt64 = 0x9E3779B97F4A7C15

    // События блока: kind 1 — noteOn, 0 — release; дорожка, нота, сила, кадр.
    public private(set) var emitCount: Int = 0
    public let emitKind: UnsafeMutablePointer<Int32>
    public let emitTrack: UnsafeMutablePointer<Int32>
    public let emitNote: UnsafeMutablePointer<Int32>
    public let emitVel: UnsafeMutablePointer<Float>
    public let emitFrame: UnsafeMutablePointer<Int64>

    /// Ноты арпеджио → интерфейс (запись).
    public let out = SPSCQueue<ArpOut>(capacity: 512, filler: ArpOut())

    public init() {
        let n: Int = SeqData.maxTracks
        let h: Int = n * Arpeggiator.maxHeld
        on = .allocate(capacity: n); on.initialize(repeating: false, count: n)
        dir = .allocate(capacity: n); dir.initialize(repeating: 0, count: n)
        rate = .allocate(capacity: n); rate.initialize(repeating: 1, count: n)
        octaves = .allocate(capacity: n); octaves.initialize(repeating: 1, count: n)
        gate = .allocate(capacity: n); gate.initialize(repeating: 0.5, count: n)
        latch = .allocate(capacity: n); latch.initialize(repeating: false, count: n)
        heldNote = .allocate(capacity: h); heldNote.initialize(repeating: 0, count: h)
        heldVel = .allocate(capacity: h); heldVel.initialize(repeating: 1, count: h)
        heldId = .allocate(capacity: h); heldId.initialize(repeating: 0, count: h)
        heldPressed = .allocate(capacity: h); heldPressed.initialize(repeating: false, count: h)
        heldCount = .allocate(capacity: n); heldCount.initialize(repeating: 0, count: n)
        running = .allocate(capacity: n); running.initialize(repeating: false, count: n)
        nextAt = .allocate(capacity: n); nextAt.initialize(repeating: 0, count: n)
        index = .allocate(capacity: n); index.initialize(repeating: 0, count: n)
        sounding = .allocate(capacity: n); sounding.initialize(repeating: false, count: n)
        offAt = .allocate(capacity: n); offAt.initialize(repeating: -1, count: n)
        lastNote = .allocate(capacity: n); lastNote.initialize(repeating: -1, count: n)
        row = .allocate(capacity: Arpeggiator.maxRow); row.initialize(repeating: 0, count: Arpeggiator.maxRow)
        rowVel = .allocate(capacity: Arpeggiator.maxRow); rowVel.initialize(repeating: 1, count: Arpeggiator.maxRow)
        let e: Int = Arpeggiator.maxEmit
        emitKind = .allocate(capacity: e); emitKind.initialize(repeating: 0, count: e)
        emitTrack = .allocate(capacity: e); emitTrack.initialize(repeating: 0, count: e)
        emitNote = .allocate(capacity: e); emitNote.initialize(repeating: 0, count: e)
        emitVel = .allocate(capacity: e); emitVel.initialize(repeating: 1, count: e)
        emitFrame = .allocate(capacity: e); emitFrame.initialize(repeating: 0, count: e)
    }

    /// Дорожка t играет живые ноты арпеджио.
    @inline(__always)
    public func active(_ t: Int) -> Bool { return t >= 0 && t < tracks && on[t] }

    /// Настройки дорожки (событие CoreEvent.arp). Выключили — звучащая нота гаснет, набор очищается; сняли LATCH —
    /// отпущенные ноты уходят.
    public func configure(track t: Int, on o: Bool, dir d: Int, rate r: Int, octaves oc: Int, gate g: Double,
                          latch l: Bool, at frame: Int64) {
        guard t >= 0 && t < tracks else { return }
        dir[t] = Int32(Arp.clampDir(d))
        rate[t] = Arp.rateSteps[Arp.clampRate(r)]
        octaves[t] = Int32(Arp.clampOctaves(oc))
        gate[t] = Arp.clampGate(g)
        let wasOn: Bool = on[t]
        on[t] = o
        latch[t] = l
        if wasOn && !o {
            heldCount[t] = 0
            stop(t, at: frame)
            return
        }
        if !l { dropReleased(t, at: frame) }
    }

    /// Живая нота дорожки с ARP: в набор (с LATCH, если все пальцы отпущены, — новый набор). Первая нота набора
    /// звучит сразу (кадр frame).
    public func press(track t: Int, note n: Int, id: Int, velocity v: Float, at frame: Int64) {
        guard active(t) else { return }
        let base: Int = t * Arpeggiator.maxHeld
        var c: Int = Int(heldCount[t])
        if latch[t] {
            var anyPressed: Bool = false
            var i: Int = 0
            while i < c {
                if heldPressed[base + i] { anyPressed = true }
                i += 1
            }
            if !anyPressed {
                c = 0
                heldCount[t] = 0
            }
        }
        if c >= Arpeggiator.maxHeld { return }
        heldNote[base + c] = Int32(n)
        heldVel[base + c] = v
        heldId[base + c] = id
        heldPressed[base + c] = true
        heldCount[t] = Int32(c + 1)
        if !running[t] {
            running[t] = true
            index[t] = 0
            nextAt[t] = Double(frame)
        }
    }

    /// Палец id отпущен: без LATCH ноты уходят из набора (пусто — арпеджио стоит), с LATCH — остаются.
    public func release(track t: Int, id: Int, at frame: Int64) {
        guard t >= 0 && t < tracks else { return }
        let base: Int = t * Arpeggiator.maxHeld
        let c: Int = Int(heldCount[t])
        var i: Int = 0
        while i < c {
            if heldId[base + i] == id { heldPressed[base + i] = false }
            i += 1
        }
        if !latch[t] { dropReleased(t, at: frame) }
    }

    private func dropReleased(_ t: Int, at frame: Int64) {
        let base: Int = t * Arpeggiator.maxHeld
        let c: Int = Int(heldCount[t])
        var k: Int = 0
        var i: Int = 0
        while i < c {
            if heldPressed[base + i] {
                heldNote[base + k] = heldNote[base + i]
                heldVel[base + k] = heldVel[base + i]
                heldId[base + k] = heldId[base + i]
                heldPressed[base + k] = true
                k += 1
            }
            i += 1
        }
        heldCount[t] = Int32(k)
        if k == 0 { stop(t, at: frame) }
    }

    /// Остановить дорожку: звучащая нота гаснет в кадре frame.
    private func stop(_ t: Int, at frame: Int64) {
        if sounding[t] { emit(0, t, lastNote[t], 1, frame) }
        sounding[t] = false
        offAt[t] = -1
        running[t] = false
        lastNote[t] = -1
    }

    @inline(__always)
    private func emit(_ kind: Int32, _ t: Int, _ n: Int32, _ v: Float, _ f: Int64) {
        if emitCount >= Arpeggiator.maxEmit { return }
        emitKind[emitCount] = kind
        emitTrack[emitCount] = Int32(t)
        emitNote[emitCount] = n
        emitVel[emitCount] = v
        emitFrame[emitCount] = f
        emitCount += 1
    }

    /// Ряд нот дорожки (Arp.sequence без коллекций): в row; длина.
    private func buildRow(_ t: Int) -> Int {
        let base: Int = t * Arpeggiator.maxHeld
        let c: Int = Int(heldCount[t])
        let d: Int = Int(dir[t])
        // Уникальные ноты: по порядку нажатия, иначе по высоте.
        var u: Int = 0
        var i: Int = 0
        while i < c {
            let n: Int32 = heldNote[base + i]
            var dup: Bool = false
            var j: Int = 0
            while j < u {
                if row[j] == n { dup = true }
                j += 1
            }
            if !dup {
                row[u] = n
                rowVel[u] = heldVel[base + i]
                u += 1
            }
            i += 1
        }
        if d != Arp.order {
            // Вставками по возрастанию (до 16 нот).
            var a: Int = 1
            while a < u {
                let n: Int32 = row[a]
                let v: Float = rowVel[a]
                var b: Int = a - 1
                while b >= 0 && row[b] > n {
                    row[b + 1] = row[b]
                    rowVel[b + 1] = rowVel[b]
                    b -= 1
                }
                row[b + 1] = n
                rowVel[b + 1] = v
                a += 1
            }
        }
        // Октавы.
        var len: Int = u
        let oc: Int = Int(octaves[t])
        var o: Int = 1
        while o < oc {
            var k: Int = 0
            while k < u && len < Arpeggiator.maxRow / 2 {
                let m: Int32 = row[k] + Int32(12 * o)
                if m <= 127 {
                    row[len] = m
                    rowVel[len] = rowVel[k]
                    len += 1
                }
                k += 1
            }
            o += 1
        }
        return len
    }

    /// Нота номер k ряда длиной len в направлении d (Up-Down, Down-Up — без повтора крайних).
    @inline(__always)
    private func pick(_ d: Int, _ k: Int, _ len: Int) -> Int {
        if len < 2 { return 0 }
        switch d {
        case Arp.down:
            return len - 1 - (k % len)
        case Arp.upDown:
            let p: Int = 2 * len - 2
            let r: Int = k % p
            return r < len ? r : p - r
        case Arp.downUp:
            let p: Int = 2 * len - 2
            let r: Int = k % p
            return r < len ? len - 1 - r : r - len + 1
        case Arp.random:
            rng ^= rng << 13
            rng ^= rng >> 7
            rng ^= rng << 17
            return Int(rng % UInt64(len))
        default:
            return k % len
        }
    }

    /// Блок [start, start + frames): ноты дорожек с ARP. playing — транспорт играет: следующие ноты встают на сетку
    /// шага арпеджио (nextTick — следующий шаг транспорта в кадре nextFrame); stepFrames — шестнадцатая в кадрах.
    public func process(start: Int64, frames: Int, playing: Bool, nextTick: Int, nextFrame: Double,
                        stepFrames: Double) {
        let end: Double = Double(start + Int64(frames))
        var t: Int = 0
        while t < tracks {
            if !on[t] || !running[t] {
                t += 1
                continue
            }
            var guardN: Int = 0
            while guardN < 64 {
                guardN += 1
                let off: Int64 = offAt[t]
                let at: Double = nextAt[t]
                if sounding[t] && off >= 0 && Double(off) <= at && Double(off) < end {
                    emit(0, t, lastNote[t], 1, off)
                    sounding[t] = false
                    offAt[t] = -1
                    continue
                }
                if at >= end { break }
                let len: Int = buildRow(t)
                if len == 0 {
                    stop(t, at: Int64(at))
                    break
                }
                if sounding[t] {
                    emit(0, t, lastNote[t], 1, Int64(at))
                    sounding[t] = false
                }
                let k: Int = pick(Int(dir[t]), Int(index[t]), len)
                let note: Int32 = row[k]
                let vel: Float = rowVel[k]
                let f: Int64 = Int64(at)
                emit(1, t, note, vel, f)
                let period: Double = rate[t] * stepFrames
                let gf: Double = Swift.max(1, gate[t] * period)
                sounding[t] = true
                lastNote[t] = note
                offAt[t] = f + Int64(gf)
                index[t] = Int32((Int(index[t]) + 1) % 1_000_000)
                var o = ArpOut()
                o.track = Int32(t)
                o.note = note
                o.velocity = vel
                o.frame = at
                o.gateFrames = gf
                o.playing = playing
                o.nextTick = nextTick
                o.nextFrame = nextFrame
                o.stepFrames = stepFrames
                _ = out.push(o)
                // Следующая нота: при игре — следующая точка сетки арпеджио, иначе — через период.
                if playing && stepFrames > 0 {
                    let pos: Double = Double(nextTick) - (nextFrame - at) / stepFrames
                    let r: Double = rate[t]
                    let g: Double = ((pos / r) + 0.000001).rounded(.down) + 1
                    nextAt[t] = nextFrame - (Double(nextTick) - g * r) * stepFrames
                } else {
                    nextAt[t] = at + period
                }
            }
            t += 1
        }
    }

    /// Список событий прочитан (AudioCore — после передачи сэмплеру).
    @inline(__always)
    public func clearEmit() { emitCount = 0 }
}
