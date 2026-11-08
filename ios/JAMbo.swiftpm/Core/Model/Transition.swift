// Переход MIX между проектами (S10, как switchWithTransition, unshiftDoc, docForSave в state.ts веба).
// Активные клипы старого проекта (с тригами) ложатся в нижнюю строку сетки (PREV) вместе со звуком старой
// дорожки; строки нового проекта — на своих местах, его последняя строка временно скрыта. Общие настройки
// (темп, громкости, мастер, EQ мастера) ведёт кроссфейдер от старого проекта к новому.

/// Звук дорожки (TrackData веба без паттернов): переезжает с клипом PREV. Громкости — у микшера (кроссфейдер).
public struct TrackSound: Codable, Equatable, Sendable {
    /// Поля — «в коробке» (8.11, объём сборки: копия и сравнение звука — одна ссылка, а не каждое поле); в файле — те
    /// же ключи, что и прежде (Fields пишется на место TrackSound).
    struct Fields: Codable, Equatable, Sendable {
        var sample: String
        var params: [String: Double]
        var folder: Folder
        var slices: [String: [SliceMark]]
        /// Метки варпинга (nil — нет; в прежних файлах поля нет).
        var warps: [String: WarpInfo]? = nil
        var table: String
        /// Сэмпл GRANULAR (nil — нет; в прежних файлах поля нет).
        var grain: String? = nil
        var assigns: [String: ModAssign]
        var eq: Eq
        /// Громкость микшера (dB), с которой звучит клип со своим звуком (клип PREV при MIX без кроссфейдера — громкость
        /// старой дорожки; решение пользователя); nil — громкость дорожки. В звук дорожки не переносится.
        var vol: Double? = nil
    }
    var box: [Fields]

    public init(sample: String, params: [String: Double], folder: Folder, slices: [String: [SliceMark]],
                warps: [String: WarpInfo]? = nil, table: String, grain: String? = nil, assigns: [String: ModAssign],
                eq: Eq, vol: Double? = nil) {
        box = [Fields(sample: sample, params: params, folder: folder, slices: slices, warps: warps, table: table,
                      grain: grain, assigns: assigns, eq: eq, vol: vol)]
    }

    public init(from decoder: Decoder) throws { box = [try Fields(from: decoder)] }
    public func encode(to encoder: Encoder) throws { try box[0].encode(to: encoder) }

    public var sample: String {
        get { return box[0].sample }
        set { box[0].sample = newValue }
    }

    public var params: [String: Double] {
        get { return box[0].params }
        set { box[0].params = newValue }
    }

    public var folder: Folder {
        get { return box[0].folder }
        set { box[0].folder = newValue }
    }

    public var slices: [String: [SliceMark]] {
        get { return box[0].slices }
        set { box[0].slices = newValue }
    }

    public var warps: [String: WarpInfo]? {
        get { return box[0].warps }
        set { box[0].warps = newValue }
    }

    public var table: String {
        get { return box[0].table }
        set { box[0].table = newValue }
    }

    public var grain: String? {
        get { return box[0].grain }
        set { box[0].grain = newValue }
    }

    public var assigns: [String: ModAssign] {
        get { return box[0].assigns }
        set { box[0].assigns = newValue }
    }

    public var eq: Eq {
        get { return box[0].eq }
        set { box[0].eq = newValue }
    }

    public var vol: Double? {
        get { return box[0].vol }
        set { box[0].vol = newValue }
    }
}

extension Track {
    /// Звук дорожки (поля, которые сейчас действуют).
    public var sound: TrackSound {
        get {
            return TrackSound(sample: sample, params: params, folder: folder, slices: slices,
                              warps: warps.isEmpty ? nil : warps, table: table, grain: grain.isEmpty ? nil : grain,
                              assigns: assigns, eq: eq)
        }
        set {
            sample = newValue.sample
            params = newValue.params
            folder = newValue.folder
            slices = newValue.slices
            warps = newValue.warps ?? [:]
            table = newValue.table
            grain = newValue.grain ?? ""
            assigns = newValue.assigns
            eq = newValue.eq
        }
    }

    /// Звук по активной ячейке (без смены ячейки): у клипа со своим звуком (src) — он (свой — в home), у клипа без
    /// своего — звук дорожки. Пока home есть, звук дорожки — звук активного клипа (правки идут в него).
    public mutating func settleSound() {
        let src: TrackSound? = clipFilled(slot) ? clips[slot]!.src : nil
        if let s = src, home == nil {
            home = sound
            sound = s
        } else if src == nil, let own = home {
            sound = own
            home = nil
        }
    }

    /// Громкость (dB), с которой звучит клип k: своя у клипа со своим звуком (TrackSound.vol), иначе — дорожки.
    public func vol(slot k: Int) -> Double {
        if clipFilled(k), let v = clips[k]!.src?.vol { return v }
        return vol
    }

    /// Звук, которым звучит клип k (для снимка звука: колбэк мог уже переключить клип, а дорожка в модели — нет).
    public func sound(slot k: Int) -> TrackSound {
        if k == slot { return sound }
        if clipFilled(k), let s = clips[k]!.src { return s }
        return home ?? sound
    }
}

/// Общие настройки, которые ведёт кроссфейдер: темп, громкости дорожек (микшер, LEVEL), выход, мастер, EQ мастера.
public struct MixGlobals: Equatable, Sendable {
    public var bpm: Double
    public var vols: [Double]
    public var trims: [Double]
    public var master: [String: Double]
    public var satBypass: Bool
    public var cmpBypass: Bool
    public var clipBypass: Bool
    public var limBypass: Bool
    public var outVol: Double
    public var masterEq: Eq

    public init(_ p: Project) {
        bpm = p.bpm
        vols = p.tracks.map { $0.vol }
        trims = p.tracks.map { $0.trim }
        master = p.master
        satBypass = p.satBypass
        cmpBypass = p.cmpBypass
        clipBypass = p.clipBypass
        limBypass = p.limBypass
        outVol = p.outVol
        masterEq = p.masterEq
    }

    /// Громкость выхода, модули мастера (параметры, BYPASS) и EQ мастера — из other (CROSSFADER OFF во время игры).
    public mutating func holdMaster(_ other: MixGlobals) {
        outVol = other.outVol
        master = other.master
        satBypass = other.satBypass
        cmpBypass = other.cmpBypass
        clipBypass = other.clipBypass
        limBypass = other.limBypass
        masterEq = other.masterEq
    }

    /// Записать в проект (дорожкам сверх списка — их значения остаются).
    public func apply(to p: inout Project) {
        p.bpm = bpm
        for i in p.tracks.indices where i < vols.count {
            p.tracks[i].vol = vols[i]
            p.tracks[i].trim = trims[i]
        }
        p.master = master
        p.satBypass = satBypass
        p.cmpBypass = cmpBypass
        p.clipBypass = clipBypass
        p.limBypass = limBypass
        p.outVol = outVol
        p.masterEq = masterEq
    }
}

/// Состояние перехода: скрытая последняя строка нового проекта (по id дорожки), гамма, нота и FX нового проекта,
/// общие настройки старого (from) и нового (to) проекта, положение кроссфейдера (0 — OLD, 1 — NEW).
public struct MixTransition: Equatable, Sendable {
    /// Поля — «в коробке» (8.11, объём сборки: переход в наблюдаемом свойстве модели копируется и сравнивается
    /// одной ссылкой).
    struct Fields: Equatable, Sendable {
        var hidden: [Int: Clip] = [:]
        var origSlot: [Int: Int] = [:]
        var hiddenScene: SceneRow = SceneRow()
        /// Дорожек у нового проекта (лишние дорожки старого убираются в конце перехода).
        var count: Int = 0
        var scale: Int = 0
        var root: Int = 0
        var fx: [String: Double] = [:]
        var from: MixGlobals
        var to: MixGlobals
        var pos: Double = 0
        /// Дорожки, клипы которых опустились в PREV, и строки, откуда (для анимации).
        var moves: [MixMove] = []
    }
    var box: [Fields]

    public init(from: MixGlobals, to: MixGlobals) {
        box = [Fields(from: from, to: to)]
    }

    public var hidden: [Int: Clip] {
        get { return box[0].hidden }
        set { box[0].hidden = newValue }
    }

    public var origSlot: [Int: Int] {
        get { return box[0].origSlot }
        set { box[0].origSlot = newValue }
    }

    public var hiddenScene: SceneRow {
        get { return box[0].hiddenScene }
        set { box[0].hiddenScene = newValue }
    }

    public var count: Int {
        get { return box[0].count }
        set { box[0].count = newValue }
    }

    public var scale: Int {
        get { return box[0].scale }
        set { box[0].scale = newValue }
    }

    public var root: Int {
        get { return box[0].root }
        set { box[0].root = newValue }
    }

    public var fx: [String: Double] {
        get { return box[0].fx }
        set { box[0].fx = newValue }
    }

    public var from: MixGlobals {
        get { return box[0].from }
        set { box[0].from = newValue }
    }

    public var to: MixGlobals {
        get { return box[0].to }
        set { box[0].to = newValue }
    }

    public var pos: Double {
        get { return box[0].pos }
        set { box[0].pos = newValue }
    }

    public var moves: [MixMove] {
        get { return box[0].moves }
        set { box[0].moves = newValue }
    }
}

/// Клип дорожки track опустился в PREV из строки from.
public struct MixMove: Equatable, Sendable {
    public let track: Int
    public let from: Int
}

extension Project {
    static let prevIndex = Params.patternSlots - 1

    /// MIX: проект next открывается переходом от self. playing — идёт игра; leaving[i] — дорожка ждёт остановки.
    /// Играть продолжают только звучавшие дорожки (с тригами, не остановленные, не ждущие остановки).
    /// Mute и solo — старого проекта; гамма, нота и FX — старого лидера; общие настройки — старые (кроссфейдер у OLD).
    /// clipVolumes (MIX без кроссфейдера) — клип PREV звучит с громкостью своей старой дорожки.
    public func mixed(into nextIn: Project, playing: Bool, leaving: [Bool], clipVolumes: Bool = false) -> (Project, MixTransition) {
        let last = Project.prevIndex
        var next = nextIn
        // Новый проект без перехода: его прежний PREV не нужен (MIX во время перехода — от текущего вида).
        next.prevRow = false
        let count = next.tracks.count
        while next.tracks.count < tracks.count { next.tracks.append(Track(index: next.tracks.count)) }
        var tr = MixTransition(from: MixGlobals(self), to: MixGlobals(next))
        tr.hiddenScene = next.scenes[last]
        tr.count = count
        tr.scale = next.scale
        tr.root = next.root
        tr.fx = next.fx
        for i in next.tracks.indices {
            var t = next.tracks[i]
            if let h = t.clips[last] { tr.hidden[t.id] = h }
            tr.origSlot[t.id] = t.slot
            var prev: Clip? = nil
            var sounding = false
            if i < tracks.count, let c = tracks[i].clips[tracks[i].slot],
               c.pages.contains(where: { $0.contains { $0.on } }) {
                var pc = c
                // Звук, которым клип звучал (у клипа со своим звуком — его).
                pc.src = tracks[i].sound
                if clipVolumes { pc.src?.vol = tracks[i].vol(slot: tracks[i].slot) }
                prev = pc
                let wait: Bool = i < leaving.count && leaving[i]
                sounding = playing && !tracks[i].stopped && !wait
                tr.moves.append(MixMove(track: i, from: tracks[i].slot))
            }
            t.clips[last] = prev
            if prev != nil {
                t.open = last
                t.activate(last)
            }
            t.stopped = !sounding
            if i < tracks.count {
                t.mute = tracks[i].mute
                t.solo = tracks[i].solo
            }
            next.tracks[i] = t
        }
        next.scale = scale
        next.root = root
        next.fx = fx
        next.scenes[last] = SceneRow(name: "PREV", repeats: 1)
        next.prevRow = true
        next.fillRows()
        tr.from.apply(to: &next)
        return (next, tr)
    }

    /// Строка PREV уступает место последней строке нового проекта: дорожки, игравшие PREV, останавливаются
    /// (активная — прежняя ячейка), свой звук возвращается; лишние дорожки старого проекта без тригов — с конца.
    public mutating func endMix(_ tr: MixTransition) {
        let last = Project.prevIndex
        for i in tracks.indices {
            var t = tracks[i]
            let fromPrev = t.slot == last
            if fromPrev {
                var k = tr.origSlot[t.id] ?? 0
                if !t.clipFilled(k) || k == last { k = t.clips.prefix(last).firstIndex { $0 != nil } ?? 0 }
                t.activate(k)
                t.stopped = true
            }
            t.clips[last] = tr.hidden[t.id]
            // Звук — по активной ячейке: у импортированного клипа — свой, иначе — звук дорожки.
            t.settleSound()
            if t.open == last && t.clips[last] == nil { t.open = t.slot }
            tracks[i] = t
        }
        scenes[last] = tr.hiddenScene
        prevRow = false
        var n = tracks.count
        let keep = Swift.max(tr.count, Params.trackCount)
        while n > keep && !tracks[n - 1].clips.contains(where: { c in
            c?.pages.contains(where: { $0.contains { $0.on } }) ?? false
        }) {
            n -= 1
        }
        if n < tracks.count { tracks.removeLast(tracks.count - n) }
        fillRows()
    }

    /// Для сохранения (docForSave веба): без строки PREV, с общими настройками, гаммой, нотой и FX нового проекта.
    /// Темп старого проекта в новый не пишется.
    public func forSave(_ tr: MixTransition?) -> Project {
        guard let tr = tr else { return self }
        var p = self
        p.endMix(tr)
        tr.to.apply(to: &p)
        p.scale = tr.scale
        p.root = tr.root
        p.fx = tr.fx
        return p
    }

    /// Гамма и нота клипа k дорожки t; без своих — проекта.
    public func clipKey(_ t: Int, slot k: Int) -> (scale: Int, root: Int) {
        guard t >= 0 && t < tracks.count, tracks[t].clipFilled(k), let c = tracks[t].clips[k] else { return (scale, root) }
        return (c.scale ?? scale, c.root ?? root)
    }

    /// Из строки PREV что-то играет (запуск, ждущий в колбэке, проверяет вызывающий).
    public var prevPlaying: Bool {
        if !prevRow { return false }
        let last = Project.prevIndex
        return tracks.contains { $0.slot == last && !$0.stopped && $0.clipFilled(last) }
    }
}
