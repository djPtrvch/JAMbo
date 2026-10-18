# Handoff: JAMbo, Swift-версия — S5c

## 1. Контекст проекта
Groovebox для iPad. Веб (`src/`, `public/`) — эталон, заморожен. Swift-перенос — ветка `swift`, `ios/JAMbo.swiftpm`. Правила — `CLAUDE.md`, `ios/CLAUDE.md`; план — `docs/SWIFT_AUDIT.md`.

## 2. Принятые решения
- Переносим всё из веба (кроме браузерного); отличия — в «Решениях» `ios/CLAUDE.md` (на S5b добавлены: COMPARE, строка EQ от края BPM, ввод частоты удержанием, двойной тап по точке — удалить, ON/OFF в меню).
- DSP сверяется с эталонами веба: по отсчётам ≤ −60 dB или полосы ±0,5 dB; каждый эталон — в SELF-TEST. Эталоны Web Audio (BiquadFilterNode и т. п.) — настоящий код веба в headless Chromium через протокол отладки (`ios/tools/eq/golden.mjs` — образец).
- Разбивка S5: S5a — мастер в Core (готов); S5b — EQ (готов, вместе со спектром EQ из S5c); S5c — измеритель, LUFS, метры MIX, индикация COMP/CLIP/LIM, Sidechain в MIX, скоп; S5d — ручки MST, громкость выхода, последовательности MIX и MST, итог вехи.

## 3. Текущая задача
S5c — индикация: измеритель справа (пик, LUFS), метры MIX, индикация COMP/CLIP/LIM (кадры IN / GR / OUT в Core уже считаются), Sidechain в MIX, скоп мастера. Спектр EQ уже сделан.

## 4. Что уже решено
- S0–S4 готовы и проверены на iPad.
- S5a: мастер (SAT, COMP, CLIP, LIM), 19 эталонов.
- S5b: Core/EQ — 8 полос, биквады Web Audio, каскады cut, сглаживание с особенностью стерео-узла Chromium, кроссфейд 40 мс; EQ дорожки (сухой сигнал и посылы, общие коэффициенты) и мастера (перед SAT); 13 эталонов (−77…−105 dB); SELF-TEST 184; CoreTests 139. Экран EQ (UI/EqView, EqPlot, EqSpectrum, AppModelEq), спектры (Core/EQ/Spectrum — съём в колбэке, анализ как AnalyserNode вне колбэка), COMPARE.
- На iPad: сборка и экран EQ проверены (точки, меню, спектры, COMPARE).

## 5. Что осталось решить
- На iPad не подтверждены: SELF-TEST 184/184, звук мастера и EQ на мастере, CPU.
- FFT — своё (0,08 мс на спектр); vDSP — только если на iPad будет тяжело.
- `ios/CLAUDE.md` сокращён (подробности вех — в docs/SWIFT_MILESTONE_Sx.md).
- Отложено: M/S, Dynamic, пресеты EQ и модулей мастера — S9; MUTE TAILS — S6; ускорение — S7.

## 6. Важные ограничения
- Колбэк: без выделений, блокировок, Swift-коллекций.
- Только Swift и фреймворки Apple; файл ≤ ~600 строк.
- Playgrounds: выражения — по шагам с явными типами (иначе «unable to type-check»); UI на Linux не собирается — проверка только на iPad.
- Надписи — английские; комментарии и документы — русские.
- Markdown: путь, причина, точный текст — затем подтверждение.
- Тесты: `ios/tools/install-swift-linux.sh`, затем `. ios/tools/swift-env.sh && cd ios/CoreTests && swift test`.
- PR — только по просьбе.

## 7. Первый запрос для нового чата
«Прочитай docs/handoffs/HANDOFF.md, ios/CLAUDE.md, docs/SWIFT_MILESTONE_S5.md и docs/ai/master-chain.md (индикация мастера). Начни S5c: измеритель и метры.»
