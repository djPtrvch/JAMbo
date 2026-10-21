import Foundation

// MIDI OUT дорожки (меню звука → MIDI): ноты дорожки с выходом не играют голоса, а уходят в очередь midiOut —
// её разбирает MidiOutPump (вне колбэка) и шлёт на устройство с метками времени, когда слышен звук. Всё — в колбэке,
// без выделений памяти.

/// Нота для MIDI OUT: Note On (длина в кадрах; −1 — живая, до отпускания liveId), отпускание живой или «всё
/// отпустить» (стоп транспорта).
public struct MidiNoteOut: Sendable {
    public static let on: UInt8 = 1
    public static let release: UInt8 = 2
    public static let allOff: UInt8 = 3

    public var kind: UInt8 = 0
    public var track: Int32 = 0
    public var note: Int16 = 0
    public var velocity: UInt8 = 0
    public var frame: Int64 = 0
    public var length: Int64 = 0
    public var liveId: Int = 0

    public init() {}
}

extension Sampler {
    /// Ноты дорожки t уходят на MIDI OUT (свой звук молчит).
    @inline(__always)
    public func sendsMidi(_ t: Int) -> Bool {
        guard let d = sound, t >= 0, t < d.trackCount else { return false }
        return d.midiOut[t] != 0
    }

    /// Ноты дорожки t в кадре frame — на MIDI OUT. velocity — Level ноты (p-lock, LFO/ENV, ручка дорожки), 0 — не
    /// шлётся; заглушённая дорожка (mute, не solo) молчит и в MIDI.
    public func midiNotes(track t: Int, at frame: Int64, notes: UnsafePointer<Int16>, count: Int, mask: VoiceMask,
                          vals: UnsafePointer<Float>?, length: Int64, liveId live: Int) {
        guard let d = sound, t >= 0, t < d.trackCount, d.open[t] != 0 else { return }
        modFrame = frame
        let level: Double = pv(d, t, VoiceParam.level, mask, vals)
        let v: Double = Swift.max(0, Swift.min(127, level.rounded()))
        if v < 1 { return }
        var e = MidiNoteOut()
        e.kind = MidiNoteOut.on
        e.track = Int32(t)
        e.velocity = UInt8(v)
        e.frame = frame
        e.length = length
        e.liveId = live
        var k = 0
        while k < count {
            e.note = notes[k]
            _ = midiOut.push(e)
            k += 1
        }
    }

    /// Отпустили живую ноту liveId (шлётся всегда: выход могли снять, пока нота держалась).
    public func midiRelease(liveId live: Int, at frame: Int64) {
        var e = MidiNoteOut()
        e.kind = MidiNoteOut.release
        e.frame = frame
        e.liveId = live
        _ = midiOut.push(e)
    }

    /// Транспорт остановился: ноты секвенсора отпускаются сразу.
    public func midiAllOff(at frame: Int64) {
        var e = MidiNoteOut()
        e.kind = MidiNoteOut.allOff
        e.frame = frame
        _ = midiOut.push(e)
    }
}
