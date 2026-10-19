import Foundation

// Снимок звука для колбэка: ручки дорожек (с ними звучащие ноты меняются сразу), громкость микшера, mute/solo,
// сэмплы дорожек (звук дорожки и папка) с маркерами нарезки. Строится в основном потоке после каждой правки
// (дёшево: без шагов); держит ссылки на SampleData, пока колбэк может их читать.

/// Параметры голоса в снимках: номер в массиве (p-lock шагов — по тем же номерам).
public enum VoiceParam {
    public static let ids = ["pitch", "start", "end", "level", "attack", "decay", "filter", "reso", "pan",
                             "harm", "timbre", "morph", "reverb", "delay", "drive"]
    public static let count = 15
    public static let pitch = 0
    public static let start = 1
    public static let end = 2
    public static let level = 3
    public static let attack = 4
    public static let decay = 5
    public static let filter = 6
    public static let reso = 7
    public static let pan = 8
    /// Синт: ручки 1.1–1.3 (0…100).
    public static let harm = 9
    public static let timbre = 10
    public static let morph = 11
    /// Посылы Reverb, Delay, Drive (0…100; посыл голоса — после Pan).
    public static let reverb = 12
    public static let delay = 13
    public static let drive = 14
}

public struct SoundData {
    public static let maxTracks = Params.maxTracks
    public static let maxEntries = 1024
    public static let maxSlices = 8192

    public var trackCount: Int = 0
    /// Переход MIX (S10): у дорожки t второй звук — для клипа PREV (звук старой дорожки), на номере t + maxTracks
    /// в таблицах звука (ручки, звук, сэмплы, таблица, MOD, Sidechain, EQ дорожки). Какой звук действует — по клипу,
    /// который сейчас играет в колбэке (slotRef — Launcher.slot): ячейка PREV — второй.
    public var alt: UnsafeMutablePointer<UInt8>
    public var slotRef: UnsafeMutablePointer<Int>
    /// Сэмплов в таблице entries (оба звука).
    public var entryTotal: Int = 0
    /// На дорожку: постоянный номер (перестановка — голоса гаснут), ручки голоса, громкость, слышна ли (mute/solo),
    /// звук дорожки (ключ; 0 — нет), сэмплы дорожки — отрезок таблицы entries.
    public var trackId: UnsafeMutablePointer<Int>
    public var params: UnsafeMutablePointer<Float>
    public var gain: UnsafeMutablePointer<Float>
    /// Подстройка громкости дорожки (LEVEL RELATIVE; при ABSOLUTE — 1), множитель: и к громкости, и к p-lock
    /// громкости MIX.
    public var trim: UnsafeMutablePointer<Float>
    public var open: UnsafeMutablePointer<UInt8>
    public var sound: UnsafeMutablePointer<UInt64>
    public var entryStart: UnsafeMutablePointer<Int32>
    public var entryCount: UnsafeMutablePointer<Int32>
    /// Сэмплы: ключ, данные, кадров, каналов, маркеры нарезки (отрезок таблицы slices; доля длины и нота).
    public var eHash: UnsafeMutablePointer<UInt64>
    public var eLeft: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>
    public var eRight: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>
    public var eFrames: UnsafeMutablePointer<Int>
    public var eChannels: UnsafeMutablePointer<Int32>
    public var eSliceStart: UnsafeMutablePointer<Int32>
    public var eSliceCount: UnsafeMutablePointer<Int32>
    public var sliceAt: UnsafeMutablePointer<Double>
    public var sliceNote: UnsafeMutablePointer<Int32>
    /// Таблица WTABLE дорожки (указатели WtTable; кадров 0 — таблица ещё не готова, WTABLE молчит, как в вебе).
    var tableRef: UnsafeMutablePointer<WtRef>
    /// Общие FX (Params.fxIds, без p-lock), глубина Sidechain дорожки (0…100), переключатели SETTINGS → SIDECHAIN
    /// (посылы Reverb, Delay, Drive: 1 — приглушаются).
    public var fx: UnsafeMutablePointer<Float>
    public var scAmount: UnsafeMutablePointer<Float>
    public var scSend: UnsafeMutablePointer<Float>
    /// SETTINGS → AUDIO ENGINE → MUTE TAILS.
    public var muteTails: Bool = false
    /// MOD: параметры LFO/ENV дорожки (Params.modIds), назначения на цели (ModTarget: источник 0 — нет, 1–4; степень;
    /// шкала ручки по звуку дорожки), есть ли у дорожки назначения; назначения на FX (Params.fxIds) и дорожка-источник.
    public var mod: UnsafeMutablePointer<Float>
    public var asSrc: UnsafeMutablePointer<Int8>
    public var asAmt: UnsafeMutablePointer<Float>
    public var scale: UnsafeMutablePointer<ParamScale>
    public var asAny: UnsafeMutablePointer<UInt8>
    public var fxSrc: UnsafeMutablePointer<Int8>
    public var fxAmt: UnsafeMutablePointer<Float>
    public var fxTrack: UnsafeMutablePointer<Int32>
    public var fxScale: UnsafeMutablePointer<ParamScale>
    /// Мастер: значения в порядке MasterChain.Index (bypass — 1, RELEASE AUTO — отдельным флагом).
    public var master: UnsafeMutablePointer<Double>
    /// EQ каналов (EqSpec.fill): дорожки 0…maxTracks−1, мастер — EqSpec.masterChannel; по EqSpec.stride значений.
    public var eq: UnsafeMutablePointer<Double>
    /// Порядок дорожек в микшере (S7b): источник динамической полосы EQ — раньше дорожки, которая его слушает
    /// (выход — в этом же блоке, как в вебе); в кольце источников одна дорожка слышит прошлый блок.
    public var eqOrder: UnsafeMutablePointer<Int>

    public static let prevSlot = Params.patternSlots - 1

    /// Номер звука дорожки t в таблицах звука: t или t + maxTracks (играет клип PREV со вторым звуком).
    @inline(__always)
    public func s(_ t: Int) -> Int {
        return alt[t] != 0 && slotRef[t] == SoundData.prevSlot ? t + SoundData.maxTracks : t
    }

    /// Параметры EQ дорожки t (второй звук — за каналами EqSpec.channels).
    @inline(__always)
    public func eqParams(_ t: Int) -> UnsafeMutablePointer<Double> {
        let u = s(t)
        let ch: Int = u == t ? t : EqSpec.channels + t
        return eq + ch * EqSpec.stride
    }

    @inline(__always)
    public func param(_ t: Int, _ p: Int) -> Float {
        return params[s(t) * VoiceParam.count + p]
    }

    /// Сэмпл дорожки t с ключом hash (−1 — нет).
    @inline(__always)
    public func entry(_ t: Int, _ hash: UInt64) -> Int {
        if hash == 0 || t < 0 || t >= trackCount { return -1 }
        let u = s(t)
        let a = Int(entryStart[u])
        let n = Int(entryCount[u])
        var k = 0
        while k < n {
            if eHash[a + k] == hash { return a + k }
            k += 1
        }
        return -1
    }

    /// Сэмпл с ключом hash на любой дорожке (предпрослушка).
    @inline(__always)
    public func anyEntry(_ hash: UInt64) -> Int {
        var t = 0
        while t < trackCount {
            let e = entry(t, hash)
            if e >= 0 { return e }
            t += 1
        }
        return -1
    }

    /// Есть ли в снимке буфер data (голос, который его читает, может звучать дальше).
    @inline(__always)
    public func holds(_ data: UnsafeMutablePointer<Float>) -> Bool {
        let n = entryTotal
        var k = 0
        while k < n {
            if eLeft[k] == data { return true }
            k += 1
        }
        return false
    }
}

public final class SoundSnapshot: @unchecked Sendable {
    public let data: SoundData
    /// Ссылки на сэмплы и таблицы (колбэк их не трогает; освобождаются вместе со снимком в основном потоке).
    private let keep: [SampleData]
    private let keepTables: [WtTable]
    /// Свой буфер slotRef (снимок без ядра — в тестах).
    private let ownSlots: UnsafeMutablePointer<Int>?
    public static var liveCount = 0

    /// samples — загруженные сэмплы по ключу; map, scale, root — ноты маркеров по порядку (SLICE NOTES).
    /// tables — готовые таблицы WTABLE по ключу (Track.table). slots — активные ячейки дорожек в колбэке
    /// (Launcher.slot; nil — свой буфер, все на первой ячейке).
    public init(_ project: Project, samples: [String: SampleData], map: SliceMap, octave: Int = 3,
                tables: [String: WtTable] = [:], scSends: SidechainSends = SidechainSends(), muteTails: Bool = false,
                levelRelative: Bool = true, slots: UnsafeMutablePointer<Int>? = nil) {
        let tracks = SoundData.maxTracks
        let tracks2 = tracks * 2
        var own: UnsafeMutablePointer<Int>? = nil
        if slots == nil {
            let b = UnsafeMutablePointer<Int>.allocate(capacity: tracks)
            b.initialize(repeating: 0, count: tracks)
            own = b
        }
        let slotRef: UnsafeMutablePointer<Int> = slots ?? own!
        let entries = SoundData.maxEntries
        let slices = SoundData.maxSlices
        let pc = VoiceParam.count
        var d = SoundData(
            alt: .allocate(capacity: tracks), slotRef: slotRef,
            trackId: .allocate(capacity: tracks), params: .allocate(capacity: tracks2 * pc),
            gain: .allocate(capacity: tracks), trim: .allocate(capacity: tracks), open: .allocate(capacity: tracks), sound: .allocate(capacity: tracks2),
            entryStart: .allocate(capacity: tracks2), entryCount: .allocate(capacity: tracks2),
            eHash: .allocate(capacity: entries), eLeft: .allocate(capacity: entries), eRight: .allocate(capacity: entries),
            eFrames: .allocate(capacity: entries), eChannels: .allocate(capacity: entries),
            eSliceStart: .allocate(capacity: entries), eSliceCount: .allocate(capacity: entries),
            sliceAt: .allocate(capacity: slices), sliceNote: .allocate(capacity: slices),
            tableRef: .allocate(capacity: tracks2),
            fx: .allocate(capacity: Params.fxCount), scAmount: .allocate(capacity: tracks2), scSend: .allocate(capacity: 3),
            mod: .allocate(capacity: tracks2 * Params.modCount), asSrc: .allocate(capacity: tracks2 * ModTarget.count),
            asAmt: .allocate(capacity: tracks2 * ModTarget.count), scale: .allocate(capacity: tracks2 * ModTarget.count),
            asAny: .allocate(capacity: tracks2), fxSrc: .allocate(capacity: Params.fxCount),
            fxAmt: .allocate(capacity: Params.fxCount), fxTrack: .allocate(capacity: Params.fxCount),
            fxScale: .allocate(capacity: Params.fxCount),
            master: .allocate(capacity: MasterChain.Index.count),
            eq: .allocate(capacity: (EqSpec.channels + tracks) * EqSpec.stride),
            eqOrder: .allocate(capacity: tracks)
        )
        MasterChain.fill(d.master, project)
        // Звук дорожки для остальных клипов (side 0) и для клипа PREV (side 1; нет — второго звука нет).
        let n0 = Swift.min(project.tracks.count, tracks)
        var sounds: [TrackSound?] = []
        for side in 0..<2 {
            for t in 0..<tracks { sounds.append(t < n0 ? project.tracks[t].sound(prev: side == 1) : nil) }
        }
        d.alt.initialize(repeating: 0, count: tracks)
        for t in 0..<n0 where project.prevRow && sounds[tracks + t] != nil { d.alt[t] = 1 }
        for ch in 0..<(EqSpec.channels + tracks) {
            var eq: Eq? = nil
            if ch == EqSpec.masterChannel {
                eq = project.masterEq
            } else if ch < tracks {
                eq = sounds[ch]?.eq
            } else if ch >= EqSpec.channels {
                eq = sounds[tracks + ch - EqSpec.channels]?.eq
            }
            EqSpec.fill(d.eq + ch * EqSpec.stride, eq)
        }
        d.mod.initialize(repeating: 0, count: tracks2 * Params.modCount)
        d.asSrc.initialize(repeating: 0, count: tracks2 * ModTarget.count)
        d.asAmt.initialize(repeating: 0, count: tracks2 * ModTarget.count)
        d.scale.initialize(repeating: ParamScale(), count: tracks2 * ModTarget.count)
        d.asAny.initialize(repeating: 0, count: tracks2)
        for (k, id) in Params.fxIds.enumerated() {
            let a = project.fxAssigns[id]
            (d.fxSrc + k).initialize(to: Int8(a?.lfo ?? 0))
            (d.fxAmt + k).initialize(to: Float(a?.amount ?? 0))
            (d.fxTrack + k).initialize(to: Int32(a?.track ?? 0))
            (d.fxScale + k).initialize(to: Params.byId[id].map { ParamScale($0) } ?? ParamScale())
        }
        for (k, id) in Params.fxIds.enumerated() {
            (d.fx + k).initialize(to: Float(project.fx[id] ?? Params.byId[id]?.def ?? 0))
        }
        d.scAmount.initialize(repeating: 0, count: tracks2)
        d.scSend[0] = scSends.rev ? 1 : 0
        d.scSend[1] = scSends.dly ? 1 : 0
        d.scSend[2] = scSends.drv ? 1 : 0
        d.muteTails = muteTails
        d.tableRef.initialize(repeating: WtRef(), count: tracks2)
        var keepTables: [WtTable] = []
        d.trackId.initialize(repeating: -1, count: tracks)
        d.params.initialize(repeating: 0, count: tracks2 * pc)
        d.gain.initialize(repeating: 0, count: tracks)
        d.trim.initialize(repeating: 1, count: tracks)
        d.open.initialize(repeating: 0, count: tracks)
        d.sound.initialize(repeating: 0, count: tracks2)
        d.entryStart.initialize(repeating: 0, count: tracks2)
        d.entryCount.initialize(repeating: 0, count: tracks2)
        d.eHash.initialize(repeating: 0, count: entries)
        d.eLeft.initialize(repeating: nil, count: entries)
        d.eRight.initialize(repeating: nil, count: entries)
        d.eFrames.initialize(repeating: 0, count: entries)
        d.eChannels.initialize(repeating: 1, count: entries)
        d.eSliceStart.initialize(repeating: 0, count: entries)
        d.eSliceCount.initialize(repeating: 0, count: entries)
        d.sliceAt.initialize(repeating: 0, count: slices)
        d.sliceNote.initialize(repeating: 0, count: slices)
        var keep: [SampleData] = []
        var e = 0
        var sl = 0
        d.trackCount = Swift.min(project.tracks.count, tracks)
        let order: [Int] = EqSpec.mixOrder(project, d.trackCount)
        for t in 0..<tracks { d.eqOrder[t] = t < order.count ? order[t] : t }
        for t in 0..<d.trackCount {
            let tr = project.tracks[t]
            d.trackId[t] = tr.id
            // LEVEL ABSOLUTE — громкость ровно как в MIX: подстройка не действует.
            let tg: Float = levelRelative ? Float(Params.volGain(tr.trim)) : 1
            d.trim[t] = tg
            d.gain[t] = Float(Params.volGain(tr.vol)) * tg
            d.open[t] = project.audible(t) ? 1 : 0
        }
        for u in 0..<tracks2 {
            let t = u % tracks
            guard t < d.trackCount, let snd = sounds[u] else { continue }
            if u >= tracks && d.alt[t] == 0 { continue }
            for (p, id) in VoiceParam.ids.enumerated() {
                d.params[u * pc + p] = Float(snd.params[id] ?? Params.byId[id]?.def ?? 0)
            }
            d.scAmount[u] = Float(snd.params["sidechain"] ?? 0)
            for (k, id) in Params.modIds.enumerated() {
                d.mod[u * Params.modCount + k] = Float(snd.params[id] ?? Params.byId[id]?.def ?? 0)
            }
            // Шкалы целей — по сетке звука дорожки (у синта свои пределы и ступени).
            var grid: [String: ParamDef] = [:]
            for p in Params.grid(sound: snd.sample) { grid[p.id] = p }
            for (j, id) in ModTarget.ids.enumerated() {
                let i = u * ModTarget.count + j
                if let def = grid[id] ?? Params.byId[id] { d.scale[i] = ParamScale(def) }
                if let a = snd.assigns[id] {
                    d.asSrc[i] = Int8(a.lfo)
                    d.asAmt[i] = Float(a.amount)
                    d.asAny[u] = 1
                }
            }
            d.sound[u] = SoundKey.hash(snd.sample)
            if let wt = tables[snd.table] {
                keepTables.append(wt)
                d.tableRef[u] = WtRef(frames: wt.frames, sizes: UnsafePointer(wt.sizes), data: UnsafePointer(wt.data))
            }
            d.entryStart[u] = Int32(e)
            var keys = snd.folder.items
            if !snd.sample.isEmpty && !keys.contains(snd.sample) { keys.append(snd.sample) }
            for key in keys where e < entries {
                guard let s = samples[key] else { continue }
                keep.append(s)
                d.eHash[e] = SoundKey.hash(key)
                d.eLeft[e] = s.left
                d.eRight[e] = s.right
                d.eFrames[e] = s.frames
                d.eChannels[e] = Int32(s.channels)
                let marks: [SliceMark] = key.isEmpty ? [] : (snd.slices[key] ?? [])
                let notes = Slices.notes(marks, map: map, scale: project.scale, root: project.root, octave: octave)
                d.eSliceStart[e] = Int32(sl)
                var n = 0
                for (k, m) in marks.enumerated() where sl + n < slices {
                    d.sliceAt[sl + n] = m.at
                    d.sliceNote[sl + n] = Int32(notes[k])
                    n += 1
                }
                d.eSliceCount[e] = Int32(n)
                sl += n
                e += 1
            }
            d.entryCount[u] = Int32(e) - d.entryStart[u]
        }
        d.entryTotal = e
        data = d
        self.keep = keep
        self.keepTables = keepTables
        ownSlots = own
        SoundSnapshot.liveCount += 1
    }

    deinit {
        SoundSnapshot.liveCount -= 1
        ownSlots?.deallocate()
        data.alt.deallocate()
        data.trackId.deallocate()
        data.params.deallocate()
        data.gain.deallocate()
        data.trim.deallocate()
        data.open.deallocate()
        data.sound.deallocate()
        data.entryStart.deallocate()
        data.entryCount.deallocate()
        data.eHash.deallocate()
        data.eLeft.deallocate()
        data.eRight.deallocate()
        data.eFrames.deallocate()
        data.eChannels.deallocate()
        data.eSliceStart.deallocate()
        data.eSliceCount.deallocate()
        data.sliceAt.deallocate()
        data.sliceNote.deallocate()
        data.tableRef.deallocate()
        data.fx.deallocate()
        data.scAmount.deallocate()
        data.scSend.deallocate()
        data.mod.deallocate()
        data.asSrc.deallocate()
        data.asAmt.deallocate()
        data.scale.deallocate()
        data.asAny.deallocate()
        data.fxSrc.deallocate()
        data.fxAmt.deallocate()
        data.fxTrack.deallocate()
        data.fxScale.deallocate()
        data.master.deallocate()
        data.eq.deallocate()
        data.eqOrder.deallocate()
    }
}
