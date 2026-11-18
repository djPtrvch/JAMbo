import Foundation

/// Контроллеры со своим протоколом (Core/Midi/Controllers.swift; JamboPad): состояние — при смене и при подключении
/// выходов (по таймеру UI), события SysEx — как действия на экране, команды из меню MIDI.
extension AppModel {
    /// Состояние для контроллеров: гамма, корень, октава клавиатуры выбранной дорожки.
    var controllerState: ControllerState {
        return ControllerState(root: project.root, scale: project.scale, octave: octave)
    }

    /// Выходы контроллера (по имени устройства).
    func controllerOutputs(_ c: MidiController) -> [Int32] {
        return midi.outputs.filter { c.owns($0.name) }.map { $0.id }
    }

    /// Каждый кадр: состояние изменилось или выходы переподключились — слать контроллерам.
    func tickControllers() {
        if !midi.started { return }
        let st: ControllerState = controllerState
        if st == midiRun.controllerState && midi.generation == midiRun.controllerGen { return }
        midiRun.controllerState = st
        midiRun.controllerGen = midi.generation
        let all: [Int32] = midi.outputs.map { $0.id }
        for c in Controllers.all {
            guard let b = c.stateSysEx(st) else { continue }
            midi.sendSysEx(b, to: c.stateToAll ? all : controllerOutputs(c))
        }
    }

    /// SysEx с входа: событие контроллера (ROOT — корневая нота, SCALE — гамма; в ответ уйдёт SET_SCALE).
    func controllerSysEx(_ bytes: [UInt8], source: Int32) {
        for c in Controllers.all {
            guard let e = c.event(bytes) else { continue }
            switch e {
            case .root(let r): setRoot(r)
            case .scale(let k): setScale(k)
            }
            return
        }
    }

    /// JAMboPAD, разъём MIDI OUT (SET_MIDI_OUT): хранится в настройках, сразу уходит на все SMC-PAD.
    func setPadMidiOut(thru: Int? = nil, controls: Bool? = nil) {
        setMidi { s in
            if let t = thru { s.padThru = t }
            if let c = controls { s.padControls = c }
        }
        let ms: MidiSettings = settings.midi
        midi.sendSysEx(JamboPad.midiOut(thru: ms.padThru, controls: ms.padControls), to: controllerOutputs(JamboPad()))
    }

    // MARK: — пресеты маппингов: встроенные (контроллеры) и свои

    /// Пресет по имени: свой (в том числе сохранённая настройка встроенного), затем встроенный.
    func midiPreset(_ name: String) -> MidiPreset? {
        return midiLearn.presets.preset(name) ?? Controllers.presets.first { $0.name == name }
    }

    /// Список пресетов: встроенные (или их сохранённые настройки) первыми, затем свои.
    var midiPresetList: [MidiPreset] {
        let own: [MidiPreset] = midiLearn.presets.list
        let builtIn: [MidiPreset] = Controllers.presets.map { b in own.first { $0.name == b.name } ?? b }
        return builtIn + own.filter { !Controllers.isBuiltIn($0.name) }
    }

    /// Встроенный пресет сохранён со своей настройкой (DELETE вернёт исходный).
    func midiPresetOverridden(_ name: String) -> Bool {
        return Controllers.isBuiltIn(name) && midiLearn.presets.preset(name) != nil
    }
}
