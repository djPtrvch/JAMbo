# Handoff: JAMbo, Swift-версия — S5

## 1. Контекст проекта
Groovebox для iPad. Веб (`src/`, `public/`) — эталон поведения, заморожен. Swift-перенос — ветка `swift`, `ios/JAMbo.swiftpm` (Swift Playgrounds). Правила — `CLAUDE.md`, `ios/CLAUDE.md`; план вех — `docs/SWIFT_AUDIT.md` (раздел 6).

## 2. Принятые решения
- Переносим всё из веба 1:1 (кроме браузерного); отличия Swift — в «Решениях» `ios/CLAUDE.md`.
- DSP сверяется с эталонами веба (рендер в Node): по отсчётам ≤ −60 dB или полосы ±0,5 dB.
- Эталоны — как у FX (ios/tools/fx/golden.mjs): блоки по 128, k-rate параметры на блок, Math.random → mulberry32; каждый эталон — в SELF-TEST.
- Окна SAT / COMP / CLIP / LIM, EQ Dynamic и Mid/Side, пресеты EQ — S9, не S5.

## 3. Текущая задача
S5 — мастер, EQ (8 полос), индикация, измеритель, LUFS, скоп. Предложение по разбивке:
- S5a — цепочка мастера в Core: сатуратор, glue, клиппер, лимитер (1:1 с saturator-, glue-, clipper-, limiter-worklet.js и oversampler.js), bypass; эталоны.
- S5b — EQ дорожек и мастера: 8 полос (bell, cut 12/24/48, shelf, notch), биквады по RBJ; эталоны.
- S5c — измеритель справа (пик, LUFS BS.1770), метры в MIX, индикация мастера COMP / CLIP / LIM, индикация Sidechain в MIX, скоп (гониометр, осциллоскоп, точки съёма), спектр EQ.
- S5d — MST и свои последовательности MIX и MST (p-lock громкостей); итог вехи — SELF-TEST, docs/SWIFT_MILESTONE_S5.md.

## 4. Что уже решено
- S0–S4 готовы и проверены на iPad (итоги — docs/SWIFT_MILESTONE_S1…S4.md).
- S4: Reverb, Delay, Drive, Sidechain — 1:1 (−102…−315 dB); посылы, страница FX, p-lock FX; MOD (LFO1–3, ENV); MORPH; toggle FX/MOD.
- SELF-TEST — 152 эталона (134 движка + 18 FX), на iPad 152/152 PASS.
- CoreTests — 116 тестов.

## 5. Что осталось решить
- Разбивка S5 (раздел 3) — согласовать с пользователем.
- Спектр EQ: FFT — Accelerate vDSP под `#if canImport(Accelerate)` с обычной реализацией рядом (правило Core).
- Отложено:
  - MUTE TAILS и экран SETTINGS → SIDECHAIN — S6;
  - ускорение Drive (17 % в Debug) — S7;
  - свои WAV-таблицы — S10.

## 6. Важные ограничения
- Колбэк: без выделения памяти, блокировок, Swift-коллекций.
- Только Swift и фреймворки Apple; файл ≤ ~600 строк.
- Надписи — на английском; комментарии и документы — по-русски.
- Markdown: путь, причина, точный текст — затем подтверждение.
- Тесты: `ios/tools/install-swift-linux.sh`, затем `. ios/tools/swift-env.sh && cd ios/CoreTests && swift test`. UI проверяет пользователь на iPad (присылать `swift.zip` всего репозитория).
- PR — только по просьбе.

## 7. Первый запрос для нового чата
«Прочитай docs/handoffs/HANDOFF.md, ios/CLAUDE.md (разделы S4a–S4e) и docs/ai/master-chain.md, docs/ai/master-clip-lim.md, docs/ai/fx-eq.md (EQ). Согласуй разбивку S5, затем начни S5a: цепочка мастера в Core с эталонами.»
