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

## Этап 5 — TEXTURE и GRANULAR
- Сделано: движки 25 и 26 по ТЗ (docs/ai/synth-engines.md, «TEXTURE и GRANULAR»); стерео-ветка голоса синта (огибающая — отдельным проходом SynthVoices.envelope, затем фильтр и Pan моно или стерео); выбор слота, legato и отпускание — в SynthVoicesNotes.swift (SynthVoices.swift был длиннее 600 строк); сэмпл GRANULAR — Track.grain, TrackSound.grain, SynthPreset.grain, Project.sampleKeys, SoundData.grainRef; SOURCE в меню звука; SAMPLER — под PERC.
- Проверено: см. «Проверка» в разделе движков; 419 тестов CoreTests.
- Отклонения от ТЗ: уровень выхода ×0,63 (иначе пики по умолчанию ≈ 1,7 в лимитер мастера); исходная высота GRANULAR — нота 48, как у сэмплера (в прототипе — пэд A, A3 = 57); своих ручек у каждого движка нет (решение пользователя); значение POSITION — секунды выбранной дорожки (TexGran.sourceSeconds).
- Открыто: проверка на iPad (сборка UI, звук на слух, нагрузка на самом слабом iPad); экспорт пресета GRANULAR отдельным файлом .jambopreset не несёт сэмпл (как и таблица WTABLE); MOTION = 1 даёт пики до ≈ 2,9 после ×0,63 (как в прототипе, где их срезал компрессор мастера).
- Попутно (решения пользователя): миниатюра ENV в окне MOD — форма только по ручкам, точка всегда на кривой (Core/Mod/EnvDot.swift, EnvDotTests); Duck — источник с MIDI OUT тоже приглушает (триг на MIDI-пути, FxRoutingTests).

## Прочее
- Иконки: клик KICK — полоса в начале, на 100 % до верха поля; у SNARE — две волны корпуса. Превью LFO и ENV движется по таймлайну.
- Reverb по умолчанию: SIZE 30 %, DECAY 1,5 с (отличие от веба — в ios/CLAUDE.md).
- Package.swift: capabilities — перед appCategory (иначе Playgrounds не загружает пакет).

## Проверено
- CoreTests 264 (облако): SynthKnobsTests, DrumEngineTests, SubEngineTests (в том числе testNoGapBeforeSequencedNote — сцена с iPad), TapVelocityTests — NaN, пик ниже 0 dBFS, алиасинг (ANALOG −60 dBc, HAT −50 dB), стыки без щелчка, нагрузка 8 голосов.
- На iPad — все этапы проверены.

## Открыто
- PLAY сэмплера на 1.4 — вернуться с новой реализацией.
