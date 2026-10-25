# S15 — аранжировщик

Решение пользователя: S14 на паузе (остановились на S14c), S15 — аранжировщик; автоматизация на таймлайне — в этой вехе (S15f, решение пользователя), S16 — автоматизация в паттернах (нужна ли — открыто). ТЗ — от пользователя (JAMbo_Arrange_TZ.md, в чате), с решениями в чате; поведение — docs/ai/arranger.md.

## План
- S15a — данные (готово). S15b — игра в колбэке (готово). S15c — экран (готово). S15d — секции, петля, INSERT (готово). Правки S15c/S15d по проверке на iPad — несколько кругов, проверены пользователем (линейка и левые углы прямые, заголовки вплотную, маркер плейхеда во всю строку секций, «нет цвета» у дорожки, цвет дорожки — только у блоков, секция — только из диапазона, измеритель до низа окна, метры заголовков, прокрутка по заголовкам).
- S15e — перенос из сетки: e1 — TO ARRANGE в меню строки (готово: Project.rowToArrange, меню строки END / CURSOR, тест testRowToArrange); e2 — журнал и SEND TO ARRANGE (готово: Core/Model/ArrangeJournal.swift — ArrJournal, Project.sendToArrange; журнал и тик — в LiveState по сообщениям clip и step, begin при PLAY; бутерброд сетки END / CURSOR; тесты testJournalTake, testSendToArrange); e3 — запись с AUTO (готово: Core/Model/ArrangeRecorder.swift — ArrRecorder (отрезки по сообщениям arrange и clip, скачок петли), Project.applyRecording; в LiveState — recorder, beginRecord, finishRecord; AppModel.arrAuto, syncArrRecord на PLAY, стопе, .ended, REC и AUTO; ноты с AUTO не пишутся; ARRANGE — красный контур; тест testRecorder). TO ARRANGE: короткие клипы повторяются до длины строки (решение пользователя).
- S15f — автоматизация на таймлайне (решение пользователя: в этой вехе, до REF; AUTO — показ строк кривых и запись): f1 — данные и воспроизведение (готово: Core/Model/ArrangeAuto.swift — ArrAutoLane, ArrAutoTarget, Track.autos; SeqData — autoFirst/autoCount/autoX/autoY, probLock; Core/Sequencer/ArrangeAutoPlay.swift — подстановка в снимок звука на блок, Chance и Ratchet на шаге, autoHold; тесты testAutomationOverridesKnob, testAutomationOnlyOnTimeline, testLaneValue); f2 — показ и правка под дорожкой (готово: ArrMetrics — autoTrack, lanes, laneY, lane(at:); AppModelArrangeAuto — arrAutoView, ручки, правки; ArrAutoHeaders, ArrAutoAddMenu, ArrAutoLaneMenu; ArrDraw.autoLanes; ArrTouches — точки); f3 — запись поворотов ручек (готово: ArrAutoLane.simplify, Track.recordAuto, тест testRecordAuto; AppModelArrangeAuto — AutoTake, knobTouch (рука — autoHold), autoTakeBegin / autoTakePoint / flushAutoTake, arrNowX, autoCurveNorm; LiveState.arrPosTime).
- S15g — REF.

## S15a — данные (Core/Model/Arrange.swift, ArrangeEdits.swift)
- ArrBlock (clip, start, length, offset — место в проходе клипа), Track.blocks и Track.color (номер в ArrPalette; блоки переезжают, удаляются и копируются с дорожкой; PASTE дорожки — блоки и цвет свои). Arrangement (Project.arrange): markers (ArrMarker: at, name, color, end — конец секции или nil), loopFrom / loopTo / loop, grid (ArrGrid: 16, 8, 4, 1 шаг), snap, hideSteps. Формат версии 5; repair — клипы в пределах, без перекрытий, цвет и сетка в пределах.
- Правки: placeBlock (перекрытая часть заменяется, блок шире участка делится — правая часть с offset), addBlock, moveBlock, resizeBlock (левый край сдвигает offset), duplicateBlock, pasteBlock(after:), insertBlock и resizeInserted (сдвиг блоков дорожки), shiftArrange, splitArrange, duplicateBlocks, pasteBlocks; секции addMarker(end:), moveMarker (секция с концом — целиком), section(at:), sectionEnd; setLoop. Строки сетки (deleteRow, moveRow, duplicateRow, pasteRow) ведут блоки (remapBlocks).
- Тесты: ArrangeTests.

## S15b — игра (Core/Sequencer/ArrangePlay.swift, Launcher, SeqSnapshot)
- Снимок: блоки дорожек (arrFirst, arrCount, blkClip, blkStart, blkLen, blkOff), arrEnd, петля. SeqData.block(t, at:) — блок под курсором.
- Launcher: follow (дорожка по таймлайну), arrDirty, arrPos, arrangeMode, arrFrom. arrangeStep — курсор, петля (переход через loopTo — на loopFrom), стоп в конце (все на таймлайне, без петли); syncArrange — клип блока с trackStart = tick − (позиция в блоке + offset), вне блоков — стоп; сообщение clip только при разрыве. Клип или строка из сетки — setFollow(false) этих дорожек. Старт — сообщения follow всегда (force), иначе интерфейс после stopped() считал дорожки в сетке.
- События: arrange(on:from:) перед PLAY, returnToArrange(track:), leaveArrange (MIX), seekArrange(pos) — курсор при игре со следующего шага. SeqOut: arrange(pos:) на каждом шаге, follow(track:on:).
- Тесты: ArrangePlayTests (точный старт, повтор и обрыв, конец, offset, петля, клип из сетки и возврат, сетка без таймлайна, MIX, переход курсора).

## S15c / S15d — экран (UI/Arrange*.swift, AppModelArrange*.swift)
- ArrangeWindow: ArrHeaders | ArrTimeline (один Canvas, ArrDraw; рисование — внутри рамки с прямыми левыми углами) | место измерителя. ArrMetrics — размеры и прокрутка (COMPACT — строки на высоту окна; EXPANDED — своя высота 44…120). Измеритель справа — MeterColumn в RootView на рамке измерителя окна дорожки (AppModel.meterFrame), низ — по низу окна (AppModel.arrBottom); пока она неизвестна — в окне.
- ArrHeaders: строки одним VStack с одним сдвигом (прокрутка без отставания — на iPad отдельные сдвиги строк отставали от таймлайна и «смазывались»); метры всех заголовков — один Canvas с одним таймером (ArrHeaderMeters). Палец вверх-вниз по заголовку — прокрутка, тап — выбор, двойной тап — меню дорожки.
- ArrTouches (таймлайн): тап, двойной тап, удержание (подъём блока, ArrLift — вид с анимацией), края, прокрутка, два пальца (ось — что разошлась первой; вместе вбок — прокрутка, вверх-вниз — ничего). ArrRulerTouches (линейка): курсор, протяжка диапазона, края диапазона, двойной тап по диапазону (ADD SECTION, SPLIT), секции по двойному тапу, перетаскивание секции.
- ArrangeBar — вторая строка; ArrMenus — меню блока, места, дорожки, секции (ArrMarkerWindow), INSERT, диапазона; ArrPaletteGrid — 19 квадратиков (у дорожки первый — «нет цвета», перечёркнутый круг).
- SETTINGS → ARRANGE (AppSettings.arrangeCompact; EXPANDED по умолчанию). ARRANGE — цель MIDI.
- Компилятор Playgrounds: длинные выражения в ArrangeMenus не проверялись по типам — всё по шагам с явными типами.

## S15e / S15f — перенос из сетки, запись, автоматизация
- Перенос и запись: см. план (e1–e3). Журнал и запись — в LiveState по сообщениям колбэка (clip, step, arrange), в проект — одной правкой.
- Автоматизация: кривая — 0…1 положения ручки по шагам таймлайна; колбэк (ArrAutoPlay.apply, до модуляции, FX и голосов) пишет значение в снимок звука (params, scAmount) и возвращает прежнее, когда кривая перестала действовать (новый снимок звука — ручки заново). Действует только у дорожек на таймлайне (Launcher.follow) и только от первой точки до последней. Chance и Ratchet — в Sequencer.trig (probLock — их p-lock на шаге).
- Рука: knobTouch → .autoHold (по слоту — autoSlotKeys, снимается и после смены режима ручек); ручка начинает с значения кривой (knobStart).
- Ручка показывает кривую, как в вебе: дуга и стрелка — значение кривой (TimelineView каждый кадр), жёлтая риска r 32…42 (KnobState.autoNorm).
- Магнит: точки кривой — на линиях сетки таймлайна (gridSteps), без магнита — четверть шага.

## Проверено
- Core: 376 тестов на Linux. На iPad — S15c и S15d (несколько кругов правок), TO ARRANGE и SEND TO ARRANGE (по замечаниям пользователя исправлено: пустые ячейки строки, отступ TO ARRANGE), автоматизация рисуется и записывается. После последних правок на iPad не проверены: звук по кривой (возможная причина — залипшее удержание рукой, исправлено), кривая на ручке, магнит точек.
- S13e (SYNC RECEIVE, SYNC START/STOP выкл. — свой PLAY и STOP независимы) — пользователь проверил: работает.

## Открыто
- Возврат дорожек к таймлайну во время игры — кнопки нет (стрелка к черте теперь — курсор в начало); нужна ли и где.
- Инерция прокрутки — нет.
- AppModel.swift — больше 600 строк (было и до S15).
- Кривые — только у дорожек на таймлайне; при игре из сетки (курсор идёт и там) — не действуют. Предложено пользователю сделать и при игре из сетки — ждёт ответа.
- STEPS: пользователь видел, что при включении и выключении скрываются и дорожки (строка дорожек по коду остаётся) — отложено пользователем, уточнить.
- ios/CLAUDE.md «Решения» — строка про S15 (внести в конце вехи).
