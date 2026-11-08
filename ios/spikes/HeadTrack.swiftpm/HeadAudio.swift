// Пробный прототип: тестовый звук, привязанный к iPad, а не к голове.
// Источник — пачки розового шума (150 мс звук, 250 мс тишина) в направлении SOURCE. При повороте головы на угол
// yaw источник относительно головы — на угле SOURCE − yaw. Простая модель головы-шара: разница времени прихода —
// формула Вудвортса, тень головы — фильтр Брауна — Дуды. Это не FABIAN и не комнаты JAMbo: проверяем только
// трекинг и задержку «поворот → звук».

import AVFoundation

final class HTAudio {
    let engine = AVAudioEngine()
    let shared: HTShared
    // Состояние колбэка (выделено заранее, в колбэке без выделения памяти и ARC).
    private let ring: UnsafeMutablePointer<Float>      // 2048 отсчётов, линия задержки источника
    private let fs: UnsafeMutablePointer<Float>        // 0–2 розовый шум, 3 угол, 4–5 задержки ушей, 6–9 фильтры, 10 огибающая
    private let ints: UnsafeMutablePointer<Int>        // 0 запись, 1 фаза пачки, 2 генератор шума
    private var node: AVAudioSourceNode? = nil
    var error: String = ""

    init(shared: HTShared) {
        self.shared = shared
        ring = UnsafeMutablePointer<Float>.allocate(capacity: 2048)
        ring.initialize(repeating: 0, count: 2048)
        fs = UnsafeMutablePointer<Float>.allocate(capacity: 16)
        fs.initialize(repeating: 0, count: 16)
        fs[4] = 2
        fs[5] = 2
        ints = UnsafeMutablePointer<Int>.allocate(capacity: 4)
        ints.initialize(repeating: 0, count: 4)
        ints[2] = 22222
    }

    func start() {
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playback, mode: .default, options: [])
            try s.setPreferredSampleRate(48000)
            try s.setPreferredIOBufferDuration(256.0 / 48000.0)
            try s.setActive(true)
        } catch {
            self.error = "Audio session: " + error.localizedDescription
        }
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else { return }
        let n = makeNode(fmt)
        node = n
        engine.attach(n)
        engine.connect(n, to: engine.mainMixerNode, format: fmt)
        do {
            try engine.start()
        } catch {
            self.error = "Audio engine: " + error.localizedDescription
        }
    }

    // Задержка выхода (мс), буфер (мс), выход.
    func latency() -> (Double, Double, String) {
        let s = AVAudioSession.sharedInstance()
        let out: Double = s.outputLatency * 1000
        let buf: Double = s.ioBufferDuration * 1000
        var names: [String] = []
        for p in s.currentRoute.outputs {
            names.append(p.portName + " (" + p.portType.rawValue + ")")
        }
        return (out, buf, names.joined(separator: ", "))
    }

    private func makeNode(_ fmt: AVAudioFormat) -> AVAudioSourceNode {
        let sh: UnsafeMutablePointer<Float> = shared.cell
        let r: UnsafeMutablePointer<Float> = ring
        let f: UnsafeMutablePointer<Float> = fs
        let iv: UnsafeMutablePointer<Int> = ints
        return AVAudioSourceNode(format: fmt) { _, _, frameCount, abl -> OSStatus in
            let bufs = UnsafeMutableAudioBufferListPointer(abl)
            if bufs.count < 2 { return noErr }
            guard let pl = bufs[0].mData?.assumingMemoryBound(to: Float.self),
                  let pr = bufs[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let n: Int = Int(frameCount)
            // Угол источника относительно головы (вправо +), не дальше ±90°.
            var yaw: Float = sh[0]
            if sh[1] < 0.5 { yaw = 0 }
            var th: Float = sh[2] - yaw
            if th > 1.5708 { th = 1.5708 }
            if th < -1.5708 { th = -1.5708 }
            let prevTh: Float = f[3]
            let newTh: Float = prevTh + (th - prevTh) * 0.5
            f[3] = newTh
            // Разница времени прихода (Вудвортс), отсчётов при 48 кГц: a = 8,75 см, c = 343 м/с.
            let itd: Float = 12.2449 * (sinf(newTh) + newTh)
            let dLt: Float = 2 + (itd > 0 ? itd : 0)
            let dRt: Float = 2 + (itd < 0 ? -itd : 0)
            // Тень головы (Браун — Дуда): угол от уха, α = 1,05 + 0,95·cos(угол / 150° · 180°).
            let thDeg: Float = newTh * 57.29578
            let relL: Float = thDeg + 90
            let relR: Float = 90 - thDeg
            let aL: Float = 1.05 + 0.95 * cosf(relL * 0.020944)
            let aR: Float = 1.05 + 0.95 * cosf(relR * 0.020944)
            let k: Float = 12.245
            let a0: Float = 1 + k
            let a1: Float = 1 - k
            let bL0: Float = 1 + aL * k
            let bL1: Float = 1 - aL * k
            let bR0: Float = 1 + aR * k
            let bR1: Float = 1 - aR * k
            let dL0: Float = f[4]
            let dR0: Float = f[5]
            let invN: Float = 1 / Float(n > 0 ? n : 1)
            var w: Int = iv[0]
            var ph: Int = iv[1]
            var seed: UInt32 = UInt32(truncatingIfNeeded: iv[2])
            var b0: Float = f[0]
            var b1: Float = f[1]
            var b2: Float = f[2]
            var env: Float = f[10]
            var xl1: Float = f[6]
            var yl1: Float = f[7]
            var xr1: Float = f[8]
            var yr1: Float = f[9]
            var i: Int = 0
            while i < n {
                seed = seed &* 1664525 &+ 1013904223
                let white: Float = Float(Int32(bitPattern: seed)) * 4.656613e-10
                b0 = 0.99765 * b0 + white * 0.0990460
                b1 = 0.96300 * b1 + white * 0.2965164
                b2 = 0.57000 * b2 + white * 1.0526913
                let pink: Float = (b0 + b1 + b2 + white * 0.1848) * 0.2
                let target: Float = ph < 7200 ? 1 : 0
                env += (target - env) * 0.004
                ph += 1
                if ph >= 19200 { ph = 0 }
                r[w] = pink * env * 0.25
                let t: Float = Float(i) * invN
                let dl: Float = dL0 + (dLt - dL0) * t
                let dr: Float = dR0 + (dRt - dR0) * t
                let posL: Float = Float(w) - dl
                let flL: Float = floorf(posL)
                let frL: Float = posL - flL
                let iL: Int = Int(flL) & 2047
                let sL: Float = r[iL] * (1 - frL) + r[(iL + 1) & 2047] * frL
                let posR: Float = Float(w) - dr
                let flR: Float = floorf(posR)
                let frR: Float = posR - flR
                let iR: Int = Int(flR) & 2047
                let sR: Float = r[iR] * (1 - frR) + r[(iR + 1) & 2047] * frR
                let yl: Float = (bL0 * sL + bL1 * xl1 - a1 * yl1) / a0
                let yr: Float = (bR0 * sR + bR1 * xr1 - a1 * yr1) / a0
                xl1 = sL
                yl1 = yl
                xr1 = sR
                yr1 = yr
                pl[i] = yl
                pr[i] = yr
                w = (w + 1) & 2047
                i += 1
            }
            if abs(yl1) < 1e-20 { yl1 = 0 }
            if abs(yr1) < 1e-20 { yr1 = 0 }
            iv[0] = w
            iv[1] = ph
            iv[2] = Int(seed)
            f[0] = b0
            f[1] = b1
            f[2] = b2
            f[4] = dLt
            f[5] = dRt
            f[6] = xl1
            f[7] = yl1
            f[8] = xr1
            f[9] = yr1
            f[10] = env
            return noErr
        }
    }
}
