#!/usr/bin/env python3
"""Генератор бинауральных импульсов комнат для Room (Headphone Monitor, фаза 2).

Воспроизводимо (фиксированный seed) создаёт ios/JAMbo.swiftpm/Resources/Room*.wav и rooms.json:
  * пара виртуальных колонок на ±30°, 1,5 м, уши и колонки на высоте 1,2 м;
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

HRTF — FABIAN head-related transfer function data base, v4 (TU Berlin), CC BY 4.0, DOI 10.14279/depositonce-5718.5
(файл HRIRs_neutral_head_orientation_v4.zip: SOFA/FABIAN_HRIR_measured_HATO_0.sofa и
SOFA/FABIAN_CTF_measured_inverted_smoothed.sofa). Ранние версии датасета — CC BY-NC-SA, их не брать.
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
MAX_MS = 300
BANDS = np.array([125, 250, 500, 1000, 2000, 4000, 8000], dtype=float)
# Время реверберации по октавам относительно RT60 комнаты (низ длиннее, верх короче).
RT_SHAPE = np.array([1.3, 1.15, 1.0, 1.0, 0.92, 0.8, 0.65])
EAR_DIST = 0.18
SPK_DIST = 1.5
DIRECT_N = 128
SPK_ANGLE = 30.0
HEIGHT = 1.2

ROOMS = [
    dict(name="Control Room", file="RoomControl.wav", size=[4.5, 3.5, 2.8], rt60=0.25, early_ms=40.0, tail=True),
    dict(name="Small Studio", file="RoomStudio.wav", size=[5.0, 4.0, 2.6], rt60=0.35, early_ms=50.0, tail=True),
    dict(name="Dry", file="RoomDry.wav", size=[4.5, 3.5, 2.8], rt60=0.10, early_ms=14.0, tail=False, alpha=0.85),
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
    """Мнимые источники: координаты и число отражений (до расстояния max_dist)."""
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
                            d = np.linalg.norm(np.array([x, y, z]) - lst)
                            if d <= max_dist:
                                out.append((np.array([x, y, z]), kx + ky + kz))
    return out


def early_part(cfg, ir, ctf, dirs, nfft):
    """Прямой звук и ранние отражения для четырёх путей (частотная область, nfft), задержка прямого — 0."""
    lx, ly, lz = cfg["size"]
    alpha = cfg.get("alpha", sabine_alpha(cfg["size"], cfg["rt60"]))
    # Поглощение по октавам: там, где RT длиннее, — меньше.
    a_b = np.clip(alpha / RT_SHAPE, 0.02, 0.98)
    refl_b = np.sqrt(1 - a_b)
    freqs = np.fft.rfftfreq(nfft, 1 / SR)
    lrefl = np.log(band_curve(refl_b, freqs))
    # Слушатель смотрит на переднюю стену (x = 0): вперёд −x, влево −y, вверх z.
    fwd, left, up = np.array([-1.0, 0, 0]), np.array([0, -1.0, 0]), np.array([0, 0, 1.0])
    lst = np.array([0.9 + SPK_DIST * np.cos(np.radians(SPK_ANGLE)), ly / 2, HEIGHT])
    out = np.zeros((4, freqs.size), dtype=complex)
    w = 2 * np.pi * freqs
    hr = np.fft.rfft(ir, nfft, axis=-1)
    max_dist = SPK_DIST + C * cfg["early_ms"] / 1000
    for s_i, side in enumerate((1.0, -1.0)):  # левая колонка (+30°), правая (−30°)
        a = np.radians(SPK_ANGLE) * side
        spk = lst + SPK_DIST * (np.cos(a) * fwd + np.sin(a) * left)
        for pos, k in images(cfg["size"], spk, lst, max_dist):
            v = pos - lst
            d = np.linalg.norm(v)
            u = np.array([v @ fwd, v @ left, v @ up]) / d
            j = int(np.argmax(dirs @ u))
            amp = (SPK_DIST / d) * np.exp(k * lrefl)
            ph = np.exp(-1j * w * (d - SPK_DIST) / C)
            out[2 * s_i + 0] += hr[j, 0] * amp * ph
            out[2 * s_i + 1] += hr[j, 1] * amp * ph
    # Диффузно-полевая эквализация (инверсная CTF FABIAN).
    out *= np.fft.rfft(ctf, nfft)[None, :]
    return out


def diffuse_tail(cfg, n, seed):
    """Хвост: 4 канала (LL, LR, RL, RR), когерентность ушей — диффузное поле, затухание по RT60 по октавам."""
    rng = np.random.default_rng(seed)
    t = np.arange(n) / SR
    out = np.zeros((4, n))
    for b, (fc, shape) in enumerate(zip(BANDS, RT_SHAPE)):
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


def front_correction(early, nfft):
    """Остаток окраски прямого звука (сигнал в центре, первые DIRECT_N отсчётов) — обратный, сглаженный, ±12 dB."""
    direct = np.zeros_like(early)
    direct[:, :DIRECT_N] = early[:, :DIRECT_N]
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
    return min_phase(g, nfft)


def make_room(cfg, ir, ctf, dirs, seed):
    n_max = int(SR * MAX_MS / 1000)
    nfft = 1 << int(np.ceil(np.log2(n_max + ir.shape[-1] + 4096)))
    spec = early_part(cfg, ir, ctf, dirs, nfft)
    early = np.fft.irfft(spec, nfft, axis=-1)
    # Начало: прямой звук — на 8-м отсчёте после самого раннего прихода (общий сдвиг всех путей).
    onset = int(np.argmax(np.max(np.abs(early), axis=0) > 0.05 * np.max(np.abs(early))))
    shift = max(0, onset - 8)
    early = np.roll(early, -shift, axis=-1)
    corr = front_correction(early, nfft)
    early = np.fft.irfft(np.fft.rfft(early, nfft, axis=-1) * corr[None, :], nfft, axis=-1)
    t_early = int(SR * cfg["early_ms"] / 1000)
    if cfg["tail"]:
        length = min(n_max, t_early + int(SR * cfg["rt60"] * RT_SHAPE.max() * 1.05))
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
    # Отражения и хвост: срез низа 30 Гц (прямая часть — без среза).
    sos = sg.butter(4, 30, btype="highpass", fs=SR, output="sos")
    rest = h.copy()
    rest[:, :DIRECT_N] = 0
    h[:, DIRECT_N:] = 0
    h += sg.sosfilt(sos, rest, axis=-1)
    # Конец — без обрыва (последние 5 мс).
    end = int(SR * 0.005)
    h[:, -end:] *= np.linspace(1, 0, end)[None, :]
    # Громкость: прямая часть для сигнала в центре — 0 dB в среднем по розовому весу.
    direct = h[:, :DIRECT_N]
    p = mono_power(direct, nfft)
    h /= np.sqrt(p)
    peak = np.max(np.abs(h))
    scale = 0.99 / peak
    return h * scale, -20 * np.log10(scale), length


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
    meta = []
    for k, cfg in enumerate(ROOMS):
        h, gain_db, length = make_room(cfg, ir, ctf, dirs, SEED + k)
        write_wav24(os.path.join(res, cfg["file"]), h)
        meta.append(dict(name=cfg["name"], file=cfg["file"], rt60=cfg["rt60"], size=cfg["size"],
                         angle=SPK_ANGLE, distance=SPK_DIST, gain_db=round(gain_db, 3),
                         length_ms=round(1000 * length / SR, 1),
                         direct=DIRECT_N, channels="LL, LR, RL, RR"))
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
