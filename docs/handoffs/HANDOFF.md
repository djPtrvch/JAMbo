# Handoff: JAMbo, Swift-версия — S5d

## 1. Контекст проекта
Groovebox для iPad. Веб (`src/`, `public/`) — эталон, заморожен. Swift-перенос — ветка `swift`, `ios/JAMbo.swiftpm`. Правила — `CLAUDE.md`, `ios/CLAUDE.md`; план — `docs/SWIFT_AUDIT.md`.

## 2. Принятые решения
- Переносим всё из веба (кроме браузерного); отличия — в «Решениях» `ios/CLAUDE.md`.
- DSP сверяется с эталонами веба: по отсчётам ≤ −60 dB или полосы ±0,5 dB; каждый эталон — в SELF-TEST. Эталоны Web Audio — настоящий код веба в headless Chromium через протокол отладки (`ios/tools/eq/golden.mjs` — образец).
- Разбивка S5: S5a — мастер в Core (готов); S5b — EQ (готов); S5c — измеритель, LUFS, метры MIX, Sidechain в MIX, индикация COMP/CLIP/LIM, скоп (готов в коде); S5d — ручки MST, громкость выхода, последовательности MIX и MST, итог вехи.

## 3. Текущая задача
S5d: ручки MST (16 параметров мастера по колонкам SAT, COMP, CLIP, LIM), громкость выхода мастера (после лимитера; регулятор на измерителе при MIX и MST, гониометр — после неё), свои последовательности MIX и MST (p-lock громкостей и параметров мастера), итог вехи S5 в docs/SWIFT_MILESTONE_S5.md и ios/CLAUDE.md. Решить с пользователем: кнопки мастера на месте LFO1–3/ENV (CLIP, LIM, SAT, COMP; с SHIFT — BYPASS) — в S5d или вместе с окнами в S9.

## 4. Что уже решено
- S0–S4 готовы и проверены на iPad. S5a: мастер (19 эталонов). S5b: EQ (13 эталонов), экран EQ, спектры, COMPARE; SELF-TEST 184.
- S5c (подробно — docs/SWIFT_MILESTONE_S5.md, раздел S5c): Core/Engine/Levels (пики дорожек и мастера по блокам, приглушение Sidechain, Loudness — LUFS показанного канала по BS.1770), микшер — Core/Sampler/SamplerMix; UI/MeterState, MeterColumn (измеритель справа, регулятор громкости дорожки), метры MIX в MixCell; Core/Master/DynTele + UI/MasterIndicator (COMP | CLIP | LIM); Core/Master/MasterScope + UI/MasterScopeView (гониометр, осциллоскоп, кнопки COMP, CLIP, LIM). CoreTests — 144.
- Отличие S5c от веба: послесвечение гониометра — старые отсчёты окна бледнее (в вебе — затухание холста).

## 5. Что осталось решить
- На iPad не подтверждены: сборка и вид S5c (измеритель, метры MIX, индикация, скоп), SELF-TEST 184/184, звук мастера и EQ на мастере, CPU.
- При MST на измерителе регулятора нет — появится с громкостью выхода (S5d).
- Тап по блоку индикации — окно модуля (S9).
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
«Прочитай docs/handoffs/HANDOFF.md, ios/CLAUDE.md, docs/SWIFT_MILESTONE_S5.md и docs/ai/master-chain.md (MST, кнопки мастера). Начни S5d: ручки MST и громкость выхода.»
