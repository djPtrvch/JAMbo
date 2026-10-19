// Запись стемов (S11d, как stems.ts и transport.ts веба), в колбэке на каждом шаге — с точностью до отсчёта.
// Кнопка ● готовит дорожку (armStem); запись готовых дорожек, у которых играет клип, начинается с PLAY — с первого
// шага. Строки идут по сетке (строк больше одной, повторы, LOOP ROW выключена) — пишется всё, как играет, конец —
// когда строки пошли по кругу или кончились; без строк клип по кругу пишется один раз — конец на границе прохода,
// где дальше клип, уже записанный в этот стем; дорожка остановилась — конец там же. Тап по ● во время записи —
// дописать до конца прохода (finishStem); PLAY во время записи — дописать всё и остановиться (requestStemStop).
// Мастер — по тем же правилам: граница прохода — у строки (её самый длинный клип), без строки — у самого длинного
// играющего клипа; конец без строк — когда все играющие клипы уже записаны.

/// Состояние правил записи (только колбэк; каналы — как у StemRing).
final class StemRules {
    let armed = UnsafeMutablePointer<Bool>.allocate(capacity: StemRing.channels)
    let rec = UnsafeMutablePointer<Bool>.allocate(capacity: StemRing.channels)
    let finish = UnsafeMutablePointer<Bool>.allocate(capacity: StemRing.channels)
    let startTick = UnsafeMutablePointer<Int>.allocate(capacity: StemRing.channels)
    let lastEnd = UnsafeMutablePointer<Int64>.allocate(capacity: StemRing.channels)
    /// Клипы (биты ячеек), уже записанные в стем дорожки; у мастера — клипы каждой дорожки.
    let seen = UnsafeMutablePointer<UInt16>.allocate(capacity: SeqData.maxTracks)
    let masterSeen = UnsafeMutablePointer<UInt16>.allocate(capacity: SeqData.maxTracks)
    /// PLAY во время записи: остановить транспорт, когда допишутся все стемы.
    var stopAsked = false

    init() {
        armed.initialize(repeating: false, count: StemRing.channels)
        rec.initialize(repeating: false, count: StemRing.channels)
        finish.initialize(repeating: false, count: StemRing.channels)
        startTick.initialize(repeating: 0, count: StemRing.channels)
        lastEnd.initialize(repeating: -1, count: StemRing.channels)
        seen.initialize(repeating: 0, count: SeqData.maxTracks)
        masterSeen.initialize(repeating: 0, count: SeqData.maxTracks)
    }

    deinit {
        armed.deallocate()
        rec.deallocate()
        finish.deallocate()
        startTick.deallocate()
        lastEnd.deallocate()
        seen.deallocate()
        masterSeen.deallocate()
    }

    var anyRecording: Bool {
        var c = 0
        while c < StemRing.channels {
            if rec[c] { return true }
            c += 1
        }
        return false
    }
}

extension Sequencer {
    // MARK: — команды интерфейса (через CoreEvent)

    /// Готовность канала к записи (кнопка ● горит).
    func armStem(_ ch: Int, _ on: Bool) {
        if ch >= 0 && ch < StemRing.channels { stemRules.armed[ch] = on }
    }

    /// Тап по ● во время записи: стем дописывается до конца прохода, готовность снимается.
    func finishStem(_ ch: Int) {
        if ch < 0 || ch >= StemRing.channels { return }
        stemRules.armed[ch] = false
        if stemRules.rec[ch] { stemRules.finish[ch] = true }
    }

    /// PLAY во время записи: дописать проходы и остановиться. false — ничего не пишется (остановить сразу).
    func requestStemStop() -> Bool {
        if !playing || !stemRules.anyRecording { return false }
        stemRules.stopAsked = true
        return true
    }

    // MARK: — на каждом шаге

    /// Шаг tick в кадре time (строки и клипы на этом тике уже сменились). true — пора остановить транспорт.
    func stemsStep(_ d: SeqData, at time: Double) -> Bool {
        let s = stemRules
        let at = Int64(time.rounded(.down))
        if tick == 0 { stemsStart(d, at: at) }
        let arranged = stemsArranged(d)
        let wrapped = launcher.wrappedAt == tick
        let m = StemRing.master
        // Мастер: всё остановилось — конец; на границе прохода — строки пошли по кругу или всё уже записано.
        if s.rec[m] {
            if !stemsAnyPlaying(d) {
                stemEnd(m, at)
            } else if stemsMasterEdge(d, tick) && tick > s.startTick[m] {
                if s.stopAsked || s.finish[m] || (arranged ? wrapped : stemsMasterAllSeen(d)) {
                    stemEnd(m, at)
                } else {
                    stemsMasterSee(d)
                }
            }
        }
        var t = 0
        while t < SeqData.maxTracks {
            if !s.rec[t] {
                t += 1
                continue
            }
            if t >= d.trackCount || !launcher.plays(d, t) {
                stemEnd(t, at)
                t += 1
                continue
            }
            let len = d.tickLen(t, slot: launcher.slot[t])
            let boundary = len > 0 && (tick - launcher.trackStart[t]) % len == 0
            if boundary && tick > s.startTick[t] {
                let bit = UInt16(1) << UInt16(launcher.slot[t])
                if s.stopAsked || s.finish[t] || (arranged ? wrapped : s.seen[t] & bit != 0) {
                    stemEnd(t, at)
                } else {
                    s.seen[t] |= bit
                }
            }
            t += 1
        }
        stemsPredict(d, arranged)
        if s.stopAsked && !s.anyRecording {
            s.stopAsked = false
            return true
        }
        return false
    }

    /// Транспорт остановился: всё, что пишется, кончается в кадре at.
    func stemsStopped(at: Int64) {
        let s = stemRules
        var c = 0
        while c < StemRing.channels {
            if s.rec[c] { stemEnd(c, at) }
            c += 1
        }
        s.stopAsked = false
    }

    // MARK: — внутреннее

    /// PLAY: готовые и играющие дорожки, мастер — если что-то играет.
    private func stemsStart(_ d: SeqData, at: Int64) {
        let s = stemRules
        if !stemRing.isReady { return }
        let m = StemRing.master
        if s.armed[m] && stemsAnyPlaying(d) {
            stemBegin(m, at)
            var t = 0
            while t < SeqData.maxTracks {
                s.masterSeen[t] = 0
                t += 1
            }
            stemsMasterSee(d)
        }
        var t = 0
        while t < d.trackCount {
            if s.armed[t] && launcher.plays(d, t) {
                stemBegin(t, at)
                s.seen[t] = UInt16(1) << UInt16(launcher.slot[t])
            }
            t += 1
        }
    }

    private func stemBegin(_ ch: Int, _ at: Int64) {
        let s = stemRules
        s.rec[ch] = true
        s.finish[ch] = false
        s.startTick[ch] = tick
        s.lastEnd[ch] = -1
        stemRing.begin(ch, at: at)
    }

    private func stemEnd(_ ch: Int, _ at: Int64) {
        let s = stemRules
        s.rec[ch] = false
        s.finish[ch] = false
        stemRing.end(ch, at: at)
    }

    /// Строки идут по сетке: играет строка с повторами, строк больше одной и LOOP ROW выключена.
    private func stemsArranged(_ d: SeqData) -> Bool {
        let row = launcher.sceneRow
        if row < 0 { return false }
        return d.repeats[min(row, SeqData.slots - 1)] > 0 && !d.rowLoop && d.rows > 1
    }

    private func stemsAnyPlaying(_ d: SeqData) -> Bool {
        var t = 0
        while t < d.trackCount {
            if launcher.plays(d, t) { return true }
            t += 1
        }
        return false
    }

    private func stemsMasterSee(_ d: SeqData) {
        var t = 0
        while t < d.trackCount {
            if launcher.plays(d, t) { stemRules.masterSeen[t] |= UInt16(1) << UInt16(launcher.slot[t]) }
            t += 1
        }
    }

    private func stemsMasterAllSeen(_ d: SeqData) -> Bool {
        var t = 0
        while t < d.trackCount {
            if launcher.plays(d, t) && stemRules.masterSeen[t] & (UInt16(1) << UInt16(launcher.slot[t])) == 0 {
                return false
            }
            t += 1
        }
        return true
    }

    /// Граница прохода для мастера: у строки — её проход, иначе — самого длинного играющего клипа.
    private func stemsMasterEdge(_ d: SeqData, _ k: Int) -> Bool {
        if launcher.sceneRow >= 0 {
            let len = launcher.sceneLen
            return len > 0 && (k - launcher.sceneStart) % len == 0
        }
        var best = -1
        var bestLen = 0
        var t = 0
        while t < d.trackCount {
            if launcher.plays(d, t) {
                let len = d.tickLen(t, slot: launcher.slot[t])
                if best < 0 || len > bestLen {
                    best = t
                    bestLen = len
                }
            }
            t += 1
        }
        return best >= 0 && bestLen > 0 && (k - launcher.trackStart[best]) % bestLen == 0
    }

    /// Ожидаемый конец записи каждого пишущегося канала (для частого мигания) — в интерфейс, если изменился.
    private func stemsPredict(_ d: SeqData, _ arranged: Bool) {
        let s = stemRules
        var c = 0
        while c < StemRing.channels {
            if s.rec[c] {
                let k: Int = c == StemRing.master ? stemsMasterEndTick(d, arranged) : stemsTrackEndTick(d, c, arranged)
                let f: Int64 = k >= 0 ? Int64(stepFrame(k).rounded(.down)) : -1
                if f != s.lastEnd[c] {
                    s.lastEnd[c] = f
                    stemRing.endAt(c, frame: f)
                }
            }
            c += 1
        }
    }

    /// Тик конца стема дорожки, если он уже виден (−1 — нет): ближайшая граница прохода, если на ней стем кончится;
    /// строки по сетке — конец последней строки.
    private func stemsTrackEndTick(_ d: SeqData, _ t: Int, _ arranged: Bool) -> Int {
        if t >= d.trackCount || !launcher.plays(d, t) { return -1 }
        let s = stemRules
        let len = d.tickLen(t, slot: launcher.slot[t])
        if len <= 0 { return -1 }
        let start = launcher.trackStart[t]
        let at = start + ((tick - start) / len + 1) * len
        let q = launcher.queued[t]
        if s.stopAsked || s.finish[t] || q == Launcher.stop { return at }
        if arranged {
            let row = launcher.sceneRow
            if row + 1 >= d.rows {
                return launcher.sceneStart + Int(d.repeats[min(row, SeqData.slots - 1)]) * launcher.sceneLen
            }
            return -1
        }
        if q >= 0 { return s.seen[t] & (UInt16(1) << UInt16(q)) != 0 ? at : -1 }
        let sceneChanges = launcher.sceneQueued >= 0 || (launcher.sceneRow >= 0 && launcher.sceneEnds(d, at))
        return sceneChanges ? -1 : at
    }

    /// Тик конца записи мастера, если виден: просили дописать или (без строк) все играющие клипы уже записаны.
    private func stemsMasterEndTick(_ d: SeqData, _ arranged: Bool) -> Int {
        let s = stemRules
        let m = StemRing.master
        if !(s.stopAsked || s.finish[m] || (!arranged && stemsMasterAllSeen(d))) { return -1 }
        var k = tick + 1
        while k < tick + 4096 {
            if stemsMasterEdge(d, k) { return k }
            k += 1
        }
        return -1
    }
}
