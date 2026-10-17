import Foundation

// Снимок звука для колбэка: ручки дорожек (с ними звучащие ноты меняются сразу), громкость микшера, mute/solo,
// сэмплы дорожек (звук дорожки и папка) с маркерами нарезки. Строится в основном потоке после каждой правки
// (дёшево: без шагов); держит ссылки на SampleData, пока колбэк может их читать.

/// Параметры голоса в снимках: номер в массиве (p-lock шагов — по тем же номерам).
public enum VoiceParam {
    public static let ids = ["pitch", "start", "end", "level", "attack", "decay", "filter", "reso", "pan",
                             "harm", "timbre", "morph"]
    public static let count = 12
    public static let pitch = 0
    public static let start = 1
    public static let end = 2
    public static let level = 3
    public static let attack = 4
    public static let decay = 5
    public static let filter = 6
    public static let reso = 7
    public static let pan = 8
    public static let harm = 9
    public static let timbre = 10
    public static let morph = 11
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
    public var open: UnsafeMutablePointer<UInt8>
    public var sound: UnsafeMutablePointer<UInt64>
    /// Движок синта звука дорожки (−1 — сэмпл или нет звука).
    public var engine: UnsafeMutablePointer<Int8>
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
    /// Ссылки на сэмплы (колбэк их не трогает; освобождаются вместе со снимком в основном потоке).
    private let keep: [SampleData]
    public static var liveCount = 0

    /// samples — загруженные сэмплы по ключу; map, scale, root — ноты маркеров по порядку (SLICE NOTES).
    public init(_ project: Project, samples: [String: SampleData], map: SliceMap, octave: Int = 3) {
        let tracks = SoundData.maxTracks
        let entries = SoundData.maxEntries
        let slices = SoundData.maxSlices
        let pc = VoiceParam.count
        var d = SoundData(
            trackId: .allocate(capacity: tracks), params: .allocate(capacity: tracks * pc),
            gain: .allocate(capacity: tracks), open: .allocate(capacity: tracks), sound: .allocate(capacity: tracks),
            engine: .allocate(capacity: tracks),
            entryStart: .allocate(capacity: tracks + 1), entryCount: .allocate(capacity: tracks),
            eHash: .allocate(capacity: entries), eLeft: .allocate(capacity: entries), eRight: .allocate(capacity: entries),
            eFrames: .allocate(capacity: entries), eChannels: .allocate(capacity: entries),
            eSliceStart: .allocate(capacity: entries), eSliceCount: .allocate(capacity: entries),
            sliceAt: .allocate(capacity: slices), sliceNote: .allocate(capacity: slices)
        )
        d.trackId.initialize(repeating: -1, count: tracks)
        d.params.initialize(repeating: 0, count: tracks * pc)
        d.gain.initialize(repeating: 0, count: tracks)
        d.open.initialize(repeating: 0, count: tracks)
        d.sound.initialize(repeating: 0, count: tracks)
        d.engine.initialize(repeating: -1, count: tracks)
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
        for t in 0..<d.trackCount {
            let tr = project.tracks[t]
            d.trackId[t] = tr.id
            for (p, id) in VoiceParam.ids.enumerated() {
                d.params[t * pc + p] = Float(tr.params[id] ?? Params.byId[id]?.def ?? 0)
            }
            d.gain[t] = Float(Params.volGain(tr.vol))
            d.open[t] = project.audible(t) ? 1 : 0
            d.sound[t] = SoundKey.hash(tr.sample)
            d.engine[t] = Int8(SynthEngines.engine(tr.sample) ?? -1)
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
        SoundSnapshot.liveCount += 1
    }

    deinit {
        SoundSnapshot.liveCount -= 1
        data.trackId.deallocate()
        data.params.deallocate()
        data.gain.deallocate()
        data.open.deallocate()
        data.sound.deallocate()
        data.engine.deallocate()
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
    }
}
