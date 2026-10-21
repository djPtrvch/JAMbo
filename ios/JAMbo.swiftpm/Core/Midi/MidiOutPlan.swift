import Foundation

// MIDI OUT дорожек (меню звука → MIDI): из нот колбэка (MidiNoteOut) — сообщения Note On и Note Off с моментами
// (секунды хоста, когда слышен звук). Note Off нот секвенсора держатся здесь и уходят незадолго до своего момента
// (не ставятся в CoreMIDI заранее: стоп отпускает их сразу). Живые ноты держатся до отпускания (liveId).
// Разбирает MidiOutPump (Audio/) в своём потоке.

/// Куда дорожка шлёт ноты: выход (uniqueID) и канал 0–15.
public struct MidiOutRoute: Equatable, Sendable {
    public var dest: Int32
    public var channel: Int

    public init(dest: Int32, channel: Int) {
        self.dest = dest
        self.channel = channel
    }
}

public struct MidiOutPlan {
    /// Сообщение на выход dest в момент time.
    public struct Send: Equatable, Sendable {
        public var time: Double
        public var dest: Int32
        public var word: UInt32
    }

    private struct Held {
        var time: Double
        var route: MidiOutRoute
        var note: Int
    }

    private var offs: [Held] = []
    private var held: [Int: [Held]] = [:]

    public init() {}

    /// Note Off секвенсора, ещё не отправленные.
    public var pending: Int { return offs.count }

    /// Событие колбэка; time — когда слышен его кадр; route — выход дорожки (nil — у дорожки выхода нет).
    public mutating func add(_ e: MidiNoteOut, time: Double, route: MidiOutRoute?, sampleRate: Double) -> [Send] {
        var out: [Send] = []
        switch e.kind {
        case MidiNoteOut.on:
            guard let r = route else { return out }
            let n: Int = Int(e.note)
            if n < 0 || n > 127 { return out }
            // Та же нота ещё держится (Note Off позже) — отпускается перед новой.
            var k = 0
            while k < offs.count {
                let o = offs[k]
                if o.route == r && o.note == n && o.time > time {
                    out.append(MidiOutPlan.off(o, at: time))
                    offs.remove(at: k)
                } else {
                    k += 1
                }
            }
            out.append(Send(time: time, dest: r.dest, word: MidiMessage.ump(status: 0x90 | r.channel, n, Int(e.velocity))))
            let h = Held(time: time, route: r, note: n)
            if e.length >= 0 {
                var o = h
                o.time = time + Swift.max(0.001, Double(e.length) / sampleRate)
                offs.append(o)
            } else {
                held[e.liveId, default: []].append(h)
            }
        case MidiNoteOut.release:
            guard let hs = held.removeValue(forKey: e.liveId) else { return out }
            for h in hs { out.append(MidiOutPlan.off(h, at: Swift.max(time, h.time))) }
        case MidiNoteOut.allOff:
            for o in offs { out.append(MidiOutPlan.off(o, at: time)) }
            offs.removeAll()
        default:
            break
        }
        return out
    }

    /// Note Off, момент которых не дальше now + ahead.
    public mutating func due(now: Double, ahead: Double) -> [Send] {
        var out: [Send] = []
        var k = 0
        while k < offs.count {
            if offs[k].time <= now + ahead {
                out.append(MidiOutPlan.off(offs[k], at: offs[k].time))
                offs.remove(at: k)
            } else {
                k += 1
            }
        }
        return out
    }

    private static func off(_ h: Held, at time: Double) -> Send {
        return Send(time: time, dest: h.route.dest, word: MidiMessage.ump(status: 0x80 | h.route.channel, h.note, 0))
    }
}
