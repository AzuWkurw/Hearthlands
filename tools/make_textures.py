#!/usr/bin/env python3
"""Generate Hearthlands' default textures into ../textures.

Usage:  python3 tools/make_textures.py            # only writes files that are missing
        python3 tools/make_textures.py --force    # overwrites everything

Needs Pillow and numpy (pip install pillow numpy). Reads data/resources.json and data/buildings.json,
so new resources and buildings you add there get a sprite automatically.

Everything is drawn SS times larger than needed and then shrunk with a high-quality filter, which
gives smooth (anti-aliased) edges. Animated sprites are strips of frames side by side.
"""
import json, math, os, random, sys, zlib
import bld_tex as BT
import numpy as np
from PIL import Image, ImageChops, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "textures")
FORCE = "--force" in sys.argv
SS = 4
os.makedirs(OUT, exist_ok=True)


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def sh(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + ((c[3],) if len(c) > 3 else (255,))


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)


def new(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


POLISH = ("bld_", "deco_tree", "deco_peak", "deco_rock", "anim_")


def save(img, name):
    p = os.path.join(OUT, name + ".png")
    if os.path.exists(p) and not FORCE:
        return
    if name.startswith(POLISH):
        img = polish(img, name)
    img.save(p)


def polish(img, name):
    """The finishing pass for buildings and scenery: a fine grain on every surface, light falling from
    above (brighter roofs, darker footings), a lit rim on the upper-left edges and a dark outline
    around the shape so it stands out from the ground."""
    a = np.asarray(img.convert("RGBA")).astype(np.float32)
    h, w = a.shape[:2]
    alpha = a[:, :, 3]
    solid = alpha >= 200
    if not solid.any():
        return img
    rs = np.random.default_rng(zlib.crc32(name.encode()))
    # grain: per-pixel speckle plus soft blotches, a few percent either way
    # (buildings carry their own textures now, so they get less grain than the scenery)
    gk = 0.5 if name.startswith("bld_") else 1.0
    grain = (rs.random((h, w)) - 0.5) * 0.07 * gk
    blot = np.kron(rs.random((h // 4 + 1, w // 4 + 1)) - 0.5, np.ones((4, 4)))[:h, :w] * 0.06 * gk
    # light from above, measured over the shape's own height
    ys = np.where(solid.any(axis=1))[0]
    top, bot = ys[0], max(ys[-1], ys[0] + 1)
    yy = np.clip((np.arange(h) - top) / (bot - top), 0, 1)
    light = (1.08 - 0.18 * yy ** 1.5)[:, None]
    f = (1.0 + grain + blot) * light
    # rim light where the shape meets empty space on its left or top
    left = np.zeros_like(solid); left[:, 1:] = ~solid[:, :-1]
    up = np.zeros_like(solid); up[1:, :] = ~solid[:-1, :]
    f = np.where(solid & (left | up), f * 1.14, f)
    rgbv = a[:, :, :3]
    rgbv = np.where(solid[:, :, None], np.clip(rgbv * f[:, :, None], 0, 255), rgbv)
    out = np.concatenate([rgbv, alpha[:, :, None]], axis=2)
    # outline: empty-ish pixels next to the shape get a dark edge (2 pixels on big sprites)
    k = 2 if w >= 96 else 1
    grow = solid.copy()
    for dy in range(-k, k + 1):
        for dx in range(-k, k + 1):
            if dx * dx + dy * dy > k * k:
                continue
            sh_ = np.zeros_like(solid)
            ys0, ys1 = max(0, dy), h + min(0, dy)
            xs0, xs1 = max(0, dx), w + min(0, dx)
            sh_[ys0:ys1, xs0:xs1] = solid[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx]
            grow |= sh_
    edge = grow & (alpha < 128)
    line = np.array([34, 26, 18], np.float32)
    ea = 170.0
    cur_a = alpha[edge] / 255.0
    na = ea / 255.0 + cur_a * (1 - ea / 255.0)
    out[edge, :3] = (line * (ea / 255.0) + out[edge, :3] * cur_a[:, None] * (1 - ea / 255.0)) / na[:, None]
    out[edge, 3] = na * 255.0
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


class Pen:
    """Works like PIL's ImageDraw, but in 'design pixels': a w x h design comes out k times larger.
    Drawing happens on a canvas SS times larger again; done() shrinks it, smoothing every edge."""

    def __init__(self, w, h, k=1):
        self.w, self.h, self.k, self.f = w, h, k, k * SS
        self.im = Image.new("RGBA", (round(w * self.f), round(h * self.f)), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def _p(self, pts):
        if pts and isinstance(pts[0], (int, float)):
            pts = [(pts[i], pts[i + 1]) for i in range(0, len(pts), 2)]
        return [((x + 0.5) * self.f - 0.5, (y + 0.5) * self.f - 0.5) for x, y in pts]

    def _box(self, b):
        x0, y0, x1, y1 = b
        f = self.f
        return [x0 * f, y0 * f, max(x0 * f, (x1 + 1) * f - 1), max(y0 * f, (y1 + 1) * f - 1)]

    def _w(self, w):
        return max(1, round(w * self.f))

    def rectangle(self, b, fill=None, outline=None, width=1):
        self.d.rectangle(self._box(b), fill=fill, outline=outline, width=self._w(width) if outline else 0)

    def rounded_rectangle(self, b, r, fill=None, outline=None, width=1):
        self.d.rounded_rectangle(self._box(b), r * self.f, fill=fill, outline=outline, width=self._w(width) if outline else 0)

    def ellipse(self, b, fill=None, outline=None, width=1):
        self.d.ellipse(self._box(b), fill=fill, outline=outline, width=self._w(width) if outline else 0)

    def pieslice(self, b, a0, a1, fill=None, outline=None, width=1):
        self.d.pieslice(self._box(b), a0, a1, fill=fill, outline=outline, width=self._w(width) if outline else 0)

    def arc(self, b, a0, a1, fill=None, width=1):
        self.d.arc(self._box(b), a0, a1, fill=fill, width=self._w(width))

    def polygon(self, pts, fill=None, outline=None, width=1):
        self.d.polygon(self._p(pts), fill=fill, outline=outline, width=self._w(width) if outline else 0)

    def line(self, pts, fill=None, width=1):
        self.d.line(self._p(pts), fill=fill, width=self._w(width), joint="curve")

    def point(self, pts, fill=None):
        if pts and isinstance(pts[0], (int, float)):
            pts = [pts]
        for x, y in pts:
            self.rectangle([x, y, x, y], fill=fill)

    def disc(self, x, y, r, fill):
        self.ellipse([x - r, y - r, x + r - 1, y + r - 1], fill=fill)

    def clipped(self, pts, draw):
        """Runs draw(pen) on a fresh layer and keeps only what lands inside the polygon pts."""
        layer = Pen(self.w, self.h, self.k)
        draw(layer)
        mask = Image.new("L", self.im.size, 0)
        ImageDraw.Draw(mask).polygon(self._p(pts), fill=255)
        layer.im.putalpha(ImageChops.multiply(layer.im.getchannel("A"), mask))
        self.im.alpha_composite(layer.im)

    def shade(self, pts, y0, y1, c0, c1):
        """A vertical gradient from colour c0 at y0 to c1 at y1 (RGBA), laid over the polygon pts."""
        H = self.im.size[1]
        a, b = (y0 + 0.5) * self.f, (y1 + 0.5) * self.f
        t = np.clip((np.arange(H) - a) / max(1.0, b - a), 0.0, 1.0)[:, None]
        g = np.zeros((H, self.im.size[0], 4), np.float32)
        for i in range(4):
            g[:, :, i] = c0[i] + (c1[i] - c0[i]) * t
        layer = Image.fromarray(g.astype(np.uint8), "RGBA")
        mask = Image.new("L", self.im.size, 0)
        ImageDraw.Draw(mask).polygon(self._p(pts), fill=255)
        layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
        self.im.alpha_composite(layer)

    def _poly_box(self, pts):
        P = self._p(pts)
        xs = [q[0] for q in P]; ys = [q[1] for q in P]
        x0 = max(0, int(min(xs)) - 1); y0 = max(0, int(min(ys)) - 1)
        x1 = min(self.im.size[0], int(max(xs)) + 2); y1 = min(self.im.size[1], int(max(ys)) + 2)
        return P, x0, y0, x1, y1

    def texfill(self, pts, tex, mult=1.0):
        """Fills the polygon pts with a texture: tex(w, h, f) gives an RGBA picture of w x h canvas
        pixels (f canvas pixels a design pixel), laid with its corner at the polygon's top left."""
        P, x0, y0, x1, y1 = self._poly_box(pts)
        if x1 <= x0 or y1 <= y0:
            return
        img = tex(x1 - x0, y1 - y0, self.f)
        if mult != 1.0:
            a = np.asarray(img).astype(np.float32)
            a[..., :3] *= mult
            img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
        mask = Image.new("L", (x1 - x0, y1 - y0), 0)
        ImageDraw.Draw(mask).polygon([(q[0] - x0, q[1] - y0) for q in P], fill=255)
        img.putalpha(ImageChops.multiply(img.getchannel("A"), mask))
        self.im.alpha_composite(img, (x0, y0))

    def texmask(self, draw, tex, mult=1.0):
        """Draws with draw(pen) on a mask, then fills what was drawn with the texture tex (as texfill)."""
        layer = Pen(self.w, self.h, self.k)
        draw(layer)
        al = layer.im.getchannel("A")
        box = al.getbbox()
        if box is None:
            return
        x0, y0, x1, y1 = box
        img = tex(x1 - x0, y1 - y0, self.f)
        if mult != 1.0:
            a = np.asarray(img).astype(np.float32)
            a[..., :3] *= mult
            img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
        img.putalpha(ImageChops.multiply(img.getchannel("A"), al.crop(box)))
        self.im.alpha_composite(img, (x0, y0))

    def texslope(self, quad, tex, mult=1.0):
        """Fills a roof slope with a texture made in roof space (rows across, the ridge at the top) and
        slanted to the slope: quad = [bottom left, bottom right, top right, top left] (design pixels)."""
        P, x0, y0, x1, y1 = self._poly_box(quad)
        bl, br, tr, tl = P
        hgt = max(1.0, bl[1] - tl[1])
        s = (tl[0] - bl[0]) / hgt              # how far the slope leans per canvas pixel up
        wid = int(max(br[0] - bl[0], tr[0] - tl[0]) + 4)
        src = tex(wid, int(hgt) + 4, self.f)
        if mult != 1.0:
            a = np.asarray(src).astype(np.float32)
            a[..., :3] *= mult
            src = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
        W, H = x1 - x0, y1 - y0
        # output (x, y) in the box -> roof space (u, v): v from the ridge down, u from the slanted left edge
        out = src.transform((W, H), Image.Transform.AFFINE,
                            (1, s, x0 - bl[0] - s * (bl[1] - y0), 0, 1, y0 - tl[1]), Image.Resampling.BILINEAR)
        mask = Image.new("L", (W, H), 0)
        ImageDraw.Draw(mask).polygon([(q[0] - x0, q[1] - y0) for q in P], fill=255)
        out.putalpha(ImageChops.multiply(out.getchannel("A"), mask))
        self.im.alpha_composite(out, (x0, y0))

    def paste(self, img, x, y, size):
        """Pastes another picture with its top-left at design (x, y), size design pixels square."""
        s = round(size * self.f)
        self.im.alpha_composite(img.resize((s, s), Image.LANCZOS), (round(x * self.f), round(y * self.f)))

    def done(self):
        out = self.im.convert("RGBa").resize((round(self.w * self.k), round(self.h * self.k)), Image.LANCZOS)
        return out.convert("RGBA")


def strip(frames):
    """Puts equally sized frames side by side into one animation strip."""
    w, h = frames[0].size
    im = new(w * len(frames), h)
    for i, f in enumerate(frames):
        im.alpha_composite(f, (i * w, 0))
    return im


# ---------------------------------------------------------------- noise that tiles seamlessly
def tnoise(n, cells, seed):
    """Smooth random values on an n x n grid that wraps around, so tiles join without seams."""
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


def fbm(n, seed, octaves=((4, 0.5), (8, 0.3), (16, 0.2))):
    return sum(tnoise(n, c, seed + k * 101) * w for k, (c, w) in enumerate(octaves))


def colorize(v, c0, c1):
    v = np.clip(v, 0, 1)[:, :, None]
    a = np.array(c0, np.float32)[None, None, :3]
    b = np.array(c1, np.float32)[None, None, :3]
    rgbv = a + (b - a) * v
    out = np.concatenate([rgbv, np.full(v.shape, 255.0)], axis=2)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


# ---------------------------------------------------------------- terrain
def terrain():
    """Ground tiles, 64x64, four of each kind (make_ground.py): they wrap around, and the variants of a
    kind share their edges, so any neighbours join without seams."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import make_ground
    make_ground.FORCE = FORCE
    make_ground.build_all()


def decos():
    # trees, boulders and mountain peaks: lit, rounded shapes at 64 px a tile (make_scenery.py)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import make_scenery
    make_scenery.FORCE = FORCE
    make_scenery.build_all()
    # clay: a dug pit with layers of wet clay
    p = Pen(32, 32, 2)
    p.ellipse([3, 9, 28, 28], fill=(150, 92, 48, 255), outline=(104, 62, 30, 255))
    p.ellipse([6, 12, 25, 25], fill=(184, 121, 63, 255))
    p.ellipse([9, 15, 22, 23], fill=(140, 84, 44, 255))
    p.ellipse([10, 14, 16, 18], fill=(214, 160, 104, 255))
    for k in range(4):
        p.arc([5 + k, 11 + k, 26 - k, 26 - k], 200, 320, fill=(120, 72, 38, 160), width=0.4)
    p.ellipse([18, 20, 22, 22.5], fill=(150, 180, 200, 140))
    p.line([(24, 8), (21, 17)], fill=(112, 78, 46, 255), width=0.9)
    p.polygon([(20, 16), (22.6, 16.8), (21.6, 20), (19.2, 19.2)], fill=(150, 154, 160, 255), outline=(80, 80, 86, 255), width=0.3)
    save(p.done(), "deco_clay")
    # ore deposits: a few rocks with glinting coloured nuggets
    ores = {1: (34, 34, 36), 2: (176, 100, 70), 3: (246, 206, 70), 4: (220, 220, 210), 5: (206, 116, 58)}
    for k, c in ores.items():
        p = Pen(16, 16, 2)
        for (x, y, r) in [(4, 11, 4), (11, 11, 4), (7.5, 6, 4)]:
            p.disc(x, y, r, (96, 92, 84, 255))
            p.disc(x - 0.5, y - 0.5, r - 1.2, c + (255,))
            p.disc(x - 1.2, y - 1.4, 1.1, sh(c, 1.6))
        save(p.done(), f"ore_{k}")


def roads():
    """16 shapes each: bit 1 = road goes up, 2 = right, 4 = down, 8 = left."""
    rnd = random.Random(5)
    for paved in (False, True):
        for m in range(16):
            p = Pen(32, 32)
            arms = [[10, 10, 21, 21]]
            if m & 1: arms.append([10, -1, 21, 15])
            if m & 2: arms.append([16, 10, 32, 21])
            if m & 4: arms.append([10, 16, 21, 32])
            if m & 8: arms.append([-1, 10, 15, 21])
            if not paved:
                for a in arms:
                    p.rounded_rectangle([a[0] - 1, a[1] - 1, a[2] + 1, a[3] + 1], 4, fill=(122, 98, 62, 200))
                for a in arms:
                    p.rounded_rectangle(a, 3, fill=(170, 142, 98, 255))
                # wheel ruts along each arm
                rut = (138, 112, 74, 255)
                if m & 5:
                    for x in (13, 18):
                        p.line([(x, 0 if m & 1 else 12), (x, 31 if m & 4 else 19)], fill=rut)
                if m & 10:
                    for y in (13, 18):
                        p.line([(0 if m & 8 else 12, y), (31 if m & 2 else 19, y)], fill=rut)
                for _ in range(10):
                    x, y = rnd.randrange(11, 21), rnd.randrange(11, 21)
                    p.point((x, y), fill=rnd.choice([(196, 172, 128, 255), (120, 98, 66, 255)]))
            else:
                for a in arms:
                    p.rectangle([a[0] - 1, a[1] - 1, a[2] + 1, a[3] + 1], fill=(84, 80, 72, 255))
                for a in arms:
                    p.rectangle(a, fill=(96, 92, 84, 255))
                layer_pts = []
                for a in arms:
                    layer_pts.append(a)

                def cobbles(q):
                    for y in range(-1, 33, 4):
                        for x in range(-2 + (y // 4 % 2) * 2, 33, 4):
                            c = rnd.choice([(150, 146, 136, 255), (164, 160, 148, 255), (136, 132, 122, 255)])
                            q.rounded_rectangle([x, y, x + 2, y + 2], 1, fill=c)
                            q.point((x, y), fill=(190, 186, 176, 255))
                for a in arms:
                    p.clipped([(a[0], a[1]), (a[2], a[1]), (a[2], a[3]), (a[0], a[3])], cobbles)
            save(p.done(), f"road_{'paved_' if paved else ''}{m}")


# ---------------------------------------------------------------- resource icons
def icon(shape, c, size=24):
    """A resource icon drawn in a 24x24 design, output size x size pixels."""
    d = Pen(24, 24, size / 24)
    c = c + (255,); dk = sh(c, 0.55); lt = sh(c, 1.3)
    if shape == "donkey":
        # a donkey's head: long face, two tall ears, a dark muzzle
        d.polygon([(8, 21), (7, 12), (10, 8), (15, 8), (18, 12), (17, 21)], fill=c, outline=dk)
        d.polygon([(8, 9), (6, 2), (10, 7)], fill=c, outline=dk)
        d.polygon([(17, 9), (19, 2), (15, 7)], fill=c, outline=dk)
        d.ellipse([8, 16, 17, 22], fill=lt, outline=dk)
        d.ellipse([10, 11, 12, 13], fill=(30, 26, 22, 255)); d.ellipse([14, 11, 16, 13], fill=(30, 26, 22, 255))
        return d.done()
    if shape == "log":
        d.rectangle([5, 8, 20, 16], fill=c, outline=dk); d.ellipse([2, 7, 9, 17], fill=lt, outline=dk); d.ellipse([4, 10, 7, 14], outline=dk)
        d.line([(10, 10), (19, 10)], fill=dk)
    elif shape == "stack":
        for y in (6, 11, 16): d.rectangle([3, y, 21, y + 4], fill=c if y != 11 else lt, outline=dk)
    elif shape == "rock":
        d.polygon([(3, 18), (6, 8), (13, 4), (20, 9), (21, 18)], fill=c, outline=dk); d.polygon([(7, 9), (13, 5), (14, 11)], fill=lt)
    elif shape == "blob":
        d.ellipse([3, 7, 21, 20], fill=c, outline=dk); d.ellipse([7, 9, 13, 13], fill=lt)
    elif shape == "drop":
        d.polygon([(12, 2), (19, 13), (5, 13)], fill=c); d.ellipse([5, 8, 19, 21], fill=c, outline=dk); d.ellipse([8, 12, 11, 16], fill=lt)
    elif shape == "ears":
        for x in (7, 12, 17):
            d.line([(x, 21), (x, 8)], fill=dk, width=1)
            for y in (5, 9, 13): d.ellipse([x - 2, y, x + 2, y + 4], fill=c, outline=dk)
    elif shape == "cone":
        d.polygon([(12, 3), (19, 13), (12, 21), (5, 13)], fill=c, outline=dk); d.line([(6, 10), (18, 10)], fill=dk); d.line([(6, 15), (18, 15)], fill=dk)
    elif shape == "fluff":
        for (x, y) in [(8, 11), (15, 10), (11, 15), (17, 15), (6, 15)]: d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=c, outline=dk)
    elif shape == "hide":
        d.polygon([(4, 6), (9, 4), (15, 4), (20, 6), (19, 13), (21, 20), (12, 18), (3, 20), (5, 13)], fill=c, outline=dk)
    elif shape == "crystal":
        for (x, y) in [(8, 14), (14, 11), (16, 17)]: d.polygon([(x, y - 6), (x + 4, y), (x, y + 5), (x - 4, y)], fill=c, outline=(150, 150, 150, 255))
    elif shape == "lump":
        for (x, y, r) in [(8, 14, 5), (15, 15, 5), (12, 9, 4)]: d.ellipse([x - r, y - r, x + r, y + r], fill=c, outline=(20, 20, 20, 255))
    elif shape == "orechunk":
        d.polygon([(3, 18), (6, 7), (14, 4), (21, 9), (20, 19)], fill=(110, 105, 96, 255), outline=(60, 58, 52, 255))
        for (x, y) in [(9, 10), (14, 13), (10, 15), (16, 8)]: d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=c)
    elif shape == "bricks":
        for row, y in enumerate((5, 11, 17)):
            off = 0 if row % 2 == 0 else 4
            for x in range(-4 + off, 22, 8): d.rectangle([max(2, x), y, min(21, x + 7), y + 5], fill=c, outline=dk)
    elif shape == "sack":
        d.ellipse([4, 7, 20, 22], fill=c, outline=dk); d.rectangle([9, 3, 15, 8], fill=c, outline=dk); d.line([(8, 7), (16, 7)], fill=dk)
    elif shape == "loaf":
        d.ellipse([2, 7, 22, 19], fill=c, outline=dk)
        for x in (8, 12, 16): d.line([(x - 1, 9), (x + 1, 13)], fill=lt, width=2)
    elif shape == "fish":
        d.ellipse([3, 8, 17, 17], fill=c, outline=dk); d.polygon([(16, 12), (22, 7), (22, 18)], fill=c, outline=dk); d.point((7, 11), fill=(0, 0, 0, 255))
    elif shape == "ham":
        d.ellipse([3, 6, 17, 20], fill=c, outline=dk); d.rectangle([15, 11, 21, 15], fill=(240, 230, 210, 255), outline=dk); d.ellipse([6, 9, 11, 13], fill=lt)
    elif shape == "veg":
        # a carrot and a turnip
        d.polygon([(4, 6), (9, 4), (15, 20)], fill=c, outline=dk)
        for x in (4, 6, 8): d.line([(x + 1, 5), (x - 1, 1)], fill=(80, 150, 60, 255), width=1)
        d.ellipse([11, 9, 21, 19], fill=(236, 228, 214, 255), outline=(120, 100, 110, 255)); d.pieslice([11, 9, 21, 19], 180, 360, fill=(170, 90, 150, 255))
        d.line([(16, 9), (15, 4)], fill=(80, 150, 60, 255), width=2); d.line([(16, 9), (19, 5)], fill=(80, 150, 60, 255), width=2)
    elif shape == "apple":
        d.ellipse([4, 6, 20, 21], fill=c, outline=dk); d.line([(12, 7), (13, 3)], fill=(90, 60, 30, 255), width=2); d.ellipse([13, 2, 19, 6], fill=(90, 160, 60, 255)); d.ellipse([7, 9, 10, 13], fill=lt)
    elif shape == "mug":
        d.rectangle([5, 6, 16, 21], fill=c, outline=dk); d.rectangle([5, 4, 16, 8], fill=(250, 248, 240, 255)); d.arc([13, 9, 21, 18], -90, 90, fill=dk, width=2)
    elif shape == "cloth":
        d.rectangle([3, 8, 21, 18], fill=c, outline=dk); d.line([(3, 12), (21, 12)], fill=lt); d.line([(3, 15), (21, 15)], fill=sh(c, 0.8))
    elif shape == "flat":
        d.rounded_rectangle([3, 6, 21, 18], 3, fill=c, outline=dk); d.line([(6, 9), (18, 9)], fill=lt)
    elif shape == "ingot":
        d.polygon([(2, 18), (6, 10), (18, 10), (22, 18)], fill=c, outline=dk); d.polygon([(6, 10), (18, 10), (16, 13), (8, 13)], fill=lt)
    elif shape == "hammer":
        d.line([(6, 20), (15, 9)], fill=(120, 84, 48, 255), width=3); d.polygon([(10, 4), (20, 10), (17, 14), (8, 8)], fill=c, outline=dk)
    elif shape == "sword":
        d.line([(5, 19), (19, 5)], fill=(210, 214, 220, 255), width=3); d.line([(6, 13), (11, 18)], fill=c, width=3); d.line([(3, 21), (6, 18)], fill=(110, 70, 40, 255), width=3)
    elif shape == "shield":
        d.polygon([(4, 4), (20, 4), (20, 12), (12, 21), (4, 12)], fill=c, outline=dk); d.line([(12, 5), (12, 19)], fill=lt, width=2)
    elif shape == "shirt":
        d.polygon([(4, 7), (9, 4), (15, 4), (20, 7), (18, 11), (16, 10), (16, 21), (8, 21), (8, 10), (6, 11)], fill=c, outline=dk)
    elif shape == "ring":
        d.ellipse([5, 8, 19, 22], outline=c, width=3); d.polygon([(12, 2), (16, 7), (12, 10), (8, 7)], fill=(150, 220, 240, 255), outline=dk)
    elif shape == "chair":
        d.rectangle([7, 3, 9, 21], fill=c); d.rectangle([7, 12, 18, 14], fill=c, outline=dk); d.rectangle([16, 14, 18, 21], fill=c); d.rectangle([7, 3, 9, 13], fill=c, outline=dk)
    elif shape == "heap":
        d.polygon([(2, 20), (8, 9), (12, 6), (16, 9), (22, 20)], fill=c, outline=dk); d.polygon([(8, 9), (12, 6), (11, 14)], fill=lt)
        for (x, y) in [(7, 17), (12, 15), (16, 18), (10, 11)]: d.point((x, y), fill=dk)
    elif shape == "goblet":
        d.polygon([(6, 3), (18, 3), (16, 11), (8, 11)], fill=c, outline=dk); d.rectangle([11, 11, 13, 17], fill=c, outline=dk)
        d.ellipse([7, 17, 17, 21], fill=c, outline=dk); d.line([(8, 5), (9, 9)], fill=(255, 255, 255, 220), width=1)
    elif shape == "pail":
        d.polygon([(5, 8), (19, 8), (17, 21), (7, 21)], fill=(150, 112, 70, 255), outline=(90, 62, 36, 255))
        d.ellipse([5, 6, 19, 10], fill=c, outline=dk); d.arc([5, 1, 19, 15], 200, 340, fill=(80, 80, 80, 255), width=1)
        d.line([(6, 13), (18, 13)], fill=(90, 62, 36, 255)); d.line([(7, 18), (17, 18)], fill=(90, 62, 36, 255))
    elif shape == "wedge":
        d.polygon([(3, 18), (21, 18), (21, 10), (3, 14)], fill=c, outline=dk); d.polygon([(3, 14), (21, 10), (17, 6)], fill=lt, outline=dk)
        for (x, y, r) in [(8, 16, 1.5), (14, 14, 1.2), (18, 15, 1.5)]: d.ellipse([x - r, y - r, x + r, y + r], fill=sh(c, 0.75))
    elif shape == "links":
        for (x, y) in [(6, 15), (12, 12), (18, 9)]:
            d.ellipse([x - 4, y - 3, x + 4, y + 3], fill=c, outline=dk); d.ellipse([x - 2, y - 2, x, y], fill=lt)
    elif shape == "jar":
        d.ellipse([4, 8, 20, 22], fill=c, outline=dk); d.rectangle([8, 4, 16, 9], fill=(230, 214, 170, 255), outline=dk)
        d.line([(8, 6), (16, 6)], fill=(160, 120, 70, 255), width=1); d.ellipse([7, 11, 11, 15], fill=lt)
    elif shape == "candle":
        for (x, h) in [(8, 13), (15, 10)]:
            d.rectangle([x - 2, 21 - h, x + 2, 21], fill=c, outline=dk)
            d.polygon([(x, 21 - h - 6), (x + 2, 21 - h - 2), (x, 21 - h), (x - 2, 21 - h - 2)], fill=(255, 190, 60, 255))
    elif shape == "grapes":
        for (x, y) in [(8, 8), (12, 8), (16, 8), (10, 12), (14, 12), (12, 16), (8, 12) if False else (16, 12)]:
            d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=c, outline=dk)
        d.ellipse([10, 5, 12, 7], fill=lt); d.line([(12, 5), (13, 1)], fill=(90, 70, 40, 255), width=1)
        d.polygon([(13, 3), (19, 1), (17, 5)], fill=(90, 150, 60, 255))
    elif shape == "cross":
        d.rectangle([9, 3, 15, 21], fill=c, outline=dk); d.rectangle([3, 9, 21, 15], fill=c, outline=dk)
        d.rectangle([10, 4, 14, 20], fill=c); d.line([(10, 5), (10, 10)], fill=lt)
    elif shape == "bottle":
        d.rectangle([10, 2, 14, 9], fill=c, outline=dk); d.rounded_rectangle([6, 8, 18, 22], 3, fill=c, outline=dk)
        d.rectangle([7, 13, 17, 18], fill=(236, 226, 196, 255)); d.line([(8, 10), (8, 20)], fill=lt, width=1)
    elif shape in ("axe", "pickaxe", "scythe", "cleaver", "saw", "trowel", "chisel"):
        # a tool on a wooden handle; the handle runs from bottom left to top right
        wood = (130, 90, 52, 255)
        metal = (196, 200, 208, 255)
        mdk = (96, 100, 108, 255)
        if shape == "axe":
            d.line([(5, 21), (16, 4)], fill=wood, width=2.4)
            d.polygon([(13, 3), (21, 6), (19, 13), (15, 8)], fill=metal, outline=mdk)
        elif shape == "pickaxe":
            d.line([(6, 21), (14, 6)], fill=wood, width=2.4)
            d.line([(3, 9), (9, 4), (14, 5), (19, 8), (22, 13)], fill=metal, width=2.2)
        elif shape == "scythe":
            d.line([(5, 21), (13, 3)], fill=wood, width=2.0)
            d.arc([3, 1, 23, 15], 200, 350, fill=metal, width=2)
            d.line([(7, 16), (11, 15)], fill=wood, width=1.6)
        elif shape == "cleaver":
            d.line([(4, 20), (10, 14)], fill=wood, width=2.6)
            d.polygon([(9, 13), (15, 3), (22, 7), (16, 17)], fill=metal, outline=mdk)
        elif shape == "saw":
            d.polygon([(4, 18), (20, 6), (21, 9), (6, 21)], fill=metal, outline=mdk)
            for k in range(6):
                x, y = 6 + k * 2.6, 20 - k * 2.0
                d.line([(x, y), (x + 1, y + 2)], fill=mdk, width=0.8)
            d.rounded_rectangle([1, 16, 7, 23], 1.5, fill=wood)
        elif shape == "trowel":
            d.line([(4, 20), (10, 14)], fill=wood, width=2.6)
            d.polygon([(10, 14), (13, 4), (21, 10)], fill=metal, outline=mdk)
        elif shape == "chisel":
            d.line([(4, 21), (11, 13)], fill=wood, width=3)
            d.polygon([(10, 12), (17, 3), (20, 6), (12, 15)], fill=metal, outline=mdk)
            d.line([(17, 3), (20, 6)], fill=(240, 240, 245, 255), width=1)
    elif shape == "bow":
        d.arc([2, 2, 22, 22], 225, 405, fill=(140, 96, 52, 255), width=2)
        d.line([(5, 5), (19, 19)], fill=(230, 226, 210, 255), width=0.7)
        d.line([(8, 16), (20, 4)], fill=(120, 84, 48, 255), width=1.2)
        d.polygon([(20, 4), (16, 5), (19, 8)], fill=(196, 200, 208, 255))
    elif shape == "tongs":
        d.line([(4, 21), (13, 9), (19, 3)], fill=(90, 94, 100, 255), width=2)
        d.line([(9, 22), (14, 10), (21, 6)], fill=(110, 114, 120, 255), width=2)
        d.ellipse([12, 8, 15, 11], fill=(60, 60, 64, 255))
    elif shape == "shears":
        d.polygon([(12, 2), (15, 3), (13, 14), (11, 13)], fill=(196, 200, 208, 255), outline=(96, 100, 108, 255))
        d.polygon([(9, 3), (12, 2), (13, 13), (11, 14)], fill=(176, 180, 188, 255), outline=(96, 100, 108, 255))
        d.arc([5, 13, 19, 23], 0, 360, fill=(110, 80, 50, 255), width=2)
    elif shape == "quill":
        d.polygon([(20, 2), (22, 5), (8, 19), (6, 17)], fill=(240, 238, 228, 255), outline=(150, 146, 136, 255))
        d.line([(21, 3), (6, 18)], fill=(170, 166, 156, 255), width=0.6)
        d.line([(6, 18), (3, 22)], fill=(40, 40, 50, 255), width=1.2)
        d.ellipse([12, 17, 20, 22], fill=(40, 40, 60, 255))
    elif shape == "harness":
        d.ellipse([3, 4, 21, 21], outline=(110, 70, 40, 255), width=3)
        d.rectangle([9, 2, 15, 6], fill=(196, 170, 90, 255), outline=(120, 96, 40, 255))
        d.line([(12, 21), (12, 23)], fill=(110, 70, 40, 255), width=2)
    else:
        d.ellipse([4, 4, 20, 20], fill=c, outline=dk)
    return d.done()


# ---------------------------------------------------------------- buildings
ROOF = {"raw": (150, 104, 56), "food": (196, 160, 84), "industry": (88, 98, 116), "crafts": (150, 84, 64),
        "folk": (168, 72, 58), "mil": (96, 100, 108), "special": (136, 52, 50), "science": (66, 88, 136),
        "logistics": (140, 96, 60)}
THATCH = ("raw", "food")
DARK = (40, 33, 24, 255)

# Each age has its own building style: the same shapes, built in that age's materials.
# 0 Roman: whitewashed plaster, terracotta tiles, arched doors, shuttered windows, pilasters.
# 1 Early Medieval: timber framing and thatch (the original look).
# 2 High Medieval: stone footings under the timber, steep slate roofs.
# 3 Renaissance: pale plastered fronts, red tiles, framed windows, a cornice.
# 4 Enlightenment: brick, dark slate, tall white sash windows, a cornice.
# 5 Industrial: dark red brick, grey slate, iron-framed factory windows, tall chimneys.
ERAS = ["roman", "early_medieval", "high_medieval", "renaissance", "enlightenment", "industrial"]
ERA = 1
ERA_LOOK = {
    0: {"wall": ((236, 228, 210), 0.65), "roof": (186, 98, 62), "roof_mat": "tiles", "wall_mat": "plaster", "window": "shutter", "columns": True},
    1: {},
    2: {"roof": (84, 90, 106), "roof_mat": "slate", "footing": True},
    3: {"wall": ((240, 228, 196), 0.45), "roof": (172, 74, 54), "roof_mat": "tiles", "wall_mat": "plaster", "window": "framed", "cornice": True},
    4: {"wall": ((168, 92, 66), 0.6), "roof": (78, 82, 94), "roof_mat": "slate", "wall_mat": "brick", "window": "sash", "cornice": True},
    5: {"wall": ((134, 64, 46), 0.75), "roof": (66, 68, 74), "roof_mat": "slate", "wall_mat": "brick", "window": "factory", "tall_chimney": True},
}


def look(key, default=None):
    return ERA_LOOK.get(ERA, {}).get(key, default)
WOOD = (112, 78, 46, 255)


class B:
    """Drawing helpers for one building picture (64 design pixels wide, light from the upper left)."""

    def __init__(self, W, H, wall, roof, cat, k=3):
        self.p = Pen(W, H, k)
        self.W, self.H = W, H
        self.b = H - 4                      # the ground line
        lw = look("wall")
        if lw:
            wall = mix(wall, lw[0], lw[1])[:3]
        lr = look("roof")
        if lr:
            roof = mix(lr, roof, 0.25)[:3]
        self.wall = wall + (255,)
        self.roof = roof + (255,)
        self.cat = cat
        self.p.ellipse([4, self.b - 5, W - 4, self.b + 3], fill=(0, 0, 0, 64))

    # ---- surfaces: every wall, roof and door is filled with a texture (bld_tex.py) over its base colour
    def _seed(self):
        return random.randrange(1 << 30)

    def surface(self, pts, mat, base, mult=1.0, foot_moss=0.0):
        """Fills polygon pts with material mat ('stone', 'brick', 'plaster', 'planks', 'rock') of colour base."""
        sd = self._seed()
        base = tuple(base[:3])
        if mat == "stone":
            tex = lambda W, H, F: BT.blocks(W, H, F, base, sd, row=4, wmin=4, wmax=7, moss=foot_moss)
        elif mat == "brick":
            tex = lambda W, H, F: BT.blocks(W, H, F, base, sd, row=2, wmin=4, brick=True, mortar=0.45, rough=0.6)
        elif mat == "plaster":
            tex = lambda W, H, F: BT.plaster(W, H, F, base, sd)
        elif mat == "planks":
            tex = lambda W, H, F: BT.wood(W, H, F, base, sd, board=3)
        elif mat == "rock":
            tex = lambda W, H, F: BT.rock(W, H, F, base, sd)
        else:
            return
        self.p.texfill(pts, tex, mult)

    def walls(self, x0, x1, top, mat, dx=7, dy=5, grass=True):
        """Front wall and right side wall of a box; mat is 'timber', 'stone' or 'planks'.
        The age decides the real material: stone stays stone, the rest follow the age's style."""
        p, b, w = self.p, self.b, self.wall
        if mat != "stone" and look("wall_mat"):
            mat = look("wall_mat")
        side = [(x1, b), (x1 + dx, b - dy), (x1 + dx, top - dy), (x1, top)]
        front = [(x0, b), (x1, b), (x1, top), (x0, top)]
        p.polygon(side, fill=sh(w, 0.66))
        p.polygon(front, fill=w)
        self.material(front, x0, x1, top, b, mat, 1.0)
        self.material(side, x1, x1 + dx, top - dy, b, mat, 0.66)
        if look("footing") and mat != "stone":
            # High Medieval: a stone footing under the walls
            fy = b - (b - top) * 0.32
            st = (150, 146, 136)
            self.surface([(x0, b), (x1, b), (x1, fy), (x0, fy)], "stone", st, 1.0, 0.5)
            self.surface([(x1, b), (x1 + dx, b - dy), (x1 + dx, fy - dy), (x1, fy)], "stone", st, 0.66, 0.5)
            p.line([(x0, fy), (x1, fy), (x1 + dx, fy - dy)], fill=(96, 92, 84, 255), width=0.5)
        p.shade(front, top, b, (255, 255, 255, 26), (0, 0, 0, 46))
        # where the walls meet the ground: a dark band of grime and shadow
        if grass:
            p.shade([(x0, b - 3), (x1, b - 3), (x1, b), (x0, b)], b - 3, b, (0, 0, 0, 0), (0, 0, 0, 80))
            p.shade([(x1, b - 3), (x1 + dx, b - dy - 3), (x1 + dx, b - dy), (x1, b)], b - dy - 3, b, (0, 0, 0, 10), (0, 0, 0, 70))
        # the corner where front and side meet catches a little light
        p.line([(x1, top), (x1, b)], fill=sh(w, 1.18), width=0.35)
        p.polygon(side, outline=sh(w, 0.38), width=0.5)
        p.polygon(front, outline=sh(w, 0.38), width=0.5)
        if look("columns") and x1 - x0 >= 16:
            # Roman: white pilasters at the corners of the front, with capitals
            for cx in (x0 + 0.6, x1 - 2.6):
                p.rectangle([cx, top + 1, cx + 2, b], fill=(244, 240, 228, 255), outline=(170, 164, 150, 255), width=0.4)
                p.line([(cx + 0.5, top + 1.5), (cx + 0.5, b - 0.5)], fill=(255, 255, 250, 255), width=0.4)
                p.line([(cx + 1.6, top + 1.5), (cx + 1.6, b - 0.5)], fill=(200, 194, 180, 255), width=0.4)
                p.rectangle([cx - 0.6, top, cx + 2.6, top + 1.4], fill=(230, 226, 214, 255))
        if look("cornice"):
            p.line([(x0 - 1, top + 0.8), (x1 + 0.5, top + 0.8)], fill=sh(w, 1.35), width=1.3)
            p.line([(x0 - 1, top + 1.6), (x1 + 0.5, top + 1.6)], fill=sh(w, 0.7), width=0.4)
            p.line([(x1 + 0.5, top + 0.8), (x1 + dx, top - dy + 0.8)], fill=sh(w, 1.0), width=1.1)
        # tufts of grass along the foot
        if not grass:
            return
        rnd = random.Random(int(x0 * 31 + b))
        for _ in range(int((x1 - x0 + dx) / 3)):
            gx = rnd.uniform(x0 - 1, x1 + dx)
            gy = b - (gx - x1) * dy / dx if gx > x1 else b
            gy += 0.6
            gc = rnd.choice([(74, 112, 46, 255), (96, 138, 58, 255), (62, 96, 38, 255)])
            for k in range(3):
                p.line([(gx, gy), (gx + (k - 1) * 0.5, gy - rnd.uniform(0.9, 1.8))], fill=gc, width=0.3)

    def material(self, pts, x0, x1, top, b, mat, f):
        w = sh(self.wall, f)
        if mat in ("stone", "brick", "plaster", "planks"):
            self.surface(pts, mat, w, 1.0, 0.25 if mat == "stone" else 0.0)
            return
        if mat == "timber":
            # half-timbering: plaster panels between oak beams (with the beams' shadow on the plaster)
            self.surface(pts, "plaster", w)
            beam = sh(WOOD, f)

            def beams(q, off=(0.0, 0.0), col=beam):
                ox, oy = off
                q.line([(x0 + ox, top + 1 + oy), (x1 + ox, top + 1 + oy)], fill=col, width=1.4)
                q.line([(x0 + ox, (top + b) / 2 + oy), (x1 + ox, (top + b) / 2 + oy)], fill=col, width=1.1)
                n = max(2, round((x1 - x0) / 10))
                for k in range(n + 1):
                    x = x0 + (x1 - x0) * k / n
                    q.line([(x + ox, top + oy), (x + ox, b + oy)], fill=col, width=1.2)
                    if k < n and k % 2 == 0:
                        q.line([(x + ox, b + oy), (x0 + (x1 - x0) * (k + 1) / n + ox, (top + b) / 2 + oy)], fill=col, width=0.9)
            self.p.clipped(pts, lambda q: beams(q, (0.35, 0.45), (0, 0, 0, 70)))
            sd = self._seed()
            self.p.clipped(pts, lambda q: q.texmask(lambda r: beams(r), lambda W, H, F: BT.wood(W, H, F, beam, sd, board=1.3, vertical=False, gap=0.0)))

    def roof_gable(self, x0, x1, top, rh, dx=7, dy=5, mat=None):
        """A pitched roof over walls(x0, x1, top): the front slope, the gable end and the ridge."""
        p = self.p
        r = self.roof
        mat = mat or ("thatch" if self.cat in THATCH else ("slate" if self.cat in ("industry", "mil", "science") else "tiles"))
        if look("roof_mat") and not (ERA == 2 and mat == "thatch"):
            mat = look("roof_mat")
        ridge = top - dy / 2 - rh
        gable = [(x1, top), (x1 + dx, top - dy), (x1 + dx / 2, ridge)]
        p.polygon(gable, fill=sh(self.wall, 0.76))
        gm = "stone" if look("wall_mat") in ("brick",) else ("plaster" if look("wall_mat") == "plaster" else "planks")
        self.surface(gable, gm if gm != "stone" else "brick", sh(self.wall, 0.76))
        p.polygon(gable, outline=sh(self.wall, 0.4), width=0.5)
        slope = [(x0 - 2, top + 1.5), (x1 + 1, top + 1.5), (x1 + dx / 2 + 1, ridge), (x0 - 2 + dx / 2, ridge)]
        back = [(x1 + 1, top + 1.5), (x1 + dx / 2 + 1, ridge), (x1 + dx + 1.5, top - dy + 1.5), (x1 + dx + 0.5, top - dy + 2.5)]
        sd = self._seed()
        rr = tuple(r[:3])
        if mat == "thatch":
            tex = lambda W, H, F: BT.thatch(W, H, F, rr, sd)
        elif mat == "slate":
            tex = lambda W, H, F: BT.slates(W, H, F, rr, sd)
        else:
            tex = lambda W, H, F: BT.roof_tiles(W, H, F, rr, sd)
        p.polygon(back, fill=sh(r, 0.6))
        p.texfill(back, tex, 0.6)
        # the eaves throw a shadow down the top of the walls
        p.shade([(x0, top + 1.5), (x1, top + 1.5), (x1, top + 6), (x0, top + 6)], top + 1.5, top + 6, (0, 0, 0, 120), (0, 0, 0, 0))
        p.shade([(x1, top + 1.5), (x1 + dx, top - dy + 1.5), (x1 + dx, top - dy + 5), (x1, top + 5)], top - dy + 1.5, top + 5, (0, 0, 0, 90), (0, 0, 0, 0))
        p.polygon(slope, fill=r)
        p.texslope([slope[0], slope[1], slope[2], slope[3]], tex)
        p.shade(slope, ridge, top, (255, 255, 255, 36), (0, 0, 0, 34))
        # ridge cap and the edge of the eaves
        if mat == "thatch":
            p.line([(x0 - 2 + dx / 2, ridge + 0.5), (x1 + dx / 2 + 1, ridge + 0.5)], fill=sh(r, 0.7), width=1.6)
            p.line([(x0 - 2 + dx / 2, ridge), (x1 + dx / 2 + 1, ridge)], fill=sh(r, 1.15), width=0.6)
        else:
            p.line([(x0 - 2 + dx / 2, ridge + 0.2), (x1 + dx / 2 + 1, ridge + 0.2)], fill=sh(r, 0.8), width=1.3)
            p.line([(x0 - 2 + dx / 2, ridge - 0.3), (x1 + dx / 2 + 1, ridge - 0.3)], fill=sh(r, 1.35), width=0.5)
        p.line([(x0 - 2, top + 1.5), (x1 + 1, top + 1.5)], fill=sh(r, 0.55), width=0.7)
        p.polygon(slope, outline=sh(r, 0.42), width=0.5)
        return ridge

    def flat_top(self, x0, x1, top, dx=7, dy=5, crenel=True):
        """The flat top of a stone tower with battlements."""
        p, w = self.p, self.wall
        deck = [(x0, top), (x1, top), (x1 + dx, top - dy), (x0 + dx, top - dy)]
        p.polygon(deck, fill=sh(w, 0.55))
        self.surface(deck, "stone", sh(w, 0.55))
        if crenel:
            for x in range(int(x0), int(x1) - 1, 5):
                m = [(x, top), (x + 2.6, top), (x + 2.6, top - 4), (x, top - 4)]
                p.polygon(m, fill=sh(w, 1.05))
                self.surface(m, "stone", sh(w, 1.05))
                p.line([(x, top - 4), (x + 2.6, top - 4)], fill=sh(w, 1.3), width=0.4)
                p.line([(x + 2.6, top - 4), (x + 2.6, top)], fill=sh(w, 0.55), width=0.4)
                p.polygon(m, outline=sh(w, 0.5), width=0.4)
            for k in range(3):
                x = x1 + dx * (k + 0.3) / 3
                y = top - dy * (k + 0.3) / 3
                m = [(x, y), (x + 1.6, y - 1.1), (x + 1.6, y - 5.1), (x, y - 4)]
                p.polygon(m, fill=sh(w, 0.7))
                self.surface(m, "stone", sh(w, 0.7))

    def door(self, x, w=8, h=12, arch=False):
        p, b = self.p, self.b
        arch = arch or ERA == 0
        # the opening in the wall, a little deeper than the door
        p.rectangle([x - 1, b - h - 1, x + w, b], fill=sh(self.wall, 0.45))
        if arch:
            p.pieslice([x - 1, b - h - w / 2 - 1, x + w, b - h + w / 2], 180, 360, fill=sh(self.wall, 0.45))
            p.pieslice([x, b - h - w / 2, x + w - 1, b - h + w / 2], 180, 360, fill=DARK)
        leaf = [(x, b), (x + w - 1, b), (x + w - 1, b - h), (x, b - h)]
        p.polygon(leaf, fill=(88, 60, 34, 255))
        sd = self._seed()
        p.texfill(leaf, lambda W, H, F: BT.wood(W, H, F, (98, 66, 38), sd, board=max(1.5, w / 3), gap=0.25))
        # shadow under the lintel, iron straps with studs, a ring handle
        p.shade([(x, b - h), (x + w - 1, b - h), (x + w - 1, b - h + 2.5), (x, b - h + 2.5)], b - h, b - h + 2.5, (0, 0, 0, 130), (0, 0, 0, 0))
        for yy in (b - h * 0.78, b - h * 0.3):
            p.line([(x + 0.3, yy), (x + w - 1.6, yy)], fill=(46, 42, 38, 255), width=0.7)
            for k in range(3):
                p.point((x + 0.8 + k * (w - 2.8) / 2, yy - 0.2), fill=(150, 146, 138, 255))
        p.arc([x + w - 2.8, b - h / 2 - 0.4, x + w - 1.9, b - h / 2 + 0.6], 0, 360, fill=(70, 64, 56, 255), width=0.3)
        # the step
        p.rectangle([x - 1.5, b - 1, x + w + 0.5, b + 0.6], fill=(156, 152, 142, 255))
        p.line([(x - 1.5, b - 1), (x + w + 0.5, b - 1)], fill=(196, 192, 182, 255), width=0.35)

    def big_door(self, x0, y0, x1, y1, col=(84, 58, 34), split=True):
        """A wide plank door (workshops, barns): boards, a lintel's shadow, iron hinges; two leaves."""
        p = self.p
        p.rectangle([x0 - 1, y0 - 1, x1 + 1, y1], fill=sh(self.wall, 0.45))
        leaf = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
        p.polygon(leaf, fill=col + (255,))
        sd = self._seed()
        p.texfill(leaf, lambda W, H, F: BT.wood(W, H, F, col, sd, board=2.0, gap=0.3))
        p.shade([(x0, y0), (x1, y0), (x1, y0 + 3), (x0, y0 + 3)], y0, y0 + 3, (0, 0, 0, 140), (0, 0, 0, 0))
        if split:
            mx = (x0 + x1) / 2
            p.line([(mx, y0), (mx, y1)], fill=(34, 24, 14, 255), width=0.6)
        for yy in (y0 + (y1 - y0) * 0.22, y1 - (y1 - y0) * 0.22):
            p.line([(x0 + 0.3, yy), (x0 + (x1 - x0) * 0.38, yy)], fill=(46, 42, 38, 255), width=0.7)
            p.line([(x1 - 0.3, yy), (x1 - (x1 - x0) * 0.38, yy)], fill=(46, 42, 38, 255), width=0.7)
        p.polygon(leaf, outline=DARK, width=0.4)

    def _glass(self, x, y, w, h, lit):
        """Panes: darker at the top under the lintel, a pale reflection across them (or warm light)."""
        p = self.p
        pane = [(x, y), (x + w - 1, y), (x + w - 1, y + h - 1), (x, y + h - 1)]
        if lit:
            p.shade(pane, y, y + h - 1, (255, 222, 140, 255), (236, 170, 80, 255))
        else:
            p.shade(pane, y, y + h - 1, (56, 74, 92, 255), (96, 124, 146, 255))
            p.polygon([(x + w * 0.15, y + h - 1), (x + w * 0.45, y), (x + w * 0.62, y), (x + w * 0.32, y + h - 1)], fill=(190, 214, 230, 70))

    def window(self, x, y, w=6, h=6, lit=False):
        p = self.p
        style = look("window")
        if style == "shutter":
            # Roman: a dark opening between two wooden shutters
            p.rectangle([x, y, x + w - 1, y + h - 1], fill=(48, 40, 32, 255) if not lit else (236, 190, 100, 255))
            for sx0, sx1 in ((x - 2, x - 0.2), (x + w - 0.8, x + w + 1)):
                p.rectangle([sx0, y, sx1, y + h - 1], fill=WOOD, outline=DARK, width=0.3)
                for k in range(1, 3):
                    p.line([(sx0 + 0.2, y + h * k / 3), (sx1 - 0.2, y + h * k / 3)], fill=(84, 58, 34, 255), width=0.3)
            p.rectangle([x - 2.2, y + h - 0.2, x + w + 1.2, y + h + 0.6], fill=(220, 214, 200, 255))
            return
        if style in ("framed", "sash"):
            hh = h * (1.35 if style == "sash" else 1.0)
            p.rectangle([x - 1.2, y - 1.2, x + w + 0.2, y + hh + 0.2], fill=(246, 244, 236, 255))
            self._glass(x, y, w, hh, lit)
            p.line([(x + w / 2 - 0.5, y), (x + w / 2 - 0.5, y + hh - 1)], fill=(246, 244, 236, 255), width=0.6)
            rows = 3 if style == "sash" else 2
            for k in range(1, rows):
                p.line([(x, y + hh * k / rows - 0.5), (x + w - 1, y + hh * k / rows - 0.5)], fill=(246, 244, 236, 255), width=0.6)
            if style == "framed":
                p.polygon([(x - 1.6, y - 1.4), (x + w / 2 - 0.5, y - 3.2), (x + w + 0.6, y - 1.4)], fill=sh(self.wall, 1.2))
            p.rectangle([x - 1.8, y + hh, x + w + 0.8, y + hh + 1], fill=(220, 216, 204, 255))
            p.shade([(x - 1.8, y + hh + 1), (x + w + 0.8, y + hh + 1), (x + w + 0.8, y + hh + 2.4), (x - 1.8, y + hh + 2.4)], y + hh + 1, y + hh + 2.4, (0, 0, 0, 70), (0, 0, 0, 0))
            return
        if style == "factory":
            p.rectangle([x - 0.8, y - 0.8, x + w - 0.2, y + h - 0.2], fill=(60, 62, 66, 255))
            self._glass(x, y, w, h, lit)
            for k in range(1, 3):
                p.line([(x + (w - 1) * k / 3, y), (x + (w - 1) * k / 3, y + h - 1)], fill=(60, 62, 66, 255), width=0.4)
                p.line([(x, y + (h - 1) * k / 3), (x + w - 1, y + (h - 1) * k / 3)], fill=(60, 62, 66, 255), width=0.4)
            return
        # timber-framed and medieval windows: a deep reveal, a wooden frame with a cross, a stone sill
        p.rectangle([x - 1.3, y - 1.3, x + w + 0.3, y + h + 0.3], fill=sh(self.wall, 0.5))
        p.rectangle([x - 1, y - 1, x + w, y + h], fill=(206, 190, 160, 255))
        self._glass(x, y, w, h, lit)
        p.line([(x + w / 2 - 0.5, y), (x + w / 2 - 0.5, y + h - 1)], fill=(222, 208, 178, 255), width=0.7)
        p.line([(x, y + h / 2 - 0.5), (x + w - 1, y + h / 2 - 0.5)], fill=(222, 208, 178, 255), width=0.7)
        p.line([(x - 1, y - 1), (x + w, y - 1)], fill=(246, 236, 210, 255), width=0.3)
        p.rectangle([x - 1.6, y + h, x + w + 0.6, y + h + 1], fill=(150, 144, 132, 255))
        p.line([(x - 1.6, y + h), (x + w + 0.6, y + h)], fill=(196, 190, 178, 255), width=0.3)
        p.shade([(x - 1.6, y + h + 1), (x + w + 0.6, y + h + 1), (x + w + 0.6, y + h + 2.4), (x - 1.6, y + h + 2.4)], y + h + 1, y + h + 2.4, (0, 0, 0, 80), (0, 0, 0, 0))
        # now and then a box of flowers under it
        if not lit and random.random() < 0.4 and ERA in (1, 2, 3):
            p.rectangle([x - 1, y + h + 1, x + w, y + h + 2.6], fill=(120, 80, 44, 255), outline=(70, 46, 26, 255), width=0.3)
            for k in range(int(w) + 1):
                fx = x - 0.5 + k
                p.disc(fx, y + h + 0.9, 0.55, (70, 120, 52, 255))
                if k % 2 == 0:
                    p.disc(fx, y + h + 0.6, 0.45, random.choice([(230, 70, 60, 255), (240, 200, 70, 255), (236, 236, 236, 255), (200, 110, 200, 255)]))

    def chimney(self, x, y_top, y_base):
        p = self.p
        if look("tall_chimney"):
            # Industrial: a tall dark brick stack with an iron band
            y_top -= 7
            body = [(x, y_top), (x + 4, y_top), (x + 4, y_base), (x, y_base)]
            p.polygon(body, fill=(118, 58, 42, 255))
            self.surface(body, "brick", (118, 58, 42))
            p.rectangle([x + 3, y_top, x + 4, y_base], fill=(0, 0, 0, 60))
            p.polygon(body, outline=(70, 34, 24, 255), width=0.5)
            p.rectangle([x - 0.6, y_top + 3, x + 4.6, y_top + 4], fill=(60, 60, 64, 255))
            p.rectangle([x - 0.8, y_top - 1.2, x + 4.8, y_top], fill=(50, 50, 54, 255))
            p.shade(body, y_top, y_top + 5, (20, 18, 16, 150), (20, 18, 16, 0))
            return
        body = [(x, y_top), (x + 4, y_top), (x + 4, y_base), (x, y_base)]
        p.polygon(body, fill=(150, 76, 58, 255))
        self.surface(body, "brick", (150, 76, 58))
        p.rectangle([x + 3, y_top, x + 4, y_base], fill=(0, 0, 0, 60))
        p.polygon(body, outline=(90, 46, 34, 255), width=0.5)
        p.rectangle([x - 0.8, y_top - 1.2, x + 4.8, y_top], fill=(90, 86, 80, 255))
        p.line([(x - 0.8, y_top - 1.2), (x + 4.8, y_top - 1.2)], fill=(140, 136, 128, 255), width=0.35)
        p.shade(body, y_top, y_top + 3, (24, 20, 16, 140), (24, 20, 16, 0))

    def sign(self, x, y, res_icon):
        """A hanging signboard showing what the building makes."""
        p = self.p
        p.line([(x - 1, y - 2), (x + 11, y - 2)], fill=WOOD, width=1)
        p.line([(x + 2, y - 2), (x + 2, y)], fill=DARK, width=0.4)
        p.line([(x + 8, y - 2), (x + 8, y)], fill=DARK, width=0.4)
        p.rounded_rectangle([x, y, x + 10, y + 10], 1.5, fill=(236, 222, 186, 255), outline=(110, 76, 42, 255), width=0.8)
        if res_icon is not None:
            p.paste(res_icon, x + 0.5, y + 0.5, 10)

    def done(self):
        return self.p.done()


def make_building(style, wall, roof, cat, res_icon, W=64, H=64, bid=None):
    random.seed(zlib.crc32(repr((style, wall, roof)).encode()) & 0xffff)
    g = B(W, H, wall, roof, cat)
    p, b = g.p, g.b
    # buildings that share a style get their own shape and the tools of their trade (bld_variants.py)
    if bid is not None:
        import bld_variants as BV
        if BV.draw(sys.modules[__name__], g, bid, res_icon):
            return g.done()
    if style == "house":
        top = b - 20
        g.walls(14, 42, top, "timber")
        ridge = g.roof_gable(14, 42, top, 14)
        g.chimney(34, ridge - 4, top - 6)
        g.door(24, 7, 11)
        g.window(16, top + 5); g.window(35, top + 5)
    elif style == "apartments":
        top = b - 38
        g.walls(10, 46, top, "timber")
        ridge = g.roof_gable(10, 46, top, 12)
        g.chimney(39, ridge - 4, top - 6)
        g.door(24, 8, 12)
        for r in range(3):
            for x in (13, 38) if r == 2 else (13, 24, 38):
                g.window(x, top + 4 + r * 11, lit=(r + x) % 3 == 0)
    elif style == "school":
        top = b - 22
        g.walls(8, 46, top, "timber")
        ridge = g.roof_gable(8, 46, top, 14)
        # a little bell turret on the ridge
        p.rectangle([27, ridge - 9, 33, ridge + 1], fill=g.wall, outline=sh(g.wall, 0.4), width=0.5)
        p.rectangle([29, ridge - 7, 31, ridge - 3], fill=DARK)
        p.disc(30, ridge - 4, 1.3, (220, 180, 70, 255))
        p.polygon([(26, ridge - 9), (30, ridge - 18), (34, ridge - 9)], fill=g.roof, outline=sh(g.roof, 0.5), width=0.5)
        g.door(23, 8, 12, arch=True)
        for x in (11, 36):
            g.window(x, top + 5, 6, 8)
        g.sign(37, b - 10, res_icon) if res_icon is not None else None
    elif style == "workshop":
        top = b - 22
        g.walls(6, 48, top, "timber")
        ridge = g.roof_gable(6, 48, top, 12)
        g.chimney(40, ridge - 6, top - 4)
        g.big_door(10, b - 14, 21, b)
        g.window(34, top + 5, 7, 6, lit=True)
        g.sign(25, b - 16, res_icon)
    elif style == "shed":
        top = b - 16
        # lean-to with a woodpile in front
        g.walls(16, 40, top, "planks")
        g.roof_gable(16, 40, top, 10)
        g.door(20, 7, 10)
        for k in range(3):
            for j in range(3 - k):
                x = 4 + j * 4 + k * 2; y = b - 3 - k * 3.4
                p.disc(x + 2, y, 1.9, (150, 104, 60, 255)); p.disc(x + 2, y, 0.9, (200, 160, 110, 255))
        g.sign(29, top + 3, res_icon)
    elif style == "quarry":
        # a heap of cut stone on the left, the stonemason's hut on the right
        for poly, c in (([(2, b), (8, b - 18), (18, b - 26), (28, b - 16), (32, b)], (140, 138, 130)),
                        ([(8, b - 18), (18, b - 26), (16, b - 8)], (186, 184, 174)),
                        ([(18, b - 26), (28, b - 16), (32, b), (16, b - 8)], (110, 108, 100))):
            p.polygon(poly, fill=c + (255,))
            g.surface(poly, "rock", c)
        for (x, y) in [(8, b - 4), (14, b - 3), (20, b - 5), (11, b - 8)]:
            blk = [(x, y), (x + 5, y), (x + 5, y + 3), (x, y + 3)]
            p.polygon(blk, fill=(196, 194, 184, 255))
            g.surface(blk, "rock", (196, 194, 184))
            p.line([(x, y), (x + 5, y)], fill=(226, 224, 216, 255), width=0.4)
            p.polygon(blk, outline=(110, 108, 100, 255), width=0.4)
        top = b - 14
        g.walls(34, 50, top, "planks", dx=6, dy=4)
        g.roof_gable(34, 50, top, 9, dx=6, dy=4)
        g.door(39, 6, 9)
    elif style == "barn":
        top = b - 22
        g.walls(18, 52, top, "planks")
        g.roof_gable(18, 52, top, 14, mat="thatch" if g.cat in THATCH else None)
        g.big_door(28, b - 15, 42, b, (128, 52, 40), split=False)
        p.line([(28, b - 15), (42, b)], fill=(230, 220, 200, 255), width=0.8)
        p.line([(42, b - 15), (28, b)], fill=(230, 220, 200, 255), width=0.8)
        p.line([(35, b - 15), (35, b)], fill=DARK, width=0.6)
        # hay bales in front
        for (x, y) in [(3, b - 6), (10, b - 6), (6, b - 11)]:
            p.rounded_rectangle([x, y, x + 7, y + 5], 1.5, fill=(222, 192, 92, 255), outline=(170, 136, 52, 255), width=0.5)
            p.line([(x + 2, y), (x + 2, y + 5)], fill=(170, 136, 52, 255), width=0.4)
        g.sign(44, top + 3, res_icon)
    elif style == "market":
        # a small hall behind three stalls with striped awnings, crates and sacks of goods
        top = b - 20
        g.walls(14, 50, top - 4, "planks")
        g.roof_gable(14, 50, top - 4, 12)
        for k, (x0, col) in enumerate([(3, (196, 64, 52, 255)), (23, (60, 110, 170, 255)), (43, (212, 170, 60, 255))]):
            cnt = [(x0 + 1, b - 9), (x0 + 17, b - 9), (x0 + 17, b), (x0 + 1, b)]
            p.polygon(cnt, fill=(140, 98, 58, 255))
            p.texfill(cnt, lambda W, H, F, sd=g._seed(): BT.wood(W, H, F, (140, 98, 58), sd, board=2.0, vertical=False))
            p.polygon(cnt, outline=(80, 54, 30, 255), width=0.5)
            p.line([(x0 + 2, b - 9), (x0 + 2, b - 17)], fill=WOOD, width=0.9)
            p.line([(x0 + 16, b - 9), (x0 + 16, b - 17)], fill=WOOD, width=0.9)
            for s2 in range(4):
                c = col if s2 % 2 == 0 else (236, 228, 210, 255)
                p.polygon([(x0 + s2 * 4.5, b - 17), (x0 + s2 * 4.5 + 4.5, b - 17), (x0 + s2 * 4.5 + 5.2, b - 13), (x0 + s2 * 4.5 + 0.7, b - 13)], fill=c)
            # goods on the counter
            p.disc(x0 + 6, b - 10, 1.8, (222, 192, 92, 255))
            p.disc(x0 + 11, b - 10.5, 1.8, (176, 72, 52, 255) if k != 1 else (110, 150, 70, 255))
    elif style == "mine":
        # a mountain side with a timbered entrance and a cart of ore on rails
        for poly, c in (([(1, b), (12, b - 28), (30, b - 38), (50, b - 26), (63, b)], (118, 112, 98)),
                        ([(1, b), (12, b - 28), (30, b - 38), (24, b - 16)], (148, 142, 126)),
                        ([(30, b - 38), (50, b - 26), (63, b), (40, b - 14)], (92, 86, 74))):
            p.polygon(poly, fill=c + (255,))
            g.surface(poly, "rock", c)
        # tufts of grass and a little scree on the slopes
        for (gx, gy) in ((6, b - 6), (10, b - 18), (52, b - 8), (57, b - 4), (44, b - 20)):
            for k in range(3):
                p.line([(gx, gy), (gx + (k - 1) * 0.6, gy - 1.4)], fill=(86, 120, 54, 255), width=0.35)
        p.pieslice([20, b - 24, 44, b + 2], 180, 360, fill=DARK)
        p.rectangle([20, b - 11, 44, b], fill=DARK)
        for x in (20, 43):
            post = [(x - 1, b - 13), (x + 1, b - 13), (x + 1, b), (x - 1, b)]
            p.polygon(post, fill=WOOD)
            p.texfill(post, lambda W, H, F, sd=g._seed(): BT.wood(W, H, F, WOOD, sd, board=2.2, gap=0))
        lintel = [(18, b - 15), (46, b - 15), (46, b - 12), (18, b - 12)]
        p.polygon(lintel, fill=WOOD)
        p.texfill(lintel, lambda W, H, F, sd=g._seed(): BT.wood(W, H, F, WOOD, sd, board=3.5, vertical=False, gap=0))
        p.polygon(lintel, outline=(70, 48, 28, 255), width=0.5)
        p.shade([(18, b - 12), (46, b - 12), (46, b - 9), (18, b - 9)], b - 12, b - 9, (0, 0, 0, 140), (0, 0, 0, 0))
        p.line([(24, b), (54, b)], fill=(80, 80, 84, 255), width=0.7)
        p.line([(24, b - 2), (54, b - 2)], fill=(80, 80, 84, 255), width=0.7)
        p.rectangle([46, b - 8, 56, b - 3], fill=(96, 70, 46, 255), outline=(60, 42, 26, 255), width=0.5)
        p.disc(48, b - 2, 1.5, DARK); p.disc(54, b - 2, 1.5, DARK)
        if res_icon is not None:
            p.paste(res_icon, 46, b - 14, 10)
    elif style == "kiln":
        top = b - 16
        g.walls(32, 54, top, "stone", dx=6, dy=4)
        g.roof_gable(32, 54, top, 10, dx=6, dy=4)
        g.door(40, 6, 9)
        # domed brick furnace with a tall chimney and a fire mouth
        p.rectangle([14, b - 46, 21, b - 20], fill=(150, 76, 58, 255), outline=(90, 46, 34, 255), width=0.5)
        p.rectangle([19, b - 46, 21, b - 20], fill=(112, 56, 42, 255))
        p.rectangle([13, b - 48, 22, b - 46], fill=(90, 86, 80, 255))
        p.pieslice([3, b - 32, 33, b + 4], 180, 360, fill=(168, 84, 60, 255), outline=(104, 50, 36, 255), width=0.6)
        p.rectangle([3, b - 14, 33, b], fill=(168, 84, 60, 255))
        dome = [(3 + 15 + 15 * math.cos(math.radians(a)), b - 14 + 18 * math.sin(math.radians(a))) for a in range(180, 361, 10)] + [(33, b), (3, b)]
        g.surface(dome, "brick", (168, 84, 60))
        p.shade(dome, b - 32, b, (255, 230, 200, 40), (0, 0, 0, 60))
        p.pieslice([6, b - 29, 24, b - 5], 200, 300, fill=(196, 110, 80, 255))
        for k in range(4):
            p.arc([3 + k * 2, b - 32 + k * 4, 33 - k * 2, b + 4 - k * 4], 185, 355, fill=(130, 62, 44, 255), width=0.4)
        p.pieslice([12, b - 12, 24, b + 4], 180, 360, fill=(60, 20, 10, 255))
        p.rectangle([12, b - 4, 24, b], fill=(60, 20, 10, 255))
        p.pieslice([14, b - 9, 22, b + 3], 180, 360, fill=(255, 150, 50, 255))
        p.rectangle([14, b - 3, 22, b], fill=(255, 196, 80, 255))
        g.sign(46, b - 13, res_icon) if res_icon is not None else None
    elif style == "stilt":
        p.rectangle([0, b - 7, 63, b + 2], fill=(56, 114, 160, 200))
        p.line([(4, b - 4), (14, b - 4)], fill=(150, 196, 226, 200), width=0.6)
        p.line([(44, b - 2), (56, b - 2)], fill=(150, 196, 226, 200), width=0.6)
        for x in (14, 26, 38, 50):
            p.rectangle([x - 1, b - 14, x + 1, b], fill=(90, 62, 36, 255))
        sdeck = [(8, b - 14), (54, b - 14), (60, b - 18), (14, b - 18)]
        p.polygon(sdeck, fill=(150, 112, 70, 255))
        p.texfill(sdeck, lambda W, H, F, sd=g._seed(): BT.wood(W, H, F, (150, 112, 70), sd, board=2.5))
        p.rectangle([8, b - 14, 54, b - 12], fill=(118, 84, 50, 255))
        top = b - 32
        g.b = b - 17
        g.walls(16, 44, top, "planks", dx=6, dy=4)
        g.roof_gable(16, 44, top, 11, dx=6, dy=4)
        g.door(26, 7, 9)
        g.sign(34, top + 3, res_icon)
        g.b = b
        # a fishing net hanging on a frame
        p.line([(4, b - 18), (4, b - 30)], fill=WOOD, width=0.8)
        p.line([(4, b - 30), (11, b - 30)], fill=WOOD, width=0.8)
        for k in range(4):
            p.line([(4 + k * 2, b - 30), (5 + k * 2, b - 20)], fill=(210, 200, 170, 200), width=0.4)
    elif style == "well":
        p.ellipse([14, b - 14, 50, b], fill=(132, 130, 122, 255), outline=(84, 82, 76, 255), width=0.6)
        p.rectangle([14, b - 9, 50, b - 4], fill=(132, 130, 122, 255))
        ring = [(32 + 18 * math.cos(math.radians(a)), b - 7 + 7 * math.sin(math.radians(a))) for a in range(0, 181, 10)] + [(14, b - 9), (50, b - 9)]
        ring = [(50, b - 9)] + [(32 + 18 * math.cos(math.radians(a)), b - 7 + 7 * math.sin(math.radians(a))) for a in range(0, 181, 10)] + [(14, b - 9)]
        g.surface(ring, "stone", (132, 130, 122))
        p.shade(ring, b - 9, b, (0, 0, 0, 0), (0, 0, 0, 70))
        p.ellipse([18, b - 13, 46, b - 6], fill=(36, 66, 104, 255), outline=(84, 82, 76, 255), width=0.6)
        p.ellipse([22, b - 12, 30, b - 10], fill=(100, 150, 200, 200))
        for x in (17, 45):
            p.rectangle([x, b - 36, x + 2, b - 8], fill=WOOD)
        p.line([(18, b - 26), (46, b - 26)], fill=(90, 62, 36, 255), width=1.6)
        p.line([(32, b - 26), (32, b - 16)], fill=(200, 190, 160, 255), width=0.5)
        p.rectangle([30, b - 17, 34, b - 13], fill=(120, 84, 48, 255), outline=(70, 48, 28, 255), width=0.4)
        p.polygon([(12, b - 33), (32, b - 46), (52, b - 33)], fill=g.roof, outline=sh(g.roof, 0.5), width=0.6)
        p.polygon([(32, b - 46), (52, b - 33), (32, b - 33)], fill=sh(g.roof, 0.75))
    elif style == "mill":
        # a tapering stone tower with a conical cap; the sails are a separate sprite that the game turns
        w = g.wall
        p.polygon([(21, b), (24, b - 34), (34, b - 34), (37, b)], fill=w)
        p.polygon([(37, b), (34, b - 34), (40, b - 37), (44, b - 4)], fill=sh(w, 0.66))
        g.material([(21, b), (24, b - 34), (34, b - 34), (37, b)], 21, 37, b - 34, b, "stone", 1.0)
        p.shade([(21, b), (24, b - 34), (34, b - 34), (37, b)], b - 34, b, (255, 255, 255, 20), (0, 0, 0, 50))
        p.polygon([(21, b), (24, b - 34), (34, b - 34), (37, b)], outline=sh(w, 0.4), width=0.6)
        p.polygon([(21, b - 33), (31, b - 50), (43, b - 37), (40, b - 33)], fill=g.roof, outline=sh(g.roof, 0.45), width=0.6)
        p.polygon([(31, b - 50), (43, b - 37), (40, b - 33), (34, b - 33)], fill=sh(g.roof, 0.7))
        g.door(26, 6, 10, arch=True)
        g.window(27, b - 26, 4, 5)
        p.disc(30, b - 38, 2.4, (60, 46, 30, 255))
    elif style == "hut":
        top = b - 18
        g.walls(16, 42, top, "stone")
        g.flat_top(16, 42, top)
        g.door(25, 7, 10, arch=True)
        p.rectangle([19, top + 4, 20, top + 9], fill=DARK); p.rectangle([37, top + 4, 38, top + 9], fill=DARK)
    elif style == "boundary_stone":
        # a tall dressed stone with a carved sign, a cairn of small stones at its foot and a pennant
        # on a pole beside it
        p.ellipse([18, b - 4, 48, b + 2], fill=(0, 0, 0, 60))
        p.polygon([(26, b), (27, b - 30), (30, b - 36), (35, b - 35), (38, b - 29), (39, b)], fill=(150, 146, 136, 255), outline=(84, 80, 72, 255), width=0.6)
        p.polygon([(34, b), (35, b - 34), (38, b - 29), (39, b)], fill=(112, 108, 100, 255))
        p.polygon([(27, b - 28), (29, b - 34), (31, b - 35), (29, b - 28)], fill=(186, 182, 172, 255))
        # a carved diamond with a notch either side: the realm's border mark
        p.polygon([(32.5, b - 27), (35.5, b - 21), (32.5, b - 15), (29.5, b - 21)], outline=(80, 76, 68, 255), width=0.9)
        p.disc(32.5, b - 21, 0.9, (80, 76, 68, 255))
        for yy in (b - 11, b - 8):
            p.line([(29, yy), (31, yy - 1)], fill=(96, 92, 84, 255), width=0.7)
            p.line([(34, yy - 1), (36, yy)], fill=(96, 92, 84, 255), width=0.7)
        for sx, sy, r in ((23, b - 1, 2.6), (42, b - 1, 2.8), (27, b + 0.5, 2.0), (38, b + 0.5, 2.2), (45.5, b - 3, 1.8)):
            p.disc(sx, sy, r, (132, 128, 118, 255))
            p.disc(sx - 0.6, sy - 0.7, r * 0.45, (176, 172, 162, 255))
        p.line([(46, b - 2), (46, b - 30)], fill=WOOD, width=1.2)
        p.polygon([(46.5, b - 30), (56, b - 27), (46.5, b - 24)], fill=(200, 200, 196, 255), outline=(120, 120, 116, 255), width=0.4)
    elif style == "palisade":
        # a ring of pointed stakes round a small timber blockhouse
        top = b - 14
        g.walls(22, 40, top - 4, "timber")
        g.roof_gable(22, 40, top - 4, 7, mat="thatch")
        for x in range(8, 56, 3):
            h = 13 + (x * 7) % 4
            stake = [(x, b + 1), (x, b - h + 2), (x + 1.4, b - h), (x + 2.8, b - h + 2), (x + 2.8, b + 1)]
            p.polygon(stake, fill=sh(WOOD, 0.95 + ((x // 3) % 3) * 0.05))
            p.texfill(stake, lambda W, H, F, sd=g._seed(), c=sh(WOOD, 0.95 + ((x // 3) % 3) * 0.05): BT.wood(W, H, F, c, sd, board=2.8, gap=0))
            p.line([(x + 0.4, b), (x + 0.4, b - h + 2)], fill=sh(WOOD, 1.25), width=0.35)
            p.polygon(stake, outline=sh(WOOD, 0.55), width=0.4)
        p.line([(8, b - 6), (56, b - 6)], fill=sh(WOOD, 0.5), width=0.8)
        p.rectangle([29, b - 9, 35, b + 1], fill=(48, 36, 24, 255))
    elif style == "bastion":
        # a low star fort: sloped stone faces, a gun platform and cannon in the embrasures
        top = b - 16
        st = g.wall
        f1 = [(4, b), (14, top + 4), (50, top + 4), (60, b)]
        f2 = [(14, top + 4), (20, top - 2), (44, top - 2), (50, top + 4)]
        p.polygon(f1, fill=sh(st, 0.9))
        g.surface(f1, "stone", sh(st, 0.9), 1.0, 0.3)
        p.polygon(f1, outline=sh(st, 0.45), width=0.6)
        p.polygon(f2, fill=sh(st, 1.15))
        g.surface(f2, "stone", sh(st, 1.15))
        p.polygon(f2, outline=sh(st, 0.5), width=0.5)
        for x in range(8, 58, 5):
            p.line([(x, b), (x + (32 - x) * 0.18, top + 4)], fill=sh(st, 0.78), width=0.35)
        for y in range(int(top) + 7, int(b), 3):
            p.line([(4 + (b - y) * 0.6, y), (60 - (b - y) * 0.6, y)], fill=sh(st, 0.8), width=0.3)
        for cx in (22, 32, 42):
            p.rectangle([cx - 2.2, top - 0.5, cx + 2.2, top + 4], fill=(40, 36, 32, 255))
            p.line([(cx, top + 2), (cx + 3.5, top + 3.5)], fill=(34, 34, 38, 255), width=1.6)
        g.door(28, 8, 8, arch=True)
    elif style == "battery":
        # an earthwork with wicker gabions and cannon pointing out
        top = b - 12
        earth = [(2, b), (10, top), (54, top), (62, b)]
        p.polygon(earth, fill=(122, 112, 70, 255))
        g.surface(earth, "rock", (122, 112, 70))
        p.polygon(earth, outline=(72, 64, 40, 255), width=0.6)
        p.polygon([(10, top), (14, top - 3), (50, top - 3), (54, top)], fill=(140, 150, 84, 255))
        for x in range(12, 52, 6):
            p.rectangle([x, top - 7, x + 4, top - 2], fill=(150, 118, 70, 255), outline=(90, 66, 36, 255), width=0.4)
            for y in range(int(top) - 6, int(top) - 2, 2):
                p.line([(x, y), (x + 4, y)], fill=(110, 82, 48, 255), width=0.3)
        for cx in (20, 38):
            p.ellipse([cx - 3, top - 4, cx + 1, top], fill=(60, 44, 28, 255))
            p.line([(cx, top - 3), (cx + 9, top - 5)], fill=(30, 30, 34, 255), width=2.2)
            p.disc(cx + 9, top - 5, 1.1, (20, 20, 22, 255))
    elif style == "catapult":
        # a wooden throwing engine on a timber frame with wheels, a heap of stones beside it
        p.rectangle([10, b - 10, 50, b - 5], fill=WOOD, outline=sh(WOOD, 0.5), width=0.6)
        for wx in (16, 44):
            p.ellipse([wx - 5, b - 9, wx + 5, b + 1], fill=sh(WOOD, 0.7), outline=sh(WOOD, 0.4), width=0.6)
            p.disc(wx, b - 4, 1.2, (60, 44, 28, 255))
        p.polygon([(22, b - 10), (30, b - 30), (34, b - 30), (38, b - 10)], fill=sh(WOOD, 0.9), outline=sh(WOOD, 0.5), width=0.5)
        p.line([(32, b - 28), (14, b - 44)], fill=sh(WOOD, 1.1), width=2.4)
        p.line([(32, b - 28), (40, b - 20)], fill=sh(WOOD, 1.1), width=2.4)
        p.rectangle([36, b - 22, 44, b - 15], fill=(110, 108, 100, 255), outline=(70, 68, 62, 255), width=0.5)
        p.pieslice([9, b - 49, 19, b - 40], 0, 180, fill=(90, 62, 36, 255))
        p.disc(14, b - 46, 2.2, (150, 148, 140, 255))
        for sx, sy in ((52, b - 2), (56, b - 3), (54, b - 6), (58, b - 1)):
            p.disc(sx, sy, 2.2, (150, 148, 140, 255))
            p.disc(sx - 0.6, sy - 0.6, 0.8, (190, 188, 180, 255))
    elif style == "harbour":
        # a timber quay over the water, a store shed with a crane, crates on the boards
        p.rectangle([2, b - 6, 62, b], fill=(70, 110, 150, 255))
        for x in range(4, 62, 3):
            p.line([(x, b - 6), (x + 2, b - 6)], fill=(150, 190, 220, 255), width=0.5)
        deck = [(6, b - 12), (60, b - 12), (60, b - 7), (6, b - 7)]
        p.polygon(deck, fill=sh(WOOD, 1.05))
        p.texfill(deck, lambda W, H, F, sd=g._seed(): BT.wood(W, H, F, sh(WOOD, 1.05), sd, board=2.5))
        p.polygon(deck, outline=sh(WOOD, 0.5), width=0.5)
        for x in (10, 24, 38, 52):
            p.rectangle([x, b - 7, x + 2, b], fill=sh(WOOD, 0.55))
        g.walls(10, 30, b - 12 - 20, "timber")
        g.roof_gable(10, 30, b - 32, 9)
        g.door(17, 7, 10)
        p.line([(48, b - 12), (48, b - 44)], fill=sh(WOOD, 0.8), width=2.2)
        p.line([(48, b - 42), (60, b - 36)], fill=sh(WOOD, 0.8), width=1.6)
        p.line([(59, b - 36), (59, b - 22)], fill=(200, 190, 160, 255), width=0.5)
        p.rectangle([56, b - 23, 62, b - 18], fill=(160, 120, 70, 255), outline=(90, 66, 36, 255), width=0.4)
        for cx in (38, 43):
            p.rectangle([cx, b - 18, cx + 5, b - 12], fill=(170, 130, 80, 255), outline=(100, 72, 40, 255), width=0.4)
    elif style == "tower":
        top = b - 46
        g.walls(18, 40, top, "stone")
        g.flat_top(18, 40, top)
        g.door(25, 7, 11, arch=True)
        for y in (top + 8, top + 20):
            p.rectangle([28, y, 29.5, y + 6], fill=DARK)
        p.line([(18, top + 3), (40, top + 3)], fill=sh(g.wall, 0.7), width=0.6)
    elif style == "barracks":
        top = b - 20
        g.walls(6, 48, top, "stone")
        g.roof_gable(6, 48, top, 12)
        g.door(23, 9, 12, arch=True)
        g.window(11, top + 5); g.window(38, top + 5)
        # a shield on the wall
        p.polygon([(34, top + 3), (38, top + 3), (38, top + 7), (36, top + 9), (34, top + 7)], fill=(200, 60, 50, 255), outline=DARK, width=0.4)
    elif style in ("castle", "hq"):
        s = W / 64.0
        top = b - 34 * (H / 72.0 if style == "hq" else 1.0)
        g.walls(12 * s, 46 * s, top, "stone")
        g.flat_top(12 * s, 46 * s, top)
        for x0 in (3 * s, 44 * s):
            tt = top - 12
            g.walls(x0, x0 + 13 * s, tt, "stone", dx=5, dy=3.5)
            g.flat_top(x0, x0 + 13 * s, tt, dx=5, dy=3.5)
            p.rectangle([x0 + 6 * s - 0.8, tt + 6, x0 + 6 * s + 0.8, tt + 12], fill=DARK)
        g.door(27 * s, 9 * s, 14, arch=True)
        for x in (18 * s, 40 * s):
            p.rectangle([x, top + 8, x + 1.6, top + 14], fill=DARK)
        if style == "hq":
            p.rectangle([29 * s, top - 22, 29 * s + 1.2, top - 4], fill=DARK)
            p.polygon([(29 * s + 1.2, top - 22), (29 * s + 14, top - 18), (29 * s + 1.2, top - 14)], fill=(200, 60, 50, 255))
    else:
        top = b - 20
        g.walls(14, 44, top, "timber")
        g.roof_gable(14, 44, top, 12)
        g.door(25, 7, 10)
    return g.done()


def buildings():
    res = {r["id"]: r for r in json.load(open(os.path.join(ROOT, "data", "resources.json")))}
    for bid, b in json.load(open(os.path.join(ROOT, "data", "buildings.json"))).items():
        if b is None:
            continue
        art = b.get("art", {})
        style = art.get("style", "house")
        wall = rgb(art.get("wall", "#c0a080"))
        cat = b.get("cat", "folk")
        roof = ROOF.get(cat, (150, 80, 60))
        ic = None
        outs = [k for k in b.get("out", {}) if k in res]
        if art.get("sign"):
            ic = icon(art["sign"], rgb(art.get("sign_color", "#c0c0c0")), 96)
        elif outs:
            ic = icon(res[outs[0]].get("icon", "dot"), rgb(res[outs[0]]["color"]), 96)
        global ERA
        # one picture per age; the plain name is the Early Medieval one (the look before ages had styles)
        for era in range(6):
            ERA = era
            if bid == "hq":
                im = make_building("hq", wall, roof, cat, None, 128, 96)
            elif style in ("castle", "apartments"):
                im = make_building(style, wall, roof, cat, ic, 64, 72, bid=bid)
            else:
                im = make_building(style, wall, roof, cat, ic, bid=bid)
            save(im, "bld_%s_e%d" % (bid, era))
            if era == 1:
                save(im, "bld_" + bid)
        ERA = 1
    import bld_variants as BV
    if BV.write_anchors(os.path.join(ROOT, "data", "buildings.json")):
        print("buildings.json: smoke and glow places updated")


# ---------------------------------------------------------------- people, animals and effects
SKIN = (240, 212, 178, 255)
CLOTH = (236, 236, 236, 255)      # light so the game can tint it with the realm colour
LEG = (88, 68, 50, 255)


def person(p, ox, step, arm=0.0, hat=None, carry=None, tool=None, swing=None, bend=0.0):
    """One small person in a 16x20 design cell at x offset ox, facing right.
    step: -1..1 leg swing, arm: -1..1 arm swing, tool: 'axe', 'pick', 'shovel', 'rod', 'seed', 'hammer',
    'spear' or None; swing: None while walking, else 0 (raised) or 1 (striking)."""
    hx, hy = ox + 8 + bend, 4.5 + abs(bend) * 0.5
    # legs
    p.line([(ox + 7, 13), (ox + 7 + step * 2.2, 19)], fill=LEG, width=1.8)
    p.line([(ox + 9, 13), (ox + 9 - step * 2.2, 19)], fill=sh(LEG, 0.8), width=1.8)
    # back arm
    p.line([(ox + 8, 8.5), (ox + 8 - arm * 2.5, 13)], fill=sh(CLOTH, 0.75), width=1.6)
    # body
    p.polygon([(ox + 5.5 + bend, 7.5), (ox + 10.5 + bend, 7.5), (ox + 11, 14), (ox + 5, 14)], fill=CLOTH, outline=(120, 120, 120, 255), width=0.4)
    p.line([(ox + 5.2, 12), (ox + 10.8, 12)], fill=(150, 120, 80, 255), width=0.7)
    p.disc(hx, hy, 2.8, SKIN)
    p.point((hx + 1.3, hy - 0.4), fill=(40, 30, 20, 255))
    if hat == "crest":
        p.pieslice([hx - 3, hy - 3.6, hx + 2.6, hy + 2], 180, 360, fill=(200, 170, 90, 255), outline=(120, 96, 40, 255), width=0.3)
        p.pieslice([hx - 2.6, hy - 6, hx + 2.2, hy - 1.6], 180, 360, fill=(190, 40, 36, 255))
    elif hat == "greathelm":
        p.rectangle([hx - 2.8, hy - 3.4, hx + 2.6, hy + 1.6], fill=(170, 174, 184, 255), outline=(90, 92, 100, 255), width=0.3)
        p.line([(hx - 0.2, hy - 0.6), (hx + 2.6, hy - 0.6)], fill=(30, 30, 34, 255), width=0.5)
    elif hat == "morion":
        p.pieslice([hx - 2.6, hy - 4.4, hx + 2.4, hy + 0.8], 180, 360, fill=(186, 190, 198, 255), outline=(96, 98, 106, 255), width=0.3)
        p.polygon([(hx - 4, hy - 0.8), (hx - 3.2, hy - 1.8), (hx + 3, hy - 1.8), (hx + 3.8, hy - 0.8)], fill=(176, 180, 188, 255))
        p.line([(hx - 0.2, hy - 4.6), (hx - 0.2, hy - 2.4)], fill=(150, 154, 162, 255), width=0.6)
    elif hat == "tricorne":
        p.polygon([(hx - 3.6, hy - 1.4), (hx - 1.8, hy - 4.2), (hx + 1.8, hy - 4.2), (hx + 3.4, hy - 1.4), (hx, hy - 2.4)], fill=(40, 36, 40, 255), outline=(20, 18, 20, 255), width=0.3)
    elif hat == "cap":
        p.rectangle([hx - 2.6, hy - 4, hx + 2.2, hy - 1.4], fill=(70, 74, 86, 255), outline=(40, 42, 50, 255), width=0.3)
        p.polygon([(hx + 1.6, hy - 1.6), (hx + 4, hy - 1.2), (hx + 1.6, hy - 0.8)], fill=(30, 30, 34, 255))
    elif hat == "hood":
        p.polygon([(hx - 3.2, hy + 1.2), (hx - 2.6, hy - 3.2), (hx + 0.2, hy - 4.4), (hx + 2.7, hy - 2.2), (hx + 2.4, hy - 0.6), (hx - 1.2, hy - 0.8), (hx - 1.6, hy + 1.6)], fill=(70, 110, 60, 255), outline=(40, 64, 34, 255), width=0.3)
    elif hat == "helmet":
        p.pieslice([hx - 3, hy - 3.6, hx + 2.6, hy + 2], 180, 360, fill=(176, 178, 186, 255), outline=(96, 98, 106, 255), width=0.3)
    else:
        p.pieslice([hx - 3, hy - 3.4, hx + 2.6, hy + 1.4], 180, 360, fill=(120, 86, 52, 255))
    # front arm and tool
    hand = (ox + 8 + arm * 2.5 + bend, 13)
    if tool and swing is None:
        # tool carried on the shoulder while walking
        hand = (ox + 10 + bend, 9.5)
        p.line([(ox + 8 + bend, 8.5), hand], fill=CLOTH, width=1.6)
        if tool != "seed":
            p.line([(ox + 3, 6), (ox + 13, 11)], fill=WOOD, width=1.0)
            head = (ox + 3, 6)
            _tool_head(p, tool, head, -1)
        else:
            p.rectangle([hand[0] - 1, hand[1], hand[0] + 2, hand[1] + 3], fill=(140, 100, 60, 255))
            p.line([(hand[0] + 0.5, hand[1]), (hand[0] + 0.5, hand[1] - 3)], fill=(80, 150, 60, 255), width=0.7)
        return
    if tool and swing is not None:
        sx, sy = ox + 9 + bend, 8.5
        if tool == "rod":
            tip = (ox + 16, 3) if swing == 0 else (ox + 17, 9)
            p.line([(sx, sy), (sx + 2, 10)], fill=CLOTH, width=1.6)
            p.line([(sx + 2, 10), tip], fill=WOOD, width=0.6)
            p.line([tip, (ox + 16, 19)], fill=(230, 230, 230, 200), width=0.3)
            return
        if tool == "seed":
            p.line([(sx, sy), (ox + 12, 15 + swing)], fill=CLOTH, width=1.6)
            p.line([(ox + 13, 18), (ox + 13, 15 - swing)], fill=(80, 150, 60, 255), width=0.8)
            p.disc(ox + 12.5, 15 - swing, 1.2, (100, 170, 70, 255))
            return
        if swing == 0:
            grip = (sx - 1, sy - 3)
            head = (sx - 4, sy - 7)
        else:
            grip = (sx + 3, sy + 2)
            head = (sx + 7, sy + 6)
        p.line([(sx, sy), grip], fill=CLOTH, width=1.6)
        p.line([grip, head], fill=WOOD, width=1.0)
        _tool_head(p, tool, head, -1 if swing == 0 else 1)
        return
    p.line([(ox + 8 + bend, 8.5), hand], fill=CLOTH, width=1.6)
    p.disc(hand[0], hand[1], 0.9, SKIN)


def _tool_head(p, tool, at, d):
    x, y = at
    if tool == "axe":
        p.polygon([(x - 1.5, y - 1.5), (x + 1.5, y - 2.5), (x + 1.8, y + 1.5), (x - 1, y + 1)], fill=(190, 196, 204, 255), outline=(90, 94, 100, 255), width=0.3)
    elif tool == "pick":
        p.line([(x - 2.5, y + 1.5), (x, y - 0.5), (x + 2.5, y + 1.5)], fill=(150, 154, 160, 255), width=0.9)
    elif tool == "shovel":
        p.rounded_rectangle([x - 1.3, y - 1.3, x + 1.3, y + 1.6], 0.6, fill=(170, 174, 180, 255), outline=(90, 94, 100, 255), width=0.3)
    elif tool == "hammer":
        p.rectangle([x - 1.5, y - 1, x + 1.5, y + 1], fill=(120, 124, 130, 255))
    elif tool == "spear":
        p.polygon([(x, y - 2.5), (x + 1, y), (x, y + 0.5), (x - 1, y)], fill=(210, 214, 220, 255))


def walkers():
    phases = [(-1, 1), (0, 0), (1, -1), (0, 0)]
    # carriers: 4 walking frames
    frames = []
    for st, ar in phases:
        p = Pen(16, 20, 2); person(p, 0, st, ar); frames.append(p.done())
    save(strip(frames), "unit_carrier")
    # workers with tools: 4 walking frames, then 2 working frames (tool raised, tool striking)
    for tool in ("axe", "pick", "shovel", "rod", "seed", "hammer"):
        frames = []
        for st, ar in phases:
            p = Pen(16, 20, 2); person(p, 0, st, ar, tool=tool); frames.append(p.done())
        for sw in (0, 1):
            p = Pen(16, 20, 2); person(p, 0, 0, 0, tool=tool, swing=sw, bend=0.8 if sw and tool in ("shovel", "seed") else 0.0); frames.append(p.done())
        save(strip(frames), "unit_worker_" + tool)
    # soldiers, one kind per age: 4 walking frames, then 2 fighting frames
    #   0 legionary (crested helmet, big oblong shield, short spear)
    #   1 spearman (round helmet, kite shield, spear) - the original soldier
    #   2 man-at-arms (great helm, heater shield, spear)
    #   3 pikeman (morion, long pike, no shield)
    #   4 musketeer (tricorne, musket with bayonet)
    #   5 rifleman (peaked cap, rifle)
    kit = [("crest", "scutum", "spear", 18), ("helmet", "kite", "spear", 20), ("greathelm", "heater", "spear", 20),
           ("morion", None, "pike", 21), ("tricorne", None, "musket", 15), ("cap", None, "rifle", 14)]
    for era, (hat, shield, arm, reach) in enumerate(kit):
        frames = []
        for i in range(6):
            p = Pen(18, 24, 2)
            st, ar = phases[i] if i < 4 else (0.4 if i == 5 else -0.2, 0)
            q = Pen(16, 20, 2)
            person(q, 0, st, ar, hat=hat)
            p.im.alpha_composite(q.im, (0, 4 * p.f))
            sx = 13 if i < 4 else (9 if i == 4 else 15.5)
            sy = 2 if i < 4 else (6 if i == 4 else 9)
            if arm in ("spear", "pike"):
                if i < 4:
                    p.line([(sx, sy + 20), (sx, sy + 20 - reach)], fill=WOOD, width=0.8)
                    _tool_head(p, "spear", (sx, sy + 20 - reach), 0)
                else:
                    p.line([(sx - 7, sy + 1), (sx, sy)], fill=WOOD, width=0.8)
                    p.polygon([(sx, sy - 1.2), (sx + 2.5, sy), (sx, sy + 1.2)], fill=(210, 214, 220, 255))
            else:
                # a gun: shouldered while marching, levelled to fire (a puff of smoke) when fighting
                if i < 4:
                    p.line([(sx - 1, sy + 13), (sx + 1.5, sy + 13 - reach)], fill=(90, 62, 38, 255), width=1.0)
                    p.line([(sx + 0.6, sy + 9), (sx + 1.5, sy + 13 - reach)], fill=(80, 82, 88, 255), width=0.6)
                    if arm == "musket":
                        p.line([(sx + 1.5, sy + 13 - reach), (sx + 1.7, sy + 10.5 - reach)], fill=(210, 214, 220, 255), width=0.4)
                else:
                    y0 = sy + 3
                    p.line([(sx - 9, y0 + 1), (sx + 1, y0)], fill=(90, 62, 38, 255), width=1.0)
                    p.line([(sx - 4, y0 + 0.5), (sx + 2.5, y0 - 0.2)], fill=(80, 82, 88, 255), width=0.6)
                    if i == 5:
                        p.disc(sx + 4, y0 - 0.4, 1.6, (236, 236, 230, 220))
                        p.disc(sx + 3, y0 - 1.6, 1.0, (250, 210, 120, 255))
            if shield == "scutum":
                p.rounded_rectangle([2, 9, 8, 19], 1.2, fill=CLOTH, outline=(100, 100, 100, 255), width=0.4)
                p.disc(5, 14, 1.0, (210, 180, 90, 255))
            elif shield == "kite":
                p.polygon([(3, 11), (8, 11), (8, 16), (5.5, 19), (3, 16)], fill=CLOTH, outline=(100, 100, 100, 255), width=0.4)
                p.line([(5.5, 12), (5.5, 18)], fill=(180, 180, 180, 255), width=0.5)
            elif shield == "heater":
                p.polygon([(2.8, 11), (8.2, 11), (8, 15), (5.5, 18.6), (3, 15)], fill=CLOTH, outline=(100, 100, 100, 255), width=0.4)
                p.line([(2.9, 13.4), (8.1, 13.4)], fill=(170, 170, 170, 255), width=0.8)
            frames.append(p.done())
        save(strip(frames), "unit_soldier_e%d" % era)
        if era == 1:
            save(strip(frames), "unit_soldier")
    # scout: green hood, a bow on his back and a staff; 4 walking frames
    frames = []
    for st, ar in phases:
        p = Pen(16, 20, 2)
        p.arc([1, 4, 7, 14], 100, 260, fill=WOOD, width=0.8)
        p.line([(2.3, 5), (2.3, 13)], fill=(220, 214, 196, 255), width=0.3)
        person(p, 0, st, ar, hat="hood")
        p.line([(12, 4), (13 + st, 19)], fill=WOOD, width=0.7)
        frames.append(p.done())
    save(strip(frames), "unit_scout")
    # pack mule: 4 frames
    frames = []
    for i in range(4):
        p = Pen(24, 18, 2)
        s = math.sin(i / 4 * math.tau)
        body = (150, 128, 106, 255)
        for x, ph in ((6, 0), (9, 1), (15, 1), (18, 0)):
            o = s * 1.6 * (1 if ph else -1)
            p.line([(x, 11), (x + o, 17)], fill=sh(body, 0.7), width=1.3)
        p.ellipse([3, 5, 20, 13], fill=body, outline=sh(body, 0.6), width=0.4)
        p.polygon([(17, 8), (20, 2), (24, 4), (23, 7), (20, 9)], fill=body, outline=sh(body, 0.6), width=0.4)
        p.line([(20, 2), (19, -1)], fill=sh(body, 0.75), width=0.8)
        p.line([(21, 2), (21.5, -1)], fill=sh(body, 0.75), width=0.8)
        p.point((22, 4), fill=(20, 20, 20, 255))
        p.line([(3, 7), (1, 11 + s)], fill=sh(body, 0.6), width=0.7)
        p.rounded_rectangle([6, 2, 15, 9], 1.5, fill=CLOTH, outline=(120, 120, 120, 255), width=0.4)
        p.line([(6, 5.5), (15, 5.5)], fill=(170, 150, 120, 255), width=0.5)
        frames.append(p.done())
    save(strip(frames), "unit_mule")
    # ox cart: an ox pulling a covered cart; wheel spokes and legs move
    frames = []
    for i in range(4):
        p = Pen(32, 20, 2)
        s = math.sin(i / 4 * math.tau)
        ox = (120, 92, 66, 255)
        for x, ph in ((22, 0), (24, 1), (28, 1), (30, 0)):
            o = s * 1.2 * (1 if ph else -1)
            p.line([(x, 12), (x + o, 18)], fill=sh(ox, 0.7), width=1.2)
        p.ellipse([20, 7, 31, 14], fill=ox, outline=sh(ox, 0.6), width=0.4)
        p.ellipse([28, 6, 32, 11], fill=sh(ox, 0.9))
        p.line([(29, 6), (28, 4)], fill=(230, 220, 190, 255), width=0.6)
        p.line([(18, 11), (22, 10)], fill=WOOD, width=0.8)
        p.rectangle([2, 8, 19, 13], fill=(140, 100, 60, 255), outline=(90, 62, 36, 255), width=0.5)
        p.pieslice([2, 0, 19, 15], 180, 360, fill=CLOTH, outline=(130, 130, 130, 255), width=0.5)
        p.line([(7, 1), (7, 8)], fill=(200, 200, 200, 255), width=0.4)
        p.line([(13, 1), (13, 8)], fill=(200, 200, 200, 255), width=0.4)
        p.ellipse([5, 11, 13, 19], fill=(110, 80, 50, 255), outline=(60, 40, 24, 255), width=0.7)
        for k in range(3):
            a = (i / 4 + k / 3) * math.pi
            p.line([(9 - math.cos(a) * 3.5, 15 - math.sin(a) * 3.5), (9 + math.cos(a) * 3.5, 15 + math.sin(a) * 3.5)], fill=(70, 50, 30, 255), width=0.5)
        frames.append(p.done())
    save(strip(frames), "unit_cart")
    # farm animals: 4 frames each
    for name, body, head in (("sheep", (240, 238, 228, 255), (60, 56, 52, 255)), ("pig", (236, 170, 160, 255), (226, 150, 140, 255))):
        frames = []
        for i in range(4):
            p = Pen(12, 10, 2)
            s = math.sin(i / 4 * math.tau)
            for x, ph in ((3, 0), (5, 1), (8, 1), (10, 0)):
                p.line([(x, 6), (x + s * 0.8 * (1 if ph else -1), 9.5)], fill=sh(head, 0.8), width=0.8)
            if name == "sheep":
                for (x, y) in [(3, 4), (6, 3), (8, 4.5), (5, 6), (8, 6.5), (3.5, 6.5)]:
                    p.disc(x, y, 2.2, body)
                p.ellipse([9, 2.5, 12, 6], fill=head)
            else:
                p.ellipse([1, 2.5, 11, 8], fill=body, outline=sh(body, 0.75), width=0.3)
                p.ellipse([9.5, 4, 12, 6.5], fill=sh(body, 1.08), outline=sh(body, 0.7), width=0.3)
                p.line([(1, 4), (0, 3)], fill=sh(body, 0.8), width=0.4)
            p.point((10.5, 3.6 if name == "sheep" else 4.6), fill=(10, 10, 10, 255))
            frames.append(p.done())
        save(strip(frames), "unit_" + name)
    # wild animals: 4 walking frames each, facing right
    wild = {
        "deer": ((150, 104, 62, 255), 16, 14),
        "boar": ((86, 64, 48, 255), 14, 10),
        "hare": ((150, 132, 108, 255), 9, 8),
        "wolf": ((128, 128, 124, 255), 16, 11),
    }
    for name, (body, W, H) in wild.items():
        frames = []
        for i in range(4):
            p = Pen(W, H, 2)
            s = math.sin(i / 4 * math.tau)
            dk = sh(body, 0.7)
            lt = sh(body, 1.18)
            if name == "deer":
                for x, ph in ((4, 0), (5.5, 1), (10.5, 1), (12, 0)):
                    p.line([(x, 8), (x + s * 1.2 * (1 if ph else -1), 13.5)], fill=dk, width=0.8)
                p.ellipse([2.5, 5, 13.5, 9.5], fill=body, outline=dk, width=0.3)
                p.ellipse([4, 7.5, 12, 9.4], fill=lt)
                p.line([(12.5, 6.5), (14, 3)], fill=body, width=1.6)
                p.ellipse([12.6, 1.6, 15.8, 4.2], fill=body, outline=dk, width=0.3)
                for dx in (0, 1.2):
                    p.line([(13.5 + dx, 2), (13 + dx, 0.2)], fill=(90, 70, 50, 255), width=0.4)
                    p.line([(13.2 + dx, 1), (12.2 + dx, 0.4)], fill=(90, 70, 50, 255), width=0.4)
                p.disc(2.6, 6, 0.9, (240, 236, 226, 255))
                p.point((15, 2.6), fill=(20, 16, 12, 255))
            elif name == "boar":
                for x, ph in ((3, 0), (4.5, 1), (9, 1), (10.5, 0)):
                    p.line([(x, 6.5), (x + s * 0.8 * (1 if ph else -1), 9.6)], fill=dk, width=0.9)
                p.ellipse([1, 2.5, 12, 8], fill=body, outline=dk, width=0.3)
                p.polygon([(3, 2.6), (8, 1.8), (10, 2.8)], fill=dk)
                p.polygon([(10.5, 3.5), (13.8, 5.2), (13.6, 6.6), (10.5, 7.2)], fill=sh(body, 1.05), outline=dk, width=0.3)
                p.line([(13, 6.4), (13.6, 5.2)], fill=(236, 230, 210, 255), width=0.4)
                p.point((11.8, 4.6), fill=(10, 8, 6, 255))
            elif name == "hare":
                hop = abs(s) * 1.2
                p.ellipse([1, 3.6 - hop, 7, 7.4 - hop], fill=body, outline=dk, width=0.3)
                p.ellipse([5.4, 2.6 - hop, 8.4, 5.2 - hop], fill=body, outline=dk, width=0.3)
                p.line([(6.4, 3 - hop), (5.6, 0.2 - hop)], fill=body, width=0.7)
                p.line([(7.2, 3 - hop), (7.0, 0.2 - hop)], fill=dk, width=0.6)
                p.line([(2, 7 - hop), (1 - s, 7.9)], fill=dk, width=0.7)
                p.disc(1.2, 4.6 - hop, 0.7, (240, 236, 226, 255))
                p.point((7.6, 3.6 - hop), fill=(10, 8, 6, 255))
            else:  # wolf
                for x, ph in ((3.5, 0), (5, 1), (10.5, 1), (12, 0)):
                    p.line([(x, 6.5), (x + s * 1.2 * (1 if ph else -1), 10.6)], fill=dk, width=0.8)
                p.ellipse([2.5, 3.5, 13, 7.6], fill=body, outline=dk, width=0.3)
                p.ellipse([4, 6, 11.5, 7.5], fill=lt)
                p.line([(2.8, 4.5), (0.4, 6.5)], fill=body, width=1.2)
                p.polygon([(12, 3.5), (15.8, 4.6), (15.6, 5.8), (12.4, 6.6)], fill=body, outline=dk, width=0.3)
                p.polygon([(12.4, 3.8), (12.8, 2), (13.6, 3.6)], fill=dk)
                p.point((14.2, 4.4), fill=(240, 220, 120, 255))
            frames.append(p.done())
        save(strip(frames), "unit_" + name)
    # flag: 4 frames of cloth waving in the wind (white, tinted with the realm colour)
    frames = []
    for i in range(4):
        p = Pen(10, 14, 2)
        p.line([(1, 0), (1, 13.5)], fill=(70, 50, 30, 255), width=0.8)
        pts_top = [(1.5 + k, 1 + math.sin(i / 4 * math.tau + k * 0.8) * 0.8) for k in range(9)]
        pts_bot = [(1.5 + k, 6 + math.sin(i / 4 * math.tau + k * 0.8) * 0.8) for k in range(8, -1, -1)]
        p.polygon(pts_top + pts_bot, fill=(244, 244, 244, 255), outline=(150, 150, 150, 255), width=0.3)
        frames.append(p.done())
    save(strip(frames), "unit_flag")


def effects():
    # scaffolding laid over buildings under construction
    p = Pen(64, 64, 2)
    pole = (172, 132, 82, 255)
    for x in (8, 32, 56):
        p.line([(x, 63), (x, 14)], fill=pole, width=1.6)
    for y in (22, 38, 54):
        p.line([(4, y), (60, y)], fill=pole, width=1.4)
        p.rectangle([4, y - 1.6, 60, y], fill=(196, 160, 104, 255), outline=(120, 86, 50, 255), width=0.4)
    p.line([(8, 54), (32, 22)], fill=sh(pole, 0.8), width=1.0)
    p.line([(32, 54), (56, 22)], fill=sh(pole, 0.8), width=1.0)
    for y in range(26, 62, 4):
        p.line([(44, y), (50, y)], fill=sh(pole, 0.9), width=0.6)
    p.line([(44, 22), (44, 63)], fill=pole, width=0.8)
    p.line([(50, 22), (50, 63)], fill=pole, width=0.8)
    save(p.done(), "fx_construction")
    # windmill sails, turned by the game around their centre
    p = Pen(48, 48, 2)
    for k in range(4):
        a = k * math.pi / 2
        ca, sa = math.cos(a), math.sin(a)

        def rot(u, v):
            return (24 + u * ca - v * sa, 24 + u * sa + v * ca)
        p.line([rot(0, 0), rot(23, 0)], fill=(96, 70, 46, 255), width=1.1)
        sail = [rot(6, 0.5), rot(23, 0.5), rot(23, 6), rot(6, 5)]
        p.polygon(sail, fill=(236, 230, 214, 235), outline=(130, 110, 86, 255), width=0.4)
        for u in (10, 14, 18):
            p.line([rot(u, 0.5), rot(u, 5.5)], fill=(150, 128, 100, 255), width=0.35)
    p.disc(24, 24, 2.4, (70, 52, 34, 255))
    save(p.done(), "anim_sails")
    # a soft puff of smoke and a soft glow, drawn by the game many times with changing size and fade
    yy, xx = np.mgrid[0:32, 0:32]
    r = np.sqrt((xx - 15.5) ** 2 + (yy - 15.5) ** 2) / 15.5
    a = np.clip(1 - r, 0, 1) ** 1.6
    smoke = np.zeros((32, 32, 4), np.uint8)
    smoke[:, :, 0:3] = 176
    smoke[:, :, 3] = (a * 230).astype(np.uint8)
    save(Image.fromarray(smoke, "RGBA"), "fx_smoke")
    glow = np.zeros((32, 32, 4), np.uint8)
    glow[:, :, 0] = 255; glow[:, :, 1] = (150 + 80 * np.clip(1 - r * 1.5, 0, 1)).astype(np.uint8); glow[:, :, 2] = 60
    glow[:, :, 3] = (np.clip(1 - r, 0, 1) ** 2 * 255).astype(np.uint8)
    save(Image.fromarray(glow, "RGBA"), "fx_glow")


def ui_icons():
    cls = {"peasant": (150, 120, 70), "artisan": (90, 120, 170), "noble": (160, 110, 190), "soldier": (180, 70, 60)}
    for k, c in cls.items():
        d = Pen(20, 20, 2)
        d.ellipse([6, 1, 14, 9], fill=(235, 210, 180, 255)); d.pieslice([2, 9, 18, 27], 180, 360, fill=c + (255,))
        if k == "noble": d.polygon([(6, 2), (8, -1), (10, 2), (12, -1), (14, 2)], fill=(250, 210, 60, 255))
        if k == "soldier": d.rectangle([6, 0, 14, 3], fill=(170, 170, 176, 255))
        if k == "artisan": d.line([(14, 12), (18, 6)], fill=(110, 110, 110, 255), width=2)
        save(icon_polish(d.done()), "ui_" + k)


def icon_polish(img):
    """Depth for a small icon: light from above (brighter top, darker foot), a glint along the top edge
    and a soft shadow under it to the lower right."""
    a = np.asarray(img.convert("RGBA")).astype(np.float32)
    h, w = a.shape[:2]
    al = a[:, :, 3] / 255.0
    ys = np.where(al.max(axis=1) > 0.3)[0]
    if len(ys) == 0:
        return img
    top, bot = ys[0], max(ys[-1], ys[0] + 1)
    yy = np.clip((np.arange(h) - top) / (bot - top), 0, 1)[:, None]
    f = 1.12 - 0.26 * yy
    solid = al > 0.5
    up = np.zeros_like(solid); up[1:, :] = ~solid[:-1, :]
    f = np.where(solid & up, f * 1.18, f)
    a[:, :, :3] = np.clip(a[:, :, :3] * f[:, :, None], 0, 255)
    out = Image.fromarray(a.astype(np.uint8), "RGBA")
    # the shadow: the shape's alpha, shifted and blurred, in dark brown, under the icon
    from PIL import ImageFilter
    k = max(1, w // 24)
    shadow = Image.new("RGBA", (w, h), (30, 20, 10, 0))
    sa = img.getchannel("A").filter(ImageFilter.GaussianBlur(k * 0.9)).point(lambda v: int(v * 0.45))
    shadow.putalpha(ImageChops.offset(sa, k, k))
    base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    base.alpha_composite(shadow)
    base.alpha_composite(out)
    return base


def resources():
    """Resource icons, 48 x 48 (the 24 x 24 designs drawn at twice the size, with depth)."""
    for r in json.load(open(os.path.join(ROOT, "data", "resources.json"))):
        save(icon_polish(icon(r.get("icon", "dot"), rgb(r["color"]), 48)), "res_" + r["id"])


AGE_COL = [(150, 60, 50), (120, 90, 60), (90, 110, 70), (70, 100, 150), (120, 80, 150), (70, 70, 80)]


def techs():
    """Research icons, 96 x 96: a picture of what the study is about (tech_icons.py) on a parchment disc,
    in a shield (or, for the repeatable studies, a round badge) in the colour of its age."""
    import tech_icons
    p = os.path.join(ROOT, "data", "techs.json")
    if not os.path.exists(p):
        return
    data = json.load(open(p))
    for t in data["techs"] + data.get("repeatables", []):
        rep = t in data.get("repeatables", [])
        c = AGE_COL[min(len(AGE_COL) - 1, int(t.get("age", 0)))]
        d = Pen(48, 48, 2)
        if rep:
            d.ellipse([2, 2, 46, 46], fill=c + (255,), outline=sh(c, 0.45), width=1.0)
            d.ellipse([5, 5, 43, 43], outline=sh(c, 1.45), width=0.8)
            d.arc([3.5, 3.5, 44.5, 44.5], 200, 330, fill=(255, 255, 255, 90), width=1.0)
        else:
            sh_pts = [(5, 3), (43, 3), (43, 26), (24, 46), (5, 26)]
            d.polygon(sh_pts, fill=c + (255,), outline=sh(c, 0.45), width=1.0)
            d.shade(sh_pts, 3, 46, (255, 255, 255, 60), (0, 0, 0, 60))
            d.polygon([(8, 6), (40, 6), (40, 25), (24, 42), (8, 25)], outline=sh(c, 1.5), width=0.7)
        # the parchment disc the picture sits on
        d.disc(24, 22.5, 15.5, (0, 0, 0, 60))
        d.disc(24, 22, 15, (238, 228, 200, 255))
        d.shade([(9, 7), (39, 7), (39, 37), (9, 37)], 7, 37, (255, 255, 255, 0), (150, 120, 80, 0))
        d.ellipse([9, 7, 39, 37], outline=(160, 130, 90, 255), width=0.6)
        tech_icons.draw(d, t)
        if t.get("final"):
            d.polygon([(16, 0.5), (20, 5), (24, 0.5), (28, 5), (32, 0.5), (32, 7), (16, 7)], fill=(250, 210, 60, 255), outline=(150, 110, 30, 255), width=0.5)
        im = d.done()
        save(im, "tech_" + t["id"])


if __name__ == "__main__":
    terrain(); decos(); roads(); resources(); buildings(); walkers(); effects(); ui_icons(); techs()
    # the detailed townsfolk, porters, workers, mules and ox carts (they replace the simple walkers)
    import folk_sprites
    folk_sprites.build_all()
    print("textures in", OUT, len([f for f in os.listdir(OUT) if f.endswith(".png")]))
