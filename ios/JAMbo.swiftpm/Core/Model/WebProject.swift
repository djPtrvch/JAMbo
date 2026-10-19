import Foundation

// Проект веба (doc из .jambo, формат 'jambo') → Project (S11a). Имена полей те же, устройство другое:
// - паттерны: в вебе страницы и длина — у дорожки (общие для всех клипов), клип — только playFrom, playTo, гамма,
//   нота, FX (активный — в полях дорожки, остальные — в slots); в Swift у каждого клипа свой паттерн — копия страниц;
// - громкости: doc.mixer['mix.volN'] → Track.vol; EQ дорожек: doc.eqs[i] → Track.eq; папки: doc.folders[i] → Track.folder
//   (сэмплы и пресеты синта);
// - ключи сэмплов: 's:<hex>' → '<hex>' (тот же SHA-256 исходного файла, SampleStore.key);
// - не переносятся (решения пользователя, S11): автоматизация (auto), миграция SPEECH; свои таблицы WTABLE ('wt:…')
//   — BASIC до S11b4; убранные в Swift параметры мастера; MORPH-снимки (trackOrig) и переход MIX (home, src).
// Сборка — словарь в формате Project, затем обычное чтение (ProjectCoding) и repair.

public enum WebProject {
    public static func convert(_ docJSON: Data) -> Project? {
        guard let obj = try? JSONSerialization.jsonObject(with: docJSON, options: [.fragmentsAllowed]),
              let d = obj as? [String: Any] else { return nil }
        let out: [String: Any] = project(d)
        guard let data = try? JSONSerialization.data(withJSONObject: out, options: []),
              var p = try? ProjectFormat.decoder().decode(Project.self, from: data) else { return nil }
        p.repair()
        return p
    }

    /// Ключ звука веба → Swift: сэмпл без 's:', синты ('mi:…') и встроенные таблицы — как есть.
    static func key(_ k: String) -> String {
        return k.hasPrefix("s:") ? String(k.dropFirst(2)) : k
    }

    /// Таблица WTABLE: встроенная — как есть; своя ('wt:s:<hex>:<кадр>') — до S11b4 BASIC.
    static func table(_ t: String) -> String {
        return t.hasPrefix("builtin:") ? t : ""
    }

    static func project(_ d: [String: Any]) -> [String: Any] {
        var p: [String: Any] = [:]
        for k in ["bpm", "scale", "root", "satBypass", "cmpBypass", "clipBypass", "limBypass", "outVol", "rows",
                  "arrStart", "rowLoop", "fxAssigns", "masterEq"] {
            if let v = d[k] { p[k] = v }
        }
        p["fx"] = filtered(d["fx"], Set(Params.fxDefaults().keys))
        p["master"] = filtered(d["master"], Set(MasterChain.ids.map { $0.id }))
        p["arrEndStop"] = (d["arrEnd"] as? String) == "stop"
        p["plusCopy"] = (d["plusMode"] as? String) != "empty"
        p["arrowSwitch"] = (d["arrowMode"] as? String) == "switch"
        if let s = d["scenes"] { p["scenes"] = s }
        p["files"] = rekeyed(d["files"])
        p["roots"] = rekeyed(d["roots"])
        let mixer: [String: Any] = d["mixer"] as? [String: Any] ?? [:]
        let eqs: [Any] = d["eqs"] as? [Any] ?? []
        let folders: [Any] = d["folders"] as? [Any] ?? []
        let tracks: [Any] = d["tracks"] as? [Any] ?? []
        var list: [[String: Any]] = []
        for (i, item) in tracks.enumerated() {
            guard let t = item as? [String: Any] else { continue }
            var tr: [String: Any] = track(t)
            if let v = mixer["mix.vol\(i + 1)"] { tr["vol"] = v }
            if i < eqs.count, let e = eqs[i] as? [String: Any] { tr["eq"] = e }
            if i < folders.count, let f = folders[i] as? [String: Any] { tr["folder"] = folder(f) }
            list.append(tr)
        }
        p["tracks"] = list
        var seqs: [[String: Any]] = []
        for item in d["chanSeqs"] as? [Any] ?? [] {
            guard let t = item as? [String: Any] else { continue }
            seqs.append(channel(t))
        }
        if !seqs.isEmpty { p["chanSeqs"] = seqs }
        return p
    }

    /// Дорожка: звук и ручки — как есть, клипы — каждый со своей копией страниц дорожки.
    static func track(_ t: [String: Any]) -> [String: Any] {
        var tr: [String: Any] = [:]
        for k in ["id", "name", "mute", "solo", "stopped", "assigns"] {
            if let v = t[k] { tr[k] = v }
        }
        tr["sample"] = key(t["sample"] as? String ?? "")
        tr["params"] = filtered(t["params"], Set(Params.byId.keys))
        tr["table"] = table(t["table"] as? String ?? "")
        if let sl = t["slices"] as? [String: Any] { tr["slices"] = rekeyed(sl) }
        let pages: [Any] = convertPages(t["pages"])
        let length: Any = t["length"] ?? Params.stepsPerPage
        let slot: Int = ProjectPack.number(t["slot"]) ?? 0
        let blank: Bool = t["blank"] as? Bool ?? false
        let slots: [Any] = t["slots"] as? [Any] ?? []
        var clips: [Any] = []
        for k in 0..<Params.patternSlots {
            if k == slot {
                clips.append(blank ? NSNull() : clip(t, pages: pages, length: length))
            } else if k < slots.count, let c = slots[k] as? [String: Any] {
                clips.append(clip(c, pages: pages, length: length))
            } else {
                clips.append(NSNull())
            }
        }
        tr["clips"] = clips
        tr["slot"] = slot
        tr["open"] = slot
        return tr
    }

    /// MIX и MST: один клип со страницами последовательности.
    static func channel(_ t: [String: Any]) -> [String: Any] {
        var tr: [String: Any] = [:]
        if let n = t["name"] { tr["name"] = n }
        let pages: [Any] = convertPages(t["pages"])
        var clips: [Any] = [clip(t, pages: pages, length: t["length"] ?? Params.stepsPerPage)]
        while clips.count < Params.patternSlots { clips.append(NSNull()) }
        tr["clips"] = clips
        return tr
    }

    static func clip(_ c: [String: Any], pages: [Any], length: Any) -> [String: Any] {
        var out: [String: Any] = ["pages": pages, "length": length]
        for k in ["playFrom", "playTo", "scale", "root"] {
            if let v = c[k] { out[k] = v }
        }
        if let fx = c["fx"] { out["fx"] = filtered(fx, Set(Params.fxDefaults().keys)) }
        return out
    }

    static func convertPages(_ v: Any?) -> [Any] {
        var out: [Any] = []
        for page in v as? [Any] ?? [] {
            var steps: [Any] = []
            for item in page as? [Any] ?? [] {
                guard var s = item as? [String: Any] else {
                    steps.append([String: Any]())
                    continue
                }
                if let snd = s["sound"] as? String { s["sound"] = key(snd) }
                steps.append(s)
            }
            out.append(steps)
        }
        return out
    }

    /// Папка: сэмплы (ключ без 's:') и пресеты синта — как есть (таблица пресета — как у дорожки).
    static func folder(_ f: [String: Any]) -> [String: Any] {
        var items: [Any] = []
        for item in f["items"] as? [Any] ?? [] {
            guard let it = item as? [String: Any] else { continue }
            if let s = it["sample"] as? String {
                items.append(["sample": key(s)])
            } else if var p = it["preset"] as? [String: Any] {
                if let t = p["table"] as? String { p["table"] = table(t) }
                items.append(["preset": p])
            }
        }
        return ["items": items, "index": f["index"] ?? -1]
    }

    static func filtered(_ v: Any?, _ keys: Set<String>) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, x) in v as? [String: Any] ?? [:] where keys.contains(k) { out[k] = x }
        return out
    }

    static func rekeyed(_ v: Any?) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, x) in v as? [String: Any] ?? [:] { out[key(k)] = x }
        return out
    }
}
