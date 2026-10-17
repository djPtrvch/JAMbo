# Handoff: JAMbo, Swift-версия — S4

## 1. Контекст проекта
Groovebox для iPad. Веб (`src/`, `public/`) — эталон поведения, заморожен. Swift-перенос — ветка `swift`, `ios/JAMbo.swiftpm` (Swift Playgrounds). Правила — `CLAUDE.md`, `ios/CLAUDE.md`; план вех — `docs/SWIFT_AUDIT.md` (раздел 6); итоги — `docs/SWIFT_MILESTONE_S0…S3.md`.

## 2. Принятые решения
- Переносим всё, что сделано в вебе, 1:1 (кроме чисто браузерного).
- FX — 1:1 по worklet’ам веба: Reverb FDN, Delay с FILTER/SPREAD, Drive 6 типов, Sidechain с CURVE.
- Перенос DSP сверяется с эталонами веба (рендер в Node): по отсчётам ≤ −60 dB или третьоктавы ±0,5 dB, страховка −40 dB.
- Playgrounds собирает Debug — горячие циклы по «Правилам кода» ios/CLAUDE.md.
- У каждого клипа свой паттерн (отличие от веба).

## 3. Текущая задача
Веха S4: посылы и FX дорожек (Reverb, Delay, Drive, Sidechain), MOD (LFO1–3, ENV, назначение, кольца), MORPH, переключатель FX/MOD.

## 4. Что уже решено
S0–S3 готовы и проверены на iPad: секвенсор, сетка паттернов, сэмплер, синт (Plaits 0–15, DRUM, ANALOG, FM, WTABLE), SELF-TEST 134/134, CPU (Debug) 12 % avg / 23 % peak. CoreTests — 98 тестов.

## 5. Что осталось решить
- План S4: порядок задач, эталоны FX, где считается MOD (колбэк или UI).
- Открыто с S3: свои WAV-таблицы и браузер (S10), таблица в проекте (S6), #39 (точка p-lock и рамка шага), #40 (перетяжка миниатюр).

## 6. Важные ограничения
- Колбэк: без выделения памяти, блокировок, Swift-коллекций.
- Только Swift и фреймворки Apple; файл ≤ ~600 строк.
- Надписи — на английском; комментарии и документы — по-русски.
- Markdown: путь, причина, точный текст — затем подтверждение пользователя.
- Тесты: `ios/tools/install-swift-linux.sh`, затем `. ios/tools/swift-env.sh && cd ios/CoreTests && swift test`. UI проверяет пользователь на iPad.
- PR — только по просьбе.

## 7. Первый запрос для нового чата
«Прочитай docs/handoffs/HANDOFF.md, ios/CLAUDE.md и docs/ai/fx-eq.md, docs/ai/sequencer.md (MOD). Предложи план S4 задачами; код не меняй до подтверждения.»
