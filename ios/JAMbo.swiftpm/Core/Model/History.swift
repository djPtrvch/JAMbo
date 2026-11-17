// История UNDO / REDO (как edit / beginGesture в state.ts веба): снимок проекта до действия.
// Проект — значение (struct), поэтому снимок — просто копия (copy-on-write: общие страницы не копируются).

public struct History<T: Equatable> {
    public static var limit: Int { return 200 }
    private var undoStack: [T] = []
    private var redoStack: [T] = []
    /// Место правки (17.11): где она сделана — окно, дорожка, страница; хранит интерфейс (тип — его), Core не знает.
    /// У записи UNDO — место правки, которую она отменяет; у записи REDO — место, где правку вернуть.
    private var undoPlaces: [Any?] = []
    private var redoPlaces: [Any?] = []
    /// Место записи, которую только что отменили или вернули (undo / redo); nil — неизвестно.
    public private(set) var lastPlace: Any? = nil
    private var gestureDepth = 0
    private var gestureStart: T?
    /// Растёт при каждом изменении стеков (новая запись, UNDO, REDO) — дубль записи с REC продолжается,
    /// пока между нотами не было других действий.
    public private(set) var serial: Int = 0

    public init() {}

    public var canUndo: Bool { return !undoStack.isEmpty }
    public var canRedo: Bool { return !redoStack.isEmpty }

    /// Действие закончено: before — состояние до него, after — после. Внутри жеста — ничего (запись в конце жеста).
    public mutating func record(before: T, after: T, place: Any? = nil) {
        if gestureDepth > 0 || before == after { return }
        push(before, place)
    }

    /// Правка вне истории (MORPH, 8.11) посреди жеста: та же правка — и в начальное состояние жеста, чтобы конец жеста
    /// её не записал.
    public mutating func shiftGesture(_ change: (inout T) -> Void) {
        guard gestureDepth > 0, var s = gestureStart else { return }
        change(&s)
        gestureStart = s
    }

    /// Непрерывный жест (поворот ручки, протягивание): одна запись на весь жест.
    public mutating func beginGesture(_ current: T) {
        if gestureDepth == 0 { gestureStart = current }
        gestureDepth += 1
    }

    public mutating func endGesture(_ current: T, place: Any? = nil) {
        if gestureDepth == 0 { return }
        gestureDepth -= 1
        if gestureDepth == 0, let start = gestureStart {
            gestureStart = nil
            if start != current { push(start, place) }
        }
    }

    /// UNDO: вернуть прежнее состояние (current уходит в REDO); nil — нечего отменять.
    public mutating func undo(_ current: T) -> T? {
        guard let prev = undoStack.popLast() else { return nil }
        let place: Any? = undoPlaces.popLast() ?? nil
        serial += 1
        redoStack.append(current)
        redoPlaces.append(place)
        lastPlace = place
        return prev
    }

    public mutating func redo(_ current: T) -> T? {
        guard let next = redoStack.popLast() else { return nil }
        let place: Any? = redoPlaces.popLast() ?? nil
        serial += 1
        undoStack.append(current)
        undoPlaces.append(place)
        lastPlace = place
        return next
    }

    /// Новый проект — история сбрасывается.
    public mutating func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
        undoPlaces.removeAll()
        redoPlaces.removeAll()
        lastPlace = nil
        gestureDepth = 0
        gestureStart = nil
    }

    private mutating func push(_ state: T, _ place: Any?) {
        serial += 1
        redoStack.removeAll()
        redoPlaces.removeAll()
        undoStack.append(state)
        undoPlaces.append(place)
        if undoStack.count > History.limit {
            undoStack.removeFirst()
            undoPlaces.removeFirst()
        }
    }
}
