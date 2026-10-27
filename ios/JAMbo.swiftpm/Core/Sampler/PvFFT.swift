import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

// БПФ вещественного сигнала для фазового вокодера (StretchPV.swift): вперёд — n отсчётов → бины 0…n/2 (Re, Im; у 0 и
// n/2 Im = 0), назад — бины → n отсчётов. На iPad — vDSP (Accelerate), иначе — своё: комплексное БПФ n/2 точек (чётные
// отсчёты — Re, нечётные — Im) и разделение спектра. Масштаб обратного преобразования — gain (круг вперёд-назад даёт
// gain·x; считается при создании). Создаётся вне колбэка; forward и inverse — без выделений памяти.

final class PvFFT {
    let n: Int
    let half: Int
    let bits: Int
    /// Круг forward → inverse: x → gain·x.
    private(set) var gain: Float = 1
    let cr: UnsafeMutablePointer<Float>
    let ci: UnsafeMutablePointer<Float>
    /// Множители комплексного БПФ (half/2: cos и −sin) и разделения (half + 1: cos и −sin угла −2πk/n).
    let wc: UnsafeMutablePointer<Float>
    let ws: UnsafeMutablePointer<Float>
    let sc: UnsafeMutablePointer<Float>
    let ss: UnsafeMutablePointer<Float>
    let rev: UnsafeMutablePointer<Int>
    #if canImport(Accelerate)
    let setup: FFTSetup
    #endif

    init(size: Int) {
        n = size
        half = size / 2
        var b = 0
        while (1 << b) < half { b += 1 }
        bits = b
        cr = .allocate(capacity: half)
        cr.initialize(repeating: 0, count: half)
        ci = .allocate(capacity: half)
        ci.initialize(repeating: 0, count: half)
        wc = .allocate(capacity: half / 2)
        ws = .allocate(capacity: half / 2)
        for k in 0..<half / 2 {
            let a: Double = -2 * Double.pi * Double(k) / Double(half)
            wc[k] = Float(cos(a))
            ws[k] = Float(sin(a))
        }
        sc = .allocate(capacity: half + 1)
        ss = .allocate(capacity: half + 1)
        for k in 0...half {
            let a: Double = -2 * Double.pi * Double(k) / Double(size)
            sc[k] = Float(cos(a))
            ss[k] = Float(sin(a))
        }
        rev = .allocate(capacity: half)
        for i in 0..<half {
            var r = 0
            var x = i
            for _ in 0..<b {
                r = (r << 1) | (x & 1)
                x >>= 1
            }
            rev[i] = r
        }
        #if canImport(Accelerate)
        setup = vDSP_create_fftsetup(vDSP_Length(b + 1), FFTRadix(kFFTRadix2))!
        #endif
        // Масштаб круга — по импульсу.
        let x = UnsafeMutablePointer<Float>.allocate(capacity: size)
        x.initialize(repeating: 0, count: size)
        x[0] = 1
        let re = UnsafeMutablePointer<Float>.allocate(capacity: half + 1)
        let im = UnsafeMutablePointer<Float>.allocate(capacity: half + 1)
        re.initialize(repeating: 0, count: half + 1)
        im.initialize(repeating: 0, count: half + 1)
        forward(x, re, im)
        inverse(re, im, x)
        gain = x[0] != 0 ? x[0] : 1
        x.deallocate()
        re.deallocate()
        im.deallocate()
    }

    deinit {
        for p in [cr, ci, wc, ws, sc, ss] { p.deallocate() }
        rev.deallocate()
        #if canImport(Accelerate)
        vDSP_destroy_fftsetup(setup)
        #endif
    }

    /// x (n отсчётов) → re, im (n/2 + 1 бинов).
    func forward(_ x: UnsafeMutablePointer<Float>, _ re: UnsafeMutablePointer<Float>, _ im: UnsafeMutablePointer<Float>) {
        let h = half
        #if canImport(Accelerate)
        var sp = DSPSplitComplex(realp: cr, imagp: ci)
        let xc = UnsafeRawPointer(x).assumingMemoryBound(to: DSPComplex.self)
        vDSP_ctoz(xc, 2, &sp, 1, vDSP_Length(h))
        vDSP_fft_zrip(setup, &sp, 1, vDSP_Length(bits + 1), FFTDirection(FFT_FORWARD))
        // vDSP — удвоенный спектр; Nyquist — в imagp[0].
        var k = 1
        while k < h {
            re[k] = 0.5 * cr[k]
            im[k] = 0.5 * ci[k]
            k += 1
        }
        re[0] = 0.5 * cr[0]
        im[0] = 0
        re[h] = 0.5 * ci[0]
        im[h] = 0
        #else
        let cr = self.cr, ci = self.ci, rev = self.rev
        var i = 0
        while i < h {
            let j = rev[i]
            cr[j] = x[2 * i]
            ci[j] = x[2 * i + 1]
            i += 1
        }
        complex(inverse: false)
        // X[k] = (Z[k] + Z*[h−k])/2 + e^(−2πik/n)·(Z[k] − Z*[h−k])/(2i).
        let sc = self.sc, ss = self.ss
        var k = 0
        while k <= h {
            let a = k == h ? 0 : k
            let m = k == 0 ? 0 : h - k
            let zr = cr[a], zi = ci[a], yr = cr[m], yi = -ci[m]
            let er: Float = 0.5 * (zr + yr), ei: Float = 0.5 * (zi + yi)
            let dr: Float = zr - yr, di: Float = zi - yi
            let or: Float = 0.5 * di, oi: Float = -0.5 * dr
            re[k] = er + sc[k] * or - ss[k] * oi
            im[k] = ei + sc[k] * oi + ss[k] * or
            k += 1
        }
        im[0] = 0
        im[h] = 0
        #endif
    }

    /// re, im (n/2 + 1 бинов) → x (n отсчётов, умноженных на gain).
    func inverse(_ re: UnsafeMutablePointer<Float>, _ im: UnsafeMutablePointer<Float>, _ x: UnsafeMutablePointer<Float>) {
        let h = half
        #if canImport(Accelerate)
        var k = 1
        while k < h {
            cr[k] = re[k]
            ci[k] = im[k]
            k += 1
        }
        cr[0] = re[0]
        ci[0] = re[h]
        var sp = DSPSplitComplex(realp: cr, imagp: ci)
        vDSP_fft_zrip(setup, &sp, 1, vDSP_Length(bits + 1), FFTDirection(FFT_INVERSE))
        let xc = UnsafeMutableRawPointer(x).assumingMemoryBound(to: DSPComplex.self)
        vDSP_ztoc(&sp, 1, xc, 2, vDSP_Length(h))
        #else
        // Z[k] = E + i·O: E = (X[k] + X*[h−k])/2, O = (X[k] − X*[h−k])/2 · e^(+2πik/n); z = ОБПФ(Z).
        let cr = self.cr, ci = self.ci, rev = self.rev, sc = self.sc, ss = self.ss
        var k = 0
        while k < h {
            let m = h - k
            let xr = re[k], xi = im[k], yr = re[m], yi = -im[m]
            let er: Float = 0.5 * (xr + yr), ei: Float = 0.5 * (xi + yi)
            let dr: Float = 0.5 * (xr - yr), di: Float = 0.5 * (xi - yi)
            // · e^(+iθ): cos θ = sc, sin θ = −ss.
            let c: Float = sc[k], s: Float = -ss[k]
            let or: Float = dr * c - di * s, oi: Float = dr * s + di * c
            let j = rev[k]
            cr[j] = er - oi
            ci[j] = ei + or
            k += 1
        }
        complex(inverse: true)
        var i = 0
        while i < h {
            x[2 * i] = cr[i]
            x[2 * i + 1] = ci[i]
            i += 1
        }
        #endif
    }

    #if !canImport(Accelerate)
    /// Комплексное БПФ half точек на месте (вход уже в порядке перестановки битов).
    private func complex(inverse inv: Bool) {
        let h = half
        let cr = self.cr, ci = self.ci, wc = self.wc, ws = self.ws
        let sgn: Float = inv ? -1 : 1
        var len = 2
        while len <= h {
            let hl = len / 2
            let step = h / len
            var s = 0
            while s < h {
                var k = 0
                while k < hl {
                    let c = wc[k * step], sn = ws[k * step] * sgn
                    let a = s + k, b = a + hl
                    let tr: Float = cr[b] * c - ci[b] * sn
                    let ti: Float = cr[b] * sn + ci[b] * c
                    cr[b] = cr[a] - tr
                    ci[b] = ci[a] - ti
                    cr[a] += tr
                    ci[a] += ti
                    k += 1
                }
                s += len
            }
            len <<= 1
        }
    }
    #endif
}
