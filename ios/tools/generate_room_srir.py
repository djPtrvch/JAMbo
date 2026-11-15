#!/usr/bin/env python3
"""Бинауральные импульсы комнат по замерам реальных комнат (SRIR) — для меню SPACE, рядом с моделями generate_rooms.py.

Замер — сферический массив (SRIR, без головы): пространственный импульс каждой колонки в точке слушателя. По нему —
направление прихода звука в каждый момент (SDM, Tervo et al., JAES 2013; направление — вектор псевдоинтенсивности
по сферическим гармоникам 0 и 1 порядка) и давление; каждый отсчёт давления идёт в уши через HRIR головы с этого
направления (FABIAN, как в generate_rooms.py; потом — персональный HRTF). Голова не из замера, поэтому её можно менять.

  * массив — жёсткая сфера (WDR: VariSphear, Лебедев 110 точек, радиус 8,75 см): разложение по гармоникам до 8
    порядка (наименьшие квадраты), радиальные фильтры жёсткой сферы; давление до ~7 кГц — гармоника 0 порядка
    (точно для любого направления), выше — ближайший к направлению прихода микрофон, выровненный по отклику жёсткой
    сферы на оси: у 110 точек гармоника 0 выше 8 кГц искажается наложением (до +20 dB);
  * направление: полоса 200 Гц…6 кГц, окно 0,67 мс; прямой звук (первые 1,5 мс) — геометрическое направление колонки
    из метаданных замера;
  * ранняя часть (до early_ms) — SDM; поздний хвост — декоррелированный шум (когерентность ушей диффузного поля) по
    октавам с измеренным затуханием (EDC по средней мощности микрофонов, наклон −5…−25 dB) и уровнем стыка; ниже
    200 Гц хвост — само измеренное давление (моды комнаты), в оба уха;
  * дальше — как generate_rooms.py: инверсная CTF FABIAN (диффузно-полевая эквализация), выравнивание прямого звука
    (front 0 — как есть, 1 — выровненный вариант Flat), громкость прямой части 0 dB, наборы HEAD (прямая часть через
    HRIR повёрнутой головы, HATO), WAV 48 кГц 24/16 бит, 4 канала LL, LR, RL, RR. Срез низа колонок — в замере
    (speaker hp 0).

Замеры — "A Spatial Audio Impulse Response Compilation Captured at the WDR Broadcast Studios" (TH Köln), Zenodo
10.5281/zenodo.3930833, CC BY 4.0 (в метаданных SOFA — CC BY-SA 3.0, лицензия 2012 г.; docs/LICENSES-room.md):
DRIR_CR1_VSA_110RS_L.sofa и _R.sofa — Control Room 1 (93 м³, мониторы Genelec 8260 ±36° на 2,44 м),
DRIR_CR7_VSA_110RS_L.sofa и _R.sofa — Control Room 7 (168 м³).
Записи комнат дописываются в rooms.json (generate_rooms.py их сохраняет: "source": "srir").

Запуск: pip install numpy scipy sofar
        python3 ios/tools/generate_room_srir.py <папка SOFA FABIAN> <папка SOFA замеров> [--report]
"""
import json
import os
import sys
import warnings

import numpy as np
import scipy.signal as sg
import scipy.special as spc
import sofar as sf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_rooms as G  # noqa: E402

SR = G.SR
C = G.C
SEED = 20261115
SH_N = 8
# Давление: гармоника 0 до XO_LO…XO_HI (переход cos²), выше — ближайший к направлению прихода микрофон.
XO_LO, XO_HI = 6000.0, 8000.0
# Угол ближайшего микрофона, по отклику на котором выравнивается верх (у 110 точек — 0…13°).
NEAR_DEG = 8.0
# Направление прихода: полоса и окно сглаживания (отсчёты).
DOA_LO, DOA_HI = 200.0, 6000.0
DOA_WIN = 32
DIRECT_MS = 1.5
# Хвост: ниже TAIL_XO — измеренное давление, выше — шум по октавам.
TAIL_XO = 200.0
TAIL_BANDS = np.array([250, 500, 1000, 2000, 4000, 8000, 16000], dtype=float)

ROOMS = [
    # Studio Real: WDR Control Room 1 (классическая музыка, Lawo mc²82, хорошо оценена звукорежиссёрами WDR).
    dict(name="StudioReal", file="RoomStudioReal.wav", sofa=("DRIR_CR1_VSA_110RS_L.sofa", "DRIR_CR1_VSA_110RS_R.sofa"),
         early_ms=50.0, max_ms=450, desc="WDR Control Room 1 (TH Köln WDR compilation, CC BY 4.0)"),
    # Studio CR7: WDR Control Room 7 (радиоспектакли; 168 м³, RT ≈ 0,4 с, перепады высот; колонки по метаданным —
    # +30° на 2,65 м и −25° на 3,11 м, как стояли в замере). Проба 15.11 — для сравнения с CR1.
    dict(name="StudioCR7", file="RoomStudioCR7.wav", sofa=("DRIR_CR7_VSA_110RS_L.sofa", "DRIR_CR7_VSA_110RS_R.sofa"),
         early_ms=60.0, max_ms=650, desc="WDR Control Room 7 (TH Köln WDR compilation, CC BY 4.0)"),
]


def real_sh(n_max, az, col):
    """Действительные сферические гармоники до порядка n_max (ACN): [точка][гармоника]; m = 1 — x, −1 — y, 0 — z."""
    out = []
    for n in range(n_max + 1):
        for m in range(-n, n + 1):
            y = spc.sph_harm_y(n, abs(m), col, az)
            if m == 0:
                out.append(y.real)
            elif m > 0:
                out.append(np.sqrt(2) * (-1) ** m * y.real)
            else:
                out.append(np.sqrt(2) * (-1) ** m * y.imag)
    return np.array(out).T


def rigid_bn(n, kr):
    """Радиальная функция жёсткой сферы (плоская волна единичной амплитуды). Знак времени — как у numpy.fft
    (e^{+iωt}): уходящая волна — функция Ганкеля второго рода."""
    j = spc.spherical_jn(n, kr)
    jd = spc.spherical_jn(n, kr, True)
    h = j - 1j * spc.spherical_yn(n, kr)
    hd = jd - 1j * spc.spherical_yn(n, kr, True)
    return 4 * np.pi * (1j ** n) * (j - jd / hd * h)


def sphere_response(cos_t, kr, n_max=60):
    """Давление на жёсткой сфере для плоской волны под углом (cos_t) к нормали микрофона: [частота][угол]."""
    p = np.zeros((kr.size, np.size(cos_t)), dtype=complex)
    for n in range(n_max):
        p += ((2 * n + 1) / (4 * np.pi) * rigid_bn(n, kr))[:, None] * spc.eval_legendre(n, np.atleast_1d(cos_t))[None, :]
    return p


def xover(freqs, lo, hi):
    """Нижняя ветвь перехода cos² (нулевая фаза), верхняя — 1 − она: в сумме ровно 1."""
    t = np.clip((freqs - lo) / (hi - lo), 0, 1)
    return np.cos(0.5 * np.pi * t) ** 2


class Speaker:
    """Замер одной колонки: давление и направление прихода по отсчётам (система слушателя: x вперёд, y влево, z вверх)."""

    def __init__(self, path):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            s = sf.read_sofa(path, verify=False)
        assert float(s.Data_SamplingRate) == SR
        self.lic = getattr(s, "GLOBAL_License", "")
        self.room = getattr(s, "GLOBAL_RoomDescription", "")
        self.spk = getattr(s, "GLOBAL_SourceDescription", "")
        x = np.asarray(s.Data_IR, dtype=float)[0]
        rp = np.asarray(s.ReceiverPosition, dtype=float)[:, :, 0]
        r = float(rp[0, 2])
        az, el = np.radians(rp[:, 0]), np.radians(rp[:, 1])
        mics = np.stack([np.cos(el) * np.cos(az), np.cos(el) * np.sin(az), np.sin(el)], axis=1)
        src = np.asarray(s.SourcePosition, dtype=float)[0]
        self.src = src / np.linalg.norm(src)
        self.dist = float(np.linalg.norm(src))
        n = x.shape[1]
        nfft = 1 << int(np.ceil(np.log2(n + 1024)))
        freqs = np.fft.rfftfreq(nfft, 1 / SR)
        kr = 2 * np.pi * np.maximum(freqs, 1.0) / C * r
        X = np.fft.rfft(x, nfft, axis=-1)
        P = np.linalg.pinv(real_sh(SH_N, az, np.pi / 2 - el)) @ X
        b0, b1 = rigid_bn(0, kr), rigid_bn(1, kr)
        a00 = P[0] / b0 * np.sqrt(4 * np.pi)          # давление в центре (плоская волна → 1)
        a1 = P[1:4] / b1[None, :] * np.sqrt(4 * np.pi / 3)  # (y, z, x) — направление прихода
        lo = xover(freqs, XO_LO, XO_HI)
        p_lo = np.fft.irfft(a00 * lo, nfft)[:n]
        band = (1 - xover(freqs, DOA_LO * 0.7, DOA_LO)) * xover(freqs, DOA_HI, DOA_HI * 1.4)
        w = np.fft.irfft(a00 * band, nfft)[:n]
        v = np.fft.irfft(a1 * band[None, :], nfft, axis=-1)[:, :n]
        win = np.hanning(DOA_WIN + 2)[1:-1]
        inten = np.stack([sg.fftconvolve(w * v[k], win, mode="same") for k in (2, 0, 1)])  # x, y, z
        doa = inten / np.maximum(np.linalg.norm(inten, axis=0), 1e-30)
        # Начало прямого звука; первые DIRECT_MS — геометрическое направление колонки.
        self.onset = int(np.argmax(np.abs(p_lo) >= 0.2 * np.max(np.abs(p_lo))))
        d_end = self.onset + int(SR * DIRECT_MS / 1000)
        self.doa_err = float(np.degrees(np.arccos(np.clip(np.mean(doa[:, self.onset:d_end], axis=1)
                                                          @ self.src / np.linalg.norm(np.mean(doa[:, self.onset:d_end], axis=1)), -1, 1))))
        doa[:, :d_end] = self.src[:, None]
        # Верх давления: ближайший к направлению прихода микрофон (у 110 точек — не дальше ~13°), выровненный по отклику
        # жёсткой сферы на оси (в пределах 13° отклик почти тот же). Среднее нескольких микрофонов не годится: они слышат
        # звук в разное время, и верх гасится.
        hax = sphere_response(np.array([np.cos(np.radians(NEAR_DEG))]), kr)[:, 0]
        hi_f = (1 - lo) / np.abs(hax)
        x_hi = np.fft.irfft(X * hi_f[None, :], nfft, axis=-1)[:, :n]
        near = np.argmax(mics @ doa, axis=0)
        p_hi = x_hi[near, np.arange(n)]
        self.p = p_lo + p_hi
        self.doa = doa
        # Для хвоста: давление ниже TAIL_XO (гармоника 0, точно) и средняя мощность микрофонов по октавам, выровненная
        # по диффузному отклику жёсткой сферы.
        self.p_low = np.fft.irfft(a00 * xover(freqs, TAIL_XO, TAIL_XO * 1.5), nfft)[:n]
        cs = np.linspace(-1, 1, 201)
        diff = np.mean(np.abs(sphere_response(cs, kr)) ** 2, axis=1)
        self.band_env = []
        for fc in TAIL_BANDS:
            lo_b, hi_b = fc / np.sqrt(2), min(fc * np.sqrt(2), SR / 2 * 0.95)
            m = (freqs >= lo_b) & (freqs < hi_b)
            g = np.zeros(freqs.size)
            g[m] = 1 / np.sqrt(diff[m])
            xb = np.fft.irfft(X * g[None, :], nfft, axis=-1)[:, :n]
            self.band_env.append(np.mean(xb ** 2, axis=0))
        self.n = n


def sdm_render(p, doa, hrir, dirs, t_from, t_to, n_out):
    """SDM: отсчёты давления p[t_from:t_to] — в уши через HRIR своего направления (ближайшее измеренное). hrir — HRIR по
    индексу направления (массив или HatoIR: [ухо][отсчёт]). Выход — [ухо][n_out]."""
    out = np.zeros((2, n_out))
    idx = np.argmax(dirs @ doa[:, t_from:t_to], axis=0)
    for t, j in zip(range(t_from, t_to), idx):
        a = p[t]
        if a == 0.0:
            continue
        h = hrir[int(j)]
        k = min(h.shape[-1], n_out - t)
        if k > 0:
            out[:, t:t + k] += a * h[:, :k]
    return out


def edc_rt(env, t0, t_end):
    """Время реверберации по кривой Шрёдера (−5…−25 dB) от t0 до t_end; мало точек — None."""
    e = env[t0:t_end]
    edc = np.cumsum(e[::-1])[::-1]
    edc = 10 * np.log10(np.maximum(edc / edc[0], 1e-30))
    i5, i25 = np.argmax(edc <= -5), np.argmax(edc <= -25)
    if i25 <= i5 + 10:
        return None
    t = np.arange(i5, i25) / SR
    slope = np.polyfit(t, edc[i5:i25], 1)[0]
    return -60.0 / slope


def tail_noise(spk, length, t_early, rng, info):
    """Хвост колонки (2 уха): выше TAIL_XO — шум по октавам с измеренным RT и уровнем на стыке (t_early), между ушами —
    когерентность диффузного поля; ниже — измеренное давление (одно на оба уха)."""
    t = np.arange(length) / SR
    out = np.zeros((2, length))
    win = slice(t_early - int(SR * 0.025), t_early - int(SR * 0.010))
    rts = []
    for b, fc in enumerate(TAIL_BANDS):
        env = spk.band_env[b]
        noise_floor = np.mean(env[-int(SR * 0.05):])
        above = np.where(sg.fftconvolve(env, np.ones(480) / 480, mode="same") > noise_floor * 10)[0]
        t_end = int(above[-1]) if above.size else spk.n
        rt = edc_rt(env, spk.onset + int(SR * 0.010), t_end) or 0.2
        rts.append(rt)
        lo, hi = fc / np.sqrt(2), min(fc * np.sqrt(2), SR / 2 * 0.95)
        sos = sg.butter(4, [lo, hi], btype="bandpass", fs=SR, output="sos")
        kd = 2 * np.pi * fc / C * G.EAR_DIST
        coh = abs(np.sin(kd) / kd)
        a = sg.sosfiltfilt(sos, rng.standard_normal(length))
        c = sg.sosfiltfilt(sos, rng.standard_normal(length))
        # Уровень полосы на стыке — средняя мощность микрофонов в окне стыка, дальше — экспонента по измеренному RT.
        lvl = np.mean(env[spk.onset + win.start - info["pre"]: spk.onset + win.stop - info["pre"]])
        tw = (np.arange(win.start, win.stop)).mean() / SR
        envelope = np.sqrt(lvl) * np.exp(-6.908 * (t - tw) / rt)
        na = np.mean(a[win] ** 2)
        out[0] += a / np.sqrt(na) * envelope
        out[1] += (coh * a + np.sqrt(1 - coh * coh) * c) / np.sqrt(na) * envelope
    return out, rts


def make_room(cfg, spks, ir, dirs, ctf, sets, front):
    """Импульс комнаты (4 × length), громкость, длина, данные для HEAD; как generate_rooms.make_room."""
    hl = ir.shape[-1]
    onset = min(s.onset for s in spks)
    pre = G.PRE + 4  # запас: начало HRIR и колонки
    t0 = max(0, onset - pre)  # отсчёт замера, который станет нулём
    n_max = int(SR * cfg["max_ms"] / 1000)
    t_early = int(SR * cfg["early_ms"] / 1000)
    nfft = 1 << int(np.ceil(np.log2(n_max + hl + 4096)))
    eq = np.fft.rfft(ctf, nfft)
    rng = np.random.default_rng(SEED)
    rt_max = 0.0
    early = np.zeros((4, n_max))
    dry = np.zeros((4, n_max))
    tails = []
    info = dict(pre=pre)
    for s_i, s in enumerate(spks):
        p = np.zeros(s.n)
        p[t0:] = s.p[t0:]
        e = sdm_render(p, s.doa, ir, dirs, t0, min(s.n, t0 + t_early + hl), t0 + n_max)[:, t0:]
        d_end = s.onset + int(SR * DIRECT_MS / 1000) + 32
        dd = sdm_render(p, s.doa, ir, dirs, t0, d_end, t0 + n_max)[:, t0:]
        early[2 * s_i:2 * s_i + 2] = e[:, :n_max]
        dry[2 * s_i:2 * s_i + 2] = dd[:, :n_max]
    early = np.fft.irfft(np.fft.rfft(early, nfft, axis=-1) * eq[None, :], nfft, axis=-1)
    dry = np.fft.irfft(np.fft.rfft(dry, nfft, axis=-1) * eq[None, :], nfft, axis=-1)
    on = int(np.argmax(np.max(np.abs(early), axis=0) > 0.05 * np.max(np.abs(early))))
    shift = max(0, on - G.PRE)
    early = np.roll(early, -shift, axis=-1)
    dry = np.roll(dry, -shift, axis=-1)
    info["pre"] = pre - shift  # отсчёт замера onset → G.PRE + (onset - t0 - pre)
    corr = G.front_correction(dry, nfft, front)
    early = np.fft.irfft(np.fft.rfft(early, nfft, axis=-1) * corr[None, :], nfft, axis=-1)
    for s_i, s in enumerate(spks):
        tail, rts = tail_noise(s, n_max, t_early, rng, dict(pre=s.onset - t0 - shift))
        rt_max = max(rt_max, max(rts))
        tails.append((tail, rts))
    length = min(n_max, t_early + int(SR * rt_max * 1.05))
    h = early[:, :length].copy()
    fade = int(SR * 0.010)
    w_out = np.ones(length)
    w_out[t_early - fade:t_early] = 0.5 * (1 + np.cos(np.linspace(0, np.pi, fade)))
    w_out[t_early:] = 0
    w_in = 1 - w_out
    h *= w_out[None, :]
    win = slice(t_early - int(SR * 0.025), t_early - fade)
    report = []
    for s_i, s in enumerate(spks):
        tail, rts = tails[s_i]
        tail = tail[:, :length]
        # Уровень шума — по уровню ранней части в окне стыка, по октавам (SDM и шум в одной шкале — ухо FABIAN).
        for b, fc in enumerate(TAIL_BANDS):
            lo, hi = fc / np.sqrt(2), min(fc * np.sqrt(2), SR / 2 * 0.95)
            sos = sg.butter(4, [lo, hi], btype="bandpass", fs=SR, output="sos")
            eb = np.mean(sg.sosfiltfilt(sos, early[2 * s_i:2 * s_i + 2, :length], axis=-1)[:, win] ** 2)
            tb = sg.sosfiltfilt(sos, tail, axis=-1)
            nb = np.mean(tb[:, win] ** 2)
            tail_b = tb * np.sqrt(eb / max(nb, 1e-30))
            if b == 0:
                acc = tail_b
            else:
                acc = acc + tail_b
        # Низ хвоста — измеренное давление (сдвинутое так же), уровень — как у ранней части ниже TAIL_XO.
        pl = np.zeros(length)
        src = s.p_low[t0 + shift:t0 + shift + length]
        pl[:src.size] = src
        sos_l = sg.butter(4, TAIL_XO, btype="lowpass", fs=SR, output="sos")
        el = np.mean(sg.sosfiltfilt(sos_l, early[2 * s_i:2 * s_i + 2, :length], axis=-1)[:, win] ** 2)
        plf = sg.sosfiltfilt(sos_l, pl)
        g_lf = np.sqrt(el / max(np.mean(plf[win] ** 2), 1e-30))
        sos_h = sg.butter(4, TAIL_XO, btype="highpass", fs=SR, output="sos")
        acc = sg.sosfiltfilt(sos_h, acc, axis=-1) + plf[None, :] * g_lf
        h[2 * s_i:2 * s_i + 2] += acc * w_in[None, :]
        report.append(rts)
    # Самый низ (< 20 Гц) — прочь: шум замера и постоянная составляющая.
    sos = sg.butter(2, 20, btype="highpass", fs=SR, output="sos")
    rest = h.copy()
    rest[:, :G.DIRECT_N] = 0
    h[:, G.DIRECT_N:] = 0
    h += sg.sosfilt(sos, rest, axis=-1)
    end = int(SR * 0.005)
    h[:, -end:] *= np.linspace(1, 0, end)[None, :]
    p = G.mono_power(h[:, :G.DIRECT_N], nfft)
    h /= np.sqrt(p)
    scale = 0.99 / np.max(np.abs(h))
    info = dict(nfft=nfft, shift=shift, t0=t0, corr=corr, norm=np.sqrt(p), scale=scale, eq=eq, rts=report)
    return h * scale, -20 * np.log10(scale), length, info


def head_sets(cfg, spks, sets, dirs, info):
    """HEAD: прямая часть (DIRECT_N, 4 пути) через HRIR повёрнутой головы — та же эквализация, сдвиг и громкость."""
    nfft, shift, t0, corr, eq = info["nfft"], info["shift"], info["t0"], info["corr"], info["eq"]
    k = info["scale"] / info["norm"]
    n_win = shift + G.DIRECT_N
    out = np.zeros((G.HEAD_COUNT, 4, G.DIRECT_N))
    for i in range(G.HEAD_COUNT):
        yaw = G.HEAD_FROM + G.HEAD_STEP * i
        hrir = G.HatoIR(sets, -yaw)
        e = np.zeros((4, nfft))
        for s_i, s in enumerate(spks):
            p = np.zeros(s.n)
            p[t0:] = s.p[t0:]
            r = sdm_render(p, s.doa, hrir, dirs, t0, min(s.n, t0 + n_win), t0 + n_win + 512)[:, t0:]
            e[2 * s_i:2 * s_i + 2, :r.shape[1]] = r
        e = np.fft.irfft(np.fft.rfft(e, nfft, axis=-1) * (eq * corr)[None, :], nfft, axis=-1)
        out[i] = np.roll(e, -shift, axis=-1)[:, :G.DIRECT_N] * k
    return out


def write_head(cfg, spks, sets, dirs, info, gain_db, file, res):
    hs = head_sets(cfg, spks, sets, dirs, info)
    hscale = 0.99 / max(float(np.max(np.abs(hs))), 0.99)
    head_file = file.replace(".wav", "Head.wav")
    G.write_wav(os.path.join(res, head_file), np.concatenate(list(hs * hscale), axis=-1), 16)
    return head_file, round(gain_db - 20 * np.log10(hscale), 3), hs


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    fab, meas = sys.argv[1], sys.argv[2]
    report = "--report" in sys.argv
    here = os.path.dirname(os.path.abspath(__file__))
    res = os.path.join(here, "..", "JAMbo.swiftpm", "Resources")
    ir, ctf, dirs, lic = G.load_hrtf(fab)
    sets = G.load_hato(fab)
    print("HRTF:", ir.shape, "license:", lic)
    meta = []
    for cfg in ROOMS:
        spks = [Speaker(os.path.join(meas, f)) for f in cfg["sofa"]]
        for s, f in zip(spks, cfg["sofa"]):
            az = np.degrees(np.arctan2(s.src[1], s.src[0]))
            peak = 20 * np.log10(np.max(np.abs(s.p[s.onset - 16:s.onset + 64])))
            print("%s: %s, %s, az %.1f°, %.2f m, onset %d, direct peak %.1f dB, DOA error (direct) %.1f°, license: %s"
                  % (f, s.room, s.spk, az, s.dist, s.onset, peak, s.doa_err, s.lic))
        h, gain_db, length, info = make_room(cfg, spks, ir, dirs, ctf, sets, G.FRONT)
        G.write_wav(os.path.join(res, cfg["file"]), h)
        head_file, head_gain, hs = write_head(cfg, spks, sets, dirs, info, gain_db, cfg["file"], res)
        # Совпадение HEAD при голове прямо с импульсом комнаты.
        i0 = (0 - G.HEAD_FROM) // G.HEAD_STEP
        dev = np.max(np.abs(hs[i0] - h[:, :G.DIRECT_N])) / np.max(np.abs(h[:, :G.DIRECT_N]))
        hf, flat_gain, _, finfo = make_room(cfg, spks, ir, dirs, ctf, sets, 1.0)
        flat_file = cfg["file"].replace(".wav", "Flat.wav")
        G.write_wav(os.path.join(res, flat_file), hf[:, :int(SR * cfg["early_ms"] / 1000)], 16)
        flat_head, flat_head_gain, _ = write_head(cfg, spks, sets, dirs, finfo, flat_gain, flat_file, res)
        meta.append(dict(name=cfg["name"], file=cfg["file"], source="srir", measurement=cfg["desc"],
                         rt60=round(float(np.median([np.median(r) for r in info["rts"]])), 3),
                         gain_db=round(gain_db, 3), length_ms=round(1000 * length / SR, 1), direct=G.DIRECT_N,
                         channels="LL, LR, RL, RR", speaker=dict(hp_hz=0, hp_order=0, ft_hz=0),
                         head=dict(file=head_file, from_deg=G.HEAD_FROM, step_deg=G.HEAD_STEP, count=G.HEAD_COUNT,
                                   gain_db=head_gain),
                         flat=dict(file=flat_file, gain_db=round(flat_gain, 3), head_file=flat_head,
                                   head_gain_db=flat_head_gain)))
        print("%s: %.1f ms, gain %.2f dB, RT по октавам %s; HEAD при 0° — отличие %.1e"
              % (cfg["name"], 1000 * length / SR, gain_db,
                 " ".join("%g:%.2f" % (f, r) for f, r in zip(TAIL_BANDS, np.mean(info["rts"], axis=0))), dev))
        if report:
            nf = 1 << 16
            c, db = G.third_octave(h[:, :G.DIRECT_N] * 10 ** (gain_db / 20), nf)
            print("   direct:  " + " ".join("%g:%+.1f" % (f, d) for f, d in zip(np.round(c), db - np.mean(db))))
            c2, db2 = G.third_octave(h * 10 ** (gain_db / 20), nf)
            print("   full IR: " + " ".join("%g:%+.1f" % (f, d) for f, d in zip(np.round(c2), db2 - np.mean(db2))))
    path = os.path.join(res, "rooms.json")
    with open(path) as f:
        data = json.load(f)
    names = {m["name"] for m in meta}
    data["rooms"] = [r for r in data["rooms"] if r["name"] not in names] + meta
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("written:", [m["file"] for m in meta])


if __name__ == "__main__":
    main()
