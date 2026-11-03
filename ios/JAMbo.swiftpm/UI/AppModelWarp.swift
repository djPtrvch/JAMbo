import Foundation

// WARP в редакторе сэмпла (docs/ai/sound-sampler.md): метки варпинга сэмпла выбранной дорожки, BPM файла, GRID,
// AUTO WARP, CLEAR WARP, ▶ по карте. Каждое действие — одна запись UNDO (перетаскивание — жестом).

extension AppModel {
    var editorWarpInfo: WarpInfo {
        return track.warpInfo(editorKey)
    }

    /// WARP TO PROJECT BPM: темп проекта (у сэмплов с метками он — BPM файла, свой не действует); выкл. — nil.
    var warpFollowBpm: Double? {
        return settings.warpProjectBpm ? project.bpm : nil
    }

    /// BPM файла идёт за темпом проекта (WARP TO PROJECT BPM, у сэмпла есть метки, варпинг включён).
    var warpBpmFollows: Bool {
        let w = editorWarpInfo
        return settings.warpProjectBpm && !w.marks.isEmpty && !w.isOff
    }

    /// BPM файла: темп проекта (WARP TO PROJECT BPM), иначе свой, иначе определённый сам, иначе 120.
    func warpBpm(_ d: SampleData) -> Double {
        return WarpMap.bpm(editorWarpInfo, detected: d.loopBpm, follow: warpFollowBpm)
    }

    func warpMap(_ d: SampleData) -> WarpMap {
        return WarpMap(editorWarpInfo, frames: d.frames, bpm: warpBpm(d))
    }

    func toggleWarp() {
        if previewOn { audio.core.events.push(.previewStop) }
        releaseFlag()
        warpSel = nil
        editorWarp.toggle()
        // WARP TO PROJECT BPM: у сэмпла без меток и своего BPM — BPM файла = темп проекта (одна запись UNDO); с
        // метками BPM файла и так идёт за темпом проекта.
        if editorWarp && settings.warpProjectBpm && editorWarpInfo.bpm == nil && !editorKey.isEmpty {
            setWarpBpm(project.bpm)
        }
    }

    /// Удержание WARP: варпинг сэмпла выкл./вкл. (метки и BPM остаются; одна запись UNDO).
    func toggleWarpOff() {
        let key = editorKey
        if key.isEmpty { return }
        let v: Bool = !editorWarpInfo.isOff
        editTrack { t in t.setWarpOff(key, v) }
    }

    /// Свой BPM файла (nil — определённый сам).
    func setWarpBpm(_ v: Double?) {
        let key = editorKey
        if key.isEmpty { return }
        editTrack { t in t.setWarpBpm(key, v) }
    }

    func autoWarp() {
        let key = editorKey
        guard !key.isEmpty, let d = sample(key) else { return }
        let ons: [Double] = d.onsets.list
        let det: Double = d.loopBpm
        let g: Double = warpGrid
        warpSel = nil
        let fol: Double? = warpFollowBpm
        editTrack { t in t.autoWarp(key, onsets: ons, frames: d.frames, detectedBpm: det, grid: g, follow: fol) }
    }

    func clearWarp() {
        let key = editorKey
        if key.isEmpty { return }
        warpSel = nil
        editTrack { t in t.clearWarp(key) }
    }

    /// Новая метка в доле длины f (на своей доле — звук не меняется).
    func addWarp(at f: Double) {
        let key = editorKey
        guard !key.isEmpty, let d = sample(key) else { return }
        let det: Double = d.loopBpm
        warpSel = nil
        let fol: Double? = warpFollowBpm
        editTrack { t in t.addWarp(key, at: f, frames: d.frames, detectedBpm: det, follow: fol) }
    }

    /// Метка начала сэмпла (нет — ставится на своей доле); номер 0.
    func warpStartMark() -> Int {
        let key = editorKey
        guard !key.isEmpty, let d = sample(key) else { return -1 }
        let det: Double = d.loopBpm
        var k = 0
        let fol: Double? = warpFollowBpm
        editTrack { t in k = t.warpStart(key, frames: d.frames, detectedBpm: det, follow: fol) }
        return k
    }

    func moveWarp(_ idx: Int, beat: Double) {
        let key = editorKey
        if key.isEmpty { return }
        editTrack { t in t.moveWarp(key, idx, beat: beat) }
    }

    /// Верхний флажок: метка idx — в место сэмпла at (доля длины) на долю beat.
    func placeWarp(_ idx: Int, at: Double, beat: Double) {
        let key = editorKey
        guard !key.isEmpty, let d = sample(key) else { return }
        editTrack { t in t.placeWarp(key, idx, at: at, beat: beat, frames: d.frames) }
    }

    func deleteWarp(_ idx: Int) {
        let key = editorKey
        if key.isEmpty { return }
        warpSel = nil
        editTrack { t in t.deleteWarp(key, idx) }
    }

    /// ▶ в режиме WARP: весь сэмпл нотой дорожки в Rate Stretch по карте (в темпе проекта); повторный тап — стоп.
    func toggleWarpPreview() {
        ensureAudio()
        if previewOn {
            audio.core.events.push(.previewStop)
            return
        }
        let key = editorKey
        guard !key.isEmpty, sample(key) != nil else { return }
        previewOn = true
        audio.core.events.push(.warpPreview(track: selectedTrack, hash: SoundKey.hash(key)))
    }
}
