import Foundation

// Разбор маппингов (S13b, как midi.ts веба): условия, самое точное из действующих, правка маппинга цели
// (источник ведёт только к одной цели), разбор значения по типу управления. Без CoreMIDI и UI — проверяется тестами.

/// Что на экране сейчас (для условий): открыта ли сетка паттернов и какую страницу показывает сетка ручек.
public struct MidiContext: Equatable, Sendable {
    public var clipOpen: Bool
    public var page: MidiPage
    /// Выбранная дорожка (место глобальных маппингов ручек).
    public var track: Int

    public init(clipOpen: Bool, page: MidiPage, track: Int = 0) {
        self.clipOpen = clipOpen
        self.page = page
        self.track = track
    }

    /// Действующие условия, от самого точного: сетка паттернов, страница ручек, global.
    public var conds: [String] {
        var out: [String] = []
        if clipOpen { out.append("clip") }
        out.append("page:" + page.rawValue)
        out.append("global")
        return out
    }
}

/// Значение сообщения по маппингу: кнопка (нажата / отпущена), значение в диапазоне (ABSOLUTE) или шаг энкодера.
public enum MidiInput: Equatable, Sendable {
    case button(Bool)
    case value(Double)
    case step(Double)
}

extension MidiSettings {
    /// Маппинг цели: в закреплённом окном MIDI MAP условии (pinned), иначе в самом точном действующем.
    public func mapping(for t: MidiTarget, _ ctx: MidiContext, pinned: String? = nil) -> MidiMapping? {
        let conds: [String] = pinned.map { [$0] } ?? ctx.conds
        for c in conds {
            if let m = mappings.first(where: { $0.target == t && $0.condKey == c && $0.fits(ctx) }) { return m }
        }
        return nil
    }

    /// Маппинги источника с этого входа в самом точном действующем условии. mapped — источник назначен хоть где-то
    /// (тогда нота не играет, даже если условие сейчас не действует — как в вебе).
    public func resolve(_ src: MidiSource, input: Int32, _ ctx: MidiContext) -> (mapped: Bool, active: [MidiMapping]) {
        let all: [MidiMapping] = mappings.filter { $0.src == src && ($0.input == nil || $0.input == input) }
        if all.isEmpty { return (false, []) }
        for c in ctx.conds {
            let maps: [MidiMapping] = all.filter { $0.condKey == c }
            if !maps.isEmpty { return (true, maps) }
        }
        return (true, [])
    }

    /// Условие нового маппинга: ячейки и строки сетки — Clip launcher (или GLOBAL, закреплённое окном); кроссфейдер —
    /// Global; закреплённое окном; в сетке паттернов — Clip launcher, иначе Global.
    func defaultCond(_ t: MidiTarget, _ ctx: MidiContext, pinned: String?) -> (MidiCond, MidiPage) {
        if t.isClip { return (pinned == "global" ? .global : .clip, ctx.page) }
        if t == MidiTarget.crossfader && pinned == nil { return (.global, ctx.page) }
        if let p = pinned {
            if p.hasPrefix("page:"), let page = MidiPage(rawValue: String(p.dropFirst(5))) { return (.page, page) }
            if let c = MidiCond(rawValue: p) { return (c, ctx.page) }
        }
        return (ctx.clipOpen ? .clip : .global, ctx.page)
    }

    /// Первый свободный CC на канале 1 (новый маппинг из окна MIDI MAP).
    public func freeSource() -> MidiSource {
        var n: Int = 0
        while n < 128 {
            let src = MidiSource(type: .cc, ch: 0, num: n)
            if !mappings.contains(where: { $0.src == src }) { return src }
            n += 1
        }
        return MidiSource(type: .cc, ch: 0, num: 0)
    }

    /// Черновик маппинга цели без маппинга (окно MIDI MAP до первой правки).
    public func draft(_ t: MidiTarget, continuous: Bool, _ ctx: MidiContext, pinned: String? = nil) -> MidiMapping {
        var m = MidiMapping(src: freeSource(), target: t, continuous: continuous)
        let (c, p) = defaultCond(t, ctx, pinned: pinned)
        m.cond = c
        m.page = p
        return m
    }

    /// Изменить маппинг цели (LEARN, окно MIDI MAP): правка поверх нынешнего маппинга (или черновика). У цели в одном
    /// условии один маппинг; источник, занятый другой целью в том же условии, переходит к этой. Возвращает ключ
    /// условия получившегося маппинга.
    @discardableResult
    public mutating func update(_ t: MidiTarget, continuous: Bool, _ ctx: MidiContext, pinned: String? = nil,
                                _ change: (inout MidiMapping) -> Void) -> String {
        let cur: MidiMapping? = mapping(for: t, ctx, pinned: pinned)
        var m: MidiMapping = cur ?? draft(t, continuous: continuous, ctx, pinned: pinned)
        change(&m)
        m.target = t
        if t.isClip && m.cond == .page { m.cond = .clip }
        m.fixPlace(ctx, force: false)
        let curIndex: Int? = cur.flatMap { c in mappings.firstIndex(where: { $0 == c }) }
        var kept: [MidiMapping] = []
        var i: Int = 0
        while i < mappings.count {
            let x: MidiMapping = mappings[i]
            let mine: Bool = x.target == t && (i == curIndex || (x.condKey == m.condKey && x.place == m.place))
            if !mine && !x.clashes(m) { kept.append(x) }
            i += 1
        }
        kept.append(m)
        mappings = kept
        return m.condKey
    }

    /// LEARN: движение контроллера назначает источник цели (тип управления, диапазон и порт остаются; у новой —
    /// по виду сообщения: CC на непрерывную цель — ABSOLUTE, иначе — кнопка).
    public mutating func learn(_ t: MidiTarget, src: MidiSource, input: Int32, continuous: Bool, _ ctx: MidiContext,
                               pinned: String? = nil) {
        let had: Bool = mapping(for: t, ctx, pinned: pinned) != nil
        update(t, continuous: continuous, ctx, pinned: pinned) { m in
            m.src = src
            m.input = input
            if !had { m.control = continuous && src.type == .cc ? .abs : .momentary }
            // LEARN на экране — параметр, который сейчас показывает ручка.
            m.fixPlace(ctx, force: true)
        }
    }

    /// Снять маппинг цели в нынешнем контексте (UNMAP).
    public mutating func unmap(_ t: MidiTarget, _ ctx: MidiContext, pinned: String? = nil) {
        guard let cur = mapping(for: t, ctx, pinned: pinned), let i = mappings.firstIndex(of: cur) else { return }
        mappings.remove(at: i)
    }
}

/// Состояния TOGGLE по целям (включено ли) — живут, пока не изменились маппинги.
public struct MidiToggles: Sendable {
    private var on: [String: Bool] = [:]

    public init() {}

    public mutating func reset() {
        on = [:]
    }

    /// Значение сообщения. isCc — CC (иначе нота); value — CC или сила ноты; press — нажатие (CC ≥ 64, Note On).
    /// Кнопочные типы (и ноты): MOMENTARY и LATCH — нажата / отпущена (у LATCH это состояние переключателя
    /// контроллера); TOGGLE — нажатие переключает, отпускание не важно (nil).
    public mutating func input(_ m: MidiMapping, isCc: Bool, value: Int, press: Bool) -> MidiInput? {
        let button: Bool = m.control == .momentary || m.control == .toggle || m.control == .latch || !isCc
        if !button {
            if m.control == .abs { return .value(m.value(at: Double(value) / 127)) }
            return .step(m.relStep(value))
        }
        if m.control != .toggle { return .button(press) }
        if !press { return nil }
        let k: String = m.target.key
        let state: Bool = !(on[k] ?? false)
        on[k] = state
        return .button(state)
    }
}

extension MidiInput {
    /// На кнопке: нажатия и отпускания по порядку. ABSOLUTE — как MOMENTARY (press — CC ≥ 64); RELATIVE — шаг вверх
    /// жмёт и отпускает.
    public func presses(press: Bool) -> [Bool] {
        switch self {
        case .button(let s): return [s]
        case .value: return [press]
        case .step(let d): return d > 0 ? [true, false] : []
        }
    }

    /// На непрерывной цели (ручка, темп): новое значение 0–1 из нынешнего cur. Кнопочные типы — края диапазона.
    public func knobValue(_ m: MidiMapping, cur: Double) -> Double {
        switch self {
        case .button(let s): return s ? m.max : m.min
        case .value(let v): return v
        case .step(let d): return m.clamp(cur + d)
        }
    }
}
