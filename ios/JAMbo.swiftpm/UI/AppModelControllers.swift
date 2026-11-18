import Foundation

/// Контроллеры со своим протоколом (Core/Midi/Controllers.swift; JamboPad): состояние — при смене и при подключении
/// выходов (по таймеру UI), события SysEx — как действия на экране, команды из меню MIDI. Только включённые в
/// MIDI → DEVICES; там же при подключении нового входа появляется его своё устройство.
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
        if midi.generation != midiRun.controllerGen { addMidiPorts() }
        midiRun.controllerState = st
        midiRun.controllerGen = midi.generation
        let all: [Int32] = midi.outputs.map { $0.id }
        let ms: MidiSettings = settings.midi
        for c in Controllers.all where ms.isOn(c.name) {
            guard let b = c.stateSysEx(st) else { continue }
            midi.sendSysEx(b, to: c.stateToAll ? all : controllerOutputs(c))
        }
    }

    /// SysEx с входа: событие контроллера (ROOT — корневая нота, SCALE — гамма; в ответ уйдёт SET_SCALE).
    func controllerSysEx(_ bytes: [UInt8], source: Int32) {
        let ms: MidiSettings = settings.midi
        for c in Controllers.all where ms.isOn(c.name) {
            guard let e = c.event(bytes) else { continue }
            switch e {
            case .root(let r): setRoot(r)
            case .scale(let k): setScale(k)
            }
            return
        }
    }

    /// JAMboPAD, разъём MIDI OUT (SET_MIDI_OUT): хранится в настройках, сразу уходит на все SMC-PAD (если включён).
    func setPadMidiOut(thru: Int? = nil, controls: Bool? = nil) {
        setMidi { s in
            if let t = thru { s.padThru = t }
            if let c = controls { s.padControls = c }
        }
        let ms: MidiSettings = settings.midi
        if !ms.isOn(JamboPad().name) { return }
        midi.sendSysEx(JamboPad.midiOut(thru: ms.padThru, controls: ms.padControls), to: controllerOutputs(JamboPad()))
    }
}
