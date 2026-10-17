// Ported from Mutable Instruments Plaits and stmlib (MIT), Copyright Emilie Gillet.
// plaits/dsp/dsp.h и plaits/dsp/engine/engine.h.

/// kCorrectedSampleRate — частота модуля (делитель тактовой, 4,6 цента ниже 48 кГц); нужна LPC в SPEECH.
/// a0 — по 48 кГц, без сдвига ноты (решение в ios/CLAUDE.md): A4 = 440 Гц, как в вебе со сдвигом
/// 12·log2(47872,34/48000) при a0 оригинала.
let kSampleRate: Float = 48000
let kCorrectedSampleRate: Float = 47872.34
let plaitsA0: Float = 0.00114583333
let kMaxBlockSize = 24
let kBlockSize = 12

/// oscillator.h.
let kMaxFrequency: Float = 0.25
let kMinFrequency: Float = 0.000001

/// TriggerState (биты).
let triggerLow = 0
let triggerRisingEdge = 1
let triggerUnpatched = 2
let triggerHigh = 4

struct EngineParameters {
    var trigger = triggerLow
    var note: Float = 48
    var timbre: Float = 0.5
    var morph: Float = 0.5
    var harmonics: Float = 0.5
    var accent: Float = 0.8
}

/// PostProcessingSettings (out_gain < 0 — лимитер с этим предусилением).
struct PostProcessingSettings {
    var outGain: Float = 1
    var auxGain: Float = 1
    var alreadyEnveloped = false
}

/// Engine: Init — в инициализаторе (буферы у каждого движка свои, вместо общего BufferAllocator),
/// Reset — при выборе движка, LoadUserData — без своих данных.
protocol PlaitsEngine: AnyObject {
    var postProcessing: PostProcessingSettings { get set }
    func reset()
    func loadUserData()
    func render(_ parameters: EngineParameters, _ out: UnsafeMutablePointer<Float>, _ aux: UnsafeMutablePointer<Float>,
                _ size: Int, _ alreadyEnveloped: inout Bool)
}

extension PlaitsEngine {
    func loadUserData() {}
}

/// Буфер Float, обнулённый (аналог allocator->Allocate<float>(n)); живёт вместе с движком.
func plaitsAllocate(_ count: Int) -> UnsafeMutablePointer<Float> {
    let p = UnsafeMutablePointer<Float>.allocate(capacity: count)
    p.initialize(repeating: 0, count: count)
    return p
}
