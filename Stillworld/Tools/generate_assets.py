#!/usr/bin/env python3
"""
STILLWORLD - procedural placeholder asset generator (numpy + Pillow only).

Writes into Stillworld/Tools/generated/:
  T_RainStreaks.png            512x1024 8-bit grey, tileable rain streaks
  T_MacroNoise.png             256x256 8-bit grey, tileable low-frequency noise
  T_SW_Default_Rough.png       64x64 flat roughness placeholder (imported as Masks)
  T_SW_Placeholder_<L>.png     128x128 tileable albedo placeholders (Grass/Dirt/Asphalt/Moss)
  SW_Rain.wav, SW_Wind.wav     20 s seamless loops, 44.1 kHz 16-bit mono
  sfx/*.wav                    short one-shots (footsteps, drips, birds, ...)

Everything here is synthesised from scratch (filtered noise, envelopes, modal
synthesis) and is released as CC0. Deterministic: fixed seeds.

Usage:  python3 Stillworld/Tools/generate_assets.py
"""

import os
import wave

import numpy as np
from PIL import Image

SR = 44100
PEAK_DBFS = -6.0
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "generated")
SFX_OUT = os.path.join(OUT, "sfx")


# ---------------------------------------------------------------------------
# Generic DSP helpers (FFT based - no scipy needed)
# ---------------------------------------------------------------------------

def freqs_for(n):
    return np.fft.rfftfreq(n, 1.0 / SR)


def shape(x, gain_fn):
    """Filter signal x with a zero-phase frequency response gain_fn(f)."""
    n = len(x)
    X = np.fft.rfft(x)
    f = freqs_for(n)
    return np.fft.irfft(X * gain_fn(f), n)


def bp_gain(lo, hi, order=2):
    """Smooth band-pass magnitude (Butterworth-like) between lo and hi Hz."""
    def g(f):
        f = np.maximum(f, 1e-3)
        hp = 1.0 / np.sqrt(1.0 + (lo / f) ** (2 * order)) if lo > 0 else 1.0
        lp = 1.0 / np.sqrt(1.0 + (f / hi) ** (2 * order)) if hi > 0 else 1.0
        return hp * lp
    return g


def band_noise(rng, n, lo, hi, order=2):
    return shape(rng.standard_normal(n), bp_gain(lo, hi, order))


def smooth_random(rng, n, cutoff_hz):
    """Slowly varying random curve, roughly zero-mean, unit std."""
    c = shape(rng.standard_normal(n), lambda f: np.exp(-(f / cutoff_hz) ** 2))
    return c / (np.std(c) + 1e-12)


def conv(x, h):
    """Linear FFT convolution, output length len(x)."""
    n = len(x) + len(h) - 1
    nfft = 1 << (n - 1).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(h, nfft), nfft)
    return y[: len(x)]


def reverb(rng, x, t60=0.6, wet=0.25, lo=200, hi=6000):
    """Cheap diffuse tail: convolve with exponentially decaying filtered noise."""
    n = int(t60 * SR)
    t = np.arange(n) / SR
    ir = band_noise(rng, n, lo, hi) * np.exp(-6.9 * t / t60)
    ir[: int(0.012 * SR)] = 0.0          # pre-delay
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    return x * (1.0 - wet) + conv(x, ir) * wet * 1.5


def env_ad(n, attack, decay, start=0):
    """Attack / exponential decay envelope (seconds), placed at sample `start`."""
    e = np.zeros(n)
    a = max(1, int(attack * SR))
    t = np.arange(n - start) / SR
    seg = np.where(t < attack, (t / max(attack, 1e-6)), np.exp(-(t - attack) / decay))
    seg[:a] = np.linspace(0, 1, a) ** 2
    e[start:] = seg
    return e


def fade_edges(x, fin=0.002, fout=0.02):
    x = x.copy()
    a, b = int(fin * SR), int(fout * SR)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def normalize(x, peak_db=PEAK_DBFS):
    x = x - np.mean(x)
    return x * (10 ** (peak_db / 20.0) / (np.max(np.abs(x)) + 1e-12))


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def chirp_tone(n, f_curve, amp_curve, rng=None, harmonics=((1, 1.0),)):
    """Tone with an arbitrary per-sample frequency curve (phase integrated)."""
    phase = 2 * np.pi * np.cumsum(f_curve) / SR
    y = np.zeros(n)
    for k, a in harmonics:
        y += a * np.sin(k * phase)
    return y * amp_curve


def bubble(n, f0, decay, rise=0.6, start=0, amp=1.0):
    """Minnaert-style water bubble: decaying sine whose pitch rises."""
    out = np.zeros(n)
    m = min(n - start, int(decay * 7 * SR))
    if m <= 0:
        return out
    t = np.arange(m) / SR
    f = f0 * (1.0 + rise * t / (decay * 3))
    ph = 2 * np.pi * np.cumsum(f) / SR
    e = np.exp(-t / decay) * (1 - np.exp(-t / 0.0007))
    out[start:start + m] = amp * np.sin(ph) * e
    return out


def modal_ir(rng, dur, modes):
    """Impulse response of a bank of damped resonators: modes = [(f, t60, amp)]."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for f, t60, a in modes:
        y += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 2 * np.pi)) * np.exp(-6.9 * t / t60)
    return y


def write_wav(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def make_loop(x, n, xfade):
    """x has n + xfade samples; fold the tail over the head (equal power)."""
    out = x[:n].copy()
    k = np.linspace(0, np.pi / 2, xfade)
    out[:xfade] = x[n:n + xfade] * np.cos(k) + x[:xfade] * np.sin(k)
    return out


# ---------------------------------------------------------------------------
# Textures
# ---------------------------------------------------------------------------

def gen_rain_texture(path, w=512, h=1024, count=1500, seed=11):
    rng = np.random.default_rng(seed)
    img = np.zeros((h, w), np.float64)
    dx = np.arange(-3, 4)
    for _ in range(count):
        x0 = rng.uniform(0, w)
        y0 = rng.integers(0, h)
        length = int(np.clip(rng.lognormal(np.log(55), 0.55), 12, 300))
        sigma = rng.uniform(0.35, 1.1)
        bright = rng.uniform(0.05, 1.0) ** 2.2     # mostly dim, a few bright
        t = np.linspace(0, 1, length)
        v = np.sin(np.pi * t) ** 0.8 * (0.55 + 0.45 * t)   # brighter leading (lower) end
        xi = int(np.floor(x0))
        frac = x0 - xi
        hprof = np.exp(-0.5 * ((dx - frac) / sigma) ** 2)
        hprof /= hprof.max()
        rows = (y0 + np.arange(length)) % h
        cols = (xi + dx) % w
        img[np.ix_(rows, cols)] += np.outer(v, hprof) * bright
    # soft vertical smear (wrap-around, keeps tiling) then soft tonemap
    k = np.array([0.25, 0.5, 0.25])
    img = sum(np.roll(img, s, axis=0) * kk for s, kk in zip((-1, 0, 1), k))
    img = 1.0 - np.exp(-img * 1.4)
    Image.fromarray(np.clip(img * 255 + 0.5, 0, 255).astype(np.uint8), "L").save(path, optimize=True)


def tileable_noise(rng, size, beta=2.0, fmin=1.0):
    """Periodic 1/f^beta noise via inverse FFT (tiles perfectly)."""
    fx = np.fft.fftfreq(size) * size
    fy = np.fft.fftfreq(size) * size
    r = np.sqrt(fx[None, :] ** 2 + fy[:, None] ** 2)
    amp = np.where(r >= fmin, 1.0 / np.maximum(r, 1e-6) ** (beta / 2.0), 0.0)
    ph = rng.standard_normal((size, size)) + 1j * rng.standard_normal((size, size))
    n = np.real(np.fft.ifft2(ph * amp))
    n = (n - n.mean()) / (n.std() + 1e-12)
    return n


def gen_macro_noise(path, size=256, seed=21):
    rng = np.random.default_rng(seed)
    n = tileable_noise(rng, size, beta=3.2, fmin=1.0)
    n = 0.5 + 0.22 * n
    Image.fromarray(np.clip(n * 255 + 0.5, 0, 255).astype(np.uint8), "L").save(path, optimize=True)


def gen_placeholder_albedo(path, rgb, contrast, speckle, seed, size=128):
    rng = np.random.default_rng(seed)
    n = tileable_noise(rng, size, beta=2.2, fmin=1.0) * contrast
    s = tileable_noise(rng, size, beta=0.3, fmin=8.0) * speckle
    img = np.stack([np.clip(c * (1 + n + s), 0, 1) for c in rgb], -1)
    Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGB").save(path, optimize=True)


def gen_flat_grey(path, value, size=64):
    Image.fromarray(np.full((size, size), value, np.uint8), "L").save(path, optimize=True)


# ---------------------------------------------------------------------------
# Ambience loops
# ---------------------------------------------------------------------------

def gen_rain_loop(path, seconds=20.0, seed=101):
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    xf = int(2.0 * SR)
    m = n + xf

    # Body: soft hiss, high-passed ~350 Hz, broad presence 2-6 kHz, rolled off above 9 kHz.
    def g(f):
        f = np.maximum(f, 1e-3)
        hp = 1 / np.sqrt(1 + (350 / f) ** 4)
        lp = 1 / np.sqrt(1 + (f / 6500) ** 4)
        tilt = (np.minimum(f, 2500) / 2500) ** 0.3 * (2500 / np.maximum(f, 2500)) ** 0.5   # gentle pink-ish low end
        return hp * lp * tilt
    hiss = shape(rng.standard_normal(m), g)
    # Low "distant rain on a field" bed
    bed = band_noise(rng, m, 120, 900) * 0.35
    # slow breathing of intensity
    mod = 1.0 + 0.10 * smooth_random(rng, m, 0.15) + 0.04 * smooth_random(rng, m, 1.5)
    body = (hiss + bed) * mod
    body /= np.std(body)

    # Dense micro-drops (blended into the hiss) and sparse nearer droplets.
    drops = np.zeros(m)
    for _ in range(int(seconds * 260)):
        s = rng.integers(0, m - 4000)
        drops += bubble(m, rng.uniform(1800, 5000), rng.uniform(0.0015, 0.004),
                        rise=rng.uniform(0.2, 1.0), start=s, amp=rng.uniform(0.05, 0.25))
    near = np.zeros(m)
    for _ in range(int(seconds * 4.5)):
        s = rng.integers(0, m - 8000)
        near += bubble(m, rng.uniform(1200, 3800), rng.uniform(0.004, 0.012),
                       rise=rng.uniform(0.4, 1.4), start=s, amp=rng.uniform(0.3, 1.0))
        # tiny impact click
        c = band_noise(rng, 300, 3000, 12000) * np.exp(-np.arange(300) / 40.0)
        near[s:s + 300] += c * rng.uniform(0.2, 0.6)
    near = reverb(rng, near, t60=0.35, wet=0.35)

    x = body * 0.6 + drops * 0.6 + near * 0.5
    x = make_loop(x, n, xf)
    write_wav(path, normalize(soft_clip(x / np.max(np.abs(x)) * 1.2, 1.2)))


def gen_wind_loop(path, seconds=20.0, seed=202):
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    xf = int(2.5 * SR)
    m = n + xf

    gust = smooth_random(rng, m, 0.09) * 0.7 + smooth_random(rng, m, 0.35) * 0.3
    gust = (gust - gust.min()) / (gust.max() - gust.min())
    gust = 0.3 + 0.7 * gust ** 1.4

    low = band_noise(rng, m, 25, 180, order=2)          # rumble
    mid = band_noise(rng, m, 150, 650, order=2)          # body, grows with gusts
    air = band_noise(rng, m, 600, 2500, order=2)         # faint airy edge on peaks
    # very faint, wandering "whistle" resonance
    whistle = band_noise(rng, m, 520, 580, order=4) * (0.5 + 0.5 * smooth_random(rng, m, 0.2))

    x = (low / np.std(low)) * (0.55 + 0.45 * gust) \
        + (mid / np.std(mid)) * 0.45 * gust ** 2 \
        + (air / np.std(air)) * 0.10 * gust ** 3 \
        + (whistle / np.std(whistle)) * 0.03 * gust ** 2
    x = make_loop(x, n, xf)
    write_wav(path, normalize(x))


# ---------------------------------------------------------------------------
# One-shot SFX
# ---------------------------------------------------------------------------

def _thump(rng, n, start, amp, lo=40, hi=180, decay=0.03):
    th = band_noise(rng, n, lo, hi) * env_ad(n, 0.004, decay, start)
    return th / (np.max(np.abs(th)) + 1e-12) * amp


def foot_grass(rng):
    n = int(rng.uniform(0.42, 0.55) * SR)
    x = np.zeros(n)
    for start, amp in ((0, 1.0), (int(rng.uniform(0.07, 0.12) * SR), rng.uniform(0.5, 0.8))):
        sw = band_noise(rng, n, rng.uniform(1500, 2500), rng.uniform(7000, 10000))
        e = env_ad(n, rng.uniform(0.012, 0.03), rng.uniform(0.06, 0.12), start)
        # rustle flutter
        fl = 0.6 + 0.4 * np.abs(smooth_random(rng, n, 60))
        x += sw / np.std(sw) * e * fl * amp
    # blade crackles
    for _ in range(rng.integers(15, 35)):
        s = rng.integers(0, int(n * 0.6))
        L = rng.integers(40, 160)
        c = band_noise(rng, L, 3000, 12000) * np.hanning(L)
        x[s:s + L] += c / (np.max(np.abs(c)) + 1e-9) * rng.uniform(0.2, 0.6)
    x += _thump(rng, n, 0, 0.6, 50, 160, 0.025)
    return fade_edges(x)


def foot_dirt(rng):
    n = int(rng.uniform(0.38, 0.5) * SR)
    x = np.zeros(n)
    density_env = env_ad(n, 0.01, 0.07) + 0.6 * env_ad(n, 0.01, 0.06, int(rng.uniform(0.08, 0.12) * SR))
    grains = rng.integers(140, 260)
    for _ in range(grains):
        s = rng.integers(0, int(n * 0.75))
        if rng.random() > density_env[s] * 1.2:
            continue
        L = rng.integers(25, 160)
        lo = rng.uniform(600, 2000)
        c = band_noise(rng, L + 64, lo, lo * rng.uniform(2.0, 4.0))[:L] * np.exp(-np.arange(L) / (L / 4))
        x[s:s + L] += c / (np.max(np.abs(c)) + 1e-9) * rng.uniform(0.15, 1.0) * density_env[s]
    hiss = band_noise(rng, n, 1500, 7000)
    x += hiss / np.std(hiss) * density_env * 0.08
    x += _thump(rng, n, 0, 0.9, 50, 200, 0.035)
    return fade_edges(reverb(rng, x, 0.25, 0.12))


def foot_asphalt(rng):
    n = int(rng.uniform(0.32, 0.42) * SR)
    x = np.zeros(n)
    hard = modal_ir(rng, 0.08, [(rng.uniform(160, 220), 0.03, 1.0), (rng.uniform(380, 480), 0.025, 0.6),
                                (rng.uniform(900, 1200), 0.015, 0.35), (rng.uniform(2200, 2900), 0.01, 0.2)])
    for start, amp in ((0, 1.0), (int(rng.uniform(0.06, 0.1) * SR), rng.uniform(0.35, 0.6))):
        imp = np.zeros(n)
        imp[start] = 1.0
        click = band_noise(rng, n, 1500, 6000) * env_ad(n, 0.0005, 0.004, start)
        x += (conv(imp, hard) + click / (np.max(np.abs(click)) + 1e-9) * 0.5) * amp
    # grit scuff
    sc_start = int(rng.uniform(0.0, 0.05) * SR)
    sc = band_noise(rng, n, 2000, 9000) * env_ad(n, 0.02, rng.uniform(0.05, 0.1), sc_start)
    x += sc / np.std(sc) * rng.uniform(0.04, 0.09)
    x += _thump(rng, n, 0, 0.5, 40, 140, 0.02)
    return fade_edges(reverb(rng, x, 0.4, 0.15))


def foot_wet(rng):
    n = int(rng.uniform(0.4, 0.55) * SR)
    x = np.zeros(n)
    sp = band_noise(rng, n, 800, 6000) * env_ad(n, 0.006, rng.uniform(0.06, 0.12))
    x += sp / np.std(sp) * 0.25
    sq = band_noise(rng, n, 250, 1400) * env_ad(n, 0.02, 0.08, int(0.02 * SR))
    x += sq / np.std(sq) * 0.2 * (0.5 + 0.5 * np.abs(smooth_random(rng, n, 40)))
    for _ in range(rng.integers(6, 14)):
        s = rng.integers(0, int(n * 0.55))
        x += bubble(n, rng.uniform(500, 2200), rng.uniform(0.004, 0.015),
                    rise=rng.uniform(0.5, 2.0), start=s, amp=rng.uniform(0.2, 0.8))
    return fade_edges(x)


def drip(rng):
    n = int(rng.uniform(0.5, 0.8) * SR)
    x = bubble(n, rng.uniform(900, 2600), rng.uniform(0.012, 0.035), rise=rng.uniform(0.8, 2.5), start=200)
    c = band_noise(rng, 400, 2000, 10000) * np.exp(-np.arange(400) / 60.0)
    x[200:600] += c / np.max(np.abs(c)) * 0.3
    if rng.random() < 0.5:   # small secondary drop
        x += bubble(n, rng.uniform(1500, 3500), 0.008, 1.0, int(rng.uniform(0.08, 0.2) * SR), 0.3)
    return fade_edges(reverb(rng, x, rng.uniform(0.4, 0.7), 0.3, 300, 8000))


def distance_filter(x, cutoff):
    return shape(x, lambda f: 1 / np.sqrt(1 + (np.maximum(f, 1) / cutoff) ** 4)
                 * 1 / np.sqrt(1 + (300 / np.maximum(f, 1)) ** 2))


def bird(rng):
    dur = rng.uniform(1.2, 2.2)
    n = int(dur * SR)
    x = np.zeros(n)
    kind = rng.integers(0, 3)
    t = 0.05
    base = rng.uniform(2800, 4800)
    while t < dur - 0.3:
        L = int(rng.uniform(0.04, 0.16) * SR)
        s = int(t * SR)
        u = np.linspace(0, 1, L)
        if kind == 0:     # down-slurred whistles
            f = base * (1.25 - 0.45 * u) * rng.uniform(0.9, 1.1)
        elif kind == 1:   # up-slurred "tsip"
            f = base * (0.8 + 0.5 * u ** 0.7) * rng.uniform(0.92, 1.08)
        else:             # short trilled note
            f = base * (1.0 + 0.08 * np.sin(2 * np.pi * rng.uniform(30, 55) * u * L / SR)) * (1.1 - 0.2 * u)
        a = np.sin(np.pi * u) ** 1.5
        note = chirp_tone(L, f, a, harmonics=((1, 1.0), (2, 0.12), (3, 0.03)))
        x[s:s + L] += note * rng.uniform(0.5, 1.0)
        t += L / SR + rng.uniform(0.03, 0.25)
        if rng.random() < 0.18:
            t += rng.uniform(0.2, 0.5)
    x = distance_filter(x, rng.uniform(4500, 6500))
    return fade_edges(reverb(rng, x, 1.2, 0.45, 800, 9000))


def crow(rng):
    caws = rng.integers(2, 5)
    dur = 0.4 + caws * 0.65
    n = int(dur * SR)
    x = np.zeros(n)
    t = 0.05
    f0b = rng.uniform(430, 600)
    for _ in range(caws):
        L = int(rng.uniform(0.25, 0.4) * SR)
        s = int(t * SR)
        if s + L >= n:
            break
        u = np.linspace(0, 1, L)
        jitter = 1 + 0.03 * smooth_random(rng, L, 25)
        f0 = f0b * (1.08 - 0.18 * u) * jitter
        harm = tuple((k, 1.0 / k ** 0.9) for k in range(1, 14))
        a = (1 - np.exp(-u / 0.06)) * np.exp(-((u - 0.35) / 0.55) ** 2)
        tone = chirp_tone(L, f0, a, harmonics=harm)
        rb = band_noise(rng, L, 30, 90)
        rasp = 1 + 0.35 * rb / (np.std(rb) + 1e-12)
        x[s:s + L] += tone * rasp
        t += L / SR + rng.uniform(0.25, 0.45)
    # vocal tract formants
    x = shape(x, lambda f: np.exp(-((f - 1300) / 500) ** 2) + 0.6 * np.exp(-((f - 2500) / 600) ** 2)
              + 0.15 * np.exp(-((f - 700) / 300) ** 2))
    x = distance_filter(x, 3500)
    return fade_edges(reverb(rng, x, 1.6, 0.5, 300, 6000))


def thunder_far(rng):
    dur = rng.uniform(7.0, 9.5)
    n = int(dur * SR)
    tt = np.arange(n) / SR
    # brown-ish low noise
    rumble = shape(rng.standard_normal(n),
                   lambda f: 1 / np.maximum(f, 15) * (1 / np.sqrt(1 + (np.maximum(f, 1) / 220) ** 6))
                   * (1 / np.sqrt(1 + (22 / np.maximum(f, 1)) ** 4)))
    rumble /= np.std(rumble)
    env = np.zeros(n)
    t0 = rng.uniform(0.2, 0.6)
    for _ in range(rng.integers(4, 8)):
        tc = t0 + rng.exponential(1.2)
        w = rng.uniform(0.4, 1.4)
        env += rng.uniform(0.4, 1.0) * np.exp(-((tt - tc) / w) ** 2)
    env += np.where(tt > t0, np.exp(-(tt - t0) / (dur * 0.35)), 0) * (1 - np.exp(-np.maximum(tt - t0, 0) / 0.3))
    env = env / env.max()
    env *= 1 + 0.25 * smooth_random(rng, n, 3)
    crack = band_noise(rng, n, 200, 900) * np.exp(-np.maximum(tt - t0, 0) / 0.8) * (tt > t0)
    x = rumble * env + crack / np.std(crack) * 0.08 * env
    x = reverb(rng, x, 2.5, 0.4, 30, 600)
    out = fade_edges(x, 0.05, 1.0)
    return out


def metal_creak(rng):
    dur = rng.uniform(2.2, 3.4)
    n = int(dur * SR)
    tt = np.arange(n) / SR
    # stick-slip pulse train with wandering rate
    rate = rng.uniform(25, 60) * (1 + 0.6 * smooth_random(rng, n, 1.2))
    rate = np.clip(rate, 8, 160)
    phase = np.cumsum(rate) / SR
    pulses = np.zeros(n)
    idx = np.nonzero(np.diff(np.floor(phase)) > 0)[0]
    pressure = np.sin(np.pi * np.clip((tt - 0.1) / (dur - 0.4), 0, 1)) ** 0.8
    pressure *= 1 + 0.3 * smooth_random(rng, n, 2)
    pulses[idx] = pressure[idx] * rng.uniform(0.5, 1.0, len(idx))
    base = rng.uniform(280, 420)
    ratios = [1.0, 2.31, 3.98, 6.12, 8.6]
    modes = [(base * r * rng.uniform(0.97, 1.03), rng.uniform(0.08, 0.35), 1.0 / (i + 1)) for i, r in enumerate(ratios)]
    x = conv(pulses, modal_ir(rng, 0.5, modes))
    # friction grit
    grit = band_noise(rng, n, 1500, 6000) * np.maximum(pressure, 0)
    x = x / np.max(np.abs(x)) + grit / np.std(grit) * 0.03
    return fade_edges(reverb(rng, x, 1.2, 0.35, 200, 7000), 0.01, 0.2)


def leaves_gust(rng):
    dur = rng.uniform(3.2, 5.0)
    n = int(dur * SR)
    tt = np.arange(n) / SR
    peak = rng.uniform(0.35, 0.55) * dur
    env = np.where(tt < peak, (tt / peak) ** 1.8, np.exp(-((tt - peak) / (0.35 * dur)) ** 2))
    env *= 1 + 0.25 * smooth_random(rng, n, 1.0)
    env = np.maximum(env, 0)
    rustle = band_noise(rng, n, 1200, 9000)
    rustle /= np.std(rustle)
    flutter = 0.35 + 0.65 * np.abs(smooth_random(rng, n, rng.uniform(10, 22)))
    x = rustle * flutter * env
    # leaf ticks
    for _ in range(int(dur * 90)):
        s = rng.integers(0, n - 200)
        if rng.random() > env[s]:
            continue
        L = rng.integers(30, 120)
        c = band_noise(rng, L, 2500, 11000) * np.hanning(L)
        x[s:s + L] += c / (np.max(np.abs(c)) + 1e-9) * rng.uniform(0.5, 1.6)
    wind = band_noise(rng, n, 60, 400)
    x += wind / np.std(wind) * env ** 1.5 * 0.35
    return fade_edges(x, 0.05, 0.4)


SFX = [
    ("Foot_Grass", 6, foot_grass),
    ("Foot_Dirt", 6, foot_dirt),
    ("Foot_Asphalt", 6, foot_asphalt),
    ("Foot_Wet", 4, foot_wet),
    ("Drip", 5, drip),
    ("Bird", 4, bird),
    ("Crow", 2, crow),
    ("Thunder_Far", 2, thunder_far),
    ("Metal_Creak", 3, metal_creak),
    ("Leaves_Gust", 3, leaves_gust),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(SFX_OUT, exist_ok=True)

    gen_rain_texture(os.path.join(OUT, "T_RainStreaks.png"))
    gen_macro_noise(os.path.join(OUT, "T_MacroNoise.png"))
    gen_flat_grey(os.path.join(OUT, "T_SW_Default_Rough.png"), 204)   # ~0.8 roughness (linear)
    gen_placeholder_albedo(os.path.join(OUT, "T_SW_Placeholder_Grass.png"), (0.24, 0.29, 0.14), 0.22, 0.12, 31)
    gen_placeholder_albedo(os.path.join(OUT, "T_SW_Placeholder_Dirt.png"), (0.33, 0.27, 0.20), 0.18, 0.10, 32)
    gen_placeholder_albedo(os.path.join(OUT, "T_SW_Placeholder_Asphalt.png"), (0.24, 0.24, 0.24), 0.10, 0.22, 33)
    gen_placeholder_albedo(os.path.join(OUT, "T_SW_Placeholder_Moss.png"), (0.20, 0.27, 0.10), 0.25, 0.10, 34)

    gen_rain_loop(os.path.join(OUT, "SW_Rain.wav"))
    gen_wind_loop(os.path.join(OUT, "SW_Wind.wav"))

    for base, count, fn in SFX:
        for i in range(1, count + 1):
            rng = np.random.default_rng(1000 + 37 * i + sum(map(ord, base)))
            write_wav(os.path.join(SFX_OUT, "%s_%02d.wav" % (base, i)), normalize(fn(rng)))

    total = 0
    for root, _, files in os.walk(OUT):
        for f in sorted(files):
            p = os.path.join(root, f)
            sz = os.path.getsize(p)
            total += sz
            print("%-48s %9d bytes" % (os.path.relpath(p, OUT), sz))
    print("TOTAL %.2f MB" % (total / 1e6))


if __name__ == "__main__":
    main()
