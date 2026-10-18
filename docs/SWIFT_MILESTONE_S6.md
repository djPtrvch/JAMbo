# Веха S6 — окна модулей мастера (готова)

S6-1 — общая основа окон, окно LIM, PRESETS модулей; S6-2 — окно COMP; S6-3 — окно CLIP; S6-4 — окно SAT; затем правки после проверки на iPad. Поведение — docs/ai/master-chain.md, docs/ai/master-clip-lim.md (веб), отличия — «Решения» ios/CLAUDE.md.

## Что сделано
- Открытие: при MST тап по кнопке мастера без SHIFT (COMP, CLIP / SAT, LIM — по цепочке) и тап по блоку индикации COMP | CLIP | LIM (общий жест окна сэмпла при MST выключен — касания получают блоки). Окно — на месте центра (как EQ), справа измеритель; EQ, PATTERNS, редактор сэмпла и окно модуля не открыты одновременно; выход из MST закрывает. Открытость и FREEZE не в проекте.
- Строка 48 px (UI/MasterWindow): название под бутербродом (MASTER / LIM ▾ — тап: меню SAT, COMP, CLIP, LIM), поля с левого края поля BPM, как в EQ; PRESETS, BYPASS, ✕. Поля — как в EQ, без жёлтой подсветки: палец вверх-вниз — 240 px на весь диапазон (одна запись UNDO на жест), удержание — ввод числом (системное окно; Core/Model/MasterInput — «auto», «off», «1.2 s», «1.5k», TAPE/TUBE/EDGE); тап по RATIO — 2:1 → 4:1 → 10:1, по TYPE — следующий тип; при BYPASS поля серые (у LIM — INPUT и CEILING). Поля без ручек — Params.masterExtra (FOCUS, RATIO, KNEE, MIX, SC HPF).
- Дисплеи (UI/MasterDisplay, общие): шкала 0…−48 dB, сетка 6 dB; история 4 с из кольца DynTele (750 кадров, столбец — максимум отрезка), подписи пиков GR, линия параметра тянется пальцем (±22 px), двойной тап мимо линии — FREEZE (снимок кольца); справа блок индикации (тот же MasterIndicator.draw).
- LIM: вход, выход, GR, линия CEILING, красные точки выше CEILING.
- COMP: TRANSFER (колено, кривая — MasterGlue.staticGr, точка порога вдоль диагонали, кружок RATIO, живая точка детектора, оранжевый участок сжатия) | LEVEL (пунктир THRESHOLD).
- CLIP: TRANSFER на той же шкале, что LEVEL (кривая — MasterClipper.staticOut, ручка-угол: CEILING и INPUT) | LEVEL с GR; без WAVE и VIEW.
- SAT: TRANSFER (−1…+1, MasterTables.satCurve — та же таблица компенсации, что в колбэке; палец по вертикали — DRIVE; точка текущего уровня) | SPECTRUM (вход и выход сатуратора, 20 Hz…20 kHz, 0…−96 dB, сглаживание как у спектров EQ, линия FOCUS тянется); без WAVE и BIAS. Точки съёма MasterChain.satIn / satOut пишутся, только пока окно SAT открыто (satOn).
- PRESETS модулей (Core/Model/MasterPresets, UI/MasterMenus): у каждого модуля свой список, общий для проектов (UserDefaults «masterPresets»); SAVE (имя — окном ввода, до 40 знаков), тап — загрузить (одна запись UNDO), свайп влево — карандаш на сером (RENAME) и корзина на красном (DELETE); меню шириной 260.
- Кнопки мастера с SHIFT — в две строки: BYPASS и имя модуля.

## Проверено
- CoreTests — 159 (новые: MasterPresetTests, MasterInputTests, GlueCurveTests — кривая против DSP на синусе, ClipCurveTests — против DSP на синусе 200 Гц, SatCurveTests — компенсация и точки съёма только при открытом окне).
- На iPad: все четыре окна, поля, ввод числом, линии и ручки, FREEZE, пресеты и свайп, кнопки мастера, закрытие.

## Открыто
- Пресеты EQ со свайпом — S7; спектр SAT веба (точнее, по пикселю) — при необходимости; WAVE клиппера и сатуратора — не переносятся (решение пользователя).
