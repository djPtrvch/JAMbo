// Выгрузка таблиц Plaits и stmlib для Swift-версии: Resources/plaits/<имя>.<f32|i16|i8>, little-endian,
// те же типы и длины, что в исходниках (plaits/resources.cc, stmlib/dsp/units.cc, фонемы LPC).
// Plaits и stmlib: Copyright Emilie Gillet, MIT. Сборка и запуск — export_tables.sh.
#include <cstdint>
#include <cstdio>
#include <string>
// Таблицы фонем — закрытые члены классов; для выгрузки открываем.
#define private public
#include "plaits/dsp/speech/lpc_speech_synth_controller.h"
#include "plaits/dsp/speech/naive_speech_synth.h"
#include "plaits/dsp/speech/sam_speech_synth.h"
#include "plaits/resources.h"
#include "stmlib/dsp/units.h"

using namespace plaits;

static std::string out_dir;

template <typename T>
static void Dump(const char* name, const char* ext, const T* data, size_t count) {
  std::string path = out_dir + "/" + name + "." + ext;
  FILE* f = fopen(path.c_str(), "wb");
  if (!f) { perror(path.c_str()); return; }
  fwrite(data, sizeof(T), count, f);
  fclose(f);
}

int main(int argc, char** argv) {
  out_dir = argc > 1 ? argv[1] : ".";
  Dump("lut_sine", "f32", lut_sine, LUT_SINE_SIZE);
  Dump("lut_fm_frequency_quantizer", "f32", lut_fm_frequency_quantizer, LUT_FM_FREQUENCY_QUANTIZER_SIZE);
  Dump("lut_fold", "f32", lut_fold, LUT_FOLD_SIZE);
  Dump("lut_fold_2", "f32", lut_fold_2, LUT_FOLD_2_SIZE);
  Dump("lut_stiffness", "f32", lut_stiffness, LUT_STIFFNESS_SIZE);
  Dump("lut_svf_shift", "f32", lut_svf_shift, LUT_SVF_SHIFT_SIZE);
  Dump("lut_4x_downsampler_fir", "f32", lut_4x_downsampler_fir, LUT_4X_DOWNSAMPLER_FIR_SIZE);
  Dump("lut_ws_inverse_tan", "i16", lut_ws_inverse_tan, LUT_WS_INVERSE_TAN_SIZE);
  Dump("lut_ws_inverse_sin", "i16", lut_ws_inverse_sin, LUT_WS_INVERSE_SIN_SIZE);
  Dump("lut_ws_linear", "i16", lut_ws_linear, LUT_WS_LINEAR_SIZE);
  Dump("lut_ws_bump", "i16", lut_ws_bump, LUT_WS_BUMP_SIZE);
  Dump("lut_ws_double_bump", "i16", lut_ws_double_bump, LUT_WS_DOUBLE_BUMP_SIZE);
  Dump("lut_lpc_excitation_pulse", "i8", lut_lpc_excitation_pulse, LUT_LPC_EXCITATION_PULSE_SIZE);
  Dump("wav_integrated_waves", "i16", wav_integrated_waves, WAV_INTEGRATED_WAVES_SIZE);
  Dump("lut_pitch_ratio_high", "f32", stmlib::lut_pitch_ratio_high, 257);
  Dump("lut_pitch_ratio_low", "f32", stmlib::lut_pitch_ratio_low, 257);
  // Фонемы LPC: кадр Frame (energy, period — u8; k0, k1 — i16; k2…k9 — i8) → 12 значений i16 подряд.
  const int n = kLPCSpeechSynthNumPhonemes;
  int16_t frames[n * 12];
  for (int i = 0; i < n; ++i) {
    const LPCSpeechSynth::Frame& p = LPCSpeechSynthController::phonemes_[i];
    const int16_t v[12] = { p.energy, p.period, p.k0, p.k1, p.k2, p.k3, p.k4, p.k5, p.k6, p.k7, p.k8, p.k9 };
    for (int k = 0; k < 12; ++k) frames[i * 12 + k] = v[k];
  }
  Dump("lpc_phonemes", "i16", frames, n * 12);
  // Formant (NaiveSpeechSynth): [фонема 5][регистр 5][форманта 5] × (frequency, amplitude), u8.
  Dump("naive_phonemes", "u8", &NaiveSpeechSynth::phonemes_[0][0].formant[0].frequency,
       kNaiveSpeechNumPhonemes * kNaiveSpeechNumRegisters * kNaiveSpeechNumFormants * 2);
  // SAM: [фонема 17 + охранная][форманта 3] × (frequency, amplitude), u8; амплитуды — 16 × f32.
  Dump("sam_phonemes", "u8", &SAMSpeechSynth::phonemes_[0].formant[0].frequency,
       (kSAMNumPhonemes + 1) * kSAMNumFormants * 2);
  Dump("sam_formant_amplitude", "f32", SAMSpeechSynth::formant_amplitude_lut, 16);
  printf("tables: %s\n", out_dir.c_str());
  return 0;
}
