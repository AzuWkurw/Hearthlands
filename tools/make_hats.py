#!/usr/bin/env python3
"""The hats people wear in each age (build 63), drawn over workers, porters and townsfolk:
textures/unit_hat_e0.png .. unit_hat_e5.png, 64x40 each, the hat's brim at the bottom.

    python3 tools/make_hats.py

e0 Roman: a laurel band   e1 Medieval: a hood          e2 Renaissance: a beret with a feather
e3 Reason: a tricorn      e4 Industry: a top hat        e5 Modern: a flat cap
"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 64, 40


def img():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def outline(d, pts, fill, line=(30, 24, 18, 255)):
    d.polygon(pts, fill=fill, outline=line)


def laurel():
    im = img(); d = ImageDraw.Draw(im)
    d.arc((14, 18, 50, 46), 200, 340, fill=(70, 120, 40, 255), width=5)
    for x in range(18, 48, 6):
        d.ellipse((x, 24 + abs(32 - x) // 5 - 4, x + 6, 24 + abs(32 - x) // 5 + 1), fill=(96, 150, 56, 255))
    return im


def hood():
    im = img(); d = ImageDraw.Draw(im)
    outline(d, [(14, 39), (18, 16), (32, 4), (46, 16), (50, 39), (42, 39), (40, 24), (24, 24), (22, 39)], (118, 82, 50, 255))
    return im


def beret():
    im = img(); d = ImageDraw.Draw(im)
    d.ellipse((10, 18, 54, 38), fill=(120, 30, 46, 255), outline=(40, 16, 20, 255))
    d.line((40, 22, 58, 2), fill=(240, 236, 220, 255), width=4)
    d.line((44, 16, 54, 6), fill=(200, 196, 180, 255), width=2)
    return im


def tricorn():
    im = img(); d = ImageDraw.Draw(im)
    outline(d, [(4, 36), (16, 20), (32, 14), (48, 20), (60, 36), (32, 30)], (36, 34, 40, 255), (10, 10, 12, 255))
    d.line((8, 34, 32, 28, 56, 34), fill=(200, 170, 80, 255), width=2)
    return im


def tophat():
    im = img(); d = ImageDraw.Draw(im)
    d.rectangle((20, 4, 44, 32), fill=(30, 30, 34, 255), outline=(8, 8, 10, 255))
    d.rectangle((20, 24, 44, 28), fill=(120, 30, 30, 255))
    d.ellipse((8, 30, 56, 39), fill=(30, 30, 34, 255), outline=(8, 8, 10, 255))
    return im


def flatcap():
    im = img(); d = ImageDraw.Draw(im)
    d.chord((14, 14, 50, 44), 180, 360, fill=(96, 98, 92, 255), outline=(36, 36, 34, 255))
    outline(d, [(40, 30), (60, 34), (58, 38), (38, 36)], (80, 82, 76, 255))
    for x in range(18, 48, 5):
        d.line((x, 22, x + 2, 29), fill=(110, 112, 104, 255))
    return im


def main():
    out = os.path.join(ROOT, "textures")
    for k, fn in enumerate([laurel, hood, beret, tricorn, tophat, flatcap]):
        fn().save(os.path.join(out, "unit_hat_e%d.png" % k))
    print("hats: 6 written to textures/")


if __name__ == "__main__":
    main()
