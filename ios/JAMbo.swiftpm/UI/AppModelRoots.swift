import Foundation

/// Нота сэмплов (индикация): у каждого сэмпла проекта, который есть в памяти, а ноты в проекте нет, — определить
/// в фоне (PitchDetect) и записать в проект без UNDO. Так нота есть, откуда бы сэмпл ни пришёл (библиотека, когда
/// сэмпл уже был в памяти после ▶, запись REC, старые проекты). Шум и ударные (nil) второй раз не считаются.
extension AppModel {
    func ensureRoots() {
        var keys = Set(project.files.keys)
        for t in project.tracks where !t.sample.isEmpty && SynthKey.engine(t.sample) == nil { keys.insert(t.sample) }
        var need: [(String, SampleData)] = []
        for k in keys where project.roots[k] == nil && !rootTried.contains(k) {
            guard let d = store.data(k) else { continue }
            rootTried.insert(k)
            need.append((k, d))
        }
        if need.isEmpty { return }
        let list = need
        Task.detached(priority: .utility) {
            var found: [(String, Int)] = []
            for (k, d) in list {
                if let r = PitchDetect.root(d) { found.append((k, r)) }
            }
            let result = found
            if result.isEmpty { return }
            await MainActor.run {
                self.mutatePlay({ p in
                    for (k, r) in result where p.roots[k] == nil { p.roots[k] = r }
                }, publish: false)
            }
        }
    }
}
