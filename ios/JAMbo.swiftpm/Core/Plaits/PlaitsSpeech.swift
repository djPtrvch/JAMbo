// Перенос движка Plaits 7 — SPEECH (Copyright Emilie Gillet, MIT): speech_engine, naive_speech_synth,
// sam_speech_synth, lpc_speech_synth, lpc_speech_synth_controller. Без режима Words (банков слов нет):
// harmonics не выше 1/3 (group ≤ 2) — Formant, Phoneme (SAM), LPC-фонемы.

/// naive_speech_synth: 5 формант (полосовые фильтры) на импульсном возбуждении.
struct NaiveSpeechSynth {
    static let phonemes: [[[(UInt8, UInt8)]]] = [
        [[(74, 255), (83, 114), (97, 90), (98, 90), (100, 25)], [(75, 255), (84, 128), (100, 114), (101, 101), (103, 20)],
         [(76, 255), (85, 128), (100, 18), (102, 16), (104, 3)], [(79, 255), (85, 161), (101, 25), (104, 4), (110, 0)],
         [(79, 255), (85, 128), (101, 6), (106, 25), (110, 0)]],
        [[(67, 255), (91, 64), (98, 90), (101, 64), (102, 32)], [(67, 255), (92, 51), (99, 64), (103, 51), (105, 25)],
         [(69, 255), (93, 51), (100, 32), (102, 25), (103, 25)], [(67, 255), (91, 16), (100, 8), (103, 4), (110, 0)],
         [(65, 255), (95, 25), (101, 45), (105, 2), (110, 0)]],
        [[(59, 255), (92, 8), (99, 40), (102, 20), (104, 10)], [(61, 255), (94, 45), (101, 32), (103, 25), (105, 8)],
         [(60, 255), (93, 16), (101, 16), (104, 4), (105, 4)], [(65, 255), (92, 25), (100, 8), (105, 4), (110, 0)],
         [(60, 255), (96, 64), (101, 12), (106, 12), (110, 1)]],
        [[(67, 255), (78, 72), (98, 22), (99, 25), (101, 2)], [(67, 255), (79, 80), (99, 64), (101, 64), (102, 12)],
         [(68, 255), (79, 80), (100, 12), (102, 20), (103, 5)], [(69, 255), (79, 90), (101, 40), (104, 10), (110, 0)],
         [(69, 255), (79, 72), (101, 20), (106, 20), (110, 0)]],
        [[(65, 255), (74, 25), (98, 6), (100, 10), (101, 4)], [(65, 255), (74, 25), (100, 36), (101, 51), (103, 12)],
         [(66, 255), (75, 25), (100, 18), (102, 8), (104, 5)], [(63, 255), (77, 64), (99, 8), (104, 2), (110, 0)],
         [(63, 255), (77, 40), (100, 4), (106, 2), (110, 0)]],
    ]
    var pulse = PlaitsOscillator()
    var clickDuration = 0
    var filter = [SvfF](repeating: SvfF(), count: 5)
    var coloration = SvfF()

    init() {
        for i in 0..<5 { filter[i].initialize() }
        coloration.initialize()
        coloration.setFQ(800.0 / 48000, 0.5, .dirty)
    }

    mutating func render(_ click: Bool, _ freq: Float, _ phoneme: Float, _ register: Float,
                         _ excitation: UnsafeMutablePointer<Float>, _ output: UnsafeMutablePointer<Float>,
                         _ size: Int, _ lut: PlaitsLUT) {
        if click { clickDuration = Int(Float(48000) * 0.05) }
        clickDuration -= min(clickDuration, size)
        var frequency = freq
        if clickDuration != 0 { frequency *= 0.5 }
        pulse.render(.impulseTrain, frequency, 0.5, excitation, size)
        for i in 0..<size { excitation[i] = coloration.process(excitation[i], .bandPass) }
        for i in 0..<size { excitation[i] *= 4 }
        let p = phoneme * (5 - 1.001), r = register * (5 - 1.001)
        let pi = trunc32(p), ri = trunc32(r)
        let pf = p - Float(pi), rf = r - Float(ri)
        output.update(repeating: 0, count: size)
        for i in 0..<5 {
            let p0r0 = Self.phonemes[pi][ri][i], p0r1 = Self.phonemes[pi][ri + 1][i]
            let p1r0 = Self.phonemes[pi + 1][ri][i], p1r1 = Self.phonemes[pi + 1][ri + 1][i]
            let p0rf = Float(p0r0.0) + (Float(p0r1.0) - Float(p0r0.0)) * rf
            let p1rf = Float(p1r0.0) + (Float(p1r1.0) - Float(p1r0.0)) * rf
            var f = p0rf + (p1rf - p0rf) * pf
            let p0ra = Float(p0r0.1) + (Float(p0r1.1) - Float(p0r0.1)) * rf
            let p1ra = Float(p1r0.1) + (Float(p1r1.1) - Float(p1r0.1)) * rf
            let a = (p0ra + (p1ra - p0ra) * pf) / 256
            if f >= 160 { f = 160 }
            f = plaitsA0 * lut.semitonesToRatio(f - 33)
            if clickDuration != 0 && i == 0 { f *= 0.5 }
            filter[i].setFQ(f, 20, .dirty)
            for n in 0..<size { output[n] += a * filter[i].process(excitation[n], .bandPass) }
        }
    }
}

/// sam_speech_synth: три синусные форманты с синхронизацией от импульса.
struct SAMSpeechSynth {
    static let phonemes: [[(UInt8, UInt8)]] = [
        [(60, 15), (90, 13), (200, 1)], [(40, 13), (114, 12), (139, 6)], [(33, 14), (155, 12), (209, 7)],
        [(22, 13), (189, 10), (247, 8)], [(51, 15), (99, 12), (195, 1)], [(29, 13), (65, 8), (180, 0)],
        [(13, 12), (103, 3), (182, 0)], [(20, 15), (114, 3), (213, 0)], [(13, 7), (164, 3), (222, 14)],
        [(13, 9), (121, 9), (254, 0)], [(40, 12), (112, 10), (114, 5)], [(24, 13), (54, 8), (157, 0)],
        [(33, 14), (155, 12), (166, 7)], [(36, 14), (83, 8), (249, 1)], [(40, 14), (114, 12), (139, 6)],
        [(13, 5), (58, 5), (182, 5)], [(13, 7), (164, 10), (222, 14)], [(13, 7), (164, 10), (222, 14)],
    ]
    static let amplitudeLut: [Float] = [
        0.03125000, 0.03756299, 0.04515131, 0.05427259, 0.06523652, 0.07841532, 0.09425646, 0.11329776,
        0.13618570, 0.16369736, 0.19676682, 0.23651683, 0.28429697, 0.34172946, 0.41076422, 0.49374509,
    ]
    var phase: Float = 0, frequency: Float = 0, pulseNext: Float = 0, pulseLp: Float = 0
    var formantPhase: (UInt32, UInt32, UInt32) = (0, 0, 0)
    var consonantSamples = 0
    var consonantIndex: Float = 0

    mutating func render(_ consonant: Bool, _ freq: Float, _ vowel: Float, _ shift: Float,
                         _ excitation: UnsafeMutablePointer<Float>, _ output: UnsafeMutablePointer<Float>,
                         _ size: Int, _ lut: PlaitsLUT) {
        let fr = freq >= 0.0625 ? 0.0625 : freq
        if consonant {
            consonantSamples = Int(Float(48000) * 0.05)
            let r = trunc32((vowel + 3 * fr + 7 * shift) * 8)
            consonantIndex = Float(r % 8)
        }
        consonantSamples -= min(consonantSamples, size)
        let phoneme = consonantSamples != 0 ? consonantIndex + 9 : vowel * (9 - 1.0001)
        let pi = trunc32(phoneme)
        let pfr = phoneme - Float(pi)
        let p1 = Self.phonemes[pi], p2 = Self.phonemes[pi + 1]
        let fs = 1 + shift * 2.5
        var ff: (UInt32, UInt32, UInt32) = (0, 0, 0)
        var fa: (Float, Float, Float) = (0, 0, 0)
        for i in 0..<3 {
            let f1 = Float(p1[i].0), f2 = Float(p2[i].0)
            var f = f1 + (f2 - f1) * pfr
            f *= 8 * fs * 4294967296.0 / 48000
            let a1 = Self.amplitudeLut[Int(p1[i].1)], a2 = Self.amplitudeLut[Int(p2[i].1)]
            let a = a1 + (a2 - a1) * pfr
            switch i {
            case 0: ff.0 = u32(f); fa.0 = a
            case 1: ff.1 = u32(f); fa.1 = a
            default: ff.2 = u32(f); fa.2 = a
            }
        }
        var fm = PInterp(frequency, fr, size)
        var next = pulseNext
        for n in 0..<size {
            var this = next
            next = 0
            let f = fm.next()
            phase += f
            if phase >= 1 {
                phase -= 1
                let t = phase / f
                formantPhase.0 = u32(t * Float(ff.0))
                formantPhase.1 = u32(t * Float(ff.1))
                formantPhase.2 = u32(t * Float(ff.2))
                this -= thisBlep(t)
                next -= nextBlep(t)
            } else {
                formantPhase.0 &+= ff.0
                formantPhase.1 &+= ff.1
                formantPhase.2 &+= ff.2
            }
            next += phase
            let d = this - 0.5 - pulseLp
            pulseLp += min(16 * f, 1) * d
            excitation[n] = d
            var s: Float = 0
            s += lut.sine[Int(formantPhase.0 >> 23)] * fa.0
            s += lut.sine[Int(formantPhase.1 >> 23)] * fa.1
            s += lut.sine[Int(formantPhase.2 >> 23)] * fa.2
            s *= (1 - phase)
            output[n] = s
        }
        pulseNext = next
        frequency = fm.value
    }
}

/// Кадр LPC: energy, period, k0…k9.
struct LPCFrame {
    var energy: Int = 0, period: Int = 0
    var k0: Int = 0, k1: Int = 0
    var k: (Int, Int, Int, Int, Int, Int, Int, Int) = (0, 0, 0, 0, 0, 0, 0, 0)
}

/// lpc_speech_synth: решётчатый фильтр 10-го порядка.
final class LPCSpeechSynth {
    var phase: Float = 0, frequency: Float = 0.0125, noiseEnergy: Float = 0, pulseEnergy: Float = 0
    var nextSample: Float = 0
    var pulseIndex = 0
    let k = plaitsBuffer(10)
    let s = plaitsBuffer(11)
    let e = plaitsBuffer(11)
    let lut: PlaitsLUT
    let random: PlaitsRandom

    init(_ lut: PlaitsLUT, _ random: PlaitsRandom) { self.lut = lut; self.random = random }

    @inline(__always) private func pulse(_ i: Int) -> Float { i >= 0 ? Float(lut.lpcPulse[i]) : 0 }

    func render(_ prosody: Float, _ pitchShift: Float, _ excitation: inout Float, _ output: inout Float) {
        let baseF0: Float = 100.0 / 8000
        let d = frequency - baseF0
        var f = (baseF0 + d * prosody) * pitchShift
        constrain(&f, 0, 0.5)
        var next = nextSample
        phase += f
        var this = next
        next = 0
        if phase >= 1 {
            phase -= 1
            let resetTime = phase / f
            let resetSample = trunc32(32 * resetTime)
            var disc: Float = 0
            if pulseIndex < 640 {
                pulseIndex -= resetSample
                disc = pulse(pulseIndex) / 128 * pulseEnergy
            }
            this += -disc * thisBlep(resetTime)
            next += -disc * nextBlep(resetTime)
            pulseIndex = resetSample
        }
        e[10] = Int16(truncatingIfNeeded: random.word() >> 16) > 0 ? noiseEnergy : -noiseEnergy
        if pulseIndex < 640 {
            next += pulse(pulseIndex) / 128 * pulseEnergy
            pulseIndex += 32
        }
        e[10] += this
        e[10] *= 1.5
        var i = 9
        while i >= 0 { e[i] = e[i + 1] - k[i] * s[i]; i -= 1 }
        constrain(&e[0], -2, 2)
        i = 9
        while i >= 1 { s[i] = s[i - 1] + k[i - 1] * e[i - 1]; i -= 1 }
        s[0] = e[0]
        excitation = e[10]
        output = e[0]
        nextSample = next
    }

    func playFrame(_ f1: LPCFrame, _ f2: LPCFrame, _ blend: Float) {
        let fr1 = f1.period == 0 ? frequency : 1 / Float(f1.period)
        let fr2 = f2.period == 0 ? frequency : 1 / Float(f2.period)
        frequency = fr1 + (fr2 - fr1) * blend
        let en1 = Float(f1.energy) / 256, en2 = Float(f2.energy) / 256
        let n1: Float = f1.period == 0 ? en1 : 0, n2: Float = f2.period == 0 ? en2 : 0
        noiseEnergy = n1 + (n2 - n1) * blend
        let p1: Float = f1.period != 0 ? en1 : 0, p2: Float = f2.period != 0 ? en2 : 0
        pulseEnergy = p1 + (p2 - p1) * blend
        @inline(__always) func bl(_ a: Int, _ b: Int, _ scale: Float) -> Float {
            let af = Float(a) / scale, bf = Float(b) / scale
            return af + (bf - af) * blend
        }
        k[0] = bl(f1.k0, f2.k0, 32768)
        k[1] = bl(f1.k1, f2.k1, 32768)
        k[2] = bl(f1.k.0, f2.k.0, 128)
        k[3] = bl(f1.k.1, f2.k.1, 128)
        k[4] = bl(f1.k.2, f2.k.2, 128)
        k[5] = bl(f1.k.3, f2.k.3, 128)
        k[6] = bl(f1.k.4, f2.k.4, 128)
        k[7] = bl(f1.k.5, f2.k.5, 128)
        k[8] = bl(f1.k.6, f2.k.6, 128)
        k[9] = bl(f1.k.7, f2.k.7, 128)
    }
}

/// lpc_speech_synth_controller без банков слов (bank = −1: 5 гласных и 10 согласных фонем).
final class LPCSpeechSynthController {
    var clockPhase: Float = 0
    var sample: (Float, Float) = (0, 0), nextSample: (Float, Float) = (0, 0)
    var gain: Float = 0
    var playbackFrame = -1, lastPlaybackFrame = -1, remaining = 0
    let synth: LPCSpeechSynth
    let phonemes: [LPCFrame]
    let lut: PlaitsLUT

    init(_ lut: PlaitsLUT, _ random: PlaitsRandom) {
        self.lut = lut
        synth = LPCSpeechSynth(lut, random)
        var list: [LPCFrame] = []
        for i in 0..<lut.lpcPhonemeCount {
            let p = lut.lpcPhonemes + i * 12
            var f = LPCFrame()
            f.energy = Int(p[0]); f.period = Int(p[1]); f.k0 = Int(p[2]); f.k1 = Int(p[3])
            f.k = (Int(p[4]), Int(p[5]), Int(p[6]), Int(p[7]), Int(p[8]), Int(p[9]), Int(p[10]), Int(p[11]))
            list.append(f)
        }
        phonemes = list
    }

    private func play(_ frame: Float, interpolate: Bool) {
        let fi = trunc32(frame)
        let ff: Float = interpolate ? frame - Float(fi) : 0
        let last = phonemes.count - 1
        synth.playFrame(phonemes[min(fi, last)], phonemes[min(fi + 1, last)], ff)
    }

    func render(trigger: Bool, _ frequency: Float, _ address: Float, _ formantShift: Float, _ gainIn: Float,
                _ excitation: UnsafeMutablePointer<Float>, _ output: UnsafeMutablePointer<Float>, _ size: Int) {
        let rateRatio = lut.semitonesToRatio((formantShift - 0.5) * 36)
        let rate = rateRatio / 6
        let pitchShift = frequency / (rateRatio * 100 / kCorrectedSampleRate)
        let stretchArg: Float = formantShift < 0.4 ? (formantShift - 0.4) * -45
            : (formantShift > 0.6 ? (formantShift - 0.6) * -45 : 0)
        let timeStretch = lut.semitonesToRatio(-0 * 24 + stretchArg)
        let numFrames = 5
        if trigger {
            let r = trunc32((address + 3 * formantShift + 7 * frequency) * 8)
            playbackFrame = r % 10 + 5
            lastPlaybackFrame = playbackFrame + 1
            remaining = 0
        }
        if playbackFrame == -1 && remaining == 0 {
            play(address * (Float(numFrames) - 1.0001), interpolate: true)
        } else {
            if remaining == 0 {
                play(Float(playbackFrame), interpolate: false)
                remaining = Int(Float(48000) / 40 * timeStretch)
                playbackFrame += 1
                if playbackFrame >= lastPlaybackFrame { playbackFrame = -1 }
            }
            remaining -= min(size, remaining)
        }
        var gm = PInterp(gain, gainIn, size)
        for n in 0..<size {
            var this = nextSample
            nextSample = (0, 0)
            clockPhase += rate
            if clockPhase >= 1 {
                clockPhase -= 1
                let rt = clockPhase / rate
                var ne: Float = 0, no: Float = 0
                synth.render(0, pitchShift, &ne, &no)
                let d0 = ne - sample.0, d1 = no - sample.1
                this.0 += d0 * thisBlep(rt)
                nextSample.0 += d0 * nextBlep(rt)
                this.1 += d1 * thisBlep(rt)
                nextSample.1 += d1 * nextBlep(rt)
                sample = (ne, no)
            }
            nextSample.0 += sample.0
            nextSample.1 += sample.1
            let g = gm.next()
            excitation[n] = this.0 * g
            output[n] = this.1 * g
        }
        gain = gm.value
    }
}

/// 7 — SPEECH: Formant (naive) → Phoneme (SAM) → LPC по harmonics 0…1/3.
final class SpeechEngine: PlaitsEngine {
    let lut: PlaitsLUT
    var naive = NaiveSpeechSynth()
    var sam = SAMSpeechSynth()
    let lpc: LPCSpeechSynthController
    let temp0 = plaitsBuffer(kMaxBlockSize), temp1 = plaitsBuffer(kMaxBlockSize)

    init(_ lut: PlaitsLUT, _ random: PlaitsRandom) {
        self.lut = lut
        lpc = LPCSpeechSynthController(lut, random)
    }
    func reset() {}

    func render(_ p: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ enveloped: inout Bool) {
        let f0 = lut.noteToFrequency(p.note)
        // Ветка слов (group > 2) не используется: банков слов нет.
        let group = min(p.harmonics * 6, 2)
        enveloped = false
        var blend = group
        if group <= 1 {
            naive.render(p.trigger == triggerRisingEdge, f0, p.morph, p.timbre, aux, out, size, lut)
        } else {
            lpc.render(trigger: p.trigger & triggerRisingEdge != 0, f0, p.morph, p.timbre, 1, aux, out, size)
            blend = 2 - blend
        }
        sam.render(p.trigger == triggerRisingEdge, f0, p.morph, p.timbre, temp0, temp1, size, lut)
        blend *= blend * (3 - 2 * blend)
        blend *= blend * (3 - 2 * blend)
        for i in 0..<size {
            aux[i] += (temp0[i] - aux[i]) * blend
            out[i] += (temp1[i] - out[i]) * blend
        }
    }
}
