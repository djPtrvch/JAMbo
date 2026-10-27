// Игра аранжировки в колбэке (S15, docs/ai/arranger.md): курсор идёт всегда, пока идёт игра; дорожка, которая
// идёт по таймлайну, играет блок под курсором — клип блока с его места (без ожидания конца прохода), вне блоков
// молчит. Клип из сетки уводит дорожку с таймлайна (Launcher.apply), возврат — сразу с позиции курсора. Петля —
// [loopFrom, loopTo) — только если хоть одна дорожка идёт по таймлайну (игра из сетки и её запись в аранжировку
// идут дальше без петли); все дорожки на таймлайне, петли нет и курсор прошёл последний блок — стоп.

extension Launcher {
    /// Дорожка t идёт по таймлайну (или в сетке); изменение уходит в интерфейс.
    func setFollow(_ t: Int, _ on: Bool, force: Bool = false) {
        if t < 0 || t >= SeqData.maxTracks { return }
        if on { arrDirty[t] = true }
        if follow[t] == on && !force { return }
        follow[t] = on
        out.push(.follow(track: t, on: on))
    }

    /// force — сообщение уходит и без изменения (старт: интерфейс сбросил своё состояние).
    func setFollow(all on: Bool, force: Bool = false) {
        for t in 0..<SeqData.maxTracks { setFollow(t, on, force: force) }
    }

    /// Возврат к таймлайну (во время игры): ожидание клипа снимается.
    func returnToArrange(_ t: Int) {
        if t >= 0 && t < SeqData.maxTracks && queued[t] != Launcher.none {
            queued[t] = Launcher.none
            out.push(.queue(track: t, value: Launcher.none))
        }
        setFollow(t, true)
    }

    /// Переход курсора (во время игры): следующий шаг — pos; дорожки на таймлайне пересчитывают ход.
    func seek(_ pos: Int) {
        arrPos = pos - 1
        for t in 0..<SeqData.maxTracks where follow[t] { arrDirty[t] = true }
    }

    /// Позиция курсора на тике tick (после старта — следующий шаг; петля, если хоть одна дорожка на таймлайне).
    /// false — аранжировка кончилась.
    func arrangeStep(_ d: SeqData, tick: Int) -> Bool {
        if tick > 0 {
            let prev: Int = arrPos
            arrPos += 1
            if d.loop && prev < d.loopTo && arrPos >= d.loopTo && anyFollow(d) { arrPos = d.loopFrom }
        }
        out.push(.arrange(pos: arrPos))
        if d.loop || d.arrEnd <= 0 || arrPos < d.arrEnd { return true }
        for t in 0..<d.trackCount where !follow[t] { return true }
        return false
    }

    /// Хоть одна дорожка идёт по таймлайну.
    @inline(__always)
    func anyFollow(_ d: SeqData) -> Bool {
        var t: Int = 0
        while t < d.trackCount {
            if follow[t] { return true }
            t += 1
        }
        return false
    }

    /// Ход дорожки t по блоку под курсором: другой клип, разрыв (петля, правка блоков) или тишина — сообщение clip.
    func syncArrange(_ d: SeqData, _ t: Int, tick: Int) {
        let j: Int = d.block(t, at: arrPos)
        var k: Int = slot[t]
        var off: Bool = true
        var start: Int = trackStart[t]
        if j >= 0 && d.filled(t, Int(d.blkClip[j])) {
            k = Int(d.blkClip[j])
            off = false
            start = tick - (arrPos - Int(d.blkStart[j]) + Int(d.blkOff[j]))
        }
        if !arrDirty[t] && stopped[t] == off && (off || (slot[t] == k && trackStart[t] == start)) { return }
        arrDirty[t] = false
        slot[t] = k
        stopped[t] = off
        trackStart[t] = off ? tick : start
        out.push(.clip(track: t, slot: k, stopped: off, start: trackStart[t]))
    }
}
