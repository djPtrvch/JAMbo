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
        set { put(\.settingsTab, \._settingsTab, newValue, notifyChanged(_settingsTab, newValue)) }
    }
    var viewPage: Int {
        get { access(keyPath: \.viewPage); return _viewPage }
        set { put(\.viewPage, \._viewPage, newValue, notifyChanged(_viewPage, newValue)) }
    }
    var spanView: Bool {
        get { access(keyPath: \.spanView); return _spanView }
        set { put(\.spanView, \._spanView, newValue, notifyChanged(_spanView, newValue)) }
    }
    var appWindow: AppWindow? {
        get { access(keyPath: \.appWindow); return _appWindow }
        set { put(\.appWindow, \._appWindow, newValue, notifyChanged(_appWindow, newValue)) }
    }
    var shiftHeld: Bool {
        get { access(keyPath: \.shiftHeld); return _shiftHeld }
        set { put(\.shiftHeld, \._shiftHeld, newValue, notifyChanged(_shiftHeld, newValue)) }
    }
    var pandaShown: Bool {
        get { access(keyPath: \.pandaShown); return _pandaShown }
        set { put(\.pandaShown, \._pandaShown, newValue, notifyChanged(_pandaShown, newValue)) }
    }
    var fxHeld: Bool {
        get { access(keyPath: \.fxHeld); return _fxHeld }
        set { put(\.fxHeld, \._fxHeld, newValue, notifyChanged(_fxHeld, newValue)) }
    }
    var modHeld: Bool {
        get { access(keyPath: \.modHeld); return _modHeld }
        set { put(\.modHeld, \._modHeld, newValue, notifyChanged(_modHeld, newValue)) }
    }
    var lastPage: GridPage {
        get { access(keyPath: \.lastPage); return _lastPage }
        set { put(\.lastPage, \._lastPage, newValue, notifyChanged(_lastPage, newValue)) }
    }
    var lastSource: Int {
        get { access(keyPath: \.lastSource); return _lastSource }
        set { put(\.lastSource, \._lastSource, newValue, notifyChanged(_lastSource, newValue)) }
    }
    var fxPicCol: Int {
        get { access(keyPath: \.fxPicCol); return _fxPicCol }
        set { put(\.fxPicCol, \._fxPicCol, newValue, notifyChanged(_fxPicCol, newValue)) }
    }
    var fxMidiShow: Bool {
        get { access(keyPath: \.fxMidiShow); return _fxMidiShow }
        set { put(\.fxMidiShow, \._fxMidiShow, newValue, notifyChanged(_fxMidiShow, newValue)) }
    }
    var morph: Bool {
        get { access(keyPath: \.morph); return _morph }
        set { put(\.morph, \._morph, newValue, notifyChanged(_morph, newValue)) }
    }
    var morphHeld: Bool {
        get { access(keyPath: \.morphHeld); return _morphHeld }
        set { put(\.morphHeld, \._morphHeld, newValue, notifyChanged(_morphHeld, newValue)) }
    }
    var morphUsed: Bool {
        get { access(keyPath: \.morphUsed); return _morphUsed }
        set { put(\.morphUsed, \._morphUsed, newValue, notifyChanged(_morphUsed, newValue)) }
    }
    var morphAllHeld: Bool {
        get { access(keyPath: \.morphAllHeld); return _morphAllHeld }
        set { put(\.morphAllHeld, \._morphAllHeld, newValue, notifyChanged(_morphAllHeld, newValue)) }
    }
    var pageMenu: PageMenuState? {
        get { access(keyPath: \.pageMenu); return _pageMenu }
        set { put(\.pageMenu, \._pageMenu, newValue, notifyChanged(_pageMenu, newValue)) }
    }
    var recOn: Bool {
        get { access(keyPath: \.recOn); return _recOn }
        set { put(\.recOn, \._recOn, newValue, notifyChanged(_recOn, newValue)) }
    }
    var arrAuto: Bool {
        get { access(keyPath: \.arrAuto); return _arrAuto }
        set { put(\.arrAuto, \._arrAuto, newValue, notifyChanged(_arrAuto, newValue)) }
    }
    var arrRecArm: Bool {
        get { access(keyPath: \.arrRecArm); return _arrRecArm }
        set { put(\.arrRecArm, \._arrRecArm, newValue, notifyChanged(_arrRecArm, newValue)) }
    }
    var arrPlayEnd: Int {
        get { access(keyPath: \.arrPlayEnd); return _arrPlayEnd }
        set { put(\.arrPlayEnd, \._arrPlayEnd, newValue, notifyChanged(_arrPlayEnd, newValue)) }
    }
    var arrPlay: Bool {
        get { access(keyPath: \.arrPlay); return _arrPlay }
        set { put(\.arrPlay, \._arrPlay, newValue, notifyChanged(_arrPlay, newValue)) }
    }
    var arrDraw: Bool {
        get { access(keyPath: \.arrDraw); return _arrDraw }
        set { put(\.arrDraw, \._arrDraw, newValue, notifyChanged(_arrDraw, newValue)) }
    }
    var arrAutoId: String {
        get { access(keyPath: \.arrAutoId); return _arrAutoId }
        set { put(\.arrAutoId, \._arrAutoId, newValue, notifyChanged(_arrAutoId, newValue)) }
    }
    var chordMenuOpen: Bool {
        get { access(keyPath: \.chordMenuOpen); return _chordMenuOpen }
        set { put(\.chordMenuOpen, \._chordMenuOpen, newValue, notifyChanged(_chordMenuOpen, newValue)) }
    }
    var patternView: Bool {
        get { access(keyPath: \.patternView); return _patternView }
        set { put(\.patternView, \._patternView, newValue, notifyChanged(_patternView, newValue)) }
    }
    var arrangeView: Bool {
        get { access(keyPath: \.arrangeView); return _arrangeView }
        set { put(\.arrangeView, \._arrangeView, newValue, notifyChanged(_arrangeView, newValue)) }
    }
    var arrCursor: Int {
        get { access(keyPath: \.arrCursor); return _arrCursor }
        set { put(\.arrCursor, \._arrCursor, newValue, notifyChanged(_arrCursor, newValue)) }
    }
    var arrSel: ArrSel? {
        get { access(keyPath: \.arrSel); return _arrSel }
        set { put(\.arrSel, \._arrSel, newValue, notifyChanged(_arrSel, newValue)) }
    }
    var arrMarquee: CGRect? {
        get { access(keyPath: \.arrMarquee); return _arrMarquee }
        set { put(\.arrMarquee, \._arrMarquee, newValue, notifyChanged(_arrMarquee, newValue)) }
    }
    var arrKnobs: Bool {
        get { access(keyPath: \.arrKnobs); return _arrKnobs }
        set { put(\.arrKnobs, \._arrKnobs, newValue, notifyChanged(_arrKnobs, newValue)) }
    }
    var arrLowerH: CGFloat {
        get { access(keyPath: \.arrLowerH); return _arrLowerH }
        set { put(\.arrLowerH, \._arrLowerH, newValue, notifyChanged(_arrLowerH, newValue)) }
    }
    var barH: CGFloat {
        get { access(keyPath: \.barH); return _barH }
        set { put(\.barH, \._barH, newValue, notifyChanged(_barH, newValue)) }
    }
    var arrMenu: ArrMenuState? {
        get { access(keyPath: \.arrMenu); return _arrMenu }
        set { put(\.arrMenu, \._arrMenu, newValue, notifyChanged(_arrMenu, newValue)) }
    }
    var arrInsert: Bool {
        get { access(keyPath: \.arrInsert); return _arrInsert }
        set { put(\.arrInsert, \._arrInsert, newValue, notifyChanged(_arrInsert, newValue)) }
    }
    var arrInserted: ArrSel? {
        get { access(keyPath: \.arrInserted); return _arrInserted }
        set { put(\.arrInserted, \._arrInserted, newValue, notifyChanged(_arrInserted, newValue)) }
    }
    var arrRefB: Bool {
        get { access(keyPath: \.arrRefB); return _arrRefB }
        set { put(\.arrRefB, \._arrRefB, newValue, notifyChanged(_arrRefB, newValue)) }
    }
    var rollView: Bool {
        get { access(keyPath: \.rollView); return _rollView }
        set { put(\.rollView, \._rollView, newValue, notifyChanged(_rollView, newValue)) }
    }
    var rollMenuOpen: Bool {
        get { access(keyPath: \.rollMenuOpen); return _rollMenuOpen }
        set { put(\.rollMenuOpen, \._rollMenuOpen, newValue, notifyChanged(_rollMenuOpen, newValue)) }
    }
    var rollVel: Bool {
        get { access(keyPath: \.rollVel); return _rollVel }
        set { put(\.rollVel, \._rollVel, newValue, notifyChanged(_rollVel, newValue)) }
    }
    var eqView: Bool {
        get { access(keyPath: \.eqView); return _eqView }
        set { put(\.eqView, \._eqView, newValue, notifyChanged(_eqView, newValue)) }
    }
    var eqBand: Int {
        get { access(keyPath: \.eqBand); return _eqBand }
        set { put(\.eqBand, \._eqBand, newValue, notifyChanged(_eqBand, newValue)) }
    }
    var eqListenHeld: Bool {
        get { access(keyPath: \.eqListenHeld); return _eqListenHeld }
        set { put(\.eqListenHeld, \._eqListenHeld, newValue, notifyChanged(_eqListenHeld, newValue)) }
    }
    var eqListenBand: Int {
        get { access(keyPath: \.eqListenBand); return _eqListenBand }
        set { put(\.eqListenBand, \._eqListenBand, newValue, notifyChanged(_eqListenBand, newValue)) }
    }
    var eqMenu: EqMenuState? {
        get { access(keyPath: \.eqMenu); return _eqMenu }
        set { put(\.eqMenu, \._eqMenu, newValue, notifyChanged(_eqMenu, newValue)) }
    }
    var eqMsMenu: CGRect? {
        get { access(keyPath: \.eqMsMenu); return _eqMsMenu }
        set { put(\.eqMsMenu, \._eqMsMenu, newValue, notifyChanged(_eqMsMenu, newValue)) }
    }
    var eqDynMenu: CGRect? {
        get { access(keyPath: \.eqDynMenu); return _eqDynMenu }
        set { put(\.eqDynMenu, \._eqDynMenu, newValue, notifyChanged(_eqDynMenu, newValue)) }
    }
    var eqDynShift: CGSize {
        get { access(keyPath: \.eqDynShift); return _eqDynShift }
        set { put(\.eqDynShift, \._eqDynShift, newValue, notifyChanged(_eqDynShift, newValue)) }
    }
    var eqInputAsk: EqInput? {
        get { access(keyPath: \.eqInputAsk); return _eqInputAsk }
        set { put(\.eqInputAsk, \._eqInputAsk, newValue, notifyChanged(_eqInputAsk, newValue)) }
    }
    var eqPresetMenu: EqPresetMenuState? {
        get { access(keyPath: \.eqPresetMenu); return _eqPresetMenu }
        set { put(\.eqPresetMenu, \._eqPresetMenu, newValue, notifyChanged(_eqPresetMenu, newValue)) }
    }
    var eqCompareMenu: Bool {
        get { access(keyPath: \.eqCompareMenu); return _eqCompareMenu }
        set { put(\.eqCompareMenu, \._eqCompareMenu, newValue, notifyChanged(_eqCompareMenu, newValue)) }
    }
    var eqPhones: Bool {
        get { access(keyPath: \.eqPhones); return _eqPhones }
        set { put(\.eqPhones, \._eqPhones, newValue, notifyChanged(_eqPhones, newValue)) }
    }
    var phonesName: String {
        get { access(keyPath: \.phonesName); return _phonesName }
        set { put(\.phonesName, \._phonesName, newValue, notifyChanged(_phonesName, newValue)) }
    }
    var importingPhones: Bool {
        get { access(keyPath: \.importingPhones); return _importingPhones }
        set { put(\.importingPhones, \._importingPhones, newValue, notifyChanged(_importingPhones, newValue)) }
    }
    var phonesNote: String? {
        get { access(keyPath: \.phonesNote); return _phonesNote }
        set { put(\.phonesNote, \._phonesNote, newValue, notifyChanged(_phonesNote, newValue)) }
    }
    var phonesExported: URL? {
        get { access(keyPath: \.phonesExported); return _phonesExported }
        set { put(\.phonesExported, \._phonesExported, newValue, notifyChanged(_phonesExported, newValue)) }
    }
    var gridTop: Int {
        get { access(keyPath: \.gridTop); return _gridTop }
        set { put(\.gridTop, \._gridTop, newValue, notifyChanged(_gridTop, newValue)) }
    }
    var cellMenu: CellMenuState? {
        get { access(keyPath: \.cellMenu); return _cellMenu }
        set { put(\.cellMenu, \._cellMenu, newValue, notifyChanged(_cellMenu, newValue)) }
    }
    var rowMenu: Int? {
        get { access(keyPath: \.rowMenu); return _rowMenu }
        set { put(\.rowMenu, \._rowMenu, newValue, notifyChanged(_rowMenu, newValue)) }
    }
    var gridRowsShown: Int {
        get { access(keyPath: \.gridRowsShown); return _gridRowsShown }
        set { put(\.gridRowsShown, \._gridRowsShown, newValue, notifyChanged(_gridRowsShown, newValue)) }
    }
    var clipCarry: ClipCarry? {
        get { access(keyPath: \.clipCarry); return _clipCarry }
        set { put(\.clipCarry, \._clipCarry, newValue, notifyChanged(_clipCarry, newValue)) }
    }
    var carryPoint: CGPoint {
        get { access(keyPath: \.carryPoint); return _carryPoint }
        set { put(\.carryPoint, \._carryPoint, newValue, notifyChanged(_carryPoint, newValue)) }
    }
    var deniedCell: CellRef? {
        get { access(keyPath: \.deniedCell); return _deniedCell }
        set { put(\.deniedCell, \._deniedCell, newValue, notifyChanged(_deniedCell, newValue)) }
    }
    var mix: MixTransition? {
        get { access(keyPath: \.mix); return _mix }
        set { put(\.mix, \._mix, newValue, notifyChanged(_mix, newValue)) }
    }
    var mixDropDone: Bool {
        get { access(keyPath: \.mixDropDone); return _mixDropDone }
        set { put(\.mixDropDone, \._mixDropDone, newValue, notifyChanged(_mixDropDone, newValue)) }
    }
    var choice: ChoiceState? {
        get { access(keyPath: \.choice); return _choice }
        set { put(\.choice, \._choice, newValue, notifyChanged(_choice, newValue)) }
    }
    var pianoMenuOpen: Bool {
        get { access(keyPath: \.pianoMenuOpen); return _pianoMenuOpen }
        set { put(\.pianoMenuOpen, \._pianoMenuOpen, newValue, notifyChanged(_pianoMenuOpen, newValue)) }
    }
    var samplesVersion: Int {
        get { access(keyPath: \.samplesVersion); return _samplesVersion }
        set { put(\.samplesVersion, \._samplesVersion, newValue, notifyChanged(_samplesVersion, newValue)) }
    }
    var editorOpen: Bool {
        get { access(keyPath: \.editorOpen); return _editorOpen }
        set { put(\.editorOpen, \._editorOpen, newValue, notifyChanged(_editorOpen, newValue)) }
    }
    var editorWarp: Bool {
        get { access(keyPath: \.editorWarp); return _editorWarp }
        set { put(\.editorWarp, \._editorWarp, newValue, notifyChanged(_editorWarp, newValue)) }
    }
    var warpGrid: Double {
        get { access(keyPath: \.warpGrid); return _warpGrid }
        set { put(\.warpGrid, \._warpGrid, newValue, notifyChanged(_warpGrid, newValue)) }
    }
    var warpSel: Int? {
        get { access(keyPath: \.warpSel); return _warpSel }
        set { put(\.warpSel, \._warpSel, newValue, notifyChanged(_warpSel, newValue)) }
    }
    var soundMenu: SoundMenuState? {
        get { access(keyPath: \.soundMenu); return _soundMenu }
        set { put(\.soundMenu, \._soundMenu, newValue, notifyChanged(_soundMenu, newValue)) }
    }
    var importTarget: ImportTarget? {
        get { access(keyPath: \.importTarget); return _importTarget }
        set { put(\.importTarget, \._importTarget, newValue, notifyChanged(_importTarget, newValue)) }
    }
    var importing: Bool {
        get { access(keyPath: \.importing); return _importing }
        set { put(\.importing, \._importing, newValue, notifyChanged(_importing, newValue)) }
    }
    var importingProject: Bool {
        get { access(keyPath: \.importingProject); return _importingProject }
        set { put(\.importingProject, \._importingProject, newValue, notifyChanged(_importingProject, newValue)) }
    }
    var projectImport: ProjectImport? {
        get { access(keyPath: \.projectImport); return _projectImport }
        set { put(\.projectImport, \._projectImport, newValue, notifyChanged(_projectImport, newValue)) }
    }
    var browser: BrowserMode? {
        get { access(keyPath: \.browser); return _browser }
        set { put(\.browser, \._browser, newValue, notifyChanged(_browser, newValue)) }
    }
    var libFolder: String {
        get { access(keyPath: \.libFolder); return _libFolder }
        set { put(\.libFolder, \._libFolder, newValue, notifyChanged(_libFolder, newValue)) }
    }
    var libPicked: Set<String>? {
        get { access(keyPath: \.libPicked); return _libPicked }
        set { put(\.libPicked, \._libPicked, newValue, notifyChanged(_libPicked, newValue)) }
    }
    var libNote: String {
        get { access(keyPath: \.libNote); return _libNote }
        set { put(\.libNote, \._libNote, newValue, notifyChanged(_libNote, newValue)) }
    }
    var libWarning: String? {
        get { access(keyPath: \.libWarning); return _libWarning }
        set { put(\.libWarning, \._libWarning, newValue, notifyChanged(_libWarning, newValue)) }
    }
    var importingLibrary: Bool {
        get { access(keyPath: \.importingLibrary); return _importingLibrary }
        set { put(\.importingLibrary, \._importingLibrary, newValue, notifyChanged(_importingLibrary, newValue)) }
    }
    var leftFrame: CGRect {
        get { access(keyPath: \.leftFrame); return _leftFrame }
        set { put(\.leftFrame, \._leftFrame, newValue, notifyChanged(_leftFrame, newValue)) }
    }
    var pagesFrame: CGRect {
        get { access(keyPath: \.pagesFrame); return _pagesFrame }
        set { put(\.pagesFrame, \._pagesFrame, newValue, notifyChanged(_pagesFrame, newValue)) }
    }
    var keysFrame: CGRect {
        get { access(keyPath: \.keysFrame); return _keysFrame }
        set { put(\.keysFrame, \._keysFrame, newValue, notifyChanged(_keysFrame, newValue)) }
    }
    var tracksFrame: CGRect {
        get { access(keyPath: \.tracksFrame); return _tracksFrame }
        set { put(\.tracksFrame, \._tracksFrame, newValue, notifyChanged(_tracksFrame, newValue)) }
    }
    var previewOn: Bool {
        get { access(keyPath: \.previewOn); return _previewOn }
        set { put(\.previewOn, \._previewOn, newValue, notifyChanged(_previewOn, newValue)) }
    }
    var heldFlag: Int? {
        get { access(keyPath: \.heldFlag); return _heldFlag }
        set { put(\.heldFlag, \._heldFlag, newValue, notifyChanged(_heldFlag, newValue)) }
    }
    var roleFlag: Int? {
        get { access(keyPath: \.roleFlag); return _roleFlag }
        set { put(\.roleFlag, \._roleFlag, newValue, notifyChanged(_roleFlag, newValue)) }
    }
    var trackMenu: TrackMenuState? {
        get { access(keyPath: \.trackMenu); return _trackMenu }
        set { put(\.trackMenu, \._trackMenu, newValue, notifyChanged(_trackMenu, newValue)) }
    }
    var renaming: Int? {
        get { access(keyPath: \.renaming); return _renaming }
        set { put(\.renaming, \._renaming, newValue, notifyChanged(_renaming, newValue)) }
    }
    var masterWin: Int? {
        get { access(keyPath: \.masterWin); return _masterWin }
        set { put(\.masterWin, \._masterWin, newValue, notifyChanged(_masterWin, newValue)) }
    }
    var masterMenu: MasterMenuState? {
        get { access(keyPath: \.masterMenu); return _masterMenu }
        set { put(\.masterMenu, \._masterMenu, newValue, notifyChanged(_masterMenu, newValue)) }
    }
    var masterInput: MasterInputTarget? {
        get { access(keyPath: \.masterInput); return _masterInput }
        set { put(\.masterInput, \._masterInput, newValue, notifyChanged(_masterInput, newValue)) }
    }
    var defaultFlash: Int? {
        get { access(keyPath: \.defaultFlash); return _defaultFlash }
        set { put(\.defaultFlash, \._defaultFlash, newValue, notifyChanged(_defaultFlash, newValue)) }
    }
    var defaultSaved: DefaultSaved? {
        get { access(keyPath: \.defaultSaved); return _defaultSaved }
        set { put(\.defaultSaved, \._defaultSaved, newValue, notifyChanged(_defaultSaved, newValue)) }
    }
    var heldSteps: Set<Int> {
        get { access(keyPath: \.heldSteps); return _heldSteps }
        set { put(\.heldSteps, \._heldSteps, newValue, notifyChanged(_heldSteps, newValue)) }
    }
    var heldSources: Set<Int> {
        get { access(keyPath: \.heldSources); return _heldSources }
        set { put(\.heldSources, \._heldSources, newValue, notifyChanged(_heldSources, newValue)) }
    }
    var knobFingers: Set<Int> {
        get { access(keyPath: \.knobFingers); return _knobFingers }
        set { put(\.knobFingers, \._knobFingers, newValue, notifyChanged(_knobFingers, newValue)) }
    }
    var octaves: [Int] {
        get { access(keyPath: \.octaves); return _octaves }
        set { put(\.octaves, \._octaves, newValue, notifyChanged(_octaves, newValue)) }
    }
    var chordMode: [Bool] {
        get { access(keyPath: \.chordMode); return _chordMode }
        set { put(\.chordMode, \._chordMode, newValue, notifyChanged(_chordMode, newValue)) }
    }
    var chordKind: [Int] {
        get { access(keyPath: \.chordKind); return _chordKind }
        set { put(\.chordKind, \._chordKind, newValue, notifyChanged(_chordKind, newValue)) }
    }
    var selNotes: [[Int]] {
        get { access(keyPath: \.selNotes); return _selNotes }
        set { put(\.selNotes, \._selNotes, newValue, notifyChanged(_selNotes, newValue)) }
    }
    var pressedKeys: [Int: [Int]] {
        get { access(keyPath: \.pressedKeys); return _pressedKeys }
        set { put(\.pressedKeys, \._pressedKeys, newValue, notifyChanged(_pressedKeys, newValue)) }
    }
    var arrGroup: [ArrSel] {
        get { access(keyPath: \.arrGroup); return _arrGroup }
        set { put(\.arrGroup, \._arrGroup, newValue, notifyChanged(_arrGroup, newValue)) }
    }
    var eqCompares: [Int: Int] {
        get { access(keyPath: \.eqCompares); return _eqCompares }
        set { put(\.eqCompares, \._eqCompares, newValue, notifyChanged(_eqCompares, newValue)) }
    }
    var arrDropPending: (sel: GridSelection, start: Int)? {
        get { access(keyPath: \.arrDropPending); return _arrDropPending }
        set { put(\.arrDropPending, \._arrDropPending, newValue, notifyChanged(_arrDropPending, newValue)) }
    }
    var gridMenuOpen: Bool {
        get { access(keyPath: \.gridMenuOpen); return _gridMenuOpen }
        set { put(\.gridMenuOpen, \._gridMenuOpen, newValue, notifyChanged(_gridMenuOpen, newValue)) }
    }
    var mixDrop: [Int: Int] {
        get { access(keyPath: \.mixDrop); return _mixDrop }
        set { put(\.mixDrop, \._mixDrop, newValue, notifyChanged(_mixDrop, newValue)) }
    }
    var captureFlash: Bool {
        get { access(keyPath: \.captureFlash); return _captureFlash }
        set { put(\.captureFlash, \._captureFlash, newValue, notifyChanged(_captureFlash, newValue)) }
    }
    var wavetableSerial: Int {
        get { access(keyPath: \.wavetableSerial); return _wavetableSerial }
        set { put(\.wavetableSerial, \._wavetableSerial, newValue, notifyChanged(_wavetableSerial, newValue)) }
    }
    var headCount: Int {
        get { access(keyPath: \.headCount); return _headCount }
        set { put(\.headCount, \._headCount, newValue, notifyChanged(_headCount, newValue)) }
    }
    var stemArmed: Set<Int> {
        get { access(keyPath: \.stemArmed); return _stemArmed }
        set { put(\.stemArmed, \._stemArmed, newValue, notifyChanged(_stemArmed, newValue)) }
    }
    var stemRecording: Set<Int> {
        get { access(keyPath: \.stemRecording); return _stemRecording }
        set { put(\.stemRecording, \._stemRecording, newValue, notifyChanged(_stemRecording, newValue)) }
    }
    var refusedFlag: (idx: Int, until: Double) {
        get { access(keyPath: \.refusedFlag); return _refusedFlag }
        set { put(\.refusedFlag, \._refusedFlag, newValue, notifyChanged(_refusedFlag, newValue)) }
    }
    var hasTrackClip: Bool {
        get { access(keyPath: \.hasTrackClip); return _hasTrackClip }
        set { put(\.hasTrackClip, \._hasTrackClip, newValue, notifyChanged(_hasTrackClip, newValue)) }
    }
    var scopeOn: [Bool] {
        get { access(keyPath: \.scopeOn); return _scopeOn }
        set { put(\.scopeOn, \._scopeOn, newValue, notifyChanged(_scopeOn, newValue)) }
    }
}

// Изменилось ли значение (как shouldNotifyObservers макроса @Observable): перегрузки — private в каждом файле, как у
// макроса (Playgrounds подменяет функции на лету и не находит общие перегрузки одного имени — «Replaced function»).
private func notifyChanged<T>(_ a: T, _ b: T) -> Bool { return true }
private func notifyChanged<T: Equatable>(_ a: T, _ b: T) -> Bool { return a != b }
private func notifyChanged<T: AnyObject>(_ a: T, _ b: T) -> Bool { return a !== b }
private func notifyChanged<T: Equatable & AnyObject>(_ a: T, _ b: T) -> Bool { return a != b }
