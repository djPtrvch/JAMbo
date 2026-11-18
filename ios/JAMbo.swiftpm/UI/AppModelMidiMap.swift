import Foundation

/// Окно MIDI MAP (S13c): правка маппинга цели в закреплённом условии; устройства меню MIDI → DEVICES.
extension AppModel {
    /// Открыть окно для цели; cond — условие маппинга из списка (иначе — действующее сейчас); back — после закрытия
    /// снова меню MIDI.
    func openMap(_ t: MidiTarget, cond: String? = nil, back: Bool = false) {
        if midiLearn.mapTarget != t { midiLearn.mapPage = .main }
        let m: MidiMapping? = settings.midi.mapping(for: t, midiContext, pinned: cond)
        midiLearn.pinned = m?.condKey ?? cond
        midiLearn.mapTarget = t
        midiLearn.target = t
        midiLearn.mapBack = back
    }

    func closeMap() {
        guard midiLearn.mapTarget != nil else { return }
        midiLearn.mapTarget = nil
        midiLearn.pinned = nil
        if !midiLearn.on { midiLearn.target = nil }
        if midiLearn.mapBack {
            midiLearn.mapBack = false
            midiLearn.tab = .devices
            midiLearn.reopenMenu = true
        }
    }

    /// Маппинг цели окна или черновик (пока цель не назначена).
    var mapCurrent: MidiMapping? {
        guard let t = midiLearn.mapTarget else { return nil }
        if let m = midiMapping(t) { return m }
        return settings.midi.draft(t, continuous: midiContinuous(t), midiContext, pinned: midiLearn.pinned)
    }

    var mapMapped: Bool {
        guard let t = midiLearn.mapTarget else { return false }
        return midiMapping(t) != nil
    }

    /// Правка маппинга цели окна (условие окна следует за правкой).
    func mapUpdate(_ change: @escaping (inout MidiMapping) -> Void) {
        guard let t = midiLearn.mapTarget else { return }
        let ctx: MidiContext = midiContext
        let cont: Bool = midiContinuous(t)
        let pin: String? = midiLearn.pinned
        var key: String = ""
        setMidi { s in key = s.update(t, continuous: cont, ctx, pinned: pin, change) }
        midiLearn.pinned = key
    }

    /// APPLY TO ALL PAGES: ручки страницы маппинга окна (Current page) — на все страницы сетки ручек.
    func mapApplyAllPages() {
        guard let m = mapCurrent, m.cond == .page else { return }
        let page: MidiPage = m.page
        setMidi { s in _ = s.applyKnobsToAllPages(from: page) }
    }

    func mapUnmap() {
        guard let t = midiLearn.mapTarget else { return }
        let ctx: MidiContext = midiContext
        let pin: String? = midiLearn.pinned
        setMidi { $0.unmap(t, ctx, pinned: pin) }
        closeMap()
    }

    /// Номер занят другой целью в том же условии — «used by …» (при записи маппинг перейдёт сюда).
    func mapClash(_ num: Int) -> String? {
        guard let cur = mapCurrent else { return nil }
        var m: MidiMapping = cur
        m.src.num = num
        return settings.midi.mappings.first { $0.target != cur.target && $0.clashes(m) }?.target.label
    }

    /// Открыть окно из списка маппингов устройства (меню закрывается, после окна — снова меню).
    func openMapFromList(_ m: MidiMapping) {
        openMap(m.target, cond: m.condKey, back: true)
    }

    // MARK: — устройства (MIDI → DEVICES)

    /// Включить или выключить устройство; включённый контроллер сразу получает своё состояние (пэды — и HELLO).
    func setDeviceOn(_ name: String, _ on: Bool) {
        setMidi { $0.setOn(name, on) }
        guard settings.midi.device(name)?.controller != nil else { return }
        if on { midiRun.controllerGen = -1 } else { midiLearn.pads = [:] }
    }

    func renameDevice(_ from: String, to: String) {
        var ok: Bool = false
        setMidi { ok = $0.rename(from, to: to) }
        if ok && midiLearn.device == from { midiLearn.device = to }
    }

    func removeDevice(_ name: String) {
        setMidi { $0.remove(name) }
        if midiLearn.device == name { midiLearn.device = nil }
    }

    func restoreDevice(_ name: String) {
        setMidi { $0.restore(name) }
    }

    func clearDevice(_ name: String) {
        setMidi { $0.clear(name) }
    }

    /// Снять маппинг устройства (✕ в списке).
    func removeMapping(_ m: MidiMapping) {
        setMidi { s in
            guard let k = s.devices.firstIndex(where: { $0.name == m.dev }),
                  let i = s.devices[k].mappings.firstIndex(of: m) else { return }
            s.devices[k].mappings.remove(at: i)
        }
    }

    /// IMPORT: системный выбор файлов устройств (.json).
    func chooseDeviceFiles() {
        importingProject = false
        importingLibrary = false
        importingHeads = false
        importingPhones = false
        midiLearn.importing = true
        importing = true
    }

    /// Файлы устройств: встроенный и новое имя — сразу; своё с занятым именем — вопрос REPLACE / ADD COPY (первое такое;
    /// остальные — копиями). Непрочитанные — в окне с OK.
    func importDeviceFiles(_ urls: [URL]) {
        var bad: [String] = []
        for u in urls {
            let access: Bool = u.startAccessingSecurityScopedResource()
            defer { if access { u.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: u), let d = MidiDevice.read(data) else {
                bad.append(u.lastPathComponent)
                continue
            }
            let own: Bool = settings.midi.device(d.name).map { $0.controller == nil } ?? false
            if own && midiLearn.pending == nil {
                midiLearn.pending = d
            } else {
                setMidi { $0.importDevice(d, replace: false) }
            }
        }
        if !bad.isEmpty { midiLearn.note = "Not a JAMbo MIDI device file: " + bad.joined(separator: ", ") + "." }
    }

    /// Ответ на вопрос о занятом имени.
    func importPending(replace: Bool) {
        guard let d = midiLearn.pending else { return }
        midiLearn.pending = nil
        setMidi { $0.importDevice(d, replace: replace) }
    }

    /// EXPORT: файл устройства «имя.json» во временной папке — в окно сохранения в «Файлы».
    func exportDevice(_ name: String) {
        guard let d = settings.midi.device(name), let data = d.fileData() else { return }
        let dir: URL = FileManager.default.temporaryDirectory.appendingPathComponent("midiexport", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe: String = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url: URL = dir.appendingPathComponent(safe + ".json")
        midiLearn.exported = (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }

    /// Новые входы — свои устройства (по поколению выходов MidiHost, вместе с контроллерами).
    func addMidiPorts() {
        let names: [String] = midi.inputs.map { $0.name }
        let ms: MidiSettings = settings.midi
        var fresh: [String] = []
        for n in names {
            var probe: MidiSettings = ms
            if probe.addPort(n) && !fresh.contains(n) { fresh.append(n) }
        }
        if fresh.isEmpty { return }
        setMidi { s in for n in fresh { s.addPort(n) } }
    }
}

extension AppModel {
    /// Параметр места глобального маппинга ручки: «Pitch · T1», «T3 · MIX», «Cutoff · MST».
    func placeLabel(_ m: MidiMapping) -> String? {
        guard let p = m.place, case .knob(let s) = m.target else { return nil }
        let tr: [Track] = project.tracks
        switch p.page {
        case .mix:
            return s < tr.count ? tr[s].name + " · MIX" : "MIX"
        case .master:
            return Params.masterGrid[s].label + " · MST"
        case .mod:
            return Params.modGrid[s].label + " · MOD T\(p.track + 1)"
        case .fx:
            return Params.fxGrid[s].label + " · FX T\(p.track + 1)"
        case .track:
            guard p.track < tr.count else { return "T\(p.track + 1)" }
            return Params.grid(sound: tr[p.track].sample)[s].label + " · T\(p.track + 1)"
        }
    }

    /// Имя устройства по uniqueID (nil — none); отключённое — «Not connected».
    func midiPortName(_ id: Int32?, inputs: Bool, none: String) -> String {
        guard let id = id else { return none }
        let list: [MidiEndpoint] = inputs ? midi.inputs : midi.outputs
        return list.first { $0.id == id }?.name ?? "Not connected"
    }
}
