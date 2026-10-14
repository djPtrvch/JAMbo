// История UNDO / REDO (как edit / beginGesture в state.ts веба): снимок проекта до действия.
// Проект — значение (struct), поэтому снимок — просто копия (copy-on-write: общие страницы не копируются).

public struct History<T: Equatable> {
    public static var limit: Int { return 200 }
    private var undoStack: [T] = []
    private var redoStack: [T] = []
    private var gestureDepth = 0
    private var gestureStart: T?

    public init() {}

    public var canUndo: Bool { return !undoStack.isEmpty }
    public var canRedo: Bool { return !redoStack.isEmpty }
    public var inGesture: Bool { return gestureDepth > 0 }

    /// Действие закончено: before — состояние до него, after — после. Внутри жеста — ничего (запись в конце жеста).
    public mutating func record(before: T, after: T) {
        if gestureDepth > 0 || before == after { return }
        push(before)
    }

    /// Непрерывный жест (поворот ручки, протягивание): одна запись на весь жест.
    public mutating func beginGesture(_ current: T) {
        if gestureDepth == 0 { gestureStart = current }
        gestureDepth += 1
    }

    public mutating func endGesture(_ current: T) {
        if gestureDepth == 0 { return }
        gestureDepth -= 1
        if gestureDepth == 0, let start = gestureStart {
            gestureStart = nil
            if start != current { push(start) }
        }
    }

    /// UNDO: вернуть прежнее состояние (current уходит в REDO); nil — нечего отменять.
    public mutating func undo(_ current: T) -> T? {
        guard let prev = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return prev
    }

    public mutating func redo(_ current: T) -> T? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    /// Новый проект — история сбрасывается.
    public mutating func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
        gestureDepth = 0
        gestureStart = nil
    }

    private mutating func push(_ state: T) {
        redoStack.removeAll()
        undoStack.append(state)
        if undoStack.count > History.limit { undoStack.removeFirst() }
    }
}
