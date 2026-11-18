import Foundation

// Чтение проекта из JSON (S9a): недостающие поля — значения по умолчанию, неизвестные
// пропускаются, поле не того типа — тоже по умолчанию. Так файлы прежних версий открываются, когда в модели
// появляются новые поля. Запись — своя, по тем же ключам, что чтение (общий CaseKey — без перечислений CodingKeys: объём сборки, 18.11):
// новое поле модели — добавить в чтение, запись и список ключей в ProjectFileTests.testCodingKeysCoverAllFields.

extension KeyedDecodingContainer {
    /// Поле или значение по умолчанию.
    func value<T: Decodable>(_ key: Key, _ def: T) -> T {
        return (try? decodeIfPresent(T.self, forKey: key)) ?? def
    }

    /// Необязательное поле (нет или не того типа — nil).
    func optional<T: Decodable>(_ key: Key) -> T? {
        return (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}

extension ModAssign {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        lfo = c.value(CaseKey("lfo"), 1)
        amount = c.value(CaseKey("amount"), 0)
        track = c.optional(CaseKey("track"))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(lfo, forKey: CaseKey("lfo"))
        try c.encode(amount, forKey: CaseKey("amount"))
        try c.encodeIfPresent(track, forKey: CaseKey("track"))
    }
}

extension Step {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        on = c.value(CaseKey("on"), false)
        len = c.value(CaseKey("len"), 1)
        notes = c.value(CaseKey("notes"), [Int]())
        lens = c.optional(CaseKey("lens"))
        vels = c.optional(CaseKey("vels"))
        locks = c.value(CaseKey("locks"), [String: Double]())
        sound = c.optional(CaseKey("sound"))
        soundLocks = c.optional(CaseKey("soundLocks"))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(on, forKey: CaseKey("on"))
        try c.encode(len, forKey: CaseKey("len"))
        try c.encode(notes, forKey: CaseKey("notes"))
        try c.encodeIfPresent(lens, forKey: CaseKey("lens"))
        try c.encodeIfPresent(vels, forKey: CaseKey("vels"))
        try c.encode(locks, forKey: CaseKey("locks"))
        try c.encodeIfPresent(sound, forKey: CaseKey("sound"))
        try c.encodeIfPresent(soundLocks, forKey: CaseKey("soundLocks"))
    }
}

extension Track {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        id = c.value(CaseKey("id"), Int.random(in: 0..<(1 << 31)))
        name = c.value(CaseKey("name"), "")
        sample = c.value(CaseKey("sample"), "")
        params = c.value(CaseKey("params"), [String: Double]())
        clips = c.value(CaseKey("clips"), Track.firstClips())
        slot = c.value(CaseKey("slot"), 0)
        open = c.value(CaseKey("open"), 0)
        mute = c.value(CaseKey("mute"), false)
        solo = c.value(CaseKey("solo"), false)
        stopped = c.value(CaseKey("stopped"), false)
        folder = c.value(CaseKey("folder"), Folder())
        slices = c.value(CaseKey("slices"), [String: [SliceMark]]())
        warps = c.value(CaseKey("warps"), [String: WarpInfo]())
        vol = c.value(CaseKey("vol"), Params.volDef)
        trim = c.value(CaseKey("trim"), 0)
        table = c.value(CaseKey("table"), "")
        grain = c.value(CaseKey("grain"), "")
        assigns = c.value(CaseKey("assigns"), [String: ModAssign]())
        morphOrig = c.value(CaseKey("morphOrig"), [String: Double]())
        morphOrigAssign = c.value(CaseKey("morphOrigAssign"), [String: ModAssign?]())
        morphEdited = c.value(CaseKey("morphEdited"), false)
        eq = c.value(CaseKey("eq"), Eq())
        home = c.optional(CaseKey("home"))
        midi = c.value(CaseKey("midi"), TrackMidi())
        blocks = c.value(CaseKey("blocks"), [ArrBlock]())
        color = c.value(CaseKey("color"), ArrPalette.defaultColor)
        autos = c.value(CaseKey("autos"), [ArrAutoLane]())
        drumStyle = DrumRhythm.styleIndex(c.value(CaseKey("drumStyle"), 0))
        arp = c.value(CaseKey("arp"), TrackArp())
        keyOctave = c.value(CaseKey("keyOctave"), Scales.octaveDef)
        migrateAutos()
        dropLegacyLinks()
    }

    /// Запись — как прежняя синтезированная (home — только если есть; editBlock не пишется).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(id, forKey: CaseKey("id"))
        try c.encode(name, forKey: CaseKey("name"))
        try c.encode(sample, forKey: CaseKey("sample"))
        try c.encode(params, forKey: CaseKey("params"))
        try c.encode(clips, forKey: CaseKey("clips"))
        try c.encode(slot, forKey: CaseKey("slot"))
        try c.encode(open, forKey: CaseKey("open"))
        try c.encode(mute, forKey: CaseKey("mute"))
        try c.encode(solo, forKey: CaseKey("solo"))
        try c.encode(stopped, forKey: CaseKey("stopped"))
        try c.encode(folder, forKey: CaseKey("folder"))
        try c.encode(slices, forKey: CaseKey("slices"))
        try c.encode(vol, forKey: CaseKey("vol"))
        try c.encode(trim, forKey: CaseKey("trim"))
        try c.encode(table, forKey: CaseKey("table"))
        try c.encode(grain, forKey: CaseKey("grain"))
        try c.encode(assigns, forKey: CaseKey("assigns"))
        try c.encode(morphOrig, forKey: CaseKey("morphOrig"))
        try c.encode(morphOrigAssign, forKey: CaseKey("morphOrigAssign"))
        try c.encode(morphEdited, forKey: CaseKey("morphEdited"))
        try c.encode(eq, forKey: CaseKey("eq"))
        try c.encodeIfPresent(home, forKey: CaseKey("home"))
        try c.encode(midi, forKey: CaseKey("midi"))
        try c.encode(blocks, forKey: CaseKey("blocks"))
        try c.encode(color, forKey: CaseKey("color"))
        try c.encode(autos, forKey: CaseKey("autos"))
        try c.encode(warps, forKey: CaseKey("warps"))
        try c.encode(drumStyle, forKey: CaseKey("drumStyle"))
        try c.encode(arp, forKey: CaseKey("arp"))
        try c.encode(keyOctave, forKey: CaseKey("keyOctave"))
    }
}

extension Clip {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        pages = c.value(CaseKey("pages"), [Track.emptyPage()])
        length = c.value(CaseKey("length"), Params.stepsPerPage)
        playFrom = c.value(CaseKey("playFrom"), 0)
        playTo = c.value(CaseKey("playTo"), 0)
        scale = c.optional(CaseKey("scale"))
        root = c.optional(CaseKey("root"))
        fx = c.optional(CaseKey("fx"))
        src = c.optional(CaseKey("src"))
        rate = c.optional(CaseKey("rate"))
    }

    /// Запись — как прежняя синтезированная (необязательные — только если есть).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(pages, forKey: CaseKey("pages"))
        try c.encode(length, forKey: CaseKey("length"))
        try c.encode(playFrom, forKey: CaseKey("playFrom"))
        try c.encode(playTo, forKey: CaseKey("playTo"))
        try c.encodeIfPresent(scale, forKey: CaseKey("scale"))
        try c.encodeIfPresent(root, forKey: CaseKey("root"))
        try c.encodeIfPresent(fx, forKey: CaseKey("fx"))
        try c.encodeIfPresent(src, forKey: CaseKey("src"))
        try c.encodeIfPresent(rate, forKey: CaseKey("rate"))
    }
}

extension SceneRow {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        name = c.value(CaseKey("name"), "")
        repeats = c.value(CaseKey("repeats"), 1)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(name, forKey: CaseKey("name"))
        try c.encode(repeats, forKey: CaseKey("repeats"))
    }
}

extension Project {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        tracks = c.value(CaseKey("tracks"), [Track]())
        version = c.value(CaseKey("version"), 2)
        bpm = c.value(CaseKey("bpm"), 120)
        scale = c.value(CaseKey("scale"), 0)
        root = c.value(CaseKey("root"), 0)
        fx = c.value(CaseKey("fx"), Params.fxDefaults())
        fxAssigns = c.value(CaseKey("fxAssigns"), [String: ModAssign]())
        master = c.value(CaseKey("master"), MasterChain.defaultValues())
        satBypass = c.value(CaseKey("satBypass"), false)
        cmpBypass = c.value(CaseKey("cmpBypass"), false)
        clipBypass = c.value(CaseKey("clipBypass"), false)
        limBypass = c.value(CaseKey("limBypass"), false)
        outVol = c.value(CaseKey("outVol"), 0)
        masterEq = c.value(CaseKey("masterEq"), Eq())
        chanSeqs = c.value(CaseKey("chanSeqs"), [Track.channel("MIX"), Track.channel("MST")])
        scenes = c.value(CaseKey("scenes"), [SceneRow](repeating: SceneRow(), count: Params.patternSlots))
        rows = c.value(CaseKey("rows"), 1)
        arrStart = c.value(CaseKey("arrStart"), 0)
        arrEndStop = c.value(CaseKey("arrEndStop"), false)
        plusCopy = c.value(CaseKey("plusCopy"), false)
        files = c.value(CaseKey("files"), [String: String]())
        roots = c.value(CaseKey("roots"), [String: Int]())
        rowLoop = c.value(CaseKey("rowLoop"), true)
        arrowSwitch = c.value(CaseKey("arrowSwitch"), false)
        prevRow = c.value(CaseKey("prevRow"), false)
        notice = c.optional(CaseKey("notice"))
        arrange = c.value(CaseKey("arrange"), Arrangement())
        gridHideSteps = c.value(CaseKey("gridHideSteps"), false)
    }

    /// Запись — как прежняя синтезированная (notice — только если есть).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(version, forKey: CaseKey("version"))
        try c.encode(bpm, forKey: CaseKey("bpm"))
        try c.encode(scale, forKey: CaseKey("scale"))
        try c.encode(root, forKey: CaseKey("root"))
        try c.encode(fx, forKey: CaseKey("fx"))
        try c.encode(fxAssigns, forKey: CaseKey("fxAssigns"))
        try c.encode(master, forKey: CaseKey("master"))
        try c.encode(satBypass, forKey: CaseKey("satBypass"))
        try c.encode(cmpBypass, forKey: CaseKey("cmpBypass"))
        try c.encode(clipBypass, forKey: CaseKey("clipBypass"))
        try c.encode(limBypass, forKey: CaseKey("limBypass"))
        try c.encode(outVol, forKey: CaseKey("outVol"))
        try c.encode(masterEq, forKey: CaseKey("masterEq"))
        try c.encode(tracks, forKey: CaseKey("tracks"))
        try c.encode(chanSeqs, forKey: CaseKey("chanSeqs"))
        try c.encode(scenes, forKey: CaseKey("scenes"))
        try c.encode(rows, forKey: CaseKey("rows"))
        try c.encode(arrStart, forKey: CaseKey("arrStart"))
        try c.encode(arrEndStop, forKey: CaseKey("arrEndStop"))
        try c.encode(plusCopy, forKey: CaseKey("plusCopy"))
        try c.encode(files, forKey: CaseKey("files"))
        try c.encode(roots, forKey: CaseKey("roots"))
        try c.encode(rowLoop, forKey: CaseKey("rowLoop"))
        try c.encode(arrowSwitch, forKey: CaseKey("arrowSwitch"))
        try c.encode(prevRow, forKey: CaseKey("prevRow"))
        try c.encodeIfPresent(notice, forKey: CaseKey("notice"))
        try c.encode(arrange, forKey: CaseKey("arrange"))
        try c.encode(gridHideSteps, forKey: CaseKey("gridHideSteps"))
    }
}

extension EqBand {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        on = c.value(CaseKey("on"), true)
        type = c.value(CaseKey("type"), EqSpec.bell)
        freq = c.value(CaseKey("freq"), 1000)
        gain = c.value(CaseKey("gain"), 0)
        q = c.value(CaseKey("q"), 0.71)
        slope = c.value(CaseKey("slope"), 0)
        ms = c.value(CaseKey("ms"), 0)
        dyn = c.value(CaseKey("dyn"), -1)
        thr = c.value(CaseKey("thr"), EqSpec.dynThrDef)
        range = c.value(CaseKey("range"), EqSpec.dynRangeDef)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(on, forKey: CaseKey("on"))
        try c.encode(type, forKey: CaseKey("type"))
        try c.encode(freq, forKey: CaseKey("freq"))
        try c.encode(gain, forKey: CaseKey("gain"))
        try c.encode(q, forKey: CaseKey("q"))
        try c.encode(slope, forKey: CaseKey("slope"))
        try c.encode(ms, forKey: CaseKey("ms"))
        try c.encode(dyn, forKey: CaseKey("dyn"))
        try c.encode(thr, forKey: CaseKey("thr"))
        try c.encode(range, forKey: CaseKey("range"))
    }
}

extension Eq {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        on = c.value(CaseKey("on"), true)
        bands = c.value(CaseKey("bands"), [EqBand?](repeating: nil, count: EqSpec.bands))
        // Сохранённые до 10 полос (8 мест) — дополнить пустыми.
        if bands.count > EqSpec.bands { bands.removeLast(bands.count - EqSpec.bands) }
        while bands.count < EqSpec.bands { bands.append(nil) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(on, forKey: CaseKey("on"))
        try c.encode(bands, forKey: CaseKey("bands"))
    }
}

extension Folder {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        items = c.value(CaseKey("items"), [FolderItem]())
        index = c.value(CaseKey("index"), -1)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(items, forKey: CaseKey("items"))
        try c.encode(index, forKey: CaseKey("index"))
    }
}

extension SliceMark {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        at = c.value(CaseKey("at"), 0)
        note = c.optional(CaseKey("note"))
        role = c.optional(CaseKey("role"))
        free = c.optional(CaseKey("free"))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        try c.encode(at, forKey: CaseKey("at"))
        try c.encodeIfPresent(note, forKey: CaseKey("note"))
        try c.encodeIfPresent(role, forKey: CaseKey("role"))
        try c.encodeIfPresent(free, forKey: CaseKey("free"))
    }
}
