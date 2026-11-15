#!/usr/bin/env python3
"""Compose and render Hearthlands' music into ../music (OGG Vorbis, stereo, 44.1 kHz).

Usage:  python3 tools/make_music.py [name ...]      (no names: every piece)
Needs numpy, scipy and ffmpeg (with libvorbis).

Everything is synthesised here, so there is nothing to license:
- plucked strings (harp, lute) by the Karplus-Strong method,
- a recorder and a fiddle from harmonics with vibrato and breath or bow noise,
- a horn whose tone brightens as it swells, a drone of a root and a fifth,
- frame and war drums from a falling pitch and a slap of noise, bells from inharmonic partials.
The tunes are written out note by note below, in the old modes (Dorian, Mixolydian, Aeolian...),
with chords under them; the harp plays the chords as broken arpeggios. A hall echo (a convolution
with decaying stereo noise) puts the players in one room.

Pieces: four calm ones played in turn in peacetime (with silence between, as in The Settlers), a war
theme for when your land is attacked, and short cues for a new age, victory and defeat.
"""
import os, sys, subprocess, wave
import numpy as np
from scipy.signal import fftconvolve

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "music")
SR = 44100
os.makedirs(OUT, exist_ok=True)

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def freq(name):
    """'A4' -> 440, 'Bb3', 'F#5'..."""
    n = NOTE[name[0]]
    rest = name[1:]
    while rest and rest[0] in "#b":
        n += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    midi = n + 12 * (int(rest) + 1)
    return 440.0 * 2 ** ((midi - 69) / 12)


def tt(sec):
    return np.arange(int(sec * SR)) / SR


def lp(x, cut, order=2):
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    f *= 1 / (1 + (fr / cut) ** (2 * order)) ** 0.5
    return np.fft.irfft(f, len(x))


def bp(x, lo, hi):
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    f *= (1 / (1 + (lo / np.maximum(fr, 1)) ** 4)) * (1 / (1 + (fr / hi) ** 4))
    return np.fft.irfft(f, len(x))


# ---------------------------------------------------------------- instruments
# Each returns a mono note: f (Hz), d (seconds it is held), v (loudness 0..1), rng.

def pluck(f, d, v, rng, ring=2.5, bright=0.5, pick=0.18, damp_at=None):
    """Karplus-Strong string, worked a period at a time (vectorised)."""
    L = int((min(d, damp_at) if damp_at else ring) * SR) + int(0.25 * SR)
    L = max(L, int(0.3 * SR))
    N = max(2, int(round(SR / f)))
    exc = rng.standard_normal(N)
    exc = lp(np.concatenate([exc, np.zeros(N)]), 600 + 5000 * bright)[:N]
    # where along the string it is plucked: a comb takes out some harmonics
    k = max(1, int(N * pick))
    exc = exc - np.concatenate([np.zeros(k), exc[:-k]]) * 0.9
    exc /= np.abs(exc).max() + 1e-9
    # loss per period for a ring of `ring` seconds (to -60 dB), less for high notes held short
    rho = 10 ** (-3 / (ring * f))
    y = np.zeros(L + N)
    y[:N] = exc
    last = 0.0
    for s in range(N, L + N, N):
        prev = y[s - N:s]
        shifted = np.concatenate([[last], prev[:-1]])
        last = prev[-1]
        e = min(s + N, L + N)
        y[s:e] = (rho * 0.5 * (prev + shifted))[: e - s]
    y = y[:L]
    # the loop above can only take whole samples for a period (and its averaging adds half a sample):
    # resample the note so it sounds exactly at f
    r = f * (N + 0.5) / SR
    if abs(r - 1) > 1e-4:
        src = np.arange(0, L - 1, r)
        y = np.interp(src, np.arange(L), y)
        L = len(y)
    if damp_at:
        # a lute string is stopped when the note ends
        n0 = int(damp_at * SR)
        if n0 < L:
            rel = np.ones(L)
            m = min(L - n0, int(0.12 * SR))
            rel[n0:n0 + m] = np.linspace(1, 0, m)
            rel[n0 + m:] = 0
            y *= rel
    return y * v


def harp(f, d, v, rng):
    return pluck(f, d, v, rng, ring=2.8 if f < 400 else 2.0, bright=0.35, pick=0.12)


def lute(f, d, v, rng):
    return pluck(f, d, v, rng, ring=1.6, bright=0.75, pick=0.22, damp_at=max(0.18, d + 0.05))


def vib(n, rate, depth, delay, rng):
    x = np.arange(n) / SR
    on = np.clip((x - delay) / 0.3, 0, 1)
    return 1 + depth * on * np.sin(2 * np.pi * rate * x + rng.uniform(0, 6.28))


def adsr(n, a, r, d=None, s=1.0):
    x = np.arange(n) / SR
    e = np.clip(x / max(a, 1e-4), 0, 1)
    if d:
        e = np.where(x < a, e, s + (1 - s) * np.exp(-(x - a) / d))
    rn = int(r * SR)
    if rn and n > rn:
        e[-rn:] *= np.linspace(1, 0, rn) ** 1.5
    return e


def additive(fcurve, weights, n):
    ph = 2 * np.pi * np.cumsum(fcurve) / SR
    out = np.zeros(n)
    for k, w in enumerate(weights, 1):
        if w == 0 or fcurve[0] * k > SR * 0.45:
            continue
        out += w * np.sin(k * ph)
    return out


def recorder(f, d, v, rng):
    n = int((d + 0.08) * SR)
    fc = f * vib(n, 5.2, 0.004, 0.25, rng)
    tone = additive(fc, [1.0, 0.22, 0.10, 0.04, 0.02], n)
    breath = bp(rng.standard_normal(n), f * 0.8, f * 3.5) * 0.05
    chiff = bp(rng.standard_normal(n), 2500, 6000) * np.exp(-np.arange(n) / SR / 0.012) * 0.12
    return (tone + breath + chiff) * adsr(n, 0.035, 0.07) * v * 0.6


def fiddle(f, d, v, rng, att=0.08):
    n = int((d + 0.12) * SR)
    fc = f * vib(n, 5.6, 0.006, 0.18, rng)
    w = []
    for k in range(1, 26):
        fk = f * k
        body = 1 + 0.9 * np.exp(-((fk - 480) / 180) ** 2) + 0.7 * np.exp(-((fk - 2900) / 700) ** 2)
        w.append(body / k)
    tone = additive(fc, w, n)
    bow = bp(rng.standard_normal(n), 2000, 7000) * 0.025
    return lp(tone + bow, 5000) * adsr(n, att, 0.1) * v * 0.35


def horn(f, d, v, rng):
    n = int((d + 0.15) * SR)
    x = np.arange(n) / SR
    fc = f * (1 - 0.02 * np.exp(-x / 0.05)) * vib(n, 4.8, 0.003, 0.4, rng)
    ph = 2 * np.pi * np.cumsum(fc) / SR
    bright = np.clip(x / 0.12, 0, 1) * 0.8 + 0.2
    out = np.zeros(n)
    for k, w in enumerate([1.0, 0.75, 0.55, 0.4, 0.26, 0.16, 0.09, 0.05], 1):
        if f * k < SR * 0.45:
            out += w * (bright ** (k - 1)) * np.sin(k * ph)
    return lp(out, 3200) * adsr(n, 0.06, 0.14) * v * 0.4


def drone(f, d, v, rng):
    n = int(d * SR)
    x = np.arange(n) / SR
    out = np.zeros(n)
    for ff, a in ((f, 1.0), (f * 1.5, 0.6), (f * 2, 0.3)):
        fc = ff * (1 + 0.0015 * np.sin(2 * np.pi * 0.3 * x + rng.uniform(0, 6)))
        out += a * additive(fc, [1 / k for k in range(1, 13)], n)
    swell = 0.75 + 0.25 * np.sin(2 * np.pi * x / 7.0 + rng.uniform(0, 6))
    out = lp(out, 900) * swell
    fade = np.minimum(1, np.minimum(x / 2.0, (d - x) / 2.5))
    return out * np.clip(fade, 0, 1) * v * 0.12


def drum(f, d, v, rng, kind="frame"):
    if kind == "war":
        n = int(0.9 * SR)
        x = np.arange(n) / SR
        fc = 58 * (1 + 0.9 * np.exp(-x / 0.03))
        body = np.sin(2 * np.pi * np.cumsum(fc) / SR) * np.exp(-x / 0.35)
        slap = bp(rng.standard_normal(n), 150, 2500) * np.exp(-x / 0.05) * 0.7
        return (body + slap) * v
    if kind == "tap":
        n = int(0.25 * SR)
        x = np.arange(n) / SR
        return (bp(rng.standard_normal(n), 900, 5000) * np.exp(-x / 0.025) + np.sin(2 * np.pi * 330 * x) * np.exp(-x / 0.04) * 0.4) * v * 0.6
    n = int(0.6 * SR)
    x = np.arange(n) / SR
    fc = 95 * (1 + 0.6 * np.exp(-x / 0.02))
    body = np.sin(2 * np.pi * np.cumsum(fc) / SR) * np.exp(-x / 0.22)
    slap = bp(rng.standard_normal(n), 200, 3000) * np.exp(-x / 0.03) * 0.5
    return (body + slap) * v * 0.8


def bell(f, d, v, rng):
    n = int(4.5 * SR)
    x = np.arange(n) / SR
    out = np.zeros(n)
    for r, a, dec in ((0.5, 0.6, 2.5), (1.0, 1.0, 1.8), (1.183, 0.5, 1.2), (1.506, 0.35, 1.0), (2.0, 0.3, 0.8), (2.514, 0.2, 0.6), (3.011, 0.1, 0.4)):
        out += a * np.sin(2 * np.pi * f * r * x + rng.uniform(0, 6)) * np.exp(-x / dec)
    return out * np.clip(x / 0.002, 0, 1) * v * 0.35


# the players' balance (plucked strings die away, so they need more than the held winds)
GAIN = {"lute": 3.6, "harp": 1.35, "drone": 0.75, "recorder": 0.9}

INSTR = {"harp": harp, "lute": lute, "recorder": recorder, "fiddle": fiddle, "horn": horn,
         "drone": drone, "bell": bell}


# ---------------------------------------------------------------- arranging
class Piece:
    def __init__(self, name, bpm, beats, seed):
        self.name = name
        self.spb = 60.0 / bpm
        self.beats = beats
        self.rng = np.random.default_rng(seed)
        self.notes = []          # [instrument, start s, f, held s, loudness, pan (-1..1)]
        self.bar = 0             # the next bar to write

    def at(self, bar, beat=0.0):
        return (bar * self.beats + beat) * self.spb

    def melody(self, instr, text, bar, v=0.8, pan=0.0, octave=0, swing=0.0):
        """'A4:1 D5:1.5 E5:.5 | ...' from bar on; R is a rest. Returns the bar after it."""
        beat = 0.0
        for tok in text.replace("|", " ").split():
            nm, du = tok.split(":")
            du = float(du)
            if nm != "R":
                f = freq(nm) * 2 ** octave
                jit = self.rng.normal(0, 0.006)
                lv = v * self.rng.uniform(0.88, 1.0)
                # the first beat of a bar a little louder
                if abs((beat % self.beats)) < 1e-6:
                    lv *= 1.08
                self.notes.append([instr, max(0, self.at(bar, beat) + jit), f, du * self.spb * 0.97, lv, pan])
            beat += du
        return bar + int(round(beat / self.beats))

    def chords(self, instr, prog, bar, pattern, v=0.45, pan=0.0, low=2):
        """Broken chords: prog like 'Dm C Dm Am'; pattern a list of (beat, chord tone) where the tone
        is 0 root, 1 third, 2 fifth, 3 root an octave up, 4 third up, 5 fifth up, 6 the seventh."""
        for ch in prog.split():
            tones = chord_tones(ch, low)
            for beat, k, du in pattern:
                f = tones[k]
                self.notes.append([instr, self.at(bar, beat) + self.rng.normal(0, 0.005), f, du * self.spb, v * self.rng.uniform(0.85, 1.0), pan])
            bar += 1
        return bar

    def hold(self, instr, name, bars_from, bars, v=0.6, pan=0.0):
        self.notes.append([instr, self.at(bars_from), freq(name), bars * self.beats * self.spb, v, pan])

    def drums(self, bar, bars, pattern, v=0.7, pan=0.0):
        """pattern: [(beat, kind, loudness)] repeated each bar."""
        for b in range(bar, bar + bars):
            for beat, kind, lv in pattern:
                self.notes.append(["drum:" + kind, self.at(b, beat) + self.rng.normal(0, 0.004), 0, 0, v * lv * self.rng.uniform(0.85, 1.0), pan])

    def render(self, wet=0.28, tail=4.0):
        end = max(s + d for _, s, _, d, _, _ in self.notes) + tail
        n = int(end * SR)
        L = np.zeros(n)
        R = np.zeros(n)
        cache = {}
        for instr, s, f, d, v, pan in self.notes:
            key = (instr, round(f, 2), round(d, 2))
            if instr.startswith("drum:"):
                x = drum(0, 0, 1.0, self.rng, instr[5:])
            elif key in cache and instr in ("harp", "lute"):
                x = cache[key]
            else:
                x = INSTR[instr](f, d, 1.0, self.rng)
                if instr in ("harp", "lute"):
                    cache[key] = x
            x = x * v * GAIN.get(instr, 1.0)
            i = max(0, int(s * SR))
            m = min(len(x), n - i)
            if m <= 0:
                continue
            gl = np.cos((pan + 1) * np.pi / 4)
            gr = np.sin((pan + 1) * np.pi / 4)
            L[i:i + m] += x[:m] * gl
            R[i:i + m] += x[:m] * gr
        return hall(L, R, wet)


def chord_tones(ch, low):
    """'Dm', 'G', 'C7', 'E', 'Bb' -> frequencies [root, third, fifth, root+8, third+8, fifth+8, seventh]."""
    root = ch[0]
    i = 1
    if i < len(ch) and ch[i] in "#b":
        root += ch[i]; i += 1
    q = ch[i:]
    r = freq(root + str(low))
    # keep the bass between C2 and B2 (or an octave up when low is 3)
    third = 3 if q.startswith("m") else 4
    st = [0, third, 7, 12, 12 + third, 19, 10 if "7" in q else 12]
    return [r * 2 ** (s / 12) for s in st]


def hall(L, R, wet):
    """Stereo hall: convolution with two different decaying noise bursts."""
    rng = np.random.default_rng(7)
    n = int(2.2 * SR)
    x = np.arange(n) / SR
    out = []
    for ch in (L, R):
        ir = rng.standard_normal(n) * np.exp(-x / 0.45)
        ir[: int(0.012 * SR)] = 0             # the first reflections come a little later
        ir = lp(ir, 4500)
        ir /= np.sqrt((ir ** 2).sum())
        w = fftconvolve(ch, ir)[: len(ch)]
        out.append(ch * (1 - wet) + w * wet * 2.2)
    return out[0], out[1]


def finish(name, L, R, peak_db=-1.5):
    st = np.stack([L, R], 1)
    # gentle limiting, then the loudest point at peak_db
    st = np.tanh(st / (np.abs(st).max() + 1e-9) * 1.3) / np.tanh(1.3)
    st *= 10 ** (peak_db / 20)
    # fade the very end
    m = int(1.5 * SR)
    st[-m:] *= np.linspace(1, 0, m)[:, None]
    wav = os.path.join(OUT, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(st, -1, 1) * 32767).astype("<i2").tobytes())
    ogg = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "3", ogg], check=True)
    os.remove(wav)
    secs = len(st) / SR
    print("%-14s %5.1f s  %6.0f KB" % (name, secs, os.path.getsize(ogg) / 1024))


# ---------------------------------------------------------------- the pieces
ARP3 = [(0, 0, 2.5), (0.5, 2, 2), (1, 3, 1.8), (1.5, 4, 1.5), (2, 5, 1.2), (2.5, 4, 1.0)]
ARP4 = [(0, 0, 3.5), (0.5, 2, 3), (1, 3, 2.5), (1.5, 4, 2), (2, 5, 2), (2.5, 4, 1.5), (3, 3, 1.2), (3.5, 2, 1.0)]
BALLAD = [(0, 0, 4), (1, 2, 3), (2, 4, 2), (3, 5, 1.5)]
STRUM = [(0, 0, 1.5), (0, 2, 1.5), (0, 4, 1.5), (2, 3, 1.5), (2, 5, 1.5)]


def morning():
    """Morning in the Valley: D Dorian, 3/4, recorder over the harp, a drone of D and A."""
    p = Piece("peace_morning", 84, 3, 11)
    A = "A4:1 D5:1.5 E5:.5 | F5:1 E5:1 D5:.5 C5:.5 | D5:2 A4:1 | C5:1 B4:1 A4:1 | A4:1 C5:1 F5:1 | E5:1.5 D5:.5 C5:1 | B4:1 D5:1 G4:1 | A4:3"
    A2 = "A4:1 D5:1.5 E5:.5 | F5:1 E5:1 D5:.5 C5:.5 | D5:2 A4:1 | C5:1 B4:1 A4:1 | A4:1 C5:1 F5:1 | G5:1 F5:.5 E5:.5 D5:1 | E5:1 C5:1 A4:1 | D5:3"
    B = "C5:.5 D5:.5 F5:1 A5:1 | G5:1 E5:1 C5:1 | F5:.5 E5:.5 D5:1 A5:1 | G5:1.5 F5:.5 E5:1 | A5:1 G5:.5 F5:.5 A5:1 | G5:1 E5:1 C5:1 | D5:1 B4:.5 C5:.5 D5:1 | E5:3"
    chA = "Dm C Dm Am F C G Dm"
    chA2 = "Dm C Dm Am F G Am Dm"
    chB = "F C Dm Am F C G Am"
    bar = p.chords("harp", "Dm C Dm Dm", 0, ARP3, 0.45, -0.2)
    start = 0
    sections = [(A, chA, "recorder", 0.0), (A2, chA2, "recorder", 0.0), (B, chB, "recorder", 0.0),
                (B, chB, "lute", 1), (A, chA, "lute", 0), (A2, chA2, "recorder", 0.0)]
    for mel, ch, ins, oc in sections:
        p.chords("harp", ch, bar, ARP3, 0.42, -0.25)
        if ins == "lute":
            p.melody("lute", mel, bar, 0.55, 0.3, octave=-1 if oc else 0)
            p.melody("recorder", mel, bar, 0.35, 0.15, octave=0) if oc else None
        else:
            p.melody("recorder", mel, bar, 0.75, 0.15)
        bar += 8
    p.chords("harp", "Dm Dm", bar, ARP3, 0.4, -0.2)
    p.hold("harp", "D3", bar + 2, 1, 0.5)
    p.hold("drone", "D2", 4, bar - 4, 0.8, 0.0)
    return p


def furrow():
    """The Long Furrow: G Mixolydian, 4/4, lute and recorder, a frame drum, the harp strummed."""
    p = Piece("peace_furrow", 96, 4, 22)
    A = "D4:1 G4:1 B4:1 D5:1 | C5:1.5 A4:.5 F4:1 A4:1 | G4:1 E4:1 C5:1 B4:.5 A4:.5 | B4:2 G4:2 | D5:1 B4:.5 D5:.5 G5:1 F5:1 | E5:.5 F5:.5 E5:.5 D5:.5 C5:2 | D5:1 A4:1 F5:1 E5:1 | D5:3 R:1"
    B = "E5:1 G5:1 E5:1 C5:1 | D5:1 B4:1 G4:2 | A4:1 C5:1 F5:1 A5:1 | G5:2 D5:2 | E5:.5 F5:.5 G5:1 E5:1 C5:1 | A4:1 C5:1 E5:1 A5:1 | F5:1 E5:1 D5:1 C5:1 | B4:1 A4:1 G4:2"
    chA = "G F C G G F Dm G"
    chB = "C G F G C Am Dm G"
    beat = [(0, "frame", 1.0), (1.5, "tap", 0.5), (2, "frame", 0.7), (3, "tap", 0.6), (3.5, "tap", 0.4)]
    p.drums(0, 2, [(0, "frame", 0.8), (2, "frame", 0.6)], 0.55, -0.1)
    bar = 2
    plan = [(A, chA, ["lute"]), (A, chA, ["recorder", "lute2"]), (B, chB, ["recorder"]),
            (A, chA, ["lute", "recorder2"]), (B, chB, ["recorder", "lute2"]), (A, chA, ["lute", "recorder"])]
    for mel, ch, who in plan:
        p.chords("harp", ch, bar, ARP4, 0.36, -0.3)
        p.drums(bar, 8, beat, 0.45, -0.1)
        for w in who:
            if w == "lute":
                p.melody("lute", mel, bar, 0.62, 0.25)
            elif w == "lute2":
                p.melody("lute", mel, bar, 0.38, 0.35, octave=-1)
            elif w == "recorder":
                p.melody("recorder", mel, bar, 0.72, 0.1)
            elif w == "recorder2":
                p.melody("recorder", mel, bar, 0.4, 0.05, octave=1)
        bar += 8
    p.chords("harp", "G G", bar, ARP4, 0.36, -0.3)
    p.drums(bar, 1, [(0, "frame", 0.9)], 0.5)
    p.hold("drone", "G2", 2, bar - 2, 0.6)
    return p


def hearth():
    """Hearth and Home: A Aeolian ballad, 4/4, slow: the harp alone, then the recorder and a fiddle."""
    p = Piece("peace_hearth", 66, 4, 33)
    A = "E5:1.5 D5:.5 C5:1 B4:1 | A4:2 C5:1 F5:1 | E5:1.5 G5:.5 E5:1 C5:1 | D5:3 B4:1 | C5:1 E5:1 A5:1.5 G5:.5 | F5:1 E5:1 D5:1 C5:1 | B4:1 D5:1 G4:1 B4:1 | A4:4"
    B = "A5:2 G5:1 F5:1 | G5:2 F5:1 D5:1 | E5:1.5 D5:.5 C5:1 E5:1 | A5:3 E5:1 | F5:1 A5:1 C6:1 A5:1 | G5:1.5 F5:.5 D5:2 | B4:1 D5:1 G#4:1 B4:1 | A4:4"
    chA = "Am F C G Am F G Am"
    chB = "F G C Am F G E7 Am"
    bar = 0
    p.chords("harp", chA, bar, BALLAD, 0.42, -0.2)
    p.melody("harp", A, bar, 0.62, 0.2, octave=0)
    bar += 8
    p.chords("harp", chA, bar, BALLAD, 0.38, -0.25)
    p.melody("recorder", A, bar, 0.7, 0.1)
    bar += 8
    p.chords("harp", chB, bar, BALLAD, 0.38, -0.25)
    p.melody("recorder", B, bar, 0.72, 0.1)
    p.melody("fiddle", B, bar, 0.35, 0.35, octave=-1)
    bar += 8
    p.chords("harp", chA, bar, BALLAD, 0.38, -0.25)
    p.melody("fiddle", A, bar, 0.55, 0.3)
    p.melody("harp", A, bar, 0.32, -0.1, octave=1)
    bar += 8
    p.chords("harp", "Am Am", bar, BALLAD, 0.35, -0.2)
    p.hold("drone", "A2", 8, bar - 8, 0.5)
    return p


def market():
    """Market Day: F major, brisk, a tabor, recorder and lute, the harp in the bass."""
    p = Piece("peace_market", 112, 4, 44)
    A = "C5:.5 F5:.5 A5:.5 F5:.5 C5:1 A4:1 | G4:.5 C5:.5 E5:.5 C5:.5 G4:1 E4:1 | F4:.5 A4:.5 C5:.5 F5:.5 E5:.5 D5:.5 C5:.5 Bb4:.5 | A4:1 G4:1 C5:2 | C5:.5 F5:.5 A5:.5 F5:.5 C5:1 A4:1 | Bb4:.5 D5:.5 F5:.5 D5:.5 Bb4:1 G4:1 | C5:.5 E5:.5 G5:.5 E5:.5 D5:.5 C5:.5 Bb4:.5 G4:.5 | F4:1 A4:1 F5:2"
    B = "D5:1 F5:1 A5:1.5 G5:.5 | F5:1 D5:1 Bb4:2 | C5:1 F5:1 A5:1 F5:1 | G5:1.5 F5:.5 E5:2 | F5:1 A5:1 D6:1 A5:1 | Bb5:1 G5:1 D5:2 | C5:.5 D5:.5 E5:.5 F5:.5 G5:1 E5:1 | F5:4"
    chA = "F C F C F Bb C7 F"
    chB = "Dm Bb F C Dm Gm C F"
    tabor = [(0, "frame", 1.0), (1, "tap", 0.6), (1.5, "tap", 0.4), (2, "frame", 0.8), (3, "tap", 0.6), (3.5, "tap", 0.5)]
    p.drums(0, 2, tabor, 0.5, 0.15)
    bar = 2
    for mel, ch, lead in [(A, chA, "recorder"), (A, chA, "lute"), (B, chB, "recorder"), (A, chA, "both"), (B, chB, "lute"), (A, chA, "both")]:
        p.chords("harp", ch, bar, STRUM, 0.33, -0.3, low=2)
        p.drums(bar, 8, tabor, 0.45, 0.15)
        if lead in ("recorder", "both"):
            p.melody("recorder", mel, bar, 0.7, 0.05)
        if lead in ("lute", "both"):
            p.melody("lute", mel, bar, 0.6 if lead == "lute" else 0.4, 0.3, octave=-1 if lead == "both" else 0)
        bar += 8
    p.chords("harp", "F", bar, STRUM, 0.35, -0.3)
    p.drums(bar, 1, [(0, "frame", 1.0)], 0.5)
    return p


def court():
    """The Court Dance (build 63, the Renaissance and the Age of Reason): G major, a stately pavane in
    3/4, the lute and harp under a fiddle and a recorder."""
    p = Piece("peace_court", 92, 3, 99)
    A = "G4:1 B4:1 D5:1 | C5:1.5 B4:.5 A4:1 | B4:1 G4:1 D5:1 | E5:2 D5:1 | C5:1 E5:1 G5:1 | F#5:1.5 E5:.5 D5:1 | E5:1 C5:1 A4:1 | G4:3"
    B = "D5:1.5 E5:.5 F#5:1 | G5:2 D5:1 | E5:1 F#5:1 G5:1 | A5:2 F#5:1 | G5:1 E5:1 C5:1 | D5:1.5 C5:.5 B4:1 | A4:1 B4:1 F#4:1 | G4:3"
    chA = "G C G C C D C G"
    chB = "D G C D C G D G"
    PAV = [(0, 0, 2.5), (1, 2, 1.5), (2, 4, 1.0)]
    bar = 0
    for mel, ch, lead in [(A, chA, "lute"), (A, chA, "fiddle"), (B, chB, "recorder"), (A, chA, "both"), (B, chB, "fiddle"), (A, chA, "both")]:
        p.chords("harp", ch, bar, PAV, 0.36, -0.25)
        if lead in ("lute",):
            p.melody("lute", mel, bar, 0.62, 0.1)
        if lead in ("fiddle", "both"):
            p.melody("fiddle", mel, bar, 0.6, 0.25)
        if lead in ("recorder", "both"):
            p.melody("recorder", mel, bar, 0.55 if lead == "both" else 0.7, -0.05, octave=1 if lead == "both" else 0)
        bar += 8
    p.chords("harp", "G", bar, PAV, 0.38, -0.2)
    p.hold("drone", "G2", 0, bar, 0.35)
    return p


def foundry():
    """Smoke over the Town (build 63, the Industrial and Modern ages): C minor, a steady march, brass
    calls and bells over a low drone and the beat of the works."""
    p = Piece("peace_foundry", 104, 4, 111)
    A = "C4:1 Eb4:1 G4:1.5 F4:.5 | Eb4:1 D4:1 C4:2 | Ab4:1 G4:1 F4:1 Eb4:1 | D4:3 G3:1 | C4:1 Eb4:1 G4:1 C5:1 | Bb4:1.5 Ab4:.5 G4:2 | F4:1 Ab4:1 G4:1 D4:1 | C4:4"
    B = "G4:1.5 Ab4:.5 G4:1 F4:1 | Eb4:2 G4:2 | Ab4:1 Bb4:1 C5:1 Ab4:1 | G4:3 G4:1 | C5:1 Bb4:1 Ab4:1 G4:1 | F4:1 G4:1 Ab4:2 | G4:1 F4:1 Eb4:1 D4:1 | C4:4"
    chA = "Cm Cm Fm G Cm Eb Fm Cm"
    chB = "Eb Cm Fm G Ab Fm G Cm"
    works = [(0, "war", 0.7), (1, "tap", 0.5), (2, "war", 0.55), (3, "tap", 0.5), (3.5, "tap", 0.35)]
    p.drums(0, 2, works, 0.5)
    bar = 2
    for mel, ch, lead in [(A, chA, "horn"), (B, chB, "fiddle"), (A, chA, "both"), (B, chB, "horn"), (A, chA, "both")]:
        p.chords("harp", ch, bar, BALLAD, 0.3, -0.3)
        p.drums(bar, 8, works, 0.45)
        if lead in ("horn", "both"):
            p.melody("horn", mel, bar, 0.7 if lead == "horn" else 0.5, 0.15)
        if lead in ("fiddle", "both"):
            p.melody("fiddle", mel, bar, 0.55, 0.3, octave=1 if lead == "both" else 0)
        for k in range(0, 8, 4):
            p.notes.append(["bell", p.at(bar + k), freq("C6"), 0, 0.25, -0.4])
        bar += 8
    p.hold("drone", "C2", 0, bar, 0.55)
    p.hold("horn", "C4", bar, 2, 0.5, 0.15)
    return p


def war():
    """Banners in the East: D Phrygian, war drums, a low string ostinato, horn calls, then a fiddle."""
    p = Piece("war_banners", 100, 4, 55)
    ost = "D3:.5 D3:.5 F3:.5 D3:.5 Eb3:.5 D3:.5 C3:.5 D3:.5"
    M = "D4:1.5 A4:.5 A4:1 G4:.5 F4:.5 | Eb4:1 F4:1 D4:2 | D4:1.5 A4:.5 C5:1 Bb4:.5 A4:.5 | G4:1 A4:.5 G4:.5 F4:1 Eb4:1 | D4:1 F4:1 A4:1 D5:1 | C5:1 Bb4:1 A4:2 | G4:1 Bb4:1 A4:1 G4:1 | F4:.5 Eb4:.5 D4:3"
    N = "A4:1 D5:1 F5:1.5 Eb5:.5 | D5:2 A4:2 | Bb4:1 C5:1 D5:1 F5:1 | Eb5:3 D5:1 | D5:1 F5:1 A5:1.5 G5:.5 | F5:1 Eb5:1 D5:2 | C5:1 Bb4:1 A4:1 G4:1 | A4:4"
    beat = [(0, "war", 1.0), (1, "war", 0.45), (1.5, "war", 0.4), (2, "war", 0.85), (3, "war", 0.45), (3.5, "tap", 0.6)]
    p.drums(0, 2, [(0, "war", 1.0), (2, "war", 0.8)], 0.85)
    bar = 2
    for b in range(bar, 38):
        p.melody("fiddle", ost, b, 0.35, -0.35)
    p.drums(2, 2, beat, 0.75)
    bar = 4
    p.drums(bar, 8, beat, 0.7)
    p.melody("horn", M, bar, 0.8, 0.2)
    bar += 8
    p.drums(bar, 8, beat, 0.7)
    p.melody("fiddle", N, bar, 0.6, 0.3)
    bar += 8
    p.drums(bar, 2, [(0, "war", 1.0), (0.5, "war", 0.5), (1, "war", 0.7), (2, "war", 1.0), (2.5, "war", 0.6), (3, "war", 0.8), (3.5, "war", 0.9)], 0.8)
    bar += 2
    p.drums(bar, 8, beat, 0.75)
    p.melody("horn", M, bar, 0.75, 0.2)
    p.melody("fiddle", M, bar, 0.4, 0.35, octave=1)
    bar += 8
    p.drums(bar, 8, beat, 0.75)
    p.melody("fiddle", N, bar, 0.6, 0.3)
    p.melody("horn", N, bar, 0.45, 0.15, octave=-1)
    bar += 8
    p.drums(bar, 2, [(0, "war", 1.0), (2, "war", 0.9)], 0.85)
    p.hold("horn", "D4", bar, 2, 0.6, 0.2)
    p.hold("drone", "D2", 2, bar, 1.0)
    return p


def stingers():
    out = []
    # a new age: bells and a rising horn call in D
    p = Piece("cue_age", 90, 4, 66)
    p.melody("horn", "D4:.5 F#4:.5 A4:.5 D5:2.5", 0, 0.8, 0.1)
    p.melody("horn", "A3:.5 D4:.5 F#4:.5 A4:2.5", 0, 0.5, -0.1)
    for i, nm in enumerate(["D5", "A5", "F#5", "D6"]):
        p.notes.append(["bell", p.at(0, 1.5 + i * 0.25), freq(nm), 0, 0.5, (i - 1.5) * 0.3])
    p.notes.append(["drum:war", p.at(0, 1.5), 0, 0, 0.6, 0])
    out.append(p)
    # victory: a fanfare in thirds, drums, bells
    p = Piece("cue_victory", 100, 4, 77)
    p.melody("horn", "G4:.5 G4:.5 G4:.5 B4:1.5 D5:1 | G5:4", 0, 0.85, 0.15)
    p.melody("horn", "D4:.5 D4:.5 D4:.5 G4:1.5 B4:1 | D5:4", 0, 0.55, -0.15)
    p.drums(0, 1, [(0, "war", 1.0), (0.5, "war", 0.6), (1, "war", 0.8), (1.5, "war", 0.8), (2, "war", 1.0)], 0.8)
    p.notes.append(["drum:war", p.at(1), 0, 0, 1.0, 0])
    for i, nm in enumerate(["G5", "D6", "B5", "G6"]):
        p.notes.append(["bell", p.at(1, i * 0.3), freq(nm), 0, 0.45, (i - 1.5) * 0.3])
    p.chords("harp", "G", 1, [(0, 0, 4), (0.25, 2, 4), (0.5, 3, 4), (0.75, 4, 4), (1, 5, 4)], 0.5, -0.3)
    out.append(p)
    # defeat: a slow lament on the recorder over a fading drone
    p = Piece("cue_defeat", 60, 4, 88)
    p.melody("recorder", "A4:1.5 G4:.5 F4:1 E4:1 | D4:4", 0, 0.7, 0.1)
    p.melody("fiddle", "F4:2 C4:2 | A3:4", 0, 0.35, -0.3)
    p.hold("drone", "D2", 0, 2, 0.9)
    p.hold("harp", "D3", 1, 1, 0.5, -0.2)
    out.append(p)
    return out


PIECES = {"peace_morning": morning, "peace_furrow": furrow, "peace_hearth": hearth, "peace_market": market,
          "peace_court": court, "peace_foundry": foundry,
          "war_banners": war}


if __name__ == "__main__":
    want = sys.argv[1:]
    for name, fn in PIECES.items():
        if not want or name in want:
            p = fn()
            L, R = p.render(0.3 if name != "war_banners" else 0.22)
            finish(name, L, R)
    if not want or any(w.startswith("cue") for w in want):
        for p in stingers():
            L, R = p.render(0.3, tail=3.5)
            finish(p.name, L, R)
