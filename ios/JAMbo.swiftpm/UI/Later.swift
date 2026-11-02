import Foundation

/// Отменяемый отложенный вызов (Later.run, Later.every): cancel — как Task.cancel, вызов уже не придёт.
final class LaterTask {
    private(set) var cancelled: Bool = false

    func cancel() {
        cancelled = true
    }
}

/// Отложенные вызовы на главном потоке — вместо Task { sleep … }: асинхронная функция даёт компилятору много кода
/// (части приостановки на каждое тело; S14, сборка в Playgrounds упирается в объём кода). Поведение то же.
enum Later {
    /// f через seconds (если задачу не отменили).
    @discardableResult
    static func run(_ seconds: Double, _ f: @escaping () -> Void) -> LaterTask {
        let t = LaterTask()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if !t.cancelled { f() }
        }
        return t
    }

    /// f каждые interval (первый раз — через first, без него — через interval), пока f возвращает true и задачу не
    /// отменили.
    @discardableResult
    static func every(_ interval: Double, first: Double? = nil, _ f: @escaping () -> Bool) -> LaterTask {
        let t = LaterTask()
        tick(t, first ?? interval, interval, f)
        return t
    }

    private static func tick(_ t: LaterTask, _ wait: Double, _ interval: Double, _ f: @escaping () -> Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            if t.cancelled || !f() { return }
            tick(t, interval, interval, f)
        }
    }
}
