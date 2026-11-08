// Пробный прототип: отслеживание поворота головы фронтальной камерой (ARKit, TrueDepth).
// Проверяем: работает ли ARFaceTracking в сборке Swift Playgrounds, частоту кадров трекинга, задержку
// «кадр снят → угол готов», на каком повороте теряется лицо.

import ARKit
import QuartzCore

// Трекинг → звук без блокировок: по одному Float на значение (запись и чтение Float на arm64 атомарны).
// 0 — поворот головы, рад (вправо +); 1 — трекинг включён (1/0); 2 — направление источника, рад (вправо +).
final class HTShared {
    let cell: UnsafeMutablePointer<Float>

    init() {
        cell = UnsafeMutablePointer<Float>.allocate(capacity: 4)
        cell.initialize(repeating: 0, count: 4)
        cell[1] = 1
    }
}

struct HTMetrics {
    var status: String = "Starting…"
    var yawDeg: Double = 0
    var yawGravityDeg: Double = 0
    var yawCameraDeg: Double = 0
    var sentDeg: Double = 0
    var pitchDeg: Double = 0
    var rateHz: Double = 0
    var camLatencyMs: Double = 0
    var minYaw: Double = 0
    var maxYaw: Double = 0
    var lostCount: Int = 0
}

final class HTTracker: NSObject, ARSessionDelegate {
    let session = ARSession()
    let shared: HTShared
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "headtrack")
    private var m = HTMetrics()
    private var rawG: Double = 0
    private var rawC: Double = 0
    private var offG: Double = 0
    private var offC: Double = 0
    private var sign: Double = 1
    private var camSign: Double = 1
    private var predict = true
    private var lastY: Double = 0
    private var lastT: Double = 0
    private var vel: Double = 0
    private var lostFrames: Int = 0
    private var swapAxes = false
    private var gravity = true
    private var frames: Int = 0
    private var rateStart: Double = 0
    private var latSum: Double = 0
    private var latCount: Int = 0
    private var wasTracked = false

    init(shared: HTShared) {
        self.shared = shared
        super.init()
    }

    func start() {
        if !ARFaceTrackingConfiguration.isSupported {
            setStatus("Face tracking is not supported on this device")
            return
        }
        let c = ARFaceTrackingConfiguration()
        c.isLightEstimationEnabled = false
        c.maximumNumberOfTrackedFaces = 1
        c.worldAlignment = .gravity
        session.delegate = self
        session.delegateQueue = queue
        session.run(c, options: [.resetTracking, .removeExistingAnchors])
    }

    // Текущий поворот — новый ноль (смотреть на iPad и нажать CENTER).
    func center() {
        lock.lock()
        offG = rawG
        offC = rawC
        vel = 0
        m.minYaw = 0
        m.maxYaw = 0
        m.lostCount = 0
        lock.unlock()
    }

    // s — общий знак (INVERT), cam — поправка ориентации для расчёта в осях камеры.
    func setSign(_ s: Double, cam: Double) {
        lock.lock()
        sign = s
        camSign = cam
        lock.unlock()
    }

    func setPredict(_ b: Bool) {
        lock.lock()
        predict = b
        vel = 0
        lock.unlock()
    }

    func setSwap(_ b: Bool) {
        lock.lock()
        swapAxes = b
        lock.unlock()
    }

    // TILT FIX: поворот считается вокруг вертикали (по гравитации), а не вокруг оси наклонённого iPad.
    func setGravity(_ b: Bool) {
        lock.lock()
        gravity = b
        vel = 0
        lastT = 0
        lock.unlock()
    }

    func snapshot() -> HTMetrics {
        lock.lock()
        let r = m
        lock.unlock()
        return r
    }

    private func setStatus(_ s: String) {
        lock.lock()
        m.status = s
        lock.unlock()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now: Double = CACurrentMediaTime()
        var face: ARFaceAnchor? = nil
        for a in frame.anchors {
            if let f = a as? ARFaceAnchor {
                face = f
                break
            }
        }
        lock.lock()
        defer { lock.unlock() }
        // Частота и задержка — средние за секунду.
        frames += 1
        if rateStart == 0 { rateStart = now }
        let span: Double = now - rateStart
        if span >= 1 {
            m.rateHz = Double(frames) / span
            if latCount > 0 { m.camLatencyMs = latSum / Double(latCount) * 1000 }
            frames = 0
            rateStart = now
            latSum = 0
            latCount = 0
        }
        latSum += now - frame.timestamp
        latCount += 1
        guard let f = face, f.isTracked else {
            if wasTracked { m.lostCount += 1 }
            wasTracked = false
            lostFrames += 1
            // Лицо пропало: 0,5 с держим угол, затем плавно возвращаем звук к «прямо».
            if lostFrames > 30 {
                shared.cell[0] = shared.cell[0] * 0.93
                m.status = "Face lost — returning to center"
            } else {
                m.status = "Face lost — holding last angle"
            }
            m.sentDeg = Double(shared.cell[0]) * 180 / Double.pi
            vel = 0
            return
        }
        wasTracked = true
        lostFrames = 0
        m.status = "Tracking"
        // TILT FIX (по гравитации). Мир ARKit: y — вверх. Поворот головы — угол оси ушей (x лица) в горизонтальной
        // плоскости минус такой же угол оси x камеры (в альбомной ориентации она горизонтальна при любом наклоне iPad).
        let fx: simd_float4 = f.transform.columns.0
        let cx: simd_float4 = frame.camera.transform.columns.0
        let fz: simd_float4 = f.transform.columns.2
        let headAng: Double = atan2(Double(-fx.z), Double(fx.x))
        let padAng: Double = atan2(Double(-cx.z), Double(cx.x))
        rawG = headAng - padAng
        let pitch: Double = asin(Double(max(-1, min(1, fz.y))))
        // Прежний расчёт: голова в осях камеры; ось z лица смотрит из лица вперёд (к камере).
        let rel: simd_float4x4 = simd_mul(simd_inverse(frame.camera.transform), f.transform)
        let z: simd_float4 = rel.columns.2
        let h: Double = swapAxes ? Double(z.y) : Double(z.x)
        rawC = atan2(h, Double(z.z))
        let yG: Double = sign * wrap(rawG - offG)
        let yC: Double = sign * camSign * wrap(rawC - offC)
        let y: Double = gravity ? yG : yC
        m.yawGravityDeg = yG * 180 / Double.pi
        m.yawCameraDeg = yC * 180 / Double.pi
        m.yawDeg = y * 180 / Double.pi
        m.pitchDeg = pitch * 180 / Double.pi
        if m.yawDeg < m.minYaw { m.minYaw = m.yawDeg }
        if m.yawDeg > m.maxYaw { m.maxYaw = m.yawDeg }
        // Предсказание: угол на PREDICT_S вперёд по сглаженной скорости поворота (снимает часть задержки камеры).
        let t: Double = frame.timestamp
        var out: Double = y
        if lastT > 0 && t > lastT {
            let v: Double = (y - lastY) / (t - lastT)
            vel = vel + (v - vel) * 0.5
        }
        lastY = y
        lastT = t
        if predict {
            var lead: Double = vel * HTTracker.predictS
            if lead > 0.35 { lead = 0.35 }
            if lead < -0.35 { lead = -0.35 }
            out = y + lead
        }
        m.sentDeg = out * 180 / Double.pi
        shared.cell[0] = Float(out)
    }

    static let predictS: Double = 0.035

    private func wrap(_ a: Double) -> Double {
        var d: Double = a
        if d > Double.pi { d -= 2 * Double.pi }
        if d < -Double.pi { d += 2 * Double.pi }
        return d
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        setStatus("Error: " + error.localizedDescription)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        setStatus("Interrupted")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        setStatus("Resumed")
    }
}
