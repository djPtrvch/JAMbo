import Foundation

// CUT в редакторе сэмпла (docs/ai/sound-sampler.md): вырезать выделенное маркерами обрезки и склеить остальное;
// на стыке — кроссфейд 5 мс. Маркеры нарезки и метки WARP после вырезанного сдвигаются, внутри — удаляются.

extension SampleEdit {
    /// Кроссфейд на стыке, кадров (5 мс на 48 кГц).
    public static let cutFade: Int = 240

    /// Вырезаемые кадры i0..<i1 для выделения a…b (доли длины) — как у TRIM; nil — нечего или всё.
    public static func cutRange(_ frames: Int, _ a: Double, _ b: Double) -> (Int, Int)? {
        let n: Double = Double(frames)
        let i0: Int = Swift.max(0, Swift.min(frames, Int((Swift.min(a, b) * n).rounded())))
        let i1: Int = Swift.max(i0, Swift.min(frames, Int((Swift.max(a, b) * n).rounded())))
        if i1 <= i0 || i1 - i0 >= frames { return nil }
        return (i0, i1)
    }

    /// CUT: без кадров i0..<i1. Длина — frames − (i1 − i0); на стыке левая часть продолжается в вырезанное и гаснет,
    /// правая нарастает (длина и места меток не меняются).
    public static func cut(_ s: SampleData, _ a: Double, _ b: Double) -> SampleData {
        guard let (i0, i1) = cutRange(s.frames, a, b) else { return trim(s, 0, 1) }
        let n: Int = s.frames - (i1 - i0)
        let stereo: Bool = s.channels == 2
        let out = SampleData(frames: n, stereo: stereo)
        let fade: Int = i0 > 0 ? Swift.min(cutFade, s.frames - i1) : 0
        out.left.update(from: s.left, count: i0)
        out.left.advanced(by: i0).update(from: s.left + i1, count: s.frames - i1)
        if stereo {
            out.right.update(from: s.right, count: i0)
            out.right.advanced(by: i0).update(from: s.right + i1, count: s.frames - i1)
        }
        // Кроссфейд: out[i0 + k] = A[i0 + k]·(1 − w) + B[i1 + k]·w.
        let chans: Int = stereo ? 2 : 1
        var c = 0
        while c < chans {
            let src = c == 0 ? s.left : s.right
            let dst = c == 0 ? out.left : out.right
            var k = 0
            while k < fade {
                let w: Float = Float(k + 1) / Float(fade + 1)
                dst[i0 + k] = src[i0 + k] * (1 - w) + src[i1 + k] * w
                k += 1
            }
            c += 1
        }
        return out
    }

    /// Место f (доля длины) после CUT кадров i0..<i1 из frames; nil — внутри вырезанного.
    public static func cutPlace(_ f: Double, _ frames: Int, _ i0: Int, _ i1: Int) -> Double? {
        let p: Double = f * Double(frames)
        let n: Double = Double(frames - (i1 - i0))
        if p <= Double(i0) { return p / n }
        if p < Double(i1) { return nil }
        return (p - Double(i1 - i0)) / n
    }
}

extension Track {
    /// CUT: маркеры нарезки и метки WARP сэмпла old — к копии new. После вырезанного — сдвиг (метки WARP — и по
    /// долям, на длину вырезанного по карте), внутри — удаляются; метка на стыке — одна. С метками BPM файла
    /// закрепляется (копия определила бы свой — звук до первой и после последней метки поменялся бы).
    public mutating func carryCut(_ old: String, _ new: String, frames: Int, _ i0: Int, _ i1: Int,
                                  detectedBpm: Double) {
        if old.isEmpty || new.isEmpty { return }
        let n: Int = frames - (i1 - i0)
        let gap: Double = WarpMap.minFrames / Double(Swift.max(1, n))
        var marks: [SliceMark] = []
        for m in sliceMarks(old) {
            guard let at = SampleEdit.cutPlace(m.at, frames, i0, i1) else { continue }
            if let last = marks.last, at - last.at < gap { continue }
            marks.append(SliceMark(at: at, note: m.note, role: m.role))
        }
        putMarks(new, marks)
        let w = warpInfo(old)
        if w.isEmpty { return }
        var out = WarpInfo(bpm: w.bpm, marks: [])
        out.off = w.off
        if !w.marks.isEmpty {
            let bpm: Double = WarpMap.bpm(w, detected: detectedBpm)
            let map = WarpMap(w, frames: frames, bpm: bpm)
            let span: Double = map.beat(Double(i1)) - map.beat(Double(i0))
            out.bpm = bpm
            for m in w.marks {
                guard let at = SampleEdit.cutPlace(m.at, frames, i0, i1) else { continue }
                let beat: Double = m.at * Double(frames) >= Double(i1) ? m.beat - span : m.beat
                if let last = out.marks.last, at - last.at < gap || beat - last.beat < WarpMap.minBeat { continue }
                out.marks.append(WarpMark(at: at, beat: beat))
            }
        }
        putWarp(new, out)
    }
}

extension Track {
    /// TRIM (оставлены кадры i0..<i1 из frames): маркеры нарезки и метки WARP сэмпла old — к копии new; вне
    /// оставленного — удаляются, внутри — на прежнем месте звука. Доли меток — со сдвигом на целое число долей начала
    /// (сетка та же); с метками BPM файла закрепляется. NORMALIZE и MONO — i0 = 0, i1 = frames (всё как было).
    public mutating func carryTrim(_ old: String, _ new: String, frames: Int, _ i0: Int, _ i1: Int,
                                   detectedBpm: Double) {
        if old.isEmpty || new.isEmpty || i1 <= i0 { return }
        let n: Double = Double(i1 - i0)
        let a: Double = Double(i0)
        let b: Double = Double(i1)
        var marks: [SliceMark] = []
        for m in sliceMarks(old) {
            let p: Double = m.at * Double(frames)
            if p < a || p >= b { continue }
            marks.append(SliceMark(at: (p - a) / n, note: m.note, role: m.role))
        }
        putMarks(new, marks)
        let w = warpInfo(old)
        if w.isEmpty { return }
        var out = WarpInfo(bpm: w.bpm, marks: [])
        out.off = w.off
        if !w.marks.isEmpty {
            let bpm: Double = WarpMap.bpm(w, detected: detectedBpm)
            let map = WarpMap(w, frames: frames, bpm: bpm)
            let shift: Double = i0 > 0 ? map.beat(a).rounded(.down) : 0
            out.bpm = bpm
            for m in w.marks {
                let p: Double = m.at * Double(frames)
                if p < a || p > b { continue }
                out.marks.append(WarpMark(at: (p - a) / n, beat: m.beat - shift))
            }
        }
        putWarp(new, out)
    }
}
