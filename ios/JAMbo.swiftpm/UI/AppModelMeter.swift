import Foundation

/// Измеритель справа и метры MIX: канал, стерео или моно, громкость дорожки с измерителя.
extension AppModel {
    /// Канал измерителя: выбранная дорожка, при MIX и MST — выход мастера; REF в положении B — референс (S15g).
    var meterChannel: Int {
        if refBActive { return Levels.ref }
        return channel == .track ? selectedTrack : Levels.master
    }

    /// Кадр метров (drain, 60 раз в секунду): LUFS копится и при закрытом измерителе (сетка паттернов).
    func tickMeters() {
        let lv = audio.core.levels
        meters.show(meterChannel, lv)
        let now: Double = Date.timeIntervalSinceReferenceDate
        meters.tick(lv, now: now)
        tickRefMatch()
        dynMeters.tick(audio.core.master, project, now: now)
        // Скоп — только пока виден (MST и MIX).
        let sc: MasterScope = audio.core.master.scope
        if channel != .track {
            // При MIX — только форма волны мастера (SAT), без точек съёма COMP, CLIP, LIM.
            let on: [Bool] = channel == .master ? scopeOn : [true, false, false, false]
            var m: Int = MasterScope.gonioBit
            for k in 0..<4 where on[k] { m |= 1 << k }
            sc.mask.store(m)
            scope.tick(sc, on: on)
        } else if sc.mask.load() != 0 {
            sc.mask.store(0)
        }
    }

    /// Стерео ли дорожка на метре (правило: стерео где-то на дорожке — метр стерео): стерео-сэмпл или стерео-движок
    /// (TEXTURE, GRANULAR) — у дорожки, у звука клипа, в сэмпл-локе или пресет-локе шага (паттерны и блоки
    /// аранжировки); панорама не в центре — ручкой, p-lock шагов, кривой аранжировки; панораму двигают LFO/ENV.
    /// Кэш — до правки проекта; пока сэмпл не загружен, не кэшируется.
    func trackStereo(_ t: Int) -> Bool {
        guard t >= 0 && t < project.tracks.count else { return false }
        if let v = stereoCache[t] { return v }
        var missing = false
        let tr = project.tracks[t]
        let r: Bool = trackStereoScan(tr, &missing)
        if !missing { stereoCache[t] = r }
        return r
    }

    /// Звук по ключу — стерео: движок TEXTURE, GRANULAR или стерео-сэмпл (missing — сэмпл ещё не загружен).
    private func soundStereo(_ key: String, _ missing: inout Bool) -> Bool {
        if key.isEmpty { return false }
        if let e = SynthKey.engine(key) { return Jambo.stereo(e) }
        if key.contains(":") { return false }
        guard let s = sample(key) else {
            missing = true
            return false
        }
        return s.channels > 1
    }

    private func clipStereo(_ c: Clip, _ missing: inout Bool) -> Bool {
        if let src = c.src {
            if soundStereo(src.sample, &missing) { return true }
            if abs(src.params["pan"] ?? 0) >= 1 || abs(src.assigns["pan"]?.amount ?? 0) > 0 { return true }
        }
        for page in c.pages {
            for s in page {
                if abs(s.locks["pan"] ?? 0) >= 1 { return true }
                if let k = s.sound, soundStereo(k, &missing) { return true }
            }
        }
        return false
    }

    private func trackStereoScan(_ tr: Track, _ missing: inout Bool) -> Bool {
        if soundStereo(tr.sample, &missing) { return true }
        if abs(tr.params["pan"] ?? 0) >= 1 { return true }
        if abs(tr.assigns["pan"]?.amount ?? 0) > 0 { return true }
        if let h = tr.home {
            if soundStereo(h.sample, &missing) { return true }
            if abs(h.params["pan"] ?? 0) >= 1 || abs(h.assigns["pan"]?.amount ?? 0) > 0 { return true }
        }
        for c in tr.clips {
            if let c = c, clipStereo(c, &missing) { return true }
        }
        let panLane: (ArrAutoLane) -> Bool = { l in
            l.param == "pan" && l.points.contains { abs($0.y * 127 - 64) >= 1 }
        }
        for b in tr.blocks {
            if let c = b.pattern, clipStereo(c, &missing) { return true }
            if b.autos.contains(where: panLane) { return true }
        }
        return tr.autos.contains(where: panLane)
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

/// Регулятор громкости на измерителе справа (палец и MIDI — цель LEVEL, S13b).
extension AppModel {
    /// Итоговая громкость канала измерителя (подпись VOL и положение регулятора): у дорожки — громкость MIX
    /// (при RELATIVE — с подстройкой trim, выше громкости MIX не поднимается), у MIX и MST — громкость выхода.
    func meterVol(_ ch: Int) -> Double {
        if ch == Levels.master { return project.outVol }
        if ch == Levels.ref { return project.arrange.ref?.gain ?? 0 }
        guard ch < project.tracks.count else { return Params.volDef }
        let t = project.tracks[ch]
        if !settings.levelRelative { return t.vol }
        if t.trim <= Params.volMin + 0.05 { return Params.volMin }
        return max(Params.volMin, t.vol + t.trim)
    }

    func setMeterVol(_ ch: Int, _ v: Double) {
        if ch == Levels.master {
            setOutVol(v)
        } else if ch == Levels.ref {
            setArrRefGain(v)
        } else if settings.levelRelative {
            setTrackLevel(ch, v)
        } else {
            setTrackVol(ch, v)
        }
    }
}
