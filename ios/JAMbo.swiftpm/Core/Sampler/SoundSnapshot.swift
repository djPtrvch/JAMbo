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
    /// На дорожку: постоянный номер (перестановка — голоса гаснут), ручки голоса, громкость, слышна ли (mute/solo),
    /// звук дорожки (ключ; 0 — нет), сэмплы дорожки — отрезок таблицы entries.
    public var trackId: UnsafeMutablePointer<Int>
    public var params: UnsafeMutablePointer<Float>
    public var gain: UnsafeMutablePointer<Float>
    /// Подстройка громкости дорожки (LEVEL RELATIVE), множитель: и к громкости, и к p-lock громкости MIX.
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

    @inline(__always)
    public func param(_ t: Int, _ p: Int) -> Float {
        return params[t * VoiceParam.count + p]
    }

    /// Сэмпл дорожки t с ключом hash (−1 — нет).
    @inline(__always)
    public func entry(_ t: Int, _ hash: UInt64) -> Int {
        if hash == 0 || t < 0 || t >= trackCount { return -1 }
        let a = Int(entryStart[t])
        let n = Int(entryCount[t])
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
        let n = Int(entryStart[trackCount])
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
    public static var liveCount = 0

    /// samples — загруженные сэмплы по ключу; map, scale, root — ноты маркеров по порядку (SLICE NOTES).
    /// tables — готовые таблицы WTABLE по ключу (Track.table).
    public init(_ project: Project, samples: [String: SampleData], map: SliceMap, octave: Int = 3,
                tables: [String: WtTable] = [:], scSends: SidechainSends = SidechainSends(), muteTails: Bool = false) {
        let tracks = SoundData.maxTracks
        let entries = SoundData.maxEntries
        let slices = SoundData.maxSlices
        let pc = VoiceParam.count
        var d = SoundData(
            trackId: .allocate(capacity: tracks), params: .allocate(capacity: tracks * pc),
            gain: .allocate(capacity: tracks), trim: .allocate(capacity: tracks), open: .allocate(capacity: tracks), sound: .allocate(capacity: tracks),
            entryStart: .allocate(capacity: tracks + 1), entryCount: .allocate(capacity: tracks),
            eHash: .allocate(capacity: entries), eLeft: .allocate(capacity: entries), eRight: .allocate(capacity: entries),
            eFrames: .allocate(capacity: entries), eChannels: .allocate(capacity: entries),
            eSliceStart: .allocate(capacity: entries), eSliceCount: .allocate(capacity: entries),
            sliceAt: .allocate(capacity: slices), sliceNote: .allocate(capacity: slices),
            tableRef: .allocate(capacity: tracks),
            fx: .allocate(capacity: Params.fxCount), scAmount: .allocate(capacity: tracks), scSend: .allocate(capacity: 3),
            mod: .allocate(capacity: tracks * Params.modCount), asSrc: .allocate(capacity: tracks * ModTarget.count),
            asAmt: .allocate(capacity: tracks * ModTarget.count), scale: .allocate(capacity: tracks * ModTarget.count),
            asAny: .allocate(capacity: tracks), fxSrc: .allocate(capacity: Params.fxCount),
            fxAmt: .allocate(capacity: Params.fxCount), fxTrack: .allocate(capacity: Params.fxCount),
            fxScale: .allocate(capacity: Params.fxCount),
            master: .allocate(capacity: MasterChain.Index.count),
            eq: .allocate(capacity: EqSpec.channels * EqSpec.stride),
            eqOrder: .allocate(capacity: tracks)
        )
        MasterChain.fill(d.master, project)
        for ch in 0..<EqSpec.channels {
            let eq: Eq? = ch == EqSpec.masterChannel ? project.masterEq : ch < project.tracks.count ? project.tracks[ch].eq : nil
            EqSpec.fill(d.eq + ch * EqSpec.stride, eq)
        }
        d.mod.initialize(repeating: 0, count: tracks * Params.modCount)
        d.asSrc.initialize(repeating: 0, count: tracks * ModTarget.count)
        d.asAmt.initialize(repeating: 0, count: tracks * ModTarget.count)
        d.scale.initialize(repeating: ParamScale(), count: tracks * ModTarget.count)
        d.asAny.initialize(repeating: 0, count: tracks)
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
        d.scAmount.initialize(repeating: 0, count: tracks)
        d.scSend[0] = scSends.rev ? 1 : 0
        d.scSend[1] = scSends.dly ? 1 : 0
        d.scSend[2] = scSends.drv ? 1 : 0
        d.muteTails = muteTails
        d.tableRef.initialize(repeating: WtRef(), count: tracks)
        var keepTables: [WtTable] = []
        d.trackId.initialize(repeating: -1, count: tracks)
        d.params.initialize(repeating: 0, count: tracks * pc)
        d.gain.initialize(repeating: 0, count: tracks)
        d.trim.initialize(repeating: 1, count: tracks)
        d.open.initialize(repeating: 0, count: tracks)
        d.sound.initialize(repeating: 0, count: tracks)
        d.entryStart.initialize(repeating: 0, count: tracks + 1)
        d.entryCount.initialize(repeating: 0, count: tracks)
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
            for (p, id) in VoiceParam.ids.enumerated() {
                d.params[t * pc + p] = Float(tr.params[id] ?? Params.byId[id]?.def ?? 0)
            }
            let tg: Float = Float(Params.volGain(tr.trim))
            d.trim[t] = tg
            d.gain[t] = Float(Params.volGain(tr.vol)) * tg
            d.scAmount[t] = Float(tr.params["sidechain"] ?? 0)
            for (k, id) in Params.modIds.enumerated() {
                d.mod[t * Params.modCount + k] = Float(tr.params[id] ?? Params.byId[id]?.def ?? 0)
            }
            // Шкалы целей — по сетке звука дорожки (у синта свои пределы и ступени).
            var grid: [String: ParamDef] = [:]
            for p in Params.grid(sound: tr.sample) { grid[p.id] = p }
            for (j, id) in ModTarget.ids.enumerated() {
                let i = t * ModTarget.count + j
                if let def = grid[id] ?? Params.byId[id] { d.scale[i] = ParamScale(def) }
                if let a = tr.assigns[id] {
                    d.asSrc[i] = Int8(a.lfo)
                    d.asAmt[i] = Float(a.amount)
                    d.asAny[t] = 1
                }
            }
            d.open[t] = project.audible(t) ? 1 : 0
            d.sound[t] = SoundKey.hash(tr.sample)
            if let wt = tables[tr.table] {
                keepTables.append(wt)
                d.tableRef[t] = WtRef(frames: wt.frames, sizes: UnsafePointer(wt.sizes), data: UnsafePointer(wt.data))
            }
            d.entryStart[t] = Int32(e)
            var keys = tr.folder.items
            if !tr.sample.isEmpty && !keys.contains(tr.sample) { keys.append(tr.sample) }
            for key in keys where e < entries {
                guard let s = samples[key] else { continue }
                keep.append(s)
                d.eHash[e] = SoundKey.hash(key)
                d.eLeft[e] = s.left
                d.eRight[e] = s.right
                d.eFrames[e] = s.frames
                d.eChannels[e] = Int32(s.channels)
                let marks = tr.sliceMarks(key)
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
            d.entryCount[t] = Int32(e) - d.entryStart[t]
        }
        d.entryStart[d.trackCount] = Int32(e)
        data = d
        self.keep = keep
        self.keepTables = keepTables
        SoundSnapshot.liveCount += 1
    }

    deinit {
        SoundSnapshot.liveCount -= 1
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
