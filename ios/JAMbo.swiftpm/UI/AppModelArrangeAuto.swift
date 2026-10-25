import SwiftUI

/// Окно AUTO в аранжировщике (S15f2, решения пользователя): на месте строки дорожек, секвенсора и клавиатуры; слева —
/// список кривых выбранной дорожки и «+», справа — кривая выбранной строки под таймлайном (тот же масштаб и прокрутка).
extension AppModel {
    /// Окно AUTO открыто: аранжировщик и AUTO.
    var arrAutoPanel: Bool { return arrangeView && arrAuto }

    /// Дорожка окна AUTO: выбранная (при MIX и MST — нет).
    var arrAutoTrack: Int? {
        guard channel == .track, selectedTrack < project.tracks.count else { return nil }
        return selectedTrack
    }

    /// Ручки сетки дорожки, которые можно автоматизировать (в порядке сетки).
    func arrAutoKnobs(_ t: Int) -> [ParamDef] {
        guard t >= 0 && t < project.tracks.count else { return [] }
        return Params.grid(sound: project.tracks[t].sample).filter { !$0.id.isEmpty && ArrAutoTarget.index($0.id) != nil }
    }

    /// Ручка id: с сетки дорожки (подписи движка синта), иначе из общей таблицы.
    func arrAutoDef(_ t: Int, _ id: String) -> ParamDef? {
        return arrAutoKnobs(t).first { $0.id == id } ?? Params.byId[id]
    }

    func arrAutoLabel(_ t: Int, _ id: String) -> String {
        return arrAutoDef(t, id)?.label ?? id
    }

    /// Ручка окна AUTO: выбранная строка (если она есть у дорожки), иначе первая; строк нет — nil.
    func arrAutoParam(_ t: Int) -> ParamDef? {
        guard t >= 0 && t < project.tracks.count else { return nil }
        let autos: [ArrAutoLane] = project.tracks[t].autos
        let id: String? = autos.contains { $0.param == arrAutoId } ? arrAutoId : autos.first?.param
        return id.flatMap { arrAutoDef(t, $0) }
    }

    /// «+»: строка ручки id (пустая кривая — точки ставят тапом) и выбор её; уже есть — только выбор.
    func arrAutoAdd(track t: Int, _ id: String) {
        guard t >= 0 && t < project.tracks.count else { return }
        arrAutoId = id
        if project.tracks[t].autoLane(id) == nil { edit { p in p.tracks[t].setAuto(id, []) } }
    }

    /// DELETE: строка (кривая ручки) убирается.
    func arrAutoDelete(track t: Int, _ id: String) {
        guard t >= 0 && t < project.tracks.count, project.tracks[t].autoLane(id) != nil else { return }
        edit { p in p.tracks[t].deleteAuto(id) }
    }

    /// Точки кривой (тап, перетаскивание, удаление; при перетаскивании — внутри жеста, одна запись UNDO).
    func arrAutoSet(track t: Int, _ id: String, _ points: [ArrAutoPoint]) {
        guard t >= 0 && t < project.tracks.count else { return }
        edit { p in p.tracks[t].setAuto(id, points) }
    }

    /// Шаг точки: с магнитом — на ближайшей линии сетки таймлайна (1 BAR, 1/2, 1/4, 1 STEP), без — четверть шага.
    func arrAutoSnap(_ x: Double) -> Double {
        let a: Arrangement = project.arrange
        if a.snap {
            let g: Double = Double(max(1, a.gridSteps))
            return max(0, (x / g).rounded() * g)
        }
        return max(0, (x * 4).rounded() / 4)
    }
}

/// Записываемый кусок кривой (S15f3): дорожка, ручка (слот сетки и id), значение ручки до записи, куски точек
/// (петля — новый кусок).
struct AutoTake {
    let track: Int
    let slot: Int
    let id: String
    let base: Double
    var segs: [[ArrAutoPoint]] = [[]]
}

extension AppModel {
    // MARK: — запись ручек и рука (S15f3)

    /// Позиция курсора аранжировки сейчас (шаги, дробная).
    var arrNowX: Double {
        if !playing { return Double(arrCursor) }
        let step: Double = 15 / max(20, project.bpm)
        let f: Double = (Date.timeIntervalSinceReferenceDate - live.arrPosTime) / step
        return Double(live.arrPos) + min(0.95, max(0, f))
    }

    /// Значение кривой ручки id дорожки t, которое сейчас звучит (дорожка на таймлайне); nil — кривая не действует.
    func autoCurveNorm(_ t: Int, _ id: String) -> Double? {
        guard playing, t >= 0, t < project.tracks.count, t < live.following.count, live.following[t],
              let k = project.tracks[t].autoLane(id) else { return nil }
        return project.tracks[t].autos[k].value(at: arrNowX)
    }

    /// Ручка id выбранной дорожки под рукой (палец, энкодер при записи): кривая на ней не действует.
    func autoHand(_ id: String) -> Bool {
        guard let key = autoKey(selectedTrack, id) else { return false }
        return autoHeld.contains(key)
    }

    /// Пишется ли поворот ручки id: REC + PLAY + AUTO, ручка дорожки (не FX).
    func autoRecording(_ id: String) -> Bool {
        return arrRecording && channel == .track && !fxMode && ArrAutoTarget.index(id) != nil
    }

    private func autoKey(_ t: Int, _ id: String) -> Int? {
        guard let j = ArrAutoTarget.index(id) else { return nil }
        return t * ArrAutoTarget.count + j
    }

    /// Палец на ручке (или нажатие энкодера): её кривая не действует — слышна рука; отпустили — кусок записи кончился.
    func knobTouch(_ slot: Int, _ on: Bool) {
        if !on {
            guard let key = autoSlotKeys.removeValue(forKey: slot) else { return }
            flushAutoTake(key)
            autoHold(key, false)
            return
        }
        guard channel == .track, !fxMode, !modMode, let p = param(slot), let key = autoKey(selectedTrack, p.id) else { return }
        autoSlotKeys[slot] = key
        autoHold(key, true)
    }

    private func autoHold(_ key: Int, _ on: Bool) {
        if on == autoHeld.contains(key) { return }
        if on { autoHeld.insert(key) } else { autoHeld.remove(key) }
        let n: Int = ArrAutoTarget.count
        audio.core.events.push(.autoHold(track: key / n, target: key % n, on: on))
    }

    /// Первый поворот записи: запомнить ручку до записи.
    func autoTakeBegin(_ slot: Int, _ p: ParamDef) {
        let t: Int = selectedTrack
        guard let key = autoKey(t, p.id), autoTakes[key] == nil else { return }
        autoTakes[key] = AutoTake(track: t, slot: slot, id: p.id, base: track.params[p.id] ?? p.def)
        autoHold(key, true)
    }

    /// Точка записи на текущей позиции курсора; курсор прыгнул назад (петля) — новый кусок.
    func autoTakePoint(_ id: String, _ norm: Double) {
        guard let key = autoKey(selectedTrack, id), var take = autoTakes[key] else { return }
        let x: Double = arrNowX
        let pt = ArrAutoPoint(x: x, y: min(1, max(0, norm)))
        if let last = take.segs[take.segs.count - 1].last, x < last.x - 0.5 {
            take.segs.append([pt])
        } else {
            take.segs[take.segs.count - 1].append(pt)
        }
        autoTakes[key] = take
        // Энкодер MIDI без касания: кусок кончается через 0,3 с без поворотов.
        autoFlush?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushAutoTakes(all: false) }
        autoFlush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Кусок записи — в кривую (упрощение, замена точек на участке), ручка — прежнее значение; одна запись UNDO.
    func flushAutoTake(_ key: Int) {
        guard let take = autoTakes.removeValue(forKey: key) else { return }
        let segs: [[ArrAutoPoint]] = take.segs.filter { !$0.isEmpty }
        if take.track >= project.tracks.count { return }
        edit { p in
            p.tracks[take.track].params[take.id] = take.base
            for s in segs { p.tracks[take.track].recordAuto(take.id, s) }
        }
    }

    /// Конец записи (all) или пауза энкодера: куски без пальца на ручке — в кривые.
    func flushAutoTakes(all: Bool) {
        for (key, take) in autoTakes {
            if !all && take.track == selectedTrack && knobFingers.contains(take.slot) { continue }
            flushAutoTake(key)
            if !knobFingers.contains(take.slot) || all { autoHold(key, false) }
        }
    }
}
