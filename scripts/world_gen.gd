class_name WorldGen
extends RefCounted
## Random map generation. Terrain: 0 water, 1 beach, 2 grass, 3 mountain.
## Decorations: 1 tree, 2 rock, 3 clay patch. Ore (on mountains): see GameData.ORE_NAMES.

const WATER := 0
const BEACH := 1
const GRASS := 2
const MOUNT := 3


static func _noise(s: int, freq: float, oct := 4) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = oct
	return n


## Smallest map that comfortably fits n realms.
static func min_size(n: int) -> int:
	return 56 + n * 9


## Since build 33 buildings need room (sizes and plots), so each realm gets more land: 8 realms get 192.
static func auto_size(n: int) -> int:
	return mini(208, 72 + n * 15)


## Landscape settings for generate (the map editor's Generate, and the new-game screen). Each is
## 0..1 with 0.5 the usual; leaving them out gives the same maps as always for a seed.
##   water     how much sea (higher: more and bigger lakes and seas)
##   mountains how much mountain
##   forests   how much woodland
##   ore       how much of the mountain holds ore
##   scale     how big the lakes, hills and woods are (higher: fewer, larger features)
##   shape     "island" (sea all round, the usual), "continent" (land to the edges), "lakes"
##             (mostly land with lakes), "archipelago" (many small islands)
const GEN_DEFAULTS := {"water": 0.5, "mountains": 0.5, "forests": 0.5, "ore": 0.5, "scale": 0.5, "shape": "island"}
const SHAPES := ["island", "continent", "lakes", "archipelago"]


static func generate(seed_str: String, n_enemies: int, size_override := 0, params := {}) -> Dictionary:
	var n := n_enemies + 1
	var size: int = auto_size(n) if size_override <= 0 else maxi(size_override, 48)
	var tries := 40 if size >= auto_size(n) else 12
	var gp := GEN_DEFAULTS.duplicate()
	gp.merge(params, true)
	for att in tries:
		var s: int = (seed_str.hash() + att * 101) & 0x7fffffff
		var g := _try(s, size, n, att, gp)
		if not g.is_empty():
			g["seed"] = seed_str
			return g
	return {}


static func _try(s: int, size: int, n: int, att: int, gp: Dictionary = GEN_DEFAULTS) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var w := size
	var h := size
	var N := w * h
	var ter := PackedByteArray(); ter.resize(N)
	var deco := PackedByteArray(); deco.resize(N)
	var amt := PackedByteArray(); amt.resize(N)
	var ore := PackedByteArray(); ore.resize(N)
	var shade := PackedByteArray(); shade.resize(N)
	var shape := String(gp.get("shape", "island"))
	# how big the landforms are: 30 tiles across at the usual scale, 15 to 60 from 0 to 1
	var feat := 30.0 * pow(2.0, (float(gp.scale) - 0.5) * 2.0)
	if shape == "archipelago":
		feat *= 0.55
	var hn := _noise(s, 1.0 / feat)
	var fn := _noise(s + 500, 1.0 / 16.0)
	var orn: Array = []
	for k in 5:
		orn.append(_noise(s + 1000 + k * 31, 1.0 / 9.0, 3))
	var water_t := -0.24 - att * 0.008 + (float(gp.water) - 0.5) * 0.7
	var mount_t := 0.30 + att * 0.004 - (float(gp.mountains) - 0.5) * 0.5
	if shape == "lakes":
		water_t -= 0.22
	elif shape == "archipelago":
		water_t += 0.12
	var forest_t := 0.12 - (float(gp.forests) - 0.5) * 0.7
	var ore_t := 0.18 - (float(gp.ore) - 0.5) * 0.36
	for y in h:
		for x in w:
			var i := y * w + x
			var e: float = maxf(absf(2.0 * x / w - 1.0), absf(2.0 * y / h - 1.0))
			# the sea round the edge: wide for an island, a thin coast for the others
			var edge := 0.8 if shape == "island" or shape == "archipelago" else 0.94
			var fall := (e - edge) / (1.0 - edge) if e > edge else 0.0
			var hv := hn.get_noise_2d(x, y) - fall * fall * 0.9
			ter[i] = WATER if hv < water_t else (MOUNT if hv > mount_t else GRASS)
			shade[i] = rng.randi() % 4
	# beaches next to water
	for y in h:
		for x in w:
			var i := y * w + x
			if ter[i] != GRASS:
				continue
			var near := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var xx := x + dx
					var yy := y + dy
					if xx >= 0 and yy >= 0 and xx < w and yy < h and ter[yy * w + xx] == WATER:
						near = true
			if near:
				ter[i] = BEACH
	for y in h:
		for x in w:
			var i := y * w + x
			var t := ter[i]
			if t == GRASS:
				if fn.get_noise_2d(x, y) > forest_t and rng.randf() < 0.72:
					deco[i] = 1
				elif rng.randf() < 0.012:
					deco[i] = 2; amt[i] = 8
				elif rng.randf() < 0.004:
					deco[i] = 3; amt[i] = 10
			elif t == BEACH and rng.randf() < 0.006:
				deco[i] = 2; amt[i] = 8
			elif t == MOUNT:
				var bi := 0
				var bv := -9.0
				for k in 5:
					var v: float = (orn[k] as FastNoiseLite).get_noise_2d(x, y) - (0.08 if k == 2 else 0.0)
					if v > bv:
						bv = v; bi = k + 1
				if bv > ore_t:
					ore[i] = bi
					amt[i] = 10 + rng.randi() % 20
			elif t == WATER:
				var shore := false
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var xx := x + dx
						var yy := y + dy
						if xx >= 0 and yy >= 0 and xx < w and yy < h and (ter[yy * w + xx] == GRASS or ter[yy * w + xx] == BEACH):
							shore = true
				if shore:
					amt[i] = 5 + rng.randi() % 4
	# start positions: spread out by farthest-point picking over buildable candidates
	var cands: Array = []
	for y in range(14, h - 14, 3):
		for x in range(14, w - 14, 3):
			if ter[y * w + x] != GRASS:
				continue
			var ok := 0
			for dy in range(-7, 8):
				for dx in range(-7, 8):
					var t2 := ter[(y + dy) * w + x + dx]
					if (t2 == GRASS or t2 == BEACH) and dx * dx + dy * dy <= 49:
						ok += 1
			if ok >= 120:
				cands.append(Vector2i(x, y))
	if cands.size() < n:
		return {}
	var picks: Array = [cands[rng.randi() % cands.size()]]
	while picks.size() < n:
		var bd := -1.0
		var bc := Vector2i.ZERO
		for c in cands:
			var md := 1e9
			for p in picks:
				md = minf(md, Vector2(c - p).length())
			if md > bd:
				bd = md; bc = c
		if bd < 24.0:
			return {}
		picks.append(bc)
	for i in range(picks.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = picks[i]; picks[i] = picks[j]; picks[j] = tmp
	var g := {"w": w, "h": h, "ter": ter, "deco": deco, "amt": amt, "ore": ore, "shade": shade, "starts": picks}
	for p in picks:
		_stamp(g, p.x, p.y, rng)
	_make_veins(g, rng)
	return g


## Ore amounts the map editor paints, per tile (kept in amt, times ORE_UNIT units in the vein).
const ORE_AMOUNTS := [3, 6, 12, 25]       # poor, normal, rich, very rich
const ORE_UNIT := 4

## Groups touching ore tiles of the same kind into veins. Each vein gets one shared, random amount:
## most veins are modest, a few are very rich. Mines draw from the whole vein until it runs dry.
static func _make_veins(g: Dictionary, rng: RandomNumberGenerator) -> void:
	var w: int = g.w
	var h: int = g.h
	var ore: PackedByteArray = g.ore
	var amt: PackedByteArray = g.amt
	var vein := PackedInt32Array()
	vein.resize(w * h)
	var vein_amt: Array = [0]
	var vein_tiles: Array = [PackedInt32Array()]
	for start in w * h:
		if ore[start] == 0 or vein[start] != 0:
			continue
		var id := vein_amt.size()
		var kind := ore[start]
		var tiles := PackedInt32Array()
		var stack := [start]
		vein[start] = id
		while stack.size() > 0:
			var i: int = stack.pop_back()
			tiles.append(i)
			var x := i % w
			var y := i / w
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j := ny * w + nx
				if ore[j] == kind and vein[j] == 0:
					vein[j] = id
					stack.append(j)
		var richness := pow(rng.randf(), 1.6) * 3.0 + 0.3
		var total := maxi(20, int(tiles.size() * rng.randf_range(10.0, 35.0) * richness))
		# ore painted in the map editor with an amount: the vein holds what its tiles were given
		var given := 0
		for t in tiles:
			given += int(amt[t])
		if given > 0:
			total = 0
			for t in tiles:
				total += (int(amt[t]) if amt[t] > 0 else ORE_AMOUNTS[1]) * ORE_UNIT
		else:
			for t in tiles:
				amt[t] = 0
		vein_amt.append(total)
		vein_tiles.append(tiles)
	g["vein"] = vein
	g["vein_amt"] = vein_amt
	g["vein_tiles"] = vein_tiles


static func _stamp(g: Dictionary, sx: int, sy: int, rng: RandomNumberGenerator) -> void:
	var w: int = g.w
	var h: int = g.h
	var ter: PackedByteArray = g.ter
	var deco: PackedByteArray = g.deco
	var amt: PackedByteArray = g.amt
	var ore: PackedByteArray = g.ore
	for y in range(sy - 3, sy + 4):
		for x in range(sx - 3, sx + 4):
			var i := y * w + x
			if ter[i] == WATER or ter[i] == MOUNT:
				ter[i] = GRASS
			deco[i] = 0
	var trees := 0
	for y in range(maxi(0, sy - 12), mini(h, sy + 13)):
		for x in range(maxi(0, sx - 12), mini(w, sx + 13)):
			if deco[y * w + x] == 1:
				trees += 1
	for k in 400:
		if trees >= 30:
			break
		var p := _ring(sx, sy, 5, 12, rng)
		if not _inner(p, w, h):
			continue
		var i := p.y * w + p.x
		if ter[i] == GRASS and deco[i] == 0:
			deco[i] = 1; trees += 1
	var placed := 0
	for k in 200:
		if placed >= 6:
			break
		var p := _ring(sx, sy, 6, 12, rng)
		if not _inner(p, w, h):
			continue
		var i := p.y * w + p.x
		if (ter[i] == GRASS or ter[i] == BEACH) and deco[i] == 0:
			deco[i] = 2; amt[i] = 8; placed += 1
	# two clay patches
	placed = 0
	for k in 200:
		if placed >= 2:
			break
		var p := _ring(sx, sy, 6, 11, rng)
		if p.x < 2 or p.y < 2 or p.x >= w - 2 or p.y >= h - 2:
			continue
		var ok := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if ter[(p.y + dy) * w + p.x + dx] != GRASS:
					ok = false
		if not ok:
			continue
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var i := (p.y + dy) * w + p.x + dx
				if rng.randf() < 0.8:
					deco[i] = 3; amt[i] = 12
		placed += 1
	# a pond if there is no water nearby (fish, salt, clay all like shores)
	var has_water := false
	for y in range(maxi(0, sy - 14), mini(h, sy + 15)):
		for x in range(maxi(0, sx - 14), mini(w, sx + 15)):
			if ter[y * w + x] == WATER:
				has_water = true
	if not has_water:
		for k in 40:
			var p := _ring(sx, sy, 9, 11, rng)
			if p.x < 6 or p.y < 6 or p.x >= w - 6 or p.y >= h - 6:
				continue
			for dy in range(-4, 5):
				for dx in range(-4, 5):
					var d2 := dx * dx + dy * dy
					var i := (p.y + dy) * w + p.x + dx
					if d2 <= 7:
						ter[i] = WATER; deco[i] = 0; ore[i] = 0; amt[i] = 7
					elif d2 <= 16 and ter[i] != WATER:
						ter[i] = BEACH; ore[i] = 0
						if deco[i] == 1: deco[i] = 0
			break
	# home mountain with every kind of deposit
	for k in 40:
		var p := _ring(sx, sy, 12, 15, rng)
		if p.x < 6 or p.y < 6 or p.x >= w - 6 or p.y >= h - 6:
			continue
		var ok := true
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if ter[(p.y + dy) * w + p.x + dx] == WATER:
					ok = false
		if not ok:
			continue
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if dx * dx + dy * dy > 11:
					continue
				var i := (p.y + dy) * w + p.x + dx
				ter[i] = MOUNT; deco[i] = 0
				ore[i] = 1 + ((dx + 3) + (dy + 3) * 3) % 5
				amt[i] = 14 + rng.randi() % 14
		break


static func _ring(sx: int, sy: int, r0: float, r1: float, rng: RandomNumberGenerator) -> Vector2i:
	var a := rng.randf() * TAU
	var r := rng.randf_range(r0, r1)
	return Vector2i(roundi(sx + cos(a) * r), roundi(sy + sin(a) * r))


static func _inner(p: Vector2i, w: int, h: int) -> bool:
	return p.x >= 1 and p.y >= 1 and p.x < w - 1 and p.y < h - 1


## The height of every tile, 0 (sea) to 255 (high peaks), worked out from the kinds of ground and
## the map seed, so it is the same every time a map is made or loaded (it is not saved). Land rises
## away from the sea, rolls in hills, and climbs steeply towards and into the mountains.
static func heights(seed_str: String, ter: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var n := w * h
	var hills := _noise(seed_str.hash() + 77, 1.0 / 14.0, 3)
	var crag := _noise(seed_str.hash() + 91, 1.0 / 6.0, 2)
	# distances (in steps) from the sea, from the mountains and, inside them, to their foot
	var d_sea := _dist(ter, w, h, func(t): return t == WATER, 12)
	var d_mtn := _dist(ter, w, h, func(t): return t == MOUNT, 6)
	var d_foot := _dist(ter, w, h, func(t): return t != MOUNT, 6)
	var f := PackedFloat32Array(); f.resize(n)
	for y in h:
		for x in w:
			var i := y * w + x
			var t := ter[i]
			var v := 0.0
			if t == WATER:
				v = 6.0
			elif t == BEACH:
				v = 22.0
			elif t == GRASS:
				var inland := minf(float(d_sea[i]), 10.0)
				var roll := (hills.get_noise_2d(x, y) * 0.5 + 0.5) * 62.0 * clampf(inland / 3.0, 0.0, 1.0)
				v = 32.0 + inland * 5.0 + roll + maxf(0.0, 6.0 - float(d_mtn[i])) * 13.0
			else:
				v = 160.0 + float(mini(d_foot[i], 5)) * 13.0 + crag.get_noise_2d(x, y) * 26.0
			f[i] = v
	# soften it once, keeping the sea flat
	var out := PackedByteArray(); out.resize(n)
	for y in h:
		for x in w:
			var i := y * w + x
			if ter[i] == WATER:
				out[i] = 6
				continue
			var s := 0.0
			var c := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var xx := x + dx
					var yy := y + dy
					if xx >= 0 and yy >= 0 and xx < w and yy < h:
						var wt := 2.0 if dx == 0 and dy == 0 else 1.0
						s += f[yy * w + xx] * wt
						c += wt
			out[i] = clampi(roundi(s / c), 0, 255)
	return out


## Steps from every tile to the nearest tile whose kind passes test (capped at cap), 8 directions.
static func _dist(ter: PackedByteArray, w: int, h: int, test: Callable, cap: int) -> PackedByteArray:
	var d := PackedByteArray(); d.resize(w * h); d.fill(cap)
	var q := PackedInt32Array()
	for i in w * h:
		if test.call(ter[i]):
			d[i] = 0
			q.append(i)
	var head := 0
	while head < q.size():
		var c := q[head]; head += 1
		var nd := d[c] + 1
		if nd >= cap:
			continue
		var cx := c % w
		var cy := c / w
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var xx := cx + dx
				var yy := cy + dy
				if xx >= 0 and yy >= 0 and xx < w and yy < h and d[yy * w + xx] > nd:
					d[yy * w + xx] = nd
					q.append(yy * w + xx)
	return d


# --- Hand-made maps (the map editor, missions) -------------------------------------------------------
# A map is a dictionary: w, h, seed (for the ground's heights), ter, deco, amt, ore, shade (one byte
# per tile) and starts (the headquarters' places, the player's first). Files hold it as JSON with the
# tile arrays packed (compressed, then base64), so they can sit in data/ and in the mods folder.

const MAP_KEYS := ["ter", "deco", "amt", "ore", "shade"]


## A game world from a hand-made map: the start places are cleared as in a generated world and the
## ore is grouped into veins. Only the first n starts are used. {} when the map has too few starts.
static func from_map(m: Dictionary, n: int) -> Dictionary:
	var starts: Array = m.get("starts", [])
	if starts.size() < n or n < 1:
		return {}
	var g := {"w": int(m.w), "h": int(m.h), "starts": []}
	for k in MAP_KEYS:
		g[k] = (m[k] as PackedByteArray).duplicate()
	for k in n:
		g.starts.append(Vector2i(starts[k]))
	var rng := RandomNumberGenerator.new()
	rng.seed = String(m.get("seed", "map")).hash()
	for p in g.starts:
		_stamp(g, p.x, p.y, rng)
	_make_veins(g, rng)
	# (the amounts painted on ore tiles are in the veins now)
	var gore: PackedByteArray = g.ore
	var gamt: PackedByteArray = g.amt
	for i in gore.size():
		if gore[i] != 0:
			gamt[i] = 0
	g["seed"] = String(m.get("seed", "map"))
	g["animals"] = m.get("animals", [])
	g["places"] = m.get("places", [])
	g["setup"] = m.get("setup", [])
	if (m.get("biome", PackedByteArray()) as PackedByteArray).size() == int(m.w) * int(m.h):
		g["biome"] = m.biome
	return g


static func map_to_json(m: Dictionary) -> String:
	var out := {"format": 1, "name": String(m.get("name", "")), "w": m.w, "h": m.h, "seed": String(m.get("seed", "map")),
		"starts": (m.starts as Array).map(func(s): return [s.x, s.y]), "animals": m.get("animals", []),
		"places": m.get("places", []), "setup": m.get("setup", [])}
	# the painted climate, when there is any
	var bio: PackedByteArray = m.get("biome", PackedByteArray())
	if bio.size() == int(m.w) * int(m.h) and bio.count(0) < bio.size():
		out["biome"] = Marshalls.raw_to_base64(bio.compress(FileAccess.COMPRESSION_ZSTD))
	for k in MAP_KEYS:
		var raw: PackedByteArray = m[k]
		out[k] = Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return JSON.stringify(out)


## Reads a map file (res://, user:// or a full path); {} if it cannot be read.
static func load_map(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or not d.has("ter"):
		return {}
	var w := int(d.w)
	var h := int(d.h)
	var m := {"name": String(d.get("name", path.get_file().get_basename())), "w": w, "h": h, "seed": String(d.get("seed", "map")), "starts": []}
	for s in d.get("starts", []):
		m.starts.append(Vector2i(int(s[0]), int(s[1])))
	m["animals"] = []
	for a in d.get("animals", []):
		m.animals.append([String(a[0]), int(a[1]), int(a[2])])
	m["places"] = []
	for pl in d.get("places", []):
		m.places.append([String(pl[0]), int(pl[1]), int(pl[2])])
	m["setup"] = d.get("setup", [])
	if d.has("biome"):
		var bio := Marshalls.base64_to_raw(String(d.biome)).decompress(w * h, FileAccess.COMPRESSION_ZSTD)
		if bio.size() == w * h:
			m["biome"] = bio
	for k in MAP_KEYS:
		var raw := Marshalls.base64_to_raw(String(d[k])).decompress(w * h, FileAccess.COMPRESSION_ZSTD)
		if raw.size() != w * h:
			return {}
		m[k] = raw
	return m


static func save_map(m: Dictionary, path: String) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Could not write %s" % path
	f.store_string(map_to_json(m))
	f.close()
	return ""
