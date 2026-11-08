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
    private var rawYaw: Double = 0
    private var offset: Double = 0
    private var sign: Double = 1
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
        offset = rawYaw
        m.minYaw = 0
        m.maxYaw = 0
        m.lostCount = 0
        lock.unlock()
    }

    func setSign(_ s: Double) {
        lock.lock()
        sign = s
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
            m.status = "Face lost — holding last angle"
            return
        }
        wasTracked = true
        m.status = "Tracking"
        var yaw: Double = 0
        var pitch: Double = 0
        if gravity {
            // Мир ARKit: y — вверх по гравитации. Поворот головы — угол оси ушей (x лица) в горизонтальной плоскости
            // минус такой же угол оси x камеры (в альбомной ориентации она горизонтальна при любом наклоне iPad).
            // Не зависит ни от наклона iPad, ни от того, куда наклонена голова (вниз на экран).
            let fx: simd_float4 = f.transform.columns.0
            let cx: simd_float4 = frame.camera.transform.columns.0
            let fz: simd_float4 = f.transform.columns.2
            let headAng: Double = atan2(Double(-fx.z), Double(fx.x))
            let padAng: Double = atan2(Double(-cx.z), Double(cx.x))
            yaw = -(headAng - padAng)
            pitch = asin(Double(max(-1, min(1, fz.y))))
        } else {
            // Прежний расчёт: голова в осях камеры; ось z лица смотрит из лица вперёд (к камере).
            let rel: simd_float4x4 = simd_mul(simd_inverse(frame.camera.transform), f.transform)
            let z: simd_float4 = rel.columns.2
            let h: Double = swapAxes ? Double(z.y) : Double(z.x)
            let v: Double = swapAxes ? Double(z.x) : Double(z.y)
            yaw = atan2(h, Double(z.z))
            pitch = atan2(-v, Double(z.z))
        }
        rawYaw = yaw
        var d: Double = yaw - offset
        if d > Double.pi { d -= 2 * Double.pi }
        if d < -Double.pi { d += 2 * Double.pi }
        let y: Double = sign * d
        m.yawDeg = y * 180 / Double.pi
        m.pitchDeg = pitch * 180 / Double.pi
        if m.yawDeg < m.minYaw { m.minYaw = m.yawDeg }
        if m.yawDeg > m.maxYaw { m.maxYaw = m.yawDeg }
        shared.cell[0] = Float(y)
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
