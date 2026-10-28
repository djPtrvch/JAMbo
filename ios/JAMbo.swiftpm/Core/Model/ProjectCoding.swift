import Foundation

// Чтение проекта из JSON (S9a, как normalizeDoc веба): недостающие поля — значения по умолчанию, неизвестные
// пропускаются, поле не того типа — тоже по умолчанию. Так файлы прежних версий открываются, когда в модели
// появляются новые поля. Запись — синтезированная, по тем же CodingKeys: новое поле модели — добавить и сюда.

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
    enum CodingKeys: String, CodingKey, CaseIterable { case lfo, amount, track }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lfo = c.value(.lfo, 1)
        amount = c.value(.amount, 0)
        track = c.optional(.track)
    }
}

extension Step {
    enum CodingKeys: String, CodingKey, CaseIterable { case on, len, notes, lens, vels, locks, sound, soundLocks }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = c.value(.on, false)
        len = c.value(.len, 1)
        notes = c.value(.notes, [Int]())
        lens = c.optional(.lens)
        vels = c.optional(.vels)
        locks = c.value(.locks, [String: Double]())
        sound = c.optional(.sound)
        soundLocks = c.optional(.soundLocks)
    }
}

extension Track {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, sample, params, clips, slot, open, mute, solo, stopped, folder, slices, vol, trim, table, grain, assigns,
             morphOrig, morphOrigAssign, morphEdited, eq, home, midi, blocks, color, autos, warps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, Int.random(in: 0..<(1 << 31)))
        name = c.value(.name, "")
        sample = c.value(.sample, "")
        params = c.value(.params, [String: Double]())
        clips = c.value(.clips, Track.firstClips())
        slot = c.value(.slot, 0)
        open = c.value(.open, 0)
        mute = c.value(.mute, false)
        solo = c.value(.solo, false)
        stopped = c.value(.stopped, false)
        folder = c.value(.folder, Folder())
        slices = c.value(.slices, [String: [SliceMark]]())
        warps = c.value(.warps, [String: WarpInfo]())
        vol = c.value(.vol, Params.volDef)
        trim = c.value(.trim, 0)
        table = c.value(.table, "")
        grain = c.value(.grain, "")
        assigns = c.value(.assigns, [String: ModAssign]())
        morphOrig = c.value(.morphOrig, [String: Double]())
        morphOrigAssign = c.value(.morphOrigAssign, [String: ModAssign?]())
        morphEdited = c.value(.morphEdited, false)
        eq = c.value(.eq, Eq())
        home = c.optional(.home)
        midi = c.value(.midi, TrackMidi())
        blocks = c.value(.blocks, [ArrBlock]())
        color = c.value(.color, ArrPalette.defaultColor)
        autos = c.value(.autos, [ArrAutoLane]())
    }
}

extension Clip {
    enum CodingKeys: String, CodingKey, CaseIterable { case pages, length, playFrom, playTo, scale, root, fx, src, rate }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pages = c.value(.pages, [Track.emptyPage()])
        length = c.value(.length, Params.stepsPerPage)
        playFrom = c.value(.playFrom, 0)
        playTo = c.value(.playTo, 0)
        scale = c.optional(.scale)
        root = c.optional(.root)
        fx = c.optional(.fx)
        src = c.optional(.src)
        rate = c.optional(.rate)
    }
}

extension SceneRow {
    enum CodingKeys: String, CodingKey, CaseIterable { case name, repeats }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.value(.name, "")
        repeats = c.value(.repeats, 1)
    }
}

extension Project {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case version, bpm, scale, root, fx, fxAssigns, master, satBypass, cmpBypass, clipBypass, limBypass, outVol,
             masterEq, tracks, chanSeqs, scenes, rows, arrStart, arrEndStop, plusCopy, files, roots, rowLoop,
             arrowSwitch, prevRow, notice, arrange, gridHideSteps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tracks = c.value(.tracks, [Track]())
        version = c.value(.version, 2)
        bpm = c.value(.bpm, 120)
        scale = c.value(.scale, 0)
        root = c.value(.root, 0)
        fx = c.value(.fx, Params.fxDefaults())
        fxAssigns = c.value(.fxAssigns, [String: ModAssign]())
        master = c.value(.master, MasterChain.defaultValues())
        satBypass = c.value(.satBypass, false)
        cmpBypass = c.value(.cmpBypass, false)
        clipBypass = c.value(.clipBypass, false)
        limBypass = c.value(.limBypass, false)
        outVol = c.value(.outVol, 0)
        masterEq = c.value(.masterEq, Eq())
        chanSeqs = c.value(.chanSeqs, [Track.channel("MIX"), Track.channel("MST")])
        scenes = c.value(.scenes, [SceneRow](repeating: SceneRow(), count: Params.patternSlots))
        rows = c.value(.rows, 1)
        arrStart = c.value(.arrStart, 0)
        arrEndStop = c.value(.arrEndStop, false)
        plusCopy = c.value(.plusCopy, false)
        files = c.value(.files, [String: String]())
        roots = c.value(.roots, [String: Int]())
        rowLoop = c.value(.rowLoop, true)
        arrowSwitch = c.value(.arrowSwitch, false)
        prevRow = c.value(.prevRow, false)
        notice = c.optional(.notice)
        arrange = c.value(.arrange, Arrangement())
        gridHideSteps = c.value(.gridHideSteps, false)
    }
}

extension EqBand {
    enum CodingKeys: String, CodingKey, CaseIterable { case on, type, freq, gain, q, slope, ms, dyn, thr, range }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = c.value(.on, true)
        type = c.value(.type, EqSpec.bell)
        freq = c.value(.freq, 1000)
        gain = c.value(.gain, 0)
        q = c.value(.q, 0.71)
        slope = c.value(.slope, 0)
        ms = c.value(.ms, 0)
        dyn = c.value(.dyn, -1)
        thr = c.value(.thr, EqSpec.dynThrDef)
        range = c.value(.range, EqSpec.dynRangeDef)
    }
}

extension Eq {
    enum CodingKeys: String, CodingKey, CaseIterable { case on, bands }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = c.value(.on, true)
        bands = c.value(.bands, [EqBand?](repeating: nil, count: EqSpec.bands))
        // Сохранённые до 10 полос (8 мест) — дополнить пустыми.
        if bands.count > EqSpec.bands { bands.removeLast(bands.count - EqSpec.bands) }
        while bands.count < EqSpec.bands { bands.append(nil) }
    }
}

extension Folder {
    enum CodingKeys: String, CodingKey, CaseIterable { case items, index }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.value(.items, [FolderItem]())
        index = c.value(.index, -1)
    }
}

extension SliceMark {
    enum CodingKeys: String, CodingKey, CaseIterable { case at, note }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = c.value(.at, 0)
        note = c.optional(.note)
    }
}
