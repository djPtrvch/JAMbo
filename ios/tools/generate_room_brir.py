#!/usr/bin/env python3
"""Импульсы комнат меню SPACE из готовых бинауральных замеров (BRIR, голова-манекен) — для сравнения голов: та же
комната, что у generate_room_srir.py (уши FABIAN по замеру массивом), но с ушами манекена из самого замера.

Замер — BRIR манекена Neumann KU100 на поворотном столе: 360 поворотов головы через 1° (WDR: ListenerView, влево +),
2 уха, каждая колонка — свой файл. Отсюда:
  * 4 пути (LL, LR, RL, RR) — голова прямо (поворот 0°), как есть, без синтеза: отражения и хвост — из замера;
  * диффузно-полевая эквализация — общий фильтр KU100 (Common Diffuse Field Compensation, KU100_CDFC.mat того же
    набора; у FABIAN — инверсная CTF), окраска уха в прямом звуке колонок — как есть (front 0) или выровненная (Flat,
    front 1), как generate_rooms.front_correction;
  * HEAD: прямая часть (DIRECT_N) для поворотов −50…+50° через 2° — измеренные повороты (без интерполяции), та же
    эквализация, сдвиг и громкость; отражения в наборах — как в замере при этом повороте, в пределах прямой части;
  * громкость прямой части 0 dB, WAV 48 кГц (24 или 16 бит), срез низа колонок — в замере (speaker hp 0).

Замеры — "A Spatial Audio Impulse Response Compilation Captured at the WDR Broadcast Studios" (TH Köln), Zenodo
10.5281/zenodo.3930833, CC BY 4.0 (в метаданных SOFA — CC BY-SA 3.0): BRIR_CR7_KU_ROTM_L/R (Control Room 7, B&W 803D),
BRIR_SBS_KU_ROTM_PAL/PAR (Small Broadcast Studio, 1247 м³, PA AD-Systems Stium + Flex 15). Записи дописываются в
rooms.json ("source": "brir"; generate_rooms.py их сохраняет).

Запуск: pip install numpy scipy sofar
        python3 ios/tools/generate_room_brir.py <папка SOFA замеров (и KU100_CDFC.mat)>
"""
import json
import os
import sys
import warnings

import numpy as np
import scipy.io as sio
import scipy.signal as sg
import sofar as sf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_rooms as G  # noqa: E402

SR = G.SR

ROOMS = [
    # Studio CR7 KU100 убран 15.11 (решение пользователя: с FABIAN — лучше).
    dict(name="HallKU", file="RoomHallKU.wav", sofa=("BRIR_SBS_KU_ROTM_PAL.sofa", "BRIR_SBS_KU_ROTM_PAR.sofa"),
         early_ms=80.0, max_ms=1000, bits=16, desc="WDR Small Broadcast Studio, PA, KU100 BRIR (TH Köln WDR compilation, CC BY 4.0)"),
]


def load_brir(path):
    """BRIR одной колонки: [поворот головы 0…359° (влево +)][ухо][отсчёт]."""
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        s = sf.read_sofa(path, verify=False)
    assert float(s.Data_SamplingRate) == SR
    x = np.asarray(s.Data_IR, dtype=float)[:, :, 0, :]
    view = np.asarray(s.ListenerView, dtype=float)[:, 0]
    # Поворот — по номеру записи (через 1°). В BRIR_CR7_KU_ROTM_R запись 59 пустая (NaN, в метаданных 0°) — она вне
    # HEAD (±50° — записи 0…50 и 310…359); нужные записи проверяются.
    used = list(range(0, 51)) + list(range(310, 360))
    assert x.shape[0] == 360 and np.allclose(view[used], used, atol=0.01) and np.all(np.isfinite(x[used])), path
    return x, getattr(s, "GLOBAL_RoomDescription", ""), getattr(s, "GLOBAL_SourceDescription", ""), \
        getattr(s, "GLOBAL_License", "")


def paths(spks, yaw):
    """4 пути при повороте головы yaw (вправо +): поворот замера — влево +."""
    i = int(round(-yaw)) % 360
    l, r = spks
    return np.stack([l[i, 0], l[i, 1], r[i, 0], r[i, 1]])


def conv(h, f, nfft):
    return np.fft.irfft(np.fft.rfft(h, nfft, axis=-1) * f[None, :], nfft, axis=-1)


def make_room(cfg, spks, cdfc, front):
    n_max = int(SR * cfg["max_ms"] / 1000)
    n = spks[0].shape[-1]
    nfft = 1 << int(np.ceil(np.log2(max(n, n_max) + 4096)))
    eq = np.fft.rfft(cdfc, nfft)
    h = conv(paths(spks, 0), eq, nfft)
    onset = int(np.argmax(np.max(np.abs(h), axis=0) > 0.05 * np.max(np.abs(h))))
    shift = max(0, onset - G.PRE)
    h = np.roll(h, -shift, axis=-1)
    # Прямой звук для выравнивания окраски — первые DIRECT_N отсчётов (до первых отражений).
    dry = np.zeros_like(h)
    dry[:, :G.DIRECT_N] = h[:, :G.DIRECT_N] * np.hanning(2 * G.DIRECT_N)[G.DIRECT_N // 2:G.DIRECT_N // 2 + G.DIRECT_N]
    corr = G.front_correction(dry, nfft, front)
    h = conv(h, corr, nfft)[:, :n_max]
    # Отражения и хвост: самый низ (< 20 Гц) — прочь (шум замера и постоянная составляющая); конец — без обрыва
    # (последние 10 % длины).
    sos = sg.butter(2, 20, btype="highpass", fs=SR, output="sos")
    rest = h.copy()
    rest[:, :G.DIRECT_N] = 0
    h[:, G.DIRECT_N:] = 0
    h += sg.sosfilt(sos, rest, axis=-1)
    end = n_max // 10
    h[:, -end:] *= (0.5 * (1 + np.cos(np.linspace(0, np.pi, end))))[None, :]
    p = G.mono_power(h[:, :G.DIRECT_N], nfft)
    h /= np.sqrt(p)
    scale = 0.99 / np.max(np.abs(h))
    info = dict(nfft=nfft, shift=shift, corr=corr, eq=eq, norm=np.sqrt(p), scale=scale)
    return h * scale, -20 * np.log10(scale), n_max, info


def write_head(spks, info, gain_db, file, res):
    nfft, shift, k = info["nfft"], info["shift"], info["scale"] / info["norm"]
    hs = np.zeros((G.HEAD_COUNT, 4, G.DIRECT_N))
    for i in range(G.HEAD_COUNT):
        yaw = G.HEAD_FROM + G.HEAD_STEP * i
        e = conv(conv(paths(spks, yaw), info["eq"], nfft), info["corr"], nfft)
        hs[i] = np.roll(e, -shift, axis=-1)[:, :G.DIRECT_N] * k
    hscale = 0.99 / max(float(np.max(np.abs(hs))), 0.99)
    head_file = file.replace(".wav", "Head.wav")
    G.write_wav(os.path.join(res, head_file), np.concatenate(list(hs * hscale), axis=-1), 16)
    return head_file, round(gain_db - 20 * np.log10(hscale), 3), hs


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    meas = sys.argv[1]
    here = os.path.dirname(os.path.abspath(__file__))
    res = os.path.join(here, "..", "JAMbo.swiftpm", "Resources")
    m = sio.loadmat(os.path.join(meas, "KU100_CDFC.mat"), squeeze_me=True, struct_as_record=False)["hpcf"]
    assert int(m.fs) == SR
    cdfc = np.asarray(m.minPhase, dtype=float)
    print("KU100 CDFC:", m.hpName, cdfc.shape)
    meta = []
    for cfg in ROOMS:
        loaded = [load_brir(os.path.join(meas, f)) for f in cfg["sofa"]]
        spks = [x[0] for x in loaded]
        print("%s: %s, %s, license in file: %s" % (cfg["name"], loaded[0][1], loaded[0][2], loaded[0][3]))
        h, gain_db, length, info = make_room(cfg, spks, cdfc, G.FRONT)
        G.write_wav(os.path.join(res, cfg["file"]), h, cfg["bits"])
        head_file, head_gain, hs = write_head(spks, info, gain_db, cfg["file"], res)
        i0 = (0 - G.HEAD_FROM) // G.HEAD_STEP
        dev = np.max(np.abs(hs[i0] - h[:, :G.DIRECT_N])) / np.max(np.abs(h[:, :G.DIRECT_N]))
        hf, flat_gain, _, finfo = make_room(cfg, spks, cdfc, 1.0)
        flat_file = cfg["file"].replace(".wav", "Flat.wav")
        G.write_wav(os.path.join(res, flat_file), hf[:, :int(SR * cfg["early_ms"] / 1000)], 16)
        flat_head, flat_head_gain, _ = write_head(spks, finfo, flat_gain, flat_file, res)
        meta.append(dict(name=cfg["name"], file=cfg["file"], source="brir", measurement=cfg["desc"],
                         gain_db=round(gain_db, 3), length_ms=round(1000 * length / SR, 1), direct=G.DIRECT_N,
                         channels="LL, LR, RL, RR", speaker=dict(hp_hz=0, hp_order=0, ft_hz=0),
                         head=dict(file=head_file, from_deg=G.HEAD_FROM, step_deg=G.HEAD_STEP, count=G.HEAD_COUNT,
                                   gain_db=head_gain),
                         flat=dict(file=flat_file, gain_db=round(flat_gain, 3), head_file=flat_head,
                                   head_gain_db=flat_head_gain)))
        print("%s: %.1f ms, gain %.2f dB, flat gain %.2f dB; HEAD при 0° — отличие %.1e"
              % (cfg["name"], 1000 * length / SR, gain_db, flat_gain, dev))
    path = os.path.join(res, "rooms.json")
    with open(path) as f:
        data = json.load(f)
    names = {r["name"] for r in meta}
    data["rooms"] = [r for r in data["rooms"] if r["name"] not in names] + meta
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print("written:", [r["file"] for r in meta])


if __name__ == "__main__":
    main()
