#!/usr/bin/env python3
"""Build 66.1: the tool and weapon icons in each metal, and a small badge for each metal.

The iron look is the icon as drawn (grey); bronze and steel recolour its grey metal parts (pixels with
little colour and some light): bronze to a warm gold-brown, steel to a cool blue-white with a brighter
shine. Wood, leather, cloth and the bow's string keep their colours. Writes
textures/res_<id>_bronze.png and res_<id>_steel.png (iron stays res_<id>.png), and
textures/metal_bronze.png, metal_iron.png, metal_steel.png (a small ingot, 32 px).
python3 tools/make_metal_icons.py
"""
import colorsys, os
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(__file__), "..", "textures")
# the goods made of metal whose grey parts are the metal (quills, harnesses and bows keep their look:
# only the badge tells their metal)
METAL = ["axes", "pickaxes", "farm_tools", "knives", "saws", "tongs", "trowels", "shears", "chisels", "weapons"]
# (dark, light) of each metal's ramp
RAMP = {
    "bronze": ((92, 52, 18), (246, 196, 112)),
    "steel": ((44, 62, 88), (226, 240, 255)),
}
BADGE = {"bronze": (196, 132, 58), "iron": (150, 158, 168), "steel": (110, 160, 214)}


def recolour(im, metal):
    lo, hi = RAMP[metal]
    out = im.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if s < 0.2 and v > 0.3:
                t = min(1.0, max(0.0, (v - 0.3) / 0.7))
                if metal == "steel":
                    t = min(1.0, t * 1.08)
                c = tuple(int(lo[i] + (hi[i] - lo[i]) * t) for i in range(3))
                px[x, y] = (c[0], c[1], c[2], a)
    return out


def badge(metal):
    S = 32
    im = Image.new("RGBA", (S * 4, S * 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    base = BADGE[metal]
    dark = tuple(int(c * 0.55) for c in base)
    light = tuple(min(255, int(c * 1.35 + 30)) for c in base)
    # an ingot seen from the side: a trapezoid with a lit top
    d.polygon([(10, 100), (118, 100), (100, 44), (28, 44)], fill=base + (255,), outline=dark + (255,), width=6)
    d.polygon([(28, 44), (100, 44), (92, 30), (36, 30)], fill=light + (255,), outline=dark + (255,), width=5)
    d.line([(36, 58), (84, 58)], fill=light + (200,), width=6)
    return im.resize((S, S), Image.LANCZOS)


def main():
    n = 0
    for rid in METAL:
        src = os.path.join(ROOT, "res_%s.png" % rid)
        if not os.path.exists(src):
            continue
        im = Image.open(src).convert("RGBA")
        for metal in ("bronze", "steel"):
            recolour(im, metal).save(os.path.join(ROOT, "res_%s_%s.png" % (rid, metal)))
            n += 1
    for metal in BADGE:
        badge(metal).save(os.path.join(ROOT, "metal_%s.png" % metal))
        n += 1
    print("metal icons:", n)


if __name__ == "__main__":
    main()
