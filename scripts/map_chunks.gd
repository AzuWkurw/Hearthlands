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
var max_chunks := 120      # chunks kept in memory; the least recently seen are forgotten first
const WATER_ALPHA := 128   # alpha of open water in a baked chunk (255 = land)
const EDGE_WIDTH := [0.0, 11.0, 8.0, 7.0]   # pixels each kind of ground spills over a lower neighbour
## Neighbour offsets, in mask bit order: N, E, S, W, then the corners NE, SE, SW, NW.
const NB := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]

var sim: Sim
var twin: MapChunks        # the same map at half resolution, used when zoomed out (see MapView)
var hi: MapChunks          # the same map at double resolution (64 pixels a tile), used up close
var far: MapChunks         # the same map at a quarter resolution (8 pixels a tile), used far out
var bake_trees := false    # far out the trees are too small to draw one by one: baked in as dark crowns
var smooth := false        # build mipmaps so chunks look smooth when zoomed out; call clear() after changing it
var _tex: Dictionary = {}  # chunk key -> ImageTexture
var _dirty: Dictionary = {}
var _used: Dictionary = {} # chunk key -> frame it was last drawn
var _frame := 0
var _territory := -1       # territory version the chunks were baked with
var _owners := PackedByteArray()   # the owner of every tile when the chunks were last brought up to date
var _ter: Array = []
var _road: Array = []
var _bridge: Array = []     # [wooden E-W, wooden N-S, stone E-W, stone N-S]
var _paved: Array = []
var _clay: Image
var _ore: Dictionary = {}
var _tint: Array = []
var ver := 0               # goes up whenever every chunk is to be baked again (the map view's scenery follows)
## Baking on the other processor cores: while the map is drawn, chunks are baked by worker threads
## (WorkerThreadPool), and finish_jobs() waits for them right after the frame is rendered (the map
## view calls it from RenderingServer.frame_post_draw). The game itself only changes before drawing
## (input, then the simulation in Main._process), so the workers read a world that holds still.
var use_threads := OS.get_processor_count() > 1 and DisplayServer.get_name() != "headless"
var _jobs: Dictionary = {}        # chunk key -> worker task id
var _done: Dictionary = {}        # chunk key -> image baked by a worker, not yet a texture
var _lock := Mutex.new()          # guards _done and the picture caches the workers fill
var _edge: Dictionary = {}  # ground kind * 256 + neighbour mask -> soft edge overlay, made when first needed


## Reads every texture the chunks use, as plain images at chunk resolution. Call after textures change.
## A bridge deck for one tile: boards across the way (or dressed stone), with a rail on each side and
## a shadow on the water below them. ns: the road runs north-south.
func _bridge_img(ns: bool, stone: bool) -> Image:
	var img := Image.create(TS, TS, false, Image.FORMAT_RGBA8)
	var a := int(TS * 0.2)
	var b := int(TS * 0.8)
	var deck := Color("8a6038") if not stone else Color("9c968a")
	var seam := Color("5e3f22") if not stone else Color("6e6a60")
	var rail := Color("6b4526") if not stone else Color("7c776c")
	for u in TS:
		for v in range(maxi(0, a - 2), mini(TS, b + 3)):
			var c: Color
			if v < a or v > b:
				c = Color(0, 0, 0, 0.28)          # shadow on the water
			elif v <= a + 1 or v >= b - 1:
				c = rail
			else:
				var board := (u % 5 == 0) if not stone else ((u + (v / 6) * 4) % 8 == 0 or v % 6 == 0)
				c = seam if board else deck.lightened(0.04 * float((u / 5 + v) % 3) if not stone else 0.03 * float((u * 7 + v * 3) % 4))
			if ns:
				img.set_pixel(v, u, c)
			else:
				img.set_pixel(u, v, c)
	return img


func load_images() -> void:
	for c: MapChunks in _subs():
		c.load_images()
	_bridge = [_bridge_img(false, false), _bridge_img(true, false), _bridge_img(false, true), _bridge_img(true, true)]
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


## The other resolutions of the same map, brought up to date with this one's settings.
func _subs() -> Array:
	var out := []
	for c in [twin, hi, far]:
		if c != null:
			c.sim = sim
			c.smooth = smooth
			c.details = details
			out.append(c)
	return out


## The realms' colours changed (a new game): the territory tints are made again at every resolution.
func reset_tint() -> void:
	_tint.clear()
	_territory = -1
	for c: MapChunks in _subs():
		c.reset_tint()


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
		img.resize(w, h, Image.INTERPOLATE_LANCZOS if img.get_width() > w else Image.INTERPOLATE_BILINEAR)
	return img


## Forgets every baked chunk (new game, loaded game, new textures).
func clear() -> void:
	finish_jobs()
	ver += 1
	for c: MapChunks in _subs():
		c.clear()
	_tex.clear()
	_dirty.clear()
	_used.clear()
	_territory = -1
	_owners = PackedByteArray()


func mark_all() -> void:
	ver += 1
	for c: MapChunks in _subs():
		c.mark_all()
	for k in _tex:
		_dirty[k] = true


## Something on tile i changed: re-bake the chunks that can show it. Neighbours count too, because
## road shapes depend on the tiles next door and trees reach into the tile above.
func mark_tile(i: int) -> void:
	for c: MapChunks in _subs():
		c.mark_tile(i)
	var x := i % sim.w
	var y := i / sim.w
	for yy in [y - 1, y, y + 1]:
		for xx in [x - 1, x, x + 1]:
			if xx >= 0 and yy >= 0 and xx < sim.w and yy < sim.h:
				var k: int = (yy / CH) * 1000 + xx / CH
				if _tex.has(k) or _jobs.has(k):
					_dirty[k] = true
					if _jobs.has(k):
						_dirty_after[k] = true


## Call once per frame before drawing.
func begin_frame() -> void:
	_frame += 1
	if sim.territory_version != _territory:
		_territory = sim.territory_version
		finish_jobs()     # (the workers read the tints)
		if _tint.size() != sim.players.size():
			_tint.clear()
			for p in sim.players:
				var t := Image.create(TS, TS, false, Image.FORMAT_RGBA8)
				t.fill(Color(p.color, 0.16))
				_tint.append(t)
		_mark_owner_changes()
	if _tex.size() > max_chunks:
		var keys := _tex.keys()
		keys.sort_custom(func(a, b): return int(_used.get(a, 0)) < int(_used.get(b, 0)))
		for n in keys.size() - max_chunks:
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
	if (not _tex.has(k) or _dirty.has(k)) and not _jobs.has(k):
		if int(budget[1]) == 0 or (not use_threads and Time.get_ticks_usec() < int(budget[0])):
			# the first each frame here (so something always shows), the rest on other cores
			budget[1] = int(budget[1]) + 1
			_bake(cx, cy, k)
		elif use_threads and _jobs.size() < max_jobs():
			_dirty.erase(k)       # marked again meanwhile: baked again after this one
			_jobs[k] = WorkerThreadPool.add_task(_bake_job.bind(cx, cy, k), false, "bake chunk")
	return _tex.get(k)


## How many chunks are baked on other cores at once: one for each core but the main one's.
static func max_jobs() -> int:
	return maxi(1, OS.get_processor_count() - 1)


func _bake_job(cx: int, cy: int, k: int) -> void:
	var img := _bake_image(cx, cy)
	_lock.lock()
	_done[k] = img
	_lock.unlock()


## Waits for the chunks being baked on other cores and makes them textures (after the frame is drawn).
func finish_jobs() -> void:
	for k in _jobs:
		WorkerThreadPool.wait_for_task_completion(_jobs[k])
	_jobs.clear()
	_lock.lock()
	var done := _done
	_done = {}
	_lock.unlock()
	for k in done:
		_set_tex(k, done[k])


func _bake(cx: int, cy: int, k: int) -> void:
	_set_tex(k, _bake_image(cx, cy))


func _set_tex(k: int, img: Image) -> void:
	var old: ImageTexture = _tex.get(k)
	if old != null and old.get_width() == img.get_width():
		old.update(img)
	else:
		_tex[k] = ImageTexture.create_from_image(img)
	if not _dirty_after.has(k):
		_dirty.erase(k)
	_dirty_after.erase(k)


var _dirty_after: Dictionary = {}   # chunks marked while a worker was baking them: bake again


func _bake_image(cx: int, cy: int) -> Image:
	var img := Image.create(CH * TS, CH * TS, false, Image.FORMAT_RGBA8)
	var w := sim.w
	var h := sim.h
	var full := Rect2i(0, 0, TS, TS)
	var x0 := cx * CH
	var y0 := cy * CH
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
			# (the hills' light and shade is laid on by the ground shader, see MapView._make_relief_map)
			if details:
				_details(img, pos, x, y, i, t)
			if sim.road[i] != 0 and sim.bmap[i] == 0:
				var m := 0
				if y > 0 and (sim.road[i - w] != 0 or (sim.bmap[i - w] != 0 and sim.links(i, i - w))): m |= 1
				if x < w - 1 and (sim.road[i + 1] != 0 or (sim.bmap[i + 1] != 0 and sim.links(i, i + 1))): m |= 2
				if y < h - 1 and (sim.road[i + w] != 0 or (sim.bmap[i + w] != 0 and sim.links(i, i + w))): m |= 4
				if x > 0 and (sim.road[i - 1] != 0 or (sim.bmap[i - 1] != 0 and sim.links(i, i - 1))): m |= 8
				if t == 0:
					# a road over water is a bridge: planks (or stone, once paved) across the way it runs
					var ns := (m & 5) != 0 and (m & 10) == 0
					img.blend_rect(_bridge[(1 if ns else 0) + (2 if sim.pave[i] == 1 else 0)], full, pos)
				else:
					img.blend_rect(_paved[m] if sim.pave[i] == 1 else _road[m], full, pos)
			var o := sim.owner[i]
			if o != 0 and o <= _tint.size():
				img.blend_rect(_tint[o - 1], full, pos)
			# how steep the road is here: no mark when flat, then 1 to 3 marks, yellow to red (as the
			# road markers), so you can see where carriers will be slow
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
			if d == Sim.D_TREE and bake_trees:
				img.blend_rect(_tree_crown(_hash(x, y) % 3), full, pos)
				continue
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
	return img


## Small things on the ground, baked in with it so they cost nothing to draw: reeds where land meets
## water and snow on the highest mountain tiles. Each tile picks its details from a hash of its position, so
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
		# (the foam along the shore is drawn by the ground shader, moving with the waves; straight
		# baked lines of foam stood out as white dashes where the shoreline is drawn soft)
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
	# (grass tufts, flowers and pebbles are in the ground textures themselves)


## A tree seen from far off: a dark green crown with a lit upper left and a shadow to the lower right.
var _crowns: Array = []

func _tree_crown(v: int) -> Image:
	_lock.lock()
	if _crowns.is_empty():
		for k in 3:
			var img := Image.create(TS, TS, false, Image.FORMAT_RGBA8)
			var base: Color = [Color8(46, 86, 40), Color8(36, 74, 44), Color8(58, 96, 42)][k]
			var c := Vector2(TS * (0.45 + 0.05 * k), TS * 0.45)
			var r := TS * 0.42
			for y in TS:
				for x in TS:
					var p := Vector2(x + 0.5, y + 0.5)
					var sh := p - c - Vector2(TS * 0.12, TS * 0.12)
					if (p - c).length() <= r:
						var lit := clampf(1.0 - (p - c + Vector2(r, r) * 0.4).length() / (r * 1.6), 0.0, 1.0)
						img.set_pixel(x, y, base.lightened(lit * 0.35))
					elif sh.length() <= r:
						img.set_pixel(x, y, Color(0, 0.04, 0, 0.35))
			_crowns.append(img)
	var out: Image = _crowns[v]
	_lock.unlock()
	return out


static func _hash(x: int, y: int) -> int:
	return absi((x * 73856093) ^ (y * 19349663) ^ 0x5bd1e995) % 1000003


var _snow := {}

## A whitish cover for a mountain tile, denser at the top, as a blendable image (cached by strength).
func _snow_img(cover: float) -> Image:
	var k := snappedf(cover, 0.1)
	_lock.lock()
	if _snow.has(k):
		var got: Image = _snow[k]
		_lock.unlock()
		return got
	var img := Image.create(TS, TS, false, Image.FORMAT_RGBA8)
	for py in TS:
		for px in TS:
			var n := sin(px * 0.9) * 0.08 + sin(py * 1.3 + px * 0.4) * 0.08
			var a := clampf(k - float(py) / TS * 0.6 + n, 0.0, 0.9)
			img.set_pixel(px, py, Color(0.96, 0.97, 1.0, a))
	_snow[k] = img
	_lock.unlock()
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
	_lock.lock()
	if _edge.has(key):
		var got: Image = _edge[key]
		_lock.unlock()
		return got
	var data: PackedByteArray = (_ter[u * 4] as Image).get_data()
	var sc := TS / 32.0
	var r: float = EDGE_WIDTH[u] * sc
	# the sides are joined with a smooth minimum, so where two sides meet the edge bends round
	# instead of making a square corner (coasts look less like the tile grid)
	var kr := r * 0.7
	for py in TS:
		for px in TS:
			var cx := px + 0.5
			var cy := py + 0.5
			var wx := (1.8 * sin(TAU * 2.0 * cx / TS + u) + 1.0 * sin(TAU * 5.0 * cx / TS + 1.7 * u)) * sc
			var wy := (1.8 * sin(TAU * 2.0 * cy / TS + 2.0 * u) + 1.0 * sin(TAU * 5.0 * cy / TS + u)) * sc
			var acc := 0.0
			if m & 1: acc += exp(-(cy + wx) / kr)
			if m & 2: acc += exp(-(TS - cx + wy) / kr)
			if m & 4: acc += exp(-(TS - cy - wx) / kr)
			if m & 8: acc += exp(-(cx - wy) / kr)
			if m & 16: acc += exp(-(Vector2(TS - cx, cy).length() + wx * 0.5) / kr)
			if m & 32: acc += exp(-(Vector2(TS - cx, TS - cy).length() + wy * 0.5) / kr)
			if m & 64: acc += exp(-(Vector2(cx, TS - cy).length() - wx * 0.5) / kr)
			if m & 128: acc += exp(-(Vector2(cx, cy).length() - wy * 0.5) / kr)
			var dist := -kr * log(maxf(acc, 1e-9))
			var a := clampf(1.0 - dist / r, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			var k := (py * TS + px) * 4 + 3
			data[k] = int(data[k] * a)
	var img := Image.create_from_data(TS, TS, false, Image.FORMAT_RGBA8, data)
	_edge[key] = img
	_lock.unlock()
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
