// Заглушка вместо plaits/dsp/speech/lpc_speech_synth_words.cc: режим Words движка SPEECH отключён
// (данные LPC-слов из ПЗУ Texas Instruments, лицензионный статус не подтверждён; вернуться — этап 12).
// Банки слов пустые, поэтому Init движка и speech_engine.cc не меняются; JAMbo подаёт harmonics
// не выше 1/3 (group 2), и ветка слов (group > 2) недостижима.
//
// Plaits: Copyright Emilie Gillet, лицензия MIT (см. wasm/plaits/LICENSE-MI.txt).

#include "plaits/dsp/speech/lpc_speech_synth_words.h"

namespace plaits {

/* extern */
const LPCSpeechSynthWordBankData word_banks_[LPC_SPEECH_SYNTH_NUM_WORD_BANKS] = {
  { nullptr, 0 },
  { nullptr, 0 },
  { nullptr, 0 },
  { nullptr, 0 },
  { nullptr, 0 },
};

}  // namespace plaits
