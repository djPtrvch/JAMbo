import Foundation
import Observation

// Наблюдаемые свойства AppModel простых типов (Bool, Int, рамки, необязательные значения) — вручную (S14, объём
// сборки в Playgrounds: макрос @Observable даёт на свойство ~1,8 КБ кода — замыкание withMutation, _modify и др.).
// Хранение — _имя в AppModel.swift (там же описание свойства), чтение — access, запись — put: willSet / didSet
// регистратора, как у макроса; уведомление — только если значение изменилось (как shouldNotifyObservers макроса).
// Небольшие коллекции (зажатые шаги, по 8 дорожек) — тоже: изменение на месте — копия, она мала. Крупные коллекции и
// структуры (проект, библиотека, настройки, пресеты) — через макрос (без копии). Свойства private(set) — в AppModel.swift.

extension AppModel {
    var settingsTab: SettingsTab {
        get { access(keyPath: \.settingsTab); return _settingsTab }
        set { let k = willPut(\.settingsTab, observedChanged(_settingsTab, newValue)); _settingsTab = newValue; didPut(k) }
    }
    var viewPage: Int {
        get { access(keyPath: \.viewPage); return _viewPage }
        set { let k = willPut(\.viewPage, observedChanged(_viewPage, newValue)); _viewPage = newValue; didPut(k) }
    }
    var spanView: Bool {
        get { access(keyPath: \.spanView); return _spanView }
        set { let k = willPut(\.spanView, observedChanged(_spanView, newValue)); _spanView = newValue; didPut(k) }
    }
    var appWindow: AppWindow? {
        get { access(keyPath: \.appWindow); return _appWindow }
        set { let k = willPut(\.appWindow, observedChanged(_appWindow, newValue)); _appWindow = newValue; didPut(k) }
    }
    var shiftHeld: Bool {
        get { access(keyPath: \.shiftHeld); return _shiftHeld }
        set { let k = willPut(\.shiftHeld, observedChanged(_shiftHeld, newValue)); _shiftHeld = newValue; didPut(k) }
    }
    var fxHeld: Bool {
        get { access(keyPath: \.fxHeld); return _fxHeld }
        set { let k = willPut(\.fxHeld, observedChanged(_fxHeld, newValue)); _fxHeld = newValue; didPut(k) }
    }
    var modHeld: Bool {
        get { access(keyPath: \.modHeld); return _modHeld }
        set { let k = willPut(\.modHeld, observedChanged(_modHeld, newValue)); _modHeld = newValue; didPut(k) }
    }
    var lastPage: GridPage {
        get { access(keyPath: \.lastPage); return _lastPage }
        set { let k = willPut(\.lastPage, observedChanged(_lastPage, newValue)); _lastPage = newValue; didPut(k) }
    }
    var lastSource: Int {
        get { access(keyPath: \.lastSource); return _lastSource }
        set { let k = willPut(\.lastSource, observedChanged(_lastSource, newValue)); _lastSource = newValue; didPut(k) }
    }
    var fxPicCol: Int {
        get { access(keyPath: \.fxPicCol); return _fxPicCol }
        set { let k = willPut(\.fxPicCol, observedChanged(_fxPicCol, newValue)); _fxPicCol = newValue; didPut(k) }
    }
    var fxMidiShow: Bool {
        get { access(keyPath: \.fxMidiShow); return _fxMidiShow }
        set { let k = willPut(\.fxMidiShow, observedChanged(_fxMidiShow, newValue)); _fxMidiShow = newValue; didPut(k) }
    }
    var morph: Bool {
        get { access(keyPath: \.morph); return _morph }
        set { let k = willPut(\.morph, observedChanged(_morph, newValue)); _morph = newValue; didPut(k) }
    }
    var morphHeld: Bool {
        get { access(keyPath: \.morphHeld); return _morphHeld }
        set { let k = willPut(\.morphHeld, observedChanged(_morphHeld, newValue)); _morphHeld = newValue; didPut(k) }
    }
    var morphUsed: Bool {
        get { access(keyPath: \.morphUsed); return _morphUsed }
        set { let k = willPut(\.morphUsed, observedChanged(_morphUsed, newValue)); _morphUsed = newValue; didPut(k) }
    }
    var morphAllHeld: Bool {
        get { access(keyPath: \.morphAllHeld); return _morphAllHeld }
        set { let k = willPut(\.morphAllHeld, observedChanged(_morphAllHeld, newValue)); _morphAllHeld = newValue; didPut(k) }
    }
    var pageMenu: PageMenuState? {
        get { access(keyPath: \.pageMenu); return _pageMenu }
        set { let k = willPut(\.pageMenu, observedChanged(_pageMenu, newValue)); _pageMenu = newValue; didPut(k) }
    }
    var recOn: Bool {
        get { access(keyPath: \.recOn); return _recOn }
        set { let k = willPut(\.recOn, observedChanged(_recOn, newValue)); _recOn = newValue; didPut(k) }
    }
    var arrAuto: Bool {
        get { access(keyPath: \.arrAuto); return _arrAuto }
        set { let k = willPut(\.arrAuto, observedChanged(_arrAuto, newValue)); _arrAuto = newValue; didPut(k) }
    }
    var arrRecArm: Bool {
        get { access(keyPath: \.arrRecArm); return _arrRecArm }
        set { let k = willPut(\.arrRecArm, observedChanged(_arrRecArm, newValue)); _arrRecArm = newValue; didPut(k) }
    }
    var arrPlayEnd: Int {
        get { access(keyPath: \.arrPlayEnd); return _arrPlayEnd }
        set { let k = willPut(\.arrPlayEnd, observedChanged(_arrPlayEnd, newValue)); _arrPlayEnd = newValue; didPut(k) }
    }
    var arrPlay: Bool {
        get { access(keyPath: \.arrPlay); return _arrPlay }
        set { let k = willPut(\.arrPlay, observedChanged(_arrPlay, newValue)); _arrPlay = newValue; didPut(k) }
    }
    var arrDraw: Bool {
        get { access(keyPath: \.arrDraw); return _arrDraw }
        set { let k = willPut(\.arrDraw, observedChanged(_arrDraw, newValue)); _arrDraw = newValue; didPut(k) }
    }
    var arrAutoId: String {
        get { access(keyPath: \.arrAutoId); return _arrAutoId }
        set { let k = willPut(\.arrAutoId, observedChanged(_arrAutoId, newValue)); _arrAutoId = newValue; didPut(k) }
    }
    var chordMenuOpen: Bool {
        get { access(keyPath: \.chordMenuOpen); return _chordMenuOpen }
        set { let k = willPut(\.chordMenuOpen, observedChanged(_chordMenuOpen, newValue)); _chordMenuOpen = newValue; didPut(k) }
    }
    var patternView: Bool {
        get { access(keyPath: \.patternView); return _patternView }
        set { let k = willPut(\.patternView, observedChanged(_patternView, newValue)); _patternView = newValue; didPut(k) }
    }
    var arrangeView: Bool {
        get { access(keyPath: \.arrangeView); return _arrangeView }
        set { let k = willPut(\.arrangeView, observedChanged(_arrangeView, newValue)); _arrangeView = newValue; didPut(k) }
    }
    var arrCursor: Int {
        get { access(keyPath: \.arrCursor); return _arrCursor }
        set { let k = willPut(\.arrCursor, observedChanged(_arrCursor, newValue)); _arrCursor = newValue; didPut(k) }
    }
    var arrSel: ArrSel? {
        get { access(keyPath: \.arrSel); return _arrSel }
        set { let k = willPut(\.arrSel, observedChanged(_arrSel, newValue)); _arrSel = newValue; didPut(k) }
    }
    var arrMarquee: CGRect? {
        get { access(keyPath: \.arrMarquee); return _arrMarquee }
        set { let k = willPut(\.arrMarquee, observedChanged(_arrMarquee, newValue)); _arrMarquee = newValue; didPut(k) }
    }
    var arrKnobs: Bool {
        get { access(keyPath: \.arrKnobs); return _arrKnobs }
        set { let k = willPut(\.arrKnobs, observedChanged(_arrKnobs, newValue)); _arrKnobs = newValue; didPut(k) }
    }
    var arrLowerH: CGFloat {
        get { access(keyPath: \.arrLowerH); return _arrLowerH }
        set { let k = willPut(\.arrLowerH, observedChanged(_arrLowerH, newValue)); _arrLowerH = newValue; didPut(k) }
    }
    var barH: CGFloat {
        get { access(keyPath: \.barH); return _barH }
        set { let k = willPut(\.barH, observedChanged(_barH, newValue)); _barH = newValue; didPut(k) }
    }
    var arrMenu: ArrMenuState? {
        get { access(keyPath: \.arrMenu); return _arrMenu }
        set { let k = willPut(\.arrMenu, observedChanged(_arrMenu, newValue)); _arrMenu = newValue; didPut(k) }
    }
    var arrInsert: Bool {
        get { access(keyPath: \.arrInsert); return _arrInsert }
        set { let k = willPut(\.arrInsert, observedChanged(_arrInsert, newValue)); _arrInsert = newValue; didPut(k) }
    }
    var arrInserted: ArrSel? {
        get { access(keyPath: \.arrInserted); return _arrInserted }
        set { let k = willPut(\.arrInserted, observedChanged(_arrInserted, newValue)); _arrInserted = newValue; didPut(k) }
    }
    var arrRefB: Bool {
        get { access(keyPath: \.arrRefB); return _arrRefB }
        set { let k = willPut(\.arrRefB, observedChanged(_arrRefB, newValue)); _arrRefB = newValue; didPut(k) }
    }
    var rollView: Bool {
        get { access(keyPath: \.rollView); return _rollView }
        set { let k = willPut(\.rollView, observedChanged(_rollView, newValue)); _rollView = newValue; didPut(k) }
    }
    var rollMenuOpen: Bool {
        get { access(keyPath: \.rollMenuOpen); return _rollMenuOpen }
        set { let k = willPut(\.rollMenuOpen, observedChanged(_rollMenuOpen, newValue)); _rollMenuOpen = newValue; didPut(k) }
    }
    var rollVel: Bool {
        get { access(keyPath: \.rollVel); return _rollVel }
        set { let k = willPut(\.rollVel, observedChanged(_rollVel, newValue)); _rollVel = newValue; didPut(k) }
    }
    var eqView: Bool {
        get { access(keyPath: \.eqView); return _eqView }
        set { let k = willPut(\.eqView, observedChanged(_eqView, newValue)); _eqView = newValue; didPut(k) }
    }
    var eqBand: Int {
        get { access(keyPath: \.eqBand); return _eqBand }
        set { let k = willPut(\.eqBand, observedChanged(_eqBand, newValue)); _eqBand = newValue; didPut(k) }
    }
    var eqListenHeld: Bool {
        get { access(keyPath: \.eqListenHeld); return _eqListenHeld }
        set { let k = willPut(\.eqListenHeld, observedChanged(_eqListenHeld, newValue)); _eqListenHeld = newValue; didPut(k) }
    }
    var eqListenBand: Int {
        get { access(keyPath: \.eqListenBand); return _eqListenBand }
        set { let k = willPut(\.eqListenBand, observedChanged(_eqListenBand, newValue)); _eqListenBand = newValue; didPut(k) }
    }
    var eqMenu: EqMenuState? {
        get { access(keyPath: \.eqMenu); return _eqMenu }
        set { let k = willPut(\.eqMenu, observedChanged(_eqMenu, newValue)); _eqMenu = newValue; didPut(k) }
    }
    var translationMenu: CGRect? {
        get { access(keyPath: \.translationMenu); return _translationMenu }
        set { let k = willPut(\.translationMenu, observedChanged(_translationMenu, newValue)); _translationMenu = newValue; didPut(k) }
    }
    var eqMsMenu: CGRect? {
        get { access(keyPath: \.eqMsMenu); return _eqMsMenu }
        set { let k = willPut(\.eqMsMenu, observedChanged(_eqMsMenu, newValue)); _eqMsMenu = newValue; didPut(k) }
    }
    var eqDynMenu: CGRect? {
        get { access(keyPath: \.eqDynMenu); return _eqDynMenu }
        set { let k = willPut(\.eqDynMenu, observedChanged(_eqDynMenu, newValue)); _eqDynMenu = newValue; didPut(k) }
    }
    var eqDynShift: CGSize {
        get { access(keyPath: \.eqDynShift); return _eqDynShift }
        set { let k = willPut(\.eqDynShift, observedChanged(_eqDynShift, newValue)); _eqDynShift = newValue; didPut(k) }
    }
    var eqInputAsk: EqInput? {
        get { access(keyPath: \.eqInputAsk); return _eqInputAsk }
        set { let k = willPut(\.eqInputAsk, observedChanged(_eqInputAsk, newValue)); _eqInputAsk = newValue; didPut(k) }
    }
    var eqPresetMenu: EqPresetMenuState? {
        get { access(keyPath: \.eqPresetMenu); return _eqPresetMenu }
        set { let k = willPut(\.eqPresetMenu, observedChanged(_eqPresetMenu, newValue)); _eqPresetMenu = newValue; didPut(k) }
    }
    var eqCompareMenu: Bool {
        get { access(keyPath: \.eqCompareMenu); return _eqCompareMenu }
        set { let k = willPut(\.eqCompareMenu, observedChanged(_eqCompareMenu, newValue)); _eqCompareMenu = newValue; didPut(k) }
    }
    var eqPhones: Bool {
        get { access(keyPath: \.eqPhones); return _eqPhones }
        set { let k = willPut(\.eqPhones, observedChanged(_eqPhones, newValue)); _eqPhones = newValue; didPut(k) }
    }
    var phonesName: String {
        get { access(keyPath: \.phonesName); return _phonesName }
        set { let k = willPut(\.phonesName, observedChanged(_phonesName, newValue)); _phonesName = newValue; didPut(k) }
    }
    var importingPhones: Bool {
        get { access(keyPath: \.importingPhones); return _importingPhones }
        set { let k = willPut(\.importingPhones, observedChanged(_importingPhones, newValue)); _importingPhones = newValue; didPut(k) }
    }
    var phonesNote: String? {
        get { access(keyPath: \.phonesNote); return _phonesNote }
        set { let k = willPut(\.phonesNote, observedChanged(_phonesNote, newValue)); _phonesNote = newValue; didPut(k) }
    }
    var phonesExported: URL? {
        get { access(keyPath: \.phonesExported); return _phonesExported }
        set { let k = willPut(\.phonesExported, observedChanged(_phonesExported, newValue)); _phonesExported = newValue; didPut(k) }
    }
    var gridTop: Int {
        get { access(keyPath: \.gridTop); return _gridTop }
        set { let k = willPut(\.gridTop, observedChanged(_gridTop, newValue)); _gridTop = newValue; didPut(k) }
    }
    var cellMenu: CellMenuState? {
        get { access(keyPath: \.cellMenu); return _cellMenu }
        set { let k = willPut(\.cellMenu, observedChanged(_cellMenu, newValue)); _cellMenu = newValue; didPut(k) }
    }
    var rowMenu: Int? {
        get { access(keyPath: \.rowMenu); return _rowMenu }
        set { let k = willPut(\.rowMenu, observedChanged(_rowMenu, newValue)); _rowMenu = newValue; didPut(k) }
    }
    var gridRowsShown: Int {
        get { access(keyPath: \.gridRowsShown); return _gridRowsShown }
        set { let k = willPut(\.gridRowsShown, observedChanged(_gridRowsShown, newValue)); _gridRowsShown = newValue; didPut(k) }
    }
    var clipCarry: ClipCarry? {
        get { access(keyPath: \.clipCarry); return _clipCarry }
        set { let k = willPut(\.clipCarry, observedChanged(_clipCarry, newValue)); _clipCarry = newValue; didPut(k) }
    }
    var carryPoint: CGPoint {
        get { access(keyPath: \.carryPoint); return _carryPoint }
        set { let k = willPut(\.carryPoint, observedChanged(_carryPoint, newValue)); _carryPoint = newValue; didPut(k) }
    }
    var deniedCell: CellRef? {
        get { access(keyPath: \.deniedCell); return _deniedCell }
        set { let k = willPut(\.deniedCell, observedChanged(_deniedCell, newValue)); _deniedCell = newValue; didPut(k) }
    }
    var mix: MixTransition? {
        get { access(keyPath: \.mix); return _mix }
        set { let k = willPut(\.mix, observedChanged(_mix, newValue)); _mix = newValue; didPut(k) }
    }
    var mixDropDone: Bool {
        get { access(keyPath: \.mixDropDone); return _mixDropDone }
        set { let k = willPut(\.mixDropDone, observedChanged(_mixDropDone, newValue)); _mixDropDone = newValue; didPut(k) }
    }
    var choice: ChoiceState? {
        get { access(keyPath: \.choice); return _choice }
        set { let k = willPut(\.choice, observedChanged(_choice, newValue)); _choice = newValue; didPut(k) }
    }
    var pianoMenuOpen: Bool {
        get { access(keyPath: \.pianoMenuOpen); return _pianoMenuOpen }
        set { let k = willPut(\.pianoMenuOpen, observedChanged(_pianoMenuOpen, newValue)); _pianoMenuOpen = newValue; didPut(k) }
    }
    var samplesVersion: Int {
        get { access(keyPath: \.samplesVersion); return _samplesVersion }
        set { let k = willPut(\.samplesVersion, observedChanged(_samplesVersion, newValue)); _samplesVersion = newValue; didPut(k) }
    }
    var editorOpen: Bool {
        get { access(keyPath: \.editorOpen); return _editorOpen }
        set { let k = willPut(\.editorOpen, observedChanged(_editorOpen, newValue)); _editorOpen = newValue; didPut(k) }
    }
    var editorWarp: Bool {
        get { access(keyPath: \.editorWarp); return _editorWarp }
        set { let k = willPut(\.editorWarp, observedChanged(_editorWarp, newValue)); _editorWarp = newValue; didPut(k) }
    }
    var warpGrid: Double {
        get { access(keyPath: \.warpGrid); return _warpGrid }
        set { let k = willPut(\.warpGrid, observedChanged(_warpGrid, newValue)); _warpGrid = newValue; didPut(k) }
    }
    var warpSel: Int? {
        get { access(keyPath: \.warpSel); return _warpSel }
        set { let k = willPut(\.warpSel, observedChanged(_warpSel, newValue)); _warpSel = newValue; didPut(k) }
    }
    var soundMenu: SoundMenuState? {
        get { access(keyPath: \.soundMenu); return _soundMenu }
        set { let k = willPut(\.soundMenu, observedChanged(_soundMenu, newValue)); _soundMenu = newValue; didPut(k) }
    }
    var importTarget: ImportTarget? {
        get { access(keyPath: \.importTarget); return _importTarget }
        set { let k = willPut(\.importTarget, observedChanged(_importTarget, newValue)); _importTarget = newValue; didPut(k) }
    }
    var importing: Bool {
        get { access(keyPath: \.importing); return _importing }
        set { let k = willPut(\.importing, observedChanged(_importing, newValue)); _importing = newValue; didPut(k) }
    }
    var importingProject: Bool {
        get { access(keyPath: \.importingProject); return _importingProject }
        set { let k = willPut(\.importingProject, observedChanged(_importingProject, newValue)); _importingProject = newValue; didPut(k) }
    }
    var projectImport: ProjectImport? {
        get { access(keyPath: \.projectImport); return _projectImport }
        set { let k = willPut(\.projectImport, observedChanged(_projectImport, newValue)); _projectImport = newValue; didPut(k) }
    }
    var browser: BrowserMode? {
        get { access(keyPath: \.browser); return _browser }
        set { let k = willPut(\.browser, observedChanged(_browser, newValue)); _browser = newValue; didPut(k) }
    }
    var libFolder: String {
        get { access(keyPath: \.libFolder); return _libFolder }
        set { let k = willPut(\.libFolder, observedChanged(_libFolder, newValue)); _libFolder = newValue; didPut(k) }
    }
    var libPicked: Set<String>? {
        get { access(keyPath: \.libPicked); return _libPicked }
        set { let k = willPut(\.libPicked, observedChanged(_libPicked, newValue)); _libPicked = newValue; didPut(k) }
    }
    var libNote: String {
        get { access(keyPath: \.libNote); return _libNote }
        set { let k = willPut(\.libNote, observedChanged(_libNote, newValue)); _libNote = newValue; didPut(k) }
    }
    var libWarning: String? {
        get { access(keyPath: \.libWarning); return _libWarning }
        set { let k = willPut(\.libWarning, observedChanged(_libWarning, newValue)); _libWarning = newValue; didPut(k) }
    }
    var importingLibrary: Bool {
        get { access(keyPath: \.importingLibrary); return _importingLibrary }
        set { let k = willPut(\.importingLibrary, observedChanged(_importingLibrary, newValue)); _importingLibrary = newValue; didPut(k) }
    }
    var leftFrame: CGRect {
        get { access(keyPath: \.leftFrame); return _leftFrame }
        set { let k = willPut(\.leftFrame, observedChanged(_leftFrame, newValue)); _leftFrame = newValue; didPut(k) }
    }
    var pagesFrame: CGRect {
        get { access(keyPath: \.pagesFrame); return _pagesFrame }
        set { let k = willPut(\.pagesFrame, observedChanged(_pagesFrame, newValue)); _pagesFrame = newValue; didPut(k) }
    }
    var keysFrame: CGRect {
        get { access(keyPath: \.keysFrame); return _keysFrame }
        set { let k = willPut(\.keysFrame, observedChanged(_keysFrame, newValue)); _keysFrame = newValue; didPut(k) }
    }
    var tracksFrame: CGRect {
        get { access(keyPath: \.tracksFrame); return _tracksFrame }
        set { let k = willPut(\.tracksFrame, observedChanged(_tracksFrame, newValue)); _tracksFrame = newValue; didPut(k) }
    }
    var previewOn: Bool {
        get { access(keyPath: \.previewOn); return _previewOn }
        set { let k = willPut(\.previewOn, observedChanged(_previewOn, newValue)); _previewOn = newValue; didPut(k) }
    }
    var heldFlag: Int? {
        get { access(keyPath: \.heldFlag); return _heldFlag }
        set { let k = willPut(\.heldFlag, observedChanged(_heldFlag, newValue)); _heldFlag = newValue; didPut(k) }
    }
    var roleFlag: Int? {
        get { access(keyPath: \.roleFlag); return _roleFlag }
        set { let k = willPut(\.roleFlag, observedChanged(_roleFlag, newValue)); _roleFlag = newValue; didPut(k) }
    }
    var trackMenu: TrackMenuState? {
        get { access(keyPath: \.trackMenu); return _trackMenu }
        set { let k = willPut(\.trackMenu, observedChanged(_trackMenu, newValue)); _trackMenu = newValue; didPut(k) }
    }
    var renaming: Int? {
        get { access(keyPath: \.renaming); return _renaming }
        set { let k = willPut(\.renaming, observedChanged(_renaming, newValue)); _renaming = newValue; didPut(k) }
    }
    var masterWin: Int? {
        get { access(keyPath: \.masterWin); return _masterWin }
        set { let k = willPut(\.masterWin, observedChanged(_masterWin, newValue)); _masterWin = newValue; didPut(k) }
    }
    var masterMenu: MasterMenuState? {
        get { access(keyPath: \.masterMenu); return _masterMenu }
        set { let k = willPut(\.masterMenu, observedChanged(_masterMenu, newValue)); _masterMenu = newValue; didPut(k) }
    }
    var masterInput: MasterInputTarget? {
        get { access(keyPath: \.masterInput); return _masterInput }
        set { let k = willPut(\.masterInput, observedChanged(_masterInput, newValue)); _masterInput = newValue; didPut(k) }
    }
    var defaultFlash: Int? {
        get { access(keyPath: \.defaultFlash); return _defaultFlash }
        set { let k = willPut(\.defaultFlash, observedChanged(_defaultFlash, newValue)); _defaultFlash = newValue; didPut(k) }
    }
    var defaultSaved: DefaultSaved? {
        get { access(keyPath: \.defaultSaved); return _defaultSaved }
        set { let k = willPut(\.defaultSaved, observedChanged(_defaultSaved, newValue)); _defaultSaved = newValue; didPut(k) }
    }
    var heldSteps: Set<Int> {
        get { access(keyPath: \.heldSteps); return _heldSteps }
        set { let k = willPut(\.heldSteps, observedChanged(_heldSteps, newValue)); _heldSteps = newValue; didPut(k) }
    }
    var heldSources: Set<Int> {
        get { access(keyPath: \.heldSources); return _heldSources }
        set { let k = willPut(\.heldSources, observedChanged(_heldSources, newValue)); _heldSources = newValue; didPut(k) }
    }
    var knobFingers: Set<Int> {
        get { access(keyPath: \.knobFingers); return _knobFingers }
        set { let k = willPut(\.knobFingers, observedChanged(_knobFingers, newValue)); _knobFingers = newValue; didPut(k) }
    }
    var octaves: [Int] {
        get { access(keyPath: \.octaves); return _octaves }
        set { let k = willPut(\.octaves, observedChanged(_octaves, newValue)); _octaves = newValue; didPut(k) }
    }
    var chordMode: [Bool] {
        get { access(keyPath: \.chordMode); return _chordMode }
        set { let k = willPut(\.chordMode, observedChanged(_chordMode, newValue)); _chordMode = newValue; didPut(k) }
    }
    var chordKind: [Int] {
        get { access(keyPath: \.chordKind); return _chordKind }
        set { let k = willPut(\.chordKind, observedChanged(_chordKind, newValue)); _chordKind = newValue; didPut(k) }
    }
    var selNotes: [[Int]] {
        get { access(keyPath: \.selNotes); return _selNotes }
        set { let k = willPut(\.selNotes, observedChanged(_selNotes, newValue)); _selNotes = newValue; didPut(k) }
    }
    var pressedKeys: [Int: [Int]] {
        get { access(keyPath: \.pressedKeys); return _pressedKeys }
        set { let k = willPut(\.pressedKeys, observedChanged(_pressedKeys, newValue)); _pressedKeys = newValue; didPut(k) }
    }
    var arrGroup: [ArrSel] {
        get { access(keyPath: \.arrGroup); return _arrGroup }
        set { let k = willPut(\.arrGroup, observedChanged(_arrGroup, newValue)); _arrGroup = newValue; didPut(k) }
    }
    var eqCompares: [Int: Int] {
        get { access(keyPath: \.eqCompares); return _eqCompares }
        set { let k = willPut(\.eqCompares, observedChanged(_eqCompares, newValue)); _eqCompares = newValue; didPut(k) }
    }
    var arrDropPending: (sel: GridSelection, start: Int)? {
        get { access(keyPath: \.arrDropPending); return _arrDropPending }
        set { let k = willPut(\.arrDropPending, observedChanged(_arrDropPending, newValue)); _arrDropPending = newValue; didPut(k) }
    }
    var gridMenuOpen: Bool {
        get { access(keyPath: \.gridMenuOpen); return _gridMenuOpen }
        set { let k = willPut(\.gridMenuOpen, observedChanged(_gridMenuOpen, newValue)); _gridMenuOpen = newValue; didPut(k) }
    }
    var mixDrop: [Int: Int] {
        get { access(keyPath: \.mixDrop); return _mixDrop }
        set { let k = willPut(\.mixDrop, observedChanged(_mixDrop, newValue)); _mixDrop = newValue; didPut(k) }
    }
    var captureFlash: Bool {
        get { access(keyPath: \.captureFlash); return _captureFlash }
        set { let k = willPut(\.captureFlash, observedChanged(_captureFlash, newValue)); _captureFlash = newValue; didPut(k) }
    }
    var wavetableSerial: Int {
        get { access(keyPath: \.wavetableSerial); return _wavetableSerial }
        set { let k = willPut(\.wavetableSerial, observedChanged(_wavetableSerial, newValue)); _wavetableSerial = newValue; didPut(k) }
    }
    var headCount: Int {
        get { access(keyPath: \.headCount); return _headCount }
        set { let k = willPut(\.headCount, observedChanged(_headCount, newValue)); _headCount = newValue; didPut(k) }
    }
    var stemArmed: Set<Int> {
        get { access(keyPath: \.stemArmed); return _stemArmed }
        set { let k = willPut(\.stemArmed, observedChanged(_stemArmed, newValue)); _stemArmed = newValue; didPut(k) }
    }
    var stemRecording: Set<Int> {
        get { access(keyPath: \.stemRecording); return _stemRecording }
        set { let k = willPut(\.stemRecording, observedChanged(_stemRecording, newValue)); _stemRecording = newValue; didPut(k) }
    }
    var refusedFlag: (idx: Int, until: Double) {
        get { access(keyPath: \.refusedFlag); return _refusedFlag }
        set { let k = willPut(\.refusedFlag, observedChanged(_refusedFlag, newValue)); _refusedFlag = newValue; didPut(k) }
    }
    var hasTrackClip: Bool {
        get { access(keyPath: \.hasTrackClip); return _hasTrackClip }
        set { let k = willPut(\.hasTrackClip, observedChanged(_hasTrackClip, newValue)); _hasTrackClip = newValue; didPut(k) }
    }
    var scopeOn: [Bool] {
        get { access(keyPath: \.scopeOn); return _scopeOn }
        set { let k = willPut(\.scopeOn, observedChanged(_scopeOn, newValue)); _scopeOn = newValue; didPut(k) }
    }
}

/// Изменилось ли значение (как shouldNotifyObservers макроса @Observable): у Equatable — сравнение, иначе — да. Одна
/// функция без перегрузок: Playgrounds подменяет функции на лету и не находит перегрузки одного имени («Replaced
/// function … could not be found»). nil → nil — тоже «изменилось» (лишнее уведомление, без вреда).
func observedChanged<T>(_ a: T, _ b: T) -> Bool {
    guard let x = a as? any Equatable else { return true }
    return !observedSame(x, b)
}

private func observedSame<E: Equatable>(_ x: E, _ b: Any) -> Bool {
    guard let y = b as? E else { return false }
    return x == y
}
