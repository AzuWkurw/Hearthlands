#!/usr/bin/env python3
"""Trees, mountain peaks and boulders for the map, drawn with light and shade so they look round.

Each object is modelled as simple shapes (spheres for leaf clumps and stones, cones for fir tiers,
cylinders for trunks, two faces for a peak). Every pixel is lit from the upper left by its surface
direction, with a little ambient light, darker hollows low in the crown, leaf or rock grain, and a
soft shadow cast to the lower right on the ground. Everything is drawn 4 times larger and shrunk.

Trees and peaks are 64 x 96 (one tile wide, one and a half tall), boulders 64 x 64.

Usage:  python3 tools/make_scenery.py [--force]      (also run by make_textures.py)
"""
import os, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "textures")
FORCE = "--force" in sys.argv
SS = 4
LIGHT = np.array([-0.55, -0.62, 0.56])
LIGHT = LIGHT / np.linalg.norm(LIGHT)


class Canvas:
    def __init__(self, w, h, seed):
        self.w, self.h = w, h
        self.W, self.H = w * SS, h * SS
        self.rgb = np.zeros((self.H, self.W, 3), np.float32)
        self.a = np.zeros((self.H, self.W), np.float32)
        self.rng = np.random.default_rng(seed)
        yy, xx = np.mgrid[0:self.H, 0:self.W]
        # design units (pixels of the final picture)
        self.x = (xx + 0.5) / SS
        self.y = (yy + 0.5) / SS

    def noise(self, cell, amp):
        """Smooth value noise with cells `cell` design pixels across, from -amp to +amp."""
        gw, gh = int(self.w / cell) + 3, int(self.h / cell) + 3
        g = self.rng.random((gh, gw))
        fx = self.x / cell
        fy = self.y / cell
        ix, iy = fx.astype(int), fy.astype(int)
        u, v = fx - ix, fy - iy
        u, v = u * u * (3 - 2 * u), v * v * (3 - 2 * v)
        a = g[iy, ix]; b = g[iy, ix + 1]; c = g[iy + 1, ix]; d = g[iy + 1, ix + 1]
        return ((a + (b - a) * u) * (1 - v) + (c + (d - c) * u) * v - 0.5) * 2 * amp

    def put(self, mask, col, alpha=1.0):
        """Paints colour col (H x W x 3 or a triple) over the picture where mask (0..1) is set."""
        m = np.clip(mask, 0, 1) * alpha
        col = np.asarray(col, np.float32)
        if col.ndim == 1:
            col = col[None, None, :]
        self.rgb = self.rgb * (1 - m[:, :, None]) + col * m[:, :, None]
        self.a = self.a + m * (1 - self.a)

    def shadow(self, cx, cy, rx, ry, strength=0.42):
        """A soft shadow on the ground, under what is drawn after it."""
        d = ((self.x - cx) / rx) ** 2 + ((self.y - cy) / ry) ** 2
        m = np.clip(1.0 - d, 0, 1) ** 1.2 * strength
        self.rgb = self.rgb * (1 - m[:, :, None])
        self.a = self.a + m * (1 - self.a)

    def done(self):
        img = np.concatenate([np.clip(self.rgb, 0, 255), np.clip(self.a * 255, 0, 255)[:, :, None]], axis=2)
        # premultiply while shrinking, so dark empty pixels don't bleed into the edges
        pm = img.copy()
        pm[:, :, :3] *= self.a[:, :, None]
        im = Image.fromarray(pm.astype(np.uint8), "RGBA").resize((self.w, self.h), Image.LANCZOS)
        am = Image.fromarray((self.a * 255).astype(np.uint8), "L").resize((self.w, self.h), Image.LANCZOS)
        out = np.asarray(im).astype(np.float32)
        al = np.asarray(am).astype(np.float32) / 255.0
        out[:, :, :3] = np.where(al[:, :, None] > 0.01, out[:, :, :3] / np.maximum(al[:, :, None], 0.01), 0)
        out[:, :, 3] = al * 255
        return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def lit(nx, ny, nz, amb=0.46, dif=0.82):
    return amb + dif * np.clip(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0, 1)


def sphere(c, cx, cy, r, base, grain=0.0, rough=0.0, ao_top=None, ao_bot=None, squash=1.0):
    """A lit ball (a leaf clump, a stone). rough makes the outline bumpy; ao darkens its lower part
    when it sits low in a crown."""
    dx = (c.x - cx) / r
    dy = (c.y - cy) / (r * squash)
    d2 = dx * dx + dy * dy
    edge = 1.0 + (c.noise(r * 0.35, rough) if rough else 0.0)
    m = np.clip((edge - np.sqrt(d2)) * r * SS * 0.5, 0, 1)
    nz = np.sqrt(np.clip(1 - np.minimum(d2, 1), 0, 1))
    shade = lit(dx, dy, nz)
    if grain:
        shade = shade * (1 + c.noise(1.2, grain) + c.noise(0.6, grain * 0.6))
    if ao_bot is not None:
        shade = shade * np.clip(1 - np.clip((c.y - ao_top) / (ao_bot - ao_top), 0, 1) * 0.35, 0.5, 1)
    c.put(m, np.asarray(base, np.float32)[None, None, :] * shade[:, :, None])


def trunk(c, cx, y0, y1, w0, w1, base, marks=None):
    """A trunk narrowing from w0 at the foot (y1) to w1 at the top (y0), lit as a cylinder."""
    t = np.clip((c.y - y0) / (y1 - y0), 0, 1)
    half = (w1 + (w0 - w1) * t) / 2
    dx = (c.x - cx) / np.maximum(half, 0.1)
    inside = (np.abs(dx) <= 1) & (c.y >= y0) & (c.y <= y1)
    m = np.clip((1 - np.abs(dx)) * half * SS, 0, 1) * inside
    nz = np.sqrt(np.clip(1 - dx * dx, 0, 1))
    shade = lit(dx, np.zeros_like(dx), nz, 0.42, 0.75) * (1 + c.noise(0.8, 0.08))
    col = np.asarray(base, np.float32)[None, None, :] * shade[:, :, None]
    if marks is not None:
        mk = (c.noise(1.6, 1.0) > 0.45) & (np.abs(dx) < 0.95)
        col = np.where(mk[:, :, None], np.asarray(marks, np.float32)[None, None, :] * shade[:, :, None], col)
    c.put(m, col)


def fir_tier(c, cx, top, bot, half, base, jag=0.14):
    """One skirt of a fir: a cone seen from the side, lit on the left, its lower edge ragged."""
    t = (c.y - top) / (bot - top)
    hw = half * np.clip(t, 0, 1)
    dx = (c.x - cx) / np.maximum(hw, 0.3)
    ragged = bot + c.noise(1.3, (bot - top) * jag) - np.abs(dx) * (bot - top) * 0.12
    inside = (t >= 0) & (np.abs(dx) <= 1) & (c.y <= ragged)
    m = np.clip(np.minimum((1 - np.abs(dx)) * hw * SS * 0.5, (ragged - c.y) * SS * 0.5), 0, 1) * inside
    nz = np.sqrt(np.clip(1 - dx * dx, 0, 1)) * 0.8
    ny = -0.45 + t * 0.2        # the cone's surface leans back
    shade = lit(dx * 0.95, ny, nz, 0.34, 0.9)
    # the tier above shades this one's top; the needles give it texture
    shade = shade * (0.55 + 0.5 * np.clip(t, 0, 1) ** 0.8)
    shade = shade * (1 + c.noise(0.9, 0.16) + c.noise(2.5, 0.08))
    c.put(m, np.asarray(base, np.float32)[None, None, :] * shade[:, :, None])


def crown(c, clumps, base, light_col, rough=0.18, grain=0.14, top=None, bot=None, grow=1.0, at=(32, 36)):
    """A crown of leaf clumps, drawn back to front: the clumps higher up and further back first.
    grow spreads the clumps out from `at` and makes them bigger."""
    clumps = [(at[0] + (x - at[0]) * grow, at[1] + (y - at[1]) * grow, r * grow) for (x, y, r) in clumps]
    if top is not None:
        top, bot = at[1] + (top - at[1]) * grow, at[1] + (bot - at[1]) * grow
    for (x, y, r) in sorted(clumps, key=lambda k: k[1] + k[2] * 0.3):
        # higher clumps catch more light: blend the base towards the light colour
        f = np.clip((bot - y) / (bot - top), 0, 1) * 0.5 if top is not None else 0.25
        col = np.asarray(base, np.float32) * (1 - f) + np.asarray(light_col, np.float32) * f
        sphere(c, x, y, r, col, grain=grain, rough=rough, ao_top=top, ao_bot=bot)


def save(img, name):
    p = os.path.join(OUT, name + ".png")
    if os.path.exists(p) and not FORCE:
        return
    img.save(p)


def trees():
    # 0: fir, tiers of needles narrowing to a point
    c = Canvas(64, 96, 10)
    c.shadow(38, 89, 20, 5.5)
    trunk(c, 32, 70, 91, 6, 4.5, (96, 64, 36))
    tiers = [(4, 30, 11), (14, 45, 17), (26, 62, 23), (40, 80, 29)]
    for (top, bot, half) in reversed(tiers):
        fir_tier(c, 32, top, bot, half, (52, 108, 58))
    save(c.done(), "deco_tree_0")
    # 1: broad-leaved tree (an oak), a big crown of rounded clumps on a short, strong trunk
    c = Canvas(64, 96, 11)
    c.shadow(38, 88, 24, 6.5)
    trunk(c, 32, 46, 90, 9, 6, (104, 72, 44))
    for (x0, y0, x1, y1) in [(31, 60, 20, 44), (33, 62, 45, 46)]:
        for k in range(6):
            tt = k / 5.0
            sphere(c, x0 + (x1 - x0) * tt, y0 + (y1 - y0) * tt, 2.4 - tt * 0.8, (104, 72, 44))
    clumps = [(32, 20, 13), (19, 30, 11), (45, 30, 11), (24, 44, 12), (41, 44, 12), (32, 36, 13),
              (14, 42, 8), (51, 41, 8), (32, 50, 10), (26, 17, 9), (40, 18, 9)]
    crown(c, clumps, (58, 114, 50), (130, 186, 88), top=8, bot=58, grow=1.2, at=(32, 34))
    save(c.done(), "deco_tree_1")
    # 2: birch, a slim white trunk with dark marks and a light, airy crown
    c = Canvas(64, 96, 12)
    c.shadow(37, 90, 16, 4.5)
    trunk(c, 32, 30, 91, 5, 3, (236, 232, 222), marks=(54, 50, 44))
    clumps = [(32, 16, 9), (24, 26, 8), (40, 25, 8), (30, 36, 9), (38, 40, 7), (25, 46, 6),
              (33, 50, 6), (29, 10, 6), (37, 12, 6)]
    crown(c, clumps, (110, 160, 66), (184, 220, 116), rough=0.25, grain=0.16, top=4, bot=56, grow=1.2, at=(32, 25))
    save(c.done(), "deco_tree_2")
    # 3: a tall, slim spruce
    c = Canvas(64, 96, 13)
    c.shadow(37, 90, 15, 4.5)
    trunk(c, 32, 76, 92, 5, 4, (88, 58, 34))
    tiers = [(1, 22, 8), (9, 35, 12), (18, 48, 15), (28, 62, 18), (39, 77, 20), (53, 87, 22)]
    for (top, bot, half) in reversed(tiers):
        fir_tier(c, 32, top, bot, half, (42, 94, 58), jag=0.18)
    save(c.done(), "deco_tree_3")
    # 4: a round lime tree with a lighter, denser crown
    c = Canvas(64, 96, 14)
    c.shadow(38, 89, 21, 5.5)
    trunk(c, 32, 50, 90, 7, 5, (110, 82, 54))
    clumps = [(32, 24, 14), (21, 34, 11), (43, 34, 11), (32, 44, 13), (24, 52, 8), (41, 52, 8),
              (27, 18, 9), (38, 17, 9), (16, 26, 7), (48, 26, 7)]
    crown(c, clumps, (70, 126, 48), (156, 200, 92), rough=0.14, top=10, bot=60, grow=1.18, at=(32, 36))
    save(c.done(), "deco_tree_4")


def rocks():
    for v in range(2):
        c = Canvas(64, 64, 20 + v)
        stones = [(31, 40, 17, 0.8)] if v == 0 else [(23, 43, 13, 0.78), (40, 47, 10, 0.75), (34, 36, 9, 0.85)]
        c.shadow(38, 56, 25, 6.5, 0.45)
        for (x, y, r, sq) in sorted(stones, key=lambda s: s[1]):
            sphere(c, x, y, r, (138, 134, 124), grain=0.16, rough=0.1, squash=sq)
            # cracks
        save(c.done(), f"deco_rock_{v}")


def peaks():
    for v in range(2):
        c = Canvas(64, 96, 30 + v)
        tx, ty = 30 + v * 5, 10 + v * 10      # the summit
        base = 93
        lx, rx = 1, 63
        c.shadow(40, 92, 30, 5, 0.35)
        # left (lit) and right (shaded) faces, split by a ridge that wanders down from the summit
        ridge = tx + 3 + (c.y - ty) * 0.18 + c.noise(4, 2.5)
        tl = (c.y - ty) / (base - ty)
        left_edge = tx - (tx - lx) * tl + c.noise(3, 1.2) * np.clip(tl * 3, 0, 1)
        right_edge = tx + (rx - tx) * tl + c.noise(3, 1.2) * np.clip(tl * 3, 0, 1)
        m = np.clip(np.minimum(np.minimum(c.x - left_edge, right_edge - c.x), base - c.y) * SS * 0.5, 0, 1) * (c.y >= ty)
        lit_side = c.x < ridge
        rockc = np.array([132, 124, 108], np.float32)
        # the lit face brightest near the ridge, the shaded face darkest just behind it
        across_l = np.clip((c.x - left_edge) / np.maximum(ridge - left_edge, 1), 0, 1)
        across_r = np.clip((c.x - ridge) / np.maximum(right_edge - ridge, 1), 0, 1)
        shade = np.where(lit_side, 0.95 + 0.3 * across_l, 0.52 + 0.14 * across_r)
        # dark gathers at the foot
        shade = shade * (1 + c.noise(1.5, 0.1) + c.noise(5, 0.08)) * (1.06 - 0.26 * np.clip(tl, 0, 1))
        # ledges: darker lines slanting down the faces
        led = np.abs(np.sin((c.y - c.x * 0.35 * np.where(lit_side, 1, -1)) * 0.55 + c.noise(4, 1.5))) < 0.12
        shade = np.where(led & (tl > 0.15), shade * 0.82, shade)
        col = rockc[None, None, :] * shade[:, :, None]
        # snow on the upper part, lit and shaded the same way
        snow_line = ty + (base - ty) * (0.24 + 0.06 * v) + c.noise(2.5, 3.5)
        snow = c.y < snow_line
        snowc = np.array([238, 242, 248], np.float32)[None, None, :] * np.where(lit_side, 1.0, 0.8)[:, :, None]
        col = np.where(snow[:, :, None], snowc, col)
        c.put(m, col)
        save(c.done(), f"deco_peak_{v}")


def build_all():
    os.makedirs(OUT, exist_ok=True)
    trees(); rocks(); peaks()


if __name__ == "__main__":
    build_all()
