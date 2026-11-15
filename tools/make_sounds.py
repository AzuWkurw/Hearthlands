#!/usr/bin/env python3
"""Generate Hearthlands' sound effects and ambience into ../sounds.

Usage:  python3 tools/make_sounds.py [group ...]     (groups: ui work nature animals war ambience)
Needs numpy, scipy and ffmpeg (with libvorbis).

Every sound is synthesised here, so there is nothing to license:
- impacts (axes, picks, hammers, knocks) are a short noisy transient over the ringing modes of what is
  struck (wood: a few low damped modes; metal and stone: many inharmonic ones),
- textures (saws, rain, surf, wind, fire, crowds) are shaped and filtered noise,
- calls (birds, animals, horns) are pitch glides through formant filters.
A small room (early reflections and a short tail) makes the effects sit together.

Effects are mono 16-bit WAV at 44.1 kHz (the game places them left or right on screen). Variants of
one effect are numbered (chop_0, chop_1...) and the game picks one at random. Ambience loops are
stereo OGG Vorbis, made seamless by crossfading their end into their start.
"""
import os, sys, subprocess, wave
import numpy as np
from scipy.signal import fftconvolve

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "sounds")
SR = 44100
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(1234)


def t(sec):
    return np.arange(int(sec * SR)) / SR


def noise(sec):
    return rng.standard_normal(int(sec * SR))


def filt(x, lo=None, hi=None, order=2):
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    if lo:
        f *= 1 / np.sqrt(1 + (lo / np.maximum(fr, 0.5)) ** (2 * order))
    if hi:
        f *= 1 / np.sqrt(1 + (fr / hi) ** (2 * order))
    return np.fft.irfft(f, len(x))


def peak(x, fc, q, gain):
    """A resonance at fc (a formant) added to x."""
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    bw = fc / q
    f *= 1 + gain * np.exp(-((fr - fc) / bw) ** 2)
    return np.fft.irfft(f, len(x))


def decay(n, tau, attack=0.0005):
    x = np.arange(n) / SR
    return np.clip(x / max(attack, 1e-5), 0, 1) * np.exp(-x / tau)


def modes(sec, parts, attack=0.0003):
    """Ringing modes: parts = [(freq, amp, decay s)]."""
    x = t(sec)
    out = np.zeros(len(x))
    for f, a, d in parts:
        if f < SR * 0.45:
            out += a * np.sin(2 * np.pi * f * x + rng.uniform(0, 6.28)) * np.exp(-x / d)
    return out * np.clip(x / attack, 0, 1)


def glide(fcurve):
    return 2 * np.pi * np.cumsum(fcurve) / SR


def harmonics(ph, weights):
    return sum(w * np.sin(k * ph) for k, w in enumerate(weights, 1))


def room(x, size=0.35, wet=0.2, bright=5000):
    """A small room: a few early reflections and a short diffuse tail."""
    n = int(size * SR)
    ir = np.zeros(n)
    ir[0] = 1.0
    for d, a in ((0.007, 0.5), (0.013, 0.35), (0.021, 0.28), (0.034, 0.2)):
        ir[int(d * SR)] += a
    tail = rng.standard_normal(n) * np.exp(-np.arange(n) / (n / 5)) * 0.12
    tail[: int(0.03 * SR)] = 0
    ir += filt(tail, hi=bright)
    y = fftconvolve(x, ir)
    y /= np.abs(y).max() + 1e-9
    xn = np.concatenate([x / (np.abs(x).max() + 1e-9), np.zeros(len(y) - len(x))])
    return xn * (1 - wet) + y * wet


def fade(x, ms_in=1.0, ms_out=25.0):
    x = x.copy()
    a = int(ms_in / 1000 * SR); b = int(ms_out / 1000 * SR)
    if a: x[:a] *= np.linspace(0, 1, a)
    if b: x[-b:] *= np.linspace(1, 0, b)
    return x


def trim(x, floor_db=-60):
    """Cuts the silent end."""
    lim = np.abs(x).max() * 10 ** (floor_db / 20)
    idx = np.nonzero(np.abs(x) > lim)[0]
    return x[: idx[-1] + int(0.02 * SR)] if len(idx) else x


def save(name, x, level=0.8):
    """Short effects as WAV (quick to start); those longer than 1.2 s as OGG Vorbis (small)."""
    x = trim(x)
    x = fade(x / (np.abs(x).max() + 1e-9) * level)
    for ext in (".wav", ".ogg"):
        if os.path.exists(os.path.join(OUT, name + ext)):
            os.remove(os.path.join(OUT, name + ext))
    wav = os.path.join(OUT, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
    if len(x) > 1.2 * SR:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", os.path.join(OUT, name + ".ogg")], check=True)
        os.remove(wav)


def save_loop(name, L, R, level=0.6, xf=2.0):
    """A seamless stereo loop: the last xf seconds crossfade into the start."""
    n = int(xf * SR)
    outs = []
    for ch in (L, R):
        head, body, tail = ch[:n], ch[n:-n], ch[-n:]
        w = np.sin(np.linspace(0, np.pi / 2, n)) ** 2
        outs.append(np.concatenate([tail * (1 - w) + head * w, body]))
    st = np.stack(outs, 1)
    st = st / (np.abs(st).max() + 1e-9) * level
    wav = os.path.join(OUT, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(st, -1, 1) * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "2", os.path.join(OUT, name + ".ogg")], check=True)
    os.remove(wav)


def mix(*parts, n=None):
    n = n or max(int(at * SR) + len(p) for p, at in parts)
    out = np.zeros(n)
    for p, at in parts:
        i = int(at * SR)
        m = min(len(p), n - i)
        if m > 0:
            out[i:i + m] += p[:m]
    return out


def place(dst, src, at):
    i = int(at * SR)
    m = min(len(src), len(dst) - i)
    if m > 0 and i >= 0:
        dst[i:i + m] += src[:m]


# ---------------------------------------------------------------- building blocks
def wood_knock(f, sec=0.25, hard=0.5):
    body = modes(sec, [(f, 1.0, 0.035), (f * 2.3, 0.5, 0.02), (f * 3.9, 0.25, 0.012), (f * 5.4, 0.12, 0.008)])
    tr = filt(noise(sec), 300, 2500 + 4000 * hard) * decay(int(sec * SR), 0.006)
    return body + tr * (0.6 + hard)


def metal_hit(f, sec=0.9, ring=0.35, ratios=(1, 2.32, 4.25, 6.1, 8.3, 10.6)):
    parts = [(f * r, 1.0 / (1 + i * 0.6), ring / (1 + i * 0.45)) for i, r in enumerate(ratios)]
    body = modes(sec, parts, 0.0002)
    tr = filt(noise(sec), 2000, 12000) * decay(int(sec * SR), 0.003)
    return body + tr * 0.5


def stone_hit(f, sec=0.3):
    parts = [(f * r * rng.uniform(0.97, 1.03), rng.uniform(0.3, 1.0), rng.uniform(0.01, 0.035)) for r in (1, 1.7, 2.6, 3.4, 4.8, 6.3)]
    body = modes(sec, parts, 0.0002)
    grit = filt(noise(sec), 1500, 9000) * decay(int(sec * SR), 0.03) * (1 + 0.8 * (rng.random(int(sec * SR)) > 0.97))
    return body * 0.6 + grit


def chirp(f0, f1, sec, harm=(1, 0.2), am=0.0, am_rate=0.0):
    x = t(sec)
    fc = f0 + (f1 - f0) * (x / sec)
    s = harmonics(glide(fc), harm)
    e = np.sin(np.pi * x / sec) ** 2
    if am:
        e *= 1 - am + am * (0.5 + 0.5 * np.sin(2 * np.pi * am_rate * x))
    return s * e


def voice(f_curve, formants, sec, breath=0.08, nasal=0.0):
    """A voiced call: a buzzy source at f_curve through formant resonances (animals, shouts)."""
    n = int(sec * SR)
    ph = glide(f_curve[:n])
    src = harmonics(ph, [1 / k ** 0.9 for k in range(1, 30)])
    src += filt(rng.standard_normal(n), 300, 6000) * breath
    out = np.zeros(n)
    for fc, q, g in formants:
        out += peak(src, fc, q, g) - src
    out += src * (0.15 + nasal)
    return filt(out, 60, 7000)


# ---------------------------------------------------------------- interface
def ui():
    save("click", wood_knock(1900, 0.06, 0.9) * decay(int(0.06 * SR), 0.015), 0.4)
    k = lambda f: wood_knock(f, 0.25, 0.4)
    save("place", room(mix((k(190), 0), (k(160), 0.1)), 0.3, 0.2), 0.7)
    # a site that can't go here: a dull double thud, low and short
    save("deny", room(mix((wood_knock(110, 0.2, 0.1), 0), (wood_knock(95, 0.25, 0.1), 0.09)), 0.25, 0.15), 0.6)
    # windows: a soft paper slide up (open) and down (close)
    for name, lo, hi in (("open", 900, 3500), ("close", 3500, 900)):
        x = t(0.18)
        sw = filt(noise(0.18), 300, 7000)
        f = lo + (hi - lo) * x / 0.18
        sw = peak(sw, (lo + hi) / 2, 2.0, 2.0) * np.sin(np.pi * x / 0.18) ** 1.5
        save("win_" + name, sw * (0.4 + 0.6 * (f / max(lo, hi))), 0.25)
    # a road laid: gravel crunched under a spade
    for i in range(3):
        n = int(0.22 * SR)
        g = filt(noise(0.22), 700, 6000) * (rng.random(n) > 0.6) * decay(n, 0.06, 0.004)
        save("road_%d" % i, room(g + wood_knock(240 + i * 30, 0.22, 0.2) * 0.3, 0.2, 0.15), 0.45)
    # done: a building is finished: a bright rising chime on a small bell
    bell = lambda f, d=1.4: modes(d, [(f, 1, 0.6), (f * 2.0, 0.35, 0.4), (f * 2.76, 0.25, 0.3), (f * 5.4, 0.08, 0.15)])
    save("done", room(mix(*[(bell(f), i * 0.09) for i, f in enumerate([523.25, 659.25, 783.99, 1046.5])]), 0.6, 0.25), 0.55)
    big = lambda f: modes(3.0, [(f * r, a, d) for r, a, d in ((0.5, 0.5, 2.2), (1, 1, 1.6), (1.183, 0.45, 1.1), (1.506, 0.35, 0.9), (2.0, 0.3, 0.8), (2.514, 0.18, 0.5), (3.011, 0.1, 0.35))])
    save("research", room(mix((big(392), 0), (big(493.9), 0.14), (big(587.3), 0.28)), 0.8, 0.3), 0.55)
    coin = lambda f: metal_hit(f, 0.4, 0.08, (1, 2.4, 4.1, 5.9))
    save("coin", mix((coin(2200), 0), (coin(2750), 0.07), (coin(2450), 0.15), (coin(2600), 0.21)), 0.45)
    save("good", room(mix((bell(659.25), 0), (bell(880), 0.12), (bell(1318.5, 1.0), 0.24)), 0.6, 0.25), 0.45)
    # bad news: a low falling pair on a muffled bell
    low = lambda f: filt(modes(1.6, [(f, 1, 0.8), (f * 2.0, 0.4, 0.5), (f * 2.4, 0.3, 0.4), (f * 3.0, 0.2, 0.3)]), hi=1800)
    save("bad", room(mix((low(220), 0), (low(196), 0.2)), 0.6, 0.3), 0.55)
    # alert: an enemy attacks: a horn call, two notes
    def horn(f, sec):
        x = t(sec)
        fc = f * (1 - 0.03 * np.exp(-x / 0.05))
        ph = glide(fc)
        br = np.clip(x / 0.1, 0, 1)
        s = sum(w * br ** (k - 1) * np.sin(k * ph) for k, w in enumerate([1, 0.75, 0.6, 0.45, 0.3, 0.18, 0.1], 1))
        return filt(s, hi=3000) * np.clip(x / 0.05, 0, 1) * np.clip((sec - x) / 0.2, 0, 1)
    save("alert", room(mix((horn(233, 0.55), 0), (horn(311, 0.95), 0.5)), 0.8, 0.35), 0.65)
    w = filt(noise(2.2), 250, 1500) * np.sin(np.pi * t(2.2) / 2.2) ** 2 * 0.4
    save("season", room(mix((w, 0), (bell(1318.5, 1.6), 0.35), (bell(1568, 1.6), 0.6), (bell(2093, 1.4), 0.85)), 0.6, 0.3), 0.5)


# ---------------------------------------------------------------- work
def work():
    # chop: an axe into a trunk: a woody thunk with a short crack
    for i in range(4):
        f = rng.uniform(120, 175)
        th = wood_knock(f, 0.3, 0.3)
        cr = filt(noise(0.3), 900, 4500) * decay(int(0.3 * SR), 0.018)
        save("chop_%d" % i, room(th * 0.8 + cr, 0.3, 0.18), 0.6)
    # hammer: smith's hammer on an anvil
    for i in range(4):
        f = rng.uniform(1050, 1450)
        save("hammer_%d" % i, room(metal_hit(f, 0.8, rng.uniform(0.25, 0.4)), 0.3, 0.2), 0.45)
    # pick: a pick on stone
    for i in range(4):
        save("pick_%d" % i, room(stone_hit(rng.uniform(700, 1100), 0.3), 0.25, 0.15), 0.5)
    # saw: two or three strokes of a saw through a log
    for i in range(3):
        sec = rng.uniform(0.9, 1.3)
        x = t(sec)
        per = rng.uniform(0.38, 0.5)
        stroke = np.abs(np.sin(np.pi * x / per)) ** 0.6
        teeth = 1 + 0.7 * np.sin(2 * np.pi * rng.uniform(80, 120) * x) * (np.sin(2 * np.pi * x / per) > 0)
        s = filt(noise(sec), 1300, 6500) * stroke * teeth
        save("saw_%d" % i, room(peak(s, 3200, 3, 1.5), 0.25, 0.15), 0.38)
    # build: knocks of a mallet on a building site
    for i in range(3):
        base = rng.uniform(360, 460)
        knocks = [(wood_knock(base * rng.uniform(0.95, 1.05), 0.2, 0.5), j * rng.uniform(0.2, 0.26)) for j in range(3)]
        save("build_%d" % i, room(mix(*knocks), 0.3, 0.2), 0.5)
    # dig: a spade into earth (clay pits, farms)
    for i in range(3):
        n = int(0.4 * SR)
        thud = filt(noise(0.4), 80, 900) * decay(n, 0.05, 0.003)
        grit = filt(noise(0.4), 1200, 5000) * decay(n, 0.12, 0.01) * (rng.random(n) > 0.75) * 0.6
        save("dig_%d" % i, room(thud + grit, 0.25, 0.15), 0.5)
    # splash: a fisher's net or line in the water
    for i in range(3):
        n = int(0.6 * SR)
        x = t(0.6)
        sp = filt(noise(0.6), 600, 7000) * decay(n, 0.12, 0.004)
        bub = np.zeros(n)
        for _ in range(8):
            f = rng.uniform(500, 1400)
            b = np.sin(glide(f * (1 + 0.6 * t(0.06) / 0.06))) * decay(int(0.06 * SR), 0.02)
            place(bub, b * rng.uniform(0.1, 0.3), rng.uniform(0.03, 0.4))
        save("splash_%d" % i, sp + bub, 0.45)
    # creak: a windmill or a mill wheel turning
    for i in range(2):
        sec = rng.uniform(0.7, 1.0)
        x = t(sec)
        f = rng.uniform(140, 200) * (1 + 0.15 * np.sin(np.pi * x / sec))
        pulses = (np.sin(glide(f)) > 0.6).astype(float)
        cr = filt(pulses * (1 + 0.3 * rng.standard_normal(len(x))), 300, 3000)
        cr = peak(peak(cr, 900, 4, 2), 1700, 5, 1.5) * np.sin(np.pi * x / sec) ** 1.2
        save("creak_%d" % i, room(cr, 0.3, 0.2), 0.3)
    # bell: a chapel bell tolls
    x = t(5.0)
    tb = sum(a * np.sin(2 * np.pi * 220 * r * x) * np.exp(-x / d) for r, a, d in ((0.5, 0.7, 3.5), (1, 1, 2.6), (1.19, 0.5, 1.8), (1.5, 0.4, 1.5), (2.0, 0.35, 1.2), (2.51, 0.2, 0.8), (2.98, 0.15, 0.6), (4.07, 0.08, 0.4)))
    tb *= np.clip(x / 0.002, 0, 1)
    save("bell", room(mix((tb, 0), (metal_hit(660, 0.2, 0.05) * 0.2, 0)), 1.0, 0.3), 0.5)
    # demolish: timbers falling and rubble
    x = t(1.6)
    rub = filt(noise(1.6), 60, 1200) * np.exp(-x / 0.5)
    for _ in range(14):
        place(rub, stone_hit(rng.uniform(300, 700), 0.2) * rng.uniform(0.2, 0.6), rng.uniform(0.05, 1.0))
    thud = modes(1.6, [(62, 1, 0.3), (95, 0.5, 0.2)])
    save("demolish", room(rub + thud, 0.5, 0.25), 0.6)


# ---------------------------------------------------------------- nature
def nature():
    # a tree falls: the trunk creaks, cracks, then crashes with its branches
    for i in range(2):
        sec = 2.8
        out = np.zeros(int(sec * SR))
        x = t(0.9)
        f = 95 * (1 + 0.5 * x / 0.9)
        cr = filt((np.sin(glide(f)) > 0.7).astype(float) * (1 + 0.4 * rng.standard_normal(len(x))), 200, 2500)
        place(out, peak(cr, 700, 4, 2) * np.clip(x / 0.3, 0, 1) * 0.35, 0)
        place(out, filt(noise(0.15), 600, 6000) * decay(int(0.15 * SR), 0.03) * 1.2, 0.9)
        n = int(1.8 * SR)
        rust = filt(noise(1.8), 1500, 9000) * decay(n, 0.5, 0.05) * 0.6
        boom = modes(1.8, [(55, 1.0, 0.25), (80, 0.6, 0.18), (130, 0.3, 0.1)]) + filt(noise(1.8), 60, 600) * decay(n, 0.15, 0.003)
        place(out, rust + boom * 1.3, 1.0)
        save("treefall_%d" % i, room(out, 0.6, 0.25), 0.7)
    # thunder: a crack then a long rumble
    for i in range(3):
        sec = rng.uniform(3.5, 5.0)
        x = t(sec)
        rum = filt(noise(sec), 20, 260) * (np.exp(-x / rng.uniform(1.0, 1.6)) * (1 + 0.6 * np.sin(2 * np.pi * x * rng.uniform(1.5, 3))))
        crack = filt(noise(sec), 400, 5000) * decay(len(x), 0.08, 0.002) * (0.8 if i == 0 else 0.3)
        save("thunder_%d" % i, room(rum * 1.6 + crack, 0.8, 0.3, 2000), 0.75)
    # fire: a building catches: a whoosh
    x = t(1.4)
    wh = filt(noise(1.4), 150, 2500) * np.sin(np.pi * np.clip(x / 1.4, 0, 1)) ** 2
    save("ignite", room(wh, 0.4, 0.2), 0.55)


# ---------------------------------------------------------------- animals
def animals():
    # cow: a low moo through an "oo" mouth opening to "aa"
    for i in range(2):
        sec = rng.uniform(1.2, 1.6)
        n = int(sec * SR)
        x = np.arange(n) / SR
        f = rng.uniform(95, 120) * (1 + 0.15 * np.sin(np.pi * x / sec)) * (1 - 0.1 * x / sec)
        v = voice(f, [(350, 4, 3), (700 + 300 * 0, 5, 2), (2400, 6, 0.6)], sec, 0.05)
        save("cow_%d" % i, v * np.sin(np.pi * x / sec) ** 0.6, 0.5)
    # sheep: a bleat, its voice shaking
    for i in range(2):
        sec = rng.uniform(0.6, 0.85)
        n = int(sec * SR)
        x = np.arange(n) / SR
        f = rng.uniform(330, 420) * (1 + 0.04 * np.sin(2 * np.pi * 17 * x))
        v = voice(f, [(800, 5, 2.5), (1300, 6, 2), (2600, 6, 1)], sec, 0.1, nasal=0.2)
        v *= (0.65 + 0.35 * np.sin(2 * np.pi * 17 * x)) * np.sin(np.pi * x / sec) ** 0.5
        save("sheep_%d" % i, v, 0.45)
    # pig: two or three short grunts
    for i in range(2):
        out = np.zeros(int(0.9 * SR))
        for j in range(rng.integers(2, 4)):
            sec = rng.uniform(0.12, 0.2)
            n = int(sec * SR)
            x = np.arange(n) / SR
            f = rng.uniform(70, 95) * (1 + 0.3 * x / sec)
            g = voice(f, [(400, 3, 3), (1100, 4, 2)], sec, 0.4)
            g *= np.sin(np.pi * x / sec) * (1 + 0.5 * (rng.random(n) > 0.5))
            place(out, g, j * rng.uniform(0.22, 0.3))
        save("pig_%d" % i, out, 0.45)
    # a wolf howls far off
    sec = 2.6
    n = int(sec * SR)
    x = np.arange(n) / SR
    f = 380 + 220 * np.sin(np.pi * np.clip(x / 1.2, 0, 1)) ** 0.7 * (x < 1.2) + (600 - 180 * np.clip((x - 1.2) / 1.4, 0, 1)) * (x >= 1.2)
    f = filt(f, hi=6) + 380 * 0
    how = harmonics(glide(f * (1 + 0.006 * np.sin(2 * np.pi * 5 * x))), [1, 0.3, 0.12, 0.05]) * np.sin(np.pi * x / sec) ** 0.8
    save("wolf", room(filt(how, hi=2500), 1.0, 0.45, 2500), 0.4)
    # a horse snorts and stamps (carts, cavalry)
    n = int(0.6 * SR)
    sn = filt(noise(0.6), 300, 2500) * decay(n, 0.12, 0.02) * (1 + 0.6 * np.sin(2 * np.pi * 28 * t(0.6)))
    save("horse", room(sn + mix((wood_knock(170, 0.15, 0.3), 0.35), n=n) * 0.6, 0.3, 0.2), 0.4)


# ---------------------------------------------------------------- war
def war():
    for i in range(4):
        f = rng.uniform(1900, 2700)
        cl = metal_hit(f, 0.6, rng.uniform(0.08, 0.14), (1, 1.47, 2.8, 3.9, 5.2))
        save("clash_%d" % i, room(cl, 0.35, 0.2), 0.45)
    for i, (lo, crack, tail) in enumerate(((500, 0.5, 0.35), (1400, 0.9, 0.22))):
        x = t(1.2)
        boom = filt(noise(1.2), 30, lo) * np.exp(-x / tail) * 1.6
        cr = filt(noise(1.2), 1500, 9000) * np.exp(-x / 0.025) * crack
        save("shot_%d" % i, room(boom + cr, 0.9, 0.3, 3000), 0.7)
    # a column marching: boots on a road, drum taps
    sec = 2.0
    out = np.zeros(int(sec * SR))
    for k in range(16):
        step = filt(noise(0.08), 200, 3000) * decay(int(0.08 * SR), 0.018) * rng.uniform(0.5, 1.0)
        place(out, step, k * 0.125 + rng.uniform(0, 0.02))
    for k in range(4):
        place(out, wood_knock(260, 0.2, 0.7) * 0.7, k * 0.5)
    save("march", room(out, 0.3, 0.2), 0.4)
    # a catapult: the arm's thump and the stone landing
    n = int(1.2 * SR)
    th = modes(1.2, [(70, 1, 0.12), (140, 0.5, 0.08)]) + filt(noise(1.2), 100, 1500) * decay(n, 0.05)
    save("catapult", room(mix((th, 0), (stone_hit(500, 0.3) * 0.7, 0.75)), 0.5, 0.25), 0.6)


# ---------------------------------------------------------------- ambience loops (stereo OGG)
def ambience():
    L = 24.0
    n = int((L + 2) * SR)
    x = np.arange(n) / SR

    def two(f):
        return f(), f()

    def birds(count, lo, hi, out_l, out_r, busy=1.0):
        for _ in range(int(count * busy)):
            at = rng.uniform(0.2, L)
            f0 = rng.uniform(lo, hi)
            pan = rng.uniform(-1, 1)
            for c in range(rng.integers(2, 7)):
                d = rng.uniform(0.04, 0.13)
                ch = chirp(f0 * rng.uniform(0.9, 1.1), f0 * rng.uniform(0.75, 1.35), d, (1, 0.15, 0.05)) * rng.uniform(0.15, 0.35)
                when = at + c * rng.uniform(0.08, 0.17)
                place(out_l, ch * np.cos((pan + 1) * np.pi / 4), when)
                place(out_r, ch * np.sin((pan + 1) * np.pi / 4), when)

    # meadow: a soft breeze in the grass, larks and finches
    l, r = two(lambda: filt(noise(L + 2), 90, 700) * (0.6 + 0.4 * np.sin(2 * np.pi * x / 7.3 + rng.uniform(0, 6))) * 0.3)
    birds(30, 2800, 4800, l, r)
    save_loop("amb_meadow", l, r, 0.5)
    # forest: leaves rustling, more birds, a woodpecker now and then, a cuckoo far off
    l, r = two(lambda: filt(noise(L + 2), 400, 5000) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * x / 5.1 + rng.uniform(0, 6)))) * 0.18)
    birds(48, 2200, 5200, l, r)
    for _ in range(3):
        at = rng.uniform(1, L - 2)
        for k in range(rng.integers(8, 14)):
            tap = wood_knock(rng.uniform(900, 1100), 0.05, 0.9) * 0.18
            place(l if rng.random() < 0.5 else r, tap, at + k * 0.055)
    for at in (rng.uniform(3, 9), rng.uniform(14, 20)):
        for k, f in enumerate((720, 590)):
            c = chirp(f, f * 0.98, 0.35, (1, 0.05)) * 0.12
            place(l, c * 0.4, at + k * 0.45); place(r, c * 0.25, at + k * 0.45 + 0.01)
    save_loop("amb_forest", l, r, 0.5)
    # shore: waves rolling in and drawing back
    l, r = np.zeros(n), np.zeros(n)
    at = 0.0
    while at < L + 2:
        per = rng.uniform(5.0, 8.0)
        m = int(per * SR)
        xx = np.arange(m) / SR
        swell = np.clip(xx / (per * 0.35), 0, 1) ** 2 * np.exp(-np.maximum(0, xx - per * 0.35) / (per * 0.25))
        hiss = filt(rng.standard_normal(m), 250, 4500) * swell
        back = filt(rng.standard_normal(m), 1500, 9000) * np.exp(-np.maximum(0, xx - per * 0.45) / 0.8) * (xx > per * 0.4) * 0.25
        pan = rng.uniform(-0.4, 0.4)
        place(l, (hiss + back) * np.cos((pan + 1) * np.pi / 4), at)
        place(r, (hiss + back) * np.sin((pan + 1) * np.pi / 4), at + 0.01)
        at += per * rng.uniform(0.55, 0.75)
    rumble = filt(noise(L + 2), 30, 200) * 0.6
    save_loop("amb_shore", l + rumble, r + rumble * 0.9, 0.5)
    # winter wind: gusty, with a whistle
    def wind(lo, hi, wh):
        g = 0.45 + 0.35 * np.sin(2 * np.pi * x / rng.uniform(4, 6) + rng.uniform(0, 6)) + 0.2 * np.sin(2 * np.pi * x / 1.7 + rng.uniform(0, 6))
        w = filt(rng.standard_normal(n), lo, hi) * g
        whistle = np.sin(glide(wh + wh * 0.18 * np.sin(2 * np.pi * x / 3.1 + rng.uniform(0, 6)))) * 0.05 * g ** 2
        return w + whistle
    save_loop("amb_wind", wind(150, 1100, 700), wind(150, 1100, 760), 0.5)
    # mountain wind: thinner and higher, howling round rocks
    save_loop("amb_mountain", wind(300, 2500, 1100) * 0.9, wind(300, 2500, 1250) * 0.9, 0.45)
    # rain: a steady hiss with drops on leaves and roofs
    def rain(drops, heavy):
        s = filt(rng.standard_normal(n), 700, 8000) * (0.35 + heavy * 0.25)
        for _ in range(drops):
            d = modes(0.02, [(rng.uniform(1800, 5000), 1, 0.004)]) * rng.uniform(0.05, 0.25)
            place(s, d, rng.uniform(0, L + 1.9))
        return s + filt(rng.standard_normal(n), 60, 400) * heavy * 0.5
    save_loop("amb_rain", rain(2500, 0.0), rain(2500, 0.0), 0.5)
    save_loop("amb_storm", rain(5000, 1.0), rain(5000, 1.0), 0.6)
    # town: a murmur of voices, far-off hammers, cart wheels, a dog
    def town():
        m = filt(rng.standard_normal(n), 120, 900) * (0.7 + 0.3 * np.sin(2 * np.pi * x / 5.0 + rng.uniform(0, 6)))
        m = peak(peak(m, 450, 3, 1.5), 1100, 4, 1.0) * 0.35
        for _ in range(16):
            place(m, metal_hit(rng.uniform(1100, 1500), 0.4, 0.15) * 0.06, rng.uniform(0, L))
        for _ in range(10):
            place(m, wood_knock(rng.uniform(300, 500), 0.15, 0.4) * 0.12, rng.uniform(0, L))
        for _ in range(2):
            at = rng.uniform(0, L - 3)
            rattle = filt(rng.standard_normal(int(2.5 * SR)), 200, 1500) * (rng.random(int(2.5 * SR)) > 0.9) * 0.15
            place(m, rattle * np.sin(np.pi * t(2.5) / 2.5), at)
        return m
    save_loop("amb_town", town(), town(), 0.45)
    # battle: many swords and shouts in the distance
    def battle():
        b = filt(rng.standard_normal(n), 200, 1500) * 0.25 * (0.7 + 0.3 * np.sin(2 * np.pi * x / 3.3 + rng.uniform(0, 6)))
        for _ in range(110):
            place(b, metal_hit(rng.uniform(1700, 2800), 0.4, 0.07, (1, 1.47, 2.8, 3.9)) * rng.uniform(0.05, 0.2), rng.uniform(0, L + 1.5))
        for _ in range(14):
            sec = rng.uniform(0.3, 0.6)
            f = rng.uniform(170, 260) * (1 + 0.2 * np.sin(np.pi * t(sec) / sec))
            place(b, filt(voice(f, [(700, 4, 2), (1200, 5, 1.5)], sec, 0.3), hi=2500) * np.sin(np.pi * t(sec) / sec) * 0.05, rng.uniform(0, L))
        return filt(b, hi=4500)
    save_loop("amb_battle", battle(), battle(), 0.5)
    # fire: a building burning: crackles over a roar
    def fire():
        f = filt(rng.standard_normal(n), 60, 700) * (0.7 + 0.3 * np.sin(2 * np.pi * x / 2.3 + rng.uniform(0, 6))) * 0.4
        for _ in range(900):
            c = filt(rng.standard_normal(200), 1500, 9000) * decay(200, 0.0015) * rng.uniform(0.1, 0.7)
            place(f, c, rng.uniform(0, L + 1.9))
        return f
    save_loop("amb_fire", fire(), fire(), 0.55)
    # summer: crickets in the grass
    def crickets():
        c = np.zeros(n)
        for _ in range(5):
            f = rng.uniform(4200, 5200)
            rate = rng.uniform(18, 26)
            on = (np.sin(2 * np.pi * rate * x + rng.uniform(0, 6)) > 0.2) * (np.sin(2 * np.pi * x / rng.uniform(2, 4) + rng.uniform(0, 6)) > -0.3)
            c += np.sin(2 * np.pi * f * x) * on * rng.uniform(0.03, 0.08)
        return filt(c, 3000, 8000) + filt(rng.standard_normal(n), 90, 600) * 0.06
    save_loop("amb_summer", crickets(), crickets(), 0.35)


# ---------------------------------------------------------------- voices (build 63)
def voices():
    """A word from the worker when you pick a building: "aye?" and "hm" murmurs, low (soldiers), middle
    (workers) and high (artisans), two vowels gliding into each other."""
    A = [(750, 5, 3.0), (1200, 6, 2.2), (2600, 7, 0.8)]     # "a"
    E = [(400, 5, 3.0), (2000, 7, 1.8), (2700, 7, 0.9)]     # "e"/"i"
    O = [(450, 5, 3.0), (850, 6, 2.0), (2500, 7, 0.5)]      # "o"
    M = [(280, 4, 3.0), (1100, 5, 0.5), (2400, 6, 0.2)]     # "m"
    def word(f0, v1, v2, sec, rise):
        n = int(sec * SR)
        x = t(sec)
        f = f0 * (1 + rise * (x / sec) ** 2) * (1 + 0.01 * np.sin(2 * np.pi * 5.5 * x))
        a = voice(f, v1, sec, 0.05)
        b = voice(f, v2, sec, 0.05)
        w = np.clip((x / sec - 0.35) / 0.3, 0, 1)
        env = np.clip(x / 0.03, 0, 1) * np.clip((sec - x) / 0.08, 0, 1)
        return (a * (1 - w) + b * w) * env
    save("voice_low", room(word(105, A, E, 0.38, -0.15), 0.25, 0.15), 0.5)
    save("voice_mid", room(word(150, M, A, 0.34, 0.12), 0.25, 0.15), 0.5)
    save("voice_high", room(word(215, O, E, 0.32, 0.18), 0.25, 0.15), 0.5)


GROUPS = {"ui": ui, "voices": voices, "work": work, "nature": nature, "animals": animals, "war": war, "ambience": ambience}

if __name__ == "__main__":
    want = sys.argv[1:] or list(GROUPS)
    for g in want:
        GROUPS[g]()
    files = sorted(f for f in os.listdir(OUT) if f.endswith((".wav", ".ogg")))
    print(len(files), "sounds in", OUT)
