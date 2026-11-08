#!/usr/bin/env python3
"""Generate Hearthlands' sound effects and ambience loops into ../sounds (16-bit mono WAV).

Usage:  python3 tools/make_sounds.py

Every sound is synthesised here from sine waves, filtered noise and envelopes, so there is nothing to
license. A little room echo (a short decaying noise impulse) makes them sit together. Loops are made
seamless by crossfading their end into their start.
"""
import os, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "sounds")
SR = 22050
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(1234)


def t(sec):
    return np.arange(int(sec * SR)) / SR


def env(n, a=0.005, d=0.2, shape=4.0):
    """Attack then exponential decay over n samples."""
    x = np.arange(n) / SR
    att = np.clip(x / max(a, 1e-4), 0, 1)
    return att * np.exp(-x / max(d, 1e-4) * (shape / 4.0) * 4.0 / 4.0)


def lowpass(x, cut):
    """One-pole low-pass, run twice for a softer slope."""
    a = np.exp(-2 * np.pi * cut / SR)
    for _ in range(2):
        y = np.empty_like(x)
        acc = 0.0
        for i in range(len(x)):
            acc = (1 - a) * x[i] + a * acc
            y[i] = acc
        x = y
    return x


def lowpass_fast(x, cut):
    """Low-pass by FFT (for long sounds)."""
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    f *= 1 / (1 + (fr / cut) ** 4)
    return np.fft.irfft(f, len(x))


def bandpass_fast(x, lo, hi):
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    f *= (1 / (1 + (lo / np.maximum(fr, 1)) ** 4)) * (1 / (1 + (fr / hi) ** 4))
    return np.fft.irfft(f, len(x))


def noise(sec):
    return rng.standard_normal(int(sec * SR))


def room(x, size=0.18, wetness=0.18):
    """A small wooden room: convolve with a short burst of decaying noise."""
    n = int(size * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (n / 5))
    ir = lowpass_fast(ir, 3000)
    ir /= np.abs(ir).sum() / 6
    wet = np.zeros(len(x) + n)
    c = np.convolve(x, ir)
    wet[: len(c)] = c[: len(x) + n]
    out = np.zeros(len(x) + n)
    out[: len(x)] += x
    return out * (1 - wetness) + wet * wetness


def tone(freq, sec, partials=((1, 1.0),), decay=0.4, attack=0.004, detune=0.0):
    x = t(sec)
    s = sum(a * np.sin(2 * np.pi * freq * k * (1 + detune * k) * x) for k, a in partials)
    return s * env(len(x), attack, decay)


def norm(x, peak=0.8):
    m = np.abs(x).max()
    return x if m == 0 else x / m * peak


def fade(x, ms_in=2, ms_out=20):
    n_in = int(ms_in / 1000 * SR); n_out = int(ms_out / 1000 * SR)
    x = x.copy()
    if n_in: x[:n_in] *= np.linspace(0, 1, n_in)
    if n_out: x[-n_out:] *= np.linspace(1, 0, n_out)
    return x


def save(name, x, peak=0.8, looped=False):
    x = norm(x, peak) if looped else fade(norm(x, peak))
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data)


def mix(*parts):
    n = max(len(p) for p, _ in parts)
    out = np.zeros(n)
    for p, at in parts:
        i = int(at * SR)
        out[i: i + len(p)] += p[: n - i]
    return out


def pad(x, sec):
    n = int(sec * SR)
    return np.concatenate([x, np.zeros(max(0, n - len(x)))])[:n]


def loop(x, xf=1.0):
    """Makes x loop seamlessly: its last xf seconds are crossfaded into its start, then cut off."""
    n = int(xf * SR)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    w = np.linspace(0, 1, n)
    start = tail * (1 - w) + head * w
    return np.concatenate([start, body])


# ---------------------------------------------------------------- interface
def ui():
    # click: a short wooden tick
    c = lowpass(noise(0.03), 4000) * env(int(0.03 * SR), 0.0005, 0.006) + tone(1800, 0.03, decay=0.008) * 0.4
    save("click", c, 0.45)
    # place: a building site is marked out: a soft double knock on wood
    k = lambda f: lowpass(noise(0.12), 1500) * env(int(0.12 * SR), 0.001, 0.025) + tone(f, 0.12, ((1, 1), (2.7, 0.3)), 0.03) * 0.8
    save("place", room(mix((k(180), 0), (k(150), 0.11))), 0.7)
    # done: a building is finished: a bright rising chime
    notes = [523.25, 659.25, 783.99, 1046.5]
    parts = [(tone(f, 0.9, ((1, 1), (2, 0.35), (3, 0.12)), 0.35), i * 0.09) for i, f in enumerate(notes)]
    save("done", room(mix(*parts), 0.25, 0.25), 0.6)
    # research: a warm bell chord
    bell = lambda f: tone(f, 2.2, ((1, 1), (2.76, 0.45), (5.4, 0.2), (8.9, 0.08)), 0.7, 0.002)
    save("research", room(mix((bell(392), 0), (bell(493.9), 0.12), (bell(587.3), 0.24)), 0.3, 0.3), 0.6)
    # coin: a merchant pays
    coin = lambda f: tone(f, 0.35, ((1, 1), (2.4, 0.5), (4.1, 0.3)), 0.09, 0.001)
    save("coin", mix((coin(2200), 0), (coin(2700), 0.07), (coin(2450), 0.15)), 0.5)
    # good news and bad news
    save("good", room(mix((tone(659.25, 0.8, ((1, 1), (2, 0.3)), 0.3), 0), (tone(880, 0.9, ((1, 1), (2, 0.3)), 0.35), 0.12)), 0.25, 0.25), 0.5)
    bad = mix((tone(220, 1.0, ((1, 1), (2, 0.5), (3, 0.25)), 0.45, 0.02), 0), (tone(207.6, 1.1, ((1, 1), (2, 0.5), (3, 0.25)), 0.5, 0.02), 0.18))
    save("bad", room(lowpass_fast(bad, 1800), 0.3, 0.3), 0.55)
    # alert: an enemy attacks: a horn call
    x = t(1.3)
    f = 233 * (1 + 0.03 * np.minimum(x / 0.08, 1))
    ph = 2 * np.pi * np.cumsum(f) / SR
    horn = sum(a * np.sin(k * ph) for k, a in ((1, 1), (2, 0.6), (3, 0.45), (4, 0.25), (5, 0.12)))
    horn *= np.clip(x / 0.06, 0, 1) * np.clip((1.3 - x) / 0.25, 0, 1)
    save("alert", room(lowpass_fast(horn, 2500), 0.35, 0.3), 0.65)
    # season: a breath of wind with a soft chime
    w = bandpass_fast(noise(2.0), 300, 1600) * np.sin(np.pi * t(2.0) / 2.0) ** 2 * 0.5
    save("season", room(mix((w, 0), (tone(1318.5, 1.4, ((1, 1), (2.76, 0.3)), 0.5), 0.3), (tone(1568, 1.4, ((1, 1), (2.76, 0.3)), 0.5), 0.55)), 0.3, 0.3), 0.5)


# ---------------------------------------------------------------- work
def work():
    # chop: an axe biting into wood: a thump plus a short woody crack
    for i, f in enumerate((140, 160, 125)):
        th = tone(f, 0.25, ((1, 1), (1.6, 0.4)), 0.05, 0.001)
        cr = bandpass_fast(noise(0.25), 800, 3500) * env(int(0.25 * SR), 0.0005, 0.02)
        save("chop_%d" % i, room(th + cr * 0.9, 0.12, 0.15), 0.6)
    # hammer: metal on metal: a clang with inharmonic partials
    for i, f in enumerate((1250, 1420, 1100)):
        cl = tone(f, 0.6, ((1, 1), (2.32, 0.6), (4.25, 0.35), (6.1, 0.2)), 0.12, 0.0005)
        hit = lowpass(noise(0.05), 5000) * env(int(0.05 * SR), 0.0002, 0.006)
        save("hammer_%d" % i, room(pad(cl, 0.6) + pad(hit, 0.6) * 0.8, 0.15, 0.2), 0.5)
    # pick: a pick striking stone: short, gritty, high
    for i, f in enumerate((900, 1050, 800)):
        st = tone(f, 0.25, ((1, 1), (1.9, 0.5), (3.3, 0.3)), 0.03, 0.0005)
        gr = bandpass_fast(noise(0.25), 1500, 6000) * env(int(0.25 * SR), 0.0005, 0.04)
        save("pick_%d" % i, room(st * 0.7 + gr, 0.12, 0.15), 0.5)
    # saw: two strokes of a saw
    x = t(0.9)
    stroke = np.abs(np.sin(np.pi * x / 0.45)) ** 0.7
    s = bandpass_fast(noise(0.9), 1200, 5000) * stroke * (1 + 0.5 * np.sin(2 * np.pi * 95 * x))
    save("saw", room(s, 0.12, 0.15), 0.4)
    # build: hammering on a building site: three wooden knocks
    k = lambda f: lowpass(noise(0.1), 2500) * env(int(0.1 * SR), 0.0005, 0.015) + tone(f, 0.1, ((1, 1), (2.3, 0.4)), 0.025) * 0.7
    save("build", room(mix((k(420), 0), (k(400), 0.22), (k(430), 0.44)), 0.15, 0.2), 0.5)
    # clash: swords in battle
    for i, f in enumerate((2100, 2500)):
        cl = tone(f, 0.5, ((1, 1), (1.47, 0.7), (2.8, 0.4), (3.9, 0.25)), 0.1, 0.0003)
        sc = bandpass_fast(noise(0.5), 2500, 8000) * env(int(0.5 * SR), 0.0003, 0.03)
        save("clash_%d" % i, room(cl + sc * 0.6, 0.15, 0.2), 0.45)
    # shots: a musket's boom (low, with a crackle) and a rifle's sharper crack
    for i, (lo, crack, tail) in enumerate(((500, 0.5, 0.35), (1400, 0.9, 0.22))):
        x = t(0.9)
        boom = lowpass_fast(noise(0.9), lo) * np.exp(-x / tail) * 1.6
        cr = bandpass_fast(noise(0.9), 1500, 7000) * np.exp(-x / 0.03) * crack
        save("shot_%d" % i, room(boom + cr, 0.35, 0.3), 0.7)
    # demolish: timbers falling and rubble
    x = t(1.4)
    rub = lowpass_fast(noise(1.4), 900) * np.exp(-x / 0.45) * (1 + 0.6 * (rng.random(len(x)) > 0.995))
    thud = tone(70, 1.4, ((1, 1), (1.5, 0.5)), 0.2, 0.002)
    save("demolish", room(rub + thud * 0.8, 0.25, 0.25), 0.6)


# ---------------------------------------------------------------- ambience (seamless loops)
def ambience():
    L = 12.0
    # meadow: a soft breeze with birdsong here and there
    x = t(L + 1)
    breeze = bandpass_fast(noise(L + 1), 90, 500) * (0.6 + 0.4 * np.sin(2 * np.pi * x / 6.5)) * 0.25
    birds = np.zeros(len(x))
    for _ in range(14):
        at = rng.uniform(0.2, L)
        f0 = rng.uniform(2600, 4200)
        n_ch = rng.integers(2, 6)
        for c in range(n_ch):
            d = rng.uniform(0.05, 0.12)
            tt = t(d)
            sweep = f0 * (1 + rng.uniform(-0.25, 0.3) * tt / d)
            ph = 2 * np.pi * np.cumsum(sweep) / SR
            chirp = np.sin(ph) * np.sin(np.pi * tt / d) ** 2
            i = int((at + c * rng.uniform(0.09, 0.16)) * SR)
            if i + len(chirp) < len(birds):
                birds[i: i + len(chirp)] += chirp * rng.uniform(0.15, 0.35)
    save("amb_meadow", loop(breeze + birds * 0.5), 0.5, looped=True)
    # wind: cold, gusty winter wind
    w = bandpass_fast(noise(L + 1), 150, 1100)
    gust = 0.45 + 0.35 * np.sin(2 * np.pi * x / 4.3) + 0.2 * np.sin(2 * np.pi * x / 1.7 + 1)
    whistle = np.sin(2 * np.pi * np.cumsum(700 + 120 * np.sin(2 * np.pi * x / 3.1)) / SR) * 0.04 * gust
    save("amb_wind", loop(w * gust + whistle), 0.5, looped=True)
    # rain: a steady hiss with drops
    r = bandpass_fast(noise(L + 1), 800, 7000) * 0.35
    drops = np.zeros(len(x))
    for _ in range(900):
        i = rng.integers(0, len(x) - 400)
        drops[i: i + 400] += tone(rng.uniform(1800, 4500), 400 / SR, decay=0.004, attack=0.0002) * rng.uniform(0.05, 0.25)
    save("amb_rain", loop(r + drops), 0.5, looped=True)
    # town: distant murmur and the odd far-off knock
    m = bandpass_fast(noise(L + 1), 80, 350) * (0.7 + 0.3 * np.sin(2 * np.pi * x / 5.0))
    knocks = np.zeros(len(x))
    for _ in range(10):
        i = rng.integers(0, len(x) - 3000)
        knocks[i: i + 2205] += lowpass(noise(0.1), 900) * env(2205, 0.001, 0.02) * 0.3
    save("amb_town", loop(m * 0.4 + knocks), 0.4, looped=True)


if __name__ == "__main__":
    ui(); work(); ambience()
    print("sounds in", OUT, sorted(f for f in os.listdir(OUT) if f.endswith(".wav")))
