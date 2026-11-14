"""Own pictures for buildings that share a drawing style in make_textures.py.

Many buildings used to be the same box with a different wall colour and sign (28 workshops, 12 barns,
9 sheds...). Each building listed here gets its own shape (wider, taller, two storeys, a tower, an
open shed, a dome...) and the tools and goods of its trade in front of it: a log on a saw trestle,
a bread oven, barrels and a copper, an anvil and a glowing forge, hides on frames, cloth drying,
animals in pens, hop poles and an oast house, skeps, salt pans, a ship on the slipway...

draw(mt, g, bid, icon) draws building bid with the helpers of make_textures (module mt, picture g)
and returns True, or False when bid has no picture of its own. Where its chimney, furnace or wheel
ended up is kept in ANCH[bid] (design pixels), which tools/bld_anchors.py writes into buildings.json
so the game puts smoke and glow in the right place.
"""
import math, random

mt = None
ANCH = {}
_cur = None


def _set(key, x, y):
    if _cur is not None and key not in ANCH[_cur]:
        ANCH[_cur][key] = (x, y)


class BlendPen:
    """Wraps a Pen so that see-through colours blend over what is drawn already (PIL's ImageDraw
    replaces the pixels of an RGBA picture instead, which would punch holes in the building)."""

    def __init__(self, pen):
        self.pen = pen

    def __getattr__(self, name):
        fn = getattr(self.pen, name)
        if name not in ("polygon", "rectangle", "rounded_rectangle", "ellipse", "pieslice", "arc", "line", "disc", "point"):
            return fn

        def call(*a, **kw):
            cols = [kw.get("fill"), kw.get("outline")] + [x for x in a if isinstance(x, tuple) and len(x) == 4 and all(isinstance(v, int) for v in x)]
            if any(c is not None and len(c) == 4 and c[3] < 255 for c in cols):
                layer = mt.Pen(self.pen.w, self.pen.h, self.pen.k)
                getattr(layer, name)(*a, **kw)
                self.pen.im.alpha_composite(layer.im)
            else:
                fn(*a, **kw)
        return call


def C(c, a=255):
    return tuple(c[:3]) + (a,)


def sh(c, f):
    return mt.sh(c, f)


# ------------------------------------------------------------------ small things
def wood_fill(g, pts, col, board=2.0, vertical=True, out=0.5):
    p = g.p
    p.polygon(pts, fill=C(col))
    sd = g._seed()
    p.texfill(pts, lambda W, H, F: mt.BT.wood(W, H, F, tuple(col[:3]), sd, board=board, vertical=vertical, gap=0.2))
    if out:
        p.polygon(pts, outline=sh(C(col), 0.5), width=out)


def stone_fill(g, pts, col, mat="stone", f=1.0):
    g.p.polygon(pts, fill=C(sh(col, f)))
    g.surface(pts, mat, sh(col, f))


def chim(g, x, y_top, y_base):
    g.chimney(x, y_top, y_base)
    _set("smoke", x + 2, y_top - 2)


def log_pile(g, x, y, rows=3, r=1.9):
    p = g.p
    for k in range(rows):
        for j in range(rows - k):
            cx = x + r + 0.2 + j * (2 * r + 0.2) + k * (r + 0.1)
            cy = y - r - k * (2 * r - 0.4)
            p.disc(cx, cy, r, (150, 104, 60, 255))
            p.disc(cx, cy, r * 0.58, (206, 166, 114, 255))
            p.point((cx - 0.4, cy - 0.4), fill=(168, 124, 78, 255))


def long_log(g, x0, x1, y, r=2.2, col=(120, 84, 50)):
    """A trunk lying across: bark on the side, the cut end with rings on the left."""
    p = g.p
    body = [(x0, y - r), (x1, y - r), (x1, y + r), (x0, y + r)]
    wood_fill(g, body, col, 1.2, False, 0.4)
    p.line([(x0, y - r + 0.5), (x1, y - r + 0.5)], fill=sh(C(col), 1.3), width=0.4)
    p.disc(x0 + 0.5, y + 0.5, r, (196, 156, 104, 255))
    p.ellipse([x0 - r + 1.2, y - r + 1.2, x0 + r - 1.2, y + r - 1.2], outline=(160, 120, 76, 255), width=0.3)


def barrel(g, x, y, w=5, h=6, col=(128, 86, 48)):
    p = g.p
    c = C(col)
    p.rounded_rectangle([x, y - h, x + w, y], 1.4, fill=c, outline=sh(c, 0.45), width=0.4)
    p.rectangle([x + w * 0.66, y - h + 0.6, x + w - 0.5, y - 0.6], fill=(0, 0, 0, 50))
    p.line([(x + w * 0.3, y - h + 0.5), (x + w * 0.3, y - 0.5)], fill=sh(c, 1.3), width=0.35)
    for f in (0.22, 0.78):
        p.line([(x + 0.2, y - h * f), (x + w - 0.2, y - h * f)], fill=(58, 54, 50, 255), width=0.6)
    p.ellipse([x + 0.3, y - h - 0.6, x + w - 0.3, y - h + 0.8], fill=sh(c, 0.8), outline=(58, 54, 50, 255), width=0.3)


def barrel_end(g, cx, cy, r=2.6, col=(132, 88, 50)):
    """A barrel lying down, seen end on."""
    p = g.p
    p.disc(cx, cy, r, (58, 54, 50, 255))
    p.disc(cx, cy, r - 0.6, C(col))
    p.disc(cx - 0.3, cy - 0.3, r - 1.4, sh(C(col), 1.2))
    p.line([(cx - r + 0.8, cy - 0.5), (cx + r - 0.8, cy - 0.5)], fill=sh(C(col), 0.7), width=0.3)
    p.disc(cx + 0.4, cy + 0.6, 0.5, (40, 30, 20, 255))


def crate(g, x, y, s=5, col=(168, 128, 78)):
    p = g.p
    c = C(col)
    p.polygon([(x, y - s), (x + s, y - s), (x + s + 1.6, y - s - 1.2), (x + 1.6, y - s - 1.2)], fill=sh(c, 1.22), outline=sh(c, 0.5), width=0.3)
    p.polygon([(x + s, y), (x + s + 1.6, y - 1.2), (x + s + 1.6, y - s - 1.2), (x + s, y - s)], fill=sh(c, 0.68), outline=sh(c, 0.45), width=0.3)
    front = [(x, y), (x + s, y), (x + s, y - s), (x, y - s)]
    wood_fill(g, front, col, 1.6, False, 0)
    p.line([(x + 0.3, y - 0.3), (x + s - 0.3, y - s + 0.3)], fill=sh(c, 0.62), width=0.5)
    p.polygon(front, outline=sh(c, 0.42), width=0.45)


def sack(g, x, y, col=(214, 196, 150)):
    p = g.p
    c = C(col)
    p.polygon([(x, y), (x + 5, y), (x + 5.4, y - 3.5), (x + 4, y - 5.2), (x + 2.8, y - 6), (x + 1.8, y - 5.2), (x + 0.4, y - 4)], fill=c, outline=sh(c, 0.5), width=0.4)
    p.line([(x + 1.6, y - 4.8), (x + 4, y - 4.8)], fill=sh(c, 0.55), width=0.4)
    p.line([(x + 3.8, y - 3.8), (x + 4.6, y - 0.6)], fill=(0, 0, 0, 40), width=0.8)


def anvil(g, x, y):
    p = g.p
    stump = [(x + 1, y - 4), (x + 5, y - 4), (x + 5.4, y), (x + 0.6, y)]
    wood_fill(g, stump, (110, 78, 46), 1.4, True, 0.35)
    p.polygon([(x - 1.5, y - 6.6), (x + 6.5, y - 6.6), (x + 9, y - 5.9), (x + 5.4, y - 5.3), (x + 4.6, y - 4), (x + 1.4, y - 4),
               (x + 0.6, y - 5.3), (x - 1.5, y - 5.6)], fill=(68, 70, 76, 255), outline=(28, 28, 32, 255), width=0.35)
    p.line([(x - 1.3, y - 6.5), (x + 6.4, y - 6.5)], fill=(178, 180, 188, 255), width=0.45)


def glow_hole(g, x0, y0, x1, y1, arch=True):
    """A furnace or forge mouth glowing from inside."""
    p = g.p
    w = x1 - x0
    p.rectangle([x0 - 0.8, y0 - 0.4, x1 + 0.8, y1], fill=(54, 28, 18, 255))
    if arch:
        p.pieslice([x0 - 0.8, y0 - w / 2 - 0.8, x1 + 0.8, y0 + w / 2 + 0.4], 180, 360, fill=(54, 28, 18, 255))
        p.pieslice([x0, y0 - w / 2, x1, y0 + w / 2], 180, 360, fill=(255, 150, 54, 255))
    p.shade([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], y0, y1, (255, 140, 50, 255), (255, 220, 120, 255))
    p.line([(x0 + 0.5, y1 - 0.6), (x1 - 0.5, y1 - 0.6)], fill=(255, 246, 200, 255), width=0.6)


def wheel(g, cx, cy, r, col=(96, 66, 38), spokes=8, w=0.9):
    p = g.p
    c = C(col)
    for k in range(spokes):
        a = k * math.pi * 2 / spokes
        p.line([(cx, cy), (cx + math.cos(a) * (r - 0.4), cy + math.sin(a) * (r - 0.4))], fill=sh(c, 0.9), width=0.45)
    p.ellipse([cx - r, cy - r, cx + r - 1, cy + r - 1], outline=c, width=w)
    p.arc([cx - r + 0.3, cy - r + 0.3, cx + r - 1.3, cy + r - 1.3], 180, 270, fill=sh(c, 1.35), width=0.35)
    p.disc(cx, cy, 1.1, sh(c, 0.55))


def awning(g, x0, x1, y, col, d=4, n=None):
    p = g.p
    n = n or max(3, int((x1 - x0) / 3.2))
    w = (x1 - x0) / n
    cream = (238, 232, 216, 255)
    for k in range(n):
        c = col if k % 2 == 0 else cream
        p.polygon([(x0 + k * w, y), (x0 + (k + 1) * w, y), (x0 + (k + 1) * w + 0.8, y + d), (x0 + k * w + 0.8, y + d)], fill=c)
        p.pieslice([x0 + k * w + 0.8, y + d - 1.1, x0 + (k + 1) * w + 0.8, y + d + 1.1], 0, 180, fill=c)
    p.shade([(x0, y), (x1, y), (x1 + 0.8, y + d), (x0 + 0.8, y + d)], y, y + d, (255, 255, 255, 40), (0, 0, 0, 40))
    p.line([(x0, y), (x1, y)], fill=sh(col, 0.45), width=0.6)
    p.shade([(x0 + 0.8, y + d + 1), (x1 + 0.8, y + d + 1), (x1 + 0.8, y + d + 3), (x0 + 0.8, y + d + 3)], y + d + 1, y + d + 3, (0, 0, 0, 60), (0, 0, 0, 0))


def fence(g, x0, x1, y, step=4.0, h=5.0, col=(118, 84, 52)):
    p = g.p
    c = C(col)
    for yy in (y - h * 0.75, y - h * 0.35):
        p.line([(x0, yy), (x1, yy)], fill=sh(c, 0.9), width=0.7)
        p.line([(x0, yy - 0.3), (x1, yy - 0.3)], fill=sh(c, 1.3), width=0.25)
    x = x0
    while x <= x1 + 0.01:
        p.rectangle([x - 0.5, y - h, x + 0.5, y], fill=c, outline=sh(c, 0.5), width=0.25)
        x += step


def fence_back(g, x0, y0, dx, dy, n, h=4.0, col=(118, 84, 52)):
    """A fence running back into the picture (up and to the right)."""
    p = g.p
    c = C(col)
    for f in (0.75, 0.35):
        p.line([(x0, y0 - h * f), (x0 + dx, y0 + dy - h * f)], fill=sh(c, 0.85), width=0.6)
    for k in range(n + 1):
        x = x0 + dx * k / n
        y = y0 + dy * k / n
        p.rectangle([x - 0.4, y - h, x + 0.4, y], fill=c)


def tree(g, cx, y, r=7.0, fruit=None, trunk=8.0, col=(72, 120, 50)):
    p = g.p
    p.ellipse([cx - r * 0.8, y - 1.2, cx + r * 0.8, y + 1.4], fill=(0, 0, 0, 60))
    p.polygon([(cx - 1, y), (cx - 0.6, y - trunk), (cx + 0.8, y - trunk), (cx + 1.2, y)], fill=(104, 74, 48, 255))
    cy = y - trunk - r * 0.6
    rnd = random.Random(int(cx * 13 + y))
    p.disc(cx, cy, r, sh(C(col), 0.7))
    for k in range(9):
        a = rnd.uniform(0, math.tau)
        d = rnd.uniform(0, r * 0.55)
        rr = rnd.uniform(r * 0.35, r * 0.55)
        f = 0.85 + 0.35 * (-math.sin(a) * 0.5 + 0.5) * (1 - d / r)
        p.disc(cx + math.cos(a) * d, cy + math.sin(a) * d, rr, sh(C(col), f))
    p.disc(cx - r * 0.3, cy - r * 0.35, r * 0.35, sh(C(col), 1.25))
    if fruit:
        for k in range(int(r * 1.6)):
            a = rnd.uniform(0, math.tau)
            d = rnd.uniform(0, r * 0.85)
            p.disc(cx + math.cos(a) * d, cy + math.sin(a) * d * 0.9, 0.8, C(fruit))


def sheep(g, x, y, flip=False):
    p = g.p
    s = -1 if flip else 1
    for lx in (1.2, 4.4):
        p.line([(x + lx, y - 2), (x + lx, y)], fill=(50, 44, 40, 255), width=0.6)
    for ox, oy, r in ((1.6, -3.4, 1.9), (3.2, -4.0, 2.1), (4.6, -3.3, 1.8), (3, -2.8, 1.8)):
        p.disc(x + ox, y + oy, r, (236, 232, 220, 255))
    p.disc(x + 2.6, y - 4.6, 1.0, (250, 248, 240, 255))
    hx = x + (6.4 if s > 0 else -0.8)
    p.ellipse([hx - 1.1, y - 5.6, hx + 1.0, y - 3.2], fill=(52, 46, 42, 255))
    p.point((hx + 0.3 * s, y - 4.8), fill=(220, 210, 190, 255))


def pig(g, x, y, flip=False):
    p = g.p
    pink = (232, 168, 160, 255)
    for lx in (1.4, 4.6):
        p.line([(x + lx, y - 1.6), (x + lx, y)], fill=sh(pink, 0.75), width=0.7)
    p.ellipse([x, y - 4.6, x + 6.4, y - 1.0], fill=pink, outline=sh(pink, 0.6), width=0.3)
    hx = x + 6.2 if not flip else x - 0.4
    p.disc(hx, y - 3.0, 1.5, pink)
    p.rectangle([hx + (0.9 if not flip else -1.7), y - 3.4, hx + (1.7 if not flip else -0.9), y - 2.2], fill=sh(pink, 0.85))
    p.polygon([(hx - 0.6, y - 4.2), (hx - 0.2, y - 5.4), (hx + 0.6, y - 4.2)], fill=sh(pink, 0.85))
    tx = x - 0.3 if not flip else x + 6.6
    p.arc([tx - 0.8, y - 4.6, tx + 0.4, y - 3.4], 0, 300, fill=sh(pink, 0.7), width=0.35)
    p.ellipse([x + 1, y - 4.4, x + 4.5, y - 3.4], fill=(255, 210, 200, 90))


def cow(g, x, y):
    p = g.p
    white = (238, 234, 226, 255)
    blk = (46, 40, 36, 255)
    for lx in (1.0, 2.4, 7.2, 8.6):
        p.line([(x + lx, y - 3), (x + lx, y)], fill=sh(white, 0.7), width=0.7)
    p.rounded_rectangle([x, y - 7, x + 9.6, y - 2.6], 1.8, fill=white, outline=(120, 116, 110, 255), width=0.3)
    p.ellipse([x + 2.4, y - 6.8, x + 5.4, y - 4.2], fill=blk)
    p.ellipse([x + 6.6, y - 6.4, x + 8.4, y - 3.8], fill=blk)
    p.disc(x + 4.8, y - 2.4, 0.9, (236, 170, 170, 255))
    p.ellipse([x + 9, y - 8.4, x + 12.2, y - 5.0], fill=white, outline=(120, 116, 110, 255), width=0.3)
    p.rectangle([x + 10.6, y - 6.6, x + 12.2, y - 5.0], fill=(220, 170, 160, 255))
    p.line([(x + 9.4, y - 8.4), (x + 8.8, y - 9.4)], fill=(220, 214, 190, 255), width=0.4)
    p.line([(x + 11.2, y - 8.4), (x + 11.8, y - 9.4)], fill=(220, 214, 190, 255), width=0.4)
    p.line([(x, y - 6.4), (x - 0.8, y - 3.4)], fill=sh(white, 0.6), width=0.35)


def donkey(g, x, y, col=(136, 124, 112), flip=False, s=1.0):
    p = g.p
    c = C(col)
    def X(u):
        return x + (u if not flip else 9 * s - u)
    for lx in (1.0, 2.2, 6.6, 7.8):
        p.line([(X(lx * s), y - 3 * s), (X(lx * s), y)], fill=sh(c, 0.7), width=0.7 * s)
    p.rounded_rectangle([min(X(0), X(8.8 * s)), y - 6.6 * s, max(X(0), X(8.8 * s)), y - 2.6 * s], 1.6 * s, fill=c, outline=sh(c, 0.5), width=0.3)
    p.polygon([(X(7.6 * s), y - 6 * s), (X(9.2 * s), y - 9 * s), (X(11.2 * s), y - 8 * s), (X(11.6 * s), y - 6.6 * s), (X(10.4 * s), y - 6 * s), (X(9 * s), y - 4.6 * s)], fill=c, outline=sh(c, 0.5), width=0.3)
    p.disc(X(11.1 * s), y - 6.8 * s, 0.8 * s, (220, 214, 204, 255))
    for ex in (9.4, 10.2):
        p.polygon([(X(ex * s), y - 8.8 * s), (X((ex - 0.6) * s), y - 12 * s), (X((ex + 0.3) * s), y - 8.6 * s)], fill=sh(c, 0.85))
    p.line([(X(0.2), y - 6 * s), (X(-0.6), y - 3.2 * s)], fill=sh(c, 0.55), width=0.4)
    p.ellipse([min(X(2 * s), X(6 * s)), y - 6.4 * s, max(X(2 * s), X(6 * s)), y - 5.4 * s], fill=sh(c, 1.18))


def hide(g, x, y, w=10, h=10, col=(180, 136, 90)):
    """A hide stretched with cords on a square frame; (x, y) is the frame's bottom left."""
    p = g.p
    for fx in (x, x + w):
        p.line([(fx, y), (fx, y - h - 1)], fill=C(mt.WOOD), width=0.8)
    p.line([(x - 0.5, y - h), (x + w + 0.5, y - h)], fill=C(mt.WOOD), width=0.8)
    p.line([(x - 0.5, y - 1.2), (x + w + 0.5, y - 1.2)], fill=C(mt.WOOD), width=0.8)
    c = C(col)
    pts = [(x + 1.6, y - h + 1.4), (x + w / 2, y - h + 1.0), (x + w - 1.6, y - h + 1.4), (x + w - 1.0, y - h / 2),
           (x + w - 1.6, y - 2.4), (x + w / 2, y - 2.0), (x + 1.6, y - 2.4), (x + 1.0, y - h / 2)]
    p.polygon(pts, fill=c, outline=sh(c, 0.6), width=0.35)
    p.shade(pts, y - h, y - 2, (255, 255, 255, 40), (0, 0, 0, 40))
    for (ax, ay), (bx, by) in (((x + 1.6, y - h + 1.4), (x, y - h)), ((x + w - 1.6, y - h + 1.4), (x + w, y - h)),
                               ((x + 1.6, y - 2.4), (x, y - 1.2)), ((x + w - 1.6, y - 2.4), (x + w, y - 1.2))):
        p.line([(ax, ay), (bx, by)], fill=(210, 196, 160, 255), width=0.3)


def cloth(g, x, y, w, h, col, wave=True):
    """A length of cloth hanging from y down."""
    p = g.p
    c = C(col)
    pts = [(x, y), (x + w, y), (x + w + 0.4, y + h - 0.6), (x + w * 0.5, y + h + 0.4), (x - 0.2, y + h - 0.4)]
    p.polygon(pts, fill=c, outline=sh(c, 0.55), width=0.3)
    for k in range(1, int(w / 1.6)):
        xx = x + k * 1.6
        p.line([(xx, y + 0.3), (xx + 0.2, y + h - 0.6)], fill=sh(c, 0.82 if k % 2 else 1.12), width=0.4)
    p.shade(pts, y, y + h, (255, 255, 255, 30), (0, 0, 0, 50))


def skep(g, cx, y, r=3.4):
    p = g.p
    straw = (214, 176, 92, 255)
    p.pieslice([cx - r, y - r * 2.2, cx + r, y + r * 0.2], 180, 360, fill=straw, outline=(140, 108, 50, 255), width=0.35)
    p.rectangle([cx - r, y - r * 1.0, cx + r, y], fill=straw, outline=(140, 108, 50, 255), width=0.35)
    for k in range(1, 5):
        yy = y - k * r * 0.42
        hw = r * min(1.0, math.sqrt(max(0.0, 1 - ((k * 0.42 - 1.0) / 1.15) ** 2))) if k * 0.42 > 1.0 else r
        p.line([(cx - hw + 0.3, yy), (cx + hw - 0.3, yy)], fill=(160, 124, 60, 255), width=0.35)
    p.pieslice([cx - 0.9, y - 1.6, cx + 0.9, y + 0.4], 180, 360, fill=(40, 30, 20, 255))
    p.disc(cx - r * 0.35, y - r * 1.4, r * 0.35, (240, 210, 140, 120))


def cog(g, cx, cy, r, teeth=10, col=(70, 72, 80)):
    p = g.p
    c = C(col)
    pts = []
    for k in range(teeth * 2):
        a0 = k * math.pi / teeth
        rr = r if k % 2 == 0 else r * 0.78
        for d in (-0.32, 0.32):
            a = a0 + d * math.pi / teeth
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    p.polygon(pts, fill=c, outline=sh(c, 0.45), width=0.4)
    p.disc(cx + 0.5, cy + 0.5, r * 0.6, sh(c, 1.25))
    p.disc(cx + 0.5, cy + 0.5, r * 0.45, c)
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        p.line([(cx, cy), (cx + math.cos(a) * r * 0.5, cy + math.sin(a) * r * 0.5)], fill=sh(c, 1.3), width=0.9)
    p.disc(cx + 0.5, cy + 0.5, 1.2, sh(c, 0.5))
    p.arc([cx - r + 0.6, cy - r + 0.6, cx + r - 0.6, cy + r - 0.6], 190, 260, fill=sh(c, 1.6), width=0.4)


def dome(g, cx, base, rx, ry, col, ribs=6, tex="tiles"):
    p = g.p
    c = C(col)
    pts = [(cx + rx * math.cos(math.radians(a)), base + ry * math.sin(math.radians(a))) for a in range(180, 361, 6)]
    p.polygon(pts, fill=c)
    sd = g._seed()
    if tex == "tiles":
        p.texfill(pts, lambda W, H, F: mt.BT.roof_tiles(W, H, F, tuple(col[:3]), sd))
    elif tex == "brick":
        g.surface(pts, "brick", col)
    elif tex == "stone":
        g.surface(pts, "stone", col)
    # light on the upper left, shadow on the right
    p.clipped(pts, lambda q: (q.disc(cx - rx * 0.35, base - ry * 0.6, rx * 0.75, (255, 255, 255, 46)),
                              q.ellipse([cx + rx * 0.2, base - ry * 1.2, cx + rx * 1.6, base + ry], fill=(0, 0, 0, 60))))
    for k in range(1, ribs):
        u = -1 + 2 * k / ribs
        p.line([(cx + rx * u, base), (cx + rx * u * 0.55, base - ry * 0.8), (cx, base - ry)], fill=sh(c, 0.7), width=0.4)
    p.polygon(pts, outline=sh(c, 0.45), width=0.5)


def cone(g, cx, base, r, h, col, mat="tiles"):
    p = g.p
    c = C(col)
    pts = [(cx - r, base), (cx, base - h), (cx + r, base)]
    p.polygon(pts, fill=c)
    sd = g._seed()
    if mat == "slate":
        p.texfill(pts, lambda W, H, F: mt.BT.slates(W, H, F, tuple(col[:3]), sd))
    elif mat == "thatch":
        p.texfill(pts, lambda W, H, F: mt.BT.thatch(W, H, F, tuple(col[:3]), sd))
    else:
        p.texfill(pts, lambda W, H, F: mt.BT.roof_tiles(W, H, F, tuple(col[:3]), sd))
    p.polygon([(cx, base - h), (cx + r, base), (cx + r * 0.25, base)], fill=(0, 0, 0, 70))
    p.polygon([(cx, base - h), (cx - r, base), (cx - r * 0.6, base)], fill=(255, 255, 255, 30))
    p.polygon(pts, outline=sh(c, 0.45), width=0.5)


def tall_stack(g, x, top, base, w=5, col=(128, 62, 46), square=False):
    """A tall factory chimney of brick, a little narrower at the top."""
    p = g.p
    t = 0.0 if square else 0.8
    body = [(x, base), (x + w, base), (x + w - t, top), (x + t, top)]
    p.polygon(body, fill=C(col))
    g.surface(body, "brick", col)
    p.polygon([(x + w * 0.62, base), (x + w, base), (x + w - t, top), (x + w * 0.62 - t * 0.4, top)], fill=(0, 0, 0, 55))
    p.polygon(body, outline=sh(C(col), 0.5), width=0.5)
    for yy in (top + 2, top + (base - top) * 0.45):
        p.rectangle([x - 0.4 + t * 0.4, yy, x + w + 0.4 - t * 0.4, yy + 1], fill=(56, 54, 56, 255))
    p.rectangle([x - 0.6 + t, top - 1.6, x + w + 0.6 - t, top], fill=(60, 56, 54, 255))
    p.shade(body, top, top + 6, (20, 18, 16, 160), (20, 18, 16, 0))
    _set("smoke", x + w / 2, top - 2)


def open_front(g, x0, x1, top, mat="planks", rh=10, posts=None):
    """An open shed: the side wall, a dark inside behind posts and a roof."""
    p, b = g.p, g.b
    g.walls(x0, x1, top, mat)
    inside = [(x0 + 1, b), (x1 - 1, b), (x1 - 1, top + 1.5), (x0 + 1, top + 1.5)]
    p.polygon(inside, fill=(46, 36, 26, 255))
    p.shade(inside, top, b, (20, 14, 10, 255), (70, 56, 40, 255))
    ridge = g.roof_gable(x0, x1, top, rh)
    for x in (posts or (x0, (x0 + x1) / 2, x1 - 1.6)):
        post = [(x, b), (x + 1.6, b), (x + 1.6, top + 1), (x, top + 1)]
        wood_fill(g, post, (118, 82, 48), 1.6, True, 0.35)
    return ridge


def body(g, x0, x1, h, mat="timber", rh=12, dx=7, dy=5, roof=None):
    top = g.b - h
    g.walls(x0, x1, top, mat, dx, dy)
    ridge = g.roof_gable(x0, x1, top, rh, dx, dy, mat=roof)
    return top, ridge


def storeys(g, x0, x1, h0, h1, mat="timber", rh=12, jetty=1.5, roof=None):
    """Two floors, the upper one jutting out a little over the street."""
    b = g.b
    top0 = b - h0
    g.walls(x0, x1, top0, mat)
    top1 = top0 - h1
    g.b = top0
    g.walls(x0 - jetty, x1 + jetty, top1, mat, grass=False)
    g.b = b
    # the jetty's shadow on the lower wall and the ends of the joists
    g.p.shade([(x0, top0), (x1, top0), (x1, top0 + 3), (x0, top0 + 3)], top0, top0 + 3, (0, 0, 0, 110), (0, 0, 0, 0))
    for k in range(int((x1 - x0) / 3) + 1):
        xx = x0 - jetty + 0.6 + k * 3
        if xx < x1 + jetty - 1:
            g.p.rectangle([xx, top0 - 0.2, xx + 1.2, top0 + 1.0], fill=(86, 60, 36, 255))
    ridge = g.roof_gable(x0 - jetty, x1 + jetty, top1, rh, mat=roof)
    return top0, top1, ridge


def bars(g, x, y, w=6, h=6):
    for k in range(1, 3):
        g.p.line([(x + w * k / 3 - 0.5, y - 0.3), (x + w * k / 3 - 0.5, y + h - 0.7)], fill=(40, 40, 44, 255), width=0.45)


def water(g, x0, x1, y0, y1):
    p = g.p
    pts = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    p.shade(pts, y0, y1, (88, 140, 178, 255), (52, 100, 142, 255))
    rnd = random.Random(int(x0 * 7 + y0))
    for k in range(int((x1 - x0) * (y1 - y0) / 30) + 2):
        x = rnd.uniform(x0 + 1, x1 - 4)
        y = rnd.uniform(y0 + 0.6, y1 - 0.6)
        p.line([(x, y), (x + rnd.uniform(1.5, 3.5), y)], fill=(170, 208, 230, 200), width=0.35)


def lantern(g, x, y):
    p = g.p
    p.line([(x, y), (x + 3, y)], fill=(40, 36, 32, 255), width=0.5)
    p.line([(x + 3, y), (x + 3, y + 1)], fill=(40, 36, 32, 255), width=0.3)
    p.rectangle([x + 2, y + 1, x + 4, y + 3.6], fill=(255, 210, 110, 255), outline=(40, 36, 32, 255), width=0.3)
    p.polygon([(x + 1.7, y + 1), (x + 3, y + 0.2), (x + 4.3, y + 1)], fill=(40, 36, 32, 255))


def heap(g, x0, x1, y, h, col, mat="rock", glints=None):
    """A heap of ore, sand, clay or coal."""
    p = g.p
    cx = (x0 + x1) / 2
    pts = [(x0, y)] + [(cx + (x1 - x0) / 2 * math.cos(math.radians(a)), y - h * math.sin(math.radians(a)) ** 0.8) for a in range(170, 9, -10)] + [(x1, y)]
    p.polygon(pts, fill=C(col))
    if mat:
        g.surface(pts, mat, col)
    p.clipped(pts, lambda q: q.ellipse([cx, y - h * 1.2, x1 + 3, y + 2], fill=(0, 0, 0, 60)))
    p.clipped(pts, lambda q: q.disc(cx - (x1 - x0) * 0.2, y - h * 0.7, h * 0.6, (255, 255, 255, 40)))
    if glints:
        rnd = random.Random(int(x0 * 3 + y))
        for k in range(int((x1 - x0) * h / 8)):
            gx = rnd.uniform(x0 + 1, x1 - 1)
            top = y - h * math.sin(math.acos(max(-1, min(1, (gx - cx) / ((x1 - x0) / 2))))) ** 0.8
            gy = rnd.uniform(top + 0.6, y - 0.4)
            p.disc(gx, gy, rnd.uniform(0.4, 0.75), C(glints))
    p.polygon(pts, outline=sh(C(col), 0.5), width=0.4)


def ladder(g, x0, y0, x1, y1):
    p = g.p
    c = (150, 112, 66, 255)
    p.line([(x0, y0), (x1, y1)], fill=c, width=0.6)
    p.line([(x0 + 2, y0), (x1 + 2, y1)], fill=c, width=0.6)
    n = int(abs(y0 - y1) / 2.2)
    for k in range(1, n):
        t = k / n
        p.line([(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t), (x0 + 2 + (x1 - x0) * t, y0 + (y1 - y0) * t)], fill=c, width=0.4)


def pennant(g, x, y0, y1, col=(200, 60, 50)):
    p = g.p
    p.line([(x, y0), (x, y1)], fill=(90, 66, 40, 255), width=0.7)
    p.polygon([(x + 0.4, y1), (x + 8, y1 + 2), (x + 0.4, y1 + 4)], fill=C(col), outline=sh(C(col), 0.5), width=0.3)


def wagon(g, x, y, load=None):
    """A two-wheeled cart seen from the side, shafts to the left; load: list of (kind, colour)."""
    p = g.p
    p.line([(x - 6, y - 7.5), (x + 1, y - 6.5)], fill=C(mt.WOOD), width=0.8)
    bed = [(x, y - 10), (x + 16, y - 10), (x + 16, y - 6), (x, y - 6)]
    wood_fill(g, bed, (150, 108, 62), 1.6, False, 0.4)
    if load:
        for k, (kind, col) in enumerate(load):
            if kind == "sack":
                sack(g, x + 1 + k * 4.5, y - 10, col)
            else:
                barrel(g, x + 1 + k * 5, y - 10, 4.4, 5, col)
    wheel(g, x + 8, y - 4.4, 4.4, (92, 62, 36))


# ------------------------------------------------------------------ workshops
def v_sawmill(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 24, 50, 18, "planks", 10)
    g.big_door(28, b - 13, 38, b)
    g.sign(39, top + 3, icon)
    # boards stacked to dry, a little gap between each layer
    for k in range(4):
        y = b - k * 1.8
        wood_fill(g, [(46, y), (62, y), (62, y - 1.4), (46, y - 1.4)], (206, 168, 112), 3, False, 0.3)
    # a trunk on two trestles under an upright frame saw, sawdust beneath
    p.ellipse([4, b - 2, 22, b + 1.5], fill=(232, 206, 150, 255))
    for tx in (5, 18):
        p.line([(tx - 2, b), (tx + 2, b - 8)], fill=C(mt.WOOD), width=0.9)
        p.line([(tx + 2, b), (tx - 2, b - 8)], fill=C(mt.WOOD), width=0.9)
    long_log(g, 2, 24, b - 10, 2.6)
    p.rectangle([10, b - 26, 15, b - 4], outline=C(sh(mt.WOOD, 1.1)), width=0.9)
    p.line([(12.5, b - 26), (12.5, b - 5)], fill=(200, 204, 212, 255), width=0.6)
    p.line([(9, b - 26.5), (16, b - 26.5)], fill=C(mt.WOOD), width=1.2)
    log_pile(g, 0, b, 2, 1.8)


def v_bakery(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 20, 50, 20, "timber", 12)
    g.door(30, 7, 11)
    g.window(23, top + 5, lit=True)
    g.sign(39, top + 3, icon)
    # a domed bread oven against the wall with its own little chimney and a glowing mouth
    p.rectangle([1, b - 4, 21, b], fill=(150, 146, 136, 255))
    g.surface([(1, b), (21, b), (21, b - 4), (1, b - 4)], "stone", (150, 146, 136))
    chim(g, 8, b - 24, b - 12)
    dome(g, 11, b - 4, 9.5, 10, (184, 104, 70), ribs=0, tex="brick")
    glow_hole(g, 8, b - 8, 14, b - 4)
    _set("glow", 11, b - 6)
    # loaves on a bench
    wood_fill(g, [(38, b - 4), (52, b - 4), (52, b - 2.8), (38, b - 2.8)], (140, 100, 60), 2, False, 0.3)
    for x in (38.5, 42.5, 46.5):
        p.line([(x + 0.6, b - 2.8), (x + 0.6, b)], fill=C(mt.WOOD), width=0.5)
    for k, x in enumerate((39, 42.8, 46.6, 49.6)):
        p.ellipse([x, b - 6.6, x + 3.4, b - 4], fill=(200, 140, 70, 255), outline=(130, 80, 36, 255), width=0.3)
        p.line([(x + 0.9, b - 5.6), (x + 2.4, b - 5.6)], fill=(240, 200, 130, 255), width=0.3)


def v_brewery(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 6, 40, 26, "timber", 12)
    # a louvred vent on the ridge lets the steam of the mash out
    vx = 20
    wood_fill(g, [(vx, ridge + 1), (vx + 7, ridge + 1), (vx + 7, ridge - 6), (vx, ridge - 6)], (150, 112, 70), 1.4, False, 0.4)
    for k in range(3):
        p.line([(vx + 0.5, ridge - 4.6 + k * 1.8), (vx + 6.5, ridge - 3.8 + k * 1.8)], fill=(50, 38, 26, 255), width=0.6)
    p.polygon([(vx - 1.5, ridge - 6), (vx + 3.5, ridge - 10), (vx + 8.5, ridge - 6)], fill=g.roof, outline=sh(g.roof, 0.5), width=0.4)
    _set("smoke", vx + 3.5, ridge - 10)
    g.big_door(10, b - 14, 22, b)
    g.window(30, top + 5, lit=True)
    g.window(10, top + 4)
    g.sign(25, top + 3, icon)
    # a copper on a fire, and barrels
    p.ellipse([47, b - 2, 61, b + 1], fill=(0, 0, 0, 70))
    p.rectangle([48, b - 3, 60, b], fill=(110, 106, 98, 255))
    g.surface([(48, b), (60, b), (60, b - 3), (48, b - 3)], "stone", (110, 106, 98))
    glow_hole(g, 52, b - 2.5, 56, b, arch=False)
    copper = (196, 112, 60, 255)
    pot = [(48, b - 3), (60, b - 3), (60, b - 11), (48, b - 11)]
    p.polygon(pot, fill=copper)
    p.shade(pot, b - 11, b - 3, (255, 210, 160, 80), (0, 0, 0, 60))
    p.polygon([(56, b - 3), (60, b - 3), (60, b - 11), (56, b - 11)], fill=(0, 0, 0, 50))
    p.pieslice([48, b - 17, 60, b - 6], 180, 360, fill=sh(copper, 1.1), outline=(110, 58, 30, 255), width=0.4)
    p.polygon(pot, outline=(110, 58, 30, 255), width=0.4)
    for yy in (b - 9, b - 5):
        p.line([(48, yy), (60, yy)], fill=(130, 70, 36, 255), width=0.5)
    p.line([(54, b - 17), (54, b - 20), (44, b - 20), (40, b - 18)], fill=(176, 100, 52, 255), width=1.0)
    p.arc([49, b - 16, 53, b - 12], 190, 260, fill=(255, 220, 180, 255), width=0.5)
    barrel(g, 25, b, 5, 6.5)
    barrel(g, 31, b, 5, 6.5, (140, 96, 54))
    barrel(g, 28, b - 6.5, 5, 6, (120, 80, 46))


def v_mint(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 14, 42, 26, "stone", 10, roof="slate")
    chim(g, 35, ridge - 3, top - 4)
    g.door(24, 8, 12, arch=True)
    for x in (17, 34):
        g.window(x, top + 14, 5, 6)
        bars(g, x, top + 14, 5, 6)
    g.sign(23, top + 1, icon)
    # an iron-bound strongbox and stacked coins
    chest = [(45, b), (57, b), (57, b - 6), (45, b - 6)]
    wood_fill(g, chest, (110, 70, 40), 1.6, False, 0.4)
    p.pieslice([45, b - 9, 57, b - 3], 180, 360, fill=(120, 78, 44, 255), outline=(60, 40, 22, 255), width=0.4)
    for x in (47, 54.5):
        p.rectangle([x, b - 8.6, x + 1, b], fill=(56, 56, 60, 255))
    p.rectangle([50, b - 5.5, 52, b - 3.5], fill=(212, 176, 70, 255))
    for k, (cx, n) in enumerate(((59.5, 4), (61.5, 2))):
        for j in range(n):
            p.ellipse([cx - 1.8, b - 1.4 - j * 1.1, cx + 1.8, b - 0.2 - j * 1.1], fill=(226, 190, 80, 255), outline=(150, 110, 30, 255), width=0.25)
    # torches by the door
    for x in (21, 33):
        p.line([(x, b - 13), (x, b - 9)], fill=(70, 50, 30, 255), width=0.7)
        p.disc(x, b - 13.6, 1.0, (255, 180, 70, 255))


def v_toolsmith(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 26, 52, 18, "timber", 10)
    g.door(30, 7, 10)
    g.window(45, top + 4, 5, 5)
    g.sign(38, top + 3, icon)
    # an open forge under a lean-to roof: a stone hearth with coals, its hood and chimney, an anvil
    hearth = [(4, b), (15, b), (15, b - 7), (4, b - 7)]
    stone_fill(g, hearth, (140, 134, 124))
    p.polygon(hearth, outline=(80, 76, 70, 255), width=0.4)
    p.rectangle([5, b - 8, 14, b - 7], fill=(255, 150, 60, 255))
    for k in range(5):
        p.disc(6 + k * 1.8, b - 8, 0.9, (255, 200, 90, 255) if k % 2 else (220, 80, 30, 255))
    _set("glow", 9.5, b - 8)
    p.polygon([(5, b - 14), (14, b - 14), (12, b - 9), (7, b - 9)], fill=(118, 112, 104, 255), outline=(70, 66, 60, 255), width=0.4)
    chim(g, 7.5, b - 34, b - 14)
    for x in (2, 17):
        wood_fill(g, [(x, b), (x + 1.4, b), (x + 1.4, b - 17), (x, b - 17)], (118, 82, 48), 1.4, True, 0.3)
    lean = [(0, b - 15), (26, b - 21), (26, b - 19), (0, b - 13)]
    p.polygon(lean, fill=g.roof)
    sd = g._seed()
    p.texfill(lean, lambda W, H, F: mt.BT.slates(W, H, F, tuple(g.roof[:3]), sd))
    p.polygon(lean, outline=sh(g.roof, 0.45), width=0.4)
    anvil(g, 17, b)
    # a grindstone in its frame
    p.line([(55, b), (58, b - 7)], fill=C(mt.WOOD), width=0.8)
    p.line([(61, b), (58, b - 7)], fill=C(mt.WOOD), width=0.8)
    p.disc(58, b - 6, 4.2, (156, 150, 136, 255))
    p.disc(57.6, b - 6.4, 3.2, (186, 180, 166, 255))
    p.disc(58, b - 6, 0.8, (60, 50, 40, 255))
    p.line([(58, b - 6), (61.5, b - 9)], fill=(60, 50, 40, 255), width=0.6)


def v_weaponsmith(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 6, 38, 22, "stone", 12)
    chim(g, 10, ridge - 10, top - 2)
    g.door(9, 8, 12, arch=True)
    glow_hole(g, 19.5, b - 9, 23.5, b - 3)
    _set("glow", 21.5, b - 6)
    g.sign(25, top + 3, icon)
    anvil(g, 27, b)
    # a rack of spears, swords and a shield
    for x in (46, 61):
        p.line([(x, b), (x, b - 18)], fill=C(mt.WOOD), width=1.0)
    p.line([(45, b - 16), (62, b - 16)], fill=C(mt.WOOD), width=1.0)
    p.line([(45, b - 5), (62, b - 5)], fill=C(mt.WOOD), width=0.8)
    for k in range(4):
        x = 48 + k * 3.2
        p.line([(x, b - 1), (x + 0.6, b - 23)], fill=(130, 96, 60, 255), width=0.5)
        p.polygon([(x + 0.1, b - 23), (x + 0.6, b - 26.5), (x + 1.2, b - 23)], fill=(200, 204, 214, 255), outline=(90, 92, 100, 255), width=0.2)
    for x in (57, 59.4):
        p.line([(x, b - 15.5), (x, b - 7)], fill=(210, 214, 222, 255), width=0.7)
        p.line([(x - 1.2, b - 14), (x + 1.2, b - 14)], fill=(150, 120, 60, 255), width=0.5)
    p.ellipse([39, b - 9, 46, b - 1], fill=(170, 50, 44, 255), outline=(80, 30, 26, 255), width=0.5)
    p.disc(42.5, b - 5, 1.3, (210, 200, 160, 255))
    p.line([(42.5, b - 8.5), (42.5, b - 1.5)], fill=(230, 210, 150, 255), width=0.5)


def v_bowyer(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 18, 42, 18, "planks", 12)
    g.door(21, 6, 10)
    g.sign(30, top + 3, icon)
    # an archery target of straw on its stand
    p.line([(4, b), (8, b - 18)], fill=C(mt.WOOD), width=0.8)
    p.line([(12, b), (8, b - 18)], fill=C(mt.WOOD), width=0.8)
    p.line([(10.5, b + 0.5), (8.5, b - 10)], fill=C(mt.WOOD), width=0.6)
    for r, c in ((6.4, (222, 196, 120)), (5.2, (240, 236, 224)), (3.8, (60, 90, 160)), (2.5, (200, 56, 48)), (1.2, (240, 200, 60))):
        p.disc(8, b - 12, r, C(c))
    p.ellipse([1.6, b - 18.4, 14.4, b - 5.6], outline=(160, 130, 70, 255), width=0.4)
    for ax, ay in ((7, b - 13), (9.6, b - 10.6)):
        p.line([(ax, ay), (ax - 2.8, ay - 1.6)], fill=(90, 66, 40, 255), width=0.4)
        p.line([(ax - 2.8, ay - 1.6), (ax - 3.6, ay - 2.4)], fill=(240, 240, 240, 255), width=0.6)
    # bow staves and finished bows leaning on the wall
    for k in range(3):
        x = 50 + k * 3.6
        p.arc([x - 2.5, b - 17, x + 1.5, b - 1], 270, 450, fill=(150, 104, 54, 255), width=0.8)
        p.line([(x - 0.5, b - 16.6), (x - 0.5, b - 1.4)], fill=(230, 226, 210, 255), width=0.25)
    for x in (44, 46):
        p.line([(x, b), (x + 1.6, b - 18)], fill=(176, 130, 76, 255), width=0.7)


def v_armorer(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 10, 42, 22, "stone", 12)
    chim(g, 34, ridge - 5, top - 4)
    g.door(14, 7, 11)
    g.window(34, top + 5, lit=True)
    g.sign(23, top + 3, icon)
    anvil(g, 25, b)
    # a suit of armour on its stand and a heater shield
    x = 54
    p.line([(x, b), (x, b - 22)], fill=C(mt.WOOD), width=1.0)
    p.line([(x - 4, b), (x + 4, b)], fill=C(mt.WOOD), width=1.0)
    steel = (176, 182, 194, 255)
    cuir = [(x - 4.4, b - 18), (x + 4.4, b - 18), (x + 3.6, b - 10), (x + 2.4, b - 8), (x - 2.4, b - 8), (x - 3.6, b - 10)]
    p.polygon(cuir, fill=steel, outline=(70, 74, 84, 255), width=0.4)
    p.shade(cuir, b - 18, b - 8, (255, 255, 255, 60), (0, 0, 0, 60))
    p.line([(x, b - 17.6), (x, b - 8.4)], fill=(230, 234, 240, 255), width=0.4)
    for sx in (x - 6.6, x + 4.2):
        p.ellipse([sx, b - 19, sx + 2.4, b - 15.4], fill=steel, outline=(70, 74, 84, 255), width=0.3)
    p.pieslice([x - 3, b - 24.5, x + 3, b - 18.5], 180, 360, fill=steel, outline=(70, 74, 84, 255), width=0.4)
    p.rectangle([x - 3, b - 21.6, x + 3, b - 19], fill=steel, outline=(70, 74, 84, 255), width=0.3)
    p.line([(x - 2.2, b - 20.6), (x + 2.2, b - 20.6)], fill=(30, 30, 34, 255), width=0.5)
    sh_ = [(44, b - 12), (50, b - 12), (50, b - 6), (47, b - 1.5), (44, b - 6)]
    p.polygon(sh_, fill=(60, 80, 150, 255), outline=(30, 36, 60, 255), width=0.4)
    p.line([(47, b - 11.4), (47, b - 2.4)], fill=(230, 200, 90, 255), width=0.6)
    p.line([(44.6, b - 8.5), (49.4, b - 8.5)], fill=(230, 200, 90, 255), width=0.6)


def v_tannery(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 26, 56, 16, "planks", 9)
    g.door(30, 6, 9)
    g.sign(41, top + 3, icon)
    # hides stretched on frames behind round tanning vats sunk in the ground
    hide(g, 2, b - 6, 10, 11, (190, 146, 98))
    hide(g, 13, b - 7, 9, 10, (150, 104, 66))
    for cx, cy, liq in ((7, b - 3, (112, 76, 40)), (19, b - 2, (96, 84, 50)), (13, b + 0.5, (130, 90, 50))):
        p.ellipse([cx - 5, cy - 2, cx + 5, cy + 2], fill=(110, 80, 48, 255), outline=(60, 42, 24, 255), width=0.4)
        p.ellipse([cx - 4, cy - 1.3, cx + 4, cy + 1.3], fill=C(liq))
        p.line([(cx - 2.5, cy - 0.4), (cx, cy - 0.4)], fill=(190, 160, 110, 160), width=0.3)


def v_weaver(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 24, 54, 22, "timber", 12)
    g.door(27, 7, 11)
    # a wide window with the loom's warp threads showing behind it
    wx, wy = 38, top + 4
    p.rectangle([wx - 1.2, wy - 1.2, wx + 12.2, wy + 9.2], fill=sh(g.wall, 0.5))
    p.rectangle([wx, wy, wx + 11, wy + 8], fill=(255, 214, 140, 255))
    for k in range(12):
        p.line([(wx + 0.5 + k * 0.9, wy), (wx + 0.5 + k * 0.9, wy + 8)], fill=(150, 80, 60, 255), width=0.25)
    p.rectangle([wx, wy + 5, wx + 11, wy + 8], fill=(80, 110, 170, 255))
    p.line([(wx - 1.6, wy + 9.4), (wx + 12.6, wy + 9.4)], fill=(150, 144, 132, 255), width=0.9)
    p.paste(icon, 40, b - 12, 8) if icon is not None else None
    # cloth hung up to dry after dyeing
    for x in (2, 21):
        p.line([(x, b), (x, b - 25)], fill=C(mt.WOOD), width=0.9)
    p.line([(1, b - 24), (22, b - 24)], fill=C(mt.WOOD), width=0.9)
    for k, col in enumerate(((70, 100, 170), (186, 60, 54), (214, 170, 60), (90, 140, 80))):
        cloth(g, 3.2 + k * 4.5, b - 24, 3.6, 13 + (k % 2) * 3, col)


def v_tailor(g, icon):
    p, b = g.p, g.b
    top0, top1, ridge = storeys(g, 20, 44, 14, 14, "timber", 12)
    g.door(22, 6, 10)
    # a shop window under a striped awning, a dress and a coat on show
    wx = 31
    p.rectangle([wx - 1, b - 11, wx + 10, b - 2], fill=sh(g.wall, 0.5))
    p.shade([(wx, b - 10), (wx + 9, b - 10), (wx + 9, b - 3), (wx, b - 3)], b - 10, b - 3, (255, 220, 150, 255), (220, 160, 90, 255))
    p.polygon([(wx + 2, b - 9), (wx + 3.4, b - 9), (wx + 4.4, b - 3.2), (wx + 1, b - 3.2)], fill=(140, 60, 130, 255))
    p.disc(wx + 2.7, b - 9.4, 0.8, (60, 40, 30, 255))
    p.rectangle([wx + 5.6, b - 9, wx + 8, b - 4], fill=(60, 90, 150, 255))
    p.rectangle([wx - 1.6, b - 2, wx + 10.6, b - 1], fill=(150, 144, 132, 255))
    awning(g, wx - 2, wx + 11, b - 15, (150, 70, 140, 255), 3.4)
    for x in (22, 37):
        g.window(x, top1 + 4, 5, 5)
    g.sign(28, top1 + 2, icon)
    # a washing line with shirts and a dress
    for x in (2, 17):
        p.line([(x, b), (x, b - 20)], fill=C(mt.WOOD), width=0.8)
    p.line([(2, b - 19), (9.5, b - 17.6), (17, b - 19)], fill=(220, 214, 196, 255), width=0.3)
    for x, col, kind in ((3.6, (236, 232, 220), "shirt"), (8.4, (150, 70, 140), "dress"), (12.6, (90, 120, 170), "shirt")):
        y = b - 18.4 + (0.9 if 6 < x < 12 else 0)
        if kind == "shirt":
            pts = [(x - 0.8, y + 1.6), (x, y), (x + 3.4, y), (x + 4.2, y + 1.6), (x + 3.4, y + 2.2), (x + 3.4, y + 5.6), (x, y + 5.6), (x, y + 2.2)]
        else:
            pts = [(x + 0.6, y), (x + 2.8, y), (x + 4.2, y + 7.4), (x - 0.8, y + 7.4)]
        p.polygon(pts, fill=C(col), outline=sh(C(col), 0.55), width=0.3)


def v_linen_weaver(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 28, 56, 18, "timber", 12)
    g.door(46, 7, 10)
    g.window(31, top + 4)
    g.sign(36, top + 3, icon)
    # lengths of linen laid out on the grass to bleach in the sun, and stooks of flax
    for k in range(3):
        y = b - 1 - k * 3.2
        x = 1 + k * 2.4
        pts = [(x, y), (x + 22, y), (x + 23.4, y - 2.2), (x + 1.4, y - 2.2)]
        p.polygon(pts, fill=(246, 244, 232, 255), outline=(190, 186, 170, 255), width=0.3)
        p.line([(x + 1, y - 0.6), (x + 22.4, y - 0.6)], fill=(222, 218, 200, 255), width=0.3)
    for x in (6, 13, 20):
        p.polygon([(x - 2.4, b - 10), (x, b - 19), (x + 2.4, b - 10)], fill=(200, 176, 110, 255), outline=(140, 116, 60, 255), width=0.3)
        p.line([(x - 2, b - 13), (x + 2, b - 13)], fill=(140, 116, 60, 255), width=0.4)
        for k in range(3):
            p.line([(x - 1 + k, b - 18.5), (x - 1.5 + k * 1.5, b - 21)], fill=(110, 130, 180, 255), width=0.3)


def v_furrier(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 16, 42, 18, "planks", 15, roof="thatch")
    g.door(20, 7, 10)
    g.sign(30, top + 3, icon)
    # antlers over the gable
    ax, ay = 45.5, ridge + 3
    for s in (-1, 1):
        p.line([(ax, ay), (ax + s * 3, ay - 3), (ax + s * 4.6, ay - 6.4)], fill=(230, 220, 196, 255), width=0.6)
        p.line([(ax + s * 3, ay - 3), (ax + s * 4.8, ay - 3.4)], fill=(230, 220, 196, 255), width=0.5)
        p.line([(ax + s * 3.8, ay - 4.8), (ax + s * 3.4, ay - 7)], fill=(230, 220, 196, 255), width=0.5)
    # pelts hung on a rail: fox, ermine, wolf, bear
    p.line([(50, b), (50, b - 22)], fill=C(mt.WOOD), width=0.9)
    p.line([(63, b), (63, b - 22)], fill=C(mt.WOOD), width=0.9)
    p.line([(49, b - 21), (63.5, b - 21)], fill=C(mt.WOOD), width=0.9)
    for k, (col, ln) in enumerate((((196, 104, 50), 13), ((240, 236, 226), 9), ((126, 120, 112), 14), ((90, 62, 40), 11))):
        x = 50.6 + k * 3.1
        pts = [(x, b - 21), (x + 2.8, b - 21), (x + 3.0, b - 21 + ln * 0.7), (x + 1.8, b - 21 + ln), (x + 1.0, b - 21 + ln), (x - 0.2, b - 21 + ln * 0.7)]
        p.polygon(pts, fill=C(col), outline=sh(C(col), 0.5), width=0.3)
        p.line([(x + 1.4, b - 20), (x + 1.4, b - 21 + ln - 1)], fill=sh(C(col), 1.2), width=0.4)
    p.disc(51.8, b - 21 + 13, 0.6, (250, 250, 250, 255))
    p.disc(55.1, b - 21 + 9, 0.6, (30, 30, 30, 255))


def v_jeweller(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 18, 44, 28, "stone", 10, roof="slate")
    g.door(20, 7, 12)
    # a glazed shop window with gems and rings on velvet, a gold awning
    wx = 30
    p.rectangle([wx - 1.2, b - 12.2, wx + 12.2, b - 2], fill=(150, 120, 50, 255))
    p.rectangle([wx, b - 11, wx + 11, b - 3.4], fill=(70, 30, 60, 255))
    for k, col in enumerate(((220, 50, 60), (60, 160, 220), (60, 190, 110), (240, 210, 80), (200, 120, 230))):
        p.disc(wx + 1.6 + k * 2.1, b - 5.4 - (k % 2) * 2.4, 0.8, C(col))
        p.point((wx + 1.4 + k * 2.1, b - 5.8 - (k % 2) * 2.4), fill=(255, 255, 255, 255))
    p.arc([wx + 2, b - 10.6, wx + 4.4, b - 8.2], 0, 360, fill=(240, 210, 90, 255), width=0.4)
    p.arc([wx + 6.6, b - 10.6, wx + 9, b - 8.2], 0, 360, fill=(220, 220, 230, 255), width=0.4)
    p.polygon([(wx, b - 11), (wx + 4, b - 11), (wx, b - 7)], fill=(255, 255, 255, 50))
    awning(g, wx - 2, wx + 12, b - 16, (200, 160, 50, 255), 3.4)
    g.window(21, top + 6, 5, 7)
    g.window(36, top + 6, 5, 7)
    g.sign(26, top + 3, icon)
    lantern(g, 44, b - 18)


def v_carpenter(g, icon):
    p, b = g.p, g.b
    ridge = open_front(g, 28, 56, b - 18, "planks", 10)
    # inside: a workbench with tools on the back wall
    p.rectangle([31, b - 7, 44, b - 6], fill=(150, 110, 66, 255))
    for x in (32, 43):
        p.line([(x, b - 6), (x, b)], fill=(110, 80, 50, 255), width=0.6)
    for x, kind in ((46, "saw"), (49, "axe"), (52, "plane")):
        p.line([(x, b - 15), (x, b - 10)], fill=(170, 170, 176, 255), width=0.6)
    p.paste(icon, 33, b - 16, 8) if icon is not None else None
    # boards stacked on bearers, a sawhorse with a board on it, a finished chair
    for k in range(5):
        y = b - 1 - k * 1.6
        wood_fill(g, [(1 + k * 0.4, y), (21 - k * 0.4, y), (21 - k * 0.4, y - 1.3), (1 + k * 0.4, y - 1.3)], (196 - k * 6, 156 - k * 6, 100), 3, False, 0.3)
    for tx in (10, 18):
        p.line([(tx - 1.6, b), (tx + 1.6, b - 6)], fill=C(mt.WOOD), width=0.7)
        p.line([(tx + 1.6, b), (tx - 1.6, b - 6)], fill=C(mt.WOOD), width=0.7)
    wood_fill(g, [(4, b - 10), (26, b - 6.6), (26, b - 5.4), (4, b - 8.8)], (210, 170, 110), 3, False, 0.3)
    cx = 22
    p.rectangle([cx, b - 4.2, cx + 4, b - 3.4], fill=(150, 104, 60, 255))
    for x in (cx + 0.3, cx + 3.4):
        p.line([(x, b - 3.4), (x, b)], fill=(120, 84, 50, 255), width=0.5)
    p.line([(cx + 3.6, b - 3.6), (cx + 3.6, b - 9)], fill=(120, 84, 50, 255), width=0.6)
    p.line([(cx + 3.6, b - 8), (cx + 3.6, b - 5.4)], fill=(150, 104, 60, 255), width=1.2)


def v_apothecary(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 18, 42, 26, "timber", 12)
    g.door(21, 7, 11)
    # bunches of herbs drying under the eaves
    for k in range(6):
        x = 19.5 + k * 3.8
        p.line([(x, top + 2), (x, top + 3.4)], fill=(80, 60, 40, 255), width=0.3)
        p.polygon([(x - 1.1, top + 3.4), (x + 1.1, top + 3.4), (x + 0.4, top + 7), (x - 0.4, top + 7)], fill=C(((90, 140, 70), (120, 150, 80), (150, 110, 170))[k % 3]))
    g.sign(30, top + 9, icon)
    # a window of coloured bottles
    wx, wy = 32, b - 9
    p.rectangle([wx - 1, wy - 1, wx + 8, wy + 6], fill=sh(g.wall, 0.5))
    p.rectangle([wx, wy, wx + 7, wy + 5], fill=(250, 226, 170, 255))
    p.line([(wx, wy + 2.6), (wx + 7, wy + 2.6)], fill=(120, 90, 60, 255), width=0.4)
    for k, col in enumerate(((60, 150, 90), (70, 110, 200), (200, 120, 50), (160, 60, 90))):
        x = wx + 0.8 + k * 1.6
        p.rectangle([x, wy + 0.6, x + 1, wy + 2.4], fill=C(col))
        p.rectangle([x + 0.2, wy + 3.2, x + 1.0, wy + 4.8], fill=C(((200, 120, 50), (60, 150, 90), (160, 60, 90), (70, 110, 200))[k]))
    # pots of herbs, a mortar and pestle
    for k, x in enumerate((3, 9, 15)):
        p.polygon([(x, b - 4), (x + 4, b - 4), (x + 3.4, b), (x + 0.6, b)], fill=(180, 96, 60, 255), outline=(110, 56, 32, 255), width=0.3)
        for j in range(5):
            p.disc(x + 0.6 + j * 0.7, b - 5 - (j % 2) * 1.6 - (k == 1) * 1.4, 1.1, C(((80, 140, 60), (150, 110, 180), (110, 150, 70))[k]))
    p.pieslice([44, b - 6, 52, b + 1], 0, 180, fill=(170, 166, 156, 255), outline=(100, 96, 90, 255), width=0.4)
    p.line([(49, b - 3), (52, b - 8)], fill=(150, 146, 136, 255), width=1.0)


def v_bathhouse(g, icon):
    p, b = g.p, g.b
    top = b - 16
    g.walls(8, 46, top, "stone")
    deck = [(8, top), (46, top), (53, top - 5), (15, top - 5)]
    stone_fill(g, deck, g.wall, "stone", 0.62)
    dome(g, 30, top - 2, 14, 15, (120, 150, 160), ribs=8)
    p.rectangle([28, top - 19.5, 32, top - 16.5], fill=(90, 110, 116, 255))
    _set("smoke", 30, top - 20)
    g.door(23, 8, 11, arch=True)
    for x in (12, 38):
        g.window(x, top + 4, 4, 6)
    g.sign(32, top + 2, icon)
    # a stone basin of warm water in front
    p.ellipse([44, b - 7, 63, b + 1], fill=(160, 156, 146, 255), outline=(96, 92, 84, 255), width=0.5)
    p.ellipse([46, b - 5.8, 61, b - 0.2], fill=(90, 160, 196, 255))
    p.arc([48, b - 5, 56, b - 2], 200, 300, fill=(200, 236, 250, 255), width=0.4)


def v_tavern(g, icon):
    p, b = g.p, g.b
    top0, top1, ridge = storeys(g, 6, 46, 14, 15, "timber", 12)
    chim(g, 10, ridge - 3, top1 - 3)
    g.chimney(38, ridge - 4, top1 - 3)
    g.door(22, 8, 11)
    for x in (9, 34, 40):
        g.window(x, b - 11, 5, 5, lit=True)
    for x in (8, 18, 28, 38):
        g.window(x, top1 + 4, 5, 6, lit=x % 20 == 18)
    # a tankard sign on an iron bracket
    p.line([(46, top1 + 4), (58, top1 + 4)], fill=(40, 36, 32, 255), width=0.7)
    p.line([(46, top1 + 8), (52, top1 + 4)], fill=(40, 36, 32, 255), width=0.5)
    g.sign(49, top1 + 6, icon)
    # a bench and a barrel table
    wood_fill(g, [(8, b - 3.4), (20, b - 3.4), (20, b - 2.4), (8, b - 2.4)], (140, 100, 60), 2, False, 0.3)
    for x in (9, 18.5):
        p.line([(x, b - 2.4), (x, b)], fill=C(mt.WOOD), width=0.6)
    barrel(g, 52, b, 5, 6)
    p.rectangle([51, b - 7, 58, b - 6], fill=(150, 108, 62, 255))
    p.rectangle([53.2, b - 9, 54.8, b - 7], fill=(220, 200, 150, 255))


def v_fire_station(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 24, 50, 16, "timber", 10)
    g.big_door(28, b - 12, 40, b, (150, 50, 40))
    # a wooden watch tower with the alarm bell
    for x0, x1 in ((4, 7), (18, 15)):
        p.line([(x0, b), (x1, b - 36)], fill=C(sh(mt.WOOD, 1.05)), width=1.1)
    for y0, y1 in ((b - 2, b - 14), (b - 14, b - 26), (b - 26, b - 35)):
        p.line([(4 + (b - y0) / 12, y0), (18 - (b - y1) / 12, y1)], fill=C(mt.WOOD), width=0.5)
        p.line([(18 - (b - y0) / 12, y0), (4 + (b - y1) / 12, y1)], fill=C(mt.WOOD), width=0.5)
    wood_fill(g, [(5, b - 36), (17, b - 36), (17, b - 34), (5, b - 34)], (130, 92, 54), 2, False, 0.3)
    for x in (6, 15):
        p.line([(x, b - 36), (x, b - 43)], fill=C(mt.WOOD), width=0.7)
    p.pieslice([8.6, b - 43, 13.4, b - 37], 180, 360, fill=(212, 170, 70, 255), outline=(120, 90, 30, 255), width=0.3)
    p.rectangle([8.6, b - 40, 13.4, b - 38], fill=(212, 170, 70, 255))
    p.polygon([(3.5, b - 42.5), (11, b - 49), (18.5, b - 42.5)], fill=g.roof, outline=sh(g.roof, 0.5), width=0.4)
    g.sign(6, b - 20, icon)
    ladder(g, 44, b, 47, b - 18)
    # water barrels and leather buckets
    barrel(g, 52, b, 5, 6.5, (110, 76, 46))
    barrel(g, 57.6, b, 5, 6.5, (110, 76, 46))
    for x in (52.4, 58):
        p.ellipse([x, b - 7.2, x + 4.2, b - 6.0], fill=(80, 130, 180, 255))
    for x in (42, 45.5):
        p.polygon([(x, b - 3), (x + 2.6, b - 3), (x + 2.2, b), (x + 0.4, b)], fill=(120, 70, 40, 255), outline=(60, 36, 20, 255), width=0.3)


def v_machine_works(g, icon):
    p, b = g.p, g.b
    top = b - 22
    g.walls(4, 46, top, "brick")
    # a saw-tooth roof of glass and slate
    for k in range(3):
        x0 = 4 + k * 14
        tooth = [(x0, top), (x0 + 14, top), (x0 + 14, top - 7)]
        p.polygon(tooth, fill=g.roof)
        sd = g._seed()
        p.texfill(tooth, lambda W, H, F, sd=sd: mt.BT.slates(W, H, F, tuple(g.roof[:3]), sd))
        p.polygon([(x0 + 12.6, top - 6), (x0 + 14, top - 7), (x0 + 14, top), (x0 + 12.6, top)], fill=(150, 190, 210, 255))
        p.polygon(tooth, outline=sh(g.roof, 0.45), width=0.4)
    p.polygon([(46, top), (53, top - 5), (53, top - 12), (46, top - 7)], fill=sh(g.wall, 0.6))
    tall_stack(g, 54, b - 54, b - 4, 5)
    for x in (24, 31, 38):
        g.window(x, top + 4, 5, 6)
    g.big_door(26, b - 12, 40, b, (70, 74, 80))
    cog(g, 14, b - 12, 7.5, 12)
    cog(g, 21.6, b - 18.4, 3.6, 8, (120, 90, 50))
    # rails and an iron casting on a trolley
    p.line([(0, b + 0.6), (64, b + 0.6)], fill=(70, 70, 74, 255), width=0.6)
    p.rectangle([46, b - 3, 54, b - 1], fill=(80, 64, 46, 255))
    p.disc(48, b - 0.6, 1.1, (40, 40, 44, 255)); p.disc(52.4, b - 0.6, 1.1, (40, 40, 44, 255))
    p.rectangle([47.4, b - 6.6, 52.6, b - 3], fill=(60, 64, 72, 255), outline=(30, 30, 34, 255), width=0.3)


def v_textile_mill(g, icon):
    p, b = g.p, g.b
    top = b - 34
    g.walls(4, 44, top, "brick")
    g.roof_gable(4, 44, top, 6)
    for r in range(3):
        for k in range(5):
            x = 6.5 + k * 7.6
            if r == 2 and k == 2:
                continue
            g.window(x, top + 4 + r * 10, 4.4, 6, lit=(r + k) % 4 == 0)
    g.big_door(20, b - 9, 28, b, (90, 70, 60))
    # a bell cote on the roof, a stack at the end
    p.rectangle([22, top - 13, 26, top - 6], fill=sh(g.wall, 1.05), outline=sh(g.wall, 0.45), width=0.4)
    p.rectangle([23, top - 12, 25, top - 9], fill=(40, 34, 30, 255))
    p.disc(24, top - 10, 0.9, (220, 180, 70, 255))
    p.polygon([(21.4, top - 13), (24, top - 17), (26.6, top - 13)], fill=g.roof)
    tall_stack(g, 54, b - 56, b - 2, 6, square=True)
    # bolts of cloth waiting for the carts
    for k, col in enumerate(((170, 60, 60), (70, 100, 170), (220, 200, 120), (90, 140, 90))):
        x = 47 + (k % 2) * 7
        y = b - (k // 2) * 3.6
        p.ellipse([x, y - 3.4, x + 2.4, y], fill=sh(C(col), 0.7))
        p.rectangle([x + 1.2, y - 3.4, x + 6.4, y], fill=C(col))
        p.ellipse([x + 5.2, y - 3.4, x + 7.6, y], fill=sh(C(col), 1.2), outline=sh(C(col), 0.5), width=0.3)


def v_warehouse(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 6, 46, 28, "planks", 14)
    g.big_door(18, b - 15, 34, b, (110, 80, 50))
    g.big_door(23, top + 3, 29, top + 11, (110, 80, 50))
    # a hoist beam out of the gable with a crate on its rope
    hy = ridge + 4
    p.line([(48, hy), (62, hy)], fill=C(sh(mt.WOOD, 1.05)), width=1.4)
    p.line([(56, hy - 4), (60, hy)], fill=C(mt.WOOD), width=0.5)
    p.disc(60.5, hy + 1.3, 1.0, (60, 50, 40, 255))
    p.line([(60.5, hy + 1.3), (60.5, b - 30)], fill=(210, 196, 160, 255), width=0.4)
    crate(g, 57.6, b - 24, 5)
    for x in (2, 9):
        crate(g, x, b, 5.6, (170, 132, 80))
    crate(g, 5, b - 6, 5.6, (150, 114, 70))
    sack(g, 36, b)
    sack(g, 41, b, (200, 180, 136))
    sack(g, 38.4, b - 4.8, (220, 204, 160))


def v_cart_yard(g, icon):
    p, b = g.p, g.b
    ridge = open_front(g, 30, 58, b - 16, "planks", 9)
    p.paste(icon, 38, b - 12, 8) if icon is not None else None
    # a cart in the yard and spare wheels against the posts
    wagon(g, 8, b, [("sack", (214, 196, 150)), ("sack", (200, 180, 136)), ("sack", (220, 204, 160))])
    for x in (28, 31):
        p.ellipse([x - 1.6, b - 9, x + 1.6, b], outline=(92, 62, 36, 255), width=0.8)
        p.line([(x, b - 9), (x, b)], fill=(92, 62, 36, 255), width=0.4)
    for k in range(3):
        p.line([(48 + k * 1.2, b), (49.5 + k * 1.2, b - 12)], fill=(160, 120, 70, 255), width=0.6)


def v_cheesery(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 20, 50, 20, "timber", 12)
    g.door(24, 7, 11)
    g.window(41, top + 5)
    g.sign(32, top + 3, icon)
    # cheese wheels on shelves and milk churns
    for y in (b, b - 7, b - 14):
        wood_fill(g, [(1, y - 0.2), (18, y - 0.2), (18, y - 1.2), (1, y - 1.2)], (140, 100, 60), 2, False, 0.3)
    for x in (1.4, 17):
        p.line([(x, b), (x, b - 16)], fill=C(mt.WOOD), width=0.7)
    for row, y in enumerate((b - 1.2, b - 8.2)):
        for k in range(3 - row):
            x = 2.6 + k * 5 + row * 2.4
            yc = (226, 180, 70, 255)
            p.rectangle([x, y - 2.8, x + 4.4, y - 0.8], fill=sh(yc, 0.86))
            p.ellipse([x, y - 3.8, x + 4.4, y - 1.8], fill=yc, outline=sh(yc, 0.6), width=0.3)
            p.ellipse([x, y - 1.6, x + 4.4, y], fill=sh(yc, 0.7))
    for k, x in enumerate((53, 57.6)):
        churn = [(x, b), (x + 3.6, b), (x + 3.6, b - 5), (x + 2.8, b - 6.4), (x + 2.8, b - 7.6), (x + 0.8, b - 7.6), (x + 0.8, b - 6.4), (x, b - 5)]
        p.polygon(churn, fill=(196, 200, 206, 255), outline=(100, 104, 110, 255), width=0.3)
        p.line([(x + 1, b - 4.6), (x + 1, b - 0.6)], fill=(240, 244, 248, 255), width=0.4)
        p.rectangle([x + 0.4, b - 8.4, x + 3.2, b - 7.6], fill=(150, 154, 160, 255))


def v_butcher(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 10, 46, 24, "timber", 12)
    g.door(12, 7, 11)
    g.sign(11, top + 1, icon)
    # a stall under a red-and-white awning: hams and sausages hanging, a block and a cleaver
    sx = 22
    p.rectangle([sx, b - 14, sx + 20, b], fill=(60, 44, 30, 255))
    p.shade([(sx, b - 14), (sx + 20, b - 14), (sx + 20, b), (sx, b)], b - 14, b, (30, 20, 14, 255), (80, 60, 40, 255))
    p.line([(sx + 1, b - 12.6), (sx + 19, b - 12.6)], fill=(100, 96, 90, 255), width=0.4)
    for k in range(4):
        x = sx + 2 + k * 4.6
        p.line([(x + 1, b - 12.6), (x + 1, b - 11.6)], fill=(80, 70, 60, 255), width=0.3)
        p.polygon([(x, b - 11.6), (x + 2.2, b - 11.6), (x + 2.8, b - 7.6), (x + 1.2, b - 6.4), (x - 0.4, b - 7.8)], fill=(176, 84, 64, 255), outline=(110, 46, 34, 255), width=0.3)
        p.line([(x + 0.8, b - 11), (x + 1.4, b - 8)], fill=(232, 200, 180, 255), width=0.4)
    for k in range(5):
        p.line([(sx + 3 + k * 1.2, b - 12.6), (sx + 3.4 + k * 1.2, b - 9.6 + (k % 2))], fill=(150, 60, 50, 255), width=0.7)
    wood_fill(g, [(sx - 0.5, b - 4.6), (sx + 20.5, b - 4.6), (sx + 20.5, b), (sx - 0.5, b)], (150, 110, 70), 2, False, 0.4)
    p.rectangle([sx, b - 5.6, sx + 20, b - 4.6], fill=(220, 214, 200, 255))
    awning(g, sx - 1.6, sx + 21.6, b - 18, (190, 50, 44, 255), 3.6)
    p.ellipse([51, b - 6, 59, b - 3.6], fill=(170, 130, 86, 255), outline=(90, 64, 40, 255), width=0.3)
    wood_fill(g, [(51, b - 4.8), (59, b - 4.8), (59, b), (51, b)], (130, 92, 56), 1.4, True, 0.3)
    p.polygon([(54, b - 5.4), (56.6, b - 9.2), (58.6, b - 8.4), (56.6, b - 5.2)], fill=(200, 204, 212, 255), outline=(80, 82, 90, 255), width=0.3)
    p.line([(57.6, b - 8.8), (59.4, b - 11)], fill=(80, 56, 34, 255), width=0.7)


def v_winery(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 24, 56, 18, "stone", 10)
    # the cellar door, barrels inside
    x0, x1 = 28, 38
    p.rectangle([x0 - 1, b - 9, x1 + 1, b], fill=sh(g.wall, 0.45))
    p.pieslice([x0 - 1, b - 15, x1 + 1, b - 3], 180, 360, fill=sh(g.wall, 0.45))
    p.rectangle([x0, b - 9, x1, b], fill=(30, 22, 16, 255))
    p.pieslice([x0, b - 14, x1, b - 4], 180, 360, fill=(30, 22, 16, 255))
    barrel_end(g, 31, b - 2.8, 2.6)
    barrel_end(g, 35.6, b - 2.8, 2.6)
    barrel_end(g, 33.3, b - 7.2, 2.6)
    g.sign(41, top + 3, icon)
    # a wine press and baskets of grapes
    p.ellipse([2, b - 3, 18, b + 1.2], fill=(120, 84, 50, 255), outline=(60, 40, 22, 255), width=0.4)
    wood_fill(g, [(4, b - 1), (16, b - 1), (16, b - 7), (4, b - 7)], (140, 98, 58), 1.4, True, 0.4)
    for y in (b - 2.4, b - 6):
        p.line([(4, y), (16, y)], fill=(60, 56, 52, 255), width=0.5)
    for x in (3, 16):
        wood_fill(g, [(x, b), (x + 1.6, b), (x + 1.6, b - 18), (x, b - 18)], (118, 82, 48), 1.4, True, 0.3)
    wood_fill(g, [(2, b - 18), (19, b - 18), (19, b - 15.6), (2, b - 15.6)], (118, 82, 48), 2, False, 0.3)
    p.line([(10, b - 15.6), (10, b - 7.4)], fill=(80, 76, 72, 255), width=1.4)
    for k in range(5):
        p.line([(9, b - 14.6 + k * 1.5), (11, b - 13.8 + k * 1.5)], fill=(150, 150, 156, 255), width=0.35)
    p.line([(4, b - 11.6), (16, b - 12.4)], fill=(150, 108, 62, 255), width=0.8)
    for x in (19, 44):
        p.polygon([(x, b - 4.4), (x + 6, b - 4.4), (x + 5.2, b), (x + 0.8, b)], fill=(190, 150, 90, 255), outline=(120, 90, 50, 255), width=0.3)
        for k in range(6):
            p.disc(x + 1 + (k % 3) * 1.8, b - 4.6 - (k // 3) * 1.2, 0.9, (110, 50, 120, 255))
    barrel(g, 51, b, 5, 6.2)
    barrel(g, 57, b, 5, 6.2, (120, 80, 46))


def v_chandler(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 22, 50, 22, "timber", 12)
    g.door(26, 7, 11)
    g.window(43, top + 5, 5, 6, lit=True)
    g.sign(33, top + 3, icon)
    lantern(g, 22, b - 15)
    # candles hung in pairs on a rack to cool, a pot of tallow on a fire
    for x in (2, 19):
        p.line([(x, b), (x, b - 20)], fill=C(mt.WOOD), width=0.8)
    for y in (b - 19, b - 11):
        p.line([(1.4, y), (19.6, y)], fill=C(mt.WOOD), width=0.8)
        for k in range(7):
            x = 3.6 + k * 2.3
            p.line([(x, y), (x, y + 0.8)], fill=(60, 50, 40, 255), width=0.25)
            for d in (-0.5, 0.5):
                p.line([(x + d, y + 0.8), (x + d, y + 6.4 - (k % 2))], fill=(244, 236, 206, 255), width=0.5)
    p.rectangle([4, b - 3, 14, b], fill=(110, 106, 98, 255))
    glow_hole(g, 7, b - 2.4, 11, b, arch=False)
    p.pieslice([5, b - 7, 13, b + 0], 0, 180, fill=(50, 48, 50, 255))
    p.ellipse([5, b - 4.4, 13, b - 2.6], fill=(236, 226, 190, 255), outline=(40, 40, 44, 255), width=0.3)


def v_shipyard(g, icon):
    p, b = g.p, g.b
    water(g, 40, 64, b - 5, b + 3)
    # the slipway running down into the water, on piles
    for x in (8, 20, 32, 44):
        p.rectangle([x, b - 3, x + 1.4, b + 1], fill=(90, 64, 40, 255))
    wood_fill(g, [(2, b - 4), (48, b - 4), (54, b - 1), (2, b - 1)], (140, 104, 64), 2.4, False, 0.4)
    # a hull on the stocks: planked aft, bare frames forward
    hull = [(8, b - 22), (50, b - 25), (52, b - 23), (48, b - 15), (40, b - 10), (16, b - 10), (9, b - 15)]
    for x in (14, 24, 34):
        p.rectangle([x, b - 11, x + 1.4, b - 4], fill=(100, 72, 44, 255))
    p.polygon(hull, fill=(0, 0, 0, 0))
    plank = [q for q in hull]
    p.clipped(hull, lambda q: q.rectangle([0, 0, 36, 64], fill=(150, 106, 62, 255)))
    sd = g._seed()
    p.clipped(hull, lambda q: q.texfill([(0, 0), (36, 0), (36, 64), (0, 64)], lambda W, H, F: mt.BT.wood(W, H, F, (150, 106, 62), sd, board=1.6, vertical=False, gap=0.2)))
    for k in range(6):
        x = 37 + k * 2.6
        y_top = b - 22 - (x - 8) * 3 / 42
        y_bot = b - 10 - max(0, x - 40) * 0.6
        p.line([(x, y_top), (x - 0.4, (y_top + y_bot) / 2), (x - 1.4, y_bot)], fill=(176, 128, 74, 255), width=0.8)
    p.line([(16, b - 10), (40, b - 10), (48, b - 15), (52, b - 23)], fill=(110, 76, 44, 255), width=1.0)
    p.line([(8, b - 22), (50, b - 25)], fill=(120, 84, 48, 255), width=1.0)
    p.line([(8, b - 22), (9, b - 15), (16, b - 10)], fill=(110, 76, 44, 255), width=0.9)
    p.line([(10, b - 18), (36, b - 19.6)], fill=(96, 66, 38, 255), width=0.5)
    p.line([(52, b - 23), (54, b - 28)], fill=(120, 84, 48, 255), width=1.0)
    # shear legs to lift the timbers, a pile of them waiting
    p.line([(18, b - 4), (28, b - 44)], fill=C(mt.WOOD), width=1.0)
    p.line([(38, b - 4), (28, b - 44)], fill=C(mt.WOOD), width=1.0)
    p.line([(28, b - 43), (28, b - 32)], fill=(210, 196, 160, 255), width=0.4)
    long_log(g, 22, 34, b - 31, 1.3, (170, 124, 72))
    for k in range(3):
        long_log(g, 0 + k * 0.6, 12 - k * 0.6, b + 1 - k * 2.4, 1.2, (150, 108, 64))


# ------------------------------------------------------------------ barns and farms
def barn_body(g, x0, x1, h, rh=14, mat="planks", doors=True):
    p, b = g.p, g.b
    top, ridge = body(g, x0, x1, h, mat, rh, roof="thatch" if g.cat in mt.THATCH else None)
    if doors:
        cx = (x0 + x1) / 2
        g.big_door(cx - 6, b - 14, cx + 6, b, (128, 52, 40), split=False)
        p.line([(cx - 6, b - 14), (cx + 6, b)], fill=(230, 220, 200, 255), width=0.7)
        p.line([(cx + 6, b - 14), (cx - 6, b)], fill=(230, 220, 200, 255), width=0.7)
        p.line([(cx, b - 14), (cx, b)], fill=mt.DARK, width=0.6)
    return top, ridge


def v_orchard(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 36, 56, 16, "planks", 10, roof="thatch")
    g.door(40, 6, 10)
    g.sign(47, top + 2, icon)
    tree(g, 22, b - 4, 8.0, (210, 50, 40), 9)
    tree(g, 8, b, 7.0, (230, 120, 40), 8)
    tree(g, 28, b + 1, 6.0, (210, 50, 40), 7)
    ladder(g, 14, b, 16.4, b - 16)
    for x in (32, 37):
        p.polygon([(x, b - 3.6), (x + 4.4, b - 3.6), (x + 3.8, b), (x + 0.6, b)], fill=(180, 140, 80, 255), outline=(110, 80, 40, 255), width=0.3)
        for k in range(4):
            p.disc(x + 0.9 + (k % 3) * 1.3, b - 3.8 - (k // 3) * 1.0, 0.8, (210, 50, 40, 255) if x == 32 else (230, 120, 40, 255))


def v_hop_farm(g, icon):
    p, b = g.p, g.b
    top, ridge = barn_body(g, 16, 40, 18, 12)
    g.sign(30, top + 2, icon) if False else None
    # the oast house: a round kiln with a white cowl, where the hops are dried
    ox0, ox1 = 46, 60
    tw = [(ox0, b), (ox1, b), (ox1, b - 20), (ox0, b - 20)]
    stone_fill(g, tw, (186, 110, 80), "brick")
    p.shade(tw, b - 20, b, (0, 0, 0, 0), (0, 0, 0, 30))
    p.polygon([(ox0 + 9, b), (ox1, b), (ox1, b - 20), (ox0 + 9, b - 20)], fill=(0, 0, 0, 50))
    p.polygon(tw, outline=(110, 60, 40, 255), width=0.4)
    cone(g, 53, b - 20, 8, 16, g.roof, "tiles")
    cw = [(51, b - 34), (55, b - 34), (56.6, b - 38.4), (51.4, b - 41), (51, b - 38)]
    p.polygon(cw, fill=(244, 242, 236, 255), outline=(150, 146, 140, 255), width=0.35)
    p.line([(55, b - 36), (59, b - 34)], fill=(244, 242, 236, 255), width=0.8)
    p.rectangle([51, b - 8, 55, b], fill=(60, 40, 26, 255))
    # hop bines climbing poles and strings
    for x in (3, 9, 15):
        p.line([(x, b), (x, b - 30)], fill=(140, 110, 70, 255), width=0.6)
    p.line([(2, b - 29), (16, b - 29)], fill=(140, 110, 70, 255), width=0.4)
    rnd = random.Random(7)
    for x in (3, 9, 15):
        for k in range(14):
            y = b - 2 - k * 2
            p.disc(x + rnd.uniform(-1.4, 1.4), y, rnd.uniform(0.9, 1.4), (70, 130, 50, 255) if k % 3 else (96, 156, 64, 255))
            if k % 4 == 1:
                p.ellipse([x + 0.4, y - 0.6, x + 1.8, y + 1.4], fill=(186, 214, 110, 255))


def v_sheep_farm(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 28, 58, 14, "stone", 10, roof="thatch")
    g.door(40, 7, 10)
    g.sign(48, top + 2, icon)
    # a fold of hurdles with sheep in it
    fence_back(g, 1, b - 4, 9, -8, 3)
    fence_back(g, 26, b - 4, 9, -8, 3)
    fence(g, 10, 35, b - 12, 4.2, 4)
    sheep(g, 6, b - 6)
    sheep(g, 15, b - 9, True)
    sheep(g, 18, b - 3)
    fence(g, 1, 26, b, 4.2, 5)
    # bales of wool
    for x in (54, 59):
        p.rounded_rectangle([x, b - 4, x + 4.4, b], 1.2, fill=(240, 236, 222, 255), outline=(170, 164, 150, 255), width=0.3)


def v_pig_farm(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 32, 56, 12, "planks", 8, roof="thatch")
    p.rectangle([38, b - 7, 45, b], fill=(40, 30, 20, 255))
    p.pieslice([38, b - 10, 45, b - 4], 180, 360, fill=(40, 30, 20, 255))
    g.sign(47, top + 1, icon)
    # a muddy pen with pigs and a trough
    p.ellipse([0, b - 12, 34, b + 1], fill=(120, 92, 60, 255))
    p.ellipse([4, b - 9, 26, b - 1], fill=(102, 76, 48, 255))
    p.ellipse([10, b - 7, 18, b - 4], fill=(130, 110, 80, 180))
    fence_back(g, 0, b - 4, 8, -7, 2)
    fence(g, 8, 34, b - 11, 4.4, 4)
    pig(g, 5, b - 4)
    pig(g, 18, b - 7, True)
    pig(g, 22, b - 1)
    trough = [(26, b - 5), (34, b - 5), (33.2, b - 2), (26.8, b - 2)]
    wood_fill(g, trough, (130, 92, 56), 2, False, 0.3)
    fence(g, 0, 34, b + 2, 4.4, 4.6)


def v_flax_farm(g, icon):
    p, b = g.p, g.b
    top, ridge = barn_body(g, 30, 56, 18, 12, doors=False)
    g.big_door(36, b - 13, 46, b, (100, 110, 150), split=True)
    g.sign(47, top + 2, icon)
    # rows of blue-flowering flax and stooks drying
    for r in range(4):
        y = b - 18 + r * 4.6
        for k in range(10):
            x = 1 + k * 2.6 + r * 0.6
            p.line([(x, y + 2.4), (x, y)], fill=(90, 130, 70, 255), width=0.45)
            p.disc(x, y - 0.3, 0.7, (110, 150, 220, 255) if (k + r) % 3 else (150, 180, 240, 255))
    for x in (8, 18):
        p.polygon([(x - 2.4, b), (x, b - 8), (x + 2.4, b)], fill=(206, 184, 120, 255), outline=(140, 120, 60, 255), width=0.3)
        p.line([(x - 1.6, b - 3), (x + 1.6, b - 3)], fill=(140, 120, 60, 255), width=0.4)


def v_storehouse(g, icon):
    p, b = g.p, g.b
    # a granary raised on staddle stones to keep out rats and damp
    for x in (14, 25, 36, 46):
        p.polygon([(x + 0.6, b), (x + 2.4, b), (x + 2.0, b - 4), (x + 1.0, b - 4)], fill=(150, 146, 136, 255))
        p.ellipse([x - 0.6, b - 5.4, x + 3.6, b - 3.6], fill=(170, 166, 156, 255), outline=(100, 96, 88, 255), width=0.3)
    sb = g.b
    g.b = b - 5
    top = b - 28
    g.walls(12, 48, top, "planks", grass=False)
    ridge = g.roof_gable(12, 48, top, 13)
    g.big_door(26, b - 18, 34, b - 5, (110, 80, 50))
    g.b = sb
    # steps up to the door
    for k in range(3):
        wood_fill(g, [(25 + k * 0.4, b - k * 1.7), (35 - k * 0.4, b - k * 1.7), (35 - k * 0.4, b - k * 1.7 - 1.2), (25 + k * 0.4, b - k * 1.7 - 1.2)], (150, 112, 66), 3, False, 0.3)
    for x in (1, 6.4):
        sack(g, x, b)
    sack(g, 3.6, b - 4.6, (200, 180, 136))
    crate(g, 52, b, 5.4)
    crate(g, 56.6, b - 5.4, 4.4, (150, 114, 70))
    p.paste(icon, 18, b - 22, 7) if icon is not None else None


def v_mule_station(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 22, 56, 18, "planks", 11)
    # two stable doors in halves, a mule looking out of one
    for x in (27, 41):
        p.rectangle([x - 1, b - 13, x + 9, b], fill=sh(g.wall, 0.45))
        p.rectangle([x, b - 12, x + 8, b - 7], fill=(28, 22, 16, 255))
        wood_fill(g, [(x, b - 7), (x + 8, b - 7), (x + 8, b), (x, b)], (128, 82, 46), 2, True, 0.4)
        p.line([(x, b - 7), (x + 8, b)], fill=(90, 56, 30, 255), width=0.5)
    mc = (110, 90, 74, 255)
    p.polygon([(43, b - 7), (44, b - 10.6), (47, b - 11.4), (49, b - 9.6), (49.6, b - 7.6), (47.6, b - 7)], fill=mc, outline=sh(mc, 0.5), width=0.3)
    p.disc(48.8, b - 8, 0.9, (210, 200, 186, 255))
    for ex in (45, 46.4):
        p.polygon([(ex, b - 11), (ex - 0.6, b - 14.4), (ex + 0.8, b - 11.2)], fill=sh(mc, 0.85))
    p.point((46.4, b - 9.8), fill=(20, 16, 12, 255))
    # a mule with pack bags at the hitching rail, a trough
    p.line([(1, b - 6), (21, b - 6)], fill=C(mt.WOOD), width=0.8)
    for x in (2, 20):
        p.line([(x, b), (x, b - 7)], fill=C(mt.WOOD), width=0.9)
    donkey(g, 5, b, (110, 90, 74))
    for x, col in ((8, (170, 120, 70)), (12, (150, 104, 60))):
        p.rounded_rectangle([x, b - 7.4, x + 3.6, b - 3.2], 1, fill=C(col), outline=sh(C(col), 0.5), width=0.3)
    wood_fill(g, [(14, b - 3), (21, b - 3), (20.4, b), (14.6, b)], (130, 92, 56), 2, False, 0.3)
    p.rectangle([14.6, b - 3.6, 20.4, b - 3], fill=(90, 140, 180, 255))
    p.paste(icon, 34, top + 2, 6) if icon is not None else None


def v_dairy(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 26, 50, 18, "timber", 11)
    g.door(30, 7, 10)
    g.window(41, top + 4)
    g.sign(39, b - 11, icon)
    cow(g, 3, b)
    for x in (52, 56.4):
        churn = [(x, b), (x + 3.6, b), (x + 3.6, b - 5), (x + 2.8, b - 6.4), (x + 2.8, b - 7.6), (x + 0.8, b - 7.6), (x + 0.8, b - 6.4), (x, b - 5)]
        p.polygon(churn, fill=(196, 200, 206, 255), outline=(100, 104, 110, 255), width=0.3)
        p.line([(x + 1, b - 4.6), (x + 1, b - 0.6)], fill=(240, 244, 248, 255), width=0.4)
    p.polygon([(17, b - 3), (21, b - 3), (20.4, b), (17.6, b)], fill=(150, 110, 70, 255), outline=(90, 64, 40, 255), width=0.3)
    p.ellipse([17, b - 3.6, 21, b - 2.4], fill=(250, 248, 240, 255))
    p.rectangle([17.6, b - 1.6, 20.4, b - 0.2], fill=(200, 190, 170, 255))


def v_vineyard(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 38, 58, 15, "stone", 9)
    g.door(42, 6, 9, arch=True)
    g.sign(49, top + 2, icon)
    # rows of vines on stakes, heavy with grapes
    rnd = random.Random(3)
    for r in range(4):
        y = b - 22 + r * 6.4
        x0 = 1 + r * 0.8
        p.line([(x0, y - 4), (x0 + 34, y - 4)], fill=(150, 120, 80, 255), width=0.3)
        for k in range(7):
            x = x0 + 1 + k * 5
            p.line([(x, y + 0.6), (x, y - 5)], fill=(120, 90, 54, 255), width=0.5)
            for j in range(5):
                p.disc(x + rnd.uniform(-2.2, 2.2), y - 3 + rnd.uniform(-2, 1.6), rnd.uniform(1.0, 1.5), (60 + rnd.randint(0, 30), 120 + rnd.randint(0, 30), 50, 255))
            p.disc(x + rnd.uniform(-1.4, 1.4), y - 1.6, 0.9, (100, 40, 110, 255))
            p.disc(x + rnd.uniform(-1.4, 1.4) + 0.4, y - 1.0, 0.7, (130, 60, 140, 255))


def v_donkey_farm(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 34, 58, 16, "planks", 10, roof="thatch")
    g.big_door(40, b - 11, 50, b, (120, 84, 50))
    g.sign(51, top + 2, icon)
    # a paddock with donkeys and a foal, a hay rack
    fence_back(g, 1, b - 2, 10, -10, 3)
    fence(g, 11, 33, b - 12, 4.4, 4.4)
    donkey(g, 5, b - 5, (140, 128, 116))
    donkey(g, 20, b - 8, (110, 100, 92), True)
    donkey(g, 17, b - 1, (150, 138, 124), False, 0.7)
    wood_fill(g, [(26, b - 10), (32, b - 10), (32, b - 4), (26, b - 4)], (130, 92, 56), 1.4, True, 0.3)
    for k in range(5):
        p.line([(26.6 + k * 1.2, b - 10.6), (27 + k * 1.2, b - 8)], fill=(222, 196, 100, 255), width=0.6)
    fence(g, 1, 33, b + 1.5, 4.4, 5)


# ------------------------------------------------------------------ sheds
def shed_body(g, x0, x1, h=16, mat="planks", rh=10, roof=None, door=True):
    top, ridge = body(g, x0, x1, h, mat, rh, roof=roof)
    if door:
        g.door(x0 + 4, 7, 10)
    return top, ridge


def v_woodcutter(g, icon):
    p, b = g.p, g.b
    top, ridge = shed_body(g, 18, 42)
    g.sign(31, top + 3, icon)
    log_pile(g, 0, b, 4, 1.9)
    # a chopping block with the axe in it, split logs round it
    blk = [(48, b), (55, b), (55, b - 5), (48, b - 5)]
    wood_fill(g, blk, (120, 84, 50), 1.4, True, 0.35)
    p.ellipse([48, b - 6, 55, b - 4], fill=(206, 170, 120, 255), outline=(120, 84, 50, 255), width=0.3)
    p.line([(51.6, b - 5.4), (57, b - 12)], fill=(150, 112, 70, 255), width=0.8)
    p.polygon([(50.6, b - 4.6), (53, b - 6.6), (52.6, b - 4.2)], fill=(190, 194, 204, 255))
    for x, a in ((58, 1), (46, -1)):
        p.polygon([(x, b), (x + 2.6 * a, b), (x + 2.2 * a, b - 2.2)], fill=(206, 170, 120, 255), outline=(120, 84, 50, 255), width=0.3)


def v_forester(g, icon):
    p, b = g.p, g.b
    top, ridge = shed_body(g, 32, 54, roof="thatch")
    g.sign(44, top + 3, icon)
    # a nursery of young trees in rows, a watering can
    for r in range(3):
        for k in range(5):
            x = 3 + k * 5.4 + r * 1.6
            y = b - 14 + r * 6
            hgt = 3 + ((k + r) % 3) * 1.4
            p.ellipse([x - 1.4, y - 0.4, x + 1.4, y + 0.8], fill=(110, 84, 54, 255))
            for j in range(3):
                w = (3 - j) * hgt / 4.5
                yy = y - j * hgt / 3.2
                p.polygon([(x - w, yy), (x, yy - hgt / 2), (x + w, yy)], fill=(56 + j * 12, 110 + j * 12, 56, 255))
    x = 26
    p.rectangle([x, b - 4, x + 4, b], fill=(140, 146, 150, 255), outline=(80, 84, 90, 255), width=0.3)
    p.line([(x + 4, b - 2.4), (x + 7, b - 5)], fill=(140, 146, 150, 255), width=0.6)
    p.arc([x - 1.4, b - 6, x + 2, b - 2.4], 90, 270, fill=(80, 84, 90, 255), width=0.4)


def v_clay_pit(g, icon):
    p, b = g.p, g.b
    top, ridge = shed_body(g, 38, 56, 14)
    g.sign(48, top + 2, icon)
    # a pit dug into the clay, its edges stepped, a heap and a barrow
    p.ellipse([0, b - 12, 34, b + 1], fill=(184, 112, 64, 255))
    p.ellipse([3, b - 10.4, 31, b - 0.6], fill=(150, 86, 46, 255))
    p.ellipse([7, b - 8, 27, b - 2], fill=(118, 66, 36, 255))
    p.ellipse([12, b - 6.2, 22, b - 3.4], fill=(110, 140, 150, 200))
    p.arc([3, b - 10.4, 31, b - 0.6], 190, 350, fill=(210, 140, 90, 255), width=0.5)
    heap(g, 26, 38, b, 6, (176, 104, 60), mat=None)
    x = 22
    p.polygon([(x, b - 5), (x + 7, b - 5), (x + 6, b - 2), (x + 1, b - 2)], fill=(130, 92, 56, 255), outline=(70, 50, 30, 255), width=0.3)
    p.ellipse([x + 0.6, b - 6.4, x + 6.4, b - 4.4], fill=(190, 116, 66, 255))
    p.disc(x + 1, b - 1.2, 1.4, (60, 50, 40, 255))
    p.line([(x + 6, b - 3), (x + 10, b - 1)], fill=(110, 80, 50, 255), width=0.6)
    p.line([(31, b - 9), (34, b - 18)], fill=(150, 112, 70, 255), width=0.7)
    p.polygon([(29.6, b - 8.4), (32.4, b - 9.4), (32, b - 6), (30, b - 5.6)], fill=(150, 150, 156, 255))


def v_saltworks(g, icon):
    p, b = g.p, g.b
    top, ridge = shed_body(g, 40, 58, 14)
    g.sign(49, top + 2, icon)
    # shallow pans where the sea water dries, white salt raked into heaps
    for r, (y, crust) in enumerate(((b - 12, 0.3), (b - 6, 0.7), (b, 1.0))):
        x0 = 1 + r * 1.4
        pan = [(x0, y), (x0 + 30, y), (x0 + 33, y - 4.6), (x0 + 3, y - 4.6)]
        p.polygon(pan, fill=(150, 130, 100, 255))
        inner = [(x0 + 1, y - 0.6), (x0 + 29.4, y - 0.6), (x0 + 31.8, y - 4), (x0 + 3.4, y - 4)]
        p.polygon(inner, fill=mt.mix((110, 160, 196), (240, 244, 246), crust))
        rnd = random.Random(r)
        for k in range(10):
            xx = rnd.uniform(x0 + 3, x0 + 29)
            yy = rnd.uniform(y - 3.6, y - 1)
            p.line([(xx, yy), (xx + 2, yy)], fill=(255, 255, 255, 200), width=0.35)
    for x in (34, 0):
        pass
    heap(g, 30, 40, b + 0.5, 7, (240, 240, 236), mat=None)
    heap(g, 33, 39, b - 6, 5, (232, 232, 230), mat=None)
    p.line([(28, b - 1), (37, b - 13)], fill=(150, 112, 70, 255), width=0.6)
    p.line([(26.4, b - 1.6), (29.6, b + 0.6)], fill=(110, 80, 50, 255), width=0.8)


def v_hunter(g, icon):
    p, b = g.p, g.b
    top, ridge = shed_body(g, 22, 46, 16, "planks", 11)
    g.sign(35, top + 2, icon)
    # antlers over the door, a hide on its frame, meat drying on a rack, a bow and quiver
    ax, ay = 29.5, top + 1.5
    for s in (-1, 1):
        p.line([(ax, ay), (ax + s * 3, ay - 2.6), (ax + s * 4.2, ay - 5.6)], fill=(232, 222, 198, 255), width=0.6)
        p.line([(ax + s * 2.6, ay - 2.2), (ax + s * 4.4, ay - 2.4)], fill=(232, 222, 198, 255), width=0.5)
    hide(g, 2, b - 2, 11, 12, (170, 124, 80))
    for x in (15, 21):
        p.line([(x, b), (x, b - 14)], fill=C(mt.WOOD), width=0.8)
    p.line([(14.4, b - 13), (21.6, b - 13)], fill=C(mt.WOOD), width=0.7)
    for k in range(3):
        x = 16 + k * 2
        p.polygon([(x, b - 12.6), (x + 1.2, b - 12.6), (x + 1, b - 8), (x + 0.2, b - 8.6)], fill=(150, 56, 44, 255))
    p.arc([49, b - 16, 55, b], 280, 440, fill=(140, 96, 50, 255), width=0.8)
    p.line([(52.4, b - 15.6), (52.4, b - 0.4)], fill=(230, 226, 210, 255), width=0.25)
    p.polygon([(56, b), (59, b), (59.6, b - 9), (56.4, b - 9)], fill=(120, 76, 44, 255), outline=(60, 36, 20, 255), width=0.3)
    for k in range(3):
        p.line([(56.8 + k, b - 9), (56.4 + k, b - 12)], fill=(220, 220, 220, 255), width=0.5)


def v_herb_garden(g, icon):
    p, b = g.p, g.b
    top, ridge = shed_body(g, 40, 58, 14, "planks", 9, roof="thatch")
    g.sign(49, top + 2, icon)
    # raised beds of herbs and flowers inside a wattle fence, a little arch
    for r, y in enumerate((b - 13, b - 5)):
        x0 = 2 + r * 1.2
        bed = [(x0, y), (x0 + 30, y), (x0 + 30, y + 2), (x0, y + 2)]
        wood_fill(g, bed, (130, 92, 56), 2, False, 0.3)
        p.rectangle([x0 + 0.5, y - 0.6, x0 + 29.5, y], fill=(96, 70, 44, 255))
        for k in range(10):
            x = x0 + 1.6 + k * 2.9
            col = ((90, 140, 70), (150, 110, 190), (110, 150, 80), (240, 220, 90), (80, 130, 90))[(k + r * 2) % 5]
            for j in range(4):
                p.disc(x + (j % 2) * 1.0 - 0.5, y - 1.2 - (j // 2) * 1.2, 1.0, C(col) if j else (80, 130, 60, 255))
    p.arc([31, b - 22, 39, b - 6], 180, 360, fill=(140, 110, 70, 255), width=0.8)
    for x in (31.4, 38.4):
        p.line([(x, b - 14), (x, b)], fill=(140, 110, 70, 255), width=0.8)
    for k in range(6):
        a = math.radians(190 + k * 30)
        p.disc(35 + 4 * math.cos(a), b - 14 + 8 * math.sin(a), 0.9, (220, 80, 110, 255) if k % 2 else (80, 140, 60, 255))


def v_scout_lodge(g, icon):
    p, b = g.p, g.b
    top, ridge = shed_body(g, 26, 50, 16, "planks", 11)
    g.sign(37, top + 2, icon)
    # a lookout platform on a tall pole with a ladder and a pennant
    p.line([(10, b), (10, b - 40)], fill=C(sh(mt.WOOD, 1.05)), width=1.6)
    p.line([(4, b), (10, b - 18)], fill=C(mt.WOOD), width=0.8)
    p.line([(16, b), (10, b - 18)], fill=C(mt.WOOD), width=0.8)
    wood_fill(g, [(4, b - 40), (16, b - 40), (16, b - 38), (4, b - 38)], (140, 100, 60), 2, False, 0.3)
    for x in (4.4, 15.2):
        p.line([(x, b - 40), (x, b - 44)], fill=C(mt.WOOD), width=0.5)
    p.line([(4, b - 43.6), (16, b - 43.6)], fill=C(mt.WOOD), width=0.5)
    ladder(g, 12, b, 12, b - 38)
    pennant(g, 15.6, b - 44, b - 52, (60, 120, 60))


def v_sand_pit(g, icon):
    p, b = g.p, g.b
    top, ridge = shed_body(g, 40, 58, 14)
    g.sign(49, top + 2, icon)
    heap(g, 0, 22, b, 11, (222, 196, 130), mat=None, glints=(240, 222, 170))
    heap(g, 16, 34, b + 1, 7, (210, 184, 120), mat=None, glints=(236, 214, 160))
    # a sieve leaning on its prop and a spade in the heap
    p.polygon([(24, b - 1), (34, b - 1), (31, b - 13), (21, b - 13)], fill=(0, 0, 0, 0), outline=(140, 104, 64, 255), width=0.8)
    for k in range(1, 6):
        p.line([(21 + k * 0.5 + k * 1.6, b - 13), (24 + k * 1.6 + k * 0.1, b - 1)], fill=(150, 150, 156, 160), width=0.25)
        p.line([(21 + k * 0.6, b - 13 + k * 2), (31 + k * 0.6, b - 13 + k * 2)], fill=(150, 150, 156, 160), width=0.25)
    p.line([(30, b - 13), (36, b)], fill=C(mt.WOOD), width=0.6)
    p.line([(8, b - 9), (10, b - 20)], fill=(150, 112, 70, 255), width=0.7)
    p.polygon([(6.6, b - 9.6), (9.4, b - 9.2), (8.8, b - 5.6), (6.8, b - 6)], fill=(150, 150, 156, 255))


def v_apiary(g, icon):
    p, b = g.p, g.b
    top, ridge = shed_body(g, 38, 56, 14, "planks", 10, roof="thatch")
    g.sign(47, top + 2, icon)
    # straw skeps on a bench among flowers, and a few bees
    wood_fill(g, [(1, b - 6), (34, b - 6), (34, b - 4.8), (1, b - 4.8)], (140, 100, 60), 2, False, 0.3)
    for x in (3, 32):
        p.line([(x, b - 4.8), (x, b)], fill=C(mt.WOOD), width=0.8)
    for x in (6, 14, 22, 30):
        skep(g, x, b - 6, 3.4)
    rnd = random.Random(5)
    for k in range(16):
        x = rnd.uniform(0, 36)
        y = rnd.uniform(b - 3, b + 1)
        p.line([(x, y + 1.4), (x, y)], fill=(80, 130, 60, 255), width=0.35)
        p.disc(x, y, 0.75, C(rnd.choice([(240, 220, 90), (230, 120, 160), (200, 160, 230), (250, 250, 250)])))
    for k in range(7):
        x = rnd.uniform(4, 34)
        y = rnd.uniform(b - 22, b - 12)
        p.disc(x, y, 0.55, (230, 180, 40, 255))
        p.point((x + 0.4, y - 0.1), fill=(40, 30, 20, 255))


# ------------------------------------------------------------------ kilns and furnaces
def small_hut(g, x0, x1, h=14, mat="planks", rh=9):
    top, ridge = body(g, x0, x1, h, mat, rh, 6, 4)
    g.door(x0 + 3, 6, 9)
    return top


def v_charcoal_burner(g, icon):
    p, b = g.p, g.b
    top = small_hut(g, 42, 58)
    g.sign(49, top + 2, icon) if icon is not None else None
    # a charcoal clamp: a mound of wood covered with turf and earth, smoking from its vents
    mound = [(1 + 36 / 2 + 18 * math.cos(math.radians(a)), b - 15 * math.sin(math.radians(a)) ** 0.85) for a in range(180, -1, -8)]
    p.polygon(mound, fill=(84, 72, 60, 255))
    g.surface(mound, "rock", (84, 72, 60))
    rnd = random.Random(11)
    for k in range(18):
        a = rnd.uniform(0.2, math.pi - 0.2)
        r = rnd.uniform(0.3, 0.92)
        x = 19 + 18 * math.cos(a) * r
        y = b - 15 * math.sin(a) * r ** 0.4
        p.ellipse([x - 1.8, y - 0.8, x + 1.8, y + 0.8], fill=(86, 110, 58, 255) if k % 3 else (60, 50, 40, 255))
    p.clipped(mound, lambda q: q.ellipse([22, b - 18, 44, b + 4], fill=(0, 0, 0, 70)))
    for x, y in ((12, b - 10), (20, b - 14), (27, b - 9)):
        p.ellipse([x - 1, y - 0.6, x + 1, y + 0.6], fill=(40, 30, 24, 255))
    glow_hole(g, 17, b - 3, 21, b, arch=False)
    _set("smoke", 20, b - 15)
    _set("glow", 19, b - 1.5)
    # billets stacked ready for the next burn
    for k in range(3):
        y = b - k * 2.2
        for j in range(3 - k):
            x = 35 + j * 2.4 + k * 1.2
            p.disc(x, y - 1.1, 1.1, (140, 96, 56, 255))
            p.disc(x, y - 1.1, 0.5, (200, 160, 110, 255))


def v_smokehouse(g, icon):
    p, b = g.p, g.b
    top = b - 30
    g.walls(10, 28, top, "planks", 6, 4)
    ridge = g.roof_gable(10, 28, top, 12, 6, 4)
    # a louvred smoke vent along the ridge
    p.rectangle([14, ridge - 4, 25, ridge + 0.5], fill=(70, 50, 34, 255))
    for k in range(4):
        p.line([(14.5 + k * 2.8, ridge - 3.4), (16.5 + k * 2.8, ridge - 0.4)], fill=(150, 110, 70, 255), width=0.6)
    p.polygon([(12.5, ridge - 4), (19.5, ridge - 7.5), (26.5, ridge - 4)], fill=g.roof, outline=sh(g.roof, 0.5), width=0.4)
    _set("smoke", 19.5, ridge - 8)
    g.door(15, 7, 11)
    p.paste(icon, 15, top + 4, 8) if icon is not None else None
    # fish and hams hung on a rack in the smoke
    for x in (36, 61):
        p.line([(x, b), (x, b - 20)], fill=C(mt.WOOD), width=0.9)
    for y in (b - 19, b - 10):
        p.line([(35.4, y), (61.6, y)], fill=C(mt.WOOD), width=0.8)
    for k in range(8):
        x = 37.6 + k * 3.0
        y = b - 19
        p.line([(x, y), (x, y + 1)], fill=(60, 50, 40, 255), width=0.3)
        p.polygon([(x - 0.9, y + 1), (x + 0.9, y + 1), (x + 0.6, y + 6), (x, y + 7.4), (x - 0.6, y + 6)], fill=(176, 150, 96, 255) if k % 2 else (200, 170, 110, 255), outline=(110, 90, 50, 255), width=0.25)
        p.polygon([(x - 0.8, y + 7.6), (x, y + 6.8), (x + 0.8, y + 7.6)], fill=(150, 120, 70, 255))
    for k in range(4):
        x = 38.4 + k * 6
        y = b - 10
        p.polygon([(x - 1.6, y + 1.4), (x + 1.6, y + 1.4), (x + 2.2, y + 5), (x + 0.6, y + 7), (x - 1.4, y + 5.6)], fill=(150, 66, 48, 255), outline=(90, 40, 28, 255), width=0.3)
        p.line([(x, y), (x, y + 1.4)], fill=(60, 50, 40, 255), width=0.3)


def v_brickworks(g, icon):
    p, b = g.p, g.b
    # the domed kiln with its tall chimney and fire mouth
    p.rectangle([14, b - 46, 21, b - 20], fill=(150, 76, 58, 255), outline=(90, 46, 34, 255), width=0.5)
    p.rectangle([19, b - 46, 21, b - 20], fill=(112, 56, 42, 255))
    p.rectangle([13, b - 48, 22, b - 46], fill=(90, 86, 80, 255))
    dome(g, 18, b - 12, 15, 18, (168, 84, 60), ribs=0, tex="brick")
    p.rectangle([3, b - 12, 33, b], fill=(168, 84, 60, 255))
    g.surface([(3, b), (33, b), (33, b - 12), (3, b - 12)], "brick", (168, 84, 60))
    p.shade([(3, b), (33, b), (33, b - 12), (3, b - 12)], b - 12, b, (0, 0, 0, 0), (0, 0, 0, 60))
    for k in range(4):
        p.arc([3 + k * 2, b - 30 + k * 4, 33 - k * 2, b + 6 - k * 4], 185, 355, fill=(130, 62, 44, 255), width=0.4)
    glow_hole(g, 14, b - 7, 22, b)
    _set("smoke", 17.5, b - 49)
    _set("glow", 18, b - 3)
    # stacks of green bricks drying in open lattices, and a heap of clay
    for s, x0 in enumerate((34, 49)):
        for r in range(5):
            y = b - r * 2.2
            for k in range(4 if r % 2 == 0 else 3):
                x = x0 + k * 3.4 + (1.7 if r % 2 else 0) + r * 0.3
                p.rectangle([x, y - 1.8, x + 2.6, y], fill=(196, 104, 70, 255) if s == 0 else (176, 120, 90, 255), outline=(110, 54, 36, 255), width=0.25)
    heap(g, 36, 48, b - 13, 5, (176, 104, 60), mat=None)
    g.sign(52, b - 26, icon) if icon is not None else None


def v_iron_smelter(g, icon):
    p, b = g.p, g.b
    # a tall bloomery shaft of stone with bellows at its foot
    shaft = [(8, b), (30, b), (26, b - 34), (12, b - 34)]
    stone_fill(g, shaft, (150, 140, 128))
    p.polygon([(19, b), (30, b), (26, b - 34), (19, b - 34)], fill=(0, 0, 0, 55))
    p.polygon(shaft, outline=(80, 74, 66, 255), width=0.5)
    p.ellipse([11.6, b - 36, 26.4, b - 32], fill=(130, 122, 112, 255), outline=(80, 74, 66, 255), width=0.4)
    p.ellipse([14, b - 35.2, 24, b - 33], fill=(255, 140, 50, 255))
    p.ellipse([16, b - 34.8, 22, b - 33.4], fill=(255, 220, 120, 255))
    for k in range(3):
        y = b - 8 - k * 9
        p.line([(8.6 + (b - y) * 0.12, y), (29.4 - (b - y) * 0.12, y)], fill=(60, 60, 64, 255), width=0.8)
    glow_hole(g, 16, b - 6, 22, b)
    _set("glow", 19, b - 3)
    _set("smoke", 19, b - 36)
    # leather bellows on the left, a heap of red ore and a bloom on the anvil
    bel = [(0, b - 9), (8, b - 6.4), (8, b - 4.6), (0, b - 2)]
    p.polygon(bel, fill=(130, 86, 50, 255), outline=(70, 44, 24, 255), width=0.4)
    for k in range(3):
        p.line([(1.6 + k * 2, b - 8.4 + k * 0.8), (1.6 + k * 2, b - 2.6 - k * 0.8)], fill=(90, 58, 32, 255), width=0.3)
    p.line([(0, b - 9), (-1, b - 13)], fill=C(mt.WOOD), width=0.8)
    heap(g, 34, 50, b, 8, (150, 80, 56), "rock", glints=(196, 110, 70))
    anvil(g, 53, b)
    p.ellipse([53, b - 9, 58, b - 6.4], fill=(255, 150, 60, 255), outline=(150, 60, 30, 255), width=0.3)


def v_copper_smelter(g, icon):
    p, b = g.p, g.b
    top = small_hut(g, 32, 56, 16, "stone", 10)
    g.sign(42, top + 3, icon) if icon is not None else None
    # a bottle-shaped furnace of brick
    pts = [(4, b), (26, b), (24, b - 12), (19, b - 22), (18.6, b - 38), (11.4, b - 38), (11, b - 22), (6, b - 12)]
    stone_fill(g, pts, (170, 96, 64), "brick")
    p.polygon([(15, b), (26, b), (24, b - 12), (19, b - 22), (18.6, b - 38), (15, b - 38)], fill=(0, 0, 0, 50))
    p.polygon(pts, outline=(100, 54, 36, 255), width=0.5)
    p.rectangle([10.6, b - 39.4, 19.4, b - 38], fill=(80, 70, 64, 255))
    p.line([(6.6, b - 12), (23.4, b - 12)], fill=(70, 66, 64, 255), width=0.8)
    glow_hole(g, 12, b - 7, 18, b)
    _set("glow", 15, b - 3.5)
    _set("smoke", 15, b - 41)
    # green copper ore and the red metal cast in ingots
    heap(g, 0, 10, b + 1, 5, (90, 140, 110), "rock", glints=(120, 200, 170))
    for r in range(3):
        for k in range(3 - r):
            x = 27 + k * 3.4 + r * 1.7
            y = b - r * 1.6
            p.polygon([(x, y), (x + 3, y), (x + 2.6, y - 1.5), (x + 0.4, y - 1.5)], fill=(214, 120, 64, 255), outline=(130, 60, 30, 255), width=0.25)


def v_steelworks(g, icon):
    p, b = g.p, g.b
    top = b - 22
    g.walls(22, 54, top, "brick")
    g.roof_gable(22, 54, top, 7)
    tall_stack(g, 42, b - 56, top - 4, 5)
    tall_stack(g, 30, b - 50, top - 4, 4.4)
    g.big_door(27, b - 13, 38, b, (60, 62, 68))
    for x in (42, 48):
        g.window(x, top + 5, 4, 6, lit=True)
    # a pear-shaped converter tipped on its trunnions, pouring fire
    cx, cy = 11, b - 14
    vessel = [(cx - 6, cy + 6), (cx + 6, cy + 6), (cx + 7, cy - 2), (cx + 4, cy - 8), (cx - 2, cy - 9), (cx - 6, cy - 4)]
    p.polygon(vessel, fill=(70, 72, 80, 255), outline=(30, 30, 34, 255), width=0.5)
    p.shade(vessel, cy - 9, cy + 6, (255, 255, 255, 40), (0, 0, 0, 60))
    for yy in (cy - 1, cy + 3):
        p.line([(cx - 6.4, yy), (cx + 6.8, yy)], fill=(40, 40, 44, 255), width=0.6)
    p.polygon([(cx - 2, cy - 9), (cx + 4, cy - 8), (cx + 2, cy - 13), (cx - 1, cy - 12.6)], fill=(255, 170, 60, 255))
    p.disc(cx + 0.6, cy - 12.6, 1.8, (255, 230, 140, 255))
    for k in range(6):
        a = math.radians(-120 + k * 14)
        p.line([(cx + 1, cy - 12), (cx + 1 + math.cos(a) * 6, cy - 12 + math.sin(a) * 6)], fill=(255, 220, 120, 200), width=0.35)
    for sx in (cx - 8, cx + 7):
        p.rectangle([sx, cy - 1, sx + 1.4, b], fill=(60, 60, 66, 255))
    p.disc(cx - 7.3, cy, 1.4, (40, 40, 44, 255))
    _set("glow", cx + 0.6, cy - 12)
    p.line([(0, b + 0.6), (64, b + 0.6)], fill=(70, 70, 74, 255), width=0.6)
    p.line([(0, b - 1.2), (64, b - 1.2)], fill=(70, 70, 74, 255), width=0.5)
    p.rectangle([56, b - 4, 63, b - 1.6], fill=(220, 120, 50, 255), outline=(100, 50, 20, 255), width=0.3)


def v_glassworks(g, icon):
    p, b = g.p, g.b
    # a brick glass cone with glowing working holes
    pts = [(4, b), (38, b), (26, b - 40), (16, b - 40)]
    stone_fill(g, pts, (168, 92, 64), "brick")
    p.polygon([(21, b), (38, b), (26, b - 40), (21, b - 40)], fill=(0, 0, 0, 55))
    p.polygon(pts, outline=(100, 52, 34, 255), width=0.5)
    p.rectangle([15.4, b - 42, 26.6, b - 40], fill=(70, 64, 60, 255))
    _set("smoke", 21, b - 43)
    for x in (9, 18, 27):
        glow_hole(g, x, b - 6, x + 4, b)
    _set("glow", 20, b - 3)
    p.rectangle([5, b - 1, 37, b], fill=(110, 104, 96, 255))
    # glassware on a shelf, a heap of sand
    wood_fill(g, [(42, b - 9), (62, b - 9), (62, b - 8), (42, b - 8)], (140, 100, 60), 2, False, 0.3)
    for x in (43, 61):
        p.line([(x, b - 8), (x, b)], fill=C(mt.WOOD), width=0.7)
    for k, col in enumerate(((90, 170, 120), (110, 160, 210), (210, 160, 70), (120, 190, 200), (170, 110, 190))):
        x = 44 + k * 3.6
        p.rounded_rectangle([x, b - 13.4, x + 2.4, b - 9], 0.8, fill=C(col, 220), outline=sh(C(col), 0.5), width=0.25)
        p.rectangle([x + 0.8, b - 15, x + 1.6, b - 13.4], fill=C(col, 220))
        p.line([(x + 0.5, b - 12.8), (x + 0.5, b - 9.8)], fill=(255, 255, 255, 180), width=0.3)
    heap(g, 44, 58, b + 1, 5, (222, 200, 140), mat=None, glints=(240, 226, 180))
    g.sign(26, b - 26, icon) if icon is not None else None


# ------------------------------------------------------------------ halls (school style)
def v_lodge(g, icon):
    p, b = g.p, g.b
    top = b - 18
    g.walls(6, 48, top, "planks")
    # walls of round logs laid on each other
    for k in range(int((b - top) / 2.4)):
        y = b - 1.2 - k * 2.4
        p.line([(6, y), (48, y)], fill=(130, 92, 56, 255), width=2.0)
        p.line([(6, y - 0.7), (48, y - 0.7)], fill=(170, 126, 80, 255), width=0.5)
        p.disc(6, y, 1.2, (196, 156, 104, 255))
    ridge = g.roof_gable(6, 48, top, 16, mat="thatch")
    # crossed carved boards at the gable end
    gx = 51.5
    p.line([(gx - 3, ridge + 4), (gx + 3, ridge - 5)], fill=(150, 104, 60, 255), width=1.0)
    p.line([(gx + 3, ridge + 4), (gx - 3, ridge - 5)], fill=(150, 104, 60, 255), width=1.0)
    for s in (-1, 1):
        p.disc(gx + s * 3.2, ridge - 5.4, 1.0, (150, 104, 60, 255))
    g.door(23, 8, 12, arch=True)
    for x in (12, 38):
        g.window(x, top + 5, 5, 5, lit=True)
    # a fire pit and benches in front
    p.ellipse([52, b - 3, 62, b + 1], fill=(120, 116, 108, 255))
    p.ellipse([54, b - 2.2, 60, b + 0.2], fill=(60, 40, 30, 255))
    glow_hole(g, 55.4, b - 2, 58.6, b - 0.6, arch=False)
    p.ellipse([1, b - 2, 5, b + 1], fill=(130, 92, 56, 255))
    g.sign(30, top + 2, icon) if icon is not None else None


def v_infirmary(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 4, 46, 20, "timber", 12)
    g.door(21, 8, 12, arch=True)
    for x in (7, 13, 33, 39):
        g.window(x, top + 6, 4, 6)
    g.sign(21, top + 0.5, icon)
    # beds of healing herbs and a bench in the sun
    for k in range(5):
        x = 50 + k * 2.6
        p.disc(x, b - 1.6, 1.4, C(((90, 140, 70), (150, 110, 190), (240, 220, 90), (110, 160, 80), (220, 120, 140))[k]))
    wood_fill(g, [(49, b - 0.6), (63, b - 0.6), (63, b + 0.6), (49, b + 0.6)], (130, 92, 56), 2, False, 0.3)
    p.polygon([(51, b - 8), (54, b - 13), (57, b - 8)], fill=(0, 0, 0, 0))
    # a stretcher leaning by the door
    p.line([(31, b), (33, b - 12)], fill=(150, 112, 70, 255), width=0.6)
    p.line([(33.6, b), (35.6, b - 12)], fill=(150, 112, 70, 255), width=0.6)
    p.polygon([(31.4, b - 2), (34.4, b - 2), (35.8, b - 10.6), (32.8, b - 10.6)], fill=(230, 222, 200, 255))


def v_chapel(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 20, 50, 18, "stone", 14, roof="slate")
    for x in (26, 36, 44):
        p.rectangle([x - 0.2, top + 5 - 0.2, x + 3.2, top + 13], fill=sh(g.wall, 0.45))
        p.pieslice([x - 0.2, top + 3.4, x + 3.2, top + 6.6], 180, 360, fill=sh(g.wall, 0.45))
        p.shade([(x + 0.4, top + 5), (x + 2.6, top + 5), (x + 2.6, top + 12.4), (x + 0.4, top + 12.4)], top + 5, top + 12.4, (90, 70, 140, 255), (190, 130, 70, 255))
        p.pieslice([x + 0.4, top + 4, x + 2.6, top + 6.2], 180, 360, fill=(90, 70, 140, 255))
    # the bell tower with its spire
    tt = b - 36
    g.walls(6, 20, tt, "stone", 5, 3.5)
    p.rectangle([10.5, tt + 4, 15.5, tt + 10], fill=(30, 26, 22, 255))
    p.pieslice([10.5, tt + 2, 15.5, tt + 7], 180, 360, fill=(30, 26, 22, 255))
    p.pieslice([11.4, tt + 5, 14.6, tt + 9], 180, 360, fill=(220, 180, 70, 255))
    p.rectangle([11.4, tt + 7, 14.6, tt + 8.4], fill=(220, 180, 70, 255))
    spire = [(4.6, tt), (13, tt - 20), (21.4, tt), ]
    cone(g, 13, tt + 0.5, 8.4, 20, g.roof, "slate")
    p.polygon([(21.4, tt), (13, tt - 20), (25, tt - 3.5)], fill=sh(g.roof, 0.6))
    p.line([(13, tt - 20), (13, tt - 25)], fill=(220, 190, 90, 255), width=0.7)
    p.line([(11.2, tt - 23.4), (14.8, tt - 23.4)], fill=(220, 190, 90, 255), width=0.7)
    g.door(9.5, 7, 11, arch=True)
    g.sign(30, b - 12, icon)


def v_scriptorium(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 6, 46, 24, "stone", 12, roof="slate")
    for x in (10, 20, 30, 39):
        p.rectangle([x - 0.3, top + 4, x + 3.3, top + 11], fill=sh(g.wall, 0.45))
        p.pieslice([x - 0.3, top + 2.2, x + 3.3, top + 5.8], 180, 360, fill=sh(g.wall, 0.45))
        g._glass(x + 0.3, top + 4, 2.4, 6.6, x == 20)
    # a cloister walk along the front under a lean-to roof
    ay = b - 10
    lean = [(4, ay), (48, ay), (48, ay - 4), (4, ay - 4)]
    p.polygon(lean, fill=g.roof)
    sd = g._seed()
    p.texfill(lean, lambda W, H, F: mt.BT.slates(W, H, F, tuple(g.roof[:3]), sd))
    p.polygon(lean, outline=sh(g.roof, 0.45), width=0.4)
    p.rectangle([5, ay, 47, b], fill=sh(g.wall, 1.05))
    g.surface([(5, ay), (47, ay), (47, b), (5, b)], "stone", sh(g.wall, 1.05))
    for k in range(6):
        x = 6.6 + k * 6.8
        p.rectangle([x, ay + 3.4, x + 5, b], fill=(40, 34, 28, 255))
        p.pieslice([x, ay + 1, x + 5, ay + 6], 180, 360, fill=(40, 34, 28, 255))
    p.shade([(5, ay), (47, ay), (47, ay + 3), (5, ay + 3)], ay, ay + 3, (0, 0, 0, 100), (0, 0, 0, 0))
    g.sign(21, top + 13, icon) if icon is not None else None


def v_library(g, icon):
    p, b = g.p, g.b
    top = b - 30
    g.walls(6, 50, top, "stone")
    deck = [(6, top), (50, top), (57, top - 5), (13, top - 5)]
    stone_fill(g, deck, g.wall, "stone", 0.62)
    for x in (4, 50):
        pass
    dome(g, 30, top - 2, 11, 12, g.roof, ribs=8)
    p.rectangle([28.6, top - 17, 31.4, top - 13.6], fill=sh(g.wall, 1.1))
    p.polygon([(28, top - 17), (30, top - 20), (32, top - 17)], fill=g.roof)
    for r in range(2):
        for x in (9, 15, 41, 46):
            g.window(x, top + 4 + r * 12, 3.4, 6)
    # a portico of columns under a pediment
    pd = [(19, top + 6), (41, top + 6), (30, top - 0.6)]
    p.polygon(pd, fill=sh(g.wall, 1.15), outline=sh(g.wall, 0.5), width=0.5)
    p.polygon([(23, top + 5), (37, top + 5), (30, top + 1.4)], fill=sh(g.wall, 0.9))
    p.rectangle([19, top + 6, 41, top + 7.6], fill=sh(g.wall, 1.2), outline=sh(g.wall, 0.5), width=0.3)
    p.rectangle([20, top + 7.6, 40, b], fill=sh(g.wall, 0.55))
    g.door(27, 6, 11, arch=True)
    for x in (20.6, 25.4, 33.8, 38.6):
        col = [(x, b - 1.4), (x + 1.8, b - 1.4), (x + 1.8, top + 7.6), (x, top + 7.6)]
        p.polygon(col, fill=(240, 236, 226, 255))
        p.line([(x + 1.3, top + 8), (x + 1.3, b - 1.6)], fill=(190, 184, 170, 255), width=0.4)
    for k in range(3):
        p.rectangle([19 - k * 0.8, b - 1.4 + k * 0.6, 41 + k * 0.8, b - 0.8 + k * 0.6], fill=(200, 196, 186, 255))
    g.sign(31.5, top + 9, icon) if icon is not None and False else None


# ------------------------------------------------------------------ big buildings (64 x 72)
def v_manor(g, icon):
    p, b = g.p, g.b
    top = b - 30
    g.walls(8, 50, top, "timber")
    ridge = g.roof_gable(8, 50, top, 14)
    chim(g, 14, ridge - 2, top - 4)
    g.chimney(42, ridge - 2, top - 4)
    for r in range(2):
        for x in (11, 18, 37, 44):
            g.window(x, top + 4 + r * 13, 4, 6, lit=(r == 1 and x == 18))
    # a porch with a little gable over the door, steps, clipped hedges and gate posts
    g.door(26, 8, 13)
    p.rectangle([24.4, b - 15, 25.6, b], fill=(236, 230, 214, 255))
    p.rectangle([34.4, b - 15, 35.6, b], fill=(236, 230, 214, 255))
    p.polygon([(23, b - 15), (37, b - 15), (30, b - 21)], fill=g.roof, outline=sh(g.roof, 0.5), width=0.4)
    p.polygon([(25, b - 15.4), (35, b - 15.4), (30, b - 19.4)], fill=sh(g.wall, 1.15))
    for k in range(3):
        p.rectangle([24 - k, b - 1 + k * 0.5, 36 + k, b - 0.4 + k * 0.5], fill=(200, 196, 186, 255))
    for x in (2, 54):
        p.rounded_rectangle([x, b - 6, x + 8, b], 2.4, fill=(60, 110, 50, 255), outline=(36, 70, 30, 255), width=0.4)
        p.disc(x + 2.6, b - 4.2, 1.6, (90, 140, 70, 255))
    for x in (11, 46):
        p.disc(x + 1.5, b - 3, 2.6, (56, 104, 48, 255))
        p.disc(x + 0.9, b - 3.8, 1.2, (90, 140, 70, 255))
    g.sign(29, top + 4, icon) if icon is not None else None


def v_university(g, icon):
    p, b = g.p, g.b
    top = b - 26
    g.walls(2, 54, top, "stone")
    g.roof_gable(2, 54, top, 10, mat="slate")
    for x in (5, 11, 17, 37, 43, 49):
        p.rectangle([x - 0.2, top + 5, x + 3.2, top + 15], fill=sh(g.wall, 0.45))
        p.pieslice([x - 0.2, top + 3.4, x + 3.2, top + 6.6], 180, 360, fill=sh(g.wall, 0.45))
        g._glass(x + 0.3, top + 5, 2.4, 9.4, x == 11)
    # the clock tower over the gate
    tt = b - 50
    g.walls(22, 34, tt, "stone", 5, 3.5)
    g.flat_top(22, 34, tt, 5, 3.5, crenel=False)
    cone(g, 30.5, tt - 2, 9, 14, g.roof, "slate")
    p.disc(28, tt + 7, 4, (240, 236, 220, 255))
    p.ellipse([24, tt + 3, 32, tt + 11], outline=(40, 40, 44, 255), width=0.5)
    p.line([(28, tt + 7), (28, tt + 4.4)], fill=(30, 30, 34, 255), width=0.5)
    p.line([(28, tt + 7), (30.2, tt + 8.2)], fill=(30, 30, 34, 255), width=0.5)
    for x in (22, 34):
        p.line([(x, tt), (x, tt - 6)], fill=sh(g.wall, 0.8), width=1.2)
        p.polygon([(x - 1, tt - 6), (x, tt - 9), (x + 1, tt - 6)], fill=g.roof)
    g.door(24.5, 8, 14, arch=True)
    g.sign(25.5, tt + 14, icon) if icon is not None else None


def v_fortress(g, icon):
    p, b = g.p, g.b
    # the keep behind
    sb = g.b
    g.b = b - 10
    kt = b - 52
    g.walls(18, 42, kt, "stone")
    g.flat_top(18, 42, kt)
    for x in (24, 35):
        p.rectangle([x, kt + 8, x + 1.6, kt + 14], fill=mt.DARK)
    pennant(g, 30, kt - 4, kt - 14, (200, 60, 50))
    g.b = sb
    # a curtain wall with two round towers at the gate
    wt = b - 14
    g.walls(1, 60, wt, "stone", 3, 2)
    g.flat_top(1, 60, wt, 3, 2)
    for cx in (21, 39):
        r = 6
        tw = [(cx - r, b), (cx + r, b), (cx + r, b - 24), (cx - r, b - 24)]
        stone_fill(g, tw, g.wall)
        p.polygon([(cx + 1, b), (cx + r, b), (cx + r, b - 24), (cx + 1, b - 24)], fill=(0, 0, 0, 60))
        p.polygon([(cx - r, b), (cx - r + 1.6, b), (cx - r + 1.6, b - 24), (cx - r, b - 24)], fill=(255, 255, 255, 30))
        p.polygon(tw, outline=sh(g.wall, 0.45), width=0.5)
        for k in range(4):
            x = cx - r + 0.4 + k * 3.2
            m = [(x, b - 24), (x + 2, b - 24), (x + 2, b - 27.4), (x, b - 27.4)]
            stone_fill(g, m, g.wall, "stone", 1.08)
            p.polygon(m, outline=sh(g.wall, 0.5), width=0.3)
        p.rectangle([cx - 0.6, b - 18, cx + 0.6, b - 13], fill=mt.DARK)
    g.door(26.5, 7, 13, arch=True)
    p.rectangle([26.5, b - 13, 32.5, b], outline=(60, 60, 64, 255), width=0.3)
    for k in range(4):
        p.line([(27 + k * 1.6, b - 13), (27 + k * 1.6, b - 1)], fill=(50, 50, 54, 255), width=0.45)
    for cx in (10, 50):
        p.rectangle([cx, b - 9, cx + 1.4, b - 5], fill=mt.DARK)


def v_depot(g, icon):
    p, b = g.p, g.b
    top0 = b - 16
    g.walls(4, 48, top0, "stone")
    sb = g.b
    g.b = top0
    top1 = top0 - 12
    g.walls(4, 48, top1, "planks", grass=False)
    g.b = sb
    ridge = g.roof_gable(4, 48, top1, 12)
    for x in (9, 30):
        g.big_door(x, b - 13, x + 11, b, (110, 80, 50))
    for x in (8, 18, 28, 38):
        p.rectangle([x, top1 + 4, x + 3, top1 + 8], fill=(40, 30, 22, 255))
    # a corner watch turret of timber
    p.line([(52, b), (52, b - 36)], fill=C(mt.WOOD), width=1.2)
    p.line([(60, b), (60, b - 36)], fill=C(mt.WOOD), width=1.2)
    p.line([(52, b - 20), (60, b - 32)], fill=C(mt.WOOD), width=0.6)
    p.line([(60, b - 20), (52, b - 32)], fill=C(mt.WOOD), width=0.6)
    wood_fill(g, [(50, b - 36), (62, b - 36), (62, b - 31), (50, b - 31)], (130, 92, 54), 1.6, True, 0.4)
    p.polygon([(49, b - 36), (56, b - 44), (63, b - 36)], fill=g.roof, outline=sh(g.roof, 0.5), width=0.4)
    for x in (52, 58):
        crate(g, x - 2, b, 4.6)
    barrel(g, 21.5, b, 5, 6)
    g.sign(36, top0 - 10, icon) if icon is not None and False else None


# ------------------------------------------------------------------ wonders (64 x 72)
def v_great_hall(g, icon):
    """A long timber hall on a stone footing, carved gable ends and banners: the king's mead hall."""
    p, b = g.p, g.b
    top = b - 22
    g.walls(4, 52, top, "timber")
    for k in range(int((b - top) / 2.6)):
        y = b - 1.3 - k * 2.6
        p.line([(4, y), (52, y)], fill=(126, 88, 52, 255), width=2.2)
        p.line([(4, y - 0.8), (52, y - 0.8)], fill=(168, 124, 78, 255), width=0.5)
    p.rectangle([4, b - 4, 52, b], fill=(140, 136, 126, 255))
    g.surface([(4, b), (52, b), (52, b - 4), (4, b - 4)], "stone", (140, 136, 126))
    ridge = g.roof_gable(2, 54, top, 22, mat="thatch" if g.cat in mt.THATCH else None)
    # dragon-head gable ends crossing over the ridge
    for gx in (5, 57.5):
        p.line([(gx - 4, ridge + 6), (gx + 4, ridge - 6)], fill=(150, 104, 60, 255), width=1.3)
        p.line([(gx + 4, ridge + 6), (gx - 4, ridge - 6)], fill=(150, 104, 60, 255), width=1.3)
        for s_ in (-1, 1):
            p.disc(gx + s_ * 4.3, ridge - 6.4, 1.3, (170, 120, 70, 255))
    chim(g, 28, ridge - 4, top - 6)
    # a great door with carved posts, shields on the wall, banners
    g.big_door(22, b - 16, 34, b, (110, 70, 40))
    for x in (20.4, 34.6):
        p.rectangle([x - 0.8, b - 18, x + 0.8, b], fill=(170, 120, 70, 255))
    for k, col in enumerate(((180, 50, 44), (60, 90, 160), (200, 160, 50), (60, 120, 70))):
        x = 9 + k * 4.4 if k < 2 else 38 + (k - 2) * 4.4
        p.ellipse([x, top + 6, x + 3.6, top + 9.6], fill=C(col), outline=(60, 40, 24, 255), width=0.4)
    for x, col in ((2, (180, 50, 44)), (57, (60, 90, 160))):
        p.line([(x, b), (x, b - 34)], fill=(90, 66, 40, 255), width=0.8)
        p.polygon([(x + 0.4, b - 33), (x + 4.6, b - 33), (x + 4.6, b - 24), (x + 2.5, b - 26), (x + 0.4, b - 24)], fill=C(col), outline=sh(C(col), 0.5), width=0.3)
    _set("glow", 28, b - 8)


def v_cathedral(g, icon):
    """A Gothic cathedral: a long nave with pointed windows and buttresses, a rose window, two spires."""
    p, b = g.p, g.b
    top = b - 26
    g.walls(14, 50, top, "stone")
    g.roof_gable(14, 50, top, 14, mat="slate")
    for x in (16, 25, 34, 43):
        p.polygon([(x, b), (x + 3, b), (x + 3, top + 6), (x + 1.5, top + 2), (x, top + 6)], fill=sh(g.wall, 0.82), outline=sh(g.wall, 0.45), width=0.4)
    for x in (20, 29, 38, 46):
        p.rectangle([x, top + 7, x + 2.6, top + 18], fill=sh(g.wall, 0.45))
        p.polygon([(x, top + 7), (x + 1.3, top + 4), (x + 2.6, top + 7)], fill=sh(g.wall, 0.45))
        p.shade([(x + 0.4, top + 7), (x + 2.2, top + 7), (x + 2.2, top + 17.6), (x + 0.4, top + 17.6)], top + 6, top + 18, (90, 70, 150, 255), (200, 120, 70, 255))
    # the west front: two towers with spires, a rose window and a pointed portal
    for tx in (2, 13):
        tt = b - 44
        tw = [(tx, b), (tx + 11, b), (tx + 11, tt), (tx, tt)]
        stone_fill(g, tw, g.wall, "stone", 1.04)
        p.polygon([(tx + 7.5, b), (tx + 11, b), (tx + 11, tt), (tx + 7.5, tt)], fill=(0, 0, 0, 50))
        p.polygon(tw, outline=sh(g.wall, 0.45), width=0.5)
        p.rectangle([tx + 4, tt + 6, tx + 7, tt + 14], fill=(36, 30, 26, 255))
        p.polygon([(tx + 4, tt + 6), (tx + 5.5, tt + 3), (tx + 7, tt + 6)], fill=(36, 30, 26, 255))
        cone(g, tx + 5.5, tt + 0.5, 6.4, 20, g.roof, "slate")
        p.line([(tx + 5.5, tt - 19.5), (tx + 5.5, tt - 24)], fill=(220, 190, 90, 255), width=0.6)
        p.line([(tx + 4, tt - 22.6), (tx + 7, tt - 22.6)], fill=(220, 190, 90, 255), width=0.6)
    p.disc(13.5, b - 26, 4.6, sh(g.wall, 0.45))
    p.disc(13.5, b - 26, 3.8, (140, 60, 120, 255))
    for k in range(8):
        a = k * math.pi / 4
        p.line([(13.5, b - 26), (13.5 + math.cos(a) * 3.6, b - 26 + math.sin(a) * 3.6)], fill=(230, 200, 90, 255), width=0.4)
    p.disc(13.5, b - 26, 1.2, (240, 210, 100, 255))
    p.rectangle([9.5, b - 14, 17.5, b], fill=sh(g.wall, 0.5))
    p.polygon([(9.5, b - 14), (13.5, b - 20), (17.5, b - 14)], fill=sh(g.wall, 0.5))
    p.rectangle([10.5, b - 13, 16.5, b], fill=(90, 56, 34, 255))
    p.polygon([(10.5, b - 13), (13.5, b - 18), (16.5, b - 13)], fill=(90, 56, 34, 255))
    p.line([(13.5, b - 17), (13.5, b)], fill=(50, 30, 18, 255), width=0.5)


def v_grand_academy(g, icon):
    """A Renaissance academy: two storeys of arched windows round a central dome with a lantern."""
    p, b = g.p, g.b
    top = b - 28
    g.walls(2, 54, top, "stone")
    deck = [(2, top), (54, top), (61, top - 5), (9, top - 5)]
    stone_fill(g, deck, g.wall, "stone", 0.62)
    p.rectangle([2, top - 1.5, 54, top], fill=sh(g.wall, 1.15))
    for x in range(4, 54, 5):
        p.rectangle([x, top - 3.4, x + 1.2, top - 1.5], fill=sh(g.wall, 1.1))
    dome(g, 28, top - 4, 13, 16, (120, 140, 120), ribs=8)
    p.rectangle([25.6, top - 25, 30.4, top - 19.5], fill=sh(g.wall, 1.1), outline=sh(g.wall, 0.5), width=0.3)
    p.polygon([(25, top - 25), (28, top - 30), (31, top - 25)], fill=(120, 140, 120, 255))
    p.disc(28, top - 31, 0.9, (220, 190, 90, 255))
    for r in range(2):
        for x in (5, 11, 17, 37, 43, 49):
            y = top + 4 + r * 12
            p.rectangle([x - 0.2, y + 1.5, x + 3.2, y + 8], fill=sh(g.wall, 0.45))
            p.pieslice([x - 0.2, y, x + 3.2, y + 3.4], 180, 360, fill=sh(g.wall, 0.45))
            g._glass(x + 0.3, y + 1.6, 2.4, 6, r == 1 and x == 11)
    # the portal with paired columns and a pediment
    p.rectangle([20, top + 2, 36, b], fill=sh(g.wall, 1.1))
    p.polygon([(19, top + 2), (37, top + 2), (28, top - 2.6)], fill=sh(g.wall, 1.15), outline=sh(g.wall, 0.5), width=0.4)
    g.door(25, 6, 12, arch=True)
    for x in (20.6, 23, 32, 34.4):
        p.rectangle([x, top + 3, x + 1.4, b - 1], fill=(240, 236, 226, 255))
    for k in range(3):
        p.rectangle([19 - k, b - 1.2 + k * 0.5, 37 + k, b - 0.6 + k * 0.5], fill=(200, 196, 186, 255))


def v_observatory(g, icon):
    """An observatory: a domed tower with the shutter open and a long telescope, beside a brick wing."""
    p, b = g.p, g.b
    top = b - 20
    g.walls(28, 58, top, "brick")
    g.roof_gable(28, 58, top, 9, mat="slate")
    for x in (32, 40, 48):
        g.window(x, top + 5, 4, 7, lit=x == 40)
    g.door(52, 5, 10)
    # the round tower and its turning dome
    tx0, tx1 = 6, 28
    tower = [(tx0, b), (tx1, b), (tx1, b - 36), (tx0, b - 36)]
    stone_fill(g, tower, g.wall, "stone", 1.02)
    p.polygon([(18, b), (tx1, b), (tx1, b - 36), (18, b - 36)], fill=(0, 0, 0, 55))
    p.polygon([(tx0, b), (tx0 + 3, b), (tx0 + 3, b - 36), (tx0, b - 36)], fill=(255, 255, 255, 30))
    p.polygon(tower, outline=sh(g.wall, 0.45), width=0.5)
    for y in (b - 12, b - 24):
        p.line([(tx0, y), (tx1, y)], fill=sh(g.wall, 0.7), width=0.6)
        g.window(15, y + 3, 4, 6)
    g.door(14, 6, 10, arch=True)
    p.rectangle([tx0 - 1, b - 37.5, tx1 + 1, b - 35.5], fill=sh(g.wall, 1.15))
    dome(g, 17, b - 37, 12, 12, (150, 160, 170), ribs=8, tex="stone")
    p.polygon([(15.5, b - 48.5), (19, b - 48.5), (19.6, b - 37.5), (15, b - 37.5)], fill=(30, 30, 40, 255))
    p.line([(17, b - 41), (30, b - 58)], fill=(150, 120, 60, 255), width=2.2)
    p.line([(29, b - 56.6), (31, b - 59.4)], fill=(90, 70, 40, 255), width=2.8)
    p.line([(17.6, b - 41.6), (29.6, b - 57.6)], fill=(220, 190, 110, 255), width=0.5)
    # a few stars painted on a banner? no: a brass armillary sphere in front
    cx, cy = 40, b - 4
    p.line([(cx, b), (cx, cy)], fill=(120, 100, 60, 255), width=0.8)
    p.ellipse([cx - 4, cy - 8, cx + 4, cy], outline=(210, 170, 70, 255), width=0.6)
    p.ellipse([cx - 4, cy - 5.6, cx + 4, cy - 2.4], outline=(210, 170, 70, 255), width=0.5)
    p.ellipse([cx - 1.6, cy - 8, cx + 1.6, cy], outline=(210, 170, 70, 255), width=0.5)


def v_exhibition_palace(g, icon):
    """A palace of iron and glass: a long glass hall with a barrel-vaulted transept and flags."""
    p, b = g.p, g.b
    glass_hi = (190, 220, 232)
    frame = (70, 84, 96, 255)
    # the long hall: glass walls in an iron grid
    x0, x1, top = 2, 60, b - 18
    hall = [(x0, b), (x1, b), (x1, top), (x0, top)]
    p.shade(hall, top, b, (176, 210, 226, 255), (120, 160, 186, 255))
    for x in range(x0, x1 + 1, 4):
        p.line([(x, top), (x, b)], fill=frame, width=0.6)
    for y in (top + 6, top + 12):
        p.line([(x0, y), (x1, y)], fill=frame, width=0.5)
    p.polygon(hall, outline=frame, width=0.7)
    # stepped glass roof of the hall
    roof = [(x0 - 1, top), (x1 + 1, top), (x1 - 3, top - 6), (x0 + 3, top - 6)]
    p.polygon(roof, fill=(150, 190, 210, 255))
    p.shade(roof, top - 6, top, (220, 240, 250, 200), (120, 160, 186, 60))
    for x in range(x0 + 3, x1 - 2, 4):
        p.line([(x, top - 6), (x - 2.4, top)], fill=frame, width=0.4)
    p.polygon(roof, outline=frame, width=0.5)
    # the transept: a tall barrel vault in the middle
    cx = 31
    tw = [(cx - 10, b), (cx + 10, b), (cx + 10, top - 12), (cx - 10, top - 12)]
    p.shade(tw, top - 12, b, (190, 222, 236, 255), (130, 170, 194, 255))
    for x in range(cx - 10, cx + 11, 3):
        p.line([(x, top - 12), (x, b)], fill=frame, width=0.5)
    p.pieslice([cx - 10, top - 23, cx + 10, top - 1], 180, 360, fill=(170, 206, 224, 255), outline=frame, width=0.7)
    for k in range(1, 6):
        a = math.pi + k * math.pi / 6
        p.line([(cx, top - 12), (cx + math.cos(a) * 10, top - 12 + math.sin(a) * 11)], fill=frame, width=0.5)
    p.arc([cx - 7, top - 20, cx + 7, top - 4], 200, 260, fill=(255, 255, 255, 220), width=0.6)
    p.polygon(tw, outline=frame, width=0.7)
    # the doors and flags of many nations
    p.rectangle([cx - 3, b - 9, cx + 3, b], fill=(50, 60, 70, 255))
    p.pieslice([cx - 3, b - 12, cx + 3, b - 6], 180, 360, fill=(50, 60, 70, 255))
    for k, col in enumerate(((200, 60, 50), (60, 90, 170), (230, 200, 60), (60, 140, 80), (240, 240, 240))):
        x = 6 + k * 12 if k < 2 else 40 + (k - 2) * 8
        if k == 4:
            x = cx - 0.5
        y = top - 6 if k != 4 else top - 23
        p.line([(x, y), (x, y - 8)], fill=(60, 60, 64, 255), width=0.5)
        p.polygon([(x + 0.3, y - 8), (x + 5, y - 7), (x + 0.3, y - 5.4)], fill=C(col))


# ------------------------------------------------------------------ luxuries (build 46)
def v_mulberry_grove(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 36, 58, 15, "timber", 10, roof="thatch")
    g.door(40, 6, 9)
    g.sign(48, top + 2, icon)
    # mulberry trees and trays of cocoons on a rack
    tree(g, 8, b, 6.5, (70, 40, 90), 7, (66, 116, 52))
    tree(g, 22, b - 3, 7.0, (70, 40, 90), 8, (60, 110, 48))
    for k in range(2):
        y = b - 3 - k * 4
        wood_fill(g, [(26, y), (36, y), (36, y - 1.2), (26, y - 1.2)], (150, 112, 70), 2, False, 0.3)
        for j in range(5):
            p.ellipse([26.6 + j * 1.9, y - 2.6, 28.2 + j * 1.9, y - 1.2], fill=(246, 240, 220, 255), outline=(190, 180, 150, 255), width=0.2)
    for x in (26.4, 35.4):
        p.line([(x, b), (x, b - 8)], fill=C(mt.WOOD), width=0.6)


def v_silk_weaver(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 24, 54, 22, "timber", 12)
    g.door(27, 7, 11)
    g.window(38, top + 4, 9, 6, lit=True)
    g.sign(40, b - 12, icon)
    # lengths of dyed silk drying on a frame, a basket of cocoons
    for x in (2, 21):
        p.line([(x, b), (x, b - 25)], fill=C(mt.WOOD), width=0.9)
    p.line([(1, b - 24), (22, b - 24)], fill=C(mt.WOOD), width=0.9)
    for k, col in enumerate(((200, 60, 130), (230, 180, 60), (90, 60, 170), (60, 160, 160))):
        cloth(g, 3.2 + k * 4.5, b - 24, 3.6, 15 + (k % 2) * 3, col)
        p.line([(3.6 + k * 4.5, b - 23), (4.4 + k * 4.5, b - 10)], fill=(255, 255, 255, 120), width=0.4)
    p.polygon([(14, b - 4), (21, b - 4), (20.2, b), (14.8, b)], fill=(180, 140, 80, 255), outline=(110, 80, 40, 255), width=0.3)
    for j in range(4):
        p.ellipse([14.4 + j * 1.6, b - 5.4, 16 + j * 1.6, b - 3.8], fill=(246, 240, 220, 255))


def v_pepper_garden(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 38, 58, 15, "planks", 10, roof="thatch")
    g.door(42, 6, 9)
    g.sign(49, top + 2, icon)
    # pepper vines on poles with red berries, saffron beds, drying mats
    rnd = random.Random(9)
    for r in range(3):
        y = b - 18 + r * 6.5
        for k in range(5):
            x = 3 + k * 6.6 + r * 1.2
            p.line([(x, y + 3), (x, y - 6)], fill=(130, 100, 60, 255), width=0.5)
            for j in range(5):
                p.disc(x + rnd.uniform(-1.6, 1.6), y - 4 + j * 1.6, 1.0, (70 + rnd.randint(0, 30), 120, 50, 255))
            for j in range(3):
                p.disc(x + rnd.uniform(-1.2, 1.2), y - 3 + rnd.uniform(0, 5), 0.6, (200, 50, 40, 255))
    for k in range(6):
        p.disc(4 + k * 5, b + 0.5, 1.1, (150, 110, 200, 255))
        p.point((4 + k * 5, b + 0.5), fill=(230, 120, 40, 255))
    p.polygon([(26, b - 2), (36, b - 2), (37, b), (25, b)], fill=(190, 160, 100, 255))
    for j in range(8):
        p.disc(26.6 + j * 1.2, b - 1.2, 0.5, (70, 40, 30, 255))


def v_spice_mill(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 18, 48, 20, "timber", 12)
    g.door(22, 7, 11)
    g.window(38, top + 5, lit=True)
    g.sign(30, top + 3, icon)
    # a horse-turned millstone and jars and sacks of spices
    p.ellipse([1, b - 4, 15, b + 1], fill=(140, 136, 126, 255), outline=(80, 76, 70, 255), width=0.4)
    p.ellipse([4, b - 7, 12, b - 2], fill=(170, 166, 156, 255), outline=(90, 86, 80, 255), width=0.4)
    p.line([(8, b - 6), (8, b - 12)], fill=C(mt.WOOD), width=1.0)
    p.line([(8, b - 11), (16, b - 7)], fill=C(mt.WOOD), width=0.8)
    for k, col in enumerate(((216, 120, 42), (190, 50, 40), (230, 190, 60), (120, 80, 50))):
        x = 50 + (k % 2) * 6
        y = b - (k // 2) * 6
        p.rounded_rectangle([x, y - 5, x + 4.4, y], 1.2, fill=(180, 120, 80, 255), outline=(110, 70, 40, 255), width=0.3)
        p.ellipse([x + 0.4, y - 5.8, x + 4, y - 4.2], fill=C(col))


def v_kaolin_pit(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 38, 56, 14, "planks", 9)
    g.door(42, 6, 9)
    g.sign(48, top + 2, icon)
    p.ellipse([0, b - 12, 34, b + 1], fill=(214, 208, 196, 255))
    p.ellipse([3, b - 10.4, 31, b - 0.6], fill=(188, 182, 170, 255))
    p.ellipse([7, b - 8, 27, b - 2], fill=(236, 232, 224, 255))
    p.arc([3, b - 10.4, 31, b - 0.6], 190, 350, fill=(246, 244, 238, 255), width=0.5)
    heap(g, 26, 38, b, 6, (240, 238, 232), mat=None)
    p.line([(18, b - 6), (22, b - 16)], fill=(150, 112, 70, 255), width=0.7)
    p.polygon([(16.6, b - 6.6), (19.4, b - 6.2), (18.8, b - 2.6), (16.8, b - 3)], fill=(150, 150, 156, 255))


def v_porcelain_kiln(g, icon):
    p, b = g.p, g.b
    # a white bottle kiln and a shelf of blue-and-white ware
    pts = [(4, b), (28, b), (25, b - 14), (19, b - 26), (18.6, b - 40), (13.4, b - 40), (13, b - 26), (7, b - 14)]
    stone_fill(g, pts, (214, 206, 190), "brick")
    p.polygon([(16, b), (28, b), (25, b - 14), (19, b - 26), (18.6, b - 40), (16, b - 40)], fill=(0, 0, 0, 45))
    p.polygon(pts, outline=(130, 120, 104, 255), width=0.5)
    p.rectangle([12.6, b - 41.4, 19.4, b - 40], fill=(90, 86, 80, 255))
    glow_hole(g, 13, b - 7, 19, b)
    _set("glow", 16, b - 3.5)
    _set("smoke", 16, b - 43)
    top, ridge = body(g, 32, 58, 16, "stone", 10)
    g.door(36, 6, 10)
    g.sign(46, top + 2, icon) if icon is not None else None
    wood_fill(g, [(30, b - 2), (62, b - 2), (62, b - 1), (30, b - 1)], (140, 100, 60), 2, False, 0.3)
    for k in range(5):
        x = 32 + k * 6
        if k % 2 == 0:
            p.polygon([(x, b - 2), (x + 3.6, b - 2), (x + 4.2, b - 5.6), (x + 3, b - 7), (x + 3, b - 8.4), (x + 0.6, b - 8.4), (x + 0.6, b - 7), (x - 0.6, b - 5.6)], fill=(246, 246, 244, 255), outline=(150, 150, 160, 255), width=0.3)
            p.line([(x + 0.4, b - 5), (x + 3.2, b - 5)], fill=(50, 80, 170, 255), width=0.6)
            p.disc(x + 1.8, b - 3.6, 0.6, (50, 80, 170, 255))
        else:
            p.pieslice([x - 0.4, b - 5.4, x + 4.4, b - 0.8], 0, 180, fill=(246, 246, 244, 255), outline=(150, 150, 160, 255), width=0.3)
            p.line([(x + 0.4, b - 3), (x + 3.6, b - 3)], fill=(50, 80, 170, 255), width=0.5)


def v_coffee_plantation(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 38, 58, 15, "planks", 10)
    g.door(42, 6, 9)
    g.sign(49, top + 2, icon)
    # rows of coffee bushes with red cherries, beans drying on a patio
    rnd = random.Random(13)
    for r in range(3):
        y = b - 17 + r * 6
        for k in range(5):
            x = 4 + k * 6.4 + r * 1.4
            for j in range(7):
                p.disc(x + rnd.uniform(-2.4, 2.4), y + rnd.uniform(-2.4, 1.6), rnd.uniform(1.0, 1.6), (40 + rnd.randint(0, 30), 96 + rnd.randint(0, 30), 46, 255))
            for j in range(4):
                p.disc(x + rnd.uniform(-2, 2), y + rnd.uniform(-1.6, 1.2), 0.6, (200, 40, 40, 255))
    patio = [(2, b + 1), (34, b + 1), (35, b - 2.4), (3, b - 2.4)]
    p.polygon(patio, fill=(196, 184, 160, 255), outline=(140, 130, 110, 255), width=0.3)
    for j in range(30):
        p.point((4 + rnd.uniform(0, 29), b - 2 + rnd.uniform(0, 2.6)), fill=(110, 60, 40, 255))


def v_coffee_roaster(g, icon):
    p, b = g.p, g.b
    top, ridge = body(g, 20, 50, 20, "brick", 12)
    chim(g, 43, ridge - 4, top - 4)
    g.door(24, 7, 11)
    g.window(36, top + 5, lit=True)
    g.sign(36, b - 12, icon) if False else g.sign(30, top + 3, icon)
    # a roasting drum turning over a fire, and sacks of beans
    p.rectangle([2, b - 4, 16, b], fill=(110, 106, 98, 255))
    glow_hole(g, 6, b - 3, 12, b, arch=False)
    _set("glow", 9, b - 2)
    drum = [(3, b - 12), (15, b - 12), (15, b - 5), (3, b - 5)]
    p.polygon(drum, fill=(70, 72, 80, 255), outline=(30, 30, 34, 255), width=0.5)
    p.shade(drum, b - 12, b - 5, (255, 255, 255, 60), (0, 0, 0, 60))
    for x in (6, 9, 12):
        p.line([(x, b - 12), (x, b - 5)], fill=(40, 40, 44, 255), width=0.4)
    p.line([(15, b - 8.5), (18, b - 8.5)], fill=(40, 40, 44, 255), width=0.8)
    p.disc(18.6, b - 8.5, 1.2, (120, 90, 50, 255))
    for x, col in ((52, (190, 160, 110)), (57, (176, 146, 100))):
        sack(g, x, b, col)
    sack(g, 54.4, b - 4.8, (200, 170, 120))


# ------------------------------------------------------------------ mines
MINE = {
    "coal_mine": {"rock": (100, 96, 90), "ore": (40, 40, 44), "glint": (90, 90, 100), "frame": True},
    "iron_mine": {"rock": (128, 112, 98), "ore": (150, 78, 54), "glint": (190, 100, 70), "veins": (160, 80, 56)},
    "gold_mine": {"rock": (126, 118, 100), "ore": (210, 172, 60), "glint": (255, 230, 110), "veins": (230, 190, 70), "sluice": True},
    "copper_mine": {"rock": (118, 110, 96), "ore": (80, 150, 120), "glint": (110, 200, 170), "veins": (90, 170, 140)},
}


def v_mine(g, icon, bid):
    p, b = g.p, g.b
    m = MINE[bid]
    rk = m["rock"]
    for poly, f in (([(1, b), (12, b - 28), (30, b - 38), (50, b - 26), (63, b)], 1.0),
                    ([(1, b), (12, b - 28), (30, b - 38), (24, b - 16)], 1.25),
                    ([(30, b - 38), (50, b - 26), (63, b), (40, b - 14)], 0.78)):
        c = sh(rk, f)[:3]
        p.polygon(poly, fill=C(c))
        g.surface(poly, "rock", c)
    if m.get("veins"):
        rnd = random.Random(len(bid))
        for k in range(7):
            x = rnd.uniform(8, 54)
            y = rnd.uniform(b - 30, b - 6)
            if 18 < x < 46 and y > b - 26:
                continue
            pts = [(x, y)]
            for j in range(3):
                pts.append((pts[-1][0] + rnd.uniform(1.4, 3.2), pts[-1][1] + rnd.uniform(-1.6, 1.6)))
            p.line(pts, fill=C(m["veins"]), width=0.7)
            p.disc(pts[1][0], pts[1][1], 0.6, C(m["glint"]))
    for (gx, gy) in ((6, b - 6), (10, b - 18), (52, b - 8), (57, b - 4), (44, b - 20)):
        for k in range(3):
            p.line([(gx, gy), (gx + (k - 1) * 0.6, gy - 1.4)], fill=(86, 120, 54, 255), width=0.35)
    p.pieslice([20, b - 24, 44, b + 2], 180, 360, fill=mt.DARK)
    p.rectangle([20, b - 11, 44, b], fill=mt.DARK)
    for x in (20, 43):
        wood_fill(g, [(x - 1, b - 13), (x + 1, b - 13), (x + 1, b), (x - 1, b)], mt.WOOD, 2.2, True, 0)
    lintel = [(18, b - 15), (46, b - 15), (46, b - 12), (18, b - 12)]
    wood_fill(g, lintel, mt.WOOD, 3.5, False, 0.5)
    p.shade([(18, b - 12), (46, b - 12), (46, b - 9), (18, b - 9)], b - 12, b - 9, (0, 0, 0, 140), (0, 0, 0, 0))
    lantern(g, 40, b - 12)
    # spoil heap of the waste rock
    heap(g, 0, 16, b + 1, 7, sh(rk, 0.85)[:3], "rock", glints=m["glint"] if bid == "coal_mine" else None)
    p.line([(24, b), (58, b)], fill=(80, 80, 84, 255), width=0.7)
    p.line([(24, b - 2), (58, b - 2)], fill=(80, 80, 84, 255), width=0.7)
    for x in range(26, 58, 4):
        p.line([(x, b - 2.4), (x + 1, b + 0.4)], fill=(100, 74, 50, 255), width=0.6)
    # the cart, heaped with this mine's ore
    p.polygon([(46, b - 8), (57, b - 8), (56, b - 3), (47, b - 3)], fill=(96, 70, 46, 255), outline=(60, 42, 26, 255), width=0.5)
    p.pieslice([46.4, b - 11.6, 56.6, b - 5], 180, 360, fill=C(m["ore"]))
    for k in range(6):
        p.disc(48 + k * 1.6, b - 8.6 - (k % 2) * 1.2, 0.8, C(m["glint"]))
    p.disc(48.5, b - 2, 1.5, mt.DARK); p.disc(54.5, b - 2, 1.5, mt.DARK)
    if m.get("frame"):
        # a winding frame over a shaft beside the adit
        for x0, x1 in ((50, 55), (60, 55)):
            p.line([(x0, b - 14), (x1, b - 40)], fill=C(mt.WOOD), width=1.0)
        p.line([(52, b - 24), (58, b - 24)], fill=C(mt.WOOD), width=0.6)
        wheel(g, 55, b - 40, 4, (70, 60, 50), 6, 0.7)
        p.line([(58.6, b - 40), (58.6, b - 16)], fill=(60, 56, 52, 255), width=0.35)
    if m.get("sluice"):
        # a wooden sluice where the gold is washed out of the gravel
        sl = [(2, b - 18), (14, b - 12), (14, b - 10), (2, b - 16)]
        wood_fill(g, sl, (150, 112, 66), 2, False, 0.4)
        p.line([(3, b - 17.2), (13.6, b - 11.4)], fill=(120, 180, 220, 255), width=0.7)
        for x in (4, 12):
            p.line([(x, b - 16 + (x - 4) * 0.5), (x, b - 7)], fill=C(mt.WOOD), width=0.6)
    if icon is not None:
        p.paste(icon, 46, b - 22, 9)


# ------------------------------------------------------------------ towers, mills, huts, forts
def v_keep(g, icon):
    p, b = g.p, g.b
    top = b - 44
    g.walls(12, 44, top, "stone")
    g.flat_top(12, 44, top)
    # buttresses, arrow slits, and conical-roofed turrets on the corners
    for x in (12, 42):
        bt = [(x - 1, b), (x + 3, b), (x + 3, b - 12), (x + 1, b - 16)]
        stone_fill(g, bt, g.wall, "stone", 0.9)
        p.polygon(bt, outline=sh(g.wall, 0.45), width=0.4)
    for x in (18, 27.5, 37):
        for y in (top + 8, top + 20):
            p.rectangle([x, y, x + 1.4, y + 5], fill=mt.DARK)
    for cx in (12.5, 44.5):
        tw = [(cx - 3, top + 4), (cx + 3, top + 4), (cx + 3, top - 6), (cx - 3, top - 6)]
        stone_fill(g, tw, g.wall, "stone", 1.05)
        p.polygon(tw, outline=sh(g.wall, 0.45), width=0.4)
        cone(g, cx, top - 6, 4.2, 9, g.roof, "slate")
    pennant(g, 31, top - 8, top - 18, (200, 60, 50))
    g.door(25, 7, 11, arch=True)


def v_watch_tower(g, icon):
    p, b = g.p, g.b
    # a timber tower on four splayed legs with braces, a hut on top and a ladder
    for x0, x1 in ((18, 22), (44, 40), (24, 26), (38, 36)):
        p.line([(x0, b), (x1, b - 34)], fill=C(sh(mt.WOOD, 1.0 if x0 in (18, 44) else 0.8)), width=1.4)
    for y0, y1 in ((b - 2, b - 16), (b - 16, b - 32)):
        f0, f1 = (b - y0) / 34 * 4, (b - y1) / 34 * 4
        p.line([(18 + f0, y0), (44 - f1, y1)], fill=C(mt.WOOD), width=0.6)
        p.line([(44 - f0, y0), (18 + f1, y1)], fill=C(mt.WOOD), width=0.6)
    p.line([(19, b - 16), (43, b - 16)], fill=C(mt.WOOD), width=0.7)
    sb = g.b
    g.b = b - 33
    g.walls(19, 41, b - 45, "planks", 5, 3.5, grass=False)
    ridge = g.roof_gable(19, 41, b - 45, 8, 5, 3.5)
    g.b = sb
    p.rectangle([23, b - 42, 37, b - 39], fill=(40, 30, 22, 255))
    wood_fill(g, [(17, b - 34), (45, b - 34), (45, b - 32), (17, b - 32)], (140, 100, 60), 2, False, 0.4)
    ladder(g, 29, b, 30, b - 32)
    pennant(g, 46, ridge + 4, ridge - 4, (200, 60, 50))


def v_paper_mill(g, icon):
    p, b = g.p, g.b
    water(g, 38, 64, b - 5, b + 3)
    top, ridge = body(g, 6, 38, 22, "timber", 11)
    # the drying loft with louvred boards
    for k in range(7):
        x = 9 + k * 4
        p.rectangle([x, top + 2, x + 2.6, top + 7], fill=(150, 114, 70, 255), outline=(80, 60, 36, 255), width=0.3)
    g.door(12, 7, 11)
    g.window(26, b - 12, 6, 6)
    g.sign(22, b - 12, icon) if False else None
    # an undershot water wheel turning in the stream
    p.rectangle([42, b - 14, 44, b - 4], fill=(90, 66, 40, 255))
    wheel(g, 51, b - 10, 10.5, (110, 80, 50), 10, 1.2)
    for k in range(10):
        a = k * math.pi / 5
        x, y = 51 + math.cos(a) * 10, b - 10 + math.sin(a) * 10
        p.line([(x, y), (51 + math.cos(a) * 12.2, b - 10 + math.sin(a) * 12.2)], fill=(130, 96, 60, 255), width=1.2)
    p.line([(38, b - 10), (51, b - 10)], fill=(70, 60, 50, 255), width=1.2)
    p.arc([40, b - 6, 62, b + 2], 200, 340, fill=(220, 240, 250, 255), width=0.5)
    # sheets drying on a line
    p.line([(1, b - 14), (6, b - 13)], fill=(220, 214, 196, 255), width=0.3)
    for k in range(2):
        p.rectangle([1.4 + k * 2.4, b - 13.6 + k * 0.4, 3.2 + k * 2.4, b - 10.6 + k * 0.4], fill=(250, 248, 240, 255), outline=(180, 176, 166, 255), width=0.2)


def v_guardhouse(g, icon):
    p, b = g.p, g.b
    # a gatehouse: two stone piers, a timber gallery with a roof over the passage
    for x0 in (8, 38):
        g.walls(x0, x0 + 14, b - 22, "stone", 5, 3.5)
    top = b - 32
    sb = g.b
    g.b = b - 22
    g.walls(6, 54, top, "timber", 5, 3.5, grass=False)
    ridge = g.roof_gable(6, 54, top, 10, 5, 3.5)
    g.b = sb
    p.rectangle([22, b - 22, 38, b], fill=(36, 30, 24, 255))
    p.pieslice([22, b - 28, 38, b - 14], 180, 360, fill=(36, 30, 24, 255))
    p.shade([(22, b - 22), (38, b - 22), (38, b), (22, b)], b - 22, b, (0, 0, 0, 0), (70, 100, 50, 120))
    for x in (10, 18, 42, 50):
        g.window(x, top + 3, 3, 4)
    for x in (12.5, 44.5):
        p.rectangle([x, b - 16, x + 1.4, b - 10], fill=mt.DARK)
    # spears in a rack by the gate, a red banner
    for k in range(3):
        x = 2 + k * 1.6
        p.line([(x, b), (x + 0.4, b - 18)], fill=(130, 96, 60, 255), width=0.5)
        p.polygon([(x - 0.1, b - 18), (x + 0.4, b - 21), (x + 0.9, b - 18)], fill=(200, 204, 214, 255))
    pennant(g, 29.5, top - 2, top - 12, (200, 60, 50))


def v_redoubt(g, icon):
    p, b = g.p, g.b
    # a square earthwork: grassy ramparts, a ditch, a palisade on top and guns in the gaps
    p.ellipse([0, b - 4, 64, b + 3], fill=(70, 96, 120, 160))
    front = [(4, b - 1), (60, b - 1), (52, b - 16), (12, b - 16)]
    p.polygon(front, fill=(110, 140, 70, 255))
    g.surface(front, "rock", (110, 140, 70))
    p.shade(front, b - 16, b - 1, (255, 255, 255, 30), (0, 0, 0, 40))
    rnd = random.Random(4)
    for k in range(40):
        x = rnd.uniform(8, 56)
        y = rnd.uniform(b - 15, b - 2)
        p.line([(x, y), (x + rnd.uniform(-0.5, 0.5), y - 1.2)], fill=(80, 116, 50, 255), width=0.35)
    top = [(12, b - 16), (52, b - 16), (56, b - 20), (16, b - 20)]
    p.polygon(top, fill=(130, 110, 74, 255))
    for x in range(13, 52, 2):
        if 24 < x < 30 or 36 < x < 42:
            continue
        h = 6 + (x * 7) % 3
        st = [(x, b - 16), (x, b - 16 - h + 1.2), (x + 0.9, b - 16 - h), (x + 1.8, b - 16 - h + 1.2), (x + 1.8, b - 16)]
        p.polygon(st, fill=C(sh(mt.WOOD, 0.95 + (x % 3) * 0.06)), outline=C(sh(mt.WOOD, 0.55)), width=0.3)
    for cx in (27, 39):
        p.ellipse([cx - 2.6, b - 20, cx + 1.4, b - 16.4], fill=(60, 44, 28, 255))
        p.line([(cx, b - 18.6), (cx + 1.4, b - 13)], fill=(30, 30, 34, 255), width=2.0)
    pennant(g, 33, b - 22, b - 34, (200, 60, 50))
    p.rectangle([29, b - 7, 35, b - 1], fill=(48, 36, 24, 255))


VARIANTS = {
    "sawmill": v_sawmill, "bakery": v_bakery, "brewery": v_brewery, "mint": v_mint, "toolsmith": v_toolsmith,
    "weaponsmith": v_weaponsmith, "bowyer": v_bowyer, "armorer": v_armorer, "tannery": v_tannery, "weaver": v_weaver,
    "tailor": v_tailor, "linen_weaver": v_linen_weaver, "furrier": v_furrier, "jeweller": v_jeweller,
    "carpenter": v_carpenter, "apothecary": v_apothecary, "bathhouse": v_bathhouse, "tavern": v_tavern,
    "fire_station": v_fire_station, "machine_works": v_machine_works, "textile_mill": v_textile_mill,
    "warehouse": v_warehouse, "cart_yard": v_cart_yard, "cheesery": v_cheesery, "butcher": v_butcher,
    "winery": v_winery, "chandler": v_chandler, "shipyard": v_shipyard,
    "orchard": v_orchard, "hop_farm": v_hop_farm, "sheep_farm": v_sheep_farm, "pig_farm": v_pig_farm,
    "flax_farm": v_flax_farm, "storehouse": v_storehouse, "mule_station": v_mule_station, "dairy": v_dairy,
    "vineyard": v_vineyard, "donkey_farm": v_donkey_farm,
    "woodcutter": v_woodcutter, "forester": v_forester, "clay_pit": v_clay_pit, "saltworks": v_saltworks,
    "hunter": v_hunter, "herb_garden": v_herb_garden, "scout_lodge": v_scout_lodge, "sand_pit": v_sand_pit,
    "apiary": v_apiary,
    "charcoal_burner": v_charcoal_burner, "smokehouse": v_smokehouse, "iron_smelter": v_iron_smelter,
    "copper_smelter": v_copper_smelter, "steelworks": v_steelworks, "glassworks": v_glassworks,
    "lodge": v_lodge, "infirmary": v_infirmary, "chapel": v_chapel, "scriptorium": v_scriptorium, "library": v_library,
    "manor": v_manor, "university": v_university, "fortress": v_fortress, "depot": v_depot,
    "great_hall": v_great_hall, "cathedral": v_cathedral, "grand_academy": v_grand_academy,
    "observatory": v_observatory, "exhibition_palace": v_exhibition_palace,
    "mulberry_grove": v_mulberry_grove, "silk_weaver": v_silk_weaver, "pepper_garden": v_pepper_garden,
    "spice_mill": v_spice_mill, "kaolin_pit": v_kaolin_pit, "porcelain_kiln": v_porcelain_kiln,
    "coffee_plantation": v_coffee_plantation, "coffee_roaster": v_coffee_roaster,
    "keep": v_keep, "watch_tower": v_watch_tower, "paper_mill": v_paper_mill, "guardhouse": v_guardhouse,
    "redoubt": v_redoubt,
}


def draw(m, g, bid, icon):
    global mt, _cur
    mt = m
    if bid in MINE:
        fn = lambda g, icon: v_mine(g, icon, bid)
    elif bid in VARIANTS:
        fn = VARIANTS[bid]
    else:
        return False
    random.seed(sum(map(ord, bid)) * 131)
    _cur = bid
    ANCH.setdefault(bid, {})["_wh"] = (g.W, g.H)
    pen = g.p
    g.p = BlendPen(pen)
    try:
        fn(g, icon)
    finally:
        g.p = pen
        _cur = None
    return True


def write_anchors(path):
    """Puts where each drawn building's smoke, glow and wheel are into buildings.json ("art"), as
    fractions of the picture, so the game draws them in the right place. Returns True if it changed."""
    import json
    text = open(path).read()
    data = json.loads(text)
    for bid, a in ANCH.items():
        art = data.get(bid, {}).get("art")
        if art is None:
            continue
        W, H = a["_wh"]
        for key in ("smoke", "glow"):
            art[key] = [round(a[key][0] / W, 3), round(a[key][1] / H, 3)] if key in a else []
        if art.get("style") == "mill" and bid != "mill":
            art["hub"] = []
    out = json.dumps(data, indent=1)
    if out != text:
        open(path, "w").write(out)
        return True
    return False
