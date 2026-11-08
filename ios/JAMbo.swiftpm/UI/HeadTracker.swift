import ARKit
import QuartzCore

/// HEAD (8.11): поворот головы фронтальной камерой (ARKit Face Tracking, 60 Гц) → RoomStage.headYaw (градусы,
/// вправо +). Угол — линия ушей в горизонтальной плоскости относительно горизонтального края iPad (по гравитации: не
/// зависит от наклона iPad и головы; проба — ios/spikes/HeadTrack.swiftpm, SWIFT_MILESTONE_S14.md). Предсказание —
/// на 35 мс по сглаженной скорости поворота. Лицо пропало — 0,5 с угол держится, затем плавно к нулю. Ноль — при
/// запуске и по center() (лицом к iPad).
final class HeadTracker: NSObject, ARSessionDelegate {
    static let predict: Double = 0.035
    static let maxLead: Double = 0.35
    let stage: RoomStage
    let session = ARSession()
    private let queue = DispatchQueue(label: "jambo.head")
    private let lock = NSLock()
    private var wantCenter = true
    private var offset: Double = 0
    private var lastY: Double = 0
    private var lastT: Double = 0
    private var vel: Double = 0
    private var lostFrames = 0
    private var face = false
    /// Лицо появилось или пропало (основной поток).
    var onFace: ((Bool) -> Void)? = nil

    /// Камера TrueDepth есть и доступ к камере объявлен (Capabilities → Camera в Playgrounds); без объявления
    /// обращение к камере закрывает приложение.
    static var available: Bool {
        return ARFaceTrackingConfiguration.isSupported
            && Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil
    }

    init(stage: RoomStage) {
        self.stage = stage
        super.init()
    }

    func start() {
        guard HeadTracker.available else { return }
        let c = ARFaceTrackingConfiguration()
        c.isLightEstimationEnabled = false
        c.maximumNumberOfTrackedFaces = 1
        c.worldAlignment = .gravity
        session.delegate = self
        session.delegateQueue = queue
        lock.lock()
        wantCenter = true
        lock.unlock()
        stage.headYaw.store(0)
        stage.headOn.store(1)
        session.run(c, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        stage.headOn.store(0)
        session.pause()
    }

    /// CENTER: текущий поворот — ноль.
    func center() {
        lock.lock()
        wantCenter = true
        lock.unlock()
    }

    private func setFace(_ v: Bool) {
        if v == face { return }
        face = v
        DispatchQueue.main.async { [weak self] in self?.onFace?(v) }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        var anchor: ARFaceAnchor? = nil
        for a in frame.anchors {
            if let f = a as? ARFaceAnchor {
                anchor = f
                break
            }
        }
        guard let f = anchor, f.isTracked else {
            lostFrames += 1
            vel = 0
            lastT = 0
            if lostFrames > 30 {
                let y: Float = stage.headYaw.load() * 0.93
                stage.headYaw.store(abs(y) < 0.01 ? 0 : y)
            }
            setFace(false)
            return
        }
        lostFrames = 0
        setFace(true)
        let fx: simd_float4 = f.transform.columns.0
        let cx: simd_float4 = frame.camera.transform.columns.0
        let headAng: Double = atan2(Double(-fx.z), Double(fx.x))
        let padAng: Double = atan2(Double(-cx.z), Double(cx.x))
        let raw: Double = headAng - padAng
        lock.lock()
        if wantCenter {
            offset = raw
            wantCenter = false
            vel = 0
            lastT = 0
        }
        let off: Double = offset
        lock.unlock()
        var d: Double = raw - off
        if d > Double.pi { d -= 2 * Double.pi }
        if d < -Double.pi { d += 2 * Double.pi }
        let t: Double = frame.timestamp
        if lastT > 0 && t > lastT {
            let v: Double = (d - lastY) / (t - lastT)
            vel += (v - vel) * 0.5
        }
        lastY = d
        lastT = t
        var lead: Double = vel * HeadTracker.predict
        if lead > HeadTracker.maxLead { lead = HeadTracker.maxLead }
        if lead < -HeadTracker.maxLead { lead = -HeadTracker.maxLead }
        stage.headYaw.store(Float((d + lead) * 180 / Double.pi))
    }

    func sessionWasInterrupted(_ session: ARSession) {
        setFace(false)
    }
}
