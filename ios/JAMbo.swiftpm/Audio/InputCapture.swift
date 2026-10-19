import AVFoundation
import Foundation
import Synchronization

// REC с входа (S11e, как startCapture веба для входа): микрофон iPad, аудиоинтерфейс или другое устройство.
// Сессия переходит в режим записи только на время записи (решение пользователя): выбрали INPUT — короткий
// перерыв звука, ■ — обратно в режим воспроизведения. Вход на выход не идёт (узел входа ни к чему не подключён).
// Звук входа — tap на узле входа отдельного AVAudioEngine только на время записи (узел входа основного движка
// не трогается: после него основной движок в режиме воспроизведения не запускается); не колбэк AudioCore —
// блокировка и выделения допустимы; не дольше 60 с;
// на ■ — пересчёт в 48 кГц (AVAudioConverter), если вход работает на другой частоте.

/// Вход звука в меню RECORD FROM: uid порта ("" — вход по умолчанию) и имя записи (встроенный микрофон — MIC).
struct InputPort: Identifiable, Equatable {
    let uid: String
    let label: String
    let name: String
    var id: String { return uid }
}

final class InputCapture: @unchecked Sendable {
    private struct Buf {
        var left: [Float] = []
        var right: [Float] = []
        var stereo = false
        var limit = 0
    }

    private let buf = Mutex(Buf())
    private(set) var rate: Double = 48000
    /// Движок входа — только пока идёт запись.
    private var engine: AVAudioEngine?
    var running: Bool { return engine != nil }

    /// Записанное до сих пор (форма волны во время записи).
    func withBuffer(_ body: ([Float], [Float]) -> Void) {
        buf.withLock { b in body(b.left, b.stereo ? b.right : b.left) }
    }

    /// Ключ пояснения микрофона есть (Capabilities → Microphone в Playgrounds); без него запрос доступа роняет приложение.
    static var allowed: Bool {
        return Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
    }

    /// Разрешение доступа к микрофону (спрашивается один раз).
    static func requestAccess() async -> Bool {
        if !allowed { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// Входы для меню: что знает сессия; пока сессия не в режиме записи, список пуст — тогда вход по умолчанию.
    static func ports() -> [InputPort] {
        let list: [AVAudioSessionPortDescription] = AVAudioSession.sharedInstance().availableInputs ?? []
        if list.isEmpty { return [InputPort(uid: "", label: "iPad microphone", name: "MIC")] }
        return list.map { p in
            let mic: Bool = p.portType == .builtInMic
            return InputPort(uid: p.uid, label: p.portName, name: mic ? "MIC" : p.portName)
        }
    }

    /// Начать: свой движок, tap на узле входа (сессия уже в режиме записи).
    func start() throws -> Bool {
        let e = AVAudioEngine()
        let node: AVAudioInputNode = e.inputNode
        let format: AVAudioFormat = node.outputFormat(forBus: 0)
        if format.channelCount == 0 || format.sampleRate <= 0 { return false }
        rate = format.sampleRate
        let stereo: Bool = format.channelCount > 1
        let limit: Int = Int(format.sampleRate) * Capture.maxSeconds
        buf.withLock { b in
            b = Buf()
            b.stereo = stereo
            b.limit = limit
            b.left.reserveCapacity(limit)
            if stereo { b.right.reserveCapacity(limit) }
        }
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] pcm, _ in
            self?.append(pcm)
        }
        do {
            try e.start()
        } catch {
            node.removeTap(onBus: 0)
            throw error
        }
        engine = e
        return true
    }

    private func append(_ pcm: AVAudioPCMBuffer) {
        guard let ch = pcm.floatChannelData else { return }
        let n = Int(pcm.frameLength)
        let two: Bool = pcm.format.channelCount > 1
        buf.withLock { b in
            let k: Int = Swift.min(n, b.limit - b.left.count)
            if k <= 0 { return }
            b.left.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: k))
            if b.stereo { b.right.append(contentsOf: UnsafeBufferPointer(start: two ? ch[1] : ch[0], count: k)) }
        }
    }

    /// Стоп: снять tap; записанное — в 48 кГц (моно вход — моно сэмпл). nil — ничего не записано.
    func stop() -> (left: [Float], right: [Float]?)? {
        if let e = engine {
            e.inputNode.removeTap(onBus: 0)
            e.stop()
        }
        engine = nil
        let b: Buf = buf.withLock { b in
            let out = b
            b = Buf()
            return out
        }
        if b.left.isEmpty { return nil }
        let right: [Float]? = b.stereo ? b.right : nil
        if abs(rate - AudioCore.sampleRate) < 1 { return (b.left, right) }
        return InputCapture.resample(b.left, right, from: rate)
    }

    /// Пересчёт частоты в 48 кГц (вне колбэка, на ■).
    static func resample(_ l: [Float], _ r: [Float]?, from rate: Double) -> (left: [Float], right: [Float]?)? {
        let chans = AVAudioChannelCount(r == nil ? 1 : 2)
        guard let inF = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: chans, interleaved: false),
              let outF = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioCore.sampleRate, channels: chans,
                                       interleaved: false),
              let conv = AVAudioConverter(from: inF, to: outF),
              let src = AVAudioPCMBuffer(pcmFormat: inF, frameCapacity: AVAudioFrameCount(l.count)) else { return nil }
        src.frameLength = AVAudioFrameCount(l.count)
        guard let sc = src.floatChannelData else { return nil }
        l.withUnsafeBufferPointer { p in sc[0].update(from: p.baseAddress!, count: l.count) }
        if let rr = r { rr.withUnsafeBufferPointer { p in sc[1].update(from: p.baseAddress!, count: rr.count) } }
        let ratio: Double = AudioCore.sampleRate / rate
        let cap = AVAudioFrameCount(Double(l.count) * ratio + 1024)
        guard let dst = AVAudioPCMBuffer(pcmFormat: outF, frameCapacity: cap) else { return nil }
        var given = false
        var err: NSError?
        let status: AVAudioConverterOutputStatus = conv.convert(to: dst, error: &err) { _, st in
            if given {
                st.pointee = .endOfStream
                return nil
            }
            given = true
            st.pointee = .haveData
            return src
        }
        if status == .error { return nil }
        guard let dc = dst.floatChannelData else { return nil }
        let n = Int(dst.frameLength)
        let left: [Float] = Array(UnsafeBufferPointer(start: dc[0], count: n))
        let right: [Float]? = r == nil ? nil : Array(UnsafeBufferPointer(start: dc[1], count: n))
        return (left, right)
    }
}

extension AudioHost {
    /// REC с входа: разрешение, сессия в режим записи (выбранный вход), движок входа. false — нет доступа или вход
    /// не открылся.
    @MainActor
    func beginInput(_ uid: String) async -> Bool {
        if !(await InputCapture.requestAccess()) { return false }
        inputMode = true
        do {
            engine.stop()
            try configureSession()
            let s = AVAudioSession.sharedInstance()
            if !uid.isEmpty, let p = (s.availableInputs ?? []).first(where: { $0.uid == uid }) {
                try s.setPreferredInput(p)
            }
            try engine.start()
            if try input.start() { return true }
        } catch {
            trace("input error: \(error.localizedDescription)")
        }
        endInputMode()
        return false
    }

    /// ■: движок входа — стоп, сессия обратно в режим воспроизведения; записанное (48 кГц) или nil.
    func endInput() -> (left: [Float], right: [Float]?)? {
        let out = input.stop()
        endInputMode()
        return out
    }

    private func endInputMode() {
        _ = input.stop()
        inputMode = false
        try? AVAudioSession.sharedInstance().setPreferredInput(nil)
        restart()
    }
}
