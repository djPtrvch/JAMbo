import CoreMIDI
import Foundation
import Observation

/// Устройство MIDI в меню: uniqueID CoreMIDI и имя.
struct MidiEndpoint: Identifiable, Equatable {
    let id: Int32
    let name: String
}

/// CoreMIDI (S13a): клиент, вход со всех источников (USB, сеть, Bluetooth — всё, что видит система), список
/// устройств. Сообщения приходят в потоке CoreMIDI и уходят на главный поток (ноты, CC); клок — в S13e.
@Observable
final class MidiHost {
    /// Входы и выходы — для меню DEVICES (обновляются при подключении и отключении).
    private(set) var inputs: [MidiEndpoint] = []
    private(set) var outputs: [MidiEndpoint] = []
    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var inPort = MIDIPortRef()
    @ObservationIgnored private var connected: [MIDIEndpointRef] = []
    @ObservationIgnored private(set) var started: Bool = false
    /// Сообщение и uniqueID источника — на главном потоке.
    @ObservationIgnored var onMessage: ((MidiMessage, Int32) -> Void)? = nil

    func start() {
        if started { return }
        let made: OSStatus = MIDIClientCreateWithBlock("JAMbo" as CFString, &client) { [weak self] note in
            guard note.pointee.messageID == .msgSetupChanged else { return }
            DispatchQueue.main.async { self?.reconnect() }
        }
        guard made == noErr else { return }
        let port: OSStatus = MIDIInputPortCreateWithProtocol(client, "JAMbo In" as CFString, ._1_0, &inPort) { [weak self] list, ref in
            self?.receive(list, ref)
        }
        guard port == noErr else { return }
        started = true
        reconnect()
    }

    /// Подключить все источники заново и перечитать списки устройств.
    private func reconnect() {
        for src in connected { MIDIPortDisconnectSource(inPort, src) }
        connected = []
        var ins: [MidiEndpoint] = []
        let n: Int = MIDIGetNumberOfSources()
        var i: Int = 0
        while i < n {
            let src: MIDIEndpointRef = MIDIGetSource(i)
            let id: Int32 = MidiHost.uniqueID(src)
            // uniqueID источника — в refCon подключения: по нему фильтр входа (MIDI → DEVICES).
            let ref: UnsafeMutableRawPointer? = UnsafeMutableRawPointer(bitPattern: Int(id))
            if MIDIPortConnectSource(inPort, src, ref) == noErr { connected.append(src) }
            ins.append(MidiEndpoint(id: id, name: MidiHost.name(src)))
            i += 1
        }
        var outs: [MidiEndpoint] = []
        let m: Int = MIDIGetNumberOfDestinations()
        var j: Int = 0
        while j < m {
            let dst: MIDIEndpointRef = MIDIGetDestination(j)
            outs.append(MidiEndpoint(id: MidiHost.uniqueID(dst), name: MidiHost.name(dst)))
            j += 1
        }
        inputs = ins
        outputs = outs
    }

    /// Поток CoreMIDI: разбор пакетов, сообщения — на главный поток одним блоком.
    private func receive(_ list: UnsafePointer<MIDIEventList>, _ ref: UnsafeMutableRawPointer?) {
        let source: Int32 = Int32(truncatingIfNeeded: Int(bitPattern: ref))
        var msgs: [MidiMessage] = []
        for packet in list.unsafeSequence() {
            let count: Int = Int(packet.pointee.wordCount)
            var words = packet.pointee.words
            withUnsafeBytes(of: &words) { raw in
                let all = raw.bindMemory(to: UInt32.self)
                let used = UnsafeBufferPointer<UInt32>(rebasing: all[0..<min(count, all.count)])
                msgs.append(contentsOf: MidiMessage.parse(words: used))
            }
        }
        if msgs.isEmpty { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let handler = self.onMessage else { return }
            for msg in msgs { handler(msg, source) }
        }
    }

    private static func uniqueID(_ obj: MIDIObjectRef) -> Int32 {
        var v: Int32 = 0
        MIDIObjectGetIntegerProperty(obj, kMIDIPropertyUniqueID, &v)
        return v
    }

    private static func name(_ obj: MIDIObjectRef) -> String {
        var s: Unmanaged<CFString>? = nil
        MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &s)
        guard let cf = s?.takeRetainedValue() else { return "MIDI" }
        return cf as String
    }
}
