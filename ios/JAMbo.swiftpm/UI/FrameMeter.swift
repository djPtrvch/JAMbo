import QuartzCore

/// Кадры интерфейса (S14a): CADisplayLink — промежуток между кадрами и пропущенные кадры; время drain (60 раз
/// в секунду, сообщения колбэка → состояние). За последнюю секунду и с последнего RESET; работает всё время
/// (DIAGNOSTICS закрывает экран — замер идёт и при закрытом окне). Только главный поток; DIAGNOSTICS читает по таймеру.
final class FrameMeter: NSObject {
    struct FrameStats {
        var fps: Double = 0
        var avgMs: Double = 0
        var worstMs: Double = 0
        var dropped: Int = 0
        var drainAvgMs: Double = 0
        var drainPeakMs: Double = 0
    }

    /// Последняя секунда.
    private(set) var last = FrameStats()
    /// С последнего RESET: кадров, пропущено, худший промежуток и худший drain.
    private(set) var totalFrames: Int = 0
    private(set) var totalDropped: Int = 0
    private(set) var totalWorstMs: Double = 0
    private(set) var totalDrainMs: Double = 0

    private var link: CADisplayLink?
    private var prev: CFTimeInterval = 0
    private var winStart: CFTimeInterval = 0
    private var frames: Int = 0
    private var sumDt: Double = 0
    private var maxDt: Double = 0
    private var dropped: Int = 0
    private var drains: Int = 0
    private var drainSum: Double = 0
    private var drainMax: Double = 0

    func start() {
        if link != nil { return }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func reset() {
        totalFrames = 0
        totalDropped = 0
        totalWorstMs = 0
        totalDrainMs = 0
    }

    /// drain занял seconds (главный поток).
    func drained(_ seconds: Double) {
        let ms: Double = seconds * 1000
        drains += 1
        drainSum += ms
        if ms > drainMax { drainMax = ms }
        if ms > totalDrainMs { totalDrainMs = ms }
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now: CFTimeInterval = l.timestamp
        // Длительность кадра при текущей частоте (60 или 120 Гц на ProMotion).
        let expected: Double = l.targetTimestamp - l.timestamp
        // Перерыв дольше 0,5 с (фон, пауза) — не пропуск кадров: окно заново.
        if prev > 0 && now - prev > 0.5 {
            prev = now
            winStart = now
            frames = 0
            sumDt = 0
            maxDt = 0
            dropped = 0
            return
        }
        if prev > 0 && expected > 0 {
            let dt: Double = now - prev
            frames += 1
            sumDt += dt
            if dt > maxDt { maxDt = dt }
            if dt > expected * 1.5 {
                let lost: Int = Int((dt / expected).rounded()) - 1
                dropped += lost
                totalDropped += lost
            }
            totalFrames += 1
            let ms: Double = dt * 1000
            if ms > totalWorstMs { totalWorstMs = ms }
        } else {
            winStart = now
        }
        prev = now
        if now - winStart >= 1 { publish(now) }
    }

    private func publish(_ now: CFTimeInterval) {
        var w = FrameStats()
        let span: Double = now - winStart
        if frames > 0 && span > 0 {
            w.fps = Double(frames) / span
            w.avgMs = sumDt / Double(frames) * 1000
        }
        w.worstMs = maxDt * 1000
        w.dropped = dropped
        if drains > 0 { w.drainAvgMs = drainSum / Double(drains) }
        w.drainPeakMs = drainMax
        last = w
        winStart = now
        frames = 0
        sumDt = 0
        maxDt = 0
        dropped = 0
        drains = 0
        drainSum = 0
        drainMax = 0
    }
}
