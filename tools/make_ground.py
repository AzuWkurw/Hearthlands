#!/usr/bin/env python3
"""Ground tiles for Hearthlands: grass, beach, water and mountain rock, four variants each, 64 x 64.

Used by make_textures.py (terrain()); can be run alone:  python3 tools/make_ground.py [--force]

Every tile is made from noise that wraps around, so a tile joins itself without a seam. The four
variants of a kind share the same base and differ only away from their edges (their own detail fades
out towards the border), so any two variants side by side join without a seam too.
Relief comes from a height field lit from the upper left (as the rest of the game): grass clumps,
sand ripples and rock all catch the light on one side and fall into shade on the other.
"""
import os, sys, math
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "textures")
N = 64
FORCE = "--force" in sys.argv
LIGHT = np.array([-0.6, -0.8])      # light from the upper left (x, y)


def tnoise(cells, seed, n=N):
    """Smooth noise on an n x n grid that wraps around (cells per side)."""
    rnd = np.random.default_rng(seed)
    g = rnd.random((cells, cells))
    t = np.arange(n) * cells / n
    i0 = np.floor(t).astype(int)
    f = t - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % cells
    a = g[i0][:, i0] * (1 - f)[None, :] + g[i0][:, i1] * f[None, :]
    b = g[i1][:, i0] * (1 - f)[None, :] + g[i1][:, i1] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]


def fbm(seed, octaves):
    return sum(tnoise(c, seed + k * 101) * w for k, (c, w) in enumerate(octaves))


def window():
    """1 in the middle of a tile, 0 at its edges: where a variant may differ from the others."""
    x = (np.arange(N) + 0.5) / N
    w = np.sin(np.pi * x) ** 0.8
    return np.outer(w, w)


WIN = window()


def lit(height, strength):
    """Light and shade of a height field (wrapping), lit from the upper left: about -1..1."""
    gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) / 2
    gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) / 2
    return np.clip(-(gx * LIGHT[0] + gy * LIGHT[1]) * strength, -1, 1)


def ramp(v, stops):
    """Colours along a ramp: stops = [(position, (r, g, b))], v any shape -> (..., 3)."""
    v = np.clip(v, 0, 1)
    pos = np.array([p for p, _ in stops])
    cols = np.array([c for _, c in stops], np.float32)
    out = np.empty(v.shape + (3,), np.float32)
    for ch in range(3):
        out[..., ch] = np.interp(v, pos, cols[:, ch])
    return out


def shade(rgb, f):
    return np.clip(rgb * f[..., None], 0, 255)


def wrapdist(cx, cy):
    """Distances along x and y from (cx, cy) on the wrapping tile."""
    xs = np.arange(N)
    dx = (xs - cx + N / 2) % N - N / 2
    dy = (xs - cy + N / 2) % N - N / 2
    return dx[None, :], dy[:, None]


def blob(img, cx, cy, rx, ry, col, alpha=1.0, light=True, shadow=True):
    """A small rounded stone or clod: lit on its upper left, a soft shadow below right."""
    dx, dy = wrapdist(cx, cy)
    d = (dx / rx) ** 2 + (dy / ry) ** 2
    if shadow:
        sdx, sdy = wrapdist(cx + rx * 0.45, cy + ry * 0.6)
        sd = (sdx / (rx * 1.15)) ** 2 + (sdy / (ry * 1.1)) ** 2
        sm = np.clip(1.25 - sd, 0, 1) * 0.35 * alpha
        img[...] = img * (1 - sm[..., None])
    m = np.clip((1.0 - d) * 3.0, 0, 1) * alpha
    c = np.array(col, np.float32)
    if light:
        f = 1.0 + np.clip(-(dx / rx * 0.55 + dy / ry * 0.75), -1, 1) * 0.35
        top = np.clip(1 - ((dx + rx * 0.35) / (rx * 0.45)) ** 2 - ((dy + ry * 0.4) / (ry * 0.4)) ** 2, 0, 1) * 0.35
        cc = c[None, None, :] * f[..., None] + top[..., None] * 255 * 0.5
    else:
        cc = np.broadcast_to(c, img.shape)
    img[...] = img * (1 - m[..., None]) + np.clip(cc, 0, 255) * m[..., None]


def stroke(img, x, y, dx, dy, length, c0, c1, width=1.0, alpha=1.0):
    """A thin stroke (a grass blade) from (x, y) along (dx, dy), colour c0 at its root to c1 at its tip."""
    steps = max(2, int(length * 3))
    for k in range(steps + 1):
        t = k / steps
        px = (x + dx * length * t) % N
        py = (y + dy * length * t) % N
        ix, iy = int(px), int(py)
        fx, fy = px - ix, py - iy
        col = np.array(c0, np.float32) * (1 - t) + np.array(c1, np.float32) * t
        wgt = (1 - t * 0.5) * alpha * width
        for ox, oy, wv in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
            a = min(1.0, wv * wgt * 1.6)
            j, i = (iy + oy) % N, (ix + ox) % N
            img[j, i] = img[j, i] * (1 - a) + col * a


def save(arr, name, alpha=None):
    p = os.path.join(OUT, name + ".png")
    if os.path.exists(p) and not FORCE:
        return
    a = np.clip(arr, 0, 255).astype(np.uint8)
    rgba = np.concatenate([a, np.full((N, N, 1), 255 if alpha is None else alpha, np.uint8)], 2)
    Image.fromarray(rgba, "RGBA").save(p)


# ---------------------------------------------------------------- grass
def grass(v):
    rnd = np.random.default_rng(100 + v)
    base = fbm(11, ((2, 0.3), (4, 0.3), (8, 0.25), (16, 0.15)))
    own = fbm(500 + v, ((4, 0.4), (8, 0.35), (16, 0.25)))
    hgt = base * 0.6 + (own - 0.5) * WIN * 0.6 + fbm(21 + v * 0, ((32, 1.0),)) * 0.25
    tone = np.clip((base - 0.25) * 1.6 + (own - 0.5) * WIN * 0.5, 0, 1)
    col = ramp(tone, [(0.0, (74, 120, 46)), (0.45, (102, 154, 62)), (0.8, (130, 178, 80)), (1.0, (148, 188, 92))])
    # drier, yellower patches here and there
    dry = np.clip((fbm(31, ((2, 0.6), (4, 0.4))) - 0.58) * 3.0, 0, 1) * 0.28
    col = col * (1 - dry[..., None]) + np.array([170, 168, 90], np.float32) * dry[..., None]
    # a faint grain and the light on the clumps
    grain = (rnd.random((N, N)) - 0.5) * 0.035
    col = shade(col, 1.0 + lit(hgt, 9.0) * 0.22 + grain)
    # tufts: fans of blades from one root, with a little shadow at their foot
    for _ in range(46):
        x, y = rnd.uniform(0, N), rnd.uniform(0, N)
        g = rnd.uniform(0.85, 1.15)
        dx, dy = wrapdist(x + 0.6, y + 0.4)
        sm = np.clip(1.2 - (dx / 2.2) ** 2 - (dy / 1.2) ** 2, 0, 1) * 0.22
        col[...] = col * (1 - sm[..., None])
        for k in range(rnd.integers(3, 6)):
            ang = -math.pi / 2 + (k - 2) * 0.32 + rnd.normal(0, 0.12)
            ln = rnd.uniform(3.0, 6.0)
            stroke(col, x, y, math.cos(ang), math.sin(ang), ln, (44 * g, 80 * g, 28 * g), (138 * g, 186 * g, 90 * g), 0.9, 0.9)
    # single blades between the tufts
    for _ in range(140):
        x, y = rnd.uniform(0, N), rnd.uniform(0, N)
        ang = rnd.normal(-math.pi / 2, 0.3)
        g = rnd.uniform(0.85, 1.15)
        stroke(col, x, y, math.cos(ang), math.sin(ang), rnd.uniform(2.0, 4.0), (56 * g, 96 * g, 34 * g), (120 * g, 168 * g, 78 * g), 0.8, 0.7)
    # clover and small leaves
    for _ in range(rnd.integers(1, 4)):
        cx, cy = rnd.uniform(6, 58), rnd.uniform(6, 58)
        for k in range(rnd.integers(3, 6)):
            blob(col, cx + rnd.uniform(-3, 3), cy + rnd.uniform(-3, 3), 1.3, 1.1, (88, 140, 60), 0.9, True, False)
    # flowers on two of the variants (away from the edges)
    if v >= 2:
        for _ in range(rnd.integers(3, 6)):
            fx, fy = rnd.uniform(8, 56), rnd.uniform(8, 56)
            c = [(246, 226, 104), (246, 246, 238), (224, 140, 196), (160, 176, 240), (236, 120, 80)][rnd.integers(0, 5)]
            stroke(col, fx, fy + 3, 0, -1, 3, (60, 100, 36), (80, 124, 46), 0.8, 0.9)
            for a in range(5):
                blob(col, fx + math.cos(a * 1.257) * 0.9, fy + math.sin(a * 1.257) * 0.9, 0.75, 0.75, c, 1.0, False, False)
            blob(col, fx, fy, 0.5, 0.5, (240, 200, 60), 1.0, False, False)
    if v == 1:
        for _ in range(2):
            blob(col, rnd.uniform(10, 54), rnd.uniform(10, 54), 1.6, 1.2, (150, 146, 132), 1.0)
    return col


# ---------------------------------------------------------------- beach
def beach(v):
    rnd = np.random.default_rng(200 + v)
    base = fbm(41, ((2, 0.4), (4, 0.35), (8, 0.25)))
    own = fbm(600 + v, ((4, 0.5), (8, 0.5)))
    # ripples left by the wind: bands bent by noise
    warp = fbm(51, ((2, 0.5), (4, 0.5)))
    yy = np.arange(N)[:, None] + warp * 14 + np.arange(N)[None, :] * 0.2   # (a slant that wraps: 5 ripples a tile)
    rip = np.sin(yy / N * math.tau * 5) * 0.5 + 0.5
    hgt = rip * 0.25 + base * 0.5 + (own - 0.5) * WIN * 0.3
    tone = np.clip(base * 1.1 - 0.05 + (own - 0.5) * WIN * 0.3, 0, 1)
    col = ramp(tone, [(0.0, (196, 172, 116)), (0.5, (220, 200, 146)), (1.0, (240, 226, 178))])
    damp = np.clip((fbm(61, ((2, 0.6), (4, 0.4))) - 0.6) * 3.0, 0, 1) * 0.16
    col = col * (1 - damp[..., None])
    grain = (rnd.random((N, N)) - 0.5) * 0.07 + (rnd.random((N, N)) > 0.992) * 0.12
    col = shade(col, 1.0 + lit(hgt, 7.0) * 0.16 + grain)
    for _ in range(rnd.integers(3, 7)):
        g = rnd.uniform(0.75, 1.15)
        blob(col, rnd.uniform(4, 60), rnd.uniform(4, 60), rnd.uniform(0.9, 1.8), rnd.uniform(0.7, 1.3), (150 * g, 142 * g, 126 * g), 1.0)
    if v == 3:
        # a shell
        cx, cy = rnd.uniform(14, 50), rnd.uniform(14, 50)
        blob(col, cx, cy, 2.0, 1.5, (246, 232, 222), 1.0)
        for k in range(3):
            stroke(col, cx - 1.2 + k * 1.2, cy + 1.2, 0.2 * (k - 1), -1, 2.2, (210, 180, 166), (226, 200, 186), 0.6, 0.8)
    return col


# ---------------------------------------------------------------- water
def water(v):
    rnd = np.random.default_rng(300 + v)
    base = fbm(71, ((2, 0.45), (4, 0.35), (8, 0.2)))
    own = fbm(700 + v, ((4, 0.5), (8, 0.5)))
    warp = fbm(81, ((2, 0.5), (4, 0.5)))
    yy = np.arange(N)[:, None] + warp * 10
    swell = np.sin(yy / N * math.tau * 4 + np.arange(N)[None, :] / N * math.tau) * 0.5 + 0.5
    tone = np.clip(base * 0.8 + 0.1 + (own - 0.5) * WIN * 0.25, 0, 1)
    col = ramp(tone, [(0.0, (34, 86, 134)), (0.5, (44, 106, 156)), (1.0, (58, 126, 172))])
    col = shade(col, 1.0 + lit(swell * 0.4 + base * 0.3, 4.0) * 0.12 + (rnd.random((N, N)) - 0.5) * 0.03)
    # a few short crests, inside the tile
    for _ in range(4):
        x, y = rnd.uniform(8, 52), rnd.uniform(8, 56)
        ln = rnd.uniform(5, 10)
        stroke(col, x, y, 1, rnd.uniform(-0.15, 0.15), ln, (92, 152, 196), (110, 168, 206), 0.8, 0.55)
        stroke(col, x, y + 1.2, 1, 0, ln * 0.8, (30, 80, 126), (34, 86, 132), 0.6, 0.35)
    return col


# ---------------------------------------------------------------- mountain rock
def mountain(v):
    rnd = np.random.default_rng(400 + v)
    base = fbm(91, ((2, 0.3), (4, 0.3), (8, 0.25), (16, 0.15)))
    own = fbm(800 + v, ((4, 0.4), (8, 0.35), (16, 0.25)))
    warp = fbm(95, ((2, 0.5), (4, 0.5)))
    yy = np.arange(N)[:, None] + warp * 18
    strata = np.sin(yy / N * math.tau * 3) * 0.5 + 0.5
    # blocky rock: noise pushed into steps
    blocks = np.floor((base * 0.6 + (own - 0.5) * WIN * 0.5 + strata * 0.25) * 7) / 7
    hgt = blocks * 0.7 + base * 0.3 + fbm(97, ((32, 1.0),)) * 0.08
    tone = np.clip(base * 1.2 - 0.15 + strata * 0.15, 0, 1)
    col = ramp(tone, [(0.0, (92, 86, 78)), (0.5, (132, 126, 114)), (1.0, (172, 166, 150))])
    col = shade(col, 1.0 + lit(hgt, 14.0) * 0.32 + (rnd.random((N, N)) - 0.5) * 0.10)
    # cracks: dark lines with a lit lip, inside the tile
    for _ in range(rnd.integers(2, 4)):
        x, y = rnd.uniform(10, 54), rnd.uniform(8, 40)
        for _ in range(rnd.integers(3, 6)):
            dx, dy = rnd.uniform(-1, 1), rnd.uniform(0.4, 1.0)
            ln = rnd.uniform(3, 6)
            stroke(col, x, y, dx, dy, ln, (56, 52, 46), (64, 60, 52), 1.0, 0.9)
            stroke(col, x + 0.9, y, dx, dy, ln, (190, 184, 168), (176, 170, 156), 0.5, 0.5)
            x, y = x + dx * ln, y + dy * ln
    # loose stones and lichen
    for _ in range(rnd.integers(4, 9)):
        g = rnd.uniform(0.8, 1.2)
        blob(col, rnd.uniform(4, 60), rnd.uniform(4, 60), rnd.uniform(0.9, 2.0), rnd.uniform(0.7, 1.5), (140 * g, 134 * g, 122 * g), 1.0)
    for _ in range(rnd.integers(3, 7)):
        c = [(132, 146, 92), (170, 168, 112), (196, 170, 96)][rnd.integers(0, 3)]
        blob(col, rnd.uniform(6, 58), rnd.uniform(6, 58), rnd.uniform(0.8, 1.6), rnd.uniform(0.6, 1.2), c, 0.75, False, False)
    return col


# ---------------------------------------------------------------- roads
# 16 shapes each: bit 1 = the road goes up, 2 = right, 4 = down, 8 = left. Every shape is cut from the
# same wrapping road surface, so pieces join without seams; the edge wobbles a little with noise.
HALF = 12.0                         # half the road's width, in pixels of the 64 x 64 tile


def road_mask(m, ragged):
    xs = np.arange(N) + 0.5
    X, Y = np.meshgrid(xs, xs)
    c = N / 2
    # distance outside the road's shape: the middle square plus an arm to each joined side
    d = np.maximum(np.abs(X - c), np.abs(Y - c)) - HALF
    def arm(cond, dd):
        return np.minimum(d_, dd) if cond else d_
    d_ = d
    if m & 1: d_ = np.minimum(d_, np.maximum(np.abs(X - c) - HALF, Y - c))
    if m & 2: d_ = np.minimum(d_, np.maximum(np.abs(Y - c) - HALF, c - X))
    if m & 4: d_ = np.minimum(d_, np.maximum(np.abs(X - c) - HALF, c - Y))
    if m & 8: d_ = np.minimum(d_, np.maximum(np.abs(Y - c) - HALF, X - c))
    # rounded inner corners where two arms meet: a small round blend
    d_ = d_ + ragged
    return d_, X, Y


def dirt_roads():
    rnd = np.random.default_rng(900)
    rag = (fbm(901, ((8, 0.6), (16, 0.4))) - 0.5) * 5.0
    base = fbm(902, ((4, 0.4), (8, 0.35), (16, 0.25)))
    pebbles = []
    for _ in range(26):
        pebbles.append((rnd.uniform(0, N), rnd.uniform(0, N), rnd.uniform(0.7, 1.5), rnd.uniform(0.8, 1.15)))
    for m in range(16):
        d, X, Y = road_mask(m, rag)
        alpha = np.clip(0.5 - d / 2.6, 0, 1)
        col = ramp(base, [(0.0, (142, 112, 74)), (0.5, (168, 138, 96)), (1.0, (186, 158, 114))])
        c = N / 2
        # wheel ruts along each arm (and round the middle), the worn hump between them lighter
        rut = np.zeros((N, N), np.float32)
        hump = np.zeros((N, N), np.float32)
        vert = (m & 5) != 0
        hor = (m & 10) != 0
        if vert or not hor:
            for off in (-6.5, 6.5):
                rut = np.maximum(rut, np.exp(-((X - c - off) / 2.6) ** 2))
            hump = np.maximum(hump, np.exp(-((X - c) / 3.5) ** 2))
        if hor:
            for off in (-6.5, 6.5):
                rut = np.maximum(rut, np.exp(-((Y - c - off) / 2.6) ** 2) * (1.0 if not vert else 0.7))
            hump = np.maximum(hump, np.exp(-((Y - c) / 3.5) ** 2))
        col = shade(col, 1.0 - rut * 0.09 + hump * 0.05 + lit(base * 0.6 - rut * 0.25, 6.0) * 0.12 + (rnd.random((N, N)) - 0.5) * 0.05)
        # trodden-in pebbles
        for (px, py, r, g) in pebbles:
            blob(col, px, py, r, r * 0.8, (150 * g, 140 * g, 120 * g), 0.9)
        # the edge: a darker rim where the road cuts into the grass
        rim = np.clip(1 - np.abs(d + 1.5) / 2.5, 0, 1)
        col = shade(col, 1 - rim * 0.13)
        rgba = np.concatenate([np.clip(col, 0, 255), alpha[..., None] * 255], 2)
        Image.fromarray(rgba.astype(np.uint8), "RGBA").save(os.path.join(OUT, "road_%d.png" % m)) if (FORCE or not os.path.exists(os.path.join(OUT, "road_%d.png" % m))) else None


def cobble_roads():
    rnd = np.random.default_rng(950)
    # cobbles: a jittered grid that wraps (8 stones across a tile), each stone a lit dome
    n = 8
    cell = N / n
    pts = []
    for j in range(n):
        for i in range(n):
            pts.append(((i + 0.5 + rnd.uniform(-0.22, 0.22)) * cell, (j + 0.5 + rnd.uniform(-0.22, 0.22)) * cell, rnd.uniform(0.85, 1.12)))
    xs = np.arange(N) + 0.5
    X, Y = np.meshgrid(xs, xs)
    d1 = np.full((N, N), 1e9); d2 = np.full((N, N), 1e9)
    near = np.zeros((N, N), np.int32)
    vx = np.zeros((N, N)); vy = np.zeros((N, N))
    for k, (px, py, _) in enumerate(pts):
        dx = (X - px + N / 2) % N - N / 2
        dy = (Y - py + N / 2) % N - N / 2
        dd = np.sqrt(dx * dx + dy * dy)
        closer = dd < d1
        d2 = np.where(closer, d1, np.minimum(d2, dd))
        vx = np.where(closer, dx, vx); vy = np.where(closer, dy, vy)
        near = np.where(closer, k, near)
        d1 = np.where(closer, dd, d1)
    edge = d2 - d1                       # 0 on the line between two stones
    r = cell * 0.55
    nz = np.sqrt(np.clip(1 - (d1 / r) ** 2, 0, 1))
    light = np.clip(-(vx / r) * LIGHT[0] - (vy / r) * LIGHT[1] + nz * 0.6, 0, 1.5)
    tone = np.array([p[2] for p in pts])[near]
    stone = np.array([150, 146, 136], np.float32)[None, None, :] * (0.62 + 0.42 * light * tone)[..., None]
    gap = np.clip(1 - edge / 1.4, 0, 1)
    dirtc = np.array([92, 84, 70], np.float32)
    rag = (fbm(951, ((8, 0.6), (16, 0.4))) - 0.5) * 0.8
    for m in range(16):
        d, X2, Y2 = road_mask(m, rag)
        alpha = np.clip(0.5 - d / 0.8, 0, 1)
        col = stone * (1 - gap[..., None]) + dirtc * gap[..., None]
        col = shade(col, 1 + (rnd.random((N, N)) - 0.5) * 0.05)
        # kerb stones along the edge: a lighter band with joints
        kerb = (d > -3.2) & (d < 0.2)
        kj = ((np.floor((X2 + Y2) / 5.0) % 2) == 0)
        col[kerb] = np.array([170, 166, 156], np.float32) * np.where(kj[kerb], 1.0, 0.92)[:, None]
        rim = np.clip(1 - np.abs(d + 0.2) / 0.8, 0, 1)
        col = shade(col, 1 - rim * 0.35)
        rgba = np.concatenate([np.clip(col, 0, 255), alpha[..., None] * 255], 2)
        path = os.path.join(OUT, "road_paved_%d.png" % m)
        if FORCE or not os.path.exists(path):
            Image.fromarray(rgba.astype(np.uint8), "RGBA").save(path)


def build_all():
    os.makedirs(OUT, exist_ok=True)
    for v in range(4):
        save(grass(v), "terrain_grass_%d" % v)
        save(beach(v), "terrain_beach_%d" % v)
        save(water(v), "terrain_water_%d" % v)
        save(mountain(v), "terrain_mountain_%d" % v)
    dirt_roads()
    cobble_roads()


if __name__ == "__main__":
    build_all()
    print("ground tiles in", OUT)
