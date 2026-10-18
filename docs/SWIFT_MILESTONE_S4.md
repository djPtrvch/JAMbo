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
