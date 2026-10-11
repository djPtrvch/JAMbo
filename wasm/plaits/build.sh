#!/usr/bin/env bash
# Сборка public/plaits.wasm из исходников Mutable Instruments Plaits (MIT).
# Нужен wasi-sdk (https://github.com/WebAssembly/wasi-sdk): WASI_SDK=/путь/к/wasi-sdk ./build.sh
# Готовый plaits.wasm лежит в репозитории, поэтому для обычной сборки сайта это не нужно.
set -euo pipefail
cd "$(dirname "$0")"

EURORACK_REV=08460a69a7e1f7a81c5a2abcc7189c9a6b7208d4
STMLIB_REV=e3bd7c9cc00e4364166f9905c0509b6ffd0535ec
SRC=.src
: "${WASI_SDK:?укажите путь к wasi-sdk в WASI_SDK}"

if [ ! -d "$SRC/eurorack" ]; then
  mkdir -p "$SRC"
  git clone -q https://github.com/pichenettes/eurorack.git "$SRC/eurorack"
  git -C "$SRC/eurorack" checkout -q "$EURORACK_REV"
  git clone -q https://github.com/pichenettes/stmlib.git "$SRC/stmlib"
  git -C "$SRC/stmlib" checkout -q "$STMLIB_REV"
fi

P=$SRC/eurorack/plaits
SOURCES=(
  jambo_voices.cc
  $P/resources.cc
  $P/dsp/chords/chord_bank.cc
  $P/dsp/speech/*.cc
  $P/dsp/physical_modelling/*.cc
  $P/dsp/engine/*.cc
  $P/dsp/engine2/*.cc
  $P/dsp/fm/*.cc
  $SRC/stmlib/dsp/units.cc
  $SRC/stmlib/utils/random.cc
)

"$WASI_SDK/bin/clang++" --target=wasm32-wasi --sysroot="$WASI_SDK/share/wasi-sysroot" \
  -O3 -ffast-math -fno-exceptions -fno-rtti -DTEST \
  -I"$SRC/eurorack" -I"$SRC" -mexec-model=reactor \
  -Wl,--strip-all -Wl,-z,stack-size=65536 \
  -o ../../public/plaits.wasm "${SOURCES[@]}"
ls -l ../../public/plaits.wasm
