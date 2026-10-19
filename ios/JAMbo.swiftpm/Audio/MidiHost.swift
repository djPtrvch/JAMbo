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
/// Обратная связь (S13d) — send с главного потока, по таймеру UI (вне колбэка).
@Observable
final class MidiHost {
    /// Входы и выходы — для меню DEVICES (обновляются при подключении и отключении).
    private(set) var inputs: [MidiEndpoint] = []
    private(set) var outputs: [MidiEndpoint] = []
    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var inPort = MIDIPortRef()
    @ObservationIgnored private var outPort = MIDIPortRef()
    @ObservationIgnored private var connected: [MIDIEndpointRef] = []
    /// Выходы по uniqueID (обратная связь); растёт при каждом переподключении — значения шлются заново.
    @ObservationIgnored private var destinations: [Int32: MIDIEndpointRef] = [:]
    @ObservationIgnored private(set) var generation: Int = 0
    /// Буфер отправки (один, на главном потоке): один пакет на 64 слова.
    @ObservationIgnored private let sendList = UnsafeMutablePointer<MIDIEventList>.allocate(capacity: 1)
    @ObservationIgnored private(set) var started: Bool = false
    /// Сообщение, uniqueID источника и время прихода (секунды хоста, метка пакета) — на главном потоке.
    @ObservationIgnored var onMessage: ((MidiMessage, Int32, Double) -> Void)? = nil

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
        _ = MIDIOutputPortCreate(client, "JAMbo Out" as CFString, &outPort)
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
        var dests: [Int32: MIDIEndpointRef] = [:]
        let m: Int = MIDIGetNumberOfDestinations()
        var j: Int = 0
        while j < m {
            let dst: MIDIEndpointRef = MIDIGetDestination(j)
            let id: Int32 = MidiHost.uniqueID(dst)
            outs.append(MidiEndpoint(id: id, name: MidiHost.name(dst)))
            dests[id] = dst
            j += 1
        }
        inputs = ins
        outputs = outs
        destinations = dests
        generation += 1
    }

    /// Выход подключён (по uniqueID).
    func hasDestination(_ id: Int32) -> Bool {
        return destinations[id] != nil
    }

    /// Сообщения UMP (по слову) на выход: по 16 слов на список — помещается в MIDIEventList, даже если каждое слово
    /// займёт свой пакет (MIDIEventListAdd без места вернул бы NULL). Только с главного потока.
    func send(_ words: [UInt32], to id: Int32) {
        guard started, let dst = destinations[id], !words.isEmpty else { return }
        let size: Int = MemoryLayout<MIDIEventList>.size
        var packet: UnsafeMutablePointer<MIDIEventPacket> = MIDIEventListInit(sendList, ._1_0)
        var count: Int = 0
        for w in words {
            if count == 16 {
                MIDISendEventList(outPort, dst, sendList)
                packet = MIDIEventListInit(sendList, ._1_0)
                count = 0
            }
            var word: UInt32 = w
            packet = MIDIEventListAdd(sendList, size, packet, 0, 1, &word)
            count += 1
        }
        MIDISendEventList(outPort, dst, sendList)
    }

    /// Поток CoreMIDI: разбор пакетов, сообщения — на главный поток одним блоком.
    private func receive(_ list: UnsafePointer<MIDIEventList>, _ ref: UnsafeMutableRawPointer?) {
        let source: Int32 = Int32(truncatingIfNeeded: Int(bitPattern: ref))
        let clock = HostClock()
        var msgs: [(MidiMessage, Double)] = []
        for packet in list.unsafeSequence() {
            // Метка 0 — «сейчас».
            let stamp: UInt64 = packet.pointee.timeStamp
            let at: Double = stamp > 0 ? clock.nanoseconds(stamp) / 1e9 : clock.now()
            let count: Int = Int(packet.pointee.wordCount)
            var words = packet.pointee.words
            withUnsafeBytes(of: &words) { raw in
                let all = raw.bindMemory(to: UInt32.self)
                let used = UnsafeBufferPointer<UInt32>(rebasing: all[0..<min(count, all.count)])
                for m in MidiMessage.parse(words: used) { msgs.append((m, at)) }
            }
        }
        if msgs.isEmpty { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let handler = self.onMessage else { return }
            for (msg, at) in msgs { handler(msg, source, at) }
        }
    }

    /// Сообщения с метками времени (такты mach) на выход id или на все выходы (nil): по 16 на список.
    func sendTimed(_ events: [(at: UInt64, word: UInt32)], to id: Int32?) {
        guard started, !events.isEmpty else { return }
        var dsts: [MIDIEndpointRef] = []
        if let i = id {
            if let d = destinations[i] { dsts.append(d) }
        } else {
            dsts = Array(destinations.values)
        }
        let size: Int = MemoryLayout<MIDIEventList>.size
        for dst in dsts {
            var packet: UnsafeMutablePointer<MIDIEventPacket> = MIDIEventListInit(sendList, ._1_0)
            var count: Int = 0
            for e in events {
                if count == 16 {
                    MIDISendEventList(outPort, dst, sendList)
                    packet = MIDIEventListInit(sendList, ._1_0)
                    count = 0
                }
                var word: UInt32 = e.word
                packet = MIDIEventListAdd(sendList, size, packet, e.at, 1, &word)
                count += 1
            }
            MIDISendEventList(outPort, dst, sendList)
        }
    }

    /// Отменить отправленные, но ещё не ушедшие по времени сообщения (выход id или все).
    func flush(_ id: Int32?) {
        guard started else { return }
        if let i = id {
            if let dst = destinations[i] { MIDIFlushOutput(dst) }
        } else {
            MIDIFlushOutput(0)
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
