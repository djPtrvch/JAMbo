# Handoff: JAMbo, Swift-версия — S5b

## 1. Контекст проекта
Groovebox для iPad. Веб (`src/`, `public/`) — эталон, заморожен. Swift-перенос — ветка `swift`, `ios/JAMbo.swiftpm`. Правила — `CLAUDE.md`, `ios/CLAUDE.md`; план — `docs/SWIFT_AUDIT.md`.

## 2. Принятые решения
- Переносим всё из веба (кроме браузерного); отличия — в «Решениях» `ios/CLAUDE.md`.
- Мастер упрощён (решение пользователя): без BIAS, OUTPUT, AUTO, RANGE, HOLD, LINK, MIX клиппера, UNITY, AUDIT; SCALE — 48 dB; PRESETS модулей мастера — S9.
- DSP сверяется с эталонами веба (рендер в Node, блоки по 128): по отсчётам ≤ −60 dB или полосы ±0,5 dB; каждый эталон — в SELF-TEST.
- Разбивка S5: S5a — мастер в Core; S5b — EQ 8 полос; S5c — измеритель, LUFS, метры MIX, индикация COMP/CLIP/LIM, Sidechain в MIX, скоп, спектр EQ; S5d — ручки MST, последовательности MIX и MST, итог вехи.

## 3. Текущая задача
S5b — EQ дорожек и мастера: 8 полос (bell, low/high cut 12/24/48, low/high shelf, notch), биквады RBJ; эталоны; EQ мастера — первым в цепочке (MasterChain). Dynamic, M/S, пресеты EQ — S9.

## 4. Что уже решено
- S0–S4 готовы и проверены на iPad.
- S5a: Core/Master (SAT, COMP, CLIP, LIM, MasterChain), Project.master и BYPASS, AudioCore: дорожки и FX → мастер; 19 эталонов mst_* (−108…−122 dB); SELF-TEST 171; CoreTests 126.

## 5. Что осталось решить
- S5a на iPad не проверен: сборка, SELF-TEST 171/171, звук, CPU.
- Спектр EQ: FFT — Accelerate vDSP под `#if canImport(Accelerate)` с обычной реализацией.
- В конце S5 сократить `ios/CLAUDE.md` (167 строк).
- Отложено: MUTE TAILS — S6; ускорение Drive и мастера — S7; свои WAV-таблицы — S10.

## 6. Важные ограничения
- Колбэк: без выделений, блокировок, Swift-коллекций.
- Только Swift и фреймворки Apple; файл ≤ ~600 строк.
- Надписи — английские; комментарии и документы — русские.
- Markdown: путь, причина, точный текст — затем подтверждение.
- Тесты: `ios/tools/install-swift-linux.sh`, затем `. ios/tools/swift-env.sh && cd ios/CoreTests && swift test`.
- PR — только по просьбе.

## 7. Первый запрос для нового чата
«Прочитай docs/handoffs/HANDOFF.md, ios/CLAUDE.md (S5a) и docs/ai/fx-eq.md (EQ). Начни S5b: EQ 8 полос в Core с эталонами.»
