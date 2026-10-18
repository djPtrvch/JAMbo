import Foundation

/// Измеритель справа и метры MIX: канал, стерео или моно, громкость дорожки с измерителя.
extension AppModel {
    /// Канал измерителя: выбранная дорожка, при MIX и MST — выход мастера.
    var meterChannel: Int { return channel == .track ? selectedTrack : Levels.master }

    /// Кадр метров (drain, 60 раз в секунду): LUFS копится и при закрытом измерителе (сетка паттернов).
    func tickMeters() {
        let lv = audio.core.levels
        meters.show(meterChannel, lv)
        let now: Double = Date.timeIntervalSinceReferenceDate
        meters.tick(lv, now: now)
        dynMeters.tick(audio.core.master, project, now: now)
        // Скоп — только пока виден (MST).
        let sc: MasterScope = audio.core.master.scope
        if channel == .master {
            var m: Int = MasterScope.gonioBit
            for k in 0..<4 where scopeOn[k] { m |= 1 << k }
            sc.mask.store(m)
            scope.tick(sc, on: scopeOn)
        } else if sc.mask.load() != 0 {
            sc.mask.store(0)
        }
    }

    /// Стерео ли дорожка на метре (как trackIsStereo веба): стерео-сэмпл, панорама до края, панораму двигают
    /// LFO/ENV или p-lock шагов.
    func trackStereo(_ t: Int) -> Bool {
        guard t >= 0 && t < project.tracks.count else { return false }
        let tr = project.tracks[t]
        if (sample(tr.sample)?.channels ?? 1) > 1 { return true }
        if abs(tr.params["pan"] ?? 0) >= 1 { return true }
        if abs(tr.assigns["pan"]?.amount ?? 0) > 0 { return true }
        for page in tr.pages {
            for s in page where abs(s.locks["pan"] ?? 0) >= 1 { return true }
        }
        return false
    }

    /// Регулятор на измерителе: громкость дорожки в микшере (та же, что ручка в MIX), −∞…0 dB.
    func setTrackVol(_ t: Int, _ db: Double) {
        guard t >= 0 && t < project.tracks.count else { return }
        let v: Double = max(Params.volMin, min(0, db))
        edit { pr in pr.tracks[t].vol = v }
    }

    /// LEVEL RELATIVE: итоговая громкость дорожки db (не выше громкости MIX) — подстройка trim = db − громкость MIX;
    /// внизу шкалы — тишина. Подстройка следует за громкостью MIX (смена MIX сдвигает итог на столько же).
    func setTrackLevel(_ t: Int, _ db: Double) {
        guard t >= 0 && t < project.tracks.count else { return }
        let vol: Double = project.tracks[t].vol
        let total: Double = max(Params.volMin, min(vol, db))
        let trim: Double = total <= Params.volMin + 0.05 ? Params.volMin : max(Params.volMin, min(0, total - vol))
        edit { pr in pr.tracks[t].trim = trim }
    }

    /// Регулятор на измерителе при MIX и MST: громкость выхода мастера (после лимитера), −∞…0 dB.
    func setOutVol(_ db: Double) {
        let v: Double = max(Params.volMin, min(0, db))
        edit { pr in pr.outVol = v }
    }

    func resetMeterPeak() {
        meters.resetPeak(meterChannel)
    }

    func resetLoudness() {
        let l = audio.core.levels.loudness
        l.resetRequests.store(l.resetRequests.load() + 1)
    }
}
