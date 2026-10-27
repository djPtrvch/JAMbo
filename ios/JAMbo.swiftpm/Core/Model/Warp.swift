import Foundation

// WARP (варпинг сэмпла, docs/ai/sound-sampler.md): метки — место в сэмпле (доля длины) и его доля (в четвертях от
// начала сэмпла). Карта времени: между метками — линейно, до первой и после последней — по BPM файла. Действует только
// в Rate Stretch: голос идёт по долям в темпе проекта. Метки — у дорожки по ключу сэмпла, как маркеры нарезки.

/// Метка варпинга: доля длины сэмпла 0…1 и её доля (четверти от начала сэмпла).
public struct WarpMark: Codable, Equatable, Sendable {
    public var at: Double
    public var beat: Double

    public init(at: Double, beat: Double) {
        self.at = at
        self.beat = beat
    }
}

/// Варпинг сэмпла: свой BPM файла (nil — определённый сам) и метки по возрастанию at и beat.
public struct WarpInfo: Codable, Equatable, Sendable {
    public var bpm: Double? = nil
    public var marks: [WarpMark] = []

    public init(bpm: Double? = nil, marks: [WarpMark] = []) {
        self.bpm = bpm
        self.marks = marks
    }

    public var isEmpty: Bool { return bpm == nil && marks.isEmpty }
}

/// Карта времени сэмпла: отсчёты ↔ доли.
public struct WarpMap: Sendable {
    /// Метки: отсчёт и доля (по возрастанию обоих).
    public let pos: [Double]
    public let beats: [Double]
    /// Отсчётов на долю в темпе файла.
    public let perBeat: Double

    /// Самые узкие допуски: между метками не меньше 1/64 доли и 1 мс.
    public static let minBeat: Double = 1.0 / 64
    public static let minFrames: Double = 48
    public static let bpmMin: Double = 20
    public static let bpmMax: Double = 400
    /// BPM файла, если не определился (короткий звук) и не задан.
    public static let fallbackBpm: Double = 120

    public init(_ info: WarpInfo, frames: Int, bpm: Double) {
        pos = info.marks.map { $0.at * Double(frames) }
        beats = info.marks.map { $0.beat }
        perBeat = AudioCore.sampleRate * 60 / Swift.max(1, bpm)
    }

    /// BPM файла: свой, иначе определённый сам, иначе 120.
    public static func bpm(_ info: WarpInfo?, detected: Double) -> Double {
        if let b = info?.bpm { return b }
        return detected > 0 ? detected : fallbackBpm
    }

    /// Доля отсчёта p.
    public func beat(_ p: Double) -> Double {
        let n = pos.count
        if n == 0 { return p / perBeat }
        if p <= pos[0] { return beats[0] - (pos[0] - p) / perBeat }
        if p >= pos[n - 1] { return beats[n - 1] + (p - pos[n - 1]) / perBeat }
        var k = 1
        while pos[k] < p { k += 1 }
        let f: Double = (p - pos[k - 1]) / Swift.max(1e-9, pos[k] - pos[k - 1])
        return beats[k - 1] + f * (beats[k] - beats[k - 1])
    }

    /// Отсчёт доли b.
    public func position(_ b: Double) -> Double {
        let n = beats.count
        if n == 0 { return b * perBeat }
        if b <= beats[0] { return pos[0] - (beats[0] - b) * perBeat }
        if b >= beats[n - 1] { return pos[n - 1] + (b - beats[n - 1]) * perBeat }
        var k = 1
        while beats[k] < b { k += 1 }
        let f: Double = (b - beats[k - 1]) / Swift.max(1e-9, beats[k] - beats[k - 1])
        return pos[k - 1] + f * (pos[k] - pos[k - 1])
    }

    /// AUTO WARP: метка начала сэмпла — на долю 0 (начало проигрывания), метки на атаки (отсчёты) — каждая на
    /// ближайшую долю сетки grid (в четвертях); атака у самого начала или на той же доле, что и прежняя, — без метки.
    public static func auto(onsets: [Double], frames: Int, bpm: Double, grid: Double) -> [WarpMark] {
        let per: Double = AudioCore.sampleRate * 60 / Swift.max(1, bpm)
        let g: Double = Swift.max(1.0 / 64, grid)
        var out: [WarpMark] = [WarpMark(at: 0, beat: 0)]
        var last: Double = 0
        for p in onsets where p >= minFrames && p < Double(frames) {
            let b: Double = (p / per / g).rounded() * g
            if b <= last + minBeat / 2 { continue }
            out.append(WarpMark(at: p / Double(frames), beat: b))
            last = b
        }
        return out
    }
}

extension Track {
    public func warpInfo(_ key: String) -> WarpInfo {
        if key.isEmpty { return WarpInfo() }
        return warps[key] ?? WarpInfo()
    }

    mutating func putWarp(_ key: String, _ w: WarpInfo) {
        if key.isEmpty { return }
        warps[key] = w.isEmpty ? nil : w
    }

    /// BPM файла (nil — определённый сам), в пределах 20…400.
    public mutating func setWarpBpm(_ key: String, _ bpm: Double?) {
        var w = warpInfo(key)
        w.bpm = bpm.map { Swift.min(WarpMap.bpmMax, Swift.max(WarpMap.bpmMin, $0)) }
        putWarp(key, w)
    }

    /// Новая метка в отсчёте at (доля длины) — на её нынешней доле (звук не меняется); номер метки или nil (слишком
    /// близко к соседней).
    @discardableResult
    public mutating func addWarp(_ key: String, at: Double, frames: Int, detectedBpm: Double) -> Int? {
        var w = warpInfo(key)
        let a: Double = Swift.min(1, Swift.max(0, at))
        let map = WarpMap(w, frames: frames, bpm: WarpMap.bpm(w, detected: detectedBpm))
        let p: Double = a * Double(frames)
        for m in w.marks where Swift.abs(m.at * Double(frames) - p) < WarpMap.minFrames { return nil }
        let k: Int = w.marks.firstIndex { $0.at > a } ?? w.marks.count
        w.marks.insert(WarpMark(at: a, beat: map.beat(p)), at: k)
        putWarp(key, w)
        return k
    }

    /// Метка начала сэмпла (доля длины 0; нет — ставится на нынешней доле, звук не меняется); её номер — 0.
    @discardableResult
    public mutating func warpStart(_ key: String, frames: Int, detectedBpm: Double) -> Int {
        var w = warpInfo(key)
        if let f = w.marks.first, f.at * Double(frames) < WarpMap.minFrames { return 0 }
        let map = WarpMap(w, frames: frames, bpm: WarpMap.bpm(w, detected: detectedBpm))
        w.marks.insert(WarpMark(at: 0, beat: map.beat(0)), at: 0)
        putWarp(key, w)
        return 0
    }

    /// Доля метки idx — в пределах соседей (не ближе 1/64 доли).
    public mutating func moveWarp(_ key: String, _ idx: Int, beat: Double) {
        var w = warpInfo(key)
        guard idx >= 0, idx < w.marks.count else { return }
        let lo: Double = idx > 0 ? w.marks[idx - 1].beat + WarpMap.minBeat : -Double.greatestFiniteMagnitude
        let hi: Double = idx + 1 < w.marks.count ? w.marks[idx + 1].beat - WarpMap.minBeat : Double.greatestFiniteMagnitude
        if lo > hi { return }
        w.marks[idx].beat = Swift.min(hi, Swift.max(lo, beat))
        putWarp(key, w)
    }

    /// Верхний флажок: метка idx — в другое место сэмпла (at, доля длины) и на долю beat; место и доля — в пределах
    /// соседей (не ближе 1 мс и 1/64 доли).
    public mutating func placeWarp(_ key: String, _ idx: Int, at: Double, beat: Double, frames: Int) {
        var w = warpInfo(key)
        guard idx >= 0, idx < w.marks.count, frames > 0 else { return }
        let gap: Double = WarpMap.minFrames / Double(frames)
        let aLo: Double = idx > 0 ? w.marks[idx - 1].at + gap : 0
        let aHi: Double = idx + 1 < w.marks.count ? w.marks[idx + 1].at - gap : 1
        let bLo: Double = idx > 0 ? w.marks[idx - 1].beat + WarpMap.minBeat : -Double.greatestFiniteMagnitude
        let bHi: Double = idx + 1 < w.marks.count ? w.marks[idx + 1].beat - WarpMap.minBeat : Double.greatestFiniteMagnitude
        if aLo > aHi || bLo > bHi { return }
        w.marks[idx].at = Swift.min(aHi, Swift.max(aLo, at))
        w.marks[idx].beat = Swift.min(bHi, Swift.max(bLo, beat))
        putWarp(key, w)
    }

    public mutating func deleteWarp(_ key: String, _ idx: Int) {
        var w = warpInfo(key)
        guard idx >= 0, idx < w.marks.count else { return }
        w.marks.remove(at: idx)
        putWarp(key, w)
    }

    /// CLEAR WARP: все метки (свой BPM остаётся).
    public mutating func clearWarp(_ key: String) {
        var w = warpInfo(key)
        w.marks = []
        putWarp(key, w)
    }

    /// AUTO WARP: метки на атаки сэмпла по сетке grid (в четвертях) — вместо прежних.
    public mutating func autoWarp(_ key: String, onsets: [Double], frames: Int, detectedBpm: Double, grid: Double) {
        var w = warpInfo(key)
        w.marks = WarpMap.auto(onsets: onsets, frames: frames, bpm: WarpMap.bpm(w, detected: detectedBpm), grid: grid)
        putWarp(key, w)
    }
}
