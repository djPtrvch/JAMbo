import Foundation

// WARP в редакторе сэмпла (docs/ai/sound-sampler.md): метки варпинга сэмпла выбранной дорожки, BPM файла, GRID,
// AUTO WARP, CLEAR WARP, ▶ по карте. Каждое действие — одна запись UNDO (перетаскивание — жестом).

extension AppModel {
    var editorWarpInfo: WarpInfo {
        return track.warpInfo(editorKey)
    }

    /// BPM файла: свой, иначе определённый сам, иначе 120.
    func warpBpm(_ d: SampleData) -> Double {
        return WarpMap.bpm(editorWarpInfo, detected: d.loopBpm)
    }

    func warpMap(_ d: SampleData) -> WarpMap {
        return WarpMap(editorWarpInfo, frames: d.frames, bpm: warpBpm(d))
    }

    func toggleWarp() {
        if previewOn { audio.core.events.push(.previewStop) }
        heldFlag = nil
        warpSel = nil
        editorWarp.toggle()
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
        editTrack { t in t.autoWarp(key, onsets: ons, frames: d.frames, detectedBpm: det, grid: g) }
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
        editTrack { t in t.addWarp(key, at: f, frames: d.frames, detectedBpm: det) }
    }

    /// Метка начала сэмпла (нет — ставится на своей доле); номер 0.
    func warpStartMark() -> Int {
        let key = editorKey
        guard !key.isEmpty, let d = sample(key) else { return -1 }
        let det: Double = d.loopBpm
        var k = 0
        editTrack { t in k = t.warpStart(key, frames: d.frames, detectedBpm: det) }
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
