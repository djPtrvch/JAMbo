import Foundation

// Устройства MIDI (18.11, решение пользователя): у каждого контроллера — свой профиль со своими маппингами.
// Встроенные (Controllers: JAMboPAD) — всегда в списке, по умолчанию выключены; свои создаются сами при подключении
// нового входа (имя — имя входа). Включать можно сколько угодно: маппинги включённых работают вместе.

public struct MidiDevice: Codable, Equatable, Sendable {
    /// Имя в списке (у встроенного — имя контроллера; переименовать можно только своё).
    public var name: String
    /// Имя входа CoreMIDI, по которому профиль создан ("" — встроенный: его входы — по Controllers.owns).
    public var port: String
    public var on: Bool
    /// Маппинги (у каждого dev = name).
    public var mappings: [MidiMapping]

    public init(name: String, port: String, on: Bool, mappings: [MidiMapping] = []) {
        self.name = name
        self.port = port
        self.on = on
        self.mappings = mappings
        tag()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        name = try c.decode(String.self, forKey: CaseKey("name"))
        port = c.value(CaseKey("port"), "")
        on = c.value(CaseKey("on"), false)
        let maps: [LossyMapping] = c.value(CaseKey("mappings"), [])
        mappings = maps.compactMap { $0.value }
        tag()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(name, forKey: CaseKey("name"))
        try c.encode(port, forKey: CaseKey("port"))
        try c.encode(on, forKey: CaseKey("on"))
        try c.encode(mappings, forKey: CaseKey("mappings"))
    }

    mutating func tag() {
        var i: Int = 0
        while i < mappings.count {
            mappings[i].dev = name
            i += 1
        }
    }

    /// Встроенный контроллер (nil — своё устройство).
    public var controller: MidiController? {
        return port.isEmpty ? Controllers.named(name) : nil
    }

    /// Вход или выход с этим именем принадлежит устройству.
    public func owns(_ portName: String) -> Bool {
        if let c = controller { return c.owns(portName) }
        return portName == port
    }

    /// Встроенный изменён (RESTORE вернёт исходный).
    public var modified: Bool {
        guard let c = controller else { return false }
        return mappings != MidiDevice(name: name, port: "", on: on, mappings: c.mappings).mappings
    }
}

extension MidiSettings {
    /// Длина имени устройства (как в библиотеке).
    public static let nameMax = 40

    /// Маппинги включённых устройств — с ними работают LEARN, окно MIDI MAP, разбор сообщений и обратная связь.
    /// Запись раскладывает по устройствам (по dev); маппинги выключенных не трогает; dev без устройства — новое своё.
    public var mappings: [MidiMapping] {
        get {
            var out: [MidiMapping] = []
            for d in devices where d.on { out += d.mappings }
            return out
        }
        set {
            var k: Int = 0
            while k < devices.count {
                if devices[k].on {
                    let n: String = devices[k].name
                    devices[k].mappings = newValue.filter { $0.dev == n }
                }
                k += 1
            }
            for m in newValue where !devices.contains(where: { $0.name == m.dev }) {
                devices.append(MidiDevice(name: m.dev, port: "", on: true, mappings: newValue.filter { $0.dev == m.dev }))
            }
        }
    }

    public func device(_ name: String) -> MidiDevice? {
        return devices.first { $0.name == name }
    }

    public func isOn(_ name: String) -> Bool {
        return device(name)?.on ?? false
    }

    /// Имена включённых устройств, которым принадлежит вход portName.
    public func owners(_ portName: String) -> [String] {
        return devices.filter { $0.on && $0.owns(portName) }.map { $0.name }
    }

    /// Встроенные — в списке всегда (нет — добавить выключенным, с исходными маппингами).
    mutating func addBuiltIns() {
        for c in Controllers.all where !devices.contains(where: { $0.name == c.name }) {
            devices.insert(MidiDevice(name: c.name, port: "", on: false, mappings: c.mappings), at: 0)
        }
    }

    /// Новый вход: своё устройство с его именем, включённое (ни встроенному, ни своему он не принадлежит).
    /// Возвращает, добавлено ли.
    @discardableResult
    public mutating func addPort(_ portName: String) -> Bool {
        if portName.isEmpty || devices.contains(where: { $0.owns(portName) }) { return false }
        if Controllers.all.contains(where: { $0.owns(portName) }) { return false }
        devices.append(MidiDevice(name: freeName(portName), port: portName, on: true))
        return true
    }

    func freeName(_ base: String) -> String {
        let b: String = String(base.prefix(MidiSettings.nameMax))
        if device(b) == nil { return b }
        var k: Int = 2
        while device("\(b) \(k)") != nil { k += 1 }
        return "\(b) \(k)"
    }

    public mutating func setOn(_ name: String, _ on: Bool) {
        guard let k = devices.firstIndex(where: { $0.name == name }) else { return }
        devices[k].on = on
    }

    /// Переименовать своё (имя занято или встроенное — нет).
    @discardableResult
    public mutating func rename(_ from: String, to: String) -> Bool {
        let n: String = String(to.trimmingCharacters(in: .whitespaces).prefix(MidiSettings.nameMax))
        guard !n.isEmpty, let k = devices.firstIndex(where: { $0.name == from }), devices[k].controller == nil else { return false }
        if n != from && device(n) != nil { return false }
        devices[k].name = n
        devices[k].tag()
        return true
    }

    /// Удалить своё (встроенное — RESTORE).
    public mutating func remove(_ name: String) {
        devices.removeAll { $0.name == name && $0.controller == nil }
    }

    /// Встроенное — исходные маппинги.
    public mutating func restore(_ name: String) {
        guard let k = devices.firstIndex(where: { $0.name == name }), let c = devices[k].controller else { return }
        devices[k].mappings = c.mappings
        devices[k].tag()
    }

    /// Снять все маппинги устройства.
    public mutating func clear(_ name: String) {
        guard let k = devices.firstIndex(where: { $0.name == name }) else { return }
        devices[k].mappings = []
    }
}

// Файл устройства (EXPORT / IMPORT в MIDI → DEVICES, 18.11): JSON {"jambo":"midi-device","version":1,"name","port",
// "mappings"}; маппинги — в том же виде, что в настройках. Включено ли — не пишется.
extension MidiDevice {
    public static let fileTag = "midi-device"

    public func fileData() -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(MidiDeviceFile(name: name, port: port, mappings: mappings))
    }

    /// Разбор файла; не наш или без имени — nil.
    public static func read(_ data: Data) -> MidiDevice? {
        guard let f = try? JSONDecoder().decode(MidiDeviceFile.self, from: data), f.tag == fileTag else { return nil }
        let n: String = String(f.name.trimmingCharacters(in: .whitespaces).prefix(MidiSettings.nameMax))
        if n.isEmpty { return nil }
        return MidiDevice(name: n, port: f.port, on: true, mappings: f.mappings)
    }
}

struct MidiDeviceFile: Codable {
    var tag: String = MidiDevice.fileTag
    var version: Int = 1
    var name: String
    var port: String
    var mappings: [MidiMapping]

    init(name: String, port: String, mappings: [MidiMapping]) {
        self.name = name
        self.port = port
        self.mappings = mappings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        tag = try c.decode(String.self, forKey: CaseKey("jambo"))
        version = c.value(CaseKey("version"), 1)
        name = try c.decode(String.self, forKey: CaseKey("name"))
        port = c.value(CaseKey("port"), "")
        let maps: [LossyMapping] = c.value(CaseKey("mappings"), [])
        mappings = maps.compactMap { $0.value }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(tag, forKey: CaseKey("jambo"))
        try c.encode(version, forKey: CaseKey("version"))
        try c.encode(name, forKey: CaseKey("name"))
        try c.encode(port, forKey: CaseKey("port"))
        try c.encode(mappings, forKey: CaseKey("mappings"))
    }
}

extension MidiSettings {
    /// IMPORT: встроенный (по имени) — его маппинги заменяются; своё с тем же именем — replace: маппинги и вход
    /// заменяются (вкл./выкл. прежнее), иначе — копия со свободным именем, включённая. Возвращает имя в списке.
    @discardableResult
    public mutating func importDevice(_ d: MidiDevice, replace: Bool) -> String {
        if let k = devices.firstIndex(where: { $0.name == d.name }), replace || devices[k].controller != nil {
            devices[k].mappings = d.mappings
            if devices[k].controller == nil { devices[k].port = d.port }
            devices[k].tag()
            return d.name
        }
        var n = d
        n.name = freeName(d.name)
        n.on = true
        n.tag()
        devices.append(n)
        return n.name
    }
}
