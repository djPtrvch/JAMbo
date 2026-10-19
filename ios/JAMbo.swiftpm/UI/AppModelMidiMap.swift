import Foundation

/// Окно MIDI MAP (S13c, как ui/mapedit.ts веба): правка маппинга цели в закреплённом условии; пресеты маппингов.
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
            midiLearn.tab = .mapping
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

    /// Открыть окно из списка маппингов меню MIDI (меню закрывается, после окна — снова меню).
    func openMapFromList(_ k: Int) {
        guard k < settings.midi.mappings.count else { return }
        let m: MidiMapping = settings.midi.mappings[k]
        openMap(m.target, cond: m.condKey, back: true)
    }

    // MARK: — пресеты маппингов

    /// Маппинги изменены после загрузки или сохранения пресета («*» в строке Preset).
    var presetModified: Bool {
        guard let p = midiLearn.presets.preset(settings.midi.preset) else { return false }
        return p.mappings != settings.midi.mappings
    }

    /// Загрузить пресет: его маппинги заменяют все нынешние.
    func loadMidiPreset(_ name: String) {
        guard let p = midiLearn.presets.preset(name) else { return }
        setMidi { s in
            s.mappings = p.mappings
            s.preset = p.name
        }
    }

    func saveMidiPreset(_ name: String) {
        guard let n = midiLearn.presets.save(name, settings.midi.mappings) else { return }
        storeMidiPresets()
        setMidi { $0.preset = n }
    }

    func renameMidiPreset(_ from: String, to: String) {
        guard let n = midiLearn.presets.rename(from, to: to) else { return }
        storeMidiPresets()
        if settings.midi.preset == from { setMidi { $0.preset = n } }
    }

    func deleteMidiPreset(_ name: String) {
        midiLearn.presets.delete(name)
        storeMidiPresets()
        if settings.midi.preset == name { setMidi { $0.preset = "" } }
    }

    private func storeMidiPresets() {
        UserDefaults.standard.set(midiLearn.presets.encode(), forKey: "midiPresets")
    }
}

extension AppModel {
    /// Имя устройства по uniqueID (nil — none); отключённое — «Not connected».
    func midiPortName(_ id: Int32?, inputs: Bool, none: String) -> String {
        guard let id = id else { return none }
        let list: [MidiEndpoint] = inputs ? midi.inputs : midi.outputs
        return list.first { $0.id == id }?.name ?? "Not connected"
    }
}
