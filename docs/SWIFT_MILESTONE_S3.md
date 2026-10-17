# Веха S3 — движки синта (Plaits и свои), SELF-TEST

S3a — восемь движков MI SYNTH (Plaits 0–7), голос синта, окно синта; S3b — MI DRUMS (Plaits 8–15), свои движки DRUM, ANALOG, FM, WTABLE (16–19) и ускорение движков под отладочную сборку Playgrounds.

## Сделано
- Plaits 0–15 — перенос 1:1 по исходникам MI (eurorack 08460a6, stmlib e3bd7c9): VA, WAVESHAPE, FM, GRAIN, ADDITIVE, WAVETABLE, CHORDS, SPEECH (Formant, Phoneme, LPC; без Words), SWARM, NOISE, PARTICLE, STRING, MODAL, KICK, SNARE, HI-HAT.
- Свои движки — перенос jambo-synth-worklet.js и wavetable.ts веба 1:1: DRUM (монофоничная бочка, PITCH в Гц, Decay до 1000 мс), ANALOG (2 × PolyBLEP + суб, ×2, дрейф на дорожку; при выборе — синус), FM (2 оператора, ×2, CONTOUR), WTABLE (6 встроенных таблиц, мипмапы, WARP, UNISON).
- Голос синта: 6 голосов на дорожку, огибающая, Level, фильтр, Pan — как у сэмпла; затухающие сами (STRING, MODAL, KICK, SNARE, HI-HAT, DRUM) — огибающая только с атакой, Morph Plaits от Decay, ручка 1.3 — OUT→AUX; сглаживание Timbre, Morph и OUT→AUX (10 мс).
- Меню звука: SYNTH (DRUM, ANALOG, FM, WTABLE), MI SYNTH, MI DRUMS; TABLE — список встроенных таблиц WTABLE (до браузера S10, решение пользователя).
- Окно синта: заголовок (MI · у Plaits), живая иконка движка 0–18 (у WTABLE — кадр таблицы и её имя), ручки 1.1–1.3.
- DIAGNOSTICS: SELF-TEST (134 эталона веба), строка Build (Debug/Release).
- Отладочная сборка (Playgrounds собирает Debug): горячие циклы без вызовов из других файлов, без обобщённых преобразований целых, состояние — в локальных переменных; денормалы в затухающих состояниях — в ноль.

## Проверено (Linux, CoreTests — 98 тестов)
- Plaits: 106 эталонов (16 движков × 3 набора × 2 ноты + AUX у 11–15) — по отсчётам ≤ −60 dB или полосы ±0,5 dB, страховка −40 dB; большинство −70…−120 dB. HI-HAT — порядок умножения как в plaits.wasm (-ffast-math).
- Свои движки: 28 эталонов (рендер worklet в Node) — −108…−118 dB (остаток Int16); таблицы WTABLE — до 1e-5.
- Иконки 0–18 — 95 случаев против engineIcons.ts веба.
- Голос: A4 = 440 Гц, атака и релиз, кража голоса, KICK затухает при зажатой клавише, Decay → длина, OUT→AUX, DRUM — одна нота аккорда, WTABLE без таблицы молчит.
- Нагрузка в отладке (виртуалка x86, 6 голосов): MI SYNTH 8–17 %, MI DRUMS 4–18 %, ANALOG 10, FM 14, WTABLE 3–6, DRUM 1 %; релиз — в 8–12 раз меньше.

## Проверено на iPad
- SELF-TEST — PASS (Plaits — 48/48 на S3a; полный — на S3b), Build: Debug.
- Все движки звучат с пианоролла и секвенсора; ручки, иконки, TABLE, светлая тема.
- CPU: аккорды ADDITIVE — до 34 % (до ускорения); после ускорения DIAGNOSTICS — 12 % avg, 23 % peak.

## Открыто
- Посылы и FX, MOD/LFO и иконка от модуляции — S4; пресеты и SAVE — S10.
- Свои WAV-таблицы WTABLE и браузер LOAD TABLE — S10; таблица в проекте и пресете — S6/S10.
- Режим Words SPEECH — этап 12 (лицензия данных).
- Релизная сборка для App Store — S7 (цифры CPU на iPad в релизе).
