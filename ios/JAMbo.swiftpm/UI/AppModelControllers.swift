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

    /// Каждый кадр: состояние изменилось или выходы переподключились — слать контроллерам. После переподключения —
    /// HELLO пэдам JAMboPAD (сторона и настройка MIDI OUT каждого).
    func tickControllers() {
        if !midi.started { return }
        let st: ControllerState = controllerState
        if st == midiRun.controllerState && midi.generation == midiRun.controllerGen { return }
        let fresh: Bool = midi.generation != midiRun.controllerGen
        if fresh { addMidiPorts() }
        midiRun.controllerState = st
        midiRun.controllerGen = midi.generation
        let all: [Int32] = midi.outputs.map { $0.id }
        let ms: MidiSettings = settings.midi
        for c in Controllers.all where ms.isOn(c.name) {
            guard let b = c.stateSysEx(st) else { continue }
            midi.sendSysEx(b, to: c.stateToAll ? all : controllerOutputs(c))
        }
        if fresh { helloPads() }
    }

    /// HELLO всем пэдам (если JAMboPAD включён); стороны по Bluetooth — сразу по имени.
    func helloPads() {
        midiRun.padSide = [:]
        midiLearn.pads = [:]
        let pad = JamboPad()
        guard settings.midi.isOn(pad.name) else { return }
        for o in midi.outputs where pad.owns(o.name) {
            if let sd = JamboPad.side(name: o.name) { midiRun.padSide[o.id] = sd }
        }
        midi.sendSysEx(JamboPad.helloSysEx, to: controllerOutputs(pad))
    }

    /// Выходы пэда стороны side (0 RIGHT, 1 LEFT).
    func padOutputs(_ side: Int) -> [Int32] {
        return controllerOutputs(JamboPad()).filter { midiRun.padSide[$0] == side }
    }

    /// SysEx с входа: событие контроллера (ROOT — корневая нота, SCALE — гамма; в ответ уйдёт SET_SCALE).
    func controllerSysEx(_ bytes: [UInt8], source: Int32) {
        if let e = JamboPad().event(bytes), case .pad(let side, let thru, let controls) = e {
            padHello(source, side: side, out: PadOut(thru: thru, controls: controls))
            return
        }
        let ms: MidiSettings = settings.midi
        for c in Controllers.all where ms.isOn(c.name) {
            guard let e = c.event(bytes) else { continue }
            switch e {
            case .root(let r): setRoot(r)
            case .scale(let k): setScale(k)
            case .pad: break
            }
            return
        }
    }

    /// Ответ HELLO с входа source: выходы той же сущности CoreMIDI — пэд этой стороны.
    private func padHello(_ source: Int32, side: Int, out: PadOut) {
        if let ent = midi.inputs.first(where: { $0.id == source })?.entity, ent != 0 {
            for o in midi.outputs where o.entity == ent { midiRun.padSide[o.id] = side }
        }
        midiLearn.pads[side] = out
    }

    /// JAMboPAD, разъём MIDI OUT пэда стороны side (SET_MIDI_OUT): сразу на этот пэд, он хранит у себя.
    func setPadMidiOut(_ side: Int, thru: Int? = nil, controls: Bool? = nil) {
        var o: PadOut = midiLearn.pads[side] ?? PadOut(thru: 1, controls: false)
        if let t = thru { o.thru = t }
        if let c = controls { o.controls = c }
        midiLearn.pads[side] = o
        midi.sendSysEx(JamboPad.midiOut(thru: o.thru, controls: o.controls), to: padOutputs(side))
    }
}
