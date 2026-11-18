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

/// Окна модулей мастера SAT, COMP, CLIP, LIM (S6): на месте центра, справа измеритель;
/// кнопки мастера (тап без SHIFT) и блоки индикации COMP, CLIP, LIM. PATTERNS, EQ, редактор сэмпла и окно модуля
/// не открыты одновременно; выход из MST окно не закрывает (скрыто до возврата), закрывает двойной тап по MST (17.11). Параметры — те же, что у ручек MST.
extension AppModel {
    func openMasterWindow(_ m: Int) {
        guard channel == .master, m >= 0 && m < 4 else { return }
        masterWin = m
        setUnity(false)
        masterMenu = nil
        browser = nil
        eqView = false
        eqMenu = nil
        eqMsMenu = nil
        eqDynMenu = nil
        eqPresetMenu = nil
        patternView = false
        editorOpen = false
        closeRoll()
        closeArrange()
    }

    /// Открытие другого окна (EQ, PATTERNS, редактор, браузер, пианоролл, аранжировщик) закрывает окно модуля мастера,
    /// только если оно на экране (MST); вне MST оно скрыто и остаётся открытым (17.11).
    func closeMasterWindowShown() {
        if channel == .master { closeMasterWindow() } else { hideMasterPopups() }
    }

    /// Уход с MST: всплывающие меню и окно ввода окна модуля мастера закрываются, UNITY выключается (слушать
    /// дорожки с приглушённым мастером не нужно).
    func hideMasterPopups() {
        if masterMenu != nil { masterMenu = nil }
        if masterInput != nil { masterInput = nil }
        if masterUnity { setUnity(false) }
    }

    func closeMasterWindow() {
        if masterWin == nil && masterMenu == nil { return }
        masterWin = nil
        masterMenu = nil
        masterInput = nil
        setUnity(false)
    }

    /// UNITY окна CLIP или LIM: выход модуля −INPUT dB (только обработанная ветка; индикация — реальная).
    func setUnity(_ on: Bool) {
        let m: Int = masterWin ?? -1
        let ok: Bool = on && (m == MasterScope.clip || m == MasterScope.lim)
        if masterUnity != ok { masterUnity = ok }
        audio.core.master.unity.store(ok ? m + 1 : 0)
    }

    /// Тап по полю RELEASE (COMP, LIM): AUTO ↔ последнее ручное значение (без него — по умолчанию).
    func tapRelease(_ p: ParamDef) {
        let v: Double = masterValue(p)
        let next: Double
        if v >= MasterChain.autoValue {
            next = releaseManual[p.id] ?? p.def
        } else {
            releaseManual[p.id] = v
            next = MasterChain.autoValue
        }
        edit { pr in pr.master[p.id] = next }
    }

    /// Тап по полю MAKEUP (AUTO MAKEUP, 18.11, решение пользователя): компрессор 4 с слушает, что играет, и MAKEUP
    /// выставляется на разницу громкости входа и выхода (фильтр K) — с компрессором так же громко, как без него
    /// (одна запись UNDO). Тап во время замера — отмена; тап по выставленному — последнее ручное значение. Тише −50 dB —
    /// NO SIGNAL, MAKEUP прежний.
    func tapMakeup() {
        guard let p = Params.byId["cmp.makeup"] else { return }
        let chain: MasterChain = audio.core.master
        if makeupState == 1 {
            chain.measureGen.store(0)
            makeupState = 0
            return
        }
        if makeupLive {
            let back: Double = makeupManual ?? p.def
            makeupState = 0
            edit { pr in pr.master[p.id] = back }
            return
        }
        makeupManual = masterValue(p)
        makeupRun += 1
        let run: Int = makeupRun
        chain.measureIn.store(-240)
        chain.measureOut.store(-240)
        chain.measureGen.store(run)
        makeupState = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self = self, self.makeupRun == run, self.makeupState == 1 else { return }
            chain.measureGen.store(0)
            let inDb: Double = Double(chain.measureIn.load())
            let outDb: Double = Double(chain.measureOut.load())
            if inDb < -50 {
                self.makeupState = 3
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    if let m = self, m.makeupRun == run, m.makeupState == 3 { m.makeupState = 0 }
                }
                return
            }
            let mk: Double = MasterInput.clamp(p, ((inDb - outDb) * 10).rounded() / 10)
            self.edit { pr in pr.master[p.id] = mk }
            self.makeupApplied = mk
            self.makeupState = 2
        }
    }

    /// AUTO MAKEUP выставлен и MAKEUP с тех пор не меняли.
    var makeupLive: Bool {
        guard makeupState == 2, let p = Params.byId["cmp.makeup"] else { return false }
        return abs(masterValue(p) - makeupApplied) < 1e-6
    }

    /// Значение поля MAKEUP: замер, тишина, AUTO с числом или обычное.
    func makeupLabel(_ plain: String) -> String {
        switch makeupState {
        case 1: return "MEASURING…"
        case 3: return "NO SIGNAL"
        default: return makeupLive ? "AUTO " + plain : plain
        }
    }

    /// Параметры модуля m в строке окна (по порядку полей).
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

    func saveMasterPreset(_ m: Int, name: String, over: Int? = nil) {
        masterPresets.save(m, name: name, master: project.master, over: over)
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

    func moveMasterPreset(_ m: Int, _ from: Int, to: Int) {
        masterPresets.move(m, from, to: to)
        storeMasterPresets()
    }

    private func storeMasterPresets() {
        UserDefaults.standard.set(masterPresets.encode(), forKey: "masterPresets")
    }

    static func loadMasterPresets() -> MasterPresetBook {
        return MasterPresetBook.decode(UserDefaults.standard.data(forKey: "masterPresets"))
    }
}
