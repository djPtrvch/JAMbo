# S12 — движки синта

Подробное поведение — docs/ai/synth-engines.md (в ветке swift описывает Swift-версию); здесь — что сделано, как устроено и что проверено.

## Этап 0 — Plaits убран
- Движков Mutable Instruments нет: звуки mi:0…mi:15 в проектах и пресетах загружаются пустыми (SynthKey.isRemoved).

## Этап 1 — сетка ручек
- Velocity — на 4.4 (прежний Level), Level убран: громкость дорожки — в MIX и регуляторе справа.
- Swing — ползунок с процентами в меню клавиатуры (Params.swing, 50–75 %); версия формата проекта 3 переносит прежний swing.

## Этап 2 — ручка 1.4 и сила нажатия
- Свои движки: KICK CLICK, ANALOG WAVE A / WAVE B / DETUNE / MIX, FM FEEDBACK, WTABLE UNISON (1/3/5) и DETUNE. VoiceParam — 16 параметров (p4), маска p-lock — UInt32.
- Перевод старых проектов — версия формата 4 (SynthMigration: ручки, назначения MOD и p-lock переезжают на новые места); пресеты — fmt 3. Пропавший SUB у ANALOG — сообщение при загрузке (Project.notice).
- Pitch сэмпла — SETTINGS → SAMPLER → PITCH (SEMITONES / SMOOTH). PLAY сэмплера убран (решение пользователя): 1.4 у сэмпла пустая.
- KEY VELOCITY — по толчку iPad (акселерометр, TapSensor и TapVelocity): сила нажатия клавиш и аккордов прогрессии; звук клавиши ждёт толчка до 15 мс.

## Этап 3 — ударные
- SNARE, HAT, CLAP, PERC (номера 20–23; JamboDrums.swift, голос JamboDrumVoice в JamboBank): затухают сами, монофоничны, Decay — своя шкала у каждого.
- Меню звука в две колонки: DRUMS (KICK, SNARE, HAT, CLAP, PERC) и SYNTH (ANALOG, SUB, FM, WTABLE). Иконки — рисованные, живые от ручек.

## Этап 4 — SUB
- SUB (24) — моно-бас: OSC1 и OSC2 октавой ниже, WAVE, SUB, FAT, GRIT; PolyBLEP, ×2 передискретизация, выход 0,58.
- Щелчок (проверено на iPad и на стенде SUB Bench — страница с AudioWorklet, повторяющим DSP): старт после тишины с нуля волны; на звучащей ноте фазы и буфер децимации продолжаются (Key Reset убран, решение пользователя); коэффициенты фильтра голоса синта меняются плавно внутри куска (без ступенек при ENV и LFO на фильтре); монофоническая нота секвенсора ждёт своего кадра (SynthVoices, pKeep) — прежняя звучит до него, хвост не обрывается (касалось всех монофонических движков).

## Прочее
- Иконки: клик KICK — полоса в начале, на 100 % до верха поля; у SNARE — две волны корпуса. Превью LFO и ENV движется по таймлайну.
- Reverb по умолчанию: SIZE 30 %, DECAY 1,5 с (отличие от веба — в ios/CLAUDE.md).
- Package.swift: capabilities — перед appCategory (иначе Playgrounds не загружает пакет).

## Проверено
- CoreTests 264 (облако): SynthKnobsTests, DrumEngineTests, SubEngineTests (в том числе testNoGapBeforeSequencedNote — сцена с iPad), TapVelocityTests — NaN, пик ниже 0 dBFS, алиасинг (ANALOG −60 dBc, HAT −50 dB), стыки без щелчка, нагрузка 8 голосов.
- На iPad — все этапы проверены.

## Открыто
- PLAY сэмплера на 1.4 — вернуться с новой реализацией.
