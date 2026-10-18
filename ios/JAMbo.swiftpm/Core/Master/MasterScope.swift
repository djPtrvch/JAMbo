import Foundation

// Скоп мастера (как setMasterScope веба): точки съёма осциллоскопа — после сатуратора, компрессора, клиппера и
// лимитера (моно (L + R)/2, как форма волны веба), и конечный выход мастера стерео для гониометра. Колбэк пишет
// в кольца только включённые точки (маска ставит интерфейс, пока скоп виден); интерфейс читает новые отсчёты.

public final class MasterScope: @unchecked Sendable {
    public static let sat = 0, comp = 1, clip = 2, lim = 3
    /// Бит гониометра в маске.
    public static let gonioBit = 1 << 4
    /// Точки осциллоскопа: SAT, COMP, CLIP, LIM.
    public let taps: [SpectrumTap] = [SpectrumTap(), SpectrumTap(), SpectrumTap(), SpectrumTap()]
    public let gonioL = SpectrumTap()
    public let gonioR = SpectrumTap()
    /// Биты 0…3 — точки осциллоскопа, gonioBit — гониометр; 0 — скоп выключен.
    public let mask = AtomicCounter()
    let t0: SpectrumTap, t1: SpectrumTap, t2: SpectrumTap, t3: SpectrumTap

    public init() {
        t0 = taps[0]; t1 = taps[1]; t2 = taps[2]; t3 = taps[3]
    }

    /// Колбэк: сигнал после модуля k (если точка включена).
    @inline(__always)
    func tap(_ k: Int, _ m: Int, _ l: UnsafePointer<Float>, _ r: UnsafePointer<Float>, _ n: Int) {
        if m & (1 << k) == 0 { return }
        let t: SpectrumTap = k == 0 ? t0 : (k == 1 ? t1 : (k == 2 ? t2 : t3))
        t.push(l, r, n)
    }

    /// Колбэк: конечный выход мастера (гониометр).
    @inline(__always)
    func gonio(_ l: UnsafePointer<Float>, _ r: UnsafePointer<Float>, _ n: Int) {
        if mask.load() & MasterScope.gonioBit == 0 { return }
        gonioL.push(l, n)
        gonioR.push(r, n)
    }
}
