import Foundation

// Арпеджиатор (docs/ai/sequencer.md, «Арпеджиатор»): режим кнопки CHORD — CHORD или ARP, настройки дорожки (в проекте,
// без UNDO — как ход игры), отправка в колбэк. Звук — Core/Sequencer/Arpeggiator.

extension AppModel {
    /// Кнопка CHORD выбранной дорожки в режиме ARP (на ударной — нет).
    var arpMode: Bool { return channel == .track && !drumTrack && track.arp.mode }

    /// Кнопка CHORD горит: включён текущий режим.
    var chordButtonOn: Bool { return arpMode ? track.arp.on : chordMode[selectedTrack] }

    /// Правка настроек арпеджиатора выбранной дорожки (в проекте, без записи UNDO); сразу — в колбэк.
    func editArp(_ change: (inout TrackArp) -> Void) {
        guard channel == .track else { return }
        let i: Int = selectedTrack
        mutatePlay({ p in
            if i < p.tracks.count { change(&p.tracks[i].arp) }
        }, publish: false)
        syncArp()
    }

    /// Свайп по CHORD: вверх — ARP, вниз — CHORD; включённость переходит к новому режиму (одновременно включён один).
    func setChordArpMode(_ arp: Bool) {
        guard channel == .track, !drumTrack, track.arp.mode != arp else { return }
        let i: Int = selectedTrack
        if arp {
            let was: Bool = chordMode[i]
            chordMode[i] = false
            editArp { a in
                a.mode = true
                a.on = was
            }
        } else {
            let was: Bool = track.arp.on
            editArp { a in
                a.mode = false
                a.on = false
            }
            chordMode[i] = was
        }
    }

    /// Тап по CHORD в режиме ARP: вкл./выкл. арпеджио.
    func toggleArp() {
        editArp { a in a.on.toggle() }
    }

    func setArpDir(_ d: Int) { editArp { a in a.dir = Arp.clampDir(d) } }
    func setArpRate(_ r: Int) { editArp { a in a.rate = Arp.clampRate(r) } }
    func setArpOctaves(_ o: Int) { editArp { a in a.octaves = Arp.clampOctaves(o) } }
    func setArpGate(_ g: Double) { editArp { a in a.gate = Arp.clampGate(g) } }
    func setArpLatch(_ on: Bool) { editArp { a in a.latch = on } }

    /// Настройки арпеджиатора дорожек → колбэк (только изменившиеся; на ударной дорожке ARP не играет).
    func syncArp() {
        let n: Int = min(project.tracks.count, SeqData.maxTracks)
        var i: Int = 0
        while i < SeqData.maxTracks {
            var a: TrackArp = TrackArp()
            if i < n {
                a = project.tracks[i].arp
                if project.tracks[i].drumRole != nil { a.on = false }
                a.on = a.active
            }
            let sent: TrackArp? = i < sentArp.count ? sentArp[i] : nil
            if sent != a {
                audio.core.events.push(.arp(track: i, on: a.on, dir: a.dir, rate: a.rate, octaves: a.octaves,
                                            gate: Float(a.gate), latch: a.latch))
                if i < sentArp.count { sentArp[i] = a }
            }
            i += 1
        }
    }
}

extension AppModel {
    /// Живые ноты дорожки ti играет арпеджиатор (ARP включён, дорожка не ударная).
    func arpPlays(_ ti: Int) -> Bool {
        guard ti >= 0 && ti < project.tracks.count else { return false }
        let t: Track = project.tracks[ti]
        return t.arp.active && t.drumRole == nil
    }

    /// Ноты арпеджио из колбэка → запись (REC), Capture и запись аранжировки: при игре — одна нота на шаг (первая),
    /// длина — по GATE (не меньше шага), сила — p-lock Velocity.
    func drainArp() {
        let q = audio.core.arp.out
        while let o = q.pop() {
            arpNote(o)
        }
    }

    private func arpNote(_ o: ArpOut) {
        let ti: Int = Int(o.track)
        guard ti >= 0 && ti < project.tracks.count && channel == .track && heldSteps.isEmpty else { return }
        let sf: Double = max(1, o.stepFrames)
        let len: Int = max(1, Int((o.gateFrames / sf).rounded()))
        let vel: Double? = o.velocity < 1 ? Double(o.velocity) : nil
        let notes: [Int] = [Int(o.note)]
        var tick: Int? = nil
        if o.playing {
            let k: Int = RecordClock.tick(frame: o.frame, nextTick: o.nextTick, nextFrame: o.nextFrame,
                                          stepFrames: sf, quantize: settings.record.quantize)
            if ti < lastArpTick.count && lastArpTick[ti] == k { return }
            if ti < lastArpTick.count { lastArpTick[ti] = k }
            tick = k
        }
        if recOn && playing && o.playing && !(arrAuto && arrPlay) {
            if let index = record(track: ti, notes: notes, velocity: vel, tick: tick) {
                writeTake(track: ti) { t in t.recordLength(index, len) }
            }
        } else if !(recOn && playing) {
            // Capture: время ноты — по кадру, с поправкой на то, что её слышно сейчас.
            let now: Double = Date.timeIntervalSinceReferenceDate
            let t0: Double = now - max(0, heardFrame() - o.frame) / AudioCore.sampleRate
            let t1: Double = t0 + o.gateFrames / AudioCore.sampleRate
            arpCaptureId -= 1
            captureArp(id: arpCaptureId, track: ti, playing: o.playing, tick: tick ?? 0, t0: t0, t1: t1,
                       notes: notes, velocity: vel)
        }
        if live.recorder.active, let k = tick {
            if let i = live.recordLive(track: ti, heard: k, notes: notes, velocity: vel) {
                live.recordLiveLength(i, len)
            }
        }
    }
}
