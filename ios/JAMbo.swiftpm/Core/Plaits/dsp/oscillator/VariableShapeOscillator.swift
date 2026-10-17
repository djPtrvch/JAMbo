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

        // Интерполяторы — значение и приращение в локальных переменных, polyBLEP — формулами: в отладочной сборке
        // (Playgrounds) вызовы функций из других файлов на каждом отсчёте не встраиваются.
        var masterFV = masterFm.value, slaveFV = fm.value, pwV = pwm.value, shapeV = waveshapeModulation.value
        var pmV = phaseModulationInterp.value
        let masterFI = masterFm.increment, slaveFI = fm.increment, pwI = pwm.increment
        let shapeI = waveshapeModulation.increment, pmI = phaseModulationInterp.increment
        @_transparent func thisBlep(_ t: Float) -> Float { 0.5 * t * t }
        @_transparent func nextBlep(_ t0: Float) -> Float {
            let t = 1 - t0
            return -0.5 * t * t
        }
        @_transparent func nextIntBlep(_ t: Float) -> Float {
            let t1 = 0.5 * t
            let t2 = t1 * t1
            let t4 = t2 * t2
            return 0.1875 - t1 + 1.5 * t2 - t4
        }
        @_transparent func thisIntBlep(_ t: Float) -> Float { nextIntBlep(1 - t) }
        var next = nextSample
        var i = 0
        while i < size {
            defer { i += 1 }
            var reset = false
            var transitionDuringReset = false
            var resetTime: Float = 0

            var thisSample = next
            next = 0

            masterFV += masterFI
            slaveFV += slaveFI
            pwV += pwI
            shapeV += shapeI
            let masterF = masterFV
            let slaveF = slaveFV
            let pwNow = pwV
            let shape = shapeV

            // max(x, 0): 0 >= x ? 0 : x.
            let sq = shape - 0.5
            let squareAmount = (0 >= sq ? 0 : sq) * 2
            let tr = 1 - shape * 2
            let triangleAmount: Float = 0 >= tr ? 0 : tr

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
                    thisSample -= value * thisBlep(resetTime)
                    next -= value * nextBlep(resetTime)
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

                    thisSample += squareAmount * thisBlep(t)
                    next += squareAmount * nextBlep(t)
                    thisSample -= triangleStep * thisIntBlep(t)
                    next -= triangleStep * nextIntBlep(t)
                    high = true
                }

                if high {
                    if slavePhase < 1 { break }
                    slavePhase -= 1
                    let t = slavePhase / slaveF
                    var triangleStep = (slopeUp + slopeDown) * slaveF
                    triangleStep *= triangleAmount

                    thisSample -= (1 - triangleAmount) * thisBlep(t)
                    next -= (1 - triangleAmount) * nextBlep(t)
                    thisSample += triangleStep * thisIntBlep(t)
                    next += triangleStep * nextIntBlep(t)
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
                pmV += pmI
                out[i] = phasor + pmV * thisSample
            } else {
                out[i] = 2 * thisSample - 1
            }
        }
        nextSample = next

        // Деструкторы ParameterInterpolator оригинала.
        masterFrequency = masterFV
        slaveFrequency = slaveFV
        pw = pwV
        waveshape = shapeV
        phaseModulation = pmV
    }

    @_transparent
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
