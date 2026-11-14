"""Surface textures for the building pictures (used by make_textures.py).

Each function returns an RGBA picture (PIL) of w x h canvas pixels, where one design pixel is f canvas
pixels (the building pictures are drawn on a canvas several times larger than they come out, then
shrunk, so these can hold detail finer than a design pixel). Light comes from the upper left, as in
the rest of the game: the top and left edge of a stone, brick or tile is lit, the lower and right one
in shade. Every texture is made from a seed, so a building looks the same each time it is made.
"""
import numpy as np
from PIL import Image


def _rgb(c):
    return np.array(c[:3], np.float32)


def _img(arr, alpha=None):
    a = np.clip(arr, 0, 255).astype(np.uint8)
    h, w = a.shape[:2]
    al = np.full((h, w, 1), 255, np.uint8) if alpha is None else np.clip(alpha, 0, 255).astype(np.uint8)[..., None]
    return Image.fromarray(np.concatenate([a, al], 2), "RGBA")


def _noise(h, w, cell, rnd):
    """Smooth value noise, cell canvas pixels across."""
    gh, gw = h // cell + 2, w // cell + 2
    g = rnd.random((gh, gw))
    ys = np.arange(h) / cell
    xs = np.arange(w) / cell
    y0 = np.floor(ys).astype(int); x0 = np.floor(xs).astype(int)
    fy = ys - y0; fx = xs - x0
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    a = g[y0][:, x0] * (1 - fx) + g[y0][:, x0 + 1] * fx
    b = g[y0 + 1][:, x0] * (1 - fx) + g[y0 + 1][:, x0 + 1] * fx
    return a * (1 - fy)[:, None] + b * fy[:, None]


def _fbm(h, w, f, rnd, cells=(6, 3, 1.5)):
    return sum(_noise(h, w, max(2, int(c * f)), rnd) * wt for c, wt in zip(cells, (0.5, 0.3, 0.2)))


def _bevel(local_x, local_y, bw, bh, edge):
    """Light on the top/left rim of a block, shade on the bottom/right rim (edge: rim width)."""
    top = np.clip(1 - local_y / edge, 0, 1)
    left = np.clip(1 - local_x / edge, 0, 1)
    bot = np.clip(1 - (bh - local_y) / edge, 0, 1)
    right = np.clip(1 - (bw - local_x) / edge, 0, 1)
    return 1 + 0.16 * np.maximum(top, left) - 0.22 * np.maximum(bot, right)


def blocks(w, h, f, base, seed, row=4.0, wmin=4.0, wmax=7.0, mortar=0.55, rough=1.0, moss=0.0, brick=False):
    """Masonry: rows of blocks (row design pixels high, wmin..wmax wide), each its own tone, bevelled,
    in mortar. brick: even bricks in a running bond. moss: greenish tint creeping up from the foot."""
    rnd = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    rh = row * f
    r = np.floor(yy / rh).astype(int)
    ly = yy - r * rh
    nrows = int(h / rh) + 2
    # each row: its block edges
    bid = np.zeros((h, w), np.int64)
    lx = np.zeros((h, w), np.float32)
    bw_ = np.zeros((h, w), np.float32)
    for k in range(nrows):
        m = r == k
        if not m.any():
            continue
        if brick:
            bw = wmin * f
            off = (k % 2) * bw / 2
            edges = np.arange(-bw + off, w + bw, bw)
        else:
            edges = [-rnd.uniform(0, wmax * f)]
            while edges[-1] < w + wmax * f:
                edges.append(edges[-1] + rnd.uniform(wmin, wmax) * f)
            edges = np.array(edges)
        xs = xx[m]
        j = np.searchsorted(edges, xs, side="right") - 1
        bid[m] = k * 1000 + j
        lx[m] = xs - edges[j]
        bw_[m] = (edges[np.minimum(j + 1, len(edges) - 1)] - edges[j])
    tone = np.random.default_rng(seed + 1).random(int(bid.max()) + 1)
    t = tone[bid] * 2 - 1
    col = _rgb(base)[None, None, :] * (1 + t[..., None] * (0.07 if brick else 0.11))
    # a little hue shift per block (warmer and cooler stones)
    col[..., 0] *= 1 + t * 0.03
    col[..., 2] *= 1 - t * 0.03
    grain = (_fbm(h, w, f, rnd, (1.5, 0.7, 0.35)) - 0.5) * 0.18 * rough
    sh = _bevel(lx, ly, bw_, rh, max(1.0, 0.7 * f)) + grain
    col = col * sh[..., None]
    # mortar joints
    mw = mortar * f / 2
    joint = (ly < mw) | (ly > rh - mw) | (lx < mw) | (lx > bw_ - mw)
    mcol = _rgb(base) * (1.18 if brick else 0.62)
    col[joint] = mcol * (0.9 + 0.1 * rnd.random((int(joint.sum()), 1)))
    # chips and pits
    pits = (_noise(h, w, max(2, int(f * 0.6)), rnd) > 0.86) & ~joint
    col[pits] *= 0.82
    if moss > 0:
        mm = np.clip((yy / h - (1 - moss)) / moss, 0, 1) * (_noise(h, w, max(2, int(2 * f)), rnd) > 0.45)
        green = np.array([92, 118, 60], np.float32)
        col = col * (1 - mm[..., None] * 0.45) + green * mm[..., None] * 0.45
    return _img(col)


def plaster(w, h, f, base, seed, stains=True):
    """Lime plaster: soft mottling, a few hairline cracks, rain streaks running down."""
    rnd = np.random.default_rng(seed)
    col = _rgb(base)[None, None, :] * (1 + (_fbm(h, w, f, rnd, (8, 3, 1)) - 0.5) * 0.12)[..., None]
    col *= (1 + (rnd.random((h, w)) - 0.5) * 0.05)[..., None]
    if stains:
        xs = np.arange(w)
        streak = np.zeros(w, np.float32)
        for _ in range(max(1, w // int(9 * f))):
            c = rnd.uniform(0, w)
            streak += np.exp(-((xs - c) / (rnd.uniform(0.6, 1.6) * f)) ** 2) * rnd.uniform(0.04, 0.1)
        fall = np.clip(1 - np.arange(h) / (h * rnd.uniform(0.5, 0.9)), 0, 1)
        col *= (1 - streak[None, :] * fall[:, None])[..., None]
        # grime at the foot
        foot = np.clip((np.arange(h) / h - 0.78) / 0.22, 0, 1)
        col *= (1 - 0.12 * foot)[:, None, None]
    for _ in range(max(0, int(w * h / (f * f * 600)))):
        x, y = rnd.uniform(0, w), rnd.uniform(0, h * 0.8)
        for _ in range(int(rnd.uniform(3, 7) * f)):
            xi, yi = int(x), int(y)
            if 0 <= xi < w and 0 <= yi < h:
                col[yi, xi] *= 0.82
            x += rnd.uniform(-0.6, 0.6); y += rnd.uniform(0.3, 1.0)
    return _img(col)


def wood(w, h, f, base, seed, board=3.0, vertical=True, gap=0.35):
    """Boards: each its own tone, wavy grain along it, knots, dark gaps between them."""
    rnd = np.random.default_rng(seed)
    if not vertical:
        w, h = h, w
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    bw = board * f
    k = np.floor(xx / bw).astype(int)
    lx = xx - k * bw
    tone = rnd.random(k.max() + 2) * 2 - 1
    t = tone[k]
    wav = _noise(h, w, max(2, int(6 * f)), rnd) * 3 * f
    grain = np.sin((xx + wav) / (0.45 * f) + k * 1.7) * 0.5 + 0.5
    g2 = _noise(h, w, max(2, int(0.5 * f)), rnd)
    col = _rgb(base)[None, None, :] * (1 + t[..., None] * 0.1 - 0.12 * grain[..., None] * (0.5 + g2[..., None]))
    # rounded board: lit left edge, shaded right edge
    col *= (1 + 0.12 * np.clip(1 - lx / (0.6 * f), 0, 1) - 0.18 * np.clip(1 - (bw - lx) / (0.7 * f), 0, 1))[..., None]
    col[lx < gap * f] *= 0.45
    for _ in range(max(1, int(w * h / (f * f * 220)))):
        cx, cy = rnd.uniform(0, w), rnd.uniform(0, h)
        r = rnd.uniform(0.35, 0.6) * f
        d = ((xx - cx) / r) ** 2 + ((yy - cy) / (r * 1.6)) ** 2
        col[d < 1] *= 0.72
    im = _img(col)
    return im if vertical else im.transpose(Image.Transpose.ROTATE_90)


def roof_tiles(w, h, f, base, seed, row=2.6, tile=2.4):
    """Clay tiles in rows (roof space: rows across, the ridge at the top): each tile curved, lit down
    its middle, its lower edge scalloped, casting a shadow on the row below; tones vary tile by tile."""
    rnd = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    rh = row * f
    tw = tile * f
    r = np.floor(yy / rh).astype(int)
    ly = (yy - r * rh) / rh
    xo = xx + (r % 2) * tw / 2
    c = np.floor(xo / tw).astype(int)
    lx = (xo - c * tw) / tw
    tone = np.random.default_rng(seed + 3).random((r.max() + 2, c.max() + 2)) * 2 - 1
    t = tone[r, c]
    curve = np.cos((lx - 0.5) * np.pi) ** 0.8
    f_ = 0.82 + 0.3 * curve + 0.12 * ly
    # the shadow of the row above along the top of each row (the row above overlaps)
    f_ *= 1 - 0.38 * np.clip(1 - ly / 0.28, 0, 1)
    # scalloped lower edge: the gap between two tiles is darker
    f_ *= 1 - 0.32 * np.clip(1 - curve / 0.25, 0, 1) * (ly > 0.35)
    col = _rgb(base)[None, None, :] * (f_ * (1 + t * 0.09))[..., None]
    col[..., 1] *= 1 + t * 0.03
    lich = (_noise(h, w, max(2, int(3 * f)), rnd) > 0.8) * (rnd.random((h, w)) > 0.4)
    col[lich] = col[lich] * 0.75 + np.array([120, 126, 84], np.float32) * 0.25
    return _img(col)


def slates(w, h, f, base, seed, row=2.2, tile=3.0):
    """Slates: staggered rectangles, a lit lower edge and a dark gap, bluish tones varying."""
    rnd = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    rh = row * f
    tw = tile * f
    r = np.floor(yy / rh).astype(int)
    ly = (yy - r * rh) / rh
    xo = xx + (r % 2) * tw / 2 + (r % 3) * tw * 0.17
    c = np.floor(xo / tw).astype(int)
    lx = (xo - c * tw) / tw
    t = (np.random.default_rng(seed + 5).random((r.max() + 2, c.max() + 2)) * 2 - 1)[r, c]
    f_ = 0.9 + 0.14 * ly - 0.3 * np.clip(1 - ly / 0.2, 0, 1)
    f_ *= 1 - 0.35 * ((lx < 0.06) | (lx > 0.96))
    col = _rgb(base)[None, None, :] * (f_ * (1 + t * 0.12))[..., None]
    col[..., 2] *= 1 + t * 0.04
    col *= (1 + (rnd.random((h, w)) - 0.5) * 0.05)[..., None]
    return _img(col)


def thatch(w, h, f, base, seed, layer=3.0):
    """Thatch: layers of straw (each a band of fine streaks running down the roof), shade under each
    layer's edge, the odd mossy patch."""
    rnd = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    lh = layer * f
    band = np.floor(yy / lh).astype(int)
    ly = (yy - band * lh) / lh
    # streaks: noise squeezed across, stretched down
    st = np.zeros((h, w), np.float32)
    for cell, wt in ((0.35, 0.5), (0.7, 0.3), (1.4, 0.2)):
        n = _noise(max(4, h // 6) + 4, w, max(2, int(cell * f)), rnd)
        st += np.repeat(n, 6, axis=0)[:h] * wt
    f_ = 0.78 + 0.4 * st + 0.2 * ly - 0.3 * np.clip(1 - ly / 0.3, 0, 1)
    col = _rgb(base)[None, None, :] * f_[..., None]
    moss = (_noise(h, w, max(2, int(1.5 * f)), rnd) > 0.84) & (rnd.random((h, w)) > 0.3)
    col[moss] = col[moss] * 0.78 + np.array([104, 118, 70], np.float32) * 0.22
    return _img(col)


def rock(w, h, f, base, seed):
    """Rough rock (spoil heaps, mountain sides): lumpy relief lit from the upper left, cracks."""
    rnd = np.random.default_rng(seed)
    hgt = _fbm(h, w, f, rnd, (6, 2.5, 1.0))
    gx = np.gradient(hgt, axis=1) * f
    gy = np.gradient(hgt, axis=0) * f
    light = np.clip(-(gx * -0.6 + gy * -0.8) * 6, -1, 1)
    col = _rgb(base)[None, None, :] * (1 + light * 0.28 + (rnd.random((h, w)) - 0.5) * 0.06)[..., None]
    # a few short cracks
    for _ in range(max(1, int(w * h / (f * f * 160)))):
        x, y = rnd.uniform(0, w), rnd.uniform(0, h)
        for _ in range(int(rnd.uniform(2, 5) * f)):
            xi, yi = int(x), int(y)
            if 0 <= xi < w - 1 and 0 <= yi < h:
                col[yi, xi] *= 0.6
                col[yi, xi + 1] *= 1.12
            x += rnd.uniform(-0.8, 0.8); y += rnd.uniform(0.2, 1.0)
    return _img(col)
