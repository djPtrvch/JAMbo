# Веха S4 — FX, MOD, MORPH

S4a — эффекты в Core; S4b — посылы, шины FX, Sidechain, страница FX; S4c — MOD (LFO1–3, ENV, назначения); S4d — MORPH и режим toggle у FX/MOD; S4e — эталоны FX в SELF-TEST.

## Сделано
- Эффекты — перенос worklet'ов веба 1:1 (расчёт в Double, буферы Float, параметры на блок): Reverb (FDN, PREDELAY, TONE, LOW CUT), Delay (время по темпу, FILTER, SPREAD), Drive (6 типов, оверсэмплер 4×, компенсация), Sidechain (CURVE, триг в кадре ноты). Math.random эталонов — mulberry32 (FxRandom).
- Посылы голосов сэмплера и синта (Reverb, Delay, Drive, с p-lock) → шины дорожки → громкость и mute/solo → FxRack; Sidechain приглушает громкость дорожки и посылы; p-lock FX играющего шага любой дорожки — на время шага.
- Страница FX (удержание FX): без шага — значение в проект и клип-лидер, с шагом — p-lock FX; SC Source — имена дорожек.
- MOD: LFO1–3 и ENV в колбэке, на блок; назначения на ручки дорожки и FX (степень −100…+100 %), перенос и снятие; кольца, зона воздействия, миниатюры LFO/ENV в окне сэмпла.
- MORPH: правки на время режима, выключение возвращает всё (одна запись UNDO); точка на дорожке.
- FX и MOD: SHIFT + двойной тап — режим toggle.
- DIAGNOSTICS: SELF-TEST — 152 эталона (134 движка + 18 FX).

## Проверено (Linux, CoreTests — 116 тестов)
- FX: 18 эталонов (рендер worklet'ов в Node) — Delay −102…−315 dB, Reverb −106…−311, Drive −103…−315, Sidechain −117…−119 dB по отсчётам; полосы ±0,009 dB.
- Посылы, mute, Sidechain, p-lock FX (FxRoutingTests); формы LFO, ADSR, модуляция Level, Chance, FX, ENV от секвенсора (ModTests); MORPH (MorphTests).
- Нагрузка в отладке (виртуалка x86, доля ядра): Delay 0,7, Reverb 4,6–5,5, Drive 13–17, Sidechain 0,6 %.

## Проверено на iPad
- Посылы, эффекты, Sidechain, страница FX, p-lock FX.
- MOD: LFO1–3, ENV, назначения, кольца, миниатюры; MORPH; toggle FX/MOD.
- SELF-TEST — 152/152 PASS.

## Открыто
- Индикация Sidechain в MIX — S5.
- MUTE TAILS и экран SETTINGS → SIDECHAIN — S6.
- Ускорение Drive в отладке — S7.
- Анимация эффектов в окне сэмпла, эффекты на каждой дорожке — этап 12.

## Подробности (из ios/CLAUDE.md)

### S4a (эффекты в Core)
- Core/FX: FxDelay, FxReverb, FxDrive (+ DriveTables — ядро 4× оверсэмплера, антипроизводные, компенсация; shared, строятся вне колбэка), FxDuck (очередь тригов — фиксированный массив) — перенос delay/reverb/drive/duck-worklet.js и oversampler.js 1:1 (расчёт в Double, буферы Float, параметры k-rate на блок).
- FxRandom — mulberry32: в эталонах (ios/tools/fx/golden.mjs) Math.random заменён тем же генератором, модуляция сравнивается по отсчётам. Эталоны: 18 случаев (fx_*.i16, стерео) — −102…−315 dB.
- Нагрузка в отладке (виртуалка, доля ядра): Delay 0,7, Reverb 5,5, Drive 17, Sidechain 0,6 %.

### S4b (посылы, шины FX, Sidechain, страница FX)
- Модель: Params.fxGrid (как FX_GRID веба) и rev.predelay; Project.fx (новый проект — LOW CUT реверба 120 Гц, Drive 80 Гц), FX клипа-лидера — как гамма и нота; AppSettings.scSends (по умолчанию Drive), muteTails (экран — S6).
- Звук: посылы голоса (сэмплер и синт; VoiceParam reverb, delay, drive, с p-lock) — после Pan, в шины посылов дорожки → · громкость · mute/solo (· 1 − amount·e, если посыл приглушается) → FxRack (Reverb, Delay — время по темпу, Drive · 0,5). Sidechain: нота источника (удар рэтчета, живая нота) — триг в своём кадре, если есть кого приглушать; громкость дорожки = 1 − amount·e; стоп — flush. P-lock FX играющего шага любой дорожки (SeqData.fxMask/fxVal) — на время шага, значения FX — на блок.
- Экран: FX (удержание) — сетка FX; без шага — значение в проект и клип-лидер, с шагом — p-lock FX; SC Source — имена дорожек.
- Тесты: FxRoutingTests (посылы, mute, Sidechain, p-lock FX) — 108 тестов. MUTE TAILS — S6, индикация Sidechain в MIX — S5.
- Проверено на iPad: посылы, эффекты, Sidechain, страница FX, p-lock FX.

### S4c (MOD: LFO1–3, ENV, назначения)
- Core/Mod/ModEngine (в колбэке, на блок): LFO1–3 идут всегда (Random — новое значение на цикл), Polarity и Invert; ENV (ADSR) — каждой нотой в своём кадре (гейт: 0,6 удара рэтчета, длина ноты от 2 шагов, иначе 0,9 шага; живая — до отпускания всех клавиш); параметры — с p-lock MOD играющего шага. Track.assigns, Project.fxAssigns (ModAssign: источник 1–4, степень, дорожка FX).
- Модуляция — значение ручки в 0…1 + степень · источник: голоса сэмплера и синта (на кадр ноты и на звучащих), Chance, Ratchet, Swing, ручки FX. Выходы источников, фазы LFO и время ENV — для колец и миниатюр (AtomicFloat).
- Экран: MOD (удержание); LFO1–3 / ENV + поворот — степень −100…+100 %, + двойной тап — снять; держат ручку с назначением — тап по другому источнику переносит назначение с той же степенью, двойной тап по назначенному — снимает; кольцо (LFO1–3 — прозрачность, ENV — пунктир), зона воздействия и «L1 +50%», пока держат источник; белый контур кнопки источника; миниатюры LFO/ENV в окне сэмпла (MOD или 1,5 с после поворота ручки MOD).
- Тесты: ModTests (формы, ADSR, LFO на Level, Chance, FX, ENV от секвенсора). Проверено на iPad.

### S4d (MORPH, toggle FX/MOD)
- MORPH: Track.morphOrig / morphOrigAssign / morphEdited (как trackOrig веба); тап — режим, выключение возвращает всё на всех дорожках (одна запись UNDO); MORPH + UNDO — сброс без переключения; жёлтая точка на дорожке — в левом верхнем углу (отступ 7 × 6).
- FX и MOD: SHIFT + двойной тап — режим toggle (AppSettings.latchFx / latchMod), вторая чёрная линия контура — концентрично контуру кнопки (отступ 3).
- Тесты: MorphTests — 115 тестов.

### S4e (итог S4)
- SELF-TEST: эталоны FX (FxSelfTest, коды 32–35 — DELAY, REVERB, DRIVE, SIDECHAIN) — 152 случая. Итог вехи — docs/SWIFT_MILESTONE_S4.md. Дальше — S5 (мастер, EQ, метры, скоп).
