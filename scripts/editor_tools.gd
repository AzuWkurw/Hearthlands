class_name EditorTools
extends RefCounted
## The map editor's work on the map itself, apart from its panel (ui_editor.gd): where a mirrored
## brush paints, the fill bucket, smoothing, carving rivers, cutting out and stamping areas (copy and
## paste, turned or mirrored), and the fairness count of what lies around each start.
## These only work out which tiles change; the editor makes the changes, so it can undo them.

const MIRRORS := ["off", "left-right", "top-bottom", "four ways", "turned"]
const MIRROR_NAMES := ["Off", "Left | right", "Top | bottom", "Four ways", "Turned (180°)"]
const LAYERS := ["ter", "deco", "amt", "ore", "biome"]


## The tiles a brush at (x, y) also paints with mirror mode m on a w x h map (the tile itself first).
static func mirrored(x: int, y: int, w: int, h: int, m: String) -> Array:
	var out := [Vector2i(x, y)]
	var mx := w - 1 - x
	var my := h - 1 - y
	match m:
		"left-right": out.append(Vector2i(mx, y))
		"top-bottom": out.append(Vector2i(x, my))
		"four ways": out.append_array([Vector2i(mx, y), Vector2i(x, my), Vector2i(mx, my)])
		"turned": out.append(Vector2i(mx, my))
	var uniq := []
	for p in out:
		if not uniq.has(p):
			uniq.append(p)
	return uniq


## Tiles of a brush of width size at (x, y): a square, or a round brush (the corners left out).
static func brush_tiles(x: int, y: int, size: int, round_brush: bool) -> Array:
	var out := []
	var r := size / 2
	var rr := (size / 2.0) * (size / 2.0) + 0.6
	for dy in range(-r, size - r):
		for dx in range(-r, size - r):
			if round_brush and size > 2:
				var cx := dx + (0.5 if size % 2 == 0 else 0.0)
				var cy := dy + (0.5 if size % 2 == 0 else 0.0)
				if cx * cx + cy * cy > rr:
					continue
			out.append(Vector2i(x + dx, y + dy))
	return out


## The tiles joined to (x, y) that the fill bucket changes: with the same ground (mode "ter"), the same
## ground and the same things on it ("deco"), or the whole piece of land or water ("land"). At most
## `most` tiles.
static func flood(sim: Sim, x: int, y: int, mode := "ter", most := 60000) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not sim.inb(x, y):
		return out
	var w := sim.w
	var start := y * w + x
	var t0 := sim.ter[start]
	var d0 := sim.deco[start]
	var seen := {start: true}
	var stack := [start]
	while not stack.is_empty() and out.size() < most:
		var i: int = stack.pop_back()
		out.append(i)
		var cx := i % w
		var cy := i / w
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = cx + o.x
			var ny: int = cy + o.y
			if nx < 0 or ny < 0 or nx >= w or ny >= sim.h:
				continue
			var j := ny * w + nx
			if seen.has(j):
				continue
			if mode == "land":
				if (sim.ter[j] == Sim.WATER) != (t0 == Sim.WATER):
					continue
			elif sim.ter[j] != t0 or (mode == "deco" and sim.deco[j] != d0):
				continue
			seen[j] = true
			stack.append(j)
	return out


## Smoothing: each tile under the brush takes the ground most of its neighbours have, so jagged coasts
## and specks of land round off. Returns [tile, new ground] for the tiles that change.
static func smooth(sim: Sim, tiles: Array) -> Array:
	var out := []
	for p: Vector2i in tiles:
		if not sim.inb(p.x, p.y):
			continue
		var count := [0, 0, 0, 0]
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := p.x + dx
				var ny := p.y + dy
				if sim.inb(nx, ny):
					count[sim.ter[ny * sim.w + nx]] += 1
		var best := 0
		for k in 4:
			if count[k] > count[best]:
				best = k
		var i := p.y * sim.w + p.x
		if count[best] >= 5 and best != sim.ter[i]:
			out.append([i, best])
	return out


## The tiles of a river from a to b: a winding band of water 2 to 3 tiles wide, with a ford (a strip of
## beach across it) every ford_every tiles so people can cross. Returns [water tiles, ford tiles].
static func river(sim: Sim, a: Vector2i, b: Vector2i, ford_every := 14) -> Array:
	var water := {}
	var ford := {}
	var d := Vector2(b - a)
	var len := maxf(1.0, d.length())
	var dir := d / len
	var side := Vector2(-dir.y, dir.x)
	var steps := int(len * 3.0)
	var seed := float((a.x * 73 + a.y * 151 + b.x * 37) % 97)
	var last_ford := 0.0
	for k in steps + 1:
		var u := float(k) / steps
		var along := u * len
		# meanders: two waves of different lengths, none at the ends
		var bend := (sin(along * 0.21 + seed) * 2.2 + sin(along * 0.083 + seed * 0.5) * 3.5) * sin(u * PI)
		var c := Vector2(a) + d * u + side * bend
		var wdt := 1.0 + 0.5 * (0.5 + 0.5 * sin(along * 0.3 + seed))
		var is_ford := along - last_ford >= ford_every and along > 5.0 and along < len - 5.0
		if is_ford:
			last_ford = along
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var q := Vector2(c.x + dx, c.y + dy)
				var off := (q - c).dot(side)
				var fwd := (q - c).dot(dir)
				if absf(off) <= wdt and absf(fwd) <= 0.6:
					var t := Vector2i(roundi(q.x), roundi(q.y))
					if sim.inb(t.x, t.y):
						var i := t.y * sim.w + t.x
						if is_ford:
							ford[i] = true
						else:
							water[i] = true
	for i in ford:
		water.erase(i)
	return [water.keys(), ford.keys()]


## What lies within r tiles of each start: [{trees, stone, clay, ore (8 kinds), fish, land, mountain}].
static func fairness(sim: Sim, starts: Array, r := 15) -> Array:
	var out := []
	for s: Vector2i in starts:
		var e := {"trees": 0, "stone": 0, "clay": 0, "coal": 0, "iron": 0, "gold": 0, "granite": 0, "copper": 0, "sulfur": 0, "lead": 0, "tin": 0, "fish": 0, "land": 0, "mountain": 0}
		for y in range(maxi(0, s.y - r), mini(sim.h - 1, s.y + r) + 1):
			for x in range(maxi(0, s.x - r), mini(sim.w - 1, s.x + r) + 1):
				if (x - s.x) * (x - s.x) + (y - s.y) * (y - s.y) > r * r:
					continue
				var i := y * sim.w + x
				var t := sim.ter[i]
				match int(sim.deco[i]):
					1: e.trees += 1
					2: e.stone += 1
					3: e.clay += 1
				if t == Sim.WATER and sim.amt[i] > 0:
					e.fish += 1
				elif t == Sim.MOUNT:
					e.mountain += 1
					if sim.ore[i] > 0:
						var k: String = String(GameData.ORE_NAMES.get(int(sim.ore[i]), ""))
						if e.has(k): e[k] += 1
				elif (t == Sim.GRASS or t == Sim.BEACH) and sim.deco[i] == 0:
					e.land += 1
		out.append(e)
	return out


## A piece of the map cut out for copy and paste: {w, h, and each layer as a PackedByteArray}.
static func cut(sim: Sim, biome: PackedByteArray, r: Rect2i) -> Dictionary:
	# packed arrays are copied when written through a Dictionary, so each layer is filled first
	var n := r.size.x * r.size.y
	var lay := []
	for k in LAYERS.size():
		var arr := PackedByteArray()
		arr.resize(n)
		lay.append(arr)
	var ter: PackedByteArray = lay[0]
	var deco: PackedByteArray = lay[1]
	var amt: PackedByteArray = lay[2]
	var ore: PackedByteArray = lay[3]
	var bio: PackedByteArray = lay[4]
	for y in r.size.y:
		for x in r.size.x:
			var sx := r.position.x + x
			var sy := r.position.y + y
			if not sim.inb(sx, sy):
				continue
			var i := sy * sim.w + sx
			var j := y * r.size.x + x
			ter[j] = sim.ter[i]
			deco[j] = sim.deco[i]
			amt[j] = sim.amt[i]
			ore[j] = sim.ore[i]
			bio[j] = biome[i] if i < biome.size() else 0
	return {"w": r.size.x, "h": r.size.y, "ter": ter, "deco": deco, "amt": amt, "ore": ore, "biome": bio}


## The piece turned a quarter to the right.
static func turn(c: Dictionary) -> Dictionary:
	var w: int = c.w
	var h: int = c.h
	var n := {"w": h, "h": w}
	for k in LAYERS:
		var src: PackedByteArray = c[k]
		var dst := PackedByteArray()
		dst.resize(w * h)
		for y in h:
			for x in w:
				# (x, y) goes to (h - 1 - y, x) in the new piece, h wide
				dst[x * h + (h - 1 - y)] = src[y * w + x]
		n[k] = dst
	return n


## The piece mirrored left to right (or top to bottom when vertical).
static func flip(c: Dictionary, vertical: bool) -> Dictionary:
	var w: int = c.w
	var h: int = c.h
	var n := {"w": w, "h": h}
	for k in LAYERS:
		var src: PackedByteArray = c[k]
		var dst := PackedByteArray()
		dst.resize(w * h)
		for y in h:
			for x in w:
				var sx := x if vertical else w - 1 - x
				var sy := h - 1 - y if vertical else y
				dst[y * w + x] = src[sy * w + sx]
		n[k] = dst
	return n
