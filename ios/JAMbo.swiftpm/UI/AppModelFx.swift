import Foundation

// Страница FX (удержание кнопки FX): ручки общих эффектов — Reverb, Delay, Drive, Sidechain (сетка FX).
// Значения принадлежат клипу-лидеру (как гамма и нота); с зажатым шагом — p-lock FX на шаге (меняет FX на время шага).

extension AppModel {
    /// Ручки показывают FX: зажата FX на дорожке.
    var fxMode: Bool { return fxHeld && channel == .track && (!modHeld || lastPage == .fx) }

    /// Параметр ручки FX; SC Source — только среди существующих дорожек, подписи — имена дорожек.
    func fxParam(_ slot: Int) -> ParamDef {
        let p = Params.fxGrid[slot]
        if p.id != "sc.source" { return p }
        let names: [String] = project.tracks.map { $0.name }
        return ParamDef(id: p.id, label: p.label, kind: .stepped, min: 0, max: Double(max(0, names.count - 1)), def: 0,
                        options: names) { v in
            let i = Int(v.rounded())
            return i >= 0 && i < names.count ? names[i] : ""
        }
    }

    /// Значение FX клипа (без p-lock).
    func fxValue(_ p: ParamDef) -> Double {
        return project.fx[p.id] ?? p.def
    }

    /// Поворот ручки FX без зажатого шага: значение — в проект и в клип лидера.
    func setFx(_ p: ParamDef, _ v: Double) {
        edit { pr in
            pr.fx[p.id] = v
            writeLead(&pr)
        }
    }
}
