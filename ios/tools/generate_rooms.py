#!/usr/bin/env python3
"""Генератор бинауральных импульсов комнат для Room (Headphone Monitor, фаза 2).

Воспроизводимо (фиксированный seed) создаёт ios/JAMbo.swiftpm/Resources/Room*.wav и rooms.json — пространства пунктов
TRANSLATION (8.11): Studio (студия, мониторы ±30° на 1,5 м), Home (жилая комната), Car (салон, место водителя слева,
динамики в дверях), Club (зал ~2500 м³, стеки в ~10 м, хвост ~0,8 с — ориентиры: Adelman-Larsen et al., JASA 2010,
залы для поп- и рок-музыки — меньше 1 с, бас не длиннее середины), Desk (маленькие колонки на столе, ближнее поле):
  * пара виртуальных колонок (по умолчанию ±30°, 1,5 м, на высоте ушей 1,2 м; у комнаты могут быть свои места);
  * ранние отражения — метод мнимых источников в прямоугольной комнате (поглощение стен по октавам), направление
    прихода — HRIR датасета FABIAN (ближайшее измеренное направление), задержка — дробная (в частотной области);
  * диффузно-полевая эквализация прямого пути и ранних отражений — инверсной общей передаточной функцией (CTF)
    того же датасета (окраска уха уже учтена профилем наушников AutoEq), затем остаток окраски прямого звука
    колонок ±30° (сигнал в центре, третьоктавное сглаживание) — минимально-фазовым фильтром, одним на все 4 пути
    (разница между ушами и время прихода не меняются);
  * отражения и хвост (всё после прямой части) — срез низа 30 Гц (Баттерворт 4-го порядка): ниже отражения
    складываются в фазе и дали бы огромный инфранизкий подъём, которого у мониторов в комнате нет;
  * прямая часть (для Ambience) — первые DIRECT_N = 128 отсчётов (2,7 мс): до отражения от пола (3,9 мс);
  * поздний хвост — декоррелированный шум по октавам с затуханием по RT60 (между ушами — когерентность диффузного
    поля), стык с ранней частью по плотности энергии;
  * WAV 48 кГц, 24 бит, 4 канала: LL, LR, RL, RR (колонка → ухо: левая → левое, левая → правое, правая → левое,
    правая → правое), пик 0,99; множитель громкости — gain_db в rooms.json.
  * HEAD (отслеживание головы, 8.11): Room*Head.wav — прямая часть (первые DIRECT_N отсчётов, 4 пути) для поворотов
    головы −50…+50° через 2° (вправо +; 51 набор подряд), с той же эквализацией, сдвигом и громкостью, что и импульс
    комнаты (при голове прямо — совпадает с ним). Голова повёрнута относительно корпуса (HATO FABIAN, измерения через
    10°, между ними — линейно по выровненным импульсам), колонки остаются на местах; отражения — те же, что в пределах
    окна прямой части. Своя громкость — head.gain_db в rooms.json.

HRTF — FABIAN head-related transfer function data base, v4 (TU Berlin), CC BY 4.0, DOI 10.14279/depositonce-5718.5
(файл HRIRs_neutral_head_orientation_v4.zip: SOFA/FABIAN_HRIR_measured_HATO_0.sofa и
SOFA/FABIAN_CTF_measured_inverted_smoothed.sofa; для HEAD — ещё FABIAN_HRIR_measured_HATO_{10…50, 310…350}.sofa из
FABIAN_HRTF_DATABASE_v4.zip, папка «1 HRIRs/SOFA»). Ранние версии датасета — CC BY-NC-SA, их не брать.
Лицензии — docs/LICENSES-room.md.

Запуск: pip install numpy scipy sofar
        python3 ios/tools/generate_rooms.py <папка с SOFA-файлами> [--report]
"""
import json
import os
import struct
import sys

import numpy as np
import scipy.signal as sg
import sofar as sf

SR = 48000
C = 343.0
SEED = 20261108
BANDS = np.array([125, 250, 500, 1000, 2000, 4000, 8000], dtype=float)
# Время реверберации по октавам относительно RT60 комнаты (низ длиннее, верх короче); у комнаты может быть своё.
RT_SHAPE = np.array([1.3, 1.15, 1.0, 1.0, 0.92, 0.8, 0.65])
# Клуб: бас не длиннее середины (хорошо оценённые залы, Adelman-Larsen), верх короче (публика, воздух).
RT_CLUB = np.array([1.05, 1.0, 1.0, 1.0, 0.9, 0.75, 0.6])
EAR_DIST = 0.18
SPK_DIST = 1.5
DIRECT_N = 128
# Запас перед прямым звуком (отсчёты): при повороте головы ближнее ухо слышит колонку раньше, чем при голове прямо.
PRE = 8
# HEAD: наборы прямой части по углам поворота головы (вправо +), градусы.
HEAD_FROM = -50
HEAD_STEP = 2
HEAD_COUNT = 51
HATO = [0, 10, 20, 30, 40, 50, -10, -20, -30, -40, -50]
SPK_ANGLE = 30.0
HEIGHT = 1.2

# Места: listener и spk — [x от передней стены, y от левой стены, z от пола], м (без них — колонки ±30° на SPK_DIST).
ROOMS = [
    dict(name="Studio", file="RoomStudio.wav", size=[4.5, 3.5, 2.8], rt60=0.25, early_ms=40.0, tail=True, max_ms=300),
    dict(name="Home", file="RoomHome.wav", size=[5.5, 4.2, 2.6], rt60=0.45, early_ms=60.0, tail=True, max_ms=700, jitter=0.15,
         listener=[3.4, 2.1, 1.1], spk=[[1.4, 0.95, 1.0], [1.4, 3.25, 1.0]]),
    # Салон: водитель слева, динамики низко в передних дверях (левый ближе), сиденья и обивка глушат.
    dict(name="Car", file="RoomCar.wav", size=[2.4, 1.5, 1.15], rt60=0.07, early_ms=30.0, tail=True, max_ms=150, jitter=0.05, refl_ls=(80, -8),
         listener=[1.15, 0.42, 0.85], spk=[[0.75, 0.04, 0.35], [0.75, 1.46, 0.35]]),
    dict(name="Club", file="RoomClub.wav", size=[22.0, 16.0, 7.0], rt60=0.8, early_ms=80.0, tail=True, max_ms=1100,
         shape=RT_CLUB, jitter=0.3, floor=0.35, listener=[11.0, 8.0, 1.6], spk=[[1.0, 4.0, 2.5], [1.0, 12.0, 2.5]]),
    # Маленькие колонки на столе: ±20°, 0,6 м, обычная комната.
    dict(name="Desk", file="RoomDesk.wav", size=[4.0, 3.5, 2.6], rt60=0.4, early_ms=50.0, tail=True, max_ms=600, jitter=0.1,
         listener=[1.3, 1.75, 1.15], spk=[[0.74, 1.545, 1.0], [0.74, 1.955, 1.0]]),
    # Проба (8.11, docs/TRIALS.md): Studio без выравнивания тембра прямого звука и с выравниванием наполовину —
    # признак «спереди» (окраска уха) остаётся; хвост — тот же шум, что у Studio (seed).
    dict(name="StudioRaw", file="RoomStudioRaw.wav", size=[4.5, 3.5, 2.8], rt60=0.25, early_ms=40.0, tail=True, max_ms=300,
         front=0.0, seed=0),
    dict(name="StudioHalf", file="RoomStudioHalf.wav", size=[4.5, 3.5, 2.8], rt60=0.25, early_ms=40.0, tail=True, max_ms=300,
         front=0.5, seed=0),
]


def load_hrtf(folder):
    h = sf.read_sofa(os.path.join(folder, "FABIAN_HRIR_measured_HATO_0.sofa"), verify=False)
    c = sf.read_sofa(os.path.join(folder, "FABIAN_CTF_measured_inverted_smoothed.sofa"), verify=False)
    fs = float(h.Data_SamplingRate)
    up, down = 160, 147  # 44,1 → 48 кГц
    assert abs(fs * up / down - SR) < 1, fs
    ir = sg.resample_poly(np.asarray(h.Data_IR, dtype=float), up, down, axis=-1)
    ctf = sg.resample_poly(np.asarray(c.Data_IR, dtype=float)[0, 0], up, down)
    pos = np.asarray(h.SourcePosition, dtype=float)
    az = np.radians(pos[:, 0])
    el = np.radians(pos[:, 1])
    dirs = np.stack([np.cos(el) * np.cos(az), np.cos(el) * np.sin(az), np.sin(el)], axis=1)
    lic = getattr(h, "GLOBAL_License", "")
    return ir, ctf, dirs, lic


def load_hato(folder):
    """HRIR FABIAN для всех поворотов головы относительно корпуса (HATO, влево +): {угол: массив}. Направления
    источников в файлах — относительно корпуса, общие для всех HATO."""
    sets = {}
    ref = None
    for a in HATO:
        name = "FABIAN_HRIR_measured_HATO_%d.sofa" % (a % 360)
        h = sf.read_sofa(os.path.join(folder, name), verify=False)
        pos = np.asarray(h.SourcePosition, dtype=float)
        if ref is None:
            ref = pos
        assert np.allclose(pos, ref), name
        sets[a] = sg.resample_poly(np.asarray(h.Data_IR, dtype=float), 160, 147, axis=-1)
    return sets


def onset_of(x):
    """Начало HRIR (дробные отсчёты): первый отсчёт выше 20 % пика после повышения частоты в 8 раз."""
    u = sg.resample_poly(x, 8, 1)
    return float(np.argmax(np.abs(u) >= 0.2 * np.max(np.abs(u)))) / 8


class HatoIR:
    """HRIR для поворота головы hato (влево +, ±50°): между измерениями через 10° — линейно по выровненным
    импульсам (начало каждого уха снимается, импульсы смешиваются, начало — тоже линейно); на измеренных углах —
    как есть."""

    def __init__(self, sets, hato):
        self.sets = sets
        a = int(np.floor(hato / 10.0)) * 10
        self.a = max(-50, min(40, a))
        self.t = (hato - self.a) / 10.0
        self.shape = sets[0].shape
        self.cache = {}

    def __getitem__(self, j):
        if j in self.cache:
            return self.cache[j]
        A = self.sets[self.a][j]
        if abs(self.t) < 1e-9:
            out = A
        elif abs(self.t - 1) < 1e-9:
            out = self.sets[self.a + 10][j]
        else:
            B = self.sets[self.a + 10][j]
            n = 2048
            w = 2 * np.pi * np.fft.rfftfreq(n)
            out = np.zeros((2, n))
            for e in range(2):
                ta, tb = onset_of(A[e]), onset_of(B[e])
                fa = np.fft.rfft(A[e], n) * np.exp(1j * w * ta)
                fb = np.fft.rfft(B[e], n) * np.exp(1j * w * tb)
                tt = (1 - self.t) * ta + self.t * tb
                f = ((1 - self.t) * fa + self.t * fb) * np.exp(-1j * w * tt)
                out[e] = np.fft.irfft(f, n)
            out = out[:, :A.shape[-1] + 64]
        self.cache[j] = out
        return out


def head_sets(cfg, sets, ctf, dirs, info):
    """Прямая часть (первые DIRECT_N отсчётов, 4 пути) для поворотов головы HEAD_FROM + HEAD_STEP·i (вправо +) —
    с той же эквализацией, сдвигом и громкостью, что и импульс комнаты. Возвращает (наборы, срезанная доля энергии
    перед началом окна — наибольшая)."""
    nfft, shift, corr = info["nfft"], info["shift"], info["corr"]
    k = info["scale"] / info["norm"]
    out = np.zeros((HEAD_COUNT, 4, DIRECT_N))
    worst = 0.0
    for i in range(HEAD_COUNT):
        yaw = HEAD_FROM + HEAD_STEP * i
        spec, _ = early_part(cfg, HatoIR(sets, -yaw), ctf, dirs, nfft, limit=(shift + DIRECT_N + 256) / SR)
        e = np.fft.irfft(spec * corr[None, :], nfft, axis=-1)
        cut = np.sum(e[:, nfft - 2 * DIRECT_N:] ** 2) + np.sum(e[:, :shift] ** 2)
        worst = max(worst, cut / np.sum(e ** 2))
        out[i] = np.roll(e, -shift, axis=-1)[:, :DIRECT_N] * k
    return out, worst


def sabine_alpha(size, rt60):
    lx, ly, lz = size
    v = lx * ly * lz
    s = 2 * (lx * ly + lx * lz + ly * lz)
    return min(0.95, 0.161 * v / (s * rt60))


def band_curve(values, freqs):
    """Значения по октавам → кривая по частотам (линейно по логарифму частоты, края — постоянные)."""
    lf = np.log2(np.maximum(freqs, 1.0))
    return np.interp(lf, np.log2(BANDS), values)


def images(room, src, lst, max_dist):
    """Мнимые источники: координаты, число отражений и из них — от пола (до расстояния max_dist)."""
    lx, ly, lz = room
    n = int(np.ceil(max_dist / min(room))) + 1
    out = []
    for nx in range(-n, n + 1):
        for px in (0, 1):
            x = 2 * nx * lx + (1 - 2 * px) * src[0]
            kx = abs(2 * nx - px)
            for ny in range(-n, n + 1):
                for py in (0, 1):
                    y = 2 * ny * ly + (1 - 2 * py) * src[1]
                    ky = abs(2 * ny - py)
                    for nz in range(-n, n + 1):
                        for pz in (0, 1):
                            z = 2 * nz * lz + (1 - 2 * pz) * src[2]
                            kz = abs(2 * nz - pz)
                            kf = abs(nz) if pz == 0 or nz > 0 else 1 - nz
                            d = np.linalg.norm(np.array([x, y, z]) - lst)
                            if d <= max_dist:
                                out.append((np.array([x, y, z]), kx + ky + kz, kf))
    return out


def early_part(cfg, ir, ctf, dirs, nfft, limit=None):
    """Прямой звук и ранние отражения для четырёх путей (частотная область, nfft), задержка прямого — 0.
    limit — только пути, пришедшие не позже limit секунд после прямого (для наборов HEAD; случайные сдвиги — те же)."""
    lx, ly, lz = cfg["size"]
    alpha = cfg.get("alpha", sabine_alpha(cfg["size"], cfg["rt60"]))
    # Поглощение по октавам: там, где RT длиннее, — меньше.
    a_b = np.clip(alpha / cfg.get("shape", RT_SHAPE), 0.02, 0.98)
    refl_b = np.sqrt(1 - a_b)
    freqs = np.fft.rfftfreq(nfft, 1 / SR)
    lrefl = np.log(band_curve(refl_b, freqs))
    # Слушатель смотрит на переднюю стену (x = 0): вперёд −x, влево −y, вверх z.
    fwd, left, up = np.array([-1.0, 0, 0]), np.array([0, -1.0, 0]), np.array([0, 0, 1.0])
    lst, spks = places(cfg)
    out = np.zeros((4, freqs.size), dtype=complex)
    dry = np.zeros((4, freqs.size), dtype=complex)
    w = 2 * np.pi * freqs
    # Спектры HRIR — только нужных направлений (все 11 950 при большом nfft не помещаются в память).
    cache = {}

    def hrtf(j):
        if j not in cache:
            cache[j] = np.fft.rfft(ir[j], nfft, axis=-1)
        return cache[j]
    # Отсчёт времени и громкости — от ближней колонки (её прямой звук — 0 dB, задержка 0).
    d0 = min(np.linalg.norm(p - lst) for p in spks)
    max_dist = max(np.linalg.norm(p - lst) for p in spks) + C * cfg["early_ms"] / 1000
    # Рассеяние (неровные стены, мебель, публика): у отражения порядка k случайный сдвиг пути до jitter·√k
    # (randomized image method) — без него зеркальные отражения коробки складываются в гребёнку.
    rng = np.random.default_rng(SEED + 7)
    jit = cfg.get("jitter", 0.0)
    # Пол с публикой (клуб) — отражает слабее стен: множитель на каждое отражение от пола.
    floor = cfg.get("floor", 1.0)
    for s_i, spk in enumerate(spks):  # левая колонка, правая
        for pos, k, kf in images(cfg["size"], spk, lst, max_dist):
            v = pos - lst
            d = np.linalg.norm(v)
            if jit > 0 and k > 0:
                d += rng.uniform(-1, 1) * jit * np.sqrt(k)
            if limit is not None and (d - d0) / C > limit:
                continue
            u = np.array([v @ fwd, v @ left, v @ up]) / d
            j = int(np.argmax(dirs @ u))
            amp = (d0 / d) * np.exp(k * lrefl) * floor ** kf
            ph = np.exp(-1j * w * (d - d0) / C)
            hj = hrtf(j)
            out[2 * s_i + 0] += hj[0] * amp * ph
            out[2 * s_i + 1] += hj[1] * amp * ph
            if k == 0:
                dry[2 * s_i + 0] += hj[0] * amp * ph
                dry[2 * s_i + 1] += hj[1] * amp * ph
    # Диффузно-полевая эквализация (инверсная CTF FABIAN).
    eq = np.fft.rfft(ctf, nfft)[None, :]
    return out * eq, dry * eq


def places(cfg):
    """Слушатель и колонки (левая, правая): свои места комнаты или ±30° на SPK_DIST перед слушателем."""
    if "listener" in cfg:
        return np.array(cfg["listener"], dtype=float), [np.array(p, dtype=float) for p in cfg["spk"]]
    ly = cfg["size"][1]
    fwd, left = np.array([-1.0, 0, 0]), np.array([0, -1.0, 0])
    lst = np.array([0.9 + SPK_DIST * np.cos(np.radians(SPK_ANGLE)), ly / 2, HEIGHT])
    spks = []
    for side in (1.0, -1.0):
        a = np.radians(SPK_ANGLE) * side
        spks.append(lst + SPK_DIST * (np.cos(a) * fwd + np.sin(a) * left))
    return lst, spks


def diffuse_tail(cfg, n, seed):
    """Хвост: 4 канала (LL, LR, RL, RR), когерентность ушей — диффузное поле, затухание по RT60 по октавам."""
    rng = np.random.default_rng(seed)
    t = np.arange(n) / SR
    out = np.zeros((4, n))
    for b, (fc, shape) in enumerate(zip(BANDS, cfg.get("shape", RT_SHAPE))):
        lo, hi = fc / np.sqrt(2), min(fc * np.sqrt(2), SR / 2 * 0.95)
        sos = sg.butter(4, [lo, hi], btype="bandpass", fs=SR, output="sos")
        kd = 2 * np.pi * fc / C * EAR_DIST
        coh = abs(np.sin(kd) / kd)
        env = np.exp(-6.908 * t / (cfg["rt60"] * shape))
        for spk in range(2):
            a = sg.sosfiltfilt(sos, rng.standard_normal(n))
            c = sg.sosfiltfilt(sos, rng.standard_normal(n))
            out[2 * spk + 0] += a * env
            out[2 * spk + 1] += (coh * a + np.sqrt(1 - coh * coh) * c) * env
    return out


def smooth_third(freqs, p):
    """Сглаживание мощности по третям октавы (окно ±1/6 октавы вокруг каждой частоты)."""
    lf = np.log2(np.maximum(freqs, 1.0))
    order = np.argsort(lf)
    cs = np.concatenate([[0], np.cumsum(p[order])])
    lo = np.searchsorted(lf[order], lf - 1 / 6)
    hi = np.searchsorted(lf[order], lf + 1 / 6, side="right")
    return (cs[hi] - cs[lo]) / np.maximum(1, hi - lo)


def min_phase(mag, nfft):
    """Минимально-фазовый спектр по модулю (кепстр)."""
    logm = np.log(np.maximum(mag, 1e-6))
    cep = np.fft.irfft(logm, nfft)
    fold = np.zeros(nfft)
    fold[0] = cep[0]
    fold[1:nfft // 2] = 2 * cep[1:nfft // 2]
    fold[nfft // 2] = cep[nfft // 2]
    return np.exp(np.fft.rfft(fold, nfft))


def front_correction(direct, nfft, strength=1.0):
    """Остаток окраски прямого звука колонок без отражений (сигнал в центре) — обратный, сглаженный, ±12 dB. Только
    прямой звук: отражение от пола в первых миллисекундах (большой зал, салон) — часть пространства, его гребёнку
    не выравниваем (иначе подъём на её провале окрасил бы все отражения)."""
    left, right = ear_responses(direct, nfft)
    freqs = np.fft.rfftfreq(nfft, 1 / SR)
    p = smooth_third(freqs, 0.5 * (np.abs(left) ** 2 + np.abs(right) ** 2))
    band = (freqs >= 100) & (freqs <= 12000)
    ref = np.mean(p[band])
    g = np.sqrt(ref / np.maximum(p, 1e-20))
    g = np.clip(g, 10 ** (-12 / 20), 10 ** (12 / 20))
    # Вне 60 Гц…16 кГц — без коррекции (плавно к 1).
    g = np.where(freqs < 60, 1.0, g)
    g = np.where(freqs > 16000, 1.0, g)
    # Доля выравнивания (проба 8.11): 1 — полностью, 0 — без него (окраска уха FABIAN для колонок спереди остаётся).
    g = g ** strength
    return min_phase(g, nfft)


def make_room(cfg, ir, ctf, dirs, seed):
    n_max = int(SR * cfg["max_ms"] / 1000)
    nfft = 1 << int(np.ceil(np.log2(n_max + ir.shape[-1] + 4096)))
    spec, dspec = early_part(cfg, ir, ctf, dirs, nfft)
    early = np.fft.irfft(spec, nfft, axis=-1)
    dry = np.fft.irfft(dspec, nfft, axis=-1)
    # Начало: прямой звук — на PRE-м отсчёте после самого раннего прихода (общий сдвиг всех путей).
    onset = int(np.argmax(np.max(np.abs(early), axis=0) > 0.05 * np.max(np.abs(early))))
    shift = max(0, onset - PRE)
    early = np.roll(early, -shift, axis=-1)
    dry = np.roll(dry, -shift, axis=-1)
    corr = front_correction(dry, nfft, cfg.get("front", 1.0))
    early = np.fft.irfft(np.fft.rfft(early, nfft, axis=-1) * corr[None, :], nfft, axis=-1)
    t_early = int(SR * cfg["early_ms"] / 1000)
    if cfg["tail"]:
        length = min(n_max, t_early + int(SR * cfg["rt60"] * cfg.get("shape", RT_SHAPE).max() * 1.05))
    else:
        length = min(n_max, t_early + int(SR * 0.012))
    h = early[:, :length].copy()
    # Ранняя часть гаснет к концу окна отражений (последние 10 мс).
    fade = int(SR * 0.010)
    w_out = np.ones(length)
    w_out[t_early - fade:t_early] = 0.5 * (1 + np.cos(np.linspace(0, np.pi, fade)))
    w_out[t_early:] = 0
    h *= w_out[None, :]
    if cfg["tail"]:
        tail = diffuse_tail(cfg, length, seed)
        # Хвост нарастает в те же 10 мс; плотность энергии — как у ранних отражений в последних 15 мс окна.
        w_in = 1 - w_out
        win = slice(t_early - int(SR * 0.025), t_early - fade)
        e_early = np.mean(early[:, win] ** 2)
        e_tail = np.mean(tail[:, win] ** 2)
        tail *= np.sqrt(e_early / max(e_tail, 1e-30))
        h += tail * w_in[None, :]
    # Отражения и хвост: срез низа 30 Гц (прямая часть — без среза); у салона ещё полка вниз на низах — зеркальные
    # отражения тесной коробки складываются в фазе сильнее, чем в настоящей машине (её подъём баса — около +10 dB).
    sos = sg.butter(4, 30, btype="highpass", fs=SR, output="sos")
    rest = h.copy()
    rest[:, :DIRECT_N] = 0
    h[:, DIRECT_N:] = 0
    rest = sg.sosfilt(sos, rest, axis=-1)
    if "refl_ls" in cfg:
        b, a = low_shelf(*cfg["refl_ls"])
        rest = sg.lfilter(b, a, rest, axis=-1)
    h += rest
    # Конец — без обрыва (последние 5 мс).
    end = int(SR * 0.005)
    h[:, -end:] *= np.linspace(1, 0, end)[None, :]
    # Громкость: прямая часть для сигнала в центре — 0 dB в среднем по розовому весу.
    direct = h[:, :DIRECT_N]
    p = mono_power(direct, nfft)
    h /= np.sqrt(p)
    peak = np.max(np.abs(h))
    scale = 0.99 / peak
    info = dict(nfft=nfft, shift=shift, corr=corr, norm=np.sqrt(p), scale=scale)
    return h * scale, -20 * np.log10(scale), length, info


def low_shelf(freq, gain_db, q=0.7071):
    """Полка вниз или вверх на низах (RBJ), коэффициенты b, a."""
    a_ = 10 ** (gain_db / 40)
    w = 2 * np.pi * freq / SR
    alpha = np.sin(w) / (2 * q)
    c = np.cos(w)
    sa = 2 * np.sqrt(a_) * alpha
    b = [a_ * ((a_ + 1) - (a_ - 1) * c + sa), 2 * a_ * ((a_ - 1) - (a_ + 1) * c), a_ * ((a_ + 1) - (a_ - 1) * c - sa)]
    a = [(a_ + 1) + (a_ - 1) * c + sa, -2 * ((a_ - 1) + (a_ + 1) * c), (a_ + 1) + (a_ - 1) * c - sa]
    return np.array(b) / a[0], np.array(a) / a[0]


def ear_responses(h, nfft):
    """Сигнал в центре (L = R): левое ухо — LL + RL, правое — LR + RR."""
    left = np.fft.rfft(h[0] + h[2], nfft)
    right = np.fft.rfft(h[1] + h[3], nfft)
    return left, right


def mono_power(h, nfft):
    """Средняя мощность по 1/12 октавы 20 Гц…20 кГц (розовый вес), как Level compensation приложения."""
    left, right = ear_responses(h, nfft)
    freqs = np.fft.rfftfreq(nfft, 1 / SR)
    pts = 20 * 1000 ** ((np.arange(120) + 0.5) / 120)
    pl = np.interp(pts, freqs, np.abs(left) ** 2)
    pr = np.interp(pts, freqs, np.abs(right) ** 2)
    return float(np.mean(0.5 * (pl + pr)))


def third_octave(h, nfft):
    """АЧХ сигнала в центре по третям октавы 100 Гц…10 кГц (среднее ушей), dB."""
    left, right = ear_responses(h, nfft)
    freqs = np.fft.rfftfreq(nfft, 1 / SR)
    p = 0.5 * (np.abs(left) ** 2 + np.abs(right) ** 2)
    centers = 1000 * 2 ** (np.arange(-10, 11) / 3)
    out = []
    for fc in centers:
        m = (freqs >= fc / 2 ** (1 / 6)) & (freqs < fc * 2 ** (1 / 6))
        out.append(10 * np.log10(np.mean(p[m])))
    return centers, np.array(out)


def write_wav24(path, data):
    """WAV PCM 24 бит, каналы — строки data (4 × кадры)."""
    ch, n = data.shape
    q = np.clip(np.round(data.T * 8388607), -8388608, 8388607).astype(np.int32)
    raw = bytearray()
    for v in q.reshape(-1):
        raw += struct.pack("<i", int(v))[:3]
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 36 + len(raw)) + b"WAVE")
        f.write(b"fmt " + struct.pack("<IHHIIHH", 16, 1, ch, SR, SR * ch * 3, ch * 3, 24))
        f.write(b"data" + struct.pack("<I", len(raw)) + bytes(raw))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    folder = sys.argv[1]
    report = "--report" in sys.argv
    here = os.path.dirname(os.path.abspath(__file__))
    res = os.path.join(here, "..", "JAMbo.swiftpm", "Resources")
    ir, ctf, dirs, lic = load_hrtf(folder)
    print("HRTF:", ir.shape, "license:", lic)
    sets = load_hato(folder)
    meta = []
    for k, cfg in enumerate(ROOMS):
        h, gain_db, length, info = make_room(cfg, ir, ctf, dirs, SEED + cfg.get("seed", k))
        write_wav24(os.path.join(res, cfg["file"]), h)
        # HEAD: прямая часть по углам поворота головы — набор i в кадрах [i·DIRECT_N, (i+1)·DIRECT_N), своя громкость
        # (у ближнего уха при повороте пик выше, чем у импульса комнаты).
        hs, cut = head_sets(cfg, sets, ctf, dirs, info)
        hpeak = float(np.max(np.abs(hs)))
        hscale = 0.99 / max(hpeak, 0.99)
        head_file = cfg["file"].replace(".wav", "Head.wav")
        write_wav24(os.path.join(res, head_file), np.concatenate(list(hs * hscale), axis=-1))
        lst, spks = places(cfg)
        meta.append(dict(name=cfg["name"], file=cfg["file"], rt60=cfg["rt60"], size=cfg["size"],
                         listener=[round(float(v), 3) for v in lst],
                         speakers=[[round(float(v), 3) for v in p] for p in spks], gain_db=round(gain_db, 3),
                         length_ms=round(1000 * length / SR, 1),
                         direct=DIRECT_N, channels="LL, LR, RL, RR",
                         head=dict(file=head_file, from_deg=HEAD_FROM, step_deg=HEAD_STEP, count=HEAD_COUNT,
                                   gain_db=round(gain_db - 20 * np.log10(hscale), 3))))
        print("%s: HEAD %d sets, peak %.3f, cut before window %.1e" % (cfg["name"], HEAD_COUNT, hpeak, cut))
        if report:
            nfft = 1 << 16
            direct = h[:, :DIRECT_N] * 10 ** (gain_db / 20)
            c, db = third_octave(direct, nfft)
            dev = db - np.mean(db)
            print("%s: %.1f ms, gain %.2f dB; direct (Ambience −∞), 1/3 oct 100 Hz…10 kHz: %+.1f…%+.1f dB"
                  % (cfg["name"], 1000 * length / SR, gain_db, dev.min(), dev.max()))
            print("   " + " ".join("%g:%+.1f" % (f, d) for f, d in zip(np.round(c), dev)))
            c2, db2 = third_octave(h * 10 ** (gain_db / 20), nfft)
            print("   full IR:  " + " ".join("%g:%+.1f" % (f, d) for f, d in zip(np.round(c2), db2 - np.mean(db2))))
    with open(os.path.join(res, "rooms.json"), "w") as f:
        json.dump(dict(rooms=meta, hrtf="FABIAN HRTF data base v4, TU Berlin, CC BY 4.0, DOI 10.14279/depositonce-5718.5"),
                  f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("written:", [m["file"] for m in meta])


if __name__ == "__main__":
    main()
