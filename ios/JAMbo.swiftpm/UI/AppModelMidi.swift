import Foundation

/// MIDI (S13): сообщения с входов. Маппинги (S13b) — как палец на цели; LEARN назначает источник; остальные ноты
/// играют как клавиатура (с REC — записываются, длина — по Note Off); клок — S13e.
extension AppModel {
    func startMidi() {
        midi.onMessage = { [weak self] msg, source in self?.midiMessage(msg, source: source) }
        midi.start()
    }

    func setMidi(_ change: (inout MidiSettings) -> Void) {
        updateSettings { s in change(&s.midi) }
        midiRun.toggles.reset()
    }

    /// Условия сейчас: открыта ли сетка паттернов, какую страницу показывает сетка ручек.
    var midiContext: MidiContext {
        let page: MidiPage
        switch channel {
        case .master: page = .master
        case .mix: page = .mix
        case .track: page = modMode ? .mod : (fxMode ? .fx : .track)
        }
        return MidiContext(clipOpen: patternView, page: page, track: selectedTrack)
    }

    func midiMessage(_ msg: MidiMessage, source: Int32) {
        let ms: MidiSettings = settings.midi
        guard ms.accepts(source: source) else { return }
        if msg.isRealtime { return }
        let isCc: Bool = msg.kind == .cc
        let on: Bool = msg.kind == .noteOn
        let src = MidiSource(type: isCc ? .cc : .note, ch: msg.channel, num: msg.data1)
        // LEARN и открытое окно MIDI MAP: движение контроллера назначает источник цели (Number, Channel, Event type,
        // Input port).
        if (midiLearn.on || midiLearn.mapTarget != nil) && (isCc || on) {
            midiLearn.last = src.label
            if let t = midiLearn.mapTarget ?? midiLearn.target {
                // Тот же источник уже назначен — без записи настроек на каждое сообщение (поток CC при повороте).
                if let had = midiMapping(t), had.src == src && had.input == source { return }
                let ctx: MidiContext = midiContext
                let cont: Bool = midiContinuous(t)
                let pin: String? = t == midiLearn.mapTarget ? midiLearn.pinned : nil
                var key: String = ""
                setMidi { s in
                    s.learn(t, src: src, input: source, continuous: cont, ctx, pinned: pin)
                    key = s.mapping(for: t, ctx, pinned: pin)?.condKey ?? ""
                }
                if t == midiLearn.mapTarget && !key.isEmpty { midiLearn.pinned = key }
            }
            return
        }
        let r = ms.resolve(src, input: source, midiContext)
        if r.mapped {
            midiRun.feedbackHold[src] = Date.timeIntervalSinceReferenceDate
            let press: Bool = isCc ? msg.data2 >= 64 : on
            for m in r.active { applyMapping(m, isCc: isCc, value: msg.data2, press: press) }
            return
        }
        midiNote(msg, ms)
    }

    /// Нота с входа (не назначенная): как клавиша.
    private func midiNote(_ msg: MidiMessage, _ ms: MidiSettings) {
        let id: Int = MidiSettings.keyId(channel: msg.channel, note: msg.data1)
        if msg.kind == .noteOff {
            keyUp(id: id)
            return
        }
        guard msg.kind == .noteOn else { return }
        guard let t = ms.noteTrack(msg, selected: selectedTrack, tracks: project.tracks.count) else { return }
        // Повторный Note On без Note Off — прежняя нота отпускается.
        if keyHolds[id] != nil { keyUp(id: id) }
        let v: Double = MidiSettings.velocity(msg.data2, sensitive: settings.velocity)
        keyDown(id: id, notes: [msg.data1], velocity: v, track: t)
    }

    /// Цель с непрерывным значением: ручка или регулятор темпа.
    func midiContinuous(_ t: MidiTarget) -> Bool {
        switch t {
        case .knob: return true
        case .press: return false
        case .button(let n): return MidiButtons.continuous.contains(n)
        }
    }

    private func applyMapping(_ m: MidiMapping, isCc: Bool, value: Int, press: Bool) {
        guard let input = midiRun.toggles.input(m, isCc: isCc, value: value, press: press) else { return }
        switch m.target {
        case .knob(let s):
            midiKnob(s, m, input)
        case .press(let s):
            for p in input.presses(press: press) { midiPress(s, m, p) }
        case .button(let n):
            if n == MidiButtons.bpm {
                midiBpm(m, input)
            } else if n == MidiButtons.level {
                midiLevel(m, input)
            } else if n == MidiButtons.xfader {
                // Кроссфейдер — только во время перехода MIX.
                guard let tr = mix else { return }
                setCrossfade(input.knobValue(m, cur: tr.pos))
            } else if m.control == .latch {
                for p in input.presses(press: press) { midiLatch(n, p) }
            } else {
                for p in input.presses(press: press) { midiButton(n, p) }
            }
        }
    }

    /// Поворот энкодера — одна запись в UNDO, пока он крутится (пауза 0,3 с завершает жест).
    private func midiGesture() {
        if let g = midiRun.gesture {
            g.cancel()
        } else {
            beginGesture()
        }
        let end = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.midiRun.gesture = nil
            self.endGesture()
        }
        midiRun.gesture = end
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: end)
    }

    /// Значение на ручку — как палец: с зажатым шагом p-lock (внутри setKnob), с зажатым LFO/ENV — степень назначения.
    func midiKnob(_ s: Int, _ m: MidiMapping, _ input: MidiInput) {
        // GLOBAL — параметр своего места, что бы ни было на экране.
        if let place = m.place, !place.matches(midiContext) {
            ensureAudio()
            midiGesture()
            withKnobPlace(place) {
                if param(s) != nil { setKnob(s, norm: input.knobValue(m, cur: knobStart(s))) }
            }
            return
        }
        guard param(s) != nil else { return }
        ensureAudio()
        midiGesture()
        if heldSteps.isEmpty && canAssign, let src = heldSource {
            let a = assign(s)
            let amount: Double = a?.lfo == src ? (a?.amount ?? 0) : 0
            let n: Double = input.knobValue(m, cur: (amount + 1) / 2)
            setAssign(s, lfo: src, amount: n * 2 - 1)
            return
        }
        setKnob(s, norm: input.knobValue(m, cur: knobStart(s)))
    }

    /// Нажатие ручки (PRESS): как палец на ручке (MIDI → MAPPING → KNOB PRESS = TOUCH, по умолчанию) или действие
    /// из окна MIDI MAP — сброс, параметр позиции или кнопка.
    private func midiPress(_ s: Int, _ m: MidiMapping, _ down: Bool) {
        if settings.midi.pressTouch {
            midiTouch(s, down)
            return
        }
        switch m.press {
        case .reset:
            if down { midiReset(s) }
        case .param:
            midiKnob(s, m, .button(down))
        case .button(let n):
            midiButton(n, down)
        }
    }

    /// Касание ручки с MIDI, как палец (KnobGrid): нажатие — ручка «под пальцем» (тап по LFO/ENV переносит
    /// назначение), двойное нажатие за 0,35 с — двойной тап (снять назначение, снять p-lock, меню дорожки в MIX).
    private func midiTouch(_ s: Int, _ down: Bool) {
        guard down else {
            knobFingers.remove(s)
            return
        }
        ensureAudio()
        let now: Double = Date.timeIntervalSinceReferenceDate
        if let t = midiRun.pressTap[s], now - t < 0.35 {
            midiRun.pressTap[s] = nil
            if heldSteps.isEmpty && canAssign, let src = heldSource {
                clearAssign(s, lfo: src)
            } else {
                knobDoubleTap(s)
            }
        } else {
            midiRun.pressTap[s] = now
        }
        if channel != .mix { knobFingers.insert(s) }
    }

    /// Сброс ручки: с зажатым LFO/ENV — снять назначение, с зажатым шагом или SHIFT — снять p-lock (как двойной тап),
    /// иначе — значение по умолчанию.
    func midiReset(_ s: Int) {
        if heldSteps.isEmpty && canAssign, let src = heldSource {
            clearAssign(s, lfo: src)
            return
        }
        if !heldSteps.isEmpty || shiftHeld {
            knobDoubleTap(s)
            return
        }
        guard let p = param(s) else { return }
        beginGesture()
        setKnob(s, norm: p.toNorm(p.def))
        endGesture()
    }

    /// Темп: как ручка — диапазон 40–240 BPM по Range.
    private func midiBpm(_ m: MidiMapping, _ input: MidiInput) {
        let lo: Double = Params.bpmMin
        let hi: Double = Params.bpmMax
        let cur: Double = (project.bpm - lo) / (hi - lo)
        midiGesture()
        // Темп с MIDI — целыми BPM (решение пользователя).
        setBpm((lo + input.knobValue(m, cur: cur) * (hi - lo)).rounded())
    }

    /// Регулятор громкости измерителя: как ручка — весь ход шкалы (−60…0 dB) по Range.
    private func midiLevel(_ m: MidiMapping, _ input: MidiInput) {
        let ch: Int = meterChannel
        let lo: Double = Params.volMin
        let cur: Double = (meterVol(ch) - lo) / -lo
        midiGesture()
        setMeterVol(ch, lo + input.knobValue(m, cur: cur) * -lo)
    }

    /// Кнопка по имени: нажатие и отпускание (отпускание — только той, что нажата с MIDI).
    func midiButton(_ name: String, _ down: Bool) {
        if down {
            if midiRun.down.contains(name) { return }
            midiRun.down.insert(name)
            midiButtonPress(name)
        } else {
            guard midiRun.down.remove(name) != nil else { return }
            midiButtonRelease(name)
        }
    }

    // MARK: — LEARN

    func setLearn(_ on: Bool) {
        midiLearn.on = on
        midiLearn.target = nil
        midiLearn.last = ""
    }

    /// Тап в режиме LEARN выбирает цель (её действие не выполняется).
    func learnPick(_ t: MidiTarget) {
        midiLearn.target = t
        midiLearn.last = ""
    }

    /// Тап по цели в LEARN: двойной — окно MIDI MAP; при открытом окне — окно переходит на цель. PATTERNS ещё и
    /// переключает сетку паттернов — так можно добраться до её ячеек и строк.
    func learnTap(_ t: MidiTarget) {
        let now: Double = Date.timeIntervalSinceReferenceDate
        if let l = midiLearn.lastTap, l.target == t, now - l.at < 0.35 {
            midiLearn.lastTap = nil
            openMap(t)
            return
        }
        midiLearn.lastTap = (t, now)
        learnPick(t)
        if t == .button("PATTERNS") { togglePatterns() }
        if midiLearn.mapTarget != nil { openMap(t) }
    }

    /// Тап по ручке в LEARN: поворот или нажатие — по переключателю TURN / PRESS.
    func learnKnob(_ s: Int) {
        learnTap(midiLearn.press ? .press(s) : .knob(s))
    }

    func learnUnmap() {
        guard let t = midiLearn.target else { return }
        let ctx: MidiContext = midiContext
        let pin: String? = t == midiLearn.mapTarget ? midiLearn.pinned : nil
        setMidi { $0.unmap(t, ctx, pinned: pin) }
    }

    /// Маппинг цели сейчас (метки в LEARN; у цели окна MIDI MAP — в закреплённом условии).
    func midiMapping(_ t: MidiTarget) -> MidiMapping? {
        let pin: String? = t == midiLearn.mapTarget ? midiLearn.pinned : nil
        return settings.midi.mapping(for: t, midiContext, pinned: pin)
    }

    func removeMapping(_ k: Int) {
        setMidi { s in
            if k < s.mappings.count { s.mappings.remove(at: k) }
        }
    }

    func clearMappings() {
        setMidi { $0.mappings = [] }
    }
}
