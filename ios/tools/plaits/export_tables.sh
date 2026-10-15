#!/usr/bin/env bash
# Таблицы Plaits → ios/JAMbo.swiftpm/Resources/plaits (исходники — wasm/plaits/.src, как для plaits.wasm).
set -euo pipefail
cd "$(dirname "$0")"
SRC=../../../wasm/plaits/.src
OUT=../../JAMbo.swiftpm/Resources/plaits
mkdir -p "$OUT" build
g++ -O1 -DTEST -I"$SRC/eurorack" -I"$SRC" -o build/export_tables export_tables.cc \
  "$SRC/eurorack/plaits/resources.cc" "$SRC/stmlib/dsp/units.cc" \
  "$SRC/eurorack/plaits/dsp/speech/lpc_speech_synth_phonemes.cc"
./build/export_tables "$OUT"
ls -l "$OUT"
