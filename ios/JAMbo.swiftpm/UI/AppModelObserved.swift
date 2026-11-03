import Foundation
import Observation

// Наблюдаемые свойства AppModel простых типов (Bool, Int, рамки, необязательные значения) — вручную (S14, объём
// сборки в Playgrounds: макрос @Observable даёт на свойство ~1,8 КБ кода — замыкание withMutation, _modify и др.).
// Хранение — _имя в AppModel.swift (там же описание свойства), чтение — access, запись — put: willSet / didSet
// регистратора, как у макроса; уведомление — только если значение изменилось (как shouldNotifyObservers макроса).
// Коллекции и крупные структуры — через макрос (изменение на месте без копии). Свойства private(set) — в AppModel.swift.

extension AppModel {
    var settingsTab: SettingsTab {
        get { access(keyPath: \.settingsTab); return _settingsTab }
        set { put(\.settingsTab, \._settingsTab, newValue, AppModel.changed(_settingsTab, newValue)) }
    }
    var viewPage: Int {
        get { access(keyPath: \.viewPage); return _viewPage }
        set { put(\.viewPage, \._viewPage, newValue, AppModel.changed(_viewPage, newValue)) }
    }
    var spanView: Bool {
        get { access(keyPath: \.spanView); return _spanView }
        set { put(\.spanView, \._spanView, newValue, AppModel.changed(_spanView, newValue)) }
    }
    var appWindow: AppWindow? {
        get { access(keyPath: \.appWindow); return _appWindow }
        set { put(\.appWindow, \._appWindow, newValue, AppModel.changed(_appWindow, newValue)) }
    }
    var shiftHeld: Bool {
        get { access(keyPath: \.shiftHeld); return _shiftHeld }
        set { put(\.shiftHeld, \._shiftHeld, newValue, AppModel.changed(_shiftHeld, newValue)) }
    }
    var pandaShown: Bool {
        get { access(keyPath: \.pandaShown); return _pandaShown }
        set { put(\.pandaShown, \._pandaShown, newValue, AppModel.changed(_pandaShown, newValue)) }
    }
    var fxHeld: Bool {
        get { access(keyPath: \.fxHeld); return _fxHeld }
        set { put(\.fxHeld, \._fxHeld, newValue, AppModel.changed(_fxHeld, newValue)) }
    }
    var modHeld: Bool {
        get { access(keyPath: \.modHeld); return _modHeld }
        set { put(\.modHeld, \._modHeld, newValue, AppModel.changed(_modHeld, newValue)) }
    }
    var lastPage: GridPage {
        get { access(keyPath: \.lastPage); return _lastPage }
        set { put(\.lastPage, \._lastPage, newValue, AppModel.changed(_lastPage, newValue)) }
    }
    var lastSource: Int {
        get { access(keyPath: \.lastSource); return _lastSource }
        set { put(\.lastSource, \._lastSource, newValue, AppModel.changed(_lastSource, newValue)) }
    }
    var fxPicCol: Int {
        get { access(keyPath: \.fxPicCol); return _fxPicCol }
        set { put(\.fxPicCol, \._fxPicCol, newValue, AppModel.changed(_fxPicCol, newValue)) }
    }
    var fxMidiShow: Bool {
        get { access(keyPath: \.fxMidiShow); return _fxMidiShow }
        set { put(\.fxMidiShow, \._fxMidiShow, newValue, AppModel.changed(_fxMidiShow, newValue)) }
    }
    var morph: Bool {
        get { access(keyPath: \.morph); return _morph }
        set { put(\.morph, \._morph, newValue, AppModel.changed(_morph, newValue)) }
    }
    var morphHeld: Bool {
        get { access(keyPath: \.morphHeld); return _morphHeld }
        set { put(\.morphHeld, \._morphHeld, newValue, AppModel.changed(_morphHeld, newValue)) }
    }
    var morphUsed: Bool {
        get { access(keyPath: \.morphUsed); return _morphUsed }
        set { put(\.morphUsed, \._morphUsed, newValue, AppModel.changed(_morphUsed, newValue)) }
    }
    var morphAllHeld: Bool {
        get { access(keyPath: \.morphAllHeld); return _morphAllHeld }
        set { put(\.morphAllHeld, \._morphAllHeld, newValue, AppModel.changed(_morphAllHeld, newValue)) }
    }
    var pageMenu: PageMenuState? {
        get { access(keyPath: \.pageMenu); return _pageMenu }
        set { put(\.pageMenu, \._pageMenu, newValue, AppModel.changed(_pageMenu, newValue)) }
    }
    var recOn: Bool {
        get { access(keyPath: \.recOn); return _recOn }
        set { put(\.recOn, \._recOn, newValue, AppModel.changed(_recOn, newValue)) }
    }
    var arrAuto: Bool {
        get { access(keyPath: \.arrAuto); return _arrAuto }
        set { put(\.arrAuto, \._arrAuto, newValue, AppModel.changed(_arrAuto, newValue)) }
    }
    var arrRecArm: Bool {
        get { access(keyPath: \.arrRecArm); return _arrRecArm }
        set { put(\.arrRecArm, \._arrRecArm, newValue, AppModel.changed(_arrRecArm, newValue)) }
    }
    var arrPlayEnd: Int {
        get { access(keyPath: \.arrPlayEnd); return _arrPlayEnd }
        set { put(\.arrPlayEnd, \._arrPlayEnd, newValue, AppModel.changed(_arrPlayEnd, newValue)) }
    }
    var arrPlay: Bool {
        get { access(keyPath: \.arrPlay); return _arrPlay }
        set { put(\.arrPlay, \._arrPlay, newValue, AppModel.changed(_arrPlay, newValue)) }
    }
    var arrDraw: Bool {
        get { access(keyPath: \.arrDraw); return _arrDraw }
        set { put(\.arrDraw, \._arrDraw, newValue, AppModel.changed(_arrDraw, newValue)) }
    }
    var arrAutoId: String {
        get { access(keyPath: \.arrAutoId); return _arrAutoId }
        set { put(\.arrAutoId, \._arrAutoId, newValue, AppModel.changed(_arrAutoId, newValue)) }
    }
    var chordMenuOpen: Bool {
        get { access(keyPath: \.chordMenuOpen); return _chordMenuOpen }
        set { put(\.chordMenuOpen, \._chordMenuOpen, newValue, AppModel.changed(_chordMenuOpen, newValue)) }
    }
    var patternView: Bool {
        get { access(keyPath: \.patternView); return _patternView }
        set { put(\.patternView, \._patternView, newValue, AppModel.changed(_patternView, newValue)) }
    }
    var arrangeView: Bool {
        get { access(keyPath: \.arrangeView); return _arrangeView }
        set { put(\.arrangeView, \._arrangeView, newValue, AppModel.changed(_arrangeView, newValue)) }
    }
    var arrCursor: Int {
        get { access(keyPath: \.arrCursor); return _arrCursor }
        set { put(\.arrCursor, \._arrCursor, newValue, AppModel.changed(_arrCursor, newValue)) }
    }
    var arrSel: ArrSel? {
        get { access(keyPath: \.arrSel); return _arrSel }
        set { put(\.arrSel, \._arrSel, newValue, AppModel.changed(_arrSel, newValue)) }
    }
    var arrMarquee: CGRect? {
        get { access(keyPath: \.arrMarquee); return _arrMarquee }
        set { put(\.arrMarquee, \._arrMarquee, newValue, AppModel.changed(_arrMarquee, newValue)) }
    }
    var arrKnobs: Bool {
        get { access(keyPath: \.arrKnobs); return _arrKnobs }
        set { put(\.arrKnobs, \._arrKnobs, newValue, AppModel.changed(_arrKnobs, newValue)) }
    }
    var arrLowerH: CGFloat {
        get { access(keyPath: \.arrLowerH); return _arrLowerH }
        set { put(\.arrLowerH, \._arrLowerH, newValue, AppModel.changed(_arrLowerH, newValue)) }
    }
    var barH: CGFloat {
        get { access(keyPath: \.barH); return _barH }
        set { put(\.barH, \._barH, newValue, AppModel.changed(_barH, newValue)) }
    }
    var arrMenu: ArrMenuState? {
        get { access(keyPath: \.arrMenu); return _arrMenu }
        set { put(\.arrMenu, \._arrMenu, newValue, AppModel.changed(_arrMenu, newValue)) }
    }
    var arrInsert: Bool {
        get { access(keyPath: \.arrInsert); return _arrInsert }
        set { put(\.arrInsert, \._arrInsert, newValue, AppModel.changed(_arrInsert, newValue)) }
    }
    var arrInserted: ArrSel? {
        get { access(keyPath: \.arrInserted); return _arrInserted }
        set { put(\.arrInserted, \._arrInserted, newValue, AppModel.changed(_arrInserted, newValue)) }
    }
    var arrRefB: Bool {
        get { access(keyPath: \.arrRefB); return _arrRefB }
        set { put(\.arrRefB, \._arrRefB, newValue, AppModel.changed(_arrRefB, newValue)) }
    }
    var rollView: Bool {
        get { access(keyPath: \.rollView); return _rollView }
        set { put(\.rollView, \._rollView, newValue, AppModel.changed(_rollView, newValue)) }
    }
    var rollMenuOpen: Bool {
        get { access(keyPath: \.rollMenuOpen); return _rollMenuOpen }
        set { put(\.rollMenuOpen, \._rollMenuOpen, newValue, AppModel.changed(_rollMenuOpen, newValue)) }
    }
    var rollVel: Bool {
        get { access(keyPath: \.rollVel); return _rollVel }
        set { put(\.rollVel, \._rollVel, newValue, AppModel.changed(_rollVel, newValue)) }
    }
    var eqView: Bool {
        get { access(keyPath: \.eqView); return _eqView }
        set { put(\.eqView, \._eqView, newValue, AppModel.changed(_eqView, newValue)) }
    }
    var eqBand: Int {
        get { access(keyPath: \.eqBand); return _eqBand }
        set { put(\.eqBand, \._eqBand, newValue, AppModel.changed(_eqBand, newValue)) }
    }
    var eqListenHeld: Bool {
        get { access(keyPath: \.eqListenHeld); return _eqListenHeld }
        set { put(\.eqListenHeld, \._eqListenHeld, newValue, AppModel.changed(_eqListenHeld, newValue)) }
    }
    var eqListenBand: Int {
        get { access(keyPath: \.eqListenBand); return _eqListenBand }
        set { put(\.eqListenBand, \._eqListenBand, newValue, AppModel.changed(_eqListenBand, newValue)) }
    }
    var eqMenu: EqMenuState? {
        get { access(keyPath: \.eqMenu); return _eqMenu }
        set { put(\.eqMenu, \._eqMenu, newValue, AppModel.changed(_eqMenu, newValue)) }
    }
    var eqMsMenu: CGRect? {
        get { access(keyPath: \.eqMsMenu); return _eqMsMenu }
        set { put(\.eqMsMenu, \._eqMsMenu, newValue, AppModel.changed(_eqMsMenu, newValue)) }
    }
    var eqDynMenu: CGRect? {
        get { access(keyPath: \.eqDynMenu); return _eqDynMenu }
        set { put(\.eqDynMenu, \._eqDynMenu, newValue, AppModel.changed(_eqDynMenu, newValue)) }
    }
    var eqDynShift: CGSize {
        get { access(keyPath: \.eqDynShift); return _eqDynShift }
        set { put(\.eqDynShift, \._eqDynShift, newValue, AppModel.changed(_eqDynShift, newValue)) }
    }
    var eqInputAsk: EqInput? {
        get { access(keyPath: \.eqInputAsk); return _eqInputAsk }
        set { put(\.eqInputAsk, \._eqInputAsk, newValue, AppModel.changed(_eqInputAsk, newValue)) }
    }
    var eqPresetMenu: EqPresetMenuState? {
        get { access(keyPath: \.eqPresetMenu); return _eqPresetMenu }
        set { put(\.eqPresetMenu, \._eqPresetMenu, newValue, AppModel.changed(_eqPresetMenu, newValue)) }
    }
    var eqCompareMenu: Bool {
        get { access(keyPath: \.eqCompareMenu); return _eqCompareMenu }
        set { put(\.eqCompareMenu, \._eqCompareMenu, newValue, AppModel.changed(_eqCompareMenu, newValue)) }
    }
    var eqPhones: Bool {
        get { access(keyPath: \.eqPhones); return _eqPhones }
        set { put(\.eqPhones, \._eqPhones, newValue, AppModel.changed(_eqPhones, newValue)) }
    }
    var phonesName: String {
        get { access(keyPath: \.phonesName); return _phonesName }
        set { put(\.phonesName, \._phonesName, newValue, AppModel.changed(_phonesName, newValue)) }
    }
    var importingPhones: Bool {
        get { access(keyPath: \.importingPhones); return _importingPhones }
        set { put(\.importingPhones, \._importingPhones, newValue, AppModel.changed(_importingPhones, newValue)) }
    }
    var phonesNote: String? {
        get { access(keyPath: \.phonesNote); return _phonesNote }
        set { put(\.phonesNote, \._phonesNote, newValue, AppModel.changed(_phonesNote, newValue)) }
    }
    var phonesExported: URL? {
        get { access(keyPath: \.phonesExported); return _phonesExported }
        set { put(\.phonesExported, \._phonesExported, newValue, AppModel.changed(_phonesExported, newValue)) }
    }
    var gridTop: Int {
        get { access(keyPath: \.gridTop); return _gridTop }
        set { put(\.gridTop, \._gridTop, newValue, AppModel.changed(_gridTop, newValue)) }
    }
    var cellMenu: CellMenuState? {
        get { access(keyPath: \.cellMenu); return _cellMenu }
        set { put(\.cellMenu, \._cellMenu, newValue, AppModel.changed(_cellMenu, newValue)) }
    }
    var rowMenu: Int? {
        get { access(keyPath: \.rowMenu); return _rowMenu }
        set { put(\.rowMenu, \._rowMenu, newValue, AppModel.changed(_rowMenu, newValue)) }
    }
    var gridRowsShown: Int {
        get { access(keyPath: \.gridRowsShown); return _gridRowsShown }
        set { put(\.gridRowsShown, \._gridRowsShown, newValue, AppModel.changed(_gridRowsShown, newValue)) }
    }
    var clipCarry: ClipCarry? {
        get { access(keyPath: \.clipCarry); return _clipCarry }
        set { put(\.clipCarry, \._clipCarry, newValue, AppModel.changed(_clipCarry, newValue)) }
    }
    var carryPoint: CGPoint {
        get { access(keyPath: \.carryPoint); return _carryPoint }
        set { put(\.carryPoint, \._carryPoint, newValue, AppModel.changed(_carryPoint, newValue)) }
    }
    var deniedCell: CellRef? {
        get { access(keyPath: \.deniedCell); return _deniedCell }
        set { put(\.deniedCell, \._deniedCell, newValue, AppModel.changed(_deniedCell, newValue)) }
    }
    var mix: MixTransition? {
        get { access(keyPath: \.mix); return _mix }
        set { put(\.mix, \._mix, newValue, AppModel.changed(_mix, newValue)) }
    }
    var mixDropDone: Bool {
        get { access(keyPath: \.mixDropDone); return _mixDropDone }
        set { put(\.mixDropDone, \._mixDropDone, newValue, AppModel.changed(_mixDropDone, newValue)) }
    }
    var choice: ChoiceState? {
        get { access(keyPath: \.choice); return _choice }
        set { put(\.choice, \._choice, newValue, AppModel.changed(_choice, newValue)) }
    }
    var pianoMenuOpen: Bool {
        get { access(keyPath: \.pianoMenuOpen); return _pianoMenuOpen }
        set { put(\.pianoMenuOpen, \._pianoMenuOpen, newValue, AppModel.changed(_pianoMenuOpen, newValue)) }
    }
    var samplesVersion: Int {
        get { access(keyPath: \.samplesVersion); return _samplesVersion }
        set { put(\.samplesVersion, \._samplesVersion, newValue, AppModel.changed(_samplesVersion, newValue)) }
    }
    var editorOpen: Bool {
        get { access(keyPath: \.editorOpen); return _editorOpen }
        set { put(\.editorOpen, \._editorOpen, newValue, AppModel.changed(_editorOpen, newValue)) }
    }
    var editorWarp: Bool {
        get { access(keyPath: \.editorWarp); return _editorWarp }
        set { put(\.editorWarp, \._editorWarp, newValue, AppModel.changed(_editorWarp, newValue)) }
    }
    var warpGrid: Double {
        get { access(keyPath: \.warpGrid); return _warpGrid }
        set { put(\.warpGrid, \._warpGrid, newValue, AppModel.changed(_warpGrid, newValue)) }
    }
    var warpSel: Int? {
        get { access(keyPath: \.warpSel); return _warpSel }
        set { put(\.warpSel, \._warpSel, newValue, AppModel.changed(_warpSel, newValue)) }
    }
    var soundMenu: SoundMenuState? {
        get { access(keyPath: \.soundMenu); return _soundMenu }
        set { put(\.soundMenu, \._soundMenu, newValue, AppModel.changed(_soundMenu, newValue)) }
    }
    var importTarget: ImportTarget? {
        get { access(keyPath: \.importTarget); return _importTarget }
        set { put(\.importTarget, \._importTarget, newValue, AppModel.changed(_importTarget, newValue)) }
    }
    var importing: Bool {
        get { access(keyPath: \.importing); return _importing }
        set { put(\.importing, \._importing, newValue, AppModel.changed(_importing, newValue)) }
    }
    var importingProject: Bool {
        get { access(keyPath: \.importingProject); return _importingProject }
        set { put(\.importingProject, \._importingProject, newValue, AppModel.changed(_importingProject, newValue)) }
    }
    var projectImport: ProjectImport? {
        get { access(keyPath: \.projectImport); return _projectImport }
        set { put(\.projectImport, \._projectImport, newValue, AppModel.changed(_projectImport, newValue)) }
    }
    var browser: BrowserMode? {
        get { access(keyPath: \.browser); return _browser }
        set { put(\.browser, \._browser, newValue, AppModel.changed(_browser, newValue)) }
    }
    var libFolder: String {
        get { access(keyPath: \.libFolder); return _libFolder }
        set { put(\.libFolder, \._libFolder, newValue, AppModel.changed(_libFolder, newValue)) }
    }
    var libPicked: Set<String>? {
        get { access(keyPath: \.libPicked); return _libPicked }
        set { put(\.libPicked, \._libPicked, newValue, AppModel.changed(_libPicked, newValue)) }
    }
    var libNote: String {
        get { access(keyPath: \.libNote); return _libNote }
        set { put(\.libNote, \._libNote, newValue, AppModel.changed(_libNote, newValue)) }
    }
    var libWarning: String? {
        get { access(keyPath: \.libWarning); return _libWarning }
        set { put(\.libWarning, \._libWarning, newValue, AppModel.changed(_libWarning, newValue)) }
    }
    var importingLibrary: Bool {
        get { access(keyPath: \.importingLibrary); return _importingLibrary }
        set { put(\.importingLibrary, \._importingLibrary, newValue, AppModel.changed(_importingLibrary, newValue)) }
    }
    var leftFrame: CGRect {
        get { access(keyPath: \.leftFrame); return _leftFrame }
        set { put(\.leftFrame, \._leftFrame, newValue, AppModel.changed(_leftFrame, newValue)) }
    }
    var pagesFrame: CGRect {
        get { access(keyPath: \.pagesFrame); return _pagesFrame }
        set { put(\.pagesFrame, \._pagesFrame, newValue, AppModel.changed(_pagesFrame, newValue)) }
    }
    var keysFrame: CGRect {
        get { access(keyPath: \.keysFrame); return _keysFrame }
        set { put(\.keysFrame, \._keysFrame, newValue, AppModel.changed(_keysFrame, newValue)) }
    }
    var tracksFrame: CGRect {
        get { access(keyPath: \.tracksFrame); return _tracksFrame }
        set { put(\.tracksFrame, \._tracksFrame, newValue, AppModel.changed(_tracksFrame, newValue)) }
    }
    var previewOn: Bool {
        get { access(keyPath: \.previewOn); return _previewOn }
        set { put(\.previewOn, \._previewOn, newValue, AppModel.changed(_previewOn, newValue)) }
    }
    var heldFlag: Int? {
        get { access(keyPath: \.heldFlag); return _heldFlag }
        set { put(\.heldFlag, \._heldFlag, newValue, AppModel.changed(_heldFlag, newValue)) }
    }
    var roleFlag: Int? {
        get { access(keyPath: \.roleFlag); return _roleFlag }
        set { put(\.roleFlag, \._roleFlag, newValue, AppModel.changed(_roleFlag, newValue)) }
    }
    var trackMenu: TrackMenuState? {
        get { access(keyPath: \.trackMenu); return _trackMenu }
        set { put(\.trackMenu, \._trackMenu, newValue, AppModel.changed(_trackMenu, newValue)) }
    }
    var renaming: Int? {
        get { access(keyPath: \.renaming); return _renaming }
        set { put(\.renaming, \._renaming, newValue, AppModel.changed(_renaming, newValue)) }
    }
    var masterWin: Int? {
        get { access(keyPath: \.masterWin); return _masterWin }
        set { put(\.masterWin, \._masterWin, newValue, AppModel.changed(_masterWin, newValue)) }
    }
    var masterMenu: MasterMenuState? {
        get { access(keyPath: \.masterMenu); return _masterMenu }
        set { put(\.masterMenu, \._masterMenu, newValue, AppModel.changed(_masterMenu, newValue)) }
    }
    var masterInput: MasterInputTarget? {
        get { access(keyPath: \.masterInput); return _masterInput }
        set { put(\.masterInput, \._masterInput, newValue, AppModel.changed(_masterInput, newValue)) }
    }
    var defaultFlash: Int? {
        get { access(keyPath: \.defaultFlash); return _defaultFlash }
        set { put(\.defaultFlash, \._defaultFlash, newValue, AppModel.changed(_defaultFlash, newValue)) }
    }
    var defaultSaved: DefaultSaved? {
        get { access(keyPath: \.defaultSaved); return _defaultSaved }
        set { put(\.defaultSaved, \._defaultSaved, newValue, AppModel.changed(_defaultSaved, newValue)) }
    }
}
