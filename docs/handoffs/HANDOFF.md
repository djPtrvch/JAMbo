# Handoff: JAMbo, Swift-версия — S4e

## 1. Контекст проекта
Groovebox для iPad. Веб (`src/`, `public/`) — эталон поведения, заморожен. Swift-перенос — ветка `swift`, `ios/JAMbo.swiftpm` (Swift Playgrounds). Правила — `CLAUDE.md`, `ios/CLAUDE.md`; план вех — `docs/SWIFT_AUDIT.md` (раздел 6).

## 2. Принятые решения
- Переносим всё из веба 1:1 (кроме браузерного); отличия Swift — в «Решениях» `ios/CLAUDE.md`.
- DSP сверяется с эталонами веба (рендер в Node): по отсчётам ≤ −60 dB или полосы ±0,5 dB.
- MOD (LFO/ENV) считается в колбэке, на блок.
- Эталоны FX: Math.random → mulberry32 (FxRandom), сверка по отсчётам.

## 3. Текущая задача
S4e — итог вехи S4: эталоны FX в SELF-TEST, `docs/SWIFT_MILESTONE_S4.md`, итоговая проверка на iPad.

## 4. Что уже решено
- S0–S3 готовы.
- S4a–S4d готовы и проверены на iPad (кроме последнего отката отступа точки p-lock):
  - Reverb, Delay, Drive, Sidechain — 1:1, −102…−315 dB;
  - посылы, страница FX, p-lock FX;
  - LFO1–3, ENV, назначения, кольца, миниатюры;
  - MORPH;
  - toggle FX/MOD.
- Правки секвенсора и пианоролла перед S4 — в `ios/CLAUDE.md`.
- CoreTests — 115 тестов.

## 5. Что осталось решить
- S4e: SELF-TEST с FX, итог вехи.
- Отложено:
  - MUTE TAILS и экран SETTINGS → SIDECHAIN — S6;
  - индикация Sidechain в MIX — S5;
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
«Прочитай docs/handoffs/HANDOFF.md и ios/CLAUDE.md (разделы S4a–S4d). Сделай S4e: эталоны FX в SELF-TEST, затем предложи текст docs/SWIFT_MILESTONE_S4.md.»
