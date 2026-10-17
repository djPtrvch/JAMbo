// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/oscillator/variable_shape_oscillator.h.

/// Генератор с плавной сменой формы: пила → треугольник/пила с изломом → квадрат с ШИМ; синхронизация
/// от ведущей фазы (hard sync с polyBLEP) и выход фазы для фазовой модуляции.
struct VariableShapeOscillator {
    private var masterPhase: Float = 0
    private var slavePhase: Float = 0
    private var nextSample: Float = 0
    private var previousPw: Float = 0.5
    private var high = false

    private var masterFrequency: Float = 0
    private var slaveFrequency: Float = 0.01
    private var pw: Float = 0.5
    private var waveshape: Float = 0
    private var phaseModulation: Float = 0

    init() {}

    mutating func setMasterPhase(_ phase: Float) { masterPhase = phase }

    /// Без синхронизации.
    @inline(__always)
    mutating func render(_ frequency: Float, _ pw: Float, _ waveshape: Float,
                         _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        render(sync: false, outputPhase: false, 0, frequency, pw, waveshape, 0, out, size)
    }

    /// Синхронизация от ведущей частоты.
    @inline(__always)
    mutating func render(_ masterFrequency: Float, _ frequency: Float, _ pw: Float, _ waveshape: Float,
                         _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        render(sync: true, outputPhase: false, masterFrequency, frequency, pw, waveshape, 0, out, size)
    }

    /// Render<enable_sync, output_phase> оригинала: флаги шаблона — параметры встроенной функции.
    @inline(__always)
    mutating func render(sync enableSync: Bool, outputPhase: Bool,
                         _ masterFrequencyIn: Float, _ frequencyIn: Float, _ pwIn: Float, _ waveshapeIn: Float,
                         _ phaseModulationAmount: Float, _ out: UnsafeMutablePointer<Float>, _ size: Int) {
        var masterFrequencyTarget = masterFrequencyIn
        var frequencyTarget = frequencyIn
        var pwTarget = pwIn
        if masterFrequencyTarget >= kMaxFrequency { masterFrequencyTarget = kMaxFrequency }
        if frequencyTarget >= kMaxFrequency { frequencyTarget = kMaxFrequency }
        if frequencyTarget >= 0.25 {
            pwTarget = 0.5
        } else {
            constrain(&pwTarget, frequencyTarget * 2, 1 - 2 * frequencyTarget)
        }

        var masterFm = ParameterInterpolator(masterFrequency, masterFrequencyTarget, size)
        var fm = ParameterInterpolator(slaveFrequency, frequencyTarget, size)
        var pwm = ParameterInterpolator(pw, pwTarget, size)
        var waveshapeModulation = ParameterInterpolator(waveshape, waveshapeIn, size)
        var phaseModulationInterp = ParameterInterpolator(phaseModulation, phaseModulationAmount, size)

        var next = nextSample
        for i in 0..<size {
            var reset = false
            var transitionDuringReset = false
            var resetTime: Float = 0

            var thisSample = next
            next = 0

            let masterF = masterFm.next()
            let slaveF = fm.next()
            let pwNow = pwm.next()
            let shape = waveshapeModulation.next()

            let squareAmount = max(shape - 0.5, 0) * 2
            let triangleAmount = max(1 - shape * 2, 0)

            let slopeUp = 1 / pwNow
            let slopeDown = 1 / (1 - pwNow)

            if enableSync {
                masterPhase += masterF
                if masterPhase >= 1 {
                    masterPhase -= 1
                    resetTime = masterPhase / masterF

                    var slavePhaseAtReset = slavePhase + (1 - resetTime) * slaveF
                    reset = true
                    if slavePhaseAtReset >= 1 {
                        slavePhaseAtReset -= 1
                        transitionDuringReset = true
                    }
                    if !high && slavePhaseAtReset >= pwNow {
                        transitionDuringReset = true
                    }
                    let value = naiveSample(slavePhaseAtReset, pwNow, slopeUp, slopeDown,
                                            triangleAmount, squareAmount)
                    thisSample -= value * thisBlepSample(resetTime)
                    next -= value * nextBlepSample(resetTime)
                }
            } else if outputPhase {
                masterPhase += masterF
                if masterPhase >= 1 { masterPhase -= 1 }
            }

            slavePhase += slaveF
            while transitionDuringReset || !reset {
                if !high {
                    if slavePhase < pwNow { break }
                    let t = (slavePhase - pwNow) / (previousPw - pwNow + slaveF)
                    var triangleStep = (slopeUp + slopeDown) * slaveF
                    triangleStep *= triangleAmount

                    thisSample += squareAmount * thisBlepSample(t)
                    next += squareAmount * nextBlepSample(t)
                    thisSample -= triangleStep * thisIntegratedBlepSample(t)
                    next -= triangleStep * nextIntegratedBlepSample(t)
                    high = true
                }

                if high {
                    if slavePhase < 1 { break }
                    slavePhase -= 1
                    let t = slavePhase / slaveF
                    var triangleStep = (slopeUp + slopeDown) * slaveF
                    triangleStep *= triangleAmount

                    thisSample -= (1 - triangleAmount) * thisBlepSample(t)
                    next -= (1 - triangleAmount) * nextBlepSample(t)
                    thisSample += triangleStep * thisIntegratedBlepSample(t)
                    next += triangleStep * nextIntegratedBlepSample(t)
                    high = false
                }
            }

            if enableSync && reset {
                slavePhase = resetTime * slaveF
                high = false
            }

            next += naiveSample(slavePhase, pwNow, slopeUp, slopeDown, triangleAmount, squareAmount)
            previousPw = pwNow

            if outputPhase {
                var phasor = masterPhase
                if enableSync {
                    // Без разрыва при переходе фазы через 1.
                    let w = 4 * (1 - masterPhase) * masterPhase
                    thisSample *= w * (2 - w)
                    // Асимметрия и у основной фазы.
                    let p2 = phasor * phasor
                    phasor += (p2 * p2 - phasor) * abs(pwNow - 0.5) * 2
                }
                out[i] = phasor + phaseModulationInterp.next() * thisSample
            } else {
                out[i] = 2 * thisSample - 1
            }
        }
        nextSample = next

        // Деструкторы ParameterInterpolator оригинала.
        masterFrequency = masterFm.value
        slaveFrequency = fm.value
        pw = pwm.value
        waveshape = waveshapeModulation.value
        phaseModulation = phaseModulationInterp.value
    }

    @inline(__always)
    private func naiveSample(_ phase: Float, _ pw: Float, _ slopeUp: Float, _ slopeDown: Float,
                             _ triangleAmount: Float, _ squareAmount: Float) -> Float {
        var saw = phase
        let square: Float = phase < pw ? 0 : 1
        let triangle = phase < pw ? phase * slopeUp : 1 - (phase - pw) * slopeDown
        saw += (square - saw) * squareAmount
        saw += (triangle - saw) * triangleAmount
        return saw
    }
}
