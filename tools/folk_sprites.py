"""Townsfolk, porters, workers, pack mules and ox carts, drawn in detail.
Run on its own (python3 tools/folk_sprites.py) or from make_textures.py; it writes the unit_folk_*,
unit_porter*, unit_worker_*, unit_mule, unit_cart and unit_load_* strips into textures/.
Everything is drawn in design pixels with make_textures' Pen, so edges come out smooth.
Strips that the game tints with the realm's colour come with a *_tint companion: the tunic alone,
in grey, drawn over the picture in the realm's colour."""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_textures as mt
from PIL import Image

sh = mt.sh
SKIN = [(240, 212, 178, 255), (222, 186, 150, 255), (190, 142, 104, 255)]
HAIR = [(70, 46, 30, 255), (150, 100, 50, 255), (40, 34, 30, 255), (200, 170, 110, 255)]
BOOT = (66, 48, 36, 255)
WOOD = (122, 86, 52, 255)
IRON = (96, 98, 104, 255)

# clothes for each kind of person: tunic, trousers / skirt, extra
LOOKS = {
	"peasant":  dict(top=(150, 118, 74, 255), legs=(104, 86, 64, 255), hat="straw", belt=(84, 60, 40, 255)),
	"woman":    dict(top=(176, 92, 74, 255), legs=(120, 96, 140, 255), skirt=True, hat="kerchief", apron=(226, 220, 200, 255)),
	"artisan":  dict(top=(78, 118, 170, 255), legs=(80, 74, 70, 255), hat="cap", apron=(150, 110, 70, 255), belt=(60, 44, 32, 255)),
	"noble":    dict(top=(128, 70, 150, 255), legs=(60, 50, 64, 255), hat="feather", cloak=(96, 40, 70, 255), belt=(200, 170, 70, 255)),
	"child":    dict(top=(200, 160, 80, 255), legs=(120, 100, 70, 255), hat=None, belt=None),
	"newcomer": dict(top=(150, 146, 130, 255), legs=(110, 100, 86, 255), hat="hood", belt=(90, 70, 50, 255)),
}


def person(kind, phase, facing=1, carry=None, bend=0.0, talk=None, skin=0, hair=0, k=2, tool=None, swing=None, top=None):
	"""One person, 24 x 36 design pixels, facing right. phase 0..1 through a two-step walk
	(None: standing). carry: None, 'crate' (A-frame on the back), 'bundle' or 'sack'.
	bend 0..1: stooping to set a load down. talk: None or 0..1 (a hand raised as they speak)."""
	L = dict(LOOKS[kind])
	if top is not None:
		L["top"] = top
	p = mt.Pen(24, 36, k)
	sk = SKIN[skin % 3]
	walking = phase is not None
	s = math.sin(phase * math.tau) if walking else 0.0
	c = math.cos(phase * math.tau) if walking else 0.0
	bob = abs(c) * 0.6 if walking else 0.0
	hip = (12, 22 + bob)
	# ground shadow
	p.ellipse([5, 33, 19, 35.5], fill=(0, 0, 0, 60))
	# legs: thigh and shin, the knee bends on the forward swing; boots
	def leg(sgn, shade_f):
		sw = s * sgn
		knee = (hip[0] + sw * 2.6, hip[1] + 5.2 - max(0, -sw) * 0.4)
		foot = (hip[0] + sw * 4.2 + (0.6 if sw > 0 else 0), 33.2 - max(0.0, sw * c * sgn) * 0.0)
		col = sh(L["legs"], shade_f)
		p.line([hip, knee], fill=col, width=2.6)
		p.line([knee, (foot[0], foot[1] - 1.4)], fill=col, width=2.3)
		p.rounded_rectangle([foot[0] - 1.4, foot[1] - 2.2, foot[0] + 2.6, foot[1]], 0.8, fill=sh(BOOT, shade_f))
	leg(-1, 0.78)
	# back arm
	shoulder = (12.2 + bend * 2.5, 13.4 + bob + bend * 1.5)
	def arm(sgn, shade_f, front):
		if carry == "crate" and not front:
			return
		sw = -s * sgn * (0.5 if carry else 1.0)
		elbow = (shoulder[0] + sw * 2.2, shoulder[1] + 4.2)
		hand = (shoulder[0] + sw * 3.6 + 0.4, shoulder[1] + 8.2)
		if carry == "crate" and front:
			elbow = (shoulder[0] + 1.6, shoulder[1] + 3.4); hand = (shoulder[0] + 0.6, shoulder[1] + 1.2)
		if carry in ("bundle", "sack") and front:
			elbow = (shoulder[0] + 2.0, shoulder[1] + 3.2); hand = (shoulder[0] + 2.4, shoulder[1] - 1.0)
		if front and tool is not None:
			if swing is None:
				elbow = (shoulder[0] + 2.2, shoulder[1] + 3.4); hand = (shoulder[0] + 2.6, shoulder[1] + 0.6)
			elif tool == "rod":
				elbow = (shoulder[0] + 2.6, shoulder[1] + 3); hand = (shoulder[0] + 5, shoulder[1] + 3.4)
			elif tool == "seed":
				elbow = (shoulder[0] + 2.4, shoulder[1] + 3.4); hand = (shoulder[0] + 4.6, shoulder[1] + 5.6 + swing)
			elif swing == 0:
				elbow = (shoulder[0] + 0.4, shoulder[1] - 2.2); hand = (shoulder[0] - 1.2, shoulder[1] - 5.2)
			else:
				elbow = (shoulder[0] + 3.2, shoulder[1] + 2.2); hand = (shoulder[0] + 6.2, shoulder[1] + 4.2)
			_tool(p, tool, hand, swing)
		if front and talk is not None:
			up = 0.5 + 0.5 * math.sin(talk * math.tau)
			elbow = (shoulder[0] + 3.0, shoulder[1] + 2.6 - up)
			hand = (shoulder[0] + 5.6, shoulder[1] - 0.6 - up * 2.4)
		sleeve = sh(L["top"], shade_f)
		p.line([shoulder, elbow], fill=sleeve, width=2.4)
		p.line([elbow, hand], fill=sleeve, width=2.1)
		p.disc(hand[0] + 0.5, hand[1] + 0.5, 1.15, sh(sk, shade_f))
	arm(-1, 0.75, False)
	# cloak behind (noble)
	if L.get("cloak"):
		flap = s * 1.4
		p.polygon([(9.5, 13.5 + bob), (14.5, 13.5 + bob), (8 - flap, 29 + bob), (4.5 - flap, 28 + bob)], fill=L["cloak"], outline=sh(L["cloak"], 0.6), width=0.4)
	# body: tunic or dress, shaded left to right
	top = L["top"]
	tx = bend * 2.5
	if L.get("skirt"):
		body = [(9.2 + tx, 12.6 + bob), (15 + tx, 12.6 + bob), (16.8, 27.5 + bob), (7.4, 27.5 + bob)]
		p.polygon(body, fill=top, outline=sh(top, 0.6), width=0.4)
		p.polygon([(8.3, 21 + bob), (15.9, 21 + bob), (17.2, 28.5 + bob), (7, 28.5 + bob)], fill=L["legs"], outline=sh(L["legs"], 0.6), width=0.4)
	else:
		body = [(9 + tx, 12.6 + bob), (15.2 + tx, 12.6 + bob), (15.8, 23 + bob), (8.4, 23 + bob)]
		p.polygon(body, fill=top, outline=sh(top, 0.6), width=0.4)
	p.shade(body, 12, 24, (255, 255, 255, 40), (0, 0, 0, 40))
	p.line([(10.5 + tx, 12.8 + bob), (12.1 + tx, 15 + bob), (13.7 + tx, 12.8 + bob)], fill=sh(top, 0.6), width=0.5)  # collar
	if L.get("apron"):
		p.polygon([(10.2 + tx * 0.6, 16.5 + bob), (14.6 + tx * 0.6, 16.5 + bob), (15.4, 25 + bob), (9.6, 25 + bob)], fill=L["apron"], outline=sh(L["apron"], 0.6), width=0.4)
	if L.get("belt"):
		p.line([(8.7 + tx * 0.5, 19.2 + bob), (15.6 + tx * 0.5, 19.2 + bob)], fill=L["belt"], width=1.0)
		p.rectangle([11.6 + tx * 0.5, 18.7 + bob, 12.6 + tx * 0.5, 19.7 + bob], fill=(210, 190, 110, 255))
	if not L.get("skirt"):
		leg(1, 1.0)
	# head: neck, face with eye, nose, ear; hair behind
	hx, hy = 12.6 + bend * 3.2, 8.6 + bob + bend * 1.6
	p.rectangle([hx - 0.9, hy + 2.6, hx + 0.9, hy + 4.4], fill=sh(sk, 0.85))
	hcol = HAIR[hair % 4]
	p.ellipse([hx - 3.6, hy - 3.8, hx + 3.0, hy + 2.8], fill=hcol)
	p.ellipse([hx - 3.0, hy - 3.2, hx + 3.6, hy + 3.4], fill=sk, outline=sh(sk, 0.7), width=0.3)
	p.ellipse([hx - 3.6, hy - 3.9, hx + 2.6, hy - 0.4], fill=hcol)  # fringe
	p.point((hx + 1.7, hy + 0.2), fill=(36, 28, 24, 255))
	p.line([(hx + 3.4, hy + 0.6), (hx + 3.9, hy + 1.6), (hx + 3.3, hy + 1.8)], fill=sh(sk, 0.75), width=0.5)
	p.line([(hx + 1.4, hy + 2.3), (hx + 2.6, hy + 2.3)], fill=sh(sk, 0.6), width=0.4)
	p.ellipse([hx - 1.4, hy - 0.2, hx - 0.2, hy + 1.4], fill=sh(sk, 0.85))  # ear
	hat = L.get("hat")
	if hat == "straw":
		p.ellipse([hx - 6, hy - 3.2, hx + 6.4, hy - 1.2], fill=(214, 186, 110, 255), outline=(150, 124, 64, 255), width=0.3)
		p.pieslice([hx - 3.4, hy - 6.4, hx + 3.8, hy - 0.8], 180, 360, fill=(222, 196, 120, 255), outline=(150, 124, 64, 255), width=0.3)
		p.line([(hx - 3.2, hy - 2.6), (hx + 3.6, hy - 2.6)], fill=(170, 60, 50, 255), width=0.6)
	elif hat == "cap":
		p.pieslice([hx - 3.6, hy - 5, hx + 3.4, hy + 0.6], 180, 360, fill=(60, 64, 80, 255), outline=(36, 38, 50, 255), width=0.3)
		p.polygon([(hx + 2, hy - 2.4), (hx + 5.4, hy - 1.8), (hx + 2, hy - 1.2)], fill=(40, 42, 54, 255))
	elif hat == "feather":
		p.ellipse([hx - 5.4, hy - 3.8, hx + 5.8, hy - 1.8], fill=(40, 30, 50, 255))
		p.rounded_rectangle([hx - 3.2, hy - 7.2, hx + 3.4, hy - 2.6], 1.2, fill=(52, 38, 64, 255), outline=(30, 22, 36, 255), width=0.3)
		p.line([(hx - 2.2, hy - 6), (hx - 5.6, hy - 10.2), (hx - 6.4, hy - 8)], fill=(236, 230, 210, 255), width=0.9)
	elif hat == "kerchief":
		p.pieslice([hx - 3.8, hy - 4.6, hx + 3.6, hy + 2.2], 160, 380, fill=(230, 222, 196, 255), outline=(160, 150, 120, 255), width=0.3)
		p.disc(hx - 3.8, hy + 1.4, 1.4, (230, 222, 196, 255))
	elif hat == "hood":
		p.polygon([(hx - 4.2, hy + 3), (hx - 3.8, hy - 3.6), (hx + 0.4, hy - 5), (hx + 3.6, hy - 2.6), (hx + 3.2, hy - 0.8), (hx - 1, hy - 1.2), (hx - 1.4, hy + 3.4)], fill=(110, 104, 90, 255), outline=(70, 66, 56, 255), width=0.3)
	# loads
	if carry == "crate":
		# an A-frame on the back with a crate lashed to it
		bx = 4.2 + bend * 2.0
		by = 10.5 + bob + bend * 1.2
		p.line([(bx + 1, by + 12), (bx + 3.5, by - 1.5)], fill=WOOD, width=0.9)
		p.line([(bx + 4.8, by + 12), (bx + 3.5, by - 1.5)], fill=WOOD, width=0.9)
		p.rounded_rectangle([bx - 1.2, by, bx + 6.4, by + 8.2], 0.5, fill=(168, 120, 70, 255), outline=(96, 66, 36, 255), width=0.5)
		p.line([(bx - 1.2, by + 4.1), (bx + 6.4, by + 4.1)], fill=(120, 84, 48, 255), width=0.5)
		p.line([(bx + 2.6, by), (bx + 2.6, by + 8.2)], fill=(120, 84, 48, 255), width=0.4)
		p.line([(bx + 5.5, by + 1.5), (shoulder[0] + 0.5, shoulder[1] + 1.5)], fill=(80, 60, 40, 255), width=0.6)  # strap
	elif carry == "bundle":
		p.ellipse([hx - 2.5, hy - 9.5, hx + 6.5, hy - 3.2], fill=(196, 186, 150, 255), outline=(130, 120, 90, 255), width=0.4)
		p.line([(hx + 2, hy - 9.4), (hx + 2, hy - 3.4)], fill=(150, 90, 60, 255), width=0.5)
	elif carry == "sack":
		p.rounded_rectangle([hx - 4, hy - 8.4, hx + 5, hy - 3], 2, fill=(206, 190, 150, 255), outline=(140, 124, 90, 255), width=0.4)
	arm(1, 1.0, True)
	im = p.done()
	return im if facing > 0 else im.transpose(Image.FLIP_LEFT_RIGHT)


# --- loads drawn as goods, not icons -------------------------------------------------------------

def _tool(p, tool, hand, swing):
	"""The tool in a hand: on the shoulder while walking (swing None), raised (0) or striking (1)."""
	hx, hy = hand
	if tool == "rod":
		if swing is None:
			tip = (hx - 8, hy - 10)
		else:
			tip = (hx + 9, hy - 9) if swing == 0 else (hx + 10, hy - 4)
		p.line([(hx, hy), tip], fill=(130, 96, 60, 255), width=0.7)
		if swing is not None:
			p.line([tip, (tip[0] + 0.5, hy + 14)], fill=(235, 235, 235, 190), width=0.3)
		return
	if tool == "seed":
		if swing is None:
			p.rounded_rectangle([hx - 1.6, hy - 0.4, hx + 2.2, hy + 3.4], 0.8, fill=(176, 140, 90, 255), outline=(110, 84, 50, 255), width=0.3)
		else:
			for j in range(3):
				p.disc(hx + 1.5 + j * 1.3, hy + 2 + j * 1.6 + swing, 0.55, (210, 190, 120, 255))
		return
	if swing is None:
		a = (hx + 3.5, hy + 3.5); head = (hx - 6, hy - 6); d = -1
	elif swing == 0:
		a = (hx + 2.5, hy + 3.5); head = (hx - 4.5, hy - 5.5); d = -1
	else:
		a = (hx - 3, hy - 2.5); head = (hx + 6, hy + 5); d = 1
	p.line([a, head], fill=(130, 92, 56, 255), width=0.9)
	x, y = head
	if tool == "axe":
		p.polygon([(x - 2.2 * d, y - 2.6), (x + 1.2 * d, y - 3.0), (x + 1.8 * d, y + 1.8), (x - 1.6 * d, y + 1.4)], fill=(196, 202, 210, 255), outline=(90, 94, 100, 255), width=0.3)
	elif tool == "pick":
		p.line([(x - 3.2, y + 2.2), (x, y - 0.8), (x + 3.2, y + 2.2)], fill=(150, 154, 160, 255), width=1.0)
	elif tool == "shovel":
		p.rounded_rectangle([x - 1.8, y - 1.8, x + 1.8, y + 2.4], 0.8, fill=(176, 180, 186, 255), outline=(90, 94, 100, 255), width=0.3)
	elif tool == "hammer":
		p.rectangle([x - 2.2, y - 1.4, x + 2.2, y + 1.4], fill=(120, 124, 130, 255), outline=(70, 72, 78, 255), width=0.3)


def _load(p, kind, x, y, n):
	"""n units of goods kind stacked with their bottom-left at (x, y)."""
	if kind == "planks":
		for i in range(n):
			p.rounded_rectangle([x + (i % 2) * 0.6, y - 1.8 - i * 1.7, x + 13 + (i % 2) * 0.6, y - 0.4 - i * 1.7], 0.4,
								fill=(206, 164, 104, 255), outline=(140, 100, 56, 255), width=0.3)
	elif kind == "stone":
		for i in range(n):
			cx = x + 2 + (i % 3) * 4.2 + (i // 3) * 2
			cy = y - 2.4 - (i // 3) * 3.4
			p.rounded_rectangle([cx - 2, cy - 1.8, cx + 2, cy + 1.8], 0.8, fill=(160, 160, 158, 255), outline=(100, 100, 100, 255), width=0.3)
	elif kind == "grain":
		for i in range(n):
			cx = x + 2.5 + (i % 3) * 4.4 + (i // 3) * 2.2
			cy = y - 3 - (i // 3) * 3.6
			p.ellipse([cx - 2.6, cy - 2.4, cx + 2.6, cy + 2.6], fill=(222, 204, 160, 255), outline=(150, 132, 92, 255), width=0.3)
			p.line([(cx - 1, cy - 2.2), (cx + 1, cy - 2.2)], fill=(150, 110, 70, 255), width=0.4)
	elif kind == "crates":
		for i in range(n):
			cx = x + (i % 3) * 4.4 + (i // 3) * 2.2
			cy = y - (i // 3) * 3.8
			p.rounded_rectangle([cx, cy - 3.8, cx + 4, cy], 0.4, fill=(172, 124, 72, 255), outline=(96, 66, 36, 255), width=0.35)
			p.line([(cx, cy - 1.9), (cx + 4, cy - 1.9)], fill=(124, 86, 50, 255), width=0.3)
	elif kind == "wood":
		for i in range(n):
			cx = x + 1 + (i % 3) * 0.6
			cy = y - 1.6 - i * 2.4
			p.rounded_rectangle([cx, cy - 1.2, cx + 13, cy + 1.2], 1.2, fill=(140, 96, 58, 255), outline=(90, 60, 34, 255), width=0.3)
			p.disc(cx + 12.6, cy, 1.1, (210, 170, 110, 255))


def ox_cart(phase, load="stone", n=5, k=2, only_load=False):
	"""An ox pulling a two-wheeled cart, 48 x 26 design pixels, facing right. phase 0..1."""
	p = mt.Pen(50, 26, k)
	if only_load:
		_load(p, load, 5.5, 12, n)
		return p.done()
	s = math.sin(phase * math.tau)
	p.ellipse([2, 23, 46, 25.6], fill=(0, 0, 0, 55))
	# ox: legs (four, alternating), body, head with horns, yoke, tail
	ox = (130, 98, 70, 255)
	for x, ph in ((31, 0), (33, 1), (39.5, 1), (41.5, 0)):
		o = s * 1.8 * (1 if ph else -1)
		col = sh(ox, 0.72 if x in (33, 41.5) else 0.85)
		p.line([(x, 15.5), (x + o * 0.6, 19.5)], fill=col, width=1.6)
		p.line([(x + o * 0.6, 19.5), (x + o, 23)], fill=col, width=1.3)
		p.rectangle([x + o - 0.8, 22.6, x + o + 0.8, 23.6], fill=(50, 40, 32, 255))
	p.ellipse([28, 9, 43.5, 18], fill=ox, outline=sh(ox, 0.6), width=0.4)
	p.shade([(28, 9), (43.5, 9), (43.5, 18), (28, 18)], 9, 18, (255, 255, 255, 30), (0, 0, 0, 50))
	p.line([(28.4, 11), (26.6 - s * 0.8, 16.5)], fill=sh(ox, 0.6), width=0.7)  # tail
	p.disc(26.4 - s * 0.8, 16.8, 0.8, (60, 44, 30, 255))
	hb = s * 0.4
	p.ellipse([41.5, 8 + hb, 47.6, 14 + hb], fill=sh(ox, 0.95), outline=sh(ox, 0.6), width=0.4)
	p.ellipse([45.2, 10.6 + hb, 47.8, 13.4 + hb], fill=(200, 160, 140, 255))  # muzzle
	p.point((44.2, 10 + hb), fill=(20, 16, 14, 255))
	p.line([(43, 8.4 + hb), (41.6, 5.4 + hb), (43.2, 4.6 + hb)], fill=(236, 226, 196, 255), width=0.8)  # horn
	p.line([(42.2, 9.6 + hb), (40.8, 8.4 + hb)], fill=sh(ox, 0.7), width=1.0)  # ear
	p.line([(40.5, 7.6), (41.2, 12.5)], fill=WOOD, width=1.2)  # yoke
	# shaft from the cart to the yoke
	p.line([(24, 15), (41, 11)], fill=WOOD, width=1.0)
	# cart: bed with boards, side rails, load, wheel with turning spokes and an iron rim
	p.polygon([(2, 12), (25, 12), (25, 16.5), (2, 16.5)], fill=(150, 108, 64, 255), outline=(92, 64, 36, 255), width=0.5)
	for x in (7, 12.5, 18, 23):
		p.line([(x, 12.2), (x, 16.3)], fill=(116, 82, 48, 255), width=0.35)
	p.line([(2, 9), (25, 9)], fill=WOOD, width=0.8)
	for x in (2.6, 13.5, 24.4):
		p.line([(x, 9), (x, 12)], fill=WOOD, width=0.7)
	if load:
		_load(p, load, 5.5, 12, n)
	cx, cy, r = 13, 19.2, 5.2
	p.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(98, 70, 42, 255), outline=IRON, width=0.9)
	a0 = phase * math.tau / 2  # half a turn a step
	for j in range(8):
		a = a0 + j * math.pi / 4
		p.line([(cx, cy), (cx + math.cos(a) * (r - 0.7), cy + math.sin(a) * (r - 0.7))], fill=(176, 132, 84, 255), width=0.6)
	p.disc(cx + 0.5, cy + 0.5, 1.3, IRON)
	return p.done()


def mule(phase, loads=("grain", "bread"), k=2):
	"""A pack mule with a pannier on each side and a bridle, 34 x 26 design pixels, facing right."""
	p = mt.Pen(34, 26, k)
	s = math.sin(phase * math.tau)
	body = (150, 128, 106, 255)
	p.ellipse([4, 23, 30, 25.6], fill=(0, 0, 0, 55))
	for x, ph in ((8, 0), (10.5, 1), (21, 1), (23.5, 0)):
		o = s * 1.8 * (1 if ph else -1)
		col = sh(body, 0.7 if x in (10.5, 23.5) else 0.85)
		p.line([(x, 15.5), (x + o * 0.6, 19.6)], fill=col, width=1.4)
		p.line([(x + o * 0.6, 19.6), (x + o, 23.2)], fill=col, width=1.1)
		p.rectangle([x + o - 0.7, 22.8, x + o + 0.7, 23.7], fill=(40, 34, 30, 255))
	p.ellipse([4.5, 8.5, 26, 17.5], fill=body, outline=sh(body, 0.6), width=0.4)
	p.ellipse([5, 15, 25, 17.8], fill=sh(body, 1.25))  # pale belly
	p.line([(5, 10.5), (2.6 - s, 17)], fill=sh(body, 0.55), width=0.8)  # tail
	hb = s * 0.5
	p.polygon([(23, 11), (27.5, 3.5 + hb), (32.6, 6 + hb), (32, 9.6 + hb), (27, 14)], fill=body, outline=sh(body, 0.6), width=0.4)
	p.ellipse([29.8, 6.8 + hb, 33.2, 9.8 + hb], fill=sh(body, 0.8))
	p.line([(27.6, 3.8 + hb), (26.4, -0.4 + hb)], fill=sh(body, 0.7), width=1.0)  # ears
	p.line([(28.8, 3.6 + hb), (29.4, -0.6 + hb)], fill=sh(body, 0.75), width=1.0)
	p.point((30.2, 5.4 + hb), fill=(20, 16, 14, 255))
	p.line([(27.4, 4.8 + hb), (31.6, 8.8 + hb), (28.4, 9.8 + hb)], fill=(110, 60, 40, 255), width=0.5)  # bridle
	# pack saddle and panniers with goods showing at the top
	p.rounded_rectangle([9, 6, 21, 10], 1.2, fill=(120, 70, 50, 255), outline=(80, 44, 30, 255), width=0.4)
	p.rounded_rectangle([7.5, 9, 14.5, 17], 1.2, fill=(180, 150, 96, 255), outline=(120, 96, 56, 255), width=0.5)
	for yy in (11.5, 14):
		p.line([(7.7, yy), (14.3, yy)], fill=(140, 112, 66, 255), width=0.35)
	p.rounded_rectangle([15.5, 9, 22.5, 17], 1.2, fill=(186, 156, 100, 255), outline=(120, 96, 56, 255), width=0.5)
	for yy in (11.5, 14):
		p.line([(15.7, yy), (22.3, yy)], fill=(140, 112, 66, 255), width=0.35)
	look = {"grain": (222, 204, 160, 255), "bread": (196, 130, 64, 255), "stone": (160, 160, 158, 255), "planks": (206, 164, 104, 255)}
	for (x0, x1), g in zip(((8.4, 13.6), (16.4, 21.6)), loads):
		for j in range(3):
			p.disc(x0 + 1 + j * 1.8, 8.6 - (j % 2) * 0.6, 1.3, look.get(g, (200, 200, 200, 255)))
	return p.done()

# --- strips for the game ------------------------------------------------------------------------

KEY = (255, 0, 255, 255)


def _tinted(make):
	"""(picture, tint layer) for a person drawn by make(top): the tunic is found by drawing it once in
	its own colour and once in a key colour; the tint layer keeps the tunic alone, in grey, so the game
	can draw it again in the realm's colour."""
	import numpy as np
	base = make(None)
	keyed = make(KEY)
	a = np.asarray(base).astype(np.int32)
	b = np.asarray(keyed).astype(np.int32)
	keyness = np.clip((b[:, :, 0] + b[:, :, 2] - 2 * b[:, :, 1]) / 255.0 - 0.5, 0.0, 1.0) * 2.0
	keyness = np.minimum(keyness, b[:, :, 3] / 255.0)
	diff = np.abs(a[:, :, :3] - b[:, :, :3]).sum(axis=2) > 40
	m = np.where(diff, keyness, 0.0)
	shade = np.clip((b[:, :, 0] + b[:, :, 2]) / 2.0 / 255.0, 0.0, 1.0)
	g = np.clip(150 + shade * 105, 0, 255)
	t = np.zeros(a.shape, np.uint8)
	t[:, :, 0] = g; t[:, :, 1] = g; t[:, :, 2] = g
	t[:, :, 3] = (m * a[:, :, 3]).astype(np.uint8)
	return base, Image.fromarray(t, "RGBA")


def _save(img, name):
	img.save(os.path.join(mt.OUT, name + ".png"))


def build_all(k=2):
	walk = [j / 8 for j in range(8)]
	# townsfolk: 8 walking frames, 2 talking, 1 standing
	for kind in ("peasant", "woman", "artisan", "noble", "child", "newcomer"):
		fr = [person(kind, ph, k=k, carry="bundle" if kind == "newcomer" else None) for ph in walk]
		fr += [person(kind, None, talk=t, k=k) for t in (0.25, 0.75)]
		fr += [person(kind, None, k=k)]
		_save(mt.strip(fr), "unit_folk_" + kind)
	# porters: 8 frames loaded, 8 empty, then setting the load down (2): a man with an A-frame, a woman with a sack
	for name, kind, load in (("unit_porter", "peasant", "crate"), ("unit_porter_w", "woman", "sack")):
		pics, tints = [], []
		for ph in walk:
			pi, ti = _tinted(lambda top, ph=ph: person(kind, ph, carry=load, k=k, top=top)); pics.append(pi); tints.append(ti)
		for ph in walk:
			pi, ti = _tinted(lambda top, ph=ph: person(kind, ph, k=k, top=top)); pics.append(pi); tints.append(ti)
		for c, b in ((load, 0.9), (None, 0.6)):
			pi, ti = _tinted(lambda top, c=c, b=b: person(kind, None, carry=c, bend=b, k=k, top=top)); pics.append(pi); tints.append(ti)
		_save(mt.strip(pics), name); _save(mt.strip(tints), name + "_tint")
	# workers with their tools: 8 walking frames (tool on the shoulder), then raised and striking
	for tool in ("axe", "pick", "shovel", "rod", "seed", "hammer"):
		pics, tints = [], []
		for ph in walk:
			pi, ti = _tinted(lambda top, ph=ph: person("peasant", ph, tool=tool, k=k, top=top, hair=1)); pics.append(pi); tints.append(ti)
		for sw in (0, 1):
			bend = 0.7 if sw == 1 and tool in ("shovel", "seed", "pick") else 0.0
			pi, ti = _tinted(lambda top, sw=sw, bend=bend: person("peasant", None, tool=tool, swing=sw, bend=bend, k=k, top=top, hair=1)); pics.append(pi); tints.append(ti)
		_save(mt.strip(pics), "unit_worker_" + tool); _save(mt.strip(tints), "unit_worker_" + tool + "_tint")
	# a pack mule and an ox cart (empty: its load is drawn over it), 8 frames each
	_save(mt.strip([mule(ph, loads=("grain", "planks"), k=k) for ph in walk]), "unit_mule")
	_save(mt.strip([ox_cart(ph, load=None, k=k) for ph in walk]), "unit_cart")
	# cart loads: 6 frames, from 1 to 6 units, drawn over the cart picture
	for kind in ("planks", "stone", "grain", "wood", "crates"):
		_save(mt.strip([ox_cart(0, load=kind, n=n, k=k, only_load=True) for n in range(1, 7)]), "unit_load_" + kind)


if __name__ == "__main__":
	build_all()
	print("folk sprites written to", mt.OUT)
