"""Emblems for the research icons (used by make_textures.techs()).

Every study gets a small picture of what it is about (an axe, a plough, a waterwheel, a cannon...) on
a parchment disc inside a shield in its age's colour. EMBLEM maps each study to an emblem; studies not
listed take their branch's emblem. Emblems are drawn in a 48 x 48 design (the disc's centre at 24, 22,
about 13 design pixels across), with light from the upper left.
"""

INK = (52, 38, 26, 255)
WOOD = (132, 92, 54, 255)
WOOD_D = (92, 62, 34, 255)
IRON = (150, 154, 160, 255)
IRON_L = (210, 214, 220, 255)
IRON_D = (88, 90, 96, 255)
GOLD = (226, 184, 60, 255)
GOLD_L = (252, 224, 120, 255)
STONE = (168, 164, 154, 255)
STONE_D = (118, 114, 106, 255)
GREEN = (92, 142, 60, 255)
GREEN_D = (60, 100, 40, 255)
WATER = (80, 140, 196, 255)
RED = (186, 60, 48, 255)
WHEAT = (226, 190, 92, 255)
PAPER = (244, 236, 214, 255)
CX, CY = 24, 22


# ---------------------------------------------------------------- small helpers
def _outline_poly(d, pts, fill, w=0.7):
    d.polygon(pts, fill=fill, outline=INK, width=w)


def _hilite(d, a, b, w=0.6, col=(255, 255, 255, 140)):
    d.line([a, b], fill=col, width=w)


# ---------------------------------------------------------------- emblems
def axe(d):
    d.line([(17, 33), (30, 14)], fill=WOOD_D, width=2.6)
    d.line([(17, 33), (30, 14)], fill=WOOD, width=1.6)
    _outline_poly(d, [(27, 11), (35, 12), (36, 20), (31, 21), (28, 17)], IRON)
    _hilite(d, (29, 12.5), (34.5, 13.5))


def pickaxe(d):
    d.line([(16, 34), (31, 15)], fill=WOOD_D, width=2.4)
    d.line([(16, 34), (31, 15)], fill=WOOD, width=1.4)
    d.arc([18, 8, 42, 30], 200, 330, fill=INK, width=2.6)
    d.arc([18, 8, 42, 30], 200, 330, fill=IRON, width=1.6)


def hammer(d):
    d.line([(18, 34), (29, 17)], fill=WOOD_D, width=2.6)
    d.line([(18, 34), (29, 17)], fill=WOOD, width=1.6)
    _outline_poly(d, [(23, 13), (34, 20), (31, 25), (20, 18)], IRON)
    _hilite(d, (23.5, 14), (33, 20))


def anvil(d):
    _outline_poly(d, [(13, 18), (35, 18), (35, 22), (31, 24), (30, 28), (34, 32), (16, 32), (20, 28), (19, 24), (13, 21)], IRON_D)
    d.polygon([(13, 18), (35, 18), (35, 19.5), (13, 19.5)], fill=IRON_L)
    d.line([(26, 12), (30, 16)], fill=GOLD_L, width=0.6)
    d.line([(22, 12), (22.5, 16)], fill=GOLD_L, width=0.6)


def plough(d):
    d.line([(13, 16), (26, 27)], fill=WOOD_D, width=2.2)
    d.line([(13, 16), (26, 27)], fill=WOOD, width=1.3)
    _outline_poly(d, [(24, 25), (35, 27), (33, 32), (23, 30)], IRON)
    d.line([(14, 33), (35, 33)], fill=(120, 84, 50, 255), width=1.2)


def wheat(d):
    for k, dx in enumerate((-4, 0, 4)):
        d.line([(CX + dx * 0.4, 34), (CX + dx, 16)], fill=GREEN_D, width=0.8)
        for j in range(4):
            y = 14 + j * 3
            d.ellipse([CX + dx - 1.6, y, CX + dx + 0.2, y + 2.6], fill=WHEAT, outline=(150, 112, 40, 255), width=0.3)
            d.ellipse([CX + dx - 0.2, y + 0.8, CX + dx + 1.6, y + 3.4], fill=WHEAT, outline=(150, 112, 40, 255), width=0.3)
    d.line([(CX - 4, 28), (CX + 4, 28)], fill=RED, width=1.2)


def fish(d):
    _outline_poly(d, [(14, 23), (20, 18), (28, 17), (33, 21), (28, 26), (20, 27)], (120, 156, 186, 255))
    _outline_poly(d, [(33, 21), (37, 17), (37, 26)], (96, 132, 166, 255))
    d.disc(18.5, 21.5, 0.8, INK)
    d.arc([18, 17, 30, 25], 200, 330, fill=(220, 236, 246, 200), width=0.6)


def sapling(d):
    _outline_poly(d, [(18, 34), (30, 34), (28, 28), (20, 28)], WOOD)
    d.line([(24, 28), (24, 16)], fill=GREEN_D, width=1.2)
    for (x, y, s) in ((20, 18, -1), (28, 15, 1), (21, 13, -1)):
        d.ellipse([x - 3, y - 2, x + 3, y + 2], fill=GREEN, outline=GREEN_D, width=0.5)
        d.line([(24, y + 2), (x, y)], fill=GREEN_D, width=0.6)


def well(d):
    d.line([(15, 14), (15, 30)], fill=WOOD_D, width=1.4)
    d.line([(33, 14), (33, 30)], fill=WOOD_D, width=1.4)
    d.line([(13, 14), (35, 14)], fill=WOOD, width=1.6)
    _outline_poly(d, [(14, 26), (34, 26), (33, 34), (15, 34)], STONE)
    d.line([(24, 14), (24, 22)], fill=INK, width=0.5)
    _outline_poly(d, [(22, 21), (26, 21), (25.5, 25), (22.5, 25)], WOOD)


def waterwheel(d):
    d.ellipse([13, 11, 35, 33], outline=INK, width=1.0)
    d.ellipse([14, 12, 34, 32], outline=WOOD, width=1.8)
    for k in range(8):
        import math
        a = k * math.pi / 4
        d.line([(24, 22), (24 + math.cos(a) * 10.5, 22 + math.sin(a) * 10.5)], fill=WOOD_D, width=0.9)
    d.disc(24, 22, 2.0, IRON_D)
    d.polygon([(11, 30), (37, 30), (37, 35), (11, 35)], fill=WATER)
    d.line([(11, 30), (37, 30)], fill=(200, 230, 250, 255), width=0.6)


def windmill(d):
    _outline_poly(d, [(20, 34), (21, 20), (27, 20), (28, 34)], STONE)
    _outline_poly(d, [(19, 21), (24, 15), (29, 21)], RED)
    for a, b in (((24, 18), (13, 9)), ((24, 18), (35, 9)), ((24, 18), (13, 27)), ((24, 18), (35, 27))):
        d.line([a, b], fill=WOOD_D, width=1.0)
        d.line([((a[0] + b[0] * 2) / 3, (a[1] + b[1] * 2) / 3), b], fill=PAPER, width=2.2)
    d.disc(24, 18, 1.2, INK)


def bee(d):
    for k in range(4):
        y = 20 + k * 3.2
        hw = 6 + k * 1.6
        d.rounded_rectangle([CX - hw, y, CX + hw, y + 3], 1.5, fill=WHEAT, outline=(150, 112, 40, 255), width=0.5)
    d.rectangle([22, 30, 26, 33], fill=INK)
    d.ellipse([28, 10, 34, 15], fill=GOLD, outline=INK, width=0.5)
    d.line([(30, 10), (31, 15)], fill=INK, width=0.6)
    d.ellipse([27, 7, 31, 11], fill=(230, 240, 250, 200), outline=INK, width=0.3)


def church(d):
    _outline_poly(d, [(14, 34), (14, 22), (24, 15), (34, 22), (34, 34)], PAPER)
    _outline_poly(d, [(12, 23), (24, 13), (36, 23), (34, 23), (24, 16), (14, 23)], RED)
    d.line([(24, 6), (24, 13)], fill=GOLD, width=1.0)
    d.line([(21.5, 8.5), (26.5, 8.5)], fill=GOLD, width=1.0)
    d.pieslice([21, 26, 27, 32], 180, 360, fill=INK)
    d.rectangle([21, 29, 27, 34], fill=INK)


def flame(d):
    _outline_poly(d, [(24, 8), (31, 18), (32, 26), (28, 33), (20, 33), (16, 26), (18, 18), (21, 21)], (240, 140, 40, 255))
    d.polygon([(24, 16), (28, 24), (27, 31), (21, 31), (20, 25)], fill=(252, 220, 100, 255))


def pot(d):
    _outline_poly(d, [(18, 14), (30, 14), (29, 17), (33, 24), (30, 33), (18, 33), (15, 24), (19, 17)], (184, 108, 66, 255))
    d.line([(16, 22), (32, 22)], fill=(140, 76, 44, 255), width=0.8)
    _hilite(d, (18, 19), (17, 27), 0.8)


def horn(d):
    d.arc([12, 12, 36, 36], 200, 340, fill=INK, width=4.2)
    d.arc([12, 12, 36, 36], 200, 340, fill=(232, 216, 176, 255), width=3.0)
    d.ellipse([31, 17, 37, 25], fill=(232, 216, 176, 255), outline=INK, width=0.6)
    d.line([(13, 20), (13, 30)], fill=GOLD, width=1.0)


def yarn(d):
    d.disc(24, 22, 9, (226, 222, 210, 255))
    d.ellipse([15, 13, 33, 31], outline=INK, width=0.7)
    for k in range(4):
        d.arc([16 + k, 14 + k * 2, 32 - k, 30], 200 - k * 10, 340, fill=(180, 172, 150, 255), width=0.6)
    d.line([(31, 28), (36, 34)], fill=(200, 194, 176, 255), width=0.8)


def salt(d):
    _outline_poly(d, [(14, 33), (19, 22), (24, 17), (29, 22), (34, 33)], (240, 240, 236, 255))
    for (x, y) in ((20, 28), (25, 25), (28, 30), (23, 31)):
        d.polygon([(x, y - 1.2), (x + 1.2, y), (x, y + 1.2), (x - 1.2, y)], fill=(200, 210, 220, 255))


def cheese(d):
    _outline_poly(d, [(13, 30), (33, 18), (35, 22), (35, 31), (13, 33)], WHEAT)
    d.polygon([(13, 30), (33, 18), (35, 22), (15, 31)], fill=GOLD_L)
    for (x, y, r) in ((20, 31, 1.2), (27, 28, 1.5), (31, 31, 1.0)):
        d.disc(x, y, r, (196, 150, 50, 255))


def fields(d):
    for k, c in enumerate([(200, 170, 80, 255), (110, 150, 70, 255), (150, 110, 70, 255)]):
        x = 13 + k * 7.6
        _outline_poly(d, [(x, 33), (x + 7, 33), (x + 7, 13), (x, 13)], c, 0.5)
        for y in range(15, 33, 3):
            d.line([(x + 1, y), (x + 6, y)], fill=(0, 0, 0, 50), width=0.4)


def mug(d):
    _outline_poly(d, [(16, 15), (29, 15), (29, 34), (16, 34)], (232, 196, 96, 255))
    d.rectangle([16, 12, 29, 17], fill=(250, 246, 236, 255), outline=INK, width=0.6)
    d.arc([26, 19, 35, 29], 270, 90, fill=INK, width=2.2)
    d.arc([26, 19, 35, 29], 270, 90, fill=(232, 196, 96, 255), width=1.2)
    _hilite(d, (18, 18), (18, 32), 0.8)


def grapes(d):
    for (x, y) in ((20, 18), (24, 18), (28, 18), (22, 22), (26, 22), (30, 22), (24, 26), (28, 26), (26, 30)):
        d.disc(x, y, 2.4, (110, 60, 140, 255))
        d.disc(x - 0.7, y - 0.7, 0.8, (190, 150, 210, 255))
    d.line([(26, 15), (27, 9)], fill=WOOD, width=1.0)
    d.ellipse([27, 8, 35, 13], fill=GREEN, outline=GREEN_D, width=0.5)


def meat(d):
    _outline_poly(d, [(15, 18), (24, 13), (32, 18), (31, 28), (23, 30), (17, 27)], (196, 96, 78, 255))
    d.line([(31, 28), (35, 33)], fill=(240, 232, 214, 255), width=2.2)
    d.disc(35, 33, 1.3, (240, 232, 214, 255))
    d.arc([18, 16, 30, 28], 200, 320, fill=(236, 170, 150, 255), width=0.8)


def scroll(d, seal=False):
    _outline_poly(d, [(14, 13), (34, 13), (34, 31), (14, 31)], PAPER)
    d.ellipse([12, 11, 16, 15], fill=PAPER, outline=INK, width=0.5)
    d.ellipse([32, 29, 36, 33], fill=PAPER, outline=INK, width=0.5)
    for y in (17, 20, 23, 26):
        d.line([(17, y), (31 if y != 26 else 25, y)], fill=(150, 130, 100, 255), width=0.5)
    if seal:
        d.disc(29, 28, 2.6, RED)
        d.line([(28, 30), (27, 34)], fill=RED, width=0.8)


def mapc(d):
    _outline_poly(d, [(12, 14), (20, 12), (28, 14), (36, 12), (36, 32), (28, 34), (20, 32), (12, 34)], PAPER)
    d.line([(20, 12), (20, 32)], fill=(0, 0, 0, 40), width=0.5)
    d.line([(28, 14), (28, 34)], fill=(0, 0, 0, 40), width=0.5)
    d.polygon([(15, 20), (19, 17), (24, 19), (22, 24), (17, 25)], fill=(140, 170, 100, 255))
    d.line([(24, 28), (32, 20)], fill=RED, width=0.6)
    d.polygon([(31, 17), (32.5, 22), (34, 17)], fill=RED)


def flask(d):
    _outline_poly(d, [(22, 10), (26, 10), (26, 17), (33, 30), (31, 34), (17, 34), (15, 30), (22, 17)], (230, 240, 246, 220))
    d.polygon([(19, 25), (29, 25), (32, 31), (31, 33), (17, 33), (16, 31)], fill=(110, 200, 140, 255))
    d.disc(22, 29, 0.8, (220, 250, 230, 255))
    d.disc(26, 27, 0.6, (220, 250, 230, 255))
    d.line([(21, 10), (27, 10)], fill=INK, width=1.0)


def ship(d, steam=False):
    _outline_poly(d, [(11, 25), (37, 25), (33, 32), (15, 32)], WOOD if not steam else IRON_D)
    if steam:
        _outline_poly(d, [(21, 17), (26, 17), (26, 25), (21, 25)], RED)
        for k, (x, y, r) in enumerate(((24, 13, 2.2), (27, 9, 2.6), (31, 6, 2.2))):
            d.disc(x, y, r, (200, 200, 200, 200))
    else:
        d.line([(24, 8), (24, 25)], fill=WOOD_D, width=1.0)
        _outline_poly(d, [(24, 9), (33, 21), (24, 21)], PAPER)
        _outline_poly(d, [(23, 11), (16, 21), (23, 21)], PAPER)
    d.line([(9, 34), (39, 34)], fill=WATER, width=1.2)


def compass(d):
    d.disc(24, 22, 10, (226, 210, 170, 255))
    d.ellipse([14, 12, 34, 32], outline=INK, width=0.8)
    d.polygon([(24, 13), (26, 22), (24, 31), (22, 22)], fill=IRON_D)
    d.polygon([(24, 13), (26, 22), (22, 22)], fill=RED)
    d.polygon([(15, 22), (24, 20.5), (33, 22), (24, 23.5)], fill=(150, 130, 100, 255))


def blocks(d):
    for (x, y) in ((13, 26), (24, 26), (18, 18), (29, 18)):
        _outline_poly(d, [(x, y), (x + 10, y), (x + 10, y + 7), (x, y + 7)], STONE)
        _hilite(d, (x + 0.5, y + 0.6), (x + 9.5, y + 0.6), 0.6)
    d.line([(31, 10), (36, 16)], fill=IRON_D, width=1.6)


def sack(d):
    _outline_poly(d, [(18, 14), (30, 14), (28, 18), (34, 26), (32, 34), (16, 34), (14, 26), (20, 18)], (210, 186, 140, 255))
    d.line([(19, 17), (29, 17)], fill=WOOD_D, width=1.0)
    for (x, y) in ((22, 26), (26, 28), (24, 23)):
        d.ellipse([x - 1.2, y - 0.6, x + 1.2, y + 0.6], fill=WHEAT)


def frame_house(d):
    _outline_poly(d, [(14, 34), (14, 21), (34, 21), (34, 34)], PAPER)
    _outline_poly(d, [(12, 22), (24, 12), (36, 22)], RED)
    for x in (14, 24, 34):
        d.line([(x, 21), (x, 34)], fill=WOOD_D, width=1.2)
    d.line([(14, 27), (34, 27)], fill=WOOD_D, width=1.0)
    d.line([(14, 34), (24, 27)], fill=WOOD_D, width=0.8)
    d.line([(34, 34), (24, 27)], fill=WOOD_D, width=0.8)


def scales(d):
    d.line([(24, 11), (24, 33)], fill=WOOD_D, width=1.4)
    d.line([(13, 15), (35, 15)], fill=GOLD, width=1.2)
    for x in (15, 33):
        d.line([(x, 15), (x - 3, 23)], fill=INK, width=0.4)
        d.line([(x, 15), (x + 3, 23)], fill=INK, width=0.4)
        d.pieslice([x - 4, 19, x + 4, 27], 0, 180, fill=GOLD, outline=INK, width=0.5)
    _outline_poly(d, [(18, 33), (30, 33), (28, 30), (20, 30)], WOOD)


def wheel(d):
    import math
    d.ellipse([12, 10, 36, 34], fill=None, outline=INK, width=2.6)
    d.ellipse([12, 10, 36, 34], fill=None, outline=WOOD, width=1.6)
    for k in range(6):
        a = k * math.pi / 3
        d.line([(24, 22), (24 + math.cos(a) * 11, 22 + math.sin(a) * 11)], fill=WOOD_D, width=1.1)
    d.disc(24, 22, 2.6, IRON_D)


def horseshoe(d):
    d.arc([14, 12, 34, 34], 140, 400, fill=INK, width=4.4)
    d.arc([14, 12, 34, 34], 140, 400, fill=IRON, width=3.0)
    for a in (160, 200, 340, 380):
        import math
        r = math.radians(a)
        d.disc(24 + math.cos(r) * 8.6, 23 + math.sin(r) * 8.6, 0.6, INK)


def barrel(d):
    _outline_poly(d, [(17, 12), (31, 12), (33, 17), (33, 29), (31, 34), (17, 34), (15, 29), (15, 17)], WOOD)
    for y in (15, 23, 31):
        d.line([(15.5, y), (32.5, y)], fill=IRON_D, width=1.2)
    for x in (20, 24, 28):
        d.line([(x, 12.5), (x, 33.5)], fill=WOOD_D, width=0.4)
    _hilite(d, (18, 14), (17, 32), 0.9)


def road(d):
    _outline_poly(d, [(18, 34), (21, 12), (27, 12), (30, 34)], (176, 168, 152, 255))
    for (y, n) in ((14, 2), (18, 2), (22, 3), (27, 3), (31, 3)):
        hw = 3 + (y - 12) * 0.13
        for k in range(n):
            x = 24 - hw + (2 * hw) * (k + 0.5) / n
            d.rounded_rectangle([x - 1.2, y - 1, x + 1.2, y + 1.4], 0.6, fill=STONE_D)


def crane(d):
    d.line([(16, 34), (16, 12)], fill=WOOD_D, width=1.6)
    d.line([(16, 12), (34, 16)], fill=WOOD, width=1.6)
    d.line([(16, 20), (24, 13.8)], fill=WOOD_D, width=0.8)
    d.line([(32, 16), (32, 26)], fill=INK, width=0.5)
    _outline_poly(d, [(29, 26), (35, 26), (35, 31), (29, 31)], STONE)
    d.ellipse([10, 26, 22, 38], outline=WOOD, width=1.2)


def bridge(d):
    _outline_poly(d, [(10, 22), (38, 22), (38, 26), (10, 26)], STONE)
    for x0 in (11, 25):
        d.pieslice([x0, 24, x0 + 12, 38], 180, 360, fill=(88, 140, 190, 255))
    d.line([(10, 22), (38, 22)], fill=(220, 214, 200, 255), width=0.6)
    d.line([(9, 35), (39, 35)], fill=WATER, width=1.4)


def coins(d):
    for k, (x, y) in enumerate(((19, 28), (29, 28), (24, 22), (24, 30))):
        d.ellipse([x - 5, y - 3, x + 5, y + 3], fill=GOLD, outline=(140, 100, 30, 255), width=0.5)
        d.ellipse([x - 3, y - 1.8, x + 3, y + 1.8], outline=GOLD_L, width=0.4)


def gate(d):
    d.line([(14, 34), (14, 20)], fill=WOOD_D, width=1.6)
    _outline_poly(d, [(14, 21), (36, 17), (36, 20), (14, 24)], PAPER)
    for k in range(3):
        x = 19 + k * 6
        d.polygon([(x, 22.2 - k * 1.1), (x + 3, 21.6 - k * 1.1), (x + 3, 24.5 - k * 1.1 - 0.6), (x, 25 - k * 1.1)], fill=RED)


def rails(d):
    d.line([(18, 34), (22, 12)], fill=IRON_D, width=1.0)
    d.line([(30, 34), (26, 12)], fill=IRON_D, width=1.0)
    for y in range(14, 35, 4):
        t = (y - 12) / 22
        d.line([(22 - 4 * t - 1.5, y), (26 + 4 * t + 1.5, y)], fill=WOOD, width=1.0)


def bellows(d):
    _outline_poly(d, [(13, 22), (30, 13), (34, 22), (30, 31)], (150, 100, 60, 255))
    d.line([(13, 22), (34, 22)], fill=WOOD_D, width=1.2)
    d.line([(34, 22), (38, 22)], fill=IRON_D, width=1.4)
    for k in range(3):
        d.line([(17 + k * 4, 21), (25 + k * 3, 15 + k * 1.5)], fill=(110, 70, 40, 255), width=0.4)


def hide(d):
    _outline_poly(d, [(16, 12), (22, 15), (26, 15), (32, 12), (30, 20), (34, 26), (28, 34), (20, 34), (14, 26), (18, 20)], (170, 120, 76, 255))
    d.polygon([(19, 20), (29, 20), (31, 26), (26, 31), (22, 31), (17, 26)], fill=(196, 150, 104, 255))


def candle(d):
    _outline_poly(d, [(21, 18), (27, 18), (27, 33), (21, 33)], (244, 236, 210, 255))
    d.line([(24, 18), (24, 15)], fill=INK, width=0.5)
    d.polygon([(24, 8), (26.5, 13), (24, 16), (21.5, 13)], fill=(250, 190, 60, 255))
    d.polygon([(24, 11), (25.2, 13.5), (24, 15), (22.8, 13.5)], fill=(255, 245, 200, 255))
    d.ellipse([16, 31, 32, 35], fill=GOLD, outline=INK, width=0.5)


def bottle(d):
    _outline_poly(d, [(22, 10), (26, 10), (26, 16), (31, 21), (31, 34), (17, 34), (17, 21), (22, 16)], (110, 180, 170, 220))
    _hilite(d, (19.5, 22), (19.5, 32), 1.0, (230, 255, 250, 180))
    d.rectangle([21.5, 9, 26.5, 11], fill=WOOD)


def lens(d):
    for x in (17, 31):
        d.disc(x, 24, 5.4, (210, 230, 240, 200))
        d.ellipse([x - 5.4, 18.6, x + 5.4, 29.4], outline=INK, width=0.9)
        _hilite(d, (x - 2.5, 21), (x - 1, 19.6), 0.8)
    d.arc([21, 20, 27, 26], 200, 340, fill=INK, width=0.9)


def furnace(d):
    _outline_poly(d, [(14, 34), (17, 14), (31, 14), (34, 34)], (150, 80, 60, 255))
    for y in range(17, 34, 3):
        d.line([(15 + (34 - y) * 0.12, y), (33 - (34 - y) * 0.12, y)], fill=(110, 54, 40, 255), width=0.4)
    d.pieslice([19, 25, 29, 37], 180, 360, fill=(255, 150, 50, 255))
    d.rectangle([19, 31, 29, 34], fill=(255, 196, 80, 255))
    for (x, y, r) in ((24, 10, 2.2), (27, 6, 2.6)):
        d.disc(x, y, r, (180, 180, 180, 200))


def gear(d):
    import math
    pts = []
    for k in range(24):
        a = k * math.pi / 12
        r = 11 if k % 3 != 2 else 8.6
        r = 11 if (k // 1) % 3 < 2 else 8.4
        pts.append((24 + math.cos(a) * r, 22 + math.sin(a) * r))
    _outline_poly(d, pts, IRON)
    d.disc(24, 22, 5.4, IRON_D)
    d.disc(24, 22, 2.6, (226, 214, 190, 255))
    _hilite(d, (17, 15), (21, 12), 0.8)


def pump(d):
    _outline_poly(d, [(18, 16), (26, 16), (26, 34), (18, 34)], IRON)
    d.line([(26, 20), (33, 20)], fill=IRON_D, width=1.6)
    d.line([(18, 16), (12, 11)], fill=WOOD, width=1.4)
    d.disc(33, 24, 1.3, WATER)
    d.disc(33.5, 28, 1.0, WATER)


def bomb(d):
    barrel(d)
    d.line([(24, 12), (27, 7)], fill=INK, width=0.6)
    d.polygon([(27, 4), (29, 7), (27, 9), (25, 7)], fill=(250, 190, 60, 255))


def shuttle(d):
    _outline_poly(d, [(10, 24), (18, 19), (30, 19), (38, 24), (30, 29), (18, 29)], WOOD)
    d.rounded_rectangle([20, 21.5, 28, 26.5], 1.5, fill=(220, 210, 180, 255), outline=INK, width=0.5)
    for y in (15, 33):
        d.line([(10, y), (38, y)], fill=(180, 60, 60, 255), width=0.8)


def vase(d):
    _outline_poly(d, [(20, 11), (28, 11), (27, 15), (32, 22), (29, 33), (19, 33), (16, 22), (21, 15)], (240, 244, 250, 255))
    d.line([(17, 20), (31, 20)], fill=(60, 90, 170, 255), width=1.0)
    d.line([(18, 27), (30, 27)], fill=(60, 90, 170, 255), width=1.0)
    for x in (21, 24, 27):
        d.disc(x, 23.5, 0.8, (60, 90, 170, 255))


def factory(d):
    _outline_poly(d, [(11, 34), (11, 24), (17, 20), (17, 24), (23, 20), (23, 24), (29, 20), (29, 34)], (170, 90, 66, 255))
    d.rectangle([31, 12, 35, 34], fill=(150, 76, 58, 255), outline=INK, width=0.6)
    for (x, y, r) in ((33, 9, 2.0), (35, 5, 2.6)):
        d.disc(x, y, r, (170, 170, 170, 200))
    for x in (14, 20, 26):
        d.rectangle([x, 27, x + 2, 30], fill=(250, 210, 120, 255))


def bow(d):
    d.arc([12, 9, 32, 35], 290, 70, fill=INK, width=2.4)
    d.arc([12, 9, 32, 35], 290, 70, fill=WOOD, width=1.4)
    d.line([(26, 10.5), (26, 33.5)], fill=PAPER, width=0.4)
    d.line([(14, 22), (36, 22)], fill=WOOD_D, width=0.8)
    d.polygon([(36, 22), (33, 20.4), (33, 23.6)], fill=IRON_D)


def crossbow(d):
    d.line([(24, 12), (24, 35)], fill=WOOD, width=2.0)
    d.arc([12, 12, 36, 26], 190, 350, fill=INK, width=2.0)
    d.arc([12, 12, 36, 26], 190, 350, fill=IRON, width=1.2)
    d.line([(13, 19), (24, 24), (35, 19)], fill=PAPER, width=0.4)
    d.polygon([(24, 8), (22.4, 12), (25.6, 12)], fill=IRON_D)


def chainmail(d):
    _outline_poly(d, [(17, 12), (31, 12), (36, 17), (33, 21), (31, 19), (31, 34), (17, 34), (17, 19), (15, 21), (12, 17)], IRON)
    for y in range(14, 34, 2):
        for x in range(18, 31, 2):
            d.arc([x - 0.9, y - 0.9 + (x % 4) * 0.25, x + 0.9, y + 0.9 + (x % 4) * 0.25], 0, 360, fill=IRON_D, width=0.3)


def shield(d):
    _outline_poly(d, [(14, 11), (34, 11), (34, 22), (24, 35), (14, 22)], RED)
    d.polygon([(24, 11), (34, 11), (34, 22), (24, 35)], fill=(150, 44, 36, 255))
    d.line([(24, 11), (24, 35)], fill=GOLD, width=1.2)
    d.line([(14, 19), (34, 19)], fill=GOLD, width=1.2)


def spear(d):
    d.line([(14, 35), (32, 12)], fill=WOOD, width=1.4)
    _outline_poly(d, [(32, 12), (35, 6), (36, 13), (33, 14)], IRON)
    d.polygon([(17, 27), (13, 25), (16, 29)], fill=RED)


def tower(d):
    _outline_poly(d, [(17, 34), (17, 14), (31, 14), (31, 34)], STONE)
    for x in (17, 22, 27):
        d.rectangle([x, 10, x + 3.4, 14], fill=STONE, outline=INK, width=0.5)
    d.pieslice([21, 25, 27, 31], 180, 360, fill=INK)
    d.rectangle([21, 28, 27, 34], fill=INK)
    d.rectangle([23, 17, 25, 21], fill=INK)


def wall(d):
    _outline_poly(d, [(10, 34), (10, 19), (38, 19), (38, 34)], STONE)
    for x in range(10, 38, 6):
        d.rectangle([x, 15, x + 3.4, 19], fill=STONE, outline=INK, width=0.5)
    for y in (23, 27, 31):
        d.line([(10.5, y), (37.5, y)], fill=STONE_D, width=0.4)


def cannon(d):
    d.line([(12, 22), (33, 16)], fill=INK, width=5.0)
    d.line([(12, 22), (33, 16)], fill=IRON_D, width=3.8)
    _hilite(d, (14, 20.4), (31, 15.8), 0.7)
    d.ellipse([15, 22, 27, 34], fill=WOOD, outline=INK, width=0.7)
    d.disc(21, 28, 1.4, IRON_D)


def musket(d, bayonet=False):
    d.line([(10, 31), (34, 13)], fill=IRON_D, width=1.4)
    _outline_poly(d, [(9, 31), (17, 25), (19, 28), (12, 35)], WOOD)
    if bayonet:
        d.line([(34, 13), (39, 9)], fill=IRON_L, width=0.8)


def helmet(d):
    _outline_poly(d, [(14, 28), (15, 18), (24, 12), (33, 18), (34, 28)], IRON)
    d.rectangle([22.6, 17, 25.4, 30], fill=IRON_D)
    d.line([(13, 28), (35, 28)], fill=IRON_D, width=1.2)
    _hilite(d, (17, 18), (22, 14), 0.8)


def star(d):
    import math
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        r = 11 if k % 2 == 0 else 5
        pts.append((24 + math.cos(a) * r, 23 + math.sin(a) * r))
    _outline_poly(d, pts, STONE)
    d.disc(24, 23, 2.5, STONE_D)


def leaf(d):
    _outline_poly(d, [(14, 33), (16, 22), (24, 14), (34, 11), (32, 22), (25, 30)], GREEN)
    d.line([(15, 32), (32, 13)], fill=GREEN_D, width=0.8)
    for k in range(4):
        x, y = 18 + k * 3.6, 28 - k * 4
        d.line([(x, y), (x - 2, y - 3)], fill=GREEN_D, width=0.5)
        d.line([(x, y), (x + 3, y + 1)], fill=GREEN_D, width=0.5)


def crown(d):
    _outline_poly(d, [(12, 31), (12, 17), (18, 23), (24, 13), (30, 23), (36, 17), (36, 31)], GOLD)
    d.rectangle([12, 28, 36, 31], fill=GOLD_L, outline=INK, width=0.5)
    for x, c in ((18, RED), (24, (60, 120, 200, 255)), (30, RED)):
        d.disc(x, 29.5, 1.2, c)


def cross(d):
    d.disc(24, 22, 11, (250, 250, 250, 255))
    d.ellipse([13, 11, 35, 33], outline=INK, width=0.6)
    d.rectangle([21, 14, 27, 30], fill=RED)
    d.rectangle([16, 19, 32, 25], fill=RED)


def book(d):
    _outline_poly(d, [(12, 14), (23.5, 16), (23.5, 34), (12, 32)], PAPER)
    _outline_poly(d, [(24.5, 16), (36, 14), (36, 32), (24.5, 34)], PAPER)
    for k in range(4):
        y = 19 + k * 3.4
        d.line([(14.5, y), (21.5, y + 0.4)], fill=(150, 130, 100, 255), width=0.5)
        d.line([(26.5, y + 0.4), (33.5, y)], fill=(150, 130, 100, 255), width=0.5)
    d.line([(24, 16), (24, 34)], fill=RED, width=0.8)


def clock(d):
    d.disc(24, 22, 11, (240, 232, 210, 255))
    d.ellipse([13, 11, 35, 33], outline=GOLD, width=1.4)
    d.ellipse([13, 11, 35, 33], outline=INK, width=0.5)
    import math
    for k in range(12):
        a = k * math.pi / 6
        d.point((24 + math.cos(a) * 8.5, 22 + math.sin(a) * 8.5), fill=INK)
    d.line([(24, 22), (24, 15)], fill=INK, width=1.0)
    d.line([(24, 22), (29, 24)], fill=INK, width=0.8)


def lamp(d):
    d.line([(24, 34), (24, 18)], fill=IRON_D, width=1.4)
    _outline_poly(d, [(19, 10), (29, 10), (27, 18), (21, 18)], (250, 220, 120, 255))
    d.polygon([(18, 10), (24, 6), (30, 10)], fill=IRON_D)
    d.line([(19, 34), (29, 34)], fill=IRON_D, width=1.4)


def corn(d):
    _outline_poly(d, [(20, 34), (19, 18), (24, 9), (29, 18), (28, 34)], (238, 200, 70, 255))
    for y in range(13, 32, 3):
        d.line([(20.2, y), (27.8, y)], fill=(196, 150, 40, 255), width=0.4)
    d.polygon([(19, 34), (13, 20), (21, 26)], fill=GREEN)
    d.polygon([(29, 34), (35, 20), (27, 26)], fill=GREEN)


def can(d):
    _outline_poly(d, [(16, 15), (32, 15), (32, 33), (16, 33)], IRON)
    d.ellipse([16, 12, 32, 18], fill=IRON_L, outline=INK, width=0.5)
    d.rectangle([16, 21, 32, 28], fill=RED)
    d.disc(24, 24.5, 2.2, (240, 220, 140, 255))


def houses(d):
    for (x, y, c) in ((11, 20, PAPER), (24, 15, (220, 200, 170, 255))):
        _outline_poly(d, [(x, 34), (x, y + 6), (x + 13, y + 6), (x + 13, 34)], c)
        _outline_poly(d, [(x - 1, y + 7), (x + 6.5, y), (x + 14, y + 7)], RED)
        for wy in range(y + 9, 32, 5):
            d.rectangle([x + 3, wy, x + 5, wy + 2], fill=(90, 110, 130, 255))
            d.rectangle([x + 8, wy, x + 10, wy + 2], fill=(90, 110, 130, 255))


def quill(d):
    _outline_poly(d, [(14, 34), (30, 10), (35, 9), (33, 15), (18, 33)], PAPER)
    d.line([(14, 34), (33, 11)], fill=(150, 130, 100, 255), width=0.5)
    d.disc(30, 33, 3.0, (40, 40, 60, 255))


def press(d):
    _outline_poly(d, [(13, 34), (13, 12), (35, 12), (35, 34)], WOOD)
    d.rectangle([16, 15, 32, 31], fill=PAPER, outline=INK, width=0.5)
    d.line([(24, 9), (24, 15)], fill=IRON_D, width=1.6)
    d.line([(18, 9), (30, 9)], fill=IRON_D, width=1.2)
    for y in (19, 22, 25, 28):
        d.line([(18, y), (30, y)], fill=(60, 60, 60, 255), width=0.6)


def pennant(d):
    d.line([(14, 35), (34, 9)], fill=WOOD, width=1.6)
    _outline_poly(d, [(31, 13), (38, 18), (28, 18)], RED)
    d.disc(14, 35, 1.6, IRON_D)


def columns(d):
    _outline_poly(d, [(11, 17), (24, 9), (37, 17)], PAPER)
    for x in (14, 20, 26, 32):
        d.rectangle([x - 1.3, 18, x + 1.3, 32], fill=PAPER, outline=INK, width=0.4)
    d.rectangle([11, 32, 37, 35], fill=PAPER, outline=INK, width=0.5)


def lightning(d):
    d.line([(12, 34), (12, 14)], fill=WOOD_D, width=1.4)
    d.line([(9, 15), (15, 15)], fill=WOOD_D, width=1.0)
    d.line([(12, 15), (36, 12)], fill=INK, width=0.4)
    _outline_poly(d, [(27, 14), (22, 25), (26, 25), (21, 35), (32, 21), (27, 21), (31, 14)], GOLD)


def paper(d):
    for k in range(3):
        o = k * 2
        _outline_poly(d, [(14 + o, 12 + o), (30 + o, 12 + o), (30 + o, 32 + o), (14 + o, 32 + o)], PAPER, 0.5)
    for y in (19, 22, 25, 28):
        d.line([(19, y), (33, y)], fill=(150, 130, 100, 255), width=0.5)


def key(d):
    d.ellipse([12, 16, 22, 26], outline=INK, width=2.6)
    d.ellipse([12, 16, 22, 26], outline=GOLD, width=1.6)
    d.line([(22, 21), (36, 21)], fill=GOLD, width=1.6)
    d.line([(32, 21), (32, 26)], fill=GOLD, width=1.4)
    d.line([(35, 21), (35, 25)], fill=GOLD, width=1.4)


def chart(d):
    for k, h in enumerate((8, 13, 10, 18)):
        x = 13 + k * 6
        _outline_poly(d, [(x, 34), (x + 4.4, 34), (x + 4.4, 34 - h), (x, 34 - h)], [(110, 150, 200, 255), (200, 120, 80, 255), (120, 170, 90, 255), GOLD][k], 0.5)
    d.line([(12, 34.5), (37, 34.5)], fill=INK, width=0.7)


def medal(d):
    d.polygon([(19, 9), (24, 18), (29, 9)], fill=RED)
    d.disc(24, 25, 8, GOLD)
    d.ellipse([16, 17, 32, 33], outline=INK, width=0.6)
    star_pts = []
    import math
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        r = 5.5 if k % 2 == 0 else 2.4
        star_pts.append((24 + math.cos(a) * r, 25 + math.sin(a) * r))
    d.polygon(star_pts, fill=GOLD_L)


def sword(d):
    d.line([(15, 33), (32, 12)], fill=IRON_L, width=2.0)
    d.line([(15, 33), (32, 12)], fill=INK, width=0.3)
    d.line([(15, 26), (22, 33)], fill=GOLD, width=1.6)
    d.line([(13, 35), (16, 32)], fill=WOOD, width=1.8)


def note(d):
    _outline_poly(d, [(11, 15), (37, 15), (37, 30), (11, 30)], (210, 228, 200, 255))
    d.ellipse([20, 18, 28, 27], outline=GREEN_D, width=0.8)
    d.line([(14, 18), (17, 18)], fill=GREEN_D, width=0.6)
    d.line([(31, 27), (34, 27)], fill=GREEN_D, width=0.6)


def pipe(d):
    d.line([(10, 18), (28, 18)], fill=INK, width=5.0)
    d.line([(10, 18), (28, 18)], fill=IRON, width=3.6)
    d.line([(26, 16), (26, 34)], fill=INK, width=5.0)
    d.line([(26, 16), (26, 34)], fill=IRON, width=3.6)
    d.disc(26, 18, 2.4, IRON_L)
    d.disc(31, 33, 1.3, WATER)


def trowel(d):
    _outline_poly(d, [(14, 31), (26, 19), (32, 24), (20, 34)], IRON)
    d.line([(29, 21), (35, 14)], fill=IRON_D, width=0.8)
    d.line([(34, 15), (37, 11)], fill=WOOD, width=2.0)


EMBLEMS = {k: v for k, v in globals().items() if callable(v) and not k.startswith("_")}

# study id -> emblem (studies not listed use their branch's emblem)
BY_ID = {
    # the Bronze Age studies of build 73
    "corduroy_tracks": "road", "weights_measures": "scales", "sickles": "wheat", "storage_pits": "pot",
    "wild_hives": "bee", "hot_furnaces": "furnace", "tin_prospecting": "pickaxe", "potters_wheel": "vase",
    "village_elders": "houses", "festivals": "mug", "herb_gathering": "leaf", "calendar": "clock",
    "counting_boards": "chart", "chariots": "wheel", "shield_wall": "shield",
    # land
    "salt_trade": "salt", "castles": "tower", "charters": "scroll_seal", "tool_patterns": "hammer", "new_crops": "corn",
    "iron_axes": "axe", "coppicing": "sapling", "fish_traps": "fish", "wells": "well", "wells_and_cisterns": "well",
    "heavy_plough": "plough", "watermills": "waterwheel", "beekeeping": "bee", "monasteries": "church",
    "open_fields": "wheat", "open_field_farming": "wheat", "charcoal": "flame", "charcoal_clamps": "flame",
    "clay_working": "pot", "hunting_dogs": "horn", "wool_trade": "yarn", "salt_roads": "salt", "windmills": "windmill",
    "post_windmills": "windmill", "cheesemaking": "cheese", "three_field": "fields", "three_field_system": "fields",
    "brewers_guild": "mug", "vintners": "grapes", "smoke_curing": "meat", "cartography": "mapc", "distilling": "flask",
    "navigators_school": "compass", "crop_rotation": "fields", "selective_breeding": "yarn", "seed_drill": "sack",
    "agricultural_societies": "wheat", "iron_ships": "ship_steam", "steel_ploughs": "plough", "steam_trawlers": "ship_steam",
    # roads
    "stone_masonry": "blocks", "granaries": "sack", "timber_framing": "frame_house", "village_markets": "scales",
    "ox_carts": "wheel", "horse_collar": "horseshoe", "pack_mules": "horseshoe", "trade_fairs": "pennant",
    "heavy_horses": "horseshoe", "cellars": "barrel", "stone_roads": "road", "masons_guild": "trowel",
    "treadwheel_cranes": "crane", "stone_bridges": "bridge", "joint_stock": "coins", "joint_stock_companies": "coins",
    "canals": "bridge", "turnpike_roads": "gate", "turnpikes": "gate", "railways": "rails",
    # industry
    "tool_care": "hammer", "bellows": "bellows", "village_smithy": "anvil", "bark_tanning": "hide", "wool_combing": "yarn",
    "dyeing": "pot", "guilds": "key", "candle_making": "candle", "tanners_guild": "hide", "glassblowing": "bottle",
    "fulling_mills": "waterwheel", "banking": "coins", "lens_grinding": "lens", "engraving": "quill",
    "standard_tools": "hammer", "standard_tool_patterns": "hammer", "mine_pumps": "pump", "guild_halls": "columns",
    "vein_surveying": "pickaxe", "trip_hammers": "hammer", "milled_coinage": "coins", "lubricants": "barrel",
    "blast_furnace": "furnace", "flying_shuttle": "shuttle", "porcelain": "vase", "coke_smelting": "furnace",
    "chemistry": "flask", "textile_mills": "factory", "power_loom": "gear", "steam_engine": "gear",
    "steam_pumps": "pump", "machine_tools": "gear", "blasting_powder": "bomb",
    # war
    "longbows": "bow", "chainmail": "chainmail", "shield_walls": "shield", "militia_levy": "spear",
    "stone_castles": "tower", "crossbows": "crossbow", "town_walls": "wall", "gunpowder": "bomb", "musketry": "musket",
    "star_forts": "star", "field_artillery": "cannon", "standing_army": "helmet", "drill_manuals": "book",
    "bayonets": "musket_bayonet", "rifling": "musket", "breech_loaders": "musket",
    # people
    "herbal_lore": "leaf", "tithes": "sack", "feudalism": "crown", "hospices": "cross", "cathedral_schools": "church",
    "town_charters": "scroll_seal", "herbals": "leaf", "double_entry": "book", "double_entry_bookkeeping": "book",
    "new_world_crops": "corn", "hospitals": "cross", "clockmaking": "clock", "inoculation": "flask",
    "town_planning": "mapc", "bank_notes": "note", "sewers": "pipe", "insurance": "shield", "canning": "can",
    "gas_lighting": "lamp", "mass_schooling": "book", "public_health": "cross", "portland_cement": "trowel",
    "industrial_revolution": "factory", "tenements": "houses",
    # the studies that open each age
    "new_kingdoms": "crown", "rise_of_towns": "houses", "rebirth_of_learning": "columns", "age_of_reason": "lens",
    "dawn_of_industry": "gear",
    # learning
    "apprenticeship": "hammer", "prospecting": "pickaxe", "journeymen": "road", "papermaking": "paper",
    "tournaments": "pennant", "printing_press": "press", "humanism": "quill", "geological_survey": "pickaxe",
    "scientific_method": "flask", "encyclopedia": "book", "the_encyclopedia": "book", "royal_academies": "columns",
    "telegraph": "lightning", "rotary_press": "press",
}

# by name, for the repeatable studies (their ids are made up of other words)
BY_NAME = {
    "Better tools": "hammer", "Weapon drill": "sword", "Track upkeep": "road", "Craft secrets": "key",
    "Tax rolls": "scroll", "Muster": "spear", "Workshop practice": "anvil", "Scholarship": "book",
    "Veteran training": "helmet", "Method": "flask", "Logistics": "wheel", "Fortification": "wall",
    "Mass production": "gear", "Statistics": "chart", "General staff": "medal",
}

BY_LANE = {"land": "wheat", "roads": "wheel", "industry": "anvil", "war": "sword", "people": "houses", "learning": "book"}


def draw(d, t):
    """Draws the emblem for study t (a dict from techs.json) with pen d."""
    name = BY_ID.get(t.get("id", "")) or BY_NAME.get(t.get("name", "")) or _guess(t) or BY_LANE.get(t.get("lane", ""), "book")
    if name == "ship_steam":
        ship(d, True)
    elif name == "musket_bayonet":
        musket(d, True)
    elif name == "scroll_seal":
        scroll(d, True)
    else:
        EMBLEMS[name](d)
    return name


def _guess(t):
    """By words in the study's name, for studies a mod adds."""
    n = t.get("name", "").lower()
    for word, em in (("axe", "axe"), ("plough", "plough"), ("mill", "waterwheel"), ("fish", "fish"), ("ship", "ship"),
                     ("bank", "coins"), ("coin", "coins"), ("road", "road"), ("bridge", "bridge"), ("cart", "wheel"),
                     ("horse", "horseshoe"), ("smith", "anvil"), ("forge", "anvil"), ("steam", "gear"), ("bow", "bow"),
                     ("wall", "wall"), ("castle", "tower"), ("fort", "star"), ("gun", "cannon"), ("school", "book"),
                     ("book", "book"), ("print", "press"), ("church", "church"), ("health", "cross"), ("farm", "wheat"),
                     ("wine", "grapes"), ("beer", "mug"), ("brew", "mug"), ("glass", "bottle"), ("trade", "scales")):
        if word in n:
            return em
    return None
