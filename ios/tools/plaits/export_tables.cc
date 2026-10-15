// Экспорт таблиц Plaits и stmlib (resources.cc, units.cc, фонемы LPC) в двоичные файлы для Swift-версии:
// Resources/plaits/<имя>.<f32|i16|i8> — те же типы, что в оригинале, little-endian.
// Сборка и запуск — ios/tools/plaits/export_tables.sh.
// Plaits и stmlib: Copyright Emilie Gillet, MIT.
#include <cstdio>
#include <cstdint>
#include <string>
// Таблица фонем — закрытый член класса; для экспорта открываем.
#define private public
#include "plaits/resources.h"
#include "stmlib/dsp/units.h"
#include "plaits/dsp/speech/lpc_speech_synth_controller.h"

using namespace plaits;

static std::string dir;

template <typename T>
static void dump(const char* name, const char* ext, const T* data, size_t n) {
  std::string path = dir + "/" + name + "." + ext;
  FILE* f = fopen(path.c_str(), "wb");
  fwrite(data, sizeof(T), n, f);
  fclose(f);
}


int main(int argc, char** argv) {
  dir = argc > 1 ? argv[1] : ".";
  dump("lut_sine", "f32", lut_sine, LUT_SINE_SIZE);
  dump("lut_fm_frequency_quantizer", "f32", lut_fm_frequency_quantizer, LUT_FM_FREQUENCY_QUANTIZER_SIZE);
  dump("lut_fold", "f32", lut_fold, LUT_FOLD_SIZE);
  dump("lut_fold_2", "f32", lut_fold_2, LUT_FOLD_2_SIZE);
  dump("lut_stiffness", "f32", lut_stiffness, LUT_STIFFNESS_SIZE);
  dump("lut_svf_shift", "f32", lut_svf_shift, LUT_SVF_SHIFT_SIZE);
  dump("lut_4x_downsampler_fir", "f32", lut_4x_downsampler_fir, LUT_4X_DOWNSAMPLER_FIR_SIZE);
  dump("lut_ws_inverse_tan", "i16", lut_ws_inverse_tan, LUT_WS_INVERSE_TAN_SIZE);
  dump("lut_ws_inverse_sin", "i16", lut_ws_inverse_sin, LUT_WS_INVERSE_SIN_SIZE);
  dump("lut_ws_linear", "i16", lut_ws_linear, LUT_WS_LINEAR_SIZE);
  dump("lut_ws_bump", "i16", lut_ws_bump, LUT_WS_BUMP_SIZE);
  dump("lut_ws_double_bump", "i16", lut_ws_double_bump, LUT_WS_DOUBLE_BUMP_SIZE);
  dump("lut_lpc_excitation_pulse", "i8", lut_lpc_excitation_pulse, LUT_LPC_EXCITATION_PULSE_SIZE);
  dump("wav_integrated_waves", "i16", wav_integrated_waves, WAV_INTEGRATED_WAVES_SIZE);
  dump("lut_pitch_ratio_high", "f32", stmlib::lut_pitch_ratio_high, 257);
  dump("lut_pitch_ratio_low", "f32", stmlib::lut_pitch_ratio_low, 257);
  // Фонемы LPC: на кадр — energy, period, k0 k1 (i16), k2…k9 (i8) → 12 значений i16 подряд.
  const LPCSpeechSynth::Frame* fr = LPCSpeechSynthController::phonemes_;
  int16_t buf[kLPCSpeechSynthNumPhonemes * 12];
  for (int i = 0; i < kLPCSpeechSynthNumPhonemes; ++i) {
    const LPCSpeechSynth::Frame& p = fr[i];
    int16_t* o = buf + i * 12;
    o[0] = p.energy; o[1] = p.period; o[2] = p.k0; o[3] = p.k1;
    o[4] = p.k2; o[5] = p.k3; o[6] = p.k4; o[7] = p.k5; o[8] = p.k6; o[9] = p.k7; o[10] = p.k8; o[11] = p.k9;
  }
  dump("lpc_phonemes", "i16", buf, kLPCSpeechSynthNumPhonemes * 12);
  printf("ok\n");
  return 0;
}
