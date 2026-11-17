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
        get { access(keyPath: \.obs._meterAsleep); return obs._meterAsleep }
        set { put(\.obs._meterAsleep, newValue, observedChanged(obs._meterAsleep, newValue)) }
    }
    var openPosShown: Int {
        get { access(keyPath: \.obs._openPosShown); return obs._openPosShown }
        set { put(\.obs._openPosShown, newValue, observedChanged(obs._openPosShown, newValue)) }
    }
    var trackPosShown: Int {
        get { access(keyPath: \.obs._trackPosShown); return obs._trackPosShown }
        set { put(\.obs._trackPosShown, newValue, observedChanged(obs._trackPosShown, newValue)) }
    }
    var spaceSaved: String? {
        get { access(keyPath: \.obs._spaceSaved); return obs._spaceSaved }
        set { put(\.obs._spaceSaved, newValue, observedChanged(obs._spaceSaved, newValue)) }
    }
    var headOn: Bool {
        get { access(keyPath: \.obs._headOn); return obs._headOn }
        set { put(\.obs._headOn, newValue, observedChanged(obs._headOn, newValue)) }
    }
    var headFace: Bool {
        get { access(keyPath: \.obs._headFace); return obs._headFace }
        set { put(\.obs._headFace, newValue, observedChanged(obs._headFace, newValue)) }
    }
    var settingsTab: SettingsTab {
        get { access(keyPath: \.obs._settingsTab); return obs._settingsTab }
        set { put(\.obs._settingsTab, newValue, observedChanged(obs._settingsTab, newValue)) }
    }
    var viewPage: Int {
        get { access(keyPath: \.obs._viewPage); return obs._viewPage }
        set { put(\.obs._viewPage, newValue, observedChanged(obs._viewPage, newValue)) }
    }
    var spanView: Bool {
        get { access(keyPath: \.obs._spanView); return obs._spanView }
        set { put(\.obs._spanView, newValue, observedChanged(obs._spanView, newValue)) }
    }
    var shiftHeld: Bool {
        get { access(keyPath: \.obs._shiftHeld); return obs._shiftHeld }
        set { put(\.obs._shiftHeld, newValue, observedChanged(obs._shiftHeld, newValue)) }
    }
    var fxHeld: Bool {
        get { access(keyPath: \.obs._fxHeld); return obs._fxHeld }
        set { put(\.obs._fxHeld, newValue, observedChanged(obs._fxHeld, newValue)) }
    }
    var modHeld: Bool {
        get { access(keyPath: \.obs._modHeld); return obs._modHeld }
        set { put(\.obs._modHeld, newValue, observedChanged(obs._modHeld, newValue)) }
    }
    var lastPage: GridPage {
        get { access(keyPath: \.obs._lastPage); return obs._lastPage }
        set { put(\.obs._lastPage, newValue, observedChanged(obs._lastPage, newValue)) }
    }
    var lastSource: Int {
        get { access(keyPath: \.obs._lastSource); return obs._lastSource }
        set { put(\.obs._lastSource, newValue, observedChanged(obs._lastSource, newValue)) }
    }
    var fxPicCol: Int {
        get { access(keyPath: \.obs._fxPicCol); return obs._fxPicCol }
        set { put(\.obs._fxPicCol, newValue, observedChanged(obs._fxPicCol, newValue)) }
    }
    var fxMidiShow: Bool {
        get { access(keyPath: \.obs._fxMidiShow); return obs._fxMidiShow }
        set { put(\.obs._fxMidiShow, newValue, observedChanged(obs._fxMidiShow, newValue)) }
    }
    var morph: Bool {
        get { access(keyPath: \.obs._morph); return obs._morph }
        set { put(\.obs._morph, newValue, observedChanged(obs._morph, newValue)) }
    }
    var morphHeld: Bool {
        get { access(keyPath: \.obs._morphHeld); return obs._morphHeld }
        set { put(\.obs._morphHeld, newValue, observedChanged(obs._morphHeld, newValue)) }
    }
    var morphUsed: Bool {
        get { access(keyPath: \.obs._morphUsed); return obs._morphUsed }
        set { put(\.obs._morphUsed, newValue, observedChanged(obs._morphUsed, newValue)) }
    }
    var morphAllHeld: Bool {
        get { access(keyPath: \.obs._morphAllHeld); return obs._morphAllHeld }
        set { put(\.obs._morphAllHeld, newValue, observedChanged(obs._morphAllHeld, newValue)) }
    }
    var pageMenu: PageMenuState? {
        get { access(keyPath: \.obs._pageMenu); return obs._pageMenu }
        set { put(\.obs._pageMenu, newValue, observedChanged(obs._pageMenu, newValue)) }
    }
    var recOn: Bool {
        get { access(keyPath: \.obs._recOn); return obs._recOn }
        set { put(\.obs._recOn, newValue, observedChanged(obs._recOn, newValue)) }
    }
    var arrAuto: Bool {
        get { access(keyPath: \.obs._arrAuto); return obs._arrAuto }
        set { put(\.obs._arrAuto, newValue, observedChanged(obs._arrAuto, newValue)) }
    }
    var arrRecArm: Bool {
        get { access(keyPath: \.obs._arrRecArm); return obs._arrRecArm }
        set { put(\.obs._arrRecArm, newValue, observedChanged(obs._arrRecArm, newValue)) }
    }
    var arrPlayEnd: Int {
        get { access(keyPath: \.obs._arrPlayEnd); return obs._arrPlayEnd }
        set { put(\.obs._arrPlayEnd, newValue, observedChanged(obs._arrPlayEnd, newValue)) }
    }
    var arrPlay: Bool {
        get { access(keyPath: \.obs._arrPlay); return obs._arrPlay }
        set { put(\.obs._arrPlay, newValue, observedChanged(obs._arrPlay, newValue)) }
    }
    var arrDraw: Bool {
        get { access(keyPath: \.obs._arrDraw); return obs._arrDraw }
        set { put(\.obs._arrDraw, newValue, observedChanged(obs._arrDraw, newValue)) }
    }
    var arrAutoId: String {
        get { access(keyPath: \.obs._arrAutoId); return obs._arrAutoId }
        set { put(\.obs._arrAutoId, newValue, observedChanged(obs._arrAutoId, newValue)) }
    }
    var chordMenuOpen: Bool {
        get { access(keyPath: \.obs._chordMenuOpen); return obs._chordMenuOpen }
        set { put(\.obs._chordMenuOpen, newValue, observedChanged(obs._chordMenuOpen, newValue)) }
    }
    var patternView: Bool {
        get { access(keyPath: \.obs._patternView); return obs._patternView }
        set { put(\.obs._patternView, newValue, observedChanged(obs._patternView, newValue)) }
    }
    var arrangeView: Bool {
        get { access(keyPath: \.obs._arrangeView); return obs._arrangeView }
        set { put(\.obs._arrangeView, newValue, observedChanged(obs._arrangeView, newValue)) }
    }
    var arrCursor: Int {
        get { access(keyPath: \.obs._arrCursor); return obs._arrCursor }
        set { put(\.obs._arrCursor, newValue, observedChanged(obs._arrCursor, newValue)) }
    }
    var arrSel: ArrSel? {
        get { access(keyPath: \.obs._arrSel); return obs._arrSel }
        set { put(\.obs._arrSel, newValue, observedChanged(obs._arrSel, newValue)) }
    }
    var arrMarquee: CGRect? {
        get { access(keyPath: \.obs._arrMarquee); return obs._arrMarquee }
        set { put(\.obs._arrMarquee, newValue, observedChanged(obs._arrMarquee, newValue)) }
    }
    var arrKnobs: Bool {
        get { access(keyPath: \.obs._arrKnobs); return obs._arrKnobs }
        set { put(\.obs._arrKnobs, newValue, observedChanged(obs._arrKnobs, newValue)) }
    }
    var arrLowerH: CGFloat {
        get { access(keyPath: \.obs._arrLowerH); return obs._arrLowerH }
        set { put(\.obs._arrLowerH, newValue, observedChanged(obs._arrLowerH, newValue)) }
    }
    var barH: CGFloat {
        get { access(keyPath: \.obs._barH); return obs._barH }
        set { put(\.obs._barH, newValue, observedChanged(obs._barH, newValue)) }
    }
    var arrMenu: ArrMenuState? {
        get { access(keyPath: \.obs._arrMenu); return obs._arrMenu }
        set { put(\.obs._arrMenu, newValue, observedChanged(obs._arrMenu, newValue)) }
    }
    var arrInsert: Bool {
        get { access(keyPath: \.obs._arrInsert); return obs._arrInsert }
        set { put(\.obs._arrInsert, newValue, observedChanged(obs._arrInsert, newValue)) }
    }
    var arrInserted: ArrSel? {
        get { access(keyPath: \.obs._arrInserted); return obs._arrInserted }
        set { put(\.obs._arrInserted, newValue, observedChanged(obs._arrInserted, newValue)) }
    }
    var arrRefB: Bool {
        get { access(keyPath: \.obs._arrRefB); return obs._arrRefB }
        set { put(\.obs._arrRefB, newValue, observedChanged(obs._arrRefB, newValue)) }
    }
    var rollView: Bool {
        get { access(keyPath: \.obs._rollView); return obs._rollView }
        set { put(\.obs._rollView, newValue, observedChanged(obs._rollView, newValue)) }
    }
    var rollMenuOpen: Bool {
        get { access(keyPath: \.obs._rollMenuOpen); return obs._rollMenuOpen }
        set { put(\.obs._rollMenuOpen, newValue, observedChanged(obs._rollMenuOpen, newValue)) }
    }
    var rollVel: Bool {
        get { access(keyPath: \.obs._rollVel); return obs._rollVel }
        set { put(\.obs._rollVel, newValue, observedChanged(obs._rollVel, newValue)) }
    }
    var eqView: Bool {
        get { access(keyPath: \.obs._eqView); return obs._eqView }
        set { put(\.obs._eqView, newValue, observedChanged(obs._eqView, newValue)) }
    }
    var eqBand: Int {
        get { access(keyPath: \.obs._eqBand); return obs._eqBand }
        set { put(\.obs._eqBand, newValue, observedChanged(obs._eqBand, newValue)) }
    }
    var eqListenHeld: Bool {
        get { access(keyPath: \.obs._eqListenHeld); return obs._eqListenHeld }
        set { put(\.obs._eqListenHeld, newValue, observedChanged(obs._eqListenHeld, newValue)) }
    }
    var eqListenBand: Int {
        get { access(keyPath: \.obs._eqListenBand); return obs._eqListenBand }
        set { put(\.obs._eqListenBand, newValue, observedChanged(obs._eqListenBand, newValue)) }
    }
    var eqMenu: EqMenuState? {
        get { access(keyPath: \.obs._eqMenu); return obs._eqMenu }
        set { put(\.obs._eqMenu, newValue, observedChanged(obs._eqMenu, newValue)) }
    }
    var translationMenu: CGRect? {
        get { access(keyPath: \.obs._translationMenu); return obs._translationMenu }
        set { put(\.obs._translationMenu, newValue, observedChanged(obs._translationMenu, newValue)) }
    }
    var eqMsMenu: CGRect? {
        get { access(keyPath: \.obs._eqMsMenu); return obs._eqMsMenu }
        set { put(\.obs._eqMsMenu, newValue, observedChanged(obs._eqMsMenu, newValue)) }
    }
    var eqDynMenu: CGRect? {
        get { access(keyPath: \.obs._eqDynMenu); return obs._eqDynMenu }
        set { put(\.obs._eqDynMenu, newValue, observedChanged(obs._eqDynMenu, newValue)) }
    }
    var eqDynShift: CGSize {
        get { access(keyPath: \.obs._eqDynShift); return obs._eqDynShift }
        set { put(\.obs._eqDynShift, newValue, observedChanged(obs._eqDynShift, newValue)) }
    }
    var eqInputAsk: EqInput? {
        get { access(keyPath: \.obs._eqInputAsk); return obs._eqInputAsk }
        set { put(\.obs._eqInputAsk, newValue, observedChanged(obs._eqInputAsk, newValue)) }
    }
    var eqPresetMenu: EqPresetMenuState? {
        get { access(keyPath: \.obs._eqPresetMenu); return obs._eqPresetMenu }
        set { put(\.obs._eqPresetMenu, newValue, observedChanged(obs._eqPresetMenu, newValue)) }
    }
    var eqCompareMenu: Bool {
        get { access(keyPath: \.obs._eqCompareMenu); return obs._eqCompareMenu }
        set { put(\.obs._eqCompareMenu, newValue, observedChanged(obs._eqCompareMenu, newValue)) }
    }
    var eqPhones: Bool {
        get { access(keyPath: \.obs._eqPhones); return obs._eqPhones }
        set { put(\.obs._eqPhones, newValue, observedChanged(obs._eqPhones, newValue)) }
    }
    var phonesName: String {
        get { access(keyPath: \.obs._phonesName); return obs._phonesName }
        set { put(\.obs._phonesName, newValue, observedChanged(obs._phonesName, newValue)) }
    }
    var importingPhones: Bool {
        get { access(keyPath: \.obs._importingPhones); return obs._importingPhones }
        set { put(\.obs._importingPhones, newValue, observedChanged(obs._importingPhones, newValue)) }
    }
    var phonesNote: String? {
        get { access(keyPath: \.obs._phonesNote); return obs._phonesNote }
        set { put(\.obs._phonesNote, newValue, observedChanged(obs._phonesNote, newValue)) }
    }
    var phonesExported: URL? {
        get { access(keyPath: \.obs._phonesExported); return obs._phonesExported }
        set { put(\.obs._phonesExported, newValue, observedChanged(obs._phonesExported, newValue)) }
    }
    var gridTop: Int {
        get { access(keyPath: \.obs._gridTop); return obs._gridTop }
        set { put(\.obs._gridTop, newValue, observedChanged(obs._gridTop, newValue)) }
    }
    var cellMenu: CellMenuState? {
        get { access(keyPath: \.obs._cellMenu); return obs._cellMenu }
        set { put(\.obs._cellMenu, newValue, observedChanged(obs._cellMenu, newValue)) }
    }
    var rowMenu: Int? {
        get { access(keyPath: \.obs._rowMenu); return obs._rowMenu }
        set { put(\.obs._rowMenu, newValue, observedChanged(obs._rowMenu, newValue)) }
    }
    var gridRowsShown: Int {
        get { access(keyPath: \.obs._gridRowsShown); return obs._gridRowsShown }
        set { put(\.obs._gridRowsShown, newValue, observedChanged(obs._gridRowsShown, newValue)) }
    }
    var clipCarry: ClipCarry? {
        get { access(keyPath: \.obs._clipCarry); return obs._clipCarry }
        set { put(\.obs._clipCarry, newValue, observedChanged(obs._clipCarry, newValue)) }
    }
    var carryPoint: CGPoint {
        get { access(keyPath: \.obs._carryPoint); return obs._carryPoint }
        set { put(\.obs._carryPoint, newValue, observedChanged(obs._carryPoint, newValue)) }
    }
    var deniedCell: CellRef? {
        get { access(keyPath: \.obs._deniedCell); return obs._deniedCell }
        set { put(\.obs._deniedCell, newValue, observedChanged(obs._deniedCell, newValue)) }
    }
    var mix: MixTransition? {
        get { access(keyPath: \.obs._mix); return obs._mix }
        set { put(\.obs._mix, newValue, observedChanged(obs._mix, newValue)) }
    }
    var mixDropDone: Bool {
        get { access(keyPath: \.obs._mixDropDone); return obs._mixDropDone }
        set { put(\.obs._mixDropDone, newValue, observedChanged(obs._mixDropDone, newValue)) }
    }
    var choice: ChoiceState? {
        get { access(keyPath: \.obs._choice); return obs._choice }
        set { put(\.obs._choice, newValue, observedChanged(obs._choice, newValue)) }
    }
    var pianoMenuOpen: Bool {
        get { access(keyPath: \.obs._pianoMenuOpen); return obs._pianoMenuOpen }
        set { put(\.obs._pianoMenuOpen, newValue, observedChanged(obs._pianoMenuOpen, newValue)) }
    }
    var samplesVersion: Int {
        get { access(keyPath: \.obs._samplesVersion); return obs._samplesVersion }
        set { put(\.obs._samplesVersion, newValue, observedChanged(obs._samplesVersion, newValue)) }
    }
    var editorOpen: Bool {
        get { access(keyPath: \.obs._editorOpen); return obs._editorOpen }
        set { put(\.obs._editorOpen, newValue, observedChanged(obs._editorOpen, newValue)) }
    }
    var editorWarp: Bool {
        get { access(keyPath: \.obs._editorWarp); return obs._editorWarp }
        set { put(\.obs._editorWarp, newValue, observedChanged(obs._editorWarp, newValue)) }
    }
    var warpGrid: Double {
        get { access(keyPath: \.obs._warpGrid); return obs._warpGrid }
        set { put(\.obs._warpGrid, newValue, observedChanged(obs._warpGrid, newValue)) }
    }
    var warpSel: Int? {
        get { access(keyPath: \.obs._warpSel); return obs._warpSel }
        set { put(\.obs._warpSel, newValue, observedChanged(obs._warpSel, newValue)) }
    }
    var soundMenu: SoundMenuState? {
        get { access(keyPath: \.obs._soundMenu); return obs._soundMenu }
        set { put(\.obs._soundMenu, newValue, observedChanged(obs._soundMenu, newValue)) }
    }
    var importTarget: ImportTarget? {
        get { access(keyPath: \.obs._importTarget); return obs._importTarget }
        set { put(\.obs._importTarget, newValue, observedChanged(obs._importTarget, newValue)) }
    }
    var importing: Bool {
        get { access(keyPath: \.obs._importing); return obs._importing }
        set { put(\.obs._importing, newValue, observedChanged(obs._importing, newValue)) }
    }
    var importingProject: Bool {
        get { access(keyPath: \.obs._importingProject); return obs._importingProject }
        set { put(\.obs._importingProject, newValue, observedChanged(obs._importingProject, newValue)) }
    }
    var projectImport: ProjectImport? {
        get { access(keyPath: \.obs._projectImport); return obs._projectImport }
        set { put(\.obs._projectImport, newValue, observedChanged(obs._projectImport, newValue)) }
    }
    var browser: BrowserMode? {
        get { access(keyPath: \.obs._browser); return obs._browser }
        set { put(\.obs._browser, newValue, observedChanged(obs._browser, newValue)) }
    }
    var libFolder: String {
        get { access(keyPath: \.obs._libFolder); return obs._libFolder }
        set { put(\.obs._libFolder, newValue, observedChanged(obs._libFolder, newValue)) }
    }
    var libPicked: Set<String>? {
        get { access(keyPath: \.obs._libPicked); return obs._libPicked }
        set { put(\.obs._libPicked, newValue, observedChanged(obs._libPicked, newValue)) }
    }
    var libNote: String {
        get { access(keyPath: \.obs._libNote); return obs._libNote }
        set { put(\.obs._libNote, newValue, observedChanged(obs._libNote, newValue)) }
    }
    var libWarning: String? {
        get { access(keyPath: \.obs._libWarning); return obs._libWarning }
        set { put(\.obs._libWarning, newValue, observedChanged(obs._libWarning, newValue)) }
    }
    var importingLibrary: Bool {
        get { access(keyPath: \.obs._importingLibrary); return obs._importingLibrary }
        set { put(\.obs._importingLibrary, newValue, observedChanged(obs._importingLibrary, newValue)) }
    }
    var leftFrame: CGRect {
        get { access(keyPath: \.obs._leftFrame); return obs._leftFrame }
        set { put(\.obs._leftFrame, newValue, observedChanged(obs._leftFrame, newValue)) }
    }
    var pagesFrame: CGRect {
        get { access(keyPath: \.obs._pagesFrame); return obs._pagesFrame }
        set { put(\.obs._pagesFrame, newValue, observedChanged(obs._pagesFrame, newValue)) }
    }
    var keysFrame: CGRect {
        get { access(keyPath: \.obs._keysFrame); return obs._keysFrame }
        set { put(\.obs._keysFrame, newValue, observedChanged(obs._keysFrame, newValue)) }
    }
    var tracksFrame: CGRect {
        get { access(keyPath: \.obs._tracksFrame); return obs._tracksFrame }
        set { put(\.obs._tracksFrame, newValue, observedChanged(obs._tracksFrame, newValue)) }
    }
    var previewOn: Bool {
        get { access(keyPath: \.obs._previewOn); return obs._previewOn }
        set { put(\.obs._previewOn, newValue, observedChanged(obs._previewOn, newValue)) }
    }
    var heldFlag: Int? {
        get { access(keyPath: \.obs._heldFlag); return obs._heldFlag }
        set { put(\.obs._heldFlag, newValue, observedChanged(obs._heldFlag, newValue)) }
    }
    var roleFlag: Int? {
        get { access(keyPath: \.obs._roleFlag); return obs._roleFlag }
        set { put(\.obs._roleFlag, newValue, observedChanged(obs._roleFlag, newValue)) }
    }
    var trackMenu: TrackMenuState? {
        get { access(keyPath: \.obs._trackMenu); return obs._trackMenu }
        set { put(\.obs._trackMenu, newValue, observedChanged(obs._trackMenu, newValue)) }
    }
    var renaming: Int? {
        get { access(keyPath: \.obs._renaming); return obs._renaming }
        set { put(\.obs._renaming, newValue, observedChanged(obs._renaming, newValue)) }
    }
    var masterWin: Int? {
        get { access(keyPath: \.obs._masterWin); return obs._masterWin }
        set { put(\.obs._masterWin, newValue, observedChanged(obs._masterWin, newValue)) }
    }
    var masterMenu: MasterMenuState? {
        get { access(keyPath: \.obs._masterMenu); return obs._masterMenu }
        set { put(\.obs._masterMenu, newValue, observedChanged(obs._masterMenu, newValue)) }
    }
    var masterUnity: Bool {
        get { access(keyPath: \.obs._masterUnity); return obs._masterUnity }
        set { put(\.obs._masterUnity, newValue, observedChanged(obs._masterUnity, newValue)) }
    }
    var masterInput: MasterInputTarget? {
        get { access(keyPath: \.obs._masterInput); return obs._masterInput }
        set { put(\.obs._masterInput, newValue, observedChanged(obs._masterInput, newValue)) }
    }
    var defaultFlash: Int? {
        get { access(keyPath: \.obs._defaultFlash); return obs._defaultFlash }
        set { put(\.obs._defaultFlash, newValue, observedChanged(obs._defaultFlash, newValue)) }
    }
    var defaultSaved: DefaultSaved? {
        get { access(keyPath: \.obs._defaultSaved); return obs._defaultSaved }
        set { put(\.obs._defaultSaved, newValue, observedChanged(obs._defaultSaved, newValue)) }
    }
    var heldSteps: Set<Int> {
        get { access(keyPath: \.obs._heldSteps); return obs._heldSteps }
        set { put(\.obs._heldSteps, newValue, observedChanged(obs._heldSteps, newValue)) }
    }
    var heldSources: Set<Int> {
        get { access(keyPath: \.obs._heldSources); return obs._heldSources }
        set { put(\.obs._heldSources, newValue, observedChanged(obs._heldSources, newValue)) }
    }
    var knobFingers: Set<Int> {
        get { access(keyPath: \.obs._knobFingers); return obs._knobFingers }
        set { put(\.obs._knobFingers, newValue, observedChanged(obs._knobFingers, newValue)) }
    }
    /// Октавы клавиатуры дорожек по местам (хранятся в проекте у дорожки — Track.keyOctave), до Params.maxTracks.
    var octaves: [Int] {
        let ts: [Track] = project.tracks
        return (0..<Params.maxTracks).map { $0 < ts.count ? ts[$0].keyOctave : Scales.octaveDef }
    }
    var chordMode: [Bool] {
        get { access(keyPath: \.obs._chordMode); return obs._chordMode }
        set { put(\.obs._chordMode, newValue, observedChanged(obs._chordMode, newValue)) }
    }
    var chordKind: [Int] {
        get { access(keyPath: \.obs._chordKind); return obs._chordKind }
        set { put(\.obs._chordKind, newValue, observedChanged(obs._chordKind, newValue)) }
    }
    var partType: [Int] {
        get { access(keyPath: \.obs._partType); return obs._partType }
        set { put(\.obs._partType, newValue, observedChanged(obs._partType, newValue)) }
    }
    var selNotes: [[Int]] {
        get { access(keyPath: \.obs._selNotes); return obs._selNotes }
        set { put(\.obs._selNotes, newValue, observedChanged(obs._selNotes, newValue)) }
    }
    var pressedKeys: [Int: [Int]] {
        get { access(keyPath: \.obs._pressedKeys); return obs._pressedKeys }
        set { put(\.obs._pressedKeys, newValue, observedChanged(obs._pressedKeys, newValue)) }
    }
    var arrGroup: [ArrSel] {
        get { access(keyPath: \.obs._arrGroup); return obs._arrGroup }
        set { put(\.obs._arrGroup, newValue, observedChanged(obs._arrGroup, newValue)) }
    }
    var eqCompares: [Int: Int] {
        get { access(keyPath: \.obs._eqCompares); return obs._eqCompares }
        set { put(\.obs._eqCompares, newValue, observedChanged(obs._eqCompares, newValue)) }
    }
    var arrDropPending: (sel: GridSelection, start: Int)? {
        get { access(keyPath: \.obs._arrDropPending); return obs._arrDropPending }
        set { put(\.obs._arrDropPending, newValue, observedChanged(obs._arrDropPending, newValue)) }
    }
    var gridMenuOpen: Bool {
        get { access(keyPath: \.obs._gridMenuOpen); return obs._gridMenuOpen }
        set { put(\.obs._gridMenuOpen, newValue, observedChanged(obs._gridMenuOpen, newValue)) }
    }
    var mixDrop: [Int: Int] {
        get { access(keyPath: \.obs._mixDrop); return obs._mixDrop }
        set { put(\.obs._mixDrop, newValue, observedChanged(obs._mixDrop, newValue)) }
    }
    var captureFlash: Bool {
        get { access(keyPath: \.obs._captureFlash); return obs._captureFlash }
        set { put(\.obs._captureFlash, newValue, observedChanged(obs._captureFlash, newValue)) }
    }
    var wavetableSerial: Int {
        get { access(keyPath: \.obs._wavetableSerial); return obs._wavetableSerial }
        set { put(\.obs._wavetableSerial, newValue, observedChanged(obs._wavetableSerial, newValue)) }
    }
    var headCount: Int {
        get { access(keyPath: \.obs._headCount); return obs._headCount }
        set { put(\.obs._headCount, newValue, observedChanged(obs._headCount, newValue)) }
    }
    var stemArmed: Set<Int> {
        get { access(keyPath: \.obs._stemArmed); return obs._stemArmed }
        set { put(\.obs._stemArmed, newValue, observedChanged(obs._stemArmed, newValue)) }
    }
    var stemRecording: Set<Int> {
        get { access(keyPath: \.obs._stemRecording); return obs._stemRecording }
        set { put(\.obs._stemRecording, newValue, observedChanged(obs._stemRecording, newValue)) }
    }
    var refusedFlag: (idx: Int, until: Double) {
        get { access(keyPath: \.obs._refusedFlag); return obs._refusedFlag }
        set { put(\.obs._refusedFlag, newValue, observedChanged(obs._refusedFlag, newValue)) }
    }
    var hasTrackClip: Bool {
        get { access(keyPath: \.obs._hasTrackClip); return obs._hasTrackClip }
        set { put(\.obs._hasTrackClip, newValue, observedChanged(obs._hasTrackClip, newValue)) }
    }
    var scopeOn: [Bool] {
        get { access(keyPath: \.obs._scopeOn); return obs._scopeOn }
        set { put(\.obs._scopeOn, newValue, observedChanged(obs._scopeOn, newValue)) }
    }
    var mixMode: Int {
        get { access(keyPath: \.obs._mixMode); return obs._mixMode }
        set { put(\.obs._mixMode, newValue, obs._mixMode != newValue) }
    }
    var mixerOpen: Bool {
        get { access(keyPath: \.obs._mixerOpen); return obs._mixerOpen }
        set { put(\.obs._mixerOpen, newValue, obs._mixerOpen != newValue) }
    }
    var session: ProjectSession {
        get { access(keyPath: \.obs._session); return obs._session }
        set { put(\.obs._session, newValue, observedChanged(obs._session, newValue)) }
    }
    var projectList: [ProjectInfo] {
        get { access(keyPath: \.obs._projectList); return obs._projectList }
        set { put(\.obs._projectList, newValue, observedChanged(obs._projectList, newValue)) }
    }
    var arrPort: ArrPort {
        get { access(keyPath: \.obs._arrPort); return obs._arrPort }
        set { put(\.obs._arrPort, newValue, observedChanged(obs._arrPort, newValue)) }
    }
    var songFormat: SongFormat {
        get { access(keyPath: \.obs._songFormat); return obs._songFormat }
        set { put(\.obs._songFormat, newValue, observedChanged(obs._songFormat, newValue)) }
    }
    var songExport: SongExportState {
        get { access(keyPath: \.obs._songExport); return obs._songExport }
        set { put(\.obs._songExport, newValue, observedChanged(obs._songExport, newValue)) }
    }
    var refWave: RefWave? {
        get { access(keyPath: \.obs._refWave); return obs._refWave }
        set { put(\.obs._refWave, newValue, observedChanged(obs._refWave, newValue)) }
    }
    var refHeardTenths: Int {
        get { access(keyPath: \.obs._refHeardTenths); return obs._refHeardTenths }
        set { put(\.obs._refHeardTenths, newValue, observedChanged(obs._refHeardTenths, newValue)) }
    }
    var monitorUndo: [MonitorSnap] {
        get { access(keyPath: \.obs._monitorUndo); return obs._monitorUndo }
        set { put(\.obs._monitorUndo, newValue, observedChanged(obs._monitorUndo, newValue)) }
    }
    var monitorRedo: [MonitorSnap] {
        get { access(keyPath: \.obs._monitorRedo); return obs._monitorRedo }
        set { put(\.obs._monitorRedo, newValue, observedChanged(obs._monitorRedo, newValue)) }
    }
    var gridSel: GridSelection {
        get { access(keyPath: \.obs._gridSel); return obs._gridSel }
        set { put(\.obs._gridSel, newValue, observedChanged(obs._gridSel, newValue)) }
    }
    var topFrames: TopFrames {
        get { access(keyPath: \.obs._topFrames); return obs._topFrames }
        set { put(\.obs._topFrames, newValue, observedChanged(obs._topFrames, newValue)) }
    }
    var libTableAsk: [TableImport] {
        get { access(keyPath: \.obs._libTableAsk); return obs._libTableAsk }
        set { put(\.obs._libTableAsk, newValue, observedChanged(obs._libTableAsk, newValue)) }
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
