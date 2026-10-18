import Foundation

/// Меню окна модуля мастера: выбор модуля (тап по названию), PRESETS — у кнопки anchor; bounds — окно модуля (меню в нём помещается). Координаты «root».
struct MasterMenuState: Equatable {
    enum Kind: Equatable {
        case modules
        case presets
    }

    let kind: Kind
    let anchor: CGRect
    let bounds: CGRect
}

/// Что вводят в окне ввода окна модуля: значение параметра, имя нового пресета, новое имя пресета k.
enum MasterInputTarget: Equatable {
    case param(String)
    case save
    case rename(Int)
}

/// Окна модулей мастера SAT, COMP, CLIP, LIM (S6, как openMasterWindow веба): на месте центра, справа измеритель;
/// кнопки мастера (тап без SHIFT) и блоки индикации COMP, CLIP, LIM. PATTERNS, EQ, редактор сэмпла и окно модуля
/// не открыты одновременно; выход из MST закрывает окно. Параметры — те же, что у ручек MST.
extension AppModel {
    func openMasterWindow(_ m: Int) {
        guard channel == .master, m >= 0 && m < 4 else { return }
        masterWin = m
        masterMenu = nil
        eqView = false
        eqMenu = nil
        eqMsMenu = nil
        eqDynMenu = nil
        eqPresetMenu = nil
        patternView = false
        editorOpen = false
        closeRoll()
    }

    func closeMasterWindow() {
        if masterWin == nil && masterMenu == nil { return }
        masterWin = nil
        masterMenu = nil
        masterInput = nil
    }

    /// Параметры модуля m в строке окна (порядок веба).
    static func masterFields(_ m: Int) -> [ParamDef] {
        return MasterPresetBook.ids(m).compactMap { Params.byId[$0] }
    }

    /// Значение параметра мастера из поля окна (в пределах параметра, с его шагом; внутри жеста — одна запись UNDO).
    func setMaster(_ p: ParamDef, _ v: Double) {
        let c: Double = MasterInput.clamp(p, v)
        edit { pr in pr.master[p.id] = c }
    }

    /// Тап по полю RATIO без движения: следующий пресет 2:1 → 4:1 → 10:1 → 2:1.
    func tapRatio() {
        guard let p = Params.byId["cmp.ratio"] else { return }
        let next: Double = MasterGlue.nextRatio(masterValue(p))
        edit { pr in pr.master[p.id] = next }
    }

    /// Тап по полю TYPE сатуратора: следующий тип TAPE → TUBE → EDGE → TAPE.
    func tapSatType() {
        let p: ParamDef = Params.masterColumns[0][1]
        let next: Double = Double((Int(masterValue(p).rounded()) + 1) % 3)
        edit { pr in pr.master[p.id] = next }
    }

    // MARK: — пресеты модулей

    func saveMasterPreset(_ m: Int, name: String) {
        masterPresets.save(m, name: name, master: project.master)
        storeMasterPresets()
    }

    /// Загрузить пресет k в модуль m (одна запись UNDO).
    func loadMasterPreset(_ m: Int, _ k: Int) {
        let book: MasterPresetBook = masterPresets
        edit { pr in book.apply(m, k, to: &pr.master) }
    }

    func renameMasterPreset(_ m: Int, _ k: Int, to name: String) {
        masterPresets.rename(m, k, to: name)
        storeMasterPresets()
    }

    func deleteMasterPreset(_ m: Int, _ k: Int) {
        masterPresets.delete(m, k)
        storeMasterPresets()
    }

    private func storeMasterPresets() {
        UserDefaults.standard.set(masterPresets.encode(), forKey: "masterPresets")
    }

    static func loadMasterPresets() -> MasterPresetBook {
        return MasterPresetBook.decode(UserDefaults.standard.data(forKey: "masterPresets"))
    }
}
