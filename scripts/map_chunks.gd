class_name MapChunks
extends RefCounted
## Bakes the parts of the map that rarely change (ground, roads, scenery, ore, territory) into large
## images of 16 x 16 tiles called chunks. Drawing a few dozen chunks each frame is far cheaper than
## drawing thousands of separate tiles. A chunk is baked again only when something inside it changes.
## Where two kinds of ground meet, the higher one (beach over water, grass over beach, mountain over
## grass) spills softly over the edge. Open water is baked half transparent: the ground shader uses
## that as a marker to make the water shimmer.

const CH := 16             # tiles along each side of a chunk
var TS := 32               # pixels per tile inside a chunk (16 in the low-resolution twin)
const MAX_CHUNKS := 120    # chunks kept in memory; the least recently seen are forgotten first
const WATER_ALPHA := 128   # alpha of open water in a baked chunk (255 = land)
const EDGE_WIDTH := [0.0, 11.0, 8.0, 7.0]   # pixels each kind of ground spills over a lower neighbour
## Neighbour offsets, in mask bit order: N, E, S, W, then the corners NE, SE, SW, NW.
const NB := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]

var sim: Sim
var twin: MapChunks        # the same map at half resolution, used when zoomed out (see MapView)
var smooth := false        # build mipmaps so chunks look smooth when zoomed out; call clear() after changing it
var _tex: Dictionary = {}  # chunk key -> ImageTexture
var _dirty: Dictionary = {}
var _used: Dictionary = {} # chunk key -> frame it was last drawn
var _frame := 0
var _territory := -1       # territory version the chunks were baked with
var _owners := PackedByteArray()   # the owner of every tile when the chunks were last brought up to date
var _ter: Array = []
var _road: Array = []
var _paved: Array = []
var _clay: Image
var _ore: Dictionary = {}
var _tint: Array = []
var ver := 0               # goes up whenever every chunk is to be baked again (the map view's scenery follows)
var _edge: Dictionary = {}  # ground kind * 256 + neighbour mask -> soft edge overlay, made when first needed


## Reads every texture the chunks use, as plain images at chunk resolution. Call after textures change.
func load_images() -> void:
	if twin != null:
		twin.sim = sim
		twin.smooth = smooth
		twin.details = details
		twin.load_images()
	_ter.clear(); _road.clear(); _paved.clear(); _ore.clear(); _edge.clear(); _snow.clear()
	for t in Tex.TERRAIN:
		for v in Tex.VARIANTS:
			var img := _img("terrain_%s_%d" % [t, v], TS, TS)
			if t == "water":
				var data := img.get_data()
				for k in range(3, data.size(), 4):
					data[k] = WATER_ALPHA
				img.set_data(TS, TS, false, Image.FORMAT_RGBA8, data)
			_ter.append(img)
	for m in 16:
		_road.append(_img("road_%d" % m, TS, TS))
		_paved.append(_img("road_paved_%d" % m, TS, TS))
	_clay = _img("deco_clay", TS, TS)
	for o in GameData.ORE_NAMES:
		_ore[o] = _img("ore_%d" % o, TS / 2, TS / 2)
	clear()


## A texture as an uncompressed RGBA image of exactly w x h pixels, so custom textures of any size fit.
func _img(id: String, w: int, h: int) -> Image:
	var img := Tex.get_tex(id).get_image()
	if img == null:
		img = Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color.MAGENTA)
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != w or img.get_height() != h:
		img.resize(w, h, Image.INTERPOLATE_BILINEAR if img.get_width() > w else Image.INTERPOLATE_NEAREST)
	return img


## Forgets every baked chunk (new game, loaded game, new textures).
func clear() -> void:
	ver += 1
	if twin != null:
		twin.sim = sim
		twin.smooth = smooth
		twin.details = details
		twin.clear()
	_tex.clear()
	_dirty.clear()
	_used.clear()
	_territory = -1
	_owners = PackedByteArray()


func mark_all() -> void:
	ver += 1
	if twin != null:
		twin.sim = sim
		twin.smooth = smooth
		twin.details = details
		twin.mark_all()
	for k in _tex:
		_dirty[k] = true


## Something on tile i changed: re-bake the chunks that can show it. Neighbours count too, because
## road shapes depend on the tiles next door and trees reach into the tile above.
func mark_tile(i: int) -> void:
	if twin != null:
		twin.sim = sim
		twin.smooth = smooth
		twin.details = details
		twin.mark_tile(i)
	var x := i % sim.w
	var y := i / sim.w
	for yy in [y - 1, y, y + 1]:
		for xx in [x - 1, x, x + 1]:
			if xx >= 0 and yy >= 0 and xx < sim.w and yy < sim.h:
				var k: int = (yy / CH) * 1000 + xx / CH
				if _tex.has(k):
					_dirty[k] = true


## Call once per frame before drawing.
func begin_frame() -> void:
	_frame += 1
	if sim.territory_version != _territory:
		_territory = sim.territory_version
		if _tint.size() != sim.players.size():
			_tint.clear()
			for p in sim.players:
				var t := Image.create(TS, TS, false, Image.FORMAT_RGBA8)
				t.fill(Color(p.color, 0.16))
				_tint.append(t)
		_mark_owner_changes()
	if _tex.size() > MAX_CHUNKS:
		var keys := _tex.keys()
		keys.sort_custom(func(a, b): return int(_used.get(a, 0)) < int(_used.get(b, 0)))
		for n in keys.size() - MAX_CHUNKS:
			_tex.erase(keys[n])
			_dirty.erase(keys[n])
			_used.erase(keys[n])


## Borders moved: re-bake only chunks where a tile changed hands, not every chunk. Each map row is
## compared a chunk's width at a time (a fast built-in comparison); only differing pieces are
## checked tile by tile, and mark_tile() also catches the border lines of neighbouring tiles.
func _mark_owner_changes() -> void:
	var now := sim.owner
	if _owners.size() != now.size():
		_owners = now.duplicate()
		mark_all()
		return
	for y in sim.h:
		var row := y * sim.w
		for x0 in range(0, sim.w, CH):
			var a := row + x0
			var e := mini(a + CH, row + sim.w)
			if _owners.slice(a, e) == now.slice(a, e):
				continue
			for i in range(a, e):
				if _owners[i] != now[i]:
					mark_tile(i)
	_owners = now.duplicate()


## The texture for chunk (cx, cy). Bakes it when missing or out of date while time is left this frame:
## budget is [deadline in microseconds, chunks baked so far]. At least one chunk is baked per frame,
## and baking stops once the deadline passes, so the game never stalls. May return null until baked.
func get_chunk(cx: int, cy: int, budget: Array) -> Texture2D:
	var k := cy * 1000 + cx
	_used[k] = _frame
	if (not _tex.has(k) or _dirty.has(k)) and (int(budget[1]) == 0 or Time.get_ticks_usec() < int(budget[0])):
		budget[1] = int(budget[1]) + 1
		_bake(cx, cy, k)
	return _tex.get(k)


func _bake(cx: int, cy: int, k: int) -> void:
	var img := Image.create(CH * TS, CH * TS, false, Image.FORMAT_RGBA8)
	var w := sim.w
	var h := sim.h
	var full := Rect2i(0, 0, TS, TS)
	var x0 := cx * CH
	var y0 := cy * CH
	var relief := _relief(x0, y0)
	# ground, roads and the territory tint
	for ly in CH:
		var y := y0 + ly
		if y >= h:
			break
		for lx in CH:
			var x := x0 + lx
			if x >= w:
				break
			var i := y * w + x
			var pos := Vector2i(lx * TS, ly * TS)
			var t := int(sim.ter[i])
			img.blit_rect(_ter[t * 4 + sim.shade[i]], full, pos)
			for u in range(t + 1, 4):
				var m := _edge_mask(x, y, u)
				if m != 0:
					img.blend_rect(_edge_img(u, m), full, pos)
			# hills: slopes facing the light are lighter, the others darker (not on open water, whose
			# alpha the water shader reads)
			if relief != null and t != 0:
				img.blend_rect(relief, Rect2i(pos, Vector2i(TS, TS)), pos)
			if details:
				_details(img, pos, x, y, i, t)
			if sim.road[i] != 0 and sim.bmap[i] == 0:
				var m := 0
				if y > 0 and (sim.road[i - w] != 0 or (sim.bmap[i - w] != 0 and sim.links(i, i - w))): m |= 1
				if x < w - 1 and (sim.road[i + 1] != 0 or (sim.bmap[i + 1] != 0 and sim.links(i, i + 1))): m |= 2
				if y < h - 1 and (sim.road[i + w] != 0 or (sim.bmap[i + w] != 0 and sim.links(i, i + w))): m |= 4
				if x > 0 and (sim.road[i - 1] != 0 or (sim.bmap[i - 1] != 0 and sim.links(i, i - 1))): m |= 8
				img.blend_rect(_paved[m] if sim.pave[i] == 1 else _road[m], full, pos)
			var o := sim.owner[i]
			if o != 0 and o <= _tint.size():
				img.blend_rect(_tint[o - 1], full, pos)
			# how steep the road is here: no mark when flat, then 1 to 3 marks, yellow to red (as the
			# road markers in The Settlers II), so you can see where carriers will be slow
			if sim.road[i] != 0 and sim.bmap[i] == 0:
				var sl := sim.road_slope(i, int(sim.road[i]))
				if sl > 0:
					_slope_marks(img, pos, sl)
	# what lies flat on the ground: clay pits and ore. Trees, peaks and boulders stand up from the
	# ground, so the map view draws them itself (MapView._scenery_mesh) instead of baking them in, where
	# the raised ground would bend them.
	for ly in CH:
		var y := y0 + ly
		if y >= h:
			break
		for lx in CH:
			var x := x0 + lx
			if x >= w:
				break
			var i := y * w + x
			var d := sim.deco[i]
			var pos := Vector2i(lx * TS, ly * TS)
			if d == Sim.D_TREE or d == Sim.D_ROCK or (d == 0 and _has_peak(x, y, i)):
				continue
			if d == Sim.D_CLAY:
				img.blend_rect(_clay, full, pos)
			elif sim.ore[i] != 0 and _ore.has(int(sim.ore[i])) and sim.vein_left(i) > 0 and sim.ore_known(1, i):
				img.blend_rect(_ore[int(sim.ore[i])], Rect2i(0, 0, TS / 2, TS / 2), pos + Vector2i(TS / 4, TS * 7 / 16))
	# borders: a 2-pixel line in the owner's colour wherever the next tile belongs to someone else
	for ly in CH:
		var y := y0 + ly
		if y >= h:
			break
		for lx in CH:
			var x := x0 + lx
			if x >= w:
				break
			var i := y * w + x
			var o := sim.owner[i]
			if o == 0:
				continue
			var col: Color = sim.players[o - 1].color
			var px := lx * TS
			var py := ly * TS
			var bw := maxi(1, TS / 16)
			if y == 0 or sim.owner[i - w] != o: img.fill_rect(Rect2i(px, py, TS, bw), col)
			if y == h - 1 or sim.owner[i + w] != o: img.fill_rect(Rect2i(px, py + TS - bw, TS, bw), col)
			if x == 0 or sim.owner[i - 1] != o: img.fill_rect(Rect2i(px, py, bw, TS), col)
			if x == w - 1 or sim.owner[i + 1] != o: img.fill_rect(Rect2i(px + TS - bw, py, bw, TS), col)
	if smooth:
		img.generate_mipmaps()
	var old: ImageTexture = _tex.get(k)
	if old != null:
		old.update(img)
	else:
		_tex[k] = ImageTexture.create_from_image(img)
	_dirty.erase(k)


## Small things on the ground, baked in with it so they cost nothing to draw: grass tufts and the odd
## flower on grass, pebbles on beaches and grass, reeds where land meets water, foam along the shore,
## and snow on the highest mountain tiles. Each tile picks its details from a hash of its position, so
## they stay put when a chunk is baked again. Nothing is drawn under roads or buildings.
var details := true

func _details(img: Image, pos: Vector2i, x: int, y: int, i: int, t: int) -> void:
	if sim.road[i] != 0 or sim.bmap[i] != 0:
		return
	var h := _hash(x, y)
	var u := TS / 32.0           # one pixel of the full-size chunks
	var water_nb := 0
	for k in 4:
		var nx: int = x + NB[k].x
		var ny: int = y + NB[k].y
		if nx >= 0 and ny >= 0 and nx < sim.w and ny < sim.h and sim.ter[ny * sim.w + nx] == Sim.WATER:
			water_nb |= 1 << k
	if t == Sim.WATER:
		# foam: a broken light line just off the land
		var land := 15 & ~water_nb
		for k in 4:
			if not (land & (1 << k)):
				continue
			for j in 6:
				if (h >> j) & 1 == 0:
					continue
				var a := int((j * 5 + 1) * u)
				var o := int((2 + ((h >> (j + 6)) & 3)) * u)
				var th := maxi(1, int(2 * u))
				var ln := int(6 * u)
				var r: Rect2i
				match k:
					0: r = Rect2i(pos.x + a, pos.y + o, ln, th)
					1: r = Rect2i(pos.x + TS - o - th, pos.y + a, th, ln)
					2: r = Rect2i(pos.x + a, pos.y + TS - o - th, ln, th)
					3: r = Rect2i(pos.x + o, pos.y + a, th, ln)
				# alpha above open water's, so the water shader moves it only a little
				img.fill_rect(r.intersection(Rect2i(pos, Vector2i(TS, TS))), Color8(236, 244, 244, 225))
		return
	if sim.deco[i] != 0:
		return
	if t == Sim.MOUNT:
		# snow on the high tops: a cap that thickens with height
		if sim.height.size() == sim.w * sim.h:
			var hv := int(sim.height[i])
			if hv > 205:
				var cover := clampf((hv - 205) / 40.0, 0.15, 0.85)
				img.blend_rect(_snow_img(cover), Rect2i(0, 0, TS, TS), pos)
		return
	# reeds where grass or beach meets the water
	if water_nb != 0 and h % 4 == 0:
		for j in 1 + (h >> 4) % 2:
			var rx := pos.x + int((5 + j * 8 + (h >> (j * 3)) % 5) * u)
			var top := int((12 + (h >> (j + 2)) % 8) * u)
			var base_y := pos.y + int(28 * u)
			var bw := maxi(1, int(2 * u))
			img.fill_rect(Rect2i(rx, base_y - top, bw, top), Color8(78, 104, 40))
			img.fill_rect(Rect2i(rx + bw, base_y - top + int(4 * u), maxi(1, int(u)), top - int(4 * u)), Color8(108, 134, 58))
			# the brown head of a bulrush
			img.fill_rect(Rect2i(rx - maxi(1, int(u / 2)), base_y - top, bw + maxi(1, int(u)), maxi(2, int(5 * u))), Color8(104, 70, 38))
		return
	if t == Sim.GRASS:
		# tufts: three short blades, darker than the grass
		for j in 2 + h % 2:
			if (h >> (j * 4)) % 3 == 0:
				continue
			var cx := pos.x + int((4 + (h >> (j * 5 + 1)) % 24) * u)
			var cy := pos.y + int((8 + (h >> (j * 5 + 3)) % 20) * u)
			var c := Color8(58, 86, 32, 230)
			var c2 := Color8(132, 164, 76, 230)
			var bw2 := maxi(1, int(2 * u))
			img.fill_rect(Rect2i(cx, cy - int(6 * u), bw2, int(6 * u)), c)
			img.fill_rect(Rect2i(cx - int(3 * u), cy - int(4 * u), bw2, int(4 * u)), c)
			img.fill_rect(Rect2i(cx + int(3 * u), cy - int(4 * u), bw2, int(4 * u)), c)
			img.fill_rect(Rect2i(cx, cy - int(6 * u), maxi(1, int(u)), maxi(1, int(2 * u))), c2)
		# now and then a flower
		if h % 11 == 0:
			var fx := pos.x + int((6 + (h >> 7) % 20) * u)
			var fy := pos.y + int((6 + (h >> 11) % 20) * u)
			var fc: Color = [Color8(236, 220, 120), Color8(230, 236, 240), Color8(200, 120, 190)][(h >> 3) % 3]
			img.fill_rect(Rect2i(fx, fy, maxi(1, int(3 * u)), maxi(1, int(3 * u))), fc)
	# pebbles on beaches, and a few on grass
	if (t == Sim.BEACH and h % 2 == 0) or (t == Sim.GRASS and h % 9 == 0):
		for j in 2:
			var px := pos.x + int((5 + (h >> (j * 6 + 2)) % 22) * u)
			var py := pos.y + int((6 + (h >> (j * 6 + 5)) % 20) * u)
			img.fill_rect(Rect2i(px, py, maxi(1, int(3 * u)), maxi(1, int(3 * u))), Color8(158, 154, 140))
			img.fill_rect(Rect2i(px, py + maxi(1, int(3 * u)), maxi(1, int(3 * u)), maxi(1, int(u))), Color8(86, 80, 68, 180))


static func _hash(x: int, y: int) -> int:
	return absi((x * 73856093) ^ (y * 19349663) ^ 0x5bd1e995) % 1000003


var _snow := {}

## A whitish cover for a mountain tile, denser at the top, as a blendable image (cached by strength).
func _snow_img(cover: float) -> Image:
	var k := snappedf(cover, 0.1)
	if _snow.has(k):
		return _snow[k]
	var img := Image.create(TS, TS, false, Image.FORMAT_RGBA8)
	for py in TS:
		for px in TS:
			var n := sin(px * 0.9) * 0.08 + sin(py * 1.3 + px * 0.4) * 0.08
			var a := clampf(k - float(py) / TS * 0.6 + n, 0.0, 0.9)
			img.set_pixel(px, py, Color(0.96, 0.97, 1.0, a))
	_snow[k] = img
	return img


## Which neighbours of tile (x, y) are ground kind u or higher, as bits (see NB). A corner bit is kept
## only when neither side next to it is set, so fewer different overlays are needed.
func _edge_mask(x: int, y: int, u: int) -> int:
	var m := 0
	for k in 8:
		var nx: int = x + NB[k].x
		var ny: int = y + NB[k].y
		if nx >= 0 and ny >= 0 and nx < sim.w and ny < sim.h and sim.ter[ny * sim.w + nx] >= u:
			m |= 1 << k
	if m & 3: m &= ~16
	if m & 6: m &= ~32
	if m & 12: m &= ~64
	if m & 9: m &= ~128
	return m


## Ground kind u faded out from the edges and corners in mask m, so it lies softly over a lower tile.
## The fade line wobbles a little; the wobble repeats every tile so neighbouring overlays line up.
func _edge_img(u: int, m: int) -> Image:
	var key := u * 256 + m
	if _edge.has(key):
		return _edge[key]
	var data: PackedByteArray = (_ter[u * 4] as Image).get_data()
	var r: float = EDGE_WIDTH[u] * TS / 32.0
	for py in TS:
		for px in TS:
			var cx := px + 0.5
			var cy := py + 0.5
			var wx := 1.8 * sin(TAU * 2.0 * cx / TS + u) + 1.0 * sin(TAU * 5.0 * cx / TS + 1.7 * u)
			var wy := 1.8 * sin(TAU * 2.0 * cy / TS + 2.0 * u) + 1.0 * sin(TAU * 5.0 * cy / TS + u)
			var dist := 99.0
			if m & 1: dist = minf(dist, cy + wx)
			if m & 2: dist = minf(dist, TS - cx + wy)
			if m & 4: dist = minf(dist, TS - cy - wx)
			if m & 8: dist = minf(dist, cx - wy)
			if m & 16: dist = minf(dist, Vector2(TS - cx, cy).length() + wx * 0.5)
			if m & 32: dist = minf(dist, Vector2(TS - cx, TS - cy).length() + wy * 0.5)
			if m & 64: dist = minf(dist, Vector2(cx, TS - cy).length() - wx * 0.5)
			if m & 128: dist = minf(dist, Vector2(cx, cy).length() - wy * 0.5)
			var a := clampf(1.0 - dist / r, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			var k := (py * TS + px) * 4 + 3
			data[k] = int(data[k] * a)
	var img := Image.create_from_data(TS, TS, false, Image.FORMAT_RGBA8, data)
	_edge[key] = img
	return img


## Mountain peaks stand on some mountain tiles that are surrounded by mountain and hold nothing else.
func _has_peak(x: int, y: int, i: int) -> bool:
	# (peaks stand on unsurveyed ore too, so they don't give away where it is)
	if sim.ter[i] != 3 or (sim.ore[i] != 0 and sim.ore_known(1, i)) or sim.bmap[i] != 0 or sim.road[i] != 0:
		return false
	if x < 1 or y < 1 or x >= sim.w - 1 or y >= sim.h - 1:
		return false
	if sim.ter[i - 1] != 3 or sim.ter[i + 1] != 3 or sim.ter[i - sim.w] != 3 or sim.ter[i + sim.w] != 3:
		return false
	return ((x * 73856093) ^ (y * 19349663)) % 5 < 3


const SLOPE_COL := [Color(0, 0, 0), Color("f0d040"), Color("f09030"), Color("e04030")]


## 1 to 3 small marks in a row across the middle of a road tile, in a colour for how steep it is.
func _slope_marks(img: Image, pos: Vector2i, level: int) -> void:
	var s := maxi(3, TS / 7)
	var gap := s + maxi(1, TS / 16)
	var x := pos.x + TS / 2 - (level * gap - (gap - s)) / 2
	var y := pos.y + TS / 2 - s / 2
	for k in level:
		img.fill_rect(Rect2i(x + k * gap - 1, y - 1, s + 2, s + 2), Color(0.15, 0.1, 0.05, 0.9))
		img.fill_rect(Rect2i(x + k * gap, y, s, s), SLOPE_COL[level])


## The hill shading for the chunk whose top-left tile is (x0, y0): a picture the size of the chunk,
## light where the ground faces the light (from the upper left), dark where it faces away, a little
## lighter higher up. Worked out per tile and smoothed, so slopes fade softly.
func _relief(x0: int, y0: int) -> Image:
	if sim.height.size() != sim.w * sim.h:
		return null
	var n := CH + 2
	var data := PackedByteArray(); data.resize(n * n * 4)
	var w := sim.w
	for ly in n:
		var y := clampi(y0 + ly - 1, 0, sim.h - 1)
		for lx in n:
			var x := clampi(x0 + lx - 1, 0, w - 1)
			var hx := int(sim.height[y * w + mini(x + 1, w - 1)]) - int(sim.height[y * w + maxi(x - 1, 0)])
			var hy := int(sim.height[mini(y + 1, sim.h - 1) * w + x]) - int(sim.height[maxi(y - 1, 0) * w + x])
			# the slope towards the light, plus a little for height (higher ground lighter, low ground darker)
			var v := clampf((hx + hy) / 30.0 + (int(sim.height[y * w + x]) - 100) / 260.0, -1.0, 1.0)
			var o := (ly * n + lx) * 4
			var c := 255 if v > 0.0 else 0
			data[o] = c; data[o + 1] = c; data[o + 2] = int(c * 0.92); data[o + 3] = int(absf(v) * (125.0 if v > 0.0 else 165.0))
	var small := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)
	small.resize(n * TS, n * TS, Image.INTERPOLATE_BILINEAR)
	return small.get_region(Rect2i(TS, TS, CH * TS, CH * TS))
