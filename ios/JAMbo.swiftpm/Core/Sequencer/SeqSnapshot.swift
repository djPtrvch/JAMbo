// Снимок паттернов для аудиопотока: плоские массивы чисел, без Swift-коллекций и ARC.
// Строится в основном потоке после каждой правки (SeqSnapshot(project)), передаётся в колбэк через очередь
// (AudioCore.publish); прежний возвращается обратно и освобождается в основном потоке.

/// Указатели снимка — простые значения: колбэк копирует их себе, не трогая счётчик ссылок.
/// У каждого клипа (дорожка·slots + ячейка) свой паттерн: блок шагов (номер блока или −1 — ячейка пуста),
/// длина и играющие страницы.
public struct SeqData {
    public static let maxTracks = Params.maxTracks
    public static let maxSteps = Params.maxPages * Params.stepsPerPage
    public static let maxNotes = 8
    public static let slots = Params.patternSlots

    public var trackCount: Int = 0
    /// На дорожку: остановлена, активная ячейка (колбэк берёт их, пока транспорт стоит; при игре ими управляет сам).
    public var stopped: UnsafeMutablePointer<UInt8>
    public var slot: UnsafeMutablePointer<Int32>
    /// На клип: блок шагов (−1 — пусто), длина паттерна, страницы from…to.
    public var clipBlock: UnsafeMutablePointer<Int32>
    public var clipLength: UnsafeMutablePointer<Int32>
    public var clipFrom: UnsafeMutablePointer<Int32>
    public var clipTo: UnsafeMutablePointer<Int32>
    /// Скорость клипа (Clip.rate: 1 — ×2, 0 — ×1, −1…−4 — 1/2…1/16).
    public var clipRate: UnsafeMutablePointer<Int8>
    /// На шаг (блок·maxSteps + шаг): триг, длина, число нот и ноты (·maxNotes), Chance, Ratchet, Swing (с p-lock).
    public var on: UnsafeMutablePointer<UInt8>
    public var len: UnsafeMutablePointer<Int32>
    public var noteCount: UnsafeMutablePointer<UInt8>
    public var notes: UnsafeMutablePointer<Int16>
    /// Ноты со своими длинами или velocity (S8): split шага, длина (шаги) и velocity (Level; −1 — без своей) ·maxNotes.
    public var split: UnsafeMutablePointer<UInt8>
    public var noteLen: UnsafeMutablePointer<Int32>
    public var noteVel: UnsafeMutablePointer<Float>
    public var prob: UnsafeMutablePointer<Float>
    public var ratchet: UnsafeMutablePointer<Int32>
    public var swing: UnsafeMutablePointer<Float>
    /// Свой звук шага (ключ; 0 — звук дорожки) и p-lock параметров голоса (биты VoiceParam и значения).
    public var sound: UnsafeMutablePointer<UInt64>
    public var lockMask: UnsafeMutablePointer<VoiceMask>
    public var lockVal: UnsafeMutablePointer<Float>
    /// P-lock общих FX (биты Params.fxIds и значения): действуют, пока шаг играет.
    public var fxMask: UnsafeMutablePointer<UInt32>
    public var fxVal: UnsafeMutablePointer<Float>
    /// P-lock LFO/ENV дорожки (биты Params.modIds и значения): действуют, пока шаг играет.
    public var modMask: UnsafeMutablePointer<UInt16>
    public var modVal: UnsafeMutablePointer<Float>
    /// Строки: видимых, повторы, строка старта, в конце — стоп, LOOP ROW.
    public var rows: Int = 1
    public var repeats: UnsafeMutablePointer<Int32>
    public var arrStart: Int = 0
    public var arrEndStop: Bool = false
    public var rowLoop: Bool = true
    /// Последовательности MIX и MST (Project.chanSeqs): длина и играющие страницы; p-lock громкостей на шагах MIX —
    /// биты дорожек и усиления (Params.volGain) по maxTracks на шаг.
    public static let chans = 2
    public var chanLength: UnsafeMutablePointer<Int32>
    public var chanFrom: UnsafeMutablePointer<Int32>
    public var chanTo: UnsafeMutablePointer<Int32>
    public var mixMask: UnsafeMutablePointer<UInt16>
    public var mixGain: UnsafeMutablePointer<Float>

    @inline(__always)
    private func ci(_ t: Int, _ k: Int) -> Int {
        return t * SeqData.slots + max(0, min(SeqData.slots - 1, k))
    }

    @inline(__always)
    public func filled(_ t: Int, _ k: Int) -> Bool {
        return k >= 0 && k < SeqData.slots && clipBlock[t * SeqData.slots + k] >= 0
    }

    /// Страницы клипа k дорожки t.
    @inline(__always)
    public func clip(_ t: Int, _ k: Int) -> (from: Int, to: Int) {
        let i = ci(t, k)
        return (Int(clipFrom[i]), Int(clipTo[i]))
    }

    @inline(__always)
    public func pageLen(_ t: Int, _ k: Int, _ p: Int, from: Int) -> Int {
        return SeqData.pageLen(Int(clipLength[ci(t, k)]), p, from: from)
    }

    @inline(__always)
    static func pageLen(_ length: Int, _ p: Int, from: Int) -> Int {
        let n = Params.stepsPerPage
        if length > from * n { return max(0, min(n, length - p * n)) }
        return n
    }

    @inline(__always)
    public func playLen(_ t: Int, slot k: Int) -> Int {
        let c = clip(t, k)
        return SeqData.playLen(Int(clipLength[ci(t, k)]), c.from, c.to)
    }

    @inline(__always)
    static func playLen(_ length: Int, _ from: Int, _ to: Int) -> Int {
        var n = 0
        var p = from
        while p <= to {
            n += pageLen(length, p, from: from)
            p += 1
        }
        return max(1, n)
    }

    @inline(__always)
    public func rate(_ t: Int, slot k: Int) -> Int {
        return Int(clipRate[ci(t, k)])
    }

    /// Проход клипа в тиках транспорта: ×2 — вдвое меньше (с округлением вверх), медленнее — в 2…16 раз больше.
    @inline(__always)
    public func tickLen(_ t: Int, slot k: Int) -> Int {
        return SeqData.passTicks(playLen(t, slot: k), rate(t, slot: k))
    }

    @inline(__always)
    public static func passTicks(_ len: Int, _ rate: Int) -> Int {
        if rate > 0 { return max(1, (len + 1) / 2) }
        return len << (-rate)
    }

    /// Шаг (p·16 + s) клипа k на позиции n прохода, по кругу.
    @inline(__always)
    public func playIndex(_ t: Int, slot k: Int, _ n: Int) -> Int {
        let c = clip(t, k)
        return SeqData.playIndex(Int(clipLength[ci(t, k)]), c.from, c.to, n)
    }

    /// Шаг последовательности MIX или MST (c — Project.mixSeq, mstSeq) на позиции n от PLAY, по кругу.
    @inline(__always)
    public func chanIndex(_ c: Int, _ n: Int) -> Int {
        return SeqData.playIndex(Int(chanLength[c]), Int(chanFrom[c]), Int(chanTo[c]), n)
    }

    @inline(__always)
    static func playIndex(_ length: Int, _ from: Int, _ to: Int, _ n: Int) -> Int {
        let total = playLen(length, from, to)
        var r = ((n % total) + total) % total
        var p = from
        while p <= to {
            let l = pageLen(length, p, from: from)
            if r < l { return p * Params.stepsPerPage + r }
            r -= l
            p += 1
        }
        return from * Params.stepsPerPage
    }

    /// Индекс шага pos клипа k в массивах шагов; −1 — ячейка пуста.
    @inline(__always)
    public func stepIndex(_ t: Int, slot k: Int, _ pos: Int) -> Int {
        let b = Int(clipBlock[ci(t, k)])
        if b < 0 || pos < 0 || pos >= SeqData.maxSteps { return -1 }
        return b * SeqData.maxSteps + pos
    }

    /// Для дорожки с активным клипом из проекта (тесты, интерфейс).
    public func playLen(_ t: Int) -> Int { return playLen(t, slot: Int(slot[t])) }
    public func playIndex(_ t: Int, _ n: Int) -> Int { return playIndex(t, slot: Int(slot[t]), n) }
}

public final class SeqSnapshot: @unchecked Sendable {
    public let data: SeqData
    /// Сколько снимков сейчас в памяти (создаются и освобождаются в основном потоке) — для проверки утечек.
    public static var liveCount = 0

    public init(_ project: Project) {
        let tracks = SeqData.maxTracks
        let cells = tracks * SeqData.slots
        let used = min(project.tracks.count, tracks)
        var blocks = 0
        for t in 0..<used { blocks += project.tracks[t].clips.filter { $0 != nil }.count }
        let steps = max(1, blocks) * SeqData.maxSteps
        var d = SeqData(
            stopped: .allocate(capacity: tracks), slot: .allocate(capacity: tracks),
            clipBlock: .allocate(capacity: cells), clipLength: .allocate(capacity: cells),
            clipFrom: .allocate(capacity: cells), clipTo: .allocate(capacity: cells), clipRate: .allocate(capacity: cells),
            on: .allocate(capacity: steps), len: .allocate(capacity: steps),
            noteCount: .allocate(capacity: steps), notes: .allocate(capacity: steps * SeqData.maxNotes),
            split: .allocate(capacity: steps), noteLen: .allocate(capacity: steps * SeqData.maxNotes),
            noteVel: .allocate(capacity: steps * SeqData.maxNotes),
            prob: .allocate(capacity: steps), ratchet: .allocate(capacity: steps), swing: .allocate(capacity: steps),
            sound: .allocate(capacity: steps), lockMask: .allocate(capacity: steps),
            lockVal: .allocate(capacity: steps * VoiceParam.count),
            fxMask: .allocate(capacity: steps), fxVal: .allocate(capacity: steps * Params.fxCount),
            modMask: .allocate(capacity: steps), modVal: .allocate(capacity: steps * Params.modCount),
            repeats: .allocate(capacity: SeqData.slots),
            chanLength: .allocate(capacity: SeqData.chans), chanFrom: .allocate(capacity: SeqData.chans),
            chanTo: .allocate(capacity: SeqData.chans), mixMask: .allocate(capacity: SeqData.maxSteps),
            mixGain: .allocate(capacity: SeqData.maxSteps * tracks)
        )
        d.stopped.initialize(repeating: 1, count: tracks)
        d.slot.initialize(repeating: 0, count: tracks)
        d.clipBlock.initialize(repeating: -1, count: cells)
        d.clipLength.initialize(repeating: Int32(Params.stepsPerPage), count: cells)
        d.clipFrom.initialize(repeating: 0, count: cells)
        d.clipTo.initialize(repeating: 0, count: cells)
        d.clipRate.initialize(repeating: 0, count: cells)
        d.on.initialize(repeating: 0, count: steps)
        d.len.initialize(repeating: 1, count: steps)
        d.noteCount.initialize(repeating: 0, count: steps)
        d.notes.initialize(repeating: 0, count: steps * SeqData.maxNotes)
        d.split.initialize(repeating: 0, count: steps)
        d.noteLen.initialize(repeating: 1, count: steps * SeqData.maxNotes)
        d.noteVel.initialize(repeating: -1, count: steps * SeqData.maxNotes)
        d.prob.initialize(repeating: 100, count: steps)
        d.ratchet.initialize(repeating: 0, count: steps)
        d.swing.initialize(repeating: 50, count: steps)
        d.sound.initialize(repeating: 0, count: steps)
        d.lockMask.initialize(repeating: 0, count: steps)
        d.lockVal.initialize(repeating: 0, count: steps * VoiceParam.count)
        d.fxMask.initialize(repeating: 0, count: steps)
        d.fxVal.initialize(repeating: 0, count: steps * Params.fxCount)
        d.modMask.initialize(repeating: 0, count: steps)
        d.modVal.initialize(repeating: 0, count: steps * Params.modCount)
        d.repeats.initialize(repeating: 1, count: SeqData.slots)
        d.rows = project.visibleRows
        d.arrStart = min(project.arrStart, d.rows - 1)
        d.arrEndStop = project.arrEndStop
        d.rowLoop = project.rowLoop
        for k in 0..<SeqData.slots { d.repeats[k] = Int32(project.scenes[k].repeats) }
        d.mixMask.initialize(repeating: 0, count: SeqData.maxSteps)
        d.mixGain.initialize(repeating: 0, count: SeqData.maxSteps * tracks)
        for c in 0..<SeqData.chans {
            let clip: Clip = project.chanSeqs[c].openClip
            d.chanLength[c] = Int32(clip.length)
            d.chanFrom[c] = Int32(clip.range.lowerBound)
            d.chanTo[c] = Int32(clip.range.upperBound)
        }
        SeqSnapshot.fillMix(&d, project.chanSeqs[Project.mixSeq].openClip)
        d.trackCount = used
        var block = 0
        for t in 0..<used {
            let track = project.tracks[t]
            d.stopped[t] = track.stopped || track.blank ? 1 : 0
            d.slot[t] = Int32(track.slot)
            for k in 0..<SeqData.slots {
                guard let c = track.clips[k] else { continue }
                SeqSnapshot.fill(&d, track, c, cell: t * SeqData.slots + k, block: block)
                block += 1
            }
        }
        data = d
        SeqSnapshot.liveCount += 1
    }

    /// Снимок паттернов тот же: шаги, клипы, строки и ручки Chance, Ratchet, Swing не менялись.
    public static func same(_ a: Project, _ b: Project) -> Bool {
        if a.tracks.count != b.tracks.count || a.chanSeqs != b.chanSeqs || a.scenes != b.scenes || a.rows != b.rows || a.arrStart != b.arrStart
            || a.arrEndStop != b.arrEndStop || a.rowLoop != b.rowLoop { return false }
        for (x, y) in zip(a.tracks, b.tracks) {
            if x.slot != y.slot || x.stopped != y.stopped || x.clips != y.clips { return false }
            for id in ["prob", "ratchet", "swing"] where x.params[id] != y.params[id] { return false }
        }
        return true
    }

    /// P-lock громкостей на шагах MIX: бит дорожки и усиление.
    private static func fillMix(_ d: inout SeqData, _ c: Clip) {
        for (p, page) in c.pages.enumerated() where p < Params.maxPages {
            for (s, step) in page.enumerated() where !step.locks.isEmpty {
                let i = p * Params.stepsPerPage + s
                var mask: UInt16 = 0
                for (id, v) in step.locks {
                    guard let t = Params.mixTrack(id) else { continue }
                    mask |= UInt16(1) << UInt16(t)
                    d.mixGain[i * SeqData.maxTracks + t] = Float(Params.volGain(v))
                }
                d.mixMask[i] = mask
            }
        }
    }

    /// Номер параметра по id (p-lock голоса, FX, LFO/ENV): шаг перебирает только свои p-lock, а не все параметры.
    private static let voiceIndex: [String: Int] = SeqSnapshot.indexMap(VoiceParam.ids)
    private static let fxIndex: [String: Int] = SeqSnapshot.indexMap(Params.fxIds)
    private static let modIndex: [String: Int] = SeqSnapshot.indexMap(Params.modIds)

    private static func indexMap(_ ids: [String]) -> [String: Int] {
        var m: [String: Int] = [:]
        for (k, id) in ids.enumerated() where m[id] == nil { m[id] = k }
        return m
    }

    /// Значение ручки дорожки без p-lock (как Track.value).
    private static func trackValue(_ track: Track, _ id: String) -> Double {
        return track.params[id] ?? Params.byId[id]?.def ?? 0
    }

    private static func fill(_ d: inout SeqData, _ track: Track, _ c: Clip, cell: Int, block: Int) {
        let r = c.range
        d.clipBlock[cell] = Int32(block)
        d.clipLength[cell] = Int32(c.length)
        d.clipFrom[cell] = Int32(r.lowerBound)
        d.clipTo[cell] = Int32(r.upperBound)
        d.clipRate[cell] = Int8(Swift.max(-4, Swift.min(1, c.speed)))
        // Ручки дорожки — один раз на клип; у шага — только его p-lock (S14: снимок строится в разы быстрее).
        let probT: Double = trackValue(track, "prob")
        let ratchetT: Double = trackValue(track, "ratchet")
        let swingT: Float = Float(track.params["swing"] ?? Params.swing.def)
        let maxNotes: Int = SeqData.maxNotes
        let vCount: Int = VoiceParam.count
        let fCount: Int = Params.fxCount
        let mCount: Int = Params.modCount
        for (p, page) in c.pages.enumerated() where p < Params.maxPages {
            for (s, step) in page.enumerated() {
                let i = block * SeqData.maxSteps + p * Params.stepsPerPage + s
                d.swing[i] = swingT
                let locks: [String: Double] = step.locks
                var prob: Double = probT
                var ratchet: Double = ratchetT
                if !locks.isEmpty {
                    var mask: VoiceMask = 0
                    var fm: UInt32 = 0
                    var mm: UInt16 = 0
                    for (id, v) in locks {
                        if id == "prob" { prob = v }
                        if id == "ratchet" { ratchet = v }
                        if let k = voiceIndex[id] {
                            mask |= VoiceMask(1) << VoiceMask(k)
                            d.lockVal[i * vCount + k] = Float(v)
                        }
                        if let k = fxIndex[id] {
                            fm |= UInt32(1) << UInt32(k)
                            d.fxVal[i * fCount + k] = Float(v)
                        }
                        if let k = modIndex[id] {
                            mm |= UInt16(1) << UInt16(k)
                            d.modVal[i * mCount + k] = Float(v)
                        }
                    }
                    d.lockMask[i] = mask
                    d.fxMask[i] = fm
                    d.modMask[i] = mm
                }
                d.prob[i] = Float(prob)
                d.ratchet[i] = Int32(ratchet.rounded())
                // Пустой шаг — значения по умолчанию уже стоят.
                if !step.on && step.notes.isEmpty && step.len == 1 && step.lens == nil && step.vels == nil && step.sound == nil {
                    continue
                }
                d.on[i] = step.on ? 1 : 0
                d.len[i] = Int32(step.len)
                let n = min(step.notes.count, maxNotes)
                d.noteCount[i] = UInt8(n)
                for k in 0..<n {
                    d.notes[i * maxNotes + k] = Int16(step.notes[k])
                    d.noteLen[i * maxNotes + k] = Int32(step.noteLen(k))
                    d.noteVel[i * maxNotes + k] = Float(step.noteVel(k) ?? -1)
                }
                d.split[i] = step.lens != nil || step.vels != nil ? 1 : 0
                if let snd = step.sound { d.sound[i] = SoundKey.hash(snd) }
            }
        }
    }

    deinit {
        SeqSnapshot.liveCount -= 1
        data.stopped.deallocate()
        data.slot.deallocate()
        data.clipBlock.deallocate()
        data.clipLength.deallocate()
        data.clipFrom.deallocate()
        data.clipTo.deallocate()
        data.clipRate.deallocate()
        data.on.deallocate()
        data.len.deallocate()
        data.noteCount.deallocate()
        data.notes.deallocate()
        data.split.deallocate()
        data.noteLen.deallocate()
        data.noteVel.deallocate()
        data.prob.deallocate()
        data.ratchet.deallocate()
        data.swing.deallocate()
        data.sound.deallocate()
        data.lockMask.deallocate()
        data.lockVal.deallocate()
        data.fxMask.deallocate()
        data.fxVal.deallocate()
        data.modMask.deallocate()
        data.modVal.deallocate()
        data.repeats.deallocate()
        data.chanLength.deallocate()
        data.chanFrom.deallocate()
        data.chanTo.deallocate()
        data.mixMask.deallocate()
        data.mixGain.deallocate()
    }
}
