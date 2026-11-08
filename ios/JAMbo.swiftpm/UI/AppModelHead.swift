import UIKit

/// HEAD TRACK (8.11, docs/ai/fx-eq.md): отслеживание головы в строке MONITOR окна коррекции. Тап — вкл./выкл. (не
/// сохраняется, при запуске выкл.), SHIFT + тап — CENTER. Трекер работает, пока HEAD TRACK включён и у пункта SPACE есть
/// пространство; экран при этом не гаснет (без экрана камера не видит лица).
extension AppModel {
    /// Кнопка доступна: пространство есть, камера TrueDepth и доступ к ней объявлен.
    var headEnabled: Bool { return roomOn && HeadTracker.available }

    func headTap() {
        if shiftHeld {
            headTracker?.center()
            return
        }
        guard headEnabled else { return }
        headOn.toggle()
        syncHead()
    }

    func syncHead() {
        let run: Bool = headOn && headEnabled
        if run {
            if headTracker != nil { return }
            let t = HeadTracker(stage: audio.core.monitor.room)
            t.onFace = { [weak self] v in self?.headFace = v }
            headTracker = t
            UIApplication.shared.isIdleTimerDisabled = true
            t.start()
        } else if let t = headTracker {
            t.stop()
            headTracker = nil
            headFace = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
