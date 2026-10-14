import Foundation

// Звук дорожки: папка звуков (стрелки ◀ ▶), свой звук шага, маркеры нарезки сэмпла (как state.ts веба:
// addItems, applyItem, stepFolder, setStepSound, sliceMarks, sliceNotes). Пресеты синта в папке — S3.

/// Папка дорожки: загруженные сэмплы (ключи) и номер звучащего (−1 — нет).
public struct Folder: Codable, Equatable, Sendable {
    public var items: [String] = []
    public var index: Int = -1

    public init(items: [String] = [], index: Int = -1) {
        self.items = items
        self.index = index
    }
}

/// Маркер нарезки: доля длины сэмпла 0…1 и нота (nil — по порядку, SLICE NOTES).
public struct SliceMark: Codable, Equatable, Sendable {
    public var at: Double
    public var note: Int?

    public init(at: Double, note: Int? = nil) {
        self.at = at
        self.note = note
    }
}

/// SETTINGS → SAMPLER → SLICE NOTES: ноты маркеров по порядку — хроматически или по гамме.
public enum SliceMap: String, Codable, Sendable {
    case chromatic
    case scale
}

extension Track {
    /// Добавить сэмплы в папку (уже лежащий не повторяется); номер первого (−1 — пусто).
    @discardableResult
    public mutating func addItems(_ keys: [String]) -> Int {
        var first = -1
        for key in keys {
            var k = folder.items.firstIndex(of: key) ?? -1
            if k < 0 {
                folder.items.append(key)
                k = folder.items.count - 1
            }
            if first < 0 { first = k }
        }
        if first >= 0 { folder.index = first }
        return first
    }

    /// Загруженные файлы — в папку, первый звучит на дорожке.
    public mutating func addSamples(_ keys: [String]) {
        let at = addItems(keys)
        if at >= 0 { sample = folder.items[at] }
    }

    /// Файлы для зажатых шагов: в папку, не меняя звук дорожки.
    public mutating func addSamplesQuiet(_ keys: [String]) {
        let index = folder.index
        addItems(keys)
        if index >= 0 { folder.index = index }
    }

    /// Стрелки: соседний звук папки на дорожку.
    public mutating func stepFolder(_ dir: Int) {
        let n = folder.items.count
        if n == 0 { return }
        if folder.index < 0 {
            folder.index = dir > 0 ? 0 : n - 1
        } else {
            folder.index = ((folder.index + dir) % n + n) % n
        }
        sample = folder.items[folder.index]
    }

    /// Номер звука шага в папке или −1.
    public func stepItemIndex(_ s: Step) -> Int {
        guard let snd = s.sound else { return -1 }
        return folder.items.firstIndex(of: snd) ?? -1
    }

    /// Сменился звук шага — p-lock прежнего пресета звука убираются.
    static func dropSoundLocks(_ s: inout Step) {
        for k in s.soundLocks ?? [] { s.locks[k] = nil }
        s.soundLocks = nil
    }

    /// Зажат шаг + стрелка: шагу — соседний звук папки (от звука шага, а если его нет — от звука дорожки).
    public mutating func stepFolderOnSteps(_ indices: [Int], _ dir: Int) {
        let n = folder.items.count
        if n == 0 { return }
        for i in indices {
            guard let s = step(i) else { continue }
            let cur = stepItemIndex(s)
            let base = cur >= 0 ? cur : folder.index
            let k = base < 0 ? (dir > 0 ? 0 : n - 1) : ((base + dir) % n + n) % n
            let key = folder.items[k]
            withStep(i) { st in
                Track.dropSoundLocks(&st)
                st.sound = key
            }
        }
    }

    /// Свой звук шагов (nil — снова звук дорожки).
    public mutating func setStepSound(_ indices: [Int], _ key: String?) {
        for i in indices where step(i) != nil {
            withStep(i) { st in
                Track.dropSoundLocks(&st)
                st.sound = key
            }
        }
    }

    /// Позиция для подписи между стрелками: номер (с 1) и всего; held — зажатый шаг (его звук).
    public func folderPos(held: Int?) -> (Int, Int) {
        if let h = held, let s = step(h), s.sound != nil { return (stepItemIndex(s) + 1, folder.items.count) }
        return (folder.index + 1, folder.items.count)
    }

    /// CLEAR в редакторе: сэмпл убирается с дорожки и из её папки (дорожка без звука).
    public mutating func clearSample() {
        if let k = folder.items.firstIndex(of: sample) {
            folder.items.remove(at: k)
            folder.index = -1
        }
        sample = ""
    }

    /// Отредактированная копия (TRIM, NORMALIZE, MONO) или запись встаёт на место прежнего сэмпла (и в папке).
    public mutating func replaceSample(_ old: String, _ new: String) {
        if let k = folder.items.firstIndex(of: old) {
            folder.items[k] = new
            folder.index = k
        } else {
            addItems([new])
        }
        sample = new
    }

    // MARK: — маркеры нарезки

    public func sliceMarks(_ key: String) -> [SliceMark] {
        if key.isEmpty { return [] }
        return slices[key] ?? []
    }

    mutating func putMarks(_ key: String, _ m: [SliceMark]) {
        slices[key] = m.isEmpty ? nil : m
    }

    /// Новый маркер на доле at (нота — по порядку).
    public mutating func addSlice(_ key: String, at: Double) {
        var m = sliceMarks(key)
        m.append(SliceMark(at: Swift.min(1, Swift.max(0, at))))
        m.sort { $0.at < $1.at }
        putMarks(key, m)
    }

    public mutating func deleteSlice(_ key: String, _ idx: Int) {
        var m = sliceMarks(key)
        guard idx >= 0 && idx < m.count else { return }
        m.remove(at: idx)
        putMarks(key, m)
    }

    /// Сдвинуть маркер между соседями (gap — наименьший зазор, доля).
    public mutating func moveSlice(_ key: String, _ idx: Int, at: Double, gap: Double) {
        var m = sliceMarks(key)
        guard idx >= 0 && idx < m.count else { return }
        let lo: Double = idx > 0 ? m[idx - 1].at + gap : 0
        let hi: Double = idx < m.count - 1 ? m[idx + 1].at - gap : 1
        m[idx].at = Swift.min(hi, Swift.max(lo, at))
        putMarks(key, m)
    }

    /// Назначить маркеру ноту; false — нота уже у другого маркера.
    public mutating func setSliceNote(_ key: String, _ idx: Int, note: Int, notes: [Int]) -> Bool {
        var m = sliceMarks(key)
        guard idx >= 0 && idx < m.count else { return false }
        for (k, n) in notes.enumerated() where k != idx && n == note { return false }
        m[idx].note = note
        putMarks(key, m)
        return true
    }
}

public enum Slices {
    /// Нота по порядку маркера idx: CHROMATIC — C3, C#3…; SCALE — ступени гаммы от корневой ноты в 3-й октаве.
    public static func note(_ idx: Int, map: SliceMap, scale: Int, root: Int) -> Int {
        if map != .scale { return Params.sampleRoot + idx }
        let steps = Scales.all[Swift.max(0, Swift.min(scale, Scales.all.count - 1))].steps
        return Params.sampleRoot + root + 12 * (idx / steps.count) + steps[idx % steps.count]
    }

    /// Ноты маркеров: назначенная — как есть; остальные — по порядку, занятая нота пропускается.
    public static func notes(_ m: [SliceMark], map: SliceMap, scale: Int, root: Int) -> [Int] {
        var taken = Set<Int>()
        for v in m { if let n = v.note { taken.insert(n) } }
        var j = 0
        var out: [Int] = []
        for v in m {
            if let n = v.note {
                j += 1
                out.append(n)
                continue
            }
            while taken.contains(note(j, map: map, scale: scale, root: root)) { j += 1 }
            out.append(note(j, map: map, scale: scale, root: root))
            j += 1
        }
        return out
    }
}
