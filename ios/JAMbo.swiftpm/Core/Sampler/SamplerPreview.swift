import Foundation

// Предпрослушка (▶ редактора сэмпла): сэмпл в исходной высоте сразу на выход, мимо голосов и микшера.

extension Sampler {
    /// ▶ редактора: сэмпл hash от a до b (доли) в исходной высоте сразу на выход; новая обрывает прошлую.
    public func preview(hash: UInt64, a: Double, b: Double, at: Int64) {
        guard let d = sound else { return }
        let e = d.anyEntry(hash)
        if e < 0 { return }
        let f = Double(d.eFrames[e])
        pvL = d.eLeft[e]
        pvR = d.eRight[e]
        pvStereo = d.eChannels[e] == 2
        pvPos = Swift.max(0, Swift.min(1, a)) * f
        pvEnd = Swift.max(0, Swift.min(1, b)) * f
        pvGain = Sampler.previewGain
        pvStop = false
        _ = out.push(.start(voice: Sampler.previewVoice, track: -1, hash: hash, frame: at, a: pvPos / f, b: pvEnd / f,
                            rate: 1, frames: d.eFrames[e]))
    }

    public func stopPreview() {
        if pvL != nil { pvStop = true }
    }

    public var previewing: Bool { return pvL != nil }

    func renderPreview(_ n: Int, _ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>) {
        guard let l = pvL, let r = pvR else { return }
        let k = Float(exp(-1 / (0.005 * sr)))
        for i in 0..<n {
            if pvPos >= pvEnd || pvGain < 0.0005 {
                pvL = nil
                pvR = nil
                _ = out.push(.end(voice: Sampler.previewVoice))
                return
            }
            let j = Int(pvPos)
            let remain = Float((pvEnd - pvPos) / (0.004 * sr))
            let g = pvGain * Swift.min(1, remain)
            let xl = l[j]
            let xr = pvStereo ? r[j] : xl
            left[i] += xl * g
            right[i] += xr * g
            pvPos += 1
            if pvStop { pvGain *= k }
        }
    }
}
