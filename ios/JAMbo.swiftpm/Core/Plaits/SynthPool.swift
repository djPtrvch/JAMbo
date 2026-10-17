// Голоса синта дорожек (как plaits-worklet.js веба): на дорожку 6 слотов Plaits; голос Sampler со слотом синта
// читает звук слота и ведёт его через ту же цепочку, что и сэмпл (огибающая, Level, фильтр, Pan).
// Слот считается блоками по 24 отсчёта; нота запускается ровно в своём кадре (триггер — один блок),
// параметры — в начале каждого блока (ручки, p-lock шага). Затихший слот (тише 1e-5 дольше 4800 кадров
// после 4800 от начала ноты) больше не считается.
import Foundation

public final class SynthPool {
    public static let slots = 6
    static let block = 24
    static let silence: Int64 = 4800
    static let quiet: Float = 1e-5

    let voices: [PlaitsVoice]
    /// Слот (дорожка·6 + слот): до какого кадра занят, кто играет (ячейка голоса Sampler), счётчик тишины.
    let busyUntil: UnsafeMutablePointer<Int64>
    let owner: UnsafeMutablePointer<Int>
    let ownerStart: UnsafeMutablePointer<Int64>
    let quietFrames: UnsafeMutablePointer<Int64>
    let next: UnsafeMutablePointer<Int>
    /// Звук слотов за блок.
    let buf: UnsafeMutablePointer<Float>
    let renderedAt: UnsafeMutablePointer<Int64>
    let noteShift: Float
    let maxFrames: Int

    public init(lut: PlaitsLUT, sampleRate: Double, maxFrames: Int) {
        let n = SoundData.maxTracks * SynthPool.slots
        voices = (0..<n).map { _ in PlaitsVoice(lut: lut) }
        busyUntil = .allocate(capacity: n)
        busyUntil.initialize(repeating: 0, count: n)
        owner = .allocate(capacity: n)
        owner.initialize(repeating: -1, count: n)
        ownerStart = .allocate(capacity: n)
        ownerStart.initialize(repeating: 0, count: n)
        quietFrames = .allocate(capacity: n)
        quietFrames.initialize(repeating: 0, count: n)
        next = .allocate(capacity: SoundData.maxTracks)
        next.initialize(repeating: 0, count: SoundData.maxTracks)
        buf = .allocate(capacity: n * maxFrames)
        buf.initialize(repeating: 0, count: n * maxFrames)
        renderedAt = .allocate(capacity: n)
        renderedAt.initialize(repeating: -1, count: n)
        // Plaits настроен на 47872,34 Гц: нота сдвигается, чтобы A4 звучала 440 Гц (как в вебе).
        noteShift = Float(12 * log2(47872.34 / sampleRate))
        self.maxFrames = maxFrames
    }

    deinit {
        busyUntil.deallocate()
        owner.deallocate()
        ownerStart.deallocate()
        quietFrames.deallocate()
        next.deallocate()
        buf.deallocate()
        renderedAt.deallocate()
    }

    /// Слот для новой ноты дорожки t в кадре at: свободный (затих к моменту ноты), иначе — следующий по кругу (steal).
    func pick(_ t: Int, _ at: Int64) -> (slot: Int, steal: Bool) {
        let base = t * SynthPool.slots
        for k in 0..<SynthPool.slots {
            let c = (next[t] + k) % SynthPool.slots
            if busyUntil[base + c] <= at {
                next[t] = (c + 1) % SynthPool.slots
                return (c, false)
            }
        }
        let c = next[t]
        next[t] = (c + 1) % SynthPool.slots
        return (c, true)
    }
}

extension Sampler {
    /// Номер движка звука hash дорожки t (свой звук шага или звук дорожки); −1 — не синт.
    @inline(__always)
    func synthEngine(_ d: SoundData, _ t: Int, _ hash: UInt64) -> Int {
        if hash == 0 { return Int(d.engine[t]) }
        var k = 0
        let n = SynthEngines.hashes.count
        while k < n {
            if SynthEngines.hashes[k] == hash { return k }
            k += 1
        }
        return -1
    }

    /// Ноты синта (как triggerTrack веба для синта): слот по кругу, при нехватке прежний голос слота гаснет за ~5 мс,
    /// новая нота — через 8 мс.
    func triggerSynth(track t: Int, engine: Int, at frame: Int64, notes: UnsafePointer<Int16>, count: Int, mask: UInt16,
                      vals: UnsafePointer<Float>?, gate: Int64, own isOwn: Bool, liveId live: Int, retrig: Bool) {
        guard let pool = synth, let d = sound else { return }
        let attack: Double = Swift.max(0.002, pv(d, t, VoiceParam.attack, mask, vals) / 1000)
        let decay: Double = pv(d, t, VoiceParam.decay, mask, vals) / 1000
        let selfDecay = SynthEngines.all[engine].decay
        if !retrig { legatoCut(t, notes, count, frame, attack) }
        let att = attack * sr
        let tail = Int64((Swift.max(0.02, decay) * 2 + 0.05) * sr)
        for k in 0..<count {
            let pick = pool.pick(t, frame)
            let idx = t * SynthPool.slots + pick.slot
            let st: Int64 = pick.steal ? frame + Int64(0.008 * sr) : frame
            // Голос, который ещё звучит в этом слоте, уступает место: гаснет и замолкает к началу новой ноты.
            for v in 0..<Sampler.slots where active[v] != 0 && synthIdx[v] == idx {
                fade(v, at: frame, tau: 0.0015)
                stopAt[v] = Swift.min(stopAt[v], st)
            }
            let v = allocate(frame)
            setupCommon(v, d, t, st, Int(notes[k]), attack, decay, mask, vals)
            synthIdx[v] = idx
            synthEng[v] = engine
            pendingTrig[v] = 1
            srcL[v] = nil
            srcR[v] = nil
            stereo[v] = 0
            own[v] = isOwn ? 1 : 0
            liveId[v] = live
            if selfDecay {
                holdEnd[v] = st + Int64(att.rounded())
                stopAt[v] = holdEnd[v] + Int64(15 * sr)
                pool.busyUntil[idx] = st + Int64((attack + 0.3 + 4 * decay) * sr)
            } else if gate == Int64.max {
                holdEnd[v] = Int64.max
                stopAt[v] = Int64.max
                pool.busyUntil[idx] = Int64.max
            } else {
                let hold: Double = gate < 0 ? att : Swift.max(att, Double(gate))
                holdEnd[v] = st + Int64(hold.rounded())
                stopAt[v] = holdEnd[v] + tail
                pool.busyUntil[idx] = stopAt[v]
            }
        }
    }

    /// Звук слотов, в которых звучат голоса синта, за блок (до голосов).
    func renderSynthSlots(_ d: SoundData, _ blockStart: Int64, _ n: Int) {
        guard let pool = synth else { return }
        for v in 0..<Sampler.slots where active[v] != 0 && synthIdx[v] >= 0 {
            let idx = synthIdx[v]
            if pool.renderedAt[idx] == blockStart { continue }
            pool.renderedAt[idx] = blockStart
            renderSlot(pool, idx, d, blockStart, n)
        }
    }

    private func renderSlot(_ pool: SynthPool, _ idx: Int, _ d: SoundData, _ blockStart: Int64, _ n: Int) {
        let out = pool.buf + idx * pool.maxFrames
        let voice = pool.voices[idx]
        var pos = 0
        while pos < n {
            let frame = blockStart + Int64(pos)
            // Ноты, чей кадр настал (запоздавшие — сразу), по порядку.
            while true {
                var w = -1
                for v in 0..<Sampler.slots where active[v] != 0 && pendingTrig[v] != 0 && synthIdx[v] == idx && start[v] <= frame {
                    if w < 0 || start[v] < start[w] { w = v }
                }
                if w < 0 { break }
                pendingTrig[w] = 0
                pool.owner[idx] = w
                pool.ownerStart[idx] = start[w]
                pool.quietFrames[idx] = 0
                setSynth(voice, w, d, pool, accent: 0.8)
                voice.trigger()
            }
            var m = Swift.min(SynthPool.block, n - pos)
            for v in 0..<Sampler.slots where active[v] != 0 && pendingTrig[v] != 0 && synthIdx[v] == idx && start[v] > frame {
                m = Swift.min(m, Int(start[v] - frame))
            }
            let o = pool.owner[idx]
            if o >= 0 && active[o] != 0 && synthIdx[o] == idx && frame < stopAt[o] {
                setSynth(voice, o, d, pool, accent: 0.8)
                voice.render(m)
                voice.release()
                var peak: Float = 0
                for i in 0..<m {
                    let x = voice.output[i]
                    out[pos + i] = x
                    peak = Swift.max(peak, abs(x))
                }
                pool.quietFrames[idx] = peak < SynthPool.quiet ? pool.quietFrames[idx] + Int64(m) : 0
                if pool.quietFrames[idx] > SynthPool.silence && frame - pool.ownerStart[idx] > SynthPool.silence {
                    stopAt[o] = Swift.min(stopAt[o], frame + Int64(m))
                }
            } else {
                (out + pos).update(repeating: 0, count: m)
            }
            pos += m
        }
    }

    /// Параметры слота от голоса v: движок, нота, ручки 1.1–1.3 (с p-lock шага), Decay у затухающих самих.
    @inline(__always)
    private func setSynth(_ voice: PlaitsVoice, _ v: Int, _ d: SoundData, _ pool: SynthPool, accent: Float) {
        let t = track[v]
        let mask = lockMask[v]
        let base = v * VoiceParam.count
        @inline(__always) func val(_ p: Int) -> Float {
            if mask & (UInt16(1) << UInt16(p)) != 0 { return lockVal[base + p] }
            return d.param(t, p)
        }
        let e = synthEng[v]
        let p = SynthEngines.plaitsParams(e, harm: val(VoiceParam.harm), timbre: val(VoiceParam.timbre),
                                          morph: val(VoiceParam.morph), decayMs: val(VoiceParam.decay))
        voice.set(engine: e, note: Float(note[v]) + pool.noteShift, harmonics: p.h, timbre: p.t, morph: p.m,
                  accent: accent, aux: p.aux)
    }
}
