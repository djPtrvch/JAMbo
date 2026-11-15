# Лицензии данных пространств (окно коррекции: SPACE и HEAD)

Импульсы пространств меню SPACE (`ios/JAMbo.swiftpm/Resources/Room*.wav`, `rooms.json`) и пакеты голов
(`ios/HeadPacks/*.zip`, IMPORT в меню HEAD) созданы генератором `ios/tools/generate_room_srir.py` по замерам реальных
комнат и HRTF голов, перечисленных ниже. Своих моделей комнат в приложении нет (15.11, решение пользователя).

## Комнаты — WDR Broadcast Studios (TH Köln)

- Набор: "A Spatial Audio Impulse Response Compilation Captured at the WDR Broadcast Studios" — P. Stade, B. Bernschütz,
  M. Rühl, Technische Hochschule Köln (Proceedings of the 27th Tonmeistertagung, VDT International Convention, 2012).
- Источник: Zenodo, DOI 10.5281/zenodo.3930833, https://zenodo.org/records/3930833
- Лицензия: Creative Commons Attribution 4.0 International (CC BY 4.0) — в карточке записи Zenodo. Внимание: в метаданных
  самих SOFA-файлов и в статье 2012 г. указана CC BY-SA 3.0; обе разрешают коммерческое использование. Перед релизом —
  подтвердить у авторов CC BY 4.0 (при CC BY-SA производные импульсы распространялись бы под той же лицензией).
- Используются: `DRIR_CR7_VSA_110RS_L.sofa`, `DRIR_CR7_VSA_110RS_R.sofa` (Control Room 7, B&W 803D — Studio CR7) и
  `DRIR_SBS_VSA_110RS_PAL.sofa`, `DRIR_SBS_VSA_110RS_PAR.sofa` (Small Broadcast Studio, PA AD-Systems Stium + Flex 15 —
  Hall): сферический массив VariSphear, Лебедев 110 точек.
- Изменения: разложение по направлениям прихода (SDM), рендер через HRIR головы, синтетический поздний хвост по
  измеренному затуханию; в приложении — только итоговые бинауральные импульсы.

## Голова FABIAN (в сборке)

- FABIAN head-related transfer function data base, v4 — F. Brinkmann, A. Lindau, S. Weinzierl и др., TU Berlin.
- Источник: DepositOnce, DOI 10.14279/depositonce-5718.5 — `HRIRs_neutral_head_orientation_v4.zip`
  (`FABIAN_HRIR_measured_HATO_0.sofa`, `FABIAN_CTF_measured_inverted_smoothed.sofa`) и `FABIAN_HRTF_DATABASE_v4.zip`
  (`FABIAN_HRIR_measured_HATO_{10…50, 310…350}.sofa` — для HEAD TRACK).
- Лицензия: CC BY 4.0 (метаданные записи v4 и `GLOBAL_License` в SOFA). Ранние версии записи (DOI 10.14279/depositonce-5718,
  -5718.2 и др.) — CC BY-NC-SA 4.0, их не брать.
- Изменения: HRIR пересчитаны 44,1 → 48 кГц, применена диффузно-полевая эквализация (инверсная CTF).
- Цитирование: F. Brinkmann et al., "A High Resolution and Full-Spherical Head-Related Transfer Function Database for
  Different Head-Above-Torso Orientations", J. Audio Eng. Soc. 65(10), 2017.

## Головы SADIE II (пакеты голов)

- SADIE II Database — C. Armstrong, L. Thresh, D. Murphy, G. Kearney, The Audio Lab, University of York.
- Источник: Zenodo, DOI 10.5281/zenodo.12092466 (v2-2), https://zenodo.org/records/12092466
- Лицензия: Apache License 2.0 (`LICENSE.txt` записи и `GLOBAL_License` в SOFA: "Copyright 2018, University of York,
  Licensed under the Apache License, Version 2.0"). При распространении — сохранить уведомление об авторских правах и
  текст лицензии (в пакет и в приложение — строка в SETTINGS).
- Используются: `H<n>_48K_24bit_256tap_FIR_SOFA.sofa` (H3…H20 — люди, D1 — KU100, D2 — KEMAR).
- Изменения: своя диффузно-полевая эквализация (средняя мощность по сфере, трети октавы), рендер комнат WDR через HRIR.
- Цитирование: C. Armstrong, L. Thresh, D. Murphy, G. Kearney, "A Perceptual Evaluation of Individual and Non-Individual
  HRTFs: A Case Study of the SADIE II Database", Applied Sciences 8(11), 2029, 2018.

## Упоминание в приложении

SETTINGS → OUTPUT → MONITORING — строка об авторах замеров комнат (WDR, TH Köln), FABIAN и SADIE II с лицензиями. Для
App Store — то же в описании или разделе благодарностей.

## Инструменты генератора

numpy, scipy (BSD), sofar (MIT) — только для сборки импульсов и пакетов, в приложение не входят.
