import Foundation
import Observation

// Наблюдаемые свойства AppModel простых типов (Bool, Int, рамки, необязательные значения) — вручную (S14, объём
// сборки в Playgrounds: макрос @Observable даёт на свойство ~1,8 КБ кода — замыкание withMutation, _modify и др.).
// Хранение — _имя в AppModel.swift (там же описание свойства), чтение — access, запись — put: willSet / didSet
// регистратора, как у макроса; уведомление — только если значение изменилось (как shouldNotifyObservers макроса).
// Ключ наблюдения — путь к хранимому _имя (18.11): чтение и запись — по одному ключу, у вычисляемого пути нет своих
// функций (объём сборки).
// Небольшие коллекции (зажатые шаги, по 8 дорожек) — тоже: изменение на месте — копия, она мала. Крупные коллекции и
// структуры (проект, библиотека, настройки, пресеты) — через макрос (без копии). Свойства private(set) — в AppModel.swift.

extension AppModel {
    var meterAsleep: Bool {
        get { access(keyPath: \._meterAsleep); return _meterAsleep }
        set { put(\._meterAsleep, newValue, observedChanged(_meterAsleep, newValue)) }
    }
    var openPosShown: Int {
        get { access(keyPath: \._openPosShown); return _openPosShown }
        set { put(\._openPosShown, newValue, observedChanged(_openPosShown, newValue)) }
    }
    var trackPosShown: Int {
        get { access(keyPath: \._trackPosShown); return _trackPosShown }
        set { put(\._trackPosShown, newValue, observedChanged(_trackPosShown, newValue)) }
    }
    var spaceSaved: String? {
        get { access(keyPath: \._spaceSaved); return _spaceSaved }
        set { put(\._spaceSaved, newValue, observedChanged(_spaceSaved, newValue)) }
    }
    var headOn: Bool {
        get { access(keyPath: \._headOn); return _headOn }
        set { put(\._headOn, newValue, observedChanged(_headOn, newValue)) }
    }
    var headFace: Bool {
        get { access(keyPath: \._headFace); return _headFace }
        set { put(\._headFace, newValue, observedChanged(_headFace, newValue)) }
    }
    var settingsTab: SettingsTab {
        get { access(keyPath: \._settingsTab); return _settingsTab }
        set { put(\._settingsTab, newValue, observedChanged(_settingsTab, newValue)) }
    }
    var viewPage: Int {
        get { access(keyPath: \._viewPage); return _viewPage }
        set { put(\._viewPage, newValue, observedChanged(_viewPage, newValue)) }
    }
    var spanView: Bool {
        get { access(keyPath: \._spanView); return _spanView }
        set { put(\._spanView, newValue, observedChanged(_spanView, newValue)) }
    }
    var shiftHeld: Bool {
        get { access(keyPath: \._shiftHeld); return _shiftHeld }
        set { put(\._shiftHeld, newValue, observedChanged(_shiftHeld, newValue)) }
    }
    var fxHeld: Bool {
        get { access(keyPath: \._fxHeld); return _fxHeld }
        set { put(\._fxHeld, newValue, observedChanged(_fxHeld, newValue)) }
    }
    var modHeld: Bool {
        get { access(keyPath: \._modHeld); return _modHeld }
        set { put(\._modHeld, newValue, observedChanged(_modHeld, newValue)) }
    }
    var lastPage: GridPage {
        get { access(keyPath: \._lastPage); return _lastPage }
        set { put(\._lastPage, newValue, observedChanged(_lastPage, newValue)) }
    }
    var lastSource: Int {
        get { access(keyPath: \._lastSource); return _lastSource }
        set { put(\._lastSource, newValue, observedChanged(_lastSource, newValue)) }
    }
    var fxPicCol: Int {
        get { access(keyPath: \._fxPicCol); return _fxPicCol }
        set { put(\._fxPicCol, newValue, observedChanged(_fxPicCol, newValue)) }
    }
    var fxMidiShow: Bool {
        get { access(keyPath: \._fxMidiShow); return _fxMidiShow }
        set { put(\._fxMidiShow, newValue, observedChanged(_fxMidiShow, newValue)) }
    }
    var morph: Bool {
        get { access(keyPath: \._morph); return _morph }
        set { put(\._morph, newValue, observedChanged(_morph, newValue)) }
    }
    var morphHeld: Bool {
        get { access(keyPath: \._morphHeld); return _morphHeld }
        set { put(\._morphHeld, newValue, observedChanged(_morphHeld, newValue)) }
    }
    var morphUsed: Bool {
        get { access(keyPath: \._morphUsed); return _morphUsed }
        set { put(\._morphUsed, newValue, observedChanged(_morphUsed, newValue)) }
    }
    var morphAllHeld: Bool {
        get { access(keyPath: \._morphAllHeld); return _morphAllHeld }
        set { put(\._morphAllHeld, newValue, observedChanged(_morphAllHeld, newValue)) }
    }
    var pageMenu: PageMenuState? {
        get { access(keyPath: \._pageMenu); return _pageMenu }
        set { put(\._pageMenu, newValue, observedChanged(_pageMenu, newValue)) }
    }
    var recOn: Bool {
        get { access(keyPath: \._recOn); return _recOn }
        set { put(\._recOn, newValue, observedChanged(_recOn, newValue)) }
    }
    var arrAuto: Bool {
        get { access(keyPath: \._arrAuto); return _arrAuto }
        set { put(\._arrAuto, newValue, observedChanged(_arrAuto, newValue)) }
    }
    var arrRecArm: Bool {
        get { access(keyPath: \._arrRecArm); return _arrRecArm }
        set { put(\._arrRecArm, newValue, observedChanged(_arrRecArm, newValue)) }
    }
    var arrPlayEnd: Int {
        get { access(keyPath: \._arrPlayEnd); return _arrPlayEnd }
        set { put(\._arrPlayEnd, newValue, observedChanged(_arrPlayEnd, newValue)) }
    }
    var arrPlay: Bool {
        get { access(keyPath: \._arrPlay); return _arrPlay }
        set { put(\._arrPlay, newValue, observedChanged(_arrPlay, newValue)) }
    }
    var arrDraw: Bool {
        get { access(keyPath: \._arrDraw); return _arrDraw }
        set { put(\._arrDraw, newValue, observedChanged(_arrDraw, newValue)) }
    }
    var arrAutoId: String {
        get { access(keyPath: \._arrAutoId); return _arrAutoId }
        set { put(\._arrAutoId, newValue, observedChanged(_arrAutoId, newValue)) }
    }
    var chordMenuOpen: Bool {
        get { access(keyPath: \._chordMenuOpen); return _chordMenuOpen }
        set { put(\._chordMenuOpen, newValue, observedChanged(_chordMenuOpen, newValue)) }
    }
    var patternView: Bool {
        get { access(keyPath: \._patternView); return _patternView }
        set { put(\._patternView, newValue, observedChanged(_patternView, newValue)) }
    }
    var arrangeView: Bool {
        get { access(keyPath: \._arrangeView); return _arrangeView }
        set { put(\._arrangeView, newValue, observedChanged(_arrangeView, newValue)) }
    }
    var arrCursor: Int {
        get { access(keyPath: \._arrCursor); return _arrCursor }
        set { put(\._arrCursor, newValue, observedChanged(_arrCursor, newValue)) }
    }
    var arrSel: ArrSel? {
        get { access(keyPath: \._arrSel); return _arrSel }
        set { put(\._arrSel, newValue, observedChanged(_arrSel, newValue)) }
    }
    var arrMarquee: CGRect? {
        get { access(keyPath: \._arrMarquee); return _arrMarquee }
        set { put(\._arrMarquee, newValue, observedChanged(_arrMarquee, newValue)) }
    }
    var arrKnobs: Bool {
        get { access(keyPath: \._arrKnobs); return _arrKnobs }
        set { put(\._arrKnobs, newValue, observedChanged(_arrKnobs, newValue)) }
    }
    var arrLowerH: CGFloat {
        get { access(keyPath: \._arrLowerH); return _arrLowerH }
        set { put(\._arrLowerH, newValue, observedChanged(_arrLowerH, newValue)) }
    }
    var barH: CGFloat {
        get { access(keyPath: \._barH); return _barH }
        set { put(\._barH, newValue, observedChanged(_barH, newValue)) }
    }
    var arrMenu: ArrMenuState? {
        get { access(keyPath: \._arrMenu); return _arrMenu }
        set { put(\._arrMenu, newValue, observedChanged(_arrMenu, newValue)) }
    }
    var arrInsert: Bool {
        get { access(keyPath: \._arrInsert); return _arrInsert }
        set { put(\._arrInsert, newValue, observedChanged(_arrInsert, newValue)) }
    }
    var arrInserted: ArrSel? {
        get { access(keyPath: \._arrInserted); return _arrInserted }
        set { put(\._arrInserted, newValue, observedChanged(_arrInserted, newValue)) }
    }
    var arrRefB: Bool {
        get { access(keyPath: \._arrRefB); return _arrRefB }
        set { put(\._arrRefB, newValue, observedChanged(_arrRefB, newValue)) }
    }
    var rollView: Bool {
        get { access(keyPath: \._rollView); return _rollView }
        set { put(\._rollView, newValue, observedChanged(_rollView, newValue)) }
    }
    var rollMenuOpen: Bool {
        get { access(keyPath: \._rollMenuOpen); return _rollMenuOpen }
        set { put(\._rollMenuOpen, newValue, observedChanged(_rollMenuOpen, newValue)) }
    }
    var rollVel: Bool {
        get { access(keyPath: \._rollVel); return _rollVel }
        set { put(\._rollVel, newValue, observedChanged(_rollVel, newValue)) }
    }
    var eqView: Bool {
        get { access(keyPath: \._eqView); return _eqView }
        set { put(\._eqView, newValue, observedChanged(_eqView, newValue)) }
    }
    var eqBand: Int {
        get { access(keyPath: \._eqBand); return _eqBand }
        set { put(\._eqBand, newValue, observedChanged(_eqBand, newValue)) }
    }
    var eqListenHeld: Bool {
        get { access(keyPath: \._eqListenHeld); return _eqListenHeld }
        set { put(\._eqListenHeld, newValue, observedChanged(_eqListenHeld, newValue)) }
    }
    var eqListenBand: Int {
        get { access(keyPath: \._eqListenBand); return _eqListenBand }
        set { put(\._eqListenBand, newValue, observedChanged(_eqListenBand, newValue)) }
    }
    var eqMenu: EqMenuState? {
        get { access(keyPath: \._eqMenu); return _eqMenu }
        set { put(\._eqMenu, newValue, observedChanged(_eqMenu, newValue)) }
    }
    var translationMenu: CGRect? {
        get { access(keyPath: \._translationMenu); return _translationMenu }
        set { put(\._translationMenu, newValue, observedChanged(_translationMenu, newValue)) }
    }
    var eqMsMenu: CGRect? {
        get { access(keyPath: \._eqMsMenu); return _eqMsMenu }
        set { put(\._eqMsMenu, newValue, observedChanged(_eqMsMenu, newValue)) }
    }
    var eqDynMenu: CGRect? {
        get { access(keyPath: \._eqDynMenu); return _eqDynMenu }
        set { put(\._eqDynMenu, newValue, observedChanged(_eqDynMenu, newValue)) }
    }
    var eqDynShift: CGSize {
        get { access(keyPath: \._eqDynShift); return _eqDynShift }
        set { put(\._eqDynShift, newValue, observedChanged(_eqDynShift, newValue)) }
    }
    var eqInputAsk: EqInput? {
        get { access(keyPath: \._eqInputAsk); return _eqInputAsk }
        set { put(\._eqInputAsk, newValue, observedChanged(_eqInputAsk, newValue)) }
    }
    var eqPresetMenu: EqPresetMenuState? {
        get { access(keyPath: \._eqPresetMenu); return _eqPresetMenu }
        set { put(\._eqPresetMenu, newValue, observedChanged(_eqPresetMenu, newValue)) }
    }
    var eqCompareMenu: Bool {
        get { access(keyPath: \._eqCompareMenu); return _eqCompareMenu }
        set { put(\._eqCompareMenu, newValue, observedChanged(_eqCompareMenu, newValue)) }
    }
    var eqPhones: Bool {
        get { access(keyPath: \._eqPhones); return _eqPhones }
        set { put(\._eqPhones, newValue, observedChanged(_eqPhones, newValue)) }
    }
    var phonesName: String {
        get { access(keyPath: \._phonesName); return _phonesName }
        set { put(\._phonesName, newValue, observedChanged(_phonesName, newValue)) }
    }
    var importingPhones: Bool {
        get { access(keyPath: \._importingPhones); return _importingPhones }
        set { put(\._importingPhones, newValue, observedChanged(_importingPhones, newValue)) }
    }
    var phonesNote: String? {
        get { access(keyPath: \._phonesNote); return _phonesNote }
        set { put(\._phonesNote, newValue, observedChanged(_phonesNote, newValue)) }
    }
    var phonesExported: URL? {
        get { access(keyPath: \._phonesExported); return _phonesExported }
        set { put(\._phonesExported, newValue, observedChanged(_phonesExported, newValue)) }
    }
    var gridTop: Int {
        get { access(keyPath: \._gridTop); return _gridTop }
        set { put(\._gridTop, newValue, observedChanged(_gridTop, newValue)) }
    }
    var cellMenu: CellMenuState? {
        get { access(keyPath: \._cellMenu); return _cellMenu }
        set { put(\._cellMenu, newValue, observedChanged(_cellMenu, newValue)) }
    }
    var rowMenu: Int? {
        get { access(keyPath: \._rowMenu); return _rowMenu }
        set { put(\._rowMenu, newValue, observedChanged(_rowMenu, newValue)) }
    }
    var gridRowsShown: Int {
        get { access(keyPath: \._gridRowsShown); return _gridRowsShown }
        set { put(\._gridRowsShown, newValue, observedChanged(_gridRowsShown, newValue)) }
    }
    var clipCarry: ClipCarry? {
        get { access(keyPath: \._clipCarry); return _clipCarry }
        set { put(\._clipCarry, newValue, observedChanged(_clipCarry, newValue)) }
    }
    var carryPoint: CGPoint {
        get { access(keyPath: \._carryPoint); return _carryPoint }
        set { put(\._carryPoint, newValue, observedChanged(_carryPoint, newValue)) }
    }
    var deniedCell: CellRef? {
        get { access(keyPath: \._deniedCell); return _deniedCell }
        set { put(\._deniedCell, newValue, observedChanged(_deniedCell, newValue)) }
    }
    var mix: MixTransition? {
        get { access(keyPath: \._mix); return _mix }
        set { put(\._mix, newValue, observedChanged(_mix, newValue)) }
    }
    var mixDropDone: Bool {
        get { access(keyPath: \._mixDropDone); return _mixDropDone }
        set { put(\._mixDropDone, newValue, observedChanged(_mixDropDone, newValue)) }
    }
    var choice: ChoiceState? {
        get { access(keyPath: \._choice); return _choice }
        set { put(\._choice, newValue, observedChanged(_choice, newValue)) }
    }
    var pianoMenuOpen: Bool {
        get { access(keyPath: \._pianoMenuOpen); return _pianoMenuOpen }
        set { put(\._pianoMenuOpen, newValue, observedChanged(_pianoMenuOpen, newValue)) }
    }
    var samplesVersion: Int {
        get { access(keyPath: \._samplesVersion); return _samplesVersion }
        set { put(\._samplesVersion, newValue, observedChanged(_samplesVersion, newValue)) }
    }
    var editorOpen: Bool {
        get { access(keyPath: \._editorOpen); return _editorOpen }
        set { put(\._editorOpen, newValue, observedChanged(_editorOpen, newValue)) }
    }
    var editorWarp: Bool {
        get { access(keyPath: \._editorWarp); return _editorWarp }
        set { put(\._editorWarp, newValue, observedChanged(_editorWarp, newValue)) }
    }
    var warpGrid: Double {
        get { access(keyPath: \._warpGrid); return _warpGrid }
        set { put(\._warpGrid, newValue, observedChanged(_warpGrid, newValue)) }
    }
    var warpSel: Int? {
        get { access(keyPath: \._warpSel); return _warpSel }
        set { put(\._warpSel, newValue, observedChanged(_warpSel, newValue)) }
    }
    var soundMenu: SoundMenuState? {
        get { access(keyPath: \._soundMenu); return _soundMenu }
        set { put(\._soundMenu, newValue, observedChanged(_soundMenu, newValue)) }
    }
    var importTarget: ImportTarget? {
        get { access(keyPath: \._importTarget); return _importTarget }
        set { put(\._importTarget, newValue, observedChanged(_importTarget, newValue)) }
    }
    var importing: Bool {
        get { access(keyPath: \._importing); return _importing }
        set { put(\._importing, newValue, observedChanged(_importing, newValue)) }
    }
    var importingProject: Bool {
        get { access(keyPath: \._importingProject); return _importingProject }
        set { put(\._importingProject, newValue, observedChanged(_importingProject, newValue)) }
    }
    var projectImport: ProjectImport? {
        get { access(keyPath: \._projectImport); return _projectImport }
        set { put(\._projectImport, newValue, observedChanged(_projectImport, newValue)) }
    }
    var browser: BrowserMode? {
        get { access(keyPath: \._browser); return _browser }
        set { put(\._browser, newValue, observedChanged(_browser, newValue)) }
    }
    var libFolder: String {
        get { access(keyPath: \._libFolder); return _libFolder }
        set { put(\._libFolder, newValue, observedChanged(_libFolder, newValue)) }
    }
    var libPicked: Set<String>? {
        get { access(keyPath: \._libPicked); return _libPicked }
        set { put(\._libPicked, newValue, observedChanged(_libPicked, newValue)) }
    }
    var libNote: String {
        get { access(keyPath: \._libNote); return _libNote }
        set { put(\._libNote, newValue, observedChanged(_libNote, newValue)) }
    }
    var libWarning: String? {
        get { access(keyPath: \._libWarning); return _libWarning }
        set { put(\._libWarning, newValue, observedChanged(_libWarning, newValue)) }
    }
    var importingLibrary: Bool {
        get { access(keyPath: \._importingLibrary); return _importingLibrary }
        set { put(\._importingLibrary, newValue, observedChanged(_importingLibrary, newValue)) }
    }
    var leftFrame: CGRect {
        get { access(keyPath: \._leftFrame); return _leftFrame }
        set { put(\._leftFrame, newValue, observedChanged(_leftFrame, newValue)) }
    }
    var pagesFrame: CGRect {
        get { access(keyPath: \._pagesFrame); return _pagesFrame }
        set { put(\._pagesFrame, newValue, observedChanged(_pagesFrame, newValue)) }
    }
    var keysFrame: CGRect {
        get { access(keyPath: \._keysFrame); return _keysFrame }
        set { put(\._keysFrame, newValue, observedChanged(_keysFrame, newValue)) }
    }
    var tracksFrame: CGRect {
        get { access(keyPath: \._tracksFrame); return _tracksFrame }
        set { put(\._tracksFrame, newValue, observedChanged(_tracksFrame, newValue)) }
    }
    var previewOn: Bool {
        get { access(keyPath: \._previewOn); return _previewOn }
        set { put(\._previewOn, newValue, observedChanged(_previewOn, newValue)) }
    }
    var heldFlag: Int? {
        get { access(keyPath: \._heldFlag); return _heldFlag }
        set { put(\._heldFlag, newValue, observedChanged(_heldFlag, newValue)) }
    }
    var roleFlag: Int? {
        get { access(keyPath: \._roleFlag); return _roleFlag }
        set { put(\._roleFlag, newValue, observedChanged(_roleFlag, newValue)) }
    }
    var trackMenu: TrackMenuState? {
        get { access(keyPath: \._trackMenu); return _trackMenu }
        set { put(\._trackMenu, newValue, observedChanged(_trackMenu, newValue)) }
    }
    var renaming: Int? {
        get { access(keyPath: \._renaming); return _renaming }
        set { put(\._renaming, newValue, observedChanged(_renaming, newValue)) }
    }
    var masterWin: Int? {
        get { access(keyPath: \._masterWin); return _masterWin }
        set { put(\._masterWin, newValue, observedChanged(_masterWin, newValue)) }
    }
    var masterMenu: MasterMenuState? {
        get { access(keyPath: \._masterMenu); return _masterMenu }
        set { put(\._masterMenu, newValue, observedChanged(_masterMenu, newValue)) }
    }
    var makeupState: Int {
        get { access(keyPath: \._makeupState); return _makeupState }
        set { put(\._makeupState, newValue, observedChanged(_makeupState, newValue)) }
    }
    var masterUnity: Bool {
        get { access(keyPath: \._masterUnity); return _masterUnity }
        set { put(\._masterUnity, newValue, observedChanged(_masterUnity, newValue)) }
    }
    var masterInput: MasterInputTarget? {
        get { access(keyPath: \._masterInput); return _masterInput }
        set { put(\._masterInput, newValue, observedChanged(_masterInput, newValue)) }
    }
    var defaultFlash: Int? {
        get { access(keyPath: \._defaultFlash); return _defaultFlash }
        set { put(\._defaultFlash, newValue, observedChanged(_defaultFlash, newValue)) }
    }
    var defaultSaved: DefaultSaved? {
        get { access(keyPath: \._defaultSaved); return _defaultSaved }
        set { put(\._defaultSaved, newValue, observedChanged(_defaultSaved, newValue)) }
    }
    var heldSteps: Set<Int> {
        get { access(keyPath: \._heldSteps); return _heldSteps }
        set { put(\._heldSteps, newValue, observedChanged(_heldSteps, newValue)) }
    }
    var heldSources: Set<Int> {
        get { access(keyPath: \._heldSources); return _heldSources }
        set { put(\._heldSources, newValue, observedChanged(_heldSources, newValue)) }
    }
    var knobFingers: Set<Int> {
        get { access(keyPath: \._knobFingers); return _knobFingers }
        set { put(\._knobFingers, newValue, observedChanged(_knobFingers, newValue)) }
    }
    /// Октавы клавиатуры дорожек по местам (хранятся в проекте у дорожки — Track.keyOctave), до Params.maxTracks.
    var octaves: [Int] {
        let ts: [Track] = project.tracks
        return (0..<Params.maxTracks).map { $0 < ts.count ? ts[$0].keyOctave : Scales.octaveDef }
    }
    var chordMode: [Bool] {
        get { access(keyPath: \._chordMode); return _chordMode }
        set { put(\._chordMode, newValue, observedChanged(_chordMode, newValue)) }
    }
    var chordKind: [Int] {
        get { access(keyPath: \._chordKind); return _chordKind }
        set { put(\._chordKind, newValue, observedChanged(_chordKind, newValue)) }
    }
    var partType: [Int] {
        get { access(keyPath: \._partType); return _partType }
        set { put(\._partType, newValue, observedChanged(_partType, newValue)) }
    }
    var selNotes: [[Int]] {
        get { access(keyPath: \._selNotes); return _selNotes }
        set { put(\._selNotes, newValue, observedChanged(_selNotes, newValue)) }
    }
    var pressedKeys: [Int: [Int]] {
        get { access(keyPath: \._pressedKeys); return _pressedKeys }
        set { put(\._pressedKeys, newValue, observedChanged(_pressedKeys, newValue)) }
    }
    var arrGroup: [ArrSel] {
        get { access(keyPath: \._arrGroup); return _arrGroup }
        set { put(\._arrGroup, newValue, observedChanged(_arrGroup, newValue)) }
    }
    var eqCompares: [Int: Int] {
        get { access(keyPath: \._eqCompares); return _eqCompares }
        set { put(\._eqCompares, newValue, observedChanged(_eqCompares, newValue)) }
    }
    var arrDropPending: (sel: GridSelection, start: Int)? {
        get { access(keyPath: \._arrDropPending); return _arrDropPending }
        set { put(\._arrDropPending, newValue, observedChanged(_arrDropPending, newValue)) }
    }
    var gridMenuOpen: Bool {
        get { access(keyPath: \._gridMenuOpen); return _gridMenuOpen }
        set { put(\._gridMenuOpen, newValue, observedChanged(_gridMenuOpen, newValue)) }
    }
    var mixDrop: [Int: Int] {
        get { access(keyPath: \._mixDrop); return _mixDrop }
        set { put(\._mixDrop, newValue, observedChanged(_mixDrop, newValue)) }
    }
    var captureFlash: Bool {
        get { access(keyPath: \._captureFlash); return _captureFlash }
        set { put(\._captureFlash, newValue, observedChanged(_captureFlash, newValue)) }
    }
    var wavetableSerial: Int {
        get { access(keyPath: \._wavetableSerial); return _wavetableSerial }
        set { put(\._wavetableSerial, newValue, observedChanged(_wavetableSerial, newValue)) }
    }
    var headCount: Int {
        get { access(keyPath: \._headCount); return _headCount }
        set { put(\._headCount, newValue, observedChanged(_headCount, newValue)) }
    }
    var stemArmed: Set<Int> {
        get { access(keyPath: \._stemArmed); return _stemArmed }
        set { put(\._stemArmed, newValue, observedChanged(_stemArmed, newValue)) }
    }
    var stemRecording: Set<Int> {
        get { access(keyPath: \._stemRecording); return _stemRecording }
        set { put(\._stemRecording, newValue, observedChanged(_stemRecording, newValue)) }
    }
    var refusedFlag: (idx: Int, until: Double) {
        get { access(keyPath: \._refusedFlag); return _refusedFlag }
        set { put(\._refusedFlag, newValue, observedChanged(_refusedFlag, newValue)) }
    }
    var hasTrackClip: Bool {
        get { access(keyPath: \._hasTrackClip); return _hasTrackClip }
        set { put(\._hasTrackClip, newValue, observedChanged(_hasTrackClip, newValue)) }
    }
    var scopeOn: [Bool] {
        get { access(keyPath: \._scopeOn); return _scopeOn }
        set { put(\._scopeOn, newValue, observedChanged(_scopeOn, newValue)) }
    }
    var mixMode: Int {
        get { access(keyPath: \._mixMode); return _mixMode }
        set { put(\._mixMode, newValue, _mixMode != newValue) }
    }
    var mixerOpen: Bool {
        get { access(keyPath: \._mixerOpen); return _mixerOpen }
        set { put(\._mixerOpen, newValue, _mixerOpen != newValue) }
    }
    var session: ProjectSession {
        get { access(keyPath: \._session); return _session }
        set { put(\._session, newValue, observedChanged(_session, newValue)) }
    }
    var projectList: [ProjectInfo] {
        get { access(keyPath: \._projectList); return _projectList }
        set { put(\._projectList, newValue, observedChanged(_projectList, newValue)) }
    }
    var arrPort: ArrPort {
        get { access(keyPath: \._arrPort); return _arrPort }
        set { put(\._arrPort, newValue, observedChanged(_arrPort, newValue)) }
    }
    var songFormat: SongFormat {
        get { access(keyPath: \._songFormat); return _songFormat }
        set { put(\._songFormat, newValue, observedChanged(_songFormat, newValue)) }
    }
    var songExport: SongExportState {
        get { access(keyPath: \._songExport); return _songExport }
        set { put(\._songExport, newValue, observedChanged(_songExport, newValue)) }
    }
    var refWave: RefWave? {
        get { access(keyPath: \._refWave); return _refWave }
        set { put(\._refWave, newValue, observedChanged(_refWave, newValue)) }
    }
    var refHeardTenths: Int {
        get { access(keyPath: \._refHeardTenths); return _refHeardTenths }
        set { put(\._refHeardTenths, newValue, observedChanged(_refHeardTenths, newValue)) }
    }
    var monitorUndo: [MonitorSnap] {
        get { access(keyPath: \._monitorUndo); return _monitorUndo }
        set { put(\._monitorUndo, newValue, observedChanged(_monitorUndo, newValue)) }
    }
    var monitorRedo: [MonitorSnap] {
        get { access(keyPath: \._monitorRedo); return _monitorRedo }
        set { put(\._monitorRedo, newValue, observedChanged(_monitorRedo, newValue)) }
    }
    var gridSel: GridSelection {
        get { access(keyPath: \._gridSel); return _gridSel }
        set { put(\._gridSel, newValue, observedChanged(_gridSel, newValue)) }
    }
    var topFrames: TopFrames {
        get { access(keyPath: \._topFrames); return _topFrames }
        set { put(\._topFrames, newValue, observedChanged(_topFrames, newValue)) }
    }
    var libTableAsk: [TableImport] {
        get { access(keyPath: \._libTableAsk); return _libTableAsk }
        set { put(\._libTableAsk, newValue, observedChanged(_libTableAsk, newValue)) }
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
