# S15 — аранжировщик

Решение пользователя: S14 на паузе (остановились на S14c), S15 — аранжировщик, автоматизация — S16. ТЗ — от пользователя (JAMbo_Arrange_TZ.md, в чате), с решениями в чате; поведение — docs/ai/arranger.md.

## План
- S15a — данные (готово). S15b — игра в колбэке (готово). S15c — экран (готово). S15d — секции, петля, INSERT (готово). Правки S15c/S15d по проверке на iPad — несколько кругов, последний коммит 1055528 на iPad ещё не проверен.
- S15e — перенос из сетки: e1 — TO ARRANGE в меню строки (готово: Project.rowToArrange, меню строки END / CURSOR, тест testRowToArrange); e2 — журнал и SEND TO ARRANGE (готово: Core/Model/ArrangeJournal.swift — ArrJournal, Project.sendToArrange; журнал и тик — в LiveState по сообщениям clip и step, begin при PLAY; бутерброд сетки END / CURSOR; тесты testJournalTake, testSendToArrange); e3 — запись с AUTO (готово: Core/Model/ArrangeRecorder.swift — ArrRecorder (отрезки по сообщениям arrange и clip, скачок петли), Project.applyRecording; в LiveState — recorder, beginRecord, finishRecord; AppModel.arrAuto, syncArrRecord на PLAY, стопе, .ended, REC и AUTO; ноты с AUTO не пишутся; ARRANGE — красный контур; тест testRecorder). TO ARRANGE: короткие клипы повторяются до длины строки (решение пользователя).
- S15f — автоматизация на таймлайне (решение пользователя: в этой вехе, до REF; AUTO — показ строк кривых и запись): f1 — данные и воспроизведение (готово: Core/Model/ArrangeAuto.swift — ArrAutoLane, ArrAutoTarget, Track.autos; SeqData — autoFirst/autoCount/autoX/autoY, probLock; Core/Sequencer/ArrangeAutoPlay.swift — подстановка в снимок звука на блок, Chance и Ratchet на шаге, autoHold; тесты testAutomationOverridesKnob, testAutomationOnlyOnTimeline, testLaneValue); f2 — показ и правка под дорожкой; f3 — запись поворотов ручек.
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

## Проверено
- Core: 368 тестов на Linux. На iPad — S15c и S15d по видео и скриншотам пользователя; правки последнего круга (масштаб по Y, линии выбранной дорожки, паттерн квадратиками и линиями) — ещё нет.

## Открыто
- Возврат дорожек к таймлайну во время игры — кнопки нет (стрелка к черте теперь — курсор в начало); нужна ли и где.
- Инерция прокрутки — нет.
- AppModel.swift — больше 600 строк (было и до S15).
