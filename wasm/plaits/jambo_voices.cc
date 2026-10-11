// Голоса синтезатора JAMbo на движках Mutable Instruments Plaits: 16 классических (0–15) и два
// из Plaits 1.2 (16 — string machine, 17 — chiptune). Номера классических не меняются (так они
// хранятся в проектах).
// Один экземпляр модуля WebAssembly = одна дорожка: kSlots голосов, у каждого свои движки
// в общей памяти (как в Plaits: движки делят один буфер, при смене движка — Reset).
// Огибающую громкости, фильтр и панораму делает Web Audio; здесь — только звук движка
// (LPG Plaits не используется). Частота дискретизации Plaits — 48 кГц.
//
// Plaits и stmlib: Copyright Emilie Gillet, лицензия MIT (см. wasm/plaits/LICENSE-MI.txt).

#include "plaits/dsp/engine/additive_engine.h"
#include "plaits/dsp/engine/bass_drum_engine.h"
#include "plaits/dsp/engine/chord_engine.h"
#include "plaits/dsp/engine/fm_engine.h"
#include "plaits/dsp/engine/grain_engine.h"
#include "plaits/dsp/engine/hi_hat_engine.h"
#include "plaits/dsp/engine/modal_engine.h"
#include "plaits/dsp/engine/noise_engine.h"
#include "plaits/dsp/engine/particle_engine.h"
#include "plaits/dsp/engine/snare_drum_engine.h"
#include "plaits/dsp/engine/speech_engine.h"
#include "plaits/dsp/engine/string_engine.h"
#include "plaits/dsp/engine/swarm_engine.h"
#include "plaits/dsp/engine/virtual_analog_engine.h"
#include "plaits/dsp/engine/waveshaping_engine.h"
#include "plaits/dsp/engine/wavetable_engine.h"
#include "plaits/dsp/engine2/chiptune_engine.h"
#include "plaits/dsp/engine2/string_machine_engine.h"
#include "stmlib/dsp/limiter.h"

using namespace plaits;

namespace {

const int kSlots = 6;
const int kEngines = 18;
const int kBufferSize = 16384;

struct Slot {
  VirtualAnalogEngine virtual_analog;
  WaveshapingEngine waveshaping;
  FMEngine fm;
  GrainEngine grain;
  AdditiveEngine additive;
  WavetableEngine wavetable;
  ChordEngine chord;
  SpeechEngine speech;
  SwarmEngine swarm;
  NoiseEngine noise;
  ParticleEngine particle;
  StringEngine string;
  ModalEngine modal;
  BassDrumEngine bass_drum;
  SnareDrumEngine snare_drum;
  HiHatEngine hi_hat;
  StringMachineEngine string_machine;
  ChiptuneEngine chiptune;

  Engine* engines[kEngines];
  char buffer[kBufferSize];
  stmlib::Limiter limiter;
  stmlib::Limiter aux_limiter;

  int engine;
  bool rising;
  bool gate;
  float note;
  float harmonics;
  float timbre;
  float morph;
  float accent;
  // Микс выходов OUT и AUX (0 — только OUT), как переключение выходов модуля Plaits.
  float aux_mix;
  float out[kMaxBlockSize];
  float aux[kMaxBlockSize];
};

Slot slots[kSlots];
float output[kMaxBlockSize];

// Как в plaits/dsp/voice.cc: огибающая уже есть у движка, усиление выхода (< 0 — лимитер).
void Register(Engine* e, bool already_enveloped, float out_gain, float aux_gain) {
  e->post_processing_settings.already_enveloped = already_enveloped;
  e->post_processing_settings.out_gain = out_gain;
  e->post_processing_settings.aux_gain = aux_gain;
}

// Усиление выхода как в plaits/dsp/voice.cc: < 0 — лимитер с этим предусилением.
void Post(stmlib::Limiter* limiter, float gain, float* buffer, int size) {
  if (gain < 0.0f) {
    limiter->Process(-gain, buffer, size);
    gain = 1.0f;
  }
  for (int i = 0; i < size; ++i) buffer[i] *= gain;
}

// Смена движка: данные и сброс, как в plaits/dsp/voice.cc.
void Load(Slot& s, int engine) {
  s.engines[engine]->LoadUserData(nullptr);
  s.engines[engine]->Reset();
}

}  // namespace

extern "C" {

__attribute__((export_name("init")))
void init() {
  for (int i = 0; i < kSlots; ++i) {
    Slot& s = slots[i];
    Engine* list[kEngines] = {
      &s.virtual_analog, &s.waveshaping, &s.fm, &s.grain,
      &s.additive, &s.wavetable, &s.chord, &s.speech,
      &s.swarm, &s.noise, &s.particle, &s.string,
      &s.modal, &s.bass_drum, &s.snare_drum, &s.hi_hat,
      &s.string_machine, &s.chiptune,
    };
    // Усиления и «огибающая уже есть» — как в plaits/dsp/voice.cc.
    const float gains[kEngines] = {
      0.8f, 0.7f, 0.6f, 0.7f, 0.8f, 0.6f, 0.8f, -0.7f,
      -3.0f, -1.0f, -2.0f, -1.0f, -1.0f, 0.8f, 0.8f, 0.8f,
      0.8f, 0.5f,
    };
    const float aux_gains[kEngines] = {
      0.8f, 0.6f, 0.6f, 0.6f, 0.8f, 0.6f, 0.8f, 0.8f,
      1.0f, -1.0f, 1.0f, 0.8f, 0.8f, 0.8f, 0.8f, 0.8f,
      0.8f, 0.5f,
    };
    stmlib::BufferAllocator allocator(s.buffer, kBufferSize);
    for (int k = 0; k < kEngines; ++k) {
      s.engines[k] = list[k];
      Register(list[k], k >= 11 && k <= 15, gains[k], aux_gains[k]);
      // Все движки голоса делят одну память.
      allocator.Free();
      list[k]->Init(&allocator);
    }
    s.limiter.Init();
    s.aux_limiter.Init();
    s.aux_mix = 0.0f;
    s.engine = 0;
    Load(s, 0);
    s.rising = false;
    s.gate = false;
    s.note = 48.0f;
    s.harmonics = s.timbre = s.morph = 0.5f;
    s.accent = 0.8f;
  }
}

/**
 * Параметры голоса: движок 0..17, нота (MIDI, 60 = C4), harmonics/timbre/morph 0..1,
 * aux_mix — доля выхода AUX (0..1).
 */
__attribute__((export_name("set")))
void set(int slot, int engine, float note, float harmonics, float timbre, float morph, float accent, float aux_mix) {
  Slot& s = slots[slot];
  if (engine < 0 || engine >= kEngines) engine = 0;
  if (engine != s.engine) {
    s.engine = engine;
    Load(s, engine);
    s.limiter.Init();
    s.aux_limiter.Init();
  }
  s.aux_mix = aux_mix < 0.0f ? 0.0f : (aux_mix > 1.0f ? 1.0f : aux_mix);
  s.note = note;
  s.harmonics = harmonics;
  s.timbre = timbre;
  s.morph = morph;
  s.accent = accent;
}

/** Триггер ноты (передний фронт на следующем блоке) и гейт. */
__attribute__((export_name("trigger")))
void trigger(int slot) {
  slots[slot].rising = true;
  slots[slot].gate = true;
}

__attribute__((export_name("release")))
void release(int slot) {
  slots[slot].gate = false;
}

/** Отрисовать size (≤ 24) сэмплов голоса; указатель на результат. */
__attribute__((export_name("render")))
float* render(int slot, int size) {
  Slot& s = slots[slot];
  Engine* e = s.engines[s.engine];
  EngineParameters p;
  p.trigger = (s.rising ? TRIGGER_RISING_EDGE : TRIGGER_LOW) | (s.gate ? TRIGGER_HIGH : TRIGGER_LOW);
  s.rising = false;
  p.note = s.note;
  p.harmonics = s.harmonics;
  p.timbre = s.timbre;
  p.morph = s.morph;
  p.accent = s.accent;
  bool already_enveloped = e->post_processing_settings.already_enveloped;
  e->Render(p, s.out, s.aux, size, &already_enveloped);
  Post(&s.limiter, e->post_processing_settings.out_gain, s.out, size);
  Post(&s.aux_limiter, e->post_processing_settings.aux_gain, s.aux, size);
  const float a = s.aux_mix;
  for (int i = 0; i < size; ++i) {
    float v = s.out[i] * (1.0f - a) + s.aux[i] * a;
    output[i] = v > 1.0f ? 1.0f : (v < -1.0f ? -1.0f : v);
  }
  return output;
}

}  // extern "C"
