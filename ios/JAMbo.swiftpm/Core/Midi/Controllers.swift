import Foundation

// Контроллеры со своим протоколом (JAMboPAD; позже — Launchpad X и др.). Общее — здесь и в приложении: поиск выходов
// по имени, отправка состояния при его смене и при подключении, приём событий, встроенные маппинги (устройство в
// MIDI → DEVICES; пока оно выключено, контроллеру ничего не шлётся).
// Своё у контроллера — только описание (MidiController): какие байты слать и как читать ответы.

/// Что контроллер может повторять за приложением: гамма, корневая нота, октава клавиатуры выбранной дорожки.
public struct ControllerState: Equatable, Sendable {
    public var root: Int
    public var scale: Int
    public var octave: Int

    public init(root: Int, scale: Int, octave: Int) {
        self.root = root
        self.scale = scale
        self.octave = octave
    }
}

/// Событие с контроллера.
public enum ControllerEvent: Equatable, Sendable {
    /// Корневая нота 0–11 (выбрана на контроллере).
    case root(Int)
    /// Гамма — индекс в Scales.all (выбрана на контроллере).
    case scale(Int)
    /// Ответ пэда на HELLO (JAMboPAD): сторона (0 RIGHT, 1 LEFT), разъём MIDI OUT (0 OFF, 1 CLOCK, 2 ALL),
    /// сообщения пэда туда же и версия прошивки (major << 16 | minor << 8 | patch).
    case pad(side: Int, thru: Int, controls: Bool, version: Int)
}

public protocol MidiController {
    /// Имя в меню MIDI.
    var name: String { get }
    /// Части имени устройства CoreMIDI (без учёта регистра; USB и Bluetooth называются по-разному): по ним — выходы
    /// контроллера.
    var portNames: [String] { get }
    /// Встроенные маппинги, ориентировочные (RESTORE устройства возвращает их).
    var mappings: [MidiMapping] { get }
    /// Состояние слать на все выходы (не только контроллера).
    var stateToAll: Bool { get }
    /// SysEx (без F0 и F7) с состоянием приложения; nil — не слать.
    func stateSysEx(_ s: ControllerState) -> [UInt8]?
    /// Разбор входящего SysEx (без F0 и F7); не наш — nil.
    func event(_ sysex: [UInt8]) -> ControllerEvent?
}

extension MidiController {
    /// Имя устройства принадлежит контроллеру.
    public func owns(_ deviceName: String) -> Bool {
        return portNames.contains { deviceName.range(of: $0, options: .caseInsensitive) != nil }
    }
}

public enum Controllers {
    public static let all: [MidiController] = [JamboPad()]

    public static func named(_ name: String) -> MidiController? {
        return all.first { $0.name == name }
    }
}

/// JAMboPAD (тип JamboPad) — два M-Vave SMC-PAD со своей прошивкой (протокол — djPtrvch/SMC-Pad-Controller, docs/sysex.md и
/// docs/jambo.md): F0 7D 4A 50 <cmd> <data…> F7.
public struct JamboPad: MidiController {
    public static let header: [UInt8] = [0x7D, 0x4A, 0x50]
    public static let setScale: UInt8 = 0x0C
    public static let setMidiOut: UInt8 = 0x0D
    public static let hello: UInt8 = 0x01
    /// DIN_OUT (прошивка 0.7.0+): упакованные байты MIDI — сразу в разъём пэда, при любом режиме MIDI OUT.
    public static let dinOut: UInt8 = 0x11
    public static let dinOutVersion: Int = 0x000700
    public static let reply: UInt8 = 0x40
    public static let sideRight = 0
    public static let sideLeft = 1
    public static let rootEvent: UInt8 = 0x65
    public static let scaleEvent: UInt8 = 0x67

    public init() {}

    public var name: String { return "JAMboPAD" }
    /// По USB — «SMC-PAD», по Bluetooth — «JAMboPAD L» и «JAMboPAD R».
    public var portNames: [String] { return ["SMC-PAD", "JAMboPAD"] }
    /// SET_SCALE — на все выходы (по протоколу; другие устройства SysEx с ID 7D пропускают).
    public var stateToAll: Bool { return true }
    public var mappings: [MidiMapping] { return JamboPad.mappings() }

    /// Маска гаммы: бит k — нота на k полутонов выше корня (Major — 0xAB5).
    public static func mask(scale: Int) -> Int {
        let steps: [Int] = Scales.all[Scales.wrap(scale, Scales.all.count)].steps
        var m: Int = 0
        for s in steps { m |= 1 << s }
        return m
    }

    /// SET_SCALE: корень 0–11, маска (биты 0–6, 7–11), октава 0–7.
    public func stateSysEx(_ s: ControllerState) -> [UInt8]? {
        let m: Int = JamboPad.mask(scale: s.scale)
        let root: Int = Scales.wrap(s.root, 12)
        let oct: Int = min(Scales.octaveMax, max(Scales.octaveMin, s.octave))
        return JamboPad.header + [JamboPad.setScale, UInt8(root), UInt8(m & 0x7F), UInt8((m >> 7) & 0x1F), UInt8(oct)]
    }

    /// SET_MIDI_OUT: разъём MIDI OUT — 0 OFF, 1 CLOCK, 2 ALL; сообщения пэдов туда же — 0/1.
    public static func midiOut(thru: Int, controls: Bool) -> [UInt8] {
        let t: Int = min(2, max(0, thru))
        return header + [setMidiOut, UInt8(t), controls ? 1 : 0]
    }

    /// Выход «разъём пэда» стороны side в списках выходов (MIDI OUT дорожки, CLOCK OUTPUTS): не uniqueID CoreMIDI —
    /// ноты уходят пэду командой DIN_OUT (MidiHost), клок — на сам пэд (режим CLOCK).
    public static func jack(_ side: Int) -> Int32 {
        return Int32.min + 0x4A50 + Int32(side)
    }

    public static func jackSide(_ id: Int32) -> Int? {
        if id == jack(sideRight) { return sideRight }
        if id == jack(sideLeft) { return sideLeft }
        return nil
    }

    public static func jackName(_ side: Int) -> String {
        return "JAMboPAD " + (side == sideLeft ? "L" : "R") + " · MIDI OUT"
    }

    /// Упаковка 7 из 8 (docs/sysex.md): на каждые 7 байт — байт старших битов (бит k — байт k), затем байты без них.
    public static func pack(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i: Int = 0
        while i < bytes.count {
            let n: Int = min(7, bytes.count - i)
            var hi: UInt8 = 0
            for k in 0..<n where bytes[i + k] & 0x80 != 0 { hi |= 1 << UInt8(k) }
            out.append(hi)
            for k in 0..<n { out.append(bytes[i + k] & 0x7F) }
            i += n
        }
        return out
    }

    /// DIN_OUT: байты MIDI (сообщения целиком) — в разъём пэда.
    public static func dinOutSysEx(_ midi: [UInt8]) -> [UInt8] {
        return header + [dinOut] + pack(midi)
    }

    /// HELLO: пэд отвечает версией, стороной и настройкой MIDI OUT (docs/sysex.md).
    public static var helloSysEx: [UInt8] { return header + [hello] }

    /// Сторона пэда по имени (Bluetooth: «JAMboPAD L», «JAMboPAD R»); по USB имя одно — nil (сторона из HELLO).
    public static func side(name: String) -> Int? {
        if name.hasSuffix(" L") { return sideLeft }
        if name.hasSuffix(" R") { return sideRight }
        return nil
    }

    /// ROOT (0x65): корневая нота, выбранная на пэде; SCALE (0x67): номер гаммы (маска после него — не нужна);
    /// ответ HELLO (0x41): статус, версия (3), формат, сторона, профиль, число профилей, MIDI OUT, сообщения пэда, …
    public func event(_ sysex: [UInt8]) -> ControllerEvent? {
        guard sysex.count >= 5, Array(sysex[0..<3]) == JamboPad.header else { return nil }
        if sysex[3] == JamboPad.hello | JamboPad.reply {
            guard sysex.count >= 14, sysex[4] == 0 else { return nil }
            let v: Int = Int(sysex[5]) << 16 | Int(sysex[6]) << 8 | Int(sysex[7])
            return .pad(side: Int(sysex[9]), thru: Int(sysex[12]), controls: sysex[13] != 0, version: v)
        }
        let v: Int = Int(sysex[4])
        if sysex[3] == JamboPad.rootEvent { return v < 12 ? .root(v) : nil }
        if sysex[3] == JamboPad.scaleEvent { return v < Scales.all.count ? .scale(v) : nil }
        return nil
    }

    /// Ориентировочные маппинги по раскладке пэдов по умолчанию (docs/jambo.md; раскладка меняется в конфигураторе,
    /// кнопки — любые кнопки JAMbo: здесь — пример). Каналы — с нуля (канал 1 — 0). Обратная связь — на все пэды:
    /// номера и каналы у двух пэдов не пересекаются
    /// (обратная связь standard — выходы устройства).
    static func mappings() -> [MidiMapping] {
        var out: [MidiMapping] = []
        // 16 ручек: CC 0–15, канал 1, ABSOLUTE; CC = ряд · 4 + колонка — позиция ручки.
        var s: Int = 0
        while s < 16 {
            out.append(map(.cc, ch: 0, num: s, .knob(s), continuous: true))
            s += 1
        }
        var n: Int = 1
        while n <= 16 {
            out.append(map(.note, ch: 1, num: 35 + n, .button("STEP \(n)")))
            out.append(map(.note, ch: 4, num: 35 + n, .button("MUTE \(n)")))
            out.append(map(.note, ch: 5, num: 35 + n, .button("T\(n)")))
            n += 1
        }
        let left: [String] = ["LFO1", "LFO2", "LFO3", "ENV", "MIX", "MST"]
        for (k, b) in left.enumerated() { out.append(map(.note, ch: 1, num: 4 + k, .button(b))) }
        // Правый блок, пэды от левого нижнего: два нижних ряда — страницы 1–8, выше — CHORD, ARP, OCTAVE ▼ ▲,
        // верхний — FX, MOD, SHIFT, MORPH.
        var pads: [String] = []
        for p in 1...8 { pads.append("PAGE \(p)") }
        pads += ["CHORD", "ARP", "OCTAVE ▼", "OCTAVE ▲", "FX", "MOD", "SHIFT", "MORPH"]
        for (k, b) in pads.enumerated() { out.append(map(.note, ch: 2, num: 36 + k, .button(b))) }
        let right: [String] = ["PLAY", "REC", "UNDO", "REDO", "PATTERNS", "GRID ▲", "GRID ▼", "ROW 1", "EQ", "METRONOME"]
        for (k, b) in right.enumerated() { out.append(map(.note, ch: 2, num: k, .button(b))) }
        return out
    }

    private static func map(_ type: MidiSourceType, ch: Int, num: Int, _ t: MidiTarget, continuous: Bool = false) -> MidiMapping {
        return MidiMapping(src: MidiSource(type: type, ch: ch, num: num), target: t, continuous: continuous)
    }
}
