#!/usr/bin/env python3
"""임시 효과음 생성기 — Asset/Sound/SFX/*.wav (22.05kHz 16bit mono)

진짜 사운드 에셋이 오기 전까지 '소리가 아예 없는' 상태를 벗어나기 위한 합성음.
hud.gd play_sfx / 엔진 루프 / 창·괴물 연출이 이 파일들을 로드한다.
재생성:  python3 tools/gen_placeholder_sfx.py
"""
import math, os, struct, wave
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Asset", "Sound", "SFX")
rng = np.random.default_rng(1337)


def t(dur):
    return np.arange(int(SR * dur)) / SR


def env_exp(n, k):
    return np.exp(-k * np.arange(n) / SR)


def lowpass(x, cutoff):
    a = math.exp(-2.0 * math.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, lo, hi):
    return highpass(lowpass(x, hi), lo)


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive)


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    x = np.clip(x, -1.0, 1.0)
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print("wrote", name, f"{len(x)/SR:.2f}s")


# ── impact: 묵직한 타격 (저음 썸프 + 짧은 노이즈 버스트) ──
def impact():
    tt = t(0.4)
    f = 70 * np.exp(-6 * tt) + 32
    ph = 2 * np.pi * np.cumsum(f) / SR
    thump = np.sin(ph) * env_exp(len(tt), 9)
    noise = lowpass(rng.standard_normal(len(tt)), 900) * env_exp(len(tt), 28) * 0.8
    return norm(soft_clip(thump * 1.6 + noise, 1.8))


# ── warning: 금속 긁힘 (공진 노이즈 스윕 + 플러터) ──
def warning():
    tt = t(0.55)
    n = rng.standard_normal(len(tt))
    sweep = np.linspace(1100, 2600, len(tt))
    y = np.zeros_like(tt)
    acc = 0.0
    for i in range(len(tt)):
        a = math.exp(-2 * math.pi * sweep[i] / SR)
        acc = (1 - a) * n[i] + a * acc
        y[i] = n[i] - acc
    flutter = 0.6 + 0.4 * np.sin(2 * np.pi * 38 * tt)
    e = np.minimum(1.0, tt / 0.03) * env_exp(len(tt), 5)
    return norm(soft_clip(y * flutter * e * 3.0, 1.5))


# ── pickup: BO 흡수 '띵' (배음 2개, 빠른 감쇠) ──
def pickup():
    tt = t(0.3)
    f0 = 1320.0
    y = (np.sin(2 * np.pi * f0 * tt) + 0.4 * np.sin(2 * np.pi * f0 * 2.01 * tt)
         + 0.15 * np.sin(2 * np.pi * f0 * 3.0 * tt))
    y *= env_exp(len(tt), 14)
    y[: int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))
    return norm(y, 0.7)


# ── repair: 라쳇 클릭 4회 ──
def repair():
    tt = t(0.45)
    y = np.zeros_like(tt)
    for i in range(4):
        s = int((0.03 + i * 0.1) * SR)
        ln = int(0.03 * SR)
        y[s:s + ln] += highpass(rng.standard_normal(ln), 1500) * env_exp(ln, 120)
    return norm(soft_clip(y * 2.5, 1.2), 0.8)


# ── engine_loop: 1.0초 정확 루프 (55Hz 배음열). rpm 800→pitch 1.0, 7200→~3.0 ──
def engine_loop():
    dur = 1.0
    tt = t(dur)
    f0 = 55.0
    y = np.zeros_like(tt)
    for h in range(1, 14):
        amp = 1.0 / (h ** 1.15)
        y += amp * np.sin(2 * np.pi * f0 * h * tt + (h * 0.7))
    # 4기통 느낌: 2배음 강조 + 미세 러프니스
    y += 0.5 * np.sin(2 * np.pi * f0 * 2 * tt) * (1 + 0.15 * np.sin(2 * np.pi * 11 * tt))
    y = lowpass(y, 900)
    y += lowpass(rng.standard_normal(len(tt)), 300) * 0.08
    # 루프 이음새 제거: 양끝 5ms 크로스페이드
    xf = int(0.005 * SR)
    ramp = np.linspace(0, 1, xf)
    y[:xf] = y[:xf] * ramp + y[-xf:] * (1 - ramp)
    return norm(soft_clip(y, 1.1), 0.6)


# ── monster_breath: 멀리서 들리는 깊은 들숨 (창 경고) ──
def monster_breath():
    tt = t(1.4)
    n = rng.standard_normal(len(tt))
    y = lowpass(n, 420) * 2.0 + bandpass(n, 500, 1400) * 0.35
    swell = np.sin(np.pi * np.minimum(tt / 1.4, 1.0)) ** 1.6
    trem = 1 + 0.12 * np.sin(2 * np.pi * 6.5 * tt)
    return norm(soft_clip(y * swell * trem * 2.0, 1.3), 0.85)


# ── whoosh: 창이 옆을 스쳐 지나감 (노이즈 밴드 스윕) ──
def whoosh():
    tt = t(0.5)
    n = rng.standard_normal(len(tt))
    center = 300 + 2700 * np.sin(np.pi * tt / 0.5) ** 2
    y = np.zeros_like(tt)
    lp = 0.0
    lp2 = 0.0
    for i in range(len(tt)):
        a = math.exp(-2 * math.pi * center[i] / SR)
        lp = (1 - a) * n[i] + a * lp
        b = math.exp(-2 * math.pi * (center[i] * 0.4) / SR)
        lp2 = (1 - b) * lp + b * lp2
        y[i] = lp - lp2
    e = np.sin(np.pi * tt / 0.5) ** 1.3
    return norm(soft_clip(y * e * 6.0, 1.4), 0.9)


# ── click / rustle: passenger_hallucination.gd가 기대하는 경로 ──
def click():
    tt = t(0.08)
    y = highpass(rng.standard_normal(len(tt)), 2500) * env_exp(len(tt), 90)
    return norm(y, 0.7)


def rustle():
    tt = t(0.45)
    y = highpass(rng.standard_normal(len(tt)), 1800) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 9 * tt))) * env_exp(len(tt), 4)
    return norm(y, 0.6)


if __name__ == "__main__":
    write("impact.wav", impact())
    write("warning.wav", warning())
    write("pickup.wav", pickup())
    write("repair.wav", repair())
    write("engine_loop.wav", engine_loop())
    write("monster_breath.wav", monster_breath())
    write("whoosh.wav", whoosh())
    write("click.wav", click())
    write("rustle.wav", rustle())
