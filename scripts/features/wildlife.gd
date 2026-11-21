extends Feature
## Wildlife you can see: deer and boars in and near the woods, hares in the open, wolves in the forests
## (more in the northern taiga). They wander, keep away from buildings, and have young (not in winter)
## up to what the land can feed. Hunters must find a real animal in their hunting grounds; each catch
## takes one, so over-hunting empties a forest for a while. Wolves now and then scare the herds of sheep
## and pig farms and dairies (the farm stops for a while) and take deer and hares themselves. Fish
## jump in the fishing grounds.

const KINDS := {
	"deer": {"speed": 0.8, "per": 60, "prey": true},
	"boar": {"speed": 0.6, "per": 90, "prey": true},
	"hare": {"speed": 1.3, "per": 55, "prey": true},
	"wolf": {"speed": 1.0, "per": 450, "prey": false},
}
const FARMS := ["sheep_farm", "pig_farm", "dairy"]

## Each animal: [kind, from x, from y, to x, to y, start time, arrival time]
var animals: Array = []
var scared: Dictionary = {}       # farm building id -> game time the herd calms down
var rng := RandomNumberGenerator.new()
var _land := 0
var _t := 0
var _warned := 0.0


func _init() -> void:
	id = "wildlife"
	title = "Wildlife"
	info = "Deer, boars, hares and wolves roam the land and breed. Hunters must find real game, and wolves trouble sheep and pig farms."
	default_on = true


func on_start(loaded: bool) -> void:
	_dgrid = {}
	if not loaded or rng.seed == 0:
		rng.seed = (sim.seed_str + ":wildlife").hash()
	_land = 0
	for i in sim.w * sim.h:
		if sim.ter[i] == Sim.GRASS:
			_land += 1
	if animals.is_empty() and not loaded and not sim.map_animals.is_empty():
		# a hand-made map: the animals its maker placed
		for a in sim.map_animals:
			if KINDS.has(String(a[0])) and sim.inb(int(a[1]), int(a[2])):
				animals.append([String(a[0]), float(a[1]), float(a[2]), float(a[1]), float(a[2]), sim.time, sim.time + rng.randf_range(0.0, 6.0)])
	if animals.is_empty():
		for k: String in KINDS:
			for n in maxi(2, mini(_land / int(KINDS[k].per), _cap(k) / 2)):
				var at := _habitat_spot(k, -1, -1, 0)
				if at.x >= 0:
					animals.append([k, at.x, at.y, at.x, at.y, sim.time, sim.time + rng.randf_range(0.0, 6.0)])


## Each kind's share of the most animals a map holds (build 59: one for every 40 tiles of the map, so a
## big map's herds no longer run to thousands).
const SHARE := {"deer": 0.35, "boar": 0.22, "hare": 0.37, "wolf": 0.06}
const TILES_PER := 40.0

func _cap(k: String) -> int:
	var by_land := int(_land / int(KINDS[k].per) * 2.0)
	var by_map := int(sim.w * sim.h / TILES_PER * float(SHARE[k]))
	return maxi(3, mini(by_land, by_map))


## A tile where an animal of kind k likes to be: grass away from buildings, in or near woods for deer,
## boars and wolves. Near (cx, cy) within r tiles, or anywhere if r is 0.
func _habitat_spot(k: String, cx: int, cy: int, r: int) -> Vector2:
	for attempt in (30 if r <= 0 else 10):
		var x: int
		var y: int
		if r <= 0:
			x = rng.randi() % sim.w
			y = rng.randi() % sim.h
		else:
			x = cx + rng.randi_range(-r, r)
			y = cy + rng.randi_range(-r, r)
		if not sim.inb(x, y):
			continue
		var i := sim.idx(x, y)
		if sim.ter[i] != Sim.GRASS or sim.bmap[i] != 0:
			continue
		if _near_building(x, y, 1):
			continue
		# the trees round it, counted only when they matter: woods for deer, boars and wolves placed
		# anywhere, not too thick for hares
		if r <= 0 and k != "hare" and _trees_near(x, y, 2) < 2:
			continue
		if k == "hare" and _trees_near(x, y, 7) > 6:
			continue
		if k == "wolf" and r <= 0:
			var cl = sim.get_feature("seasons")
			if cl != null and cl.biome_at(x, y) != cl.TAIGA and rng.randf() < 0.5:
				continue
		return Vector2(x, y)
	return Vector2(-1, -1)


## Trees within 2 tiles of (x, y) (as Sim.count_near), counting no further than stop.
func _trees_near(x: int, y: int, stop: int) -> int:
	var c := 0
	var w := sim.w
	for yy in range(maxi(0, y - 2), mini(sim.h - 1, y + 2) + 1):
		for xx in range(maxi(0, x - 2), mini(w - 1, x + 2) + 1):
			var dx := xx - x
			var dy := yy - y
			if dx * dx + dy * dy <= 5 and sim.deco[yy * w + xx] == Sim.D_TREE:
				c += 1
				if c >= stop:
					return c
	return c


func _near_building(x: int, y: int, r: int) -> bool:
	for yy in range(maxi(0, y - r), mini(sim.h - 1, y + r) + 1):
		for xx in range(maxi(0, x - r), mini(sim.w - 1, x + r) + 1):
			if sim.bmap[yy * sim.w + xx] != 0:
				return true
	return false


func pos(a: Array) -> Vector2:
	var f := clampf((sim.time - float(a[5])) / maxf(0.01, float(a[6]) - float(a[5])), 0.0, 1.0)
	return Vector2(float(a[1]), float(a[2])).lerp(Vector2(float(a[3]), float(a[4])), f)


## When an animal that arrived moves on (see on_second).
static func _wake(a: Array) -> float:
	return float(a[6]) + 3.0 + fmod(float(a[5]) * 7.31 + float(a[1]) * 3.17 + float(a[2]) * 1.93, 12.0)


func on_second() -> void:
	_t += 1
	# half the animals are looked at each second, the other half the next (a big map has thousands)
	for ai in range(_t % 2, animals.size(), 2):
		var a: Array = animals[ai]
		# grazes 3 to 15 seconds where it arrived (how long follows from when and where it set out, so
		# no dice are rolled each second for each animal); the time it moves on is kept with it (build 73:
		# thousands of animals are looked at each second)
		if a.size() < 8:
			a.append(_wake(a))
		if sim.time < float(a[7]):
			continue
		var here := Vector2(float(a[3]), float(a[4]))
		# mostly short moves; now and then a longer roam, so animals spread back into hunted land
		var to := _habitat_spot(String(a[0]), roundi(here.x), roundi(here.y), 6 if rng.randf() < 0.25 else 3)
		if to.x < 0:
			# boxed in by buildings: wander off further
			to = _habitat_spot(String(a[0]), roundi(here.x), roundi(here.y), 7)
		if to.x < 0:
			continue
		_g_del(a)
		a[1] = here.x; a[2] = here.y; a[3] = to.x; a[4] = to.y
		_g_add(a)
		a[5] = sim.time
		a[6] = sim.time + here.distance_to(to) / float(KINDS[a[0]].speed)
		a[7] = _wake(a)
	if _t % 30 == 0:
		_breed()
		_wander_in()
	if _t % 10 == 0:
		_wolves()


## Every half minute some animals have young: about one in ten, fewer as the land fills up. Some are
## born out in the wild, so a hunted-out area fills again in time.
func _breed() -> void:
	var cl = sim.get_feature("seasons")
	if cl != null and cl.season() == 3:
		return
	var by := {}
	for a in animals:
		if not by.has(a[0]):
			by[a[0]] = []
		by[a[0]].append(a)
	for k: String in KINDS:
		var list: Array = by.get(k, [])
		var n := list.size()
		var cap := _cap(k)
		# more than the map holds (a game saved before build 59): some die off each half minute
		if n > cap:
			var die := maxi(1, (n - cap) / 4)
			for m in die:
				var gone: Array = list[rng.randi() % list.size()]
				list.erase(gone)
				_g_del(gone)
				animals.erase(gone)
			continue
		var births := 0
		if n == 0:
			births = 1
		else:
			var rate := 0.10 * (1.0 - float(n) / cap)
			for m in n:
				if rng.randf() < rate:
					births += 1
		for b in births:
			var at := Vector2(-1, -1)
			if n > 0 and rng.randf() < 0.7:
				var par: Array = list[rng.randi() % n]
				at = _habitat_spot(k, int(par[3]), int(par[4]), 2)
			else:
				at = _habitat_spot(k, -1, -1, 0)
			if at.x >= 0:
				animals.append([k, at.x, at.y, at.x, at.y, sim.time, sim.time])
				_g_add(animals[-1])


## Game wanders into hunting grounds from the wild: now and then an animal turns up at the edge of a
## hunter's grounds, so a hunter is slowed by over-hunting but not stopped for good.
func _wander_in() -> void:
	var count := {}
	for a in animals:
		count[a[0]] = int(count.get(a[0], 0)) + 1
	for b: Sim.Bld in sim.blds:
		if b.ty != "hunter" or b.state != "ready" or rng.randf() > 0.5:
			continue
		var k: String = ["deer", "boar", "hare", "hare"][rng.randi() % 4]
		if int(count.get(k, 0)) >= _cap(k):
			continue
		var c := sim.work_center(b)
		var at := _habitat_spot(k, c.x, c.y, sim.work_radius(b) + 2)
		if at.x >= 0:
			animals.append([k, at.x, at.y, at.x, at.y, sim.time, sim.time])
			_g_add(animals[-1])
			count[k] = int(count.get(k, 0)) + 1


func _wolves() -> void:
	# the herds' farms, found once (not once for every wolf)
	var farms := []
	var f_at := {}            # (build 73) a farm's place in that list, for the order below
	for b: Sim.Bld in sim.blds:
		if b.ty in FARMS and b.state == "ready" and not b.dead:
			f_at[b] = farms.size()
			farms.append(b)
	_hunters = {}
	# the farms by 8-tile cell, so each wolf looks only at those around it
	var fcell := {}
	for f0: Sim.Bld in farms:
		var fk := (f0.x >> 3) * 4096 + (f0.y >> 3)
		if not fcell.has(fk):
			fcell[fk] = []
		(fcell[fk] as Array).append(f0)
	_prey_grid = {}
	_prey_removed = []
	for wv in animals.filter(func(a): return a[0] == "wolf"):
		var wp := pos(wv)
		var near_f := []
		var cx := int(wp.x) >> 3
		var cy := int(wp.y) >> 3
		for gy in range(cy - 1, cy + 2):
			for gx in range(cx - 1, cx + 2):
				near_f.append_array(fcell.get(gx * 4096 + gy, []))
		# (in the order the farms were found, as before)
		near_f.sort_custom(func(x, y): return int(f_at[x]) < int(f_at[y])) if near_f.size() > 1 else null
		# a farm's herd nearby
		for f: Sim.Bld in _farms_near(wp, 3, near_f):
			if not scared.has(f.id) and rng.randf() < 0.1 and not _hunter_near(f):
				scared[f.id] = sim.time + 45.0
				if f.p == sim.human().id and sim.time - _warned > 60.0:
					_warned = sim.time
					sim.emit_log("Wolves scared the herd of your %s. A hunter nearby keeps them down." % String(f.def.name).to_lower(), Color("f0b070"))
		# or a deer or hare
		if rng.randf() < 0.02:
			var prey = _nearest_prey(wp, 2.0)
			if prey != null:
				_g_del(prey)
				# its place now: where it was when the grid was made, less those caught before it this round
				var at0 := int(_prey_at)
				for r0 in _prey_removed:
					if int(r0) < int(_prey_at):
						at0 -= 1
				if at0 >= 0 and at0 < animals.size() and is_same(animals[at0], prey):
					animals.remove_at(at0)
				else:
					animals.erase(prey)
				_prey_removed.append(_prey_at)
				_prey_gone(prey)
	for k in scared.keys():
		if sim.time >= float(scared[k]):
			scared.erase(k)


## A hunter whose grounds reach the farm keeps the wolves away from it.
var _hunters := {}         # realm id -> its staffed hunters, found once a wolves' round (build 73)

func _hunter_near(f: Sim.Bld) -> bool:
	if not _hunters.has(f.p):
		var hs := []
		for b: Sim.Bld in sim.realm_blds(sim.players[f.p - 1]):
			if b.ty == "hunter":
				hs.append(b)
		_hunters[f.p] = hs
	for b: Sim.Bld in _hunters[f.p]:
		if b.staffed and Vector2(b.x - f.x, b.y - f.y).length() <= float(sim.work_radius(b)) + 1.0:
			return true
	return false


func _farms_near(at: Vector2, r: float, farms: Array) -> Array:
	var out := []
	for b: Sim.Bld in farms:
		if Vector2(b.x, b.y).distance_to(at) <= r:
			out.append(b)
	return out


## Deer and hares by 4-tile cell (with their place in the list), made when first needed in a wolves'
## round and again after one is caught.
var _prey_grid := {}

func _nearest_prey(at: Vector2, r: float):
	if _prey_grid.is_empty():
		_prey_grid["made"] = true
		for i in animals.size():
			var a: Array = animals[i]
			if a[0] == "deer" or a[0] == "hare":
				var p := pos(a)
				var k := (int(p.x) >> 2) * 4096 + (int(p.y) >> 2)
				if not _prey_grid.has(k):
					_prey_grid[k] = []
				(_prey_grid[k] as Array).append([i, a])
	# the same answer as _nearest: the closest within r, the later in the list on a tie
	var cands := []
	var cx := int(at.x) >> 2
	var cy := int(at.y) >> 2
	for gy in range(cy - 1, cy + 2):
		for gx in range(cx - 1, cx + 2):
			cands.append_array(_prey_grid.get(gx * 4096 + gy, []))
	# (the list order among them: the index each had when the grid was made; a caught one leaves the
	# grid, and the others keep their order)
	cands.sort_custom(func(x, y): return int(x[0]) < int(y[0]))
	var best = null
	var bd := r
	for e in cands:
		var a: Array = e[1]
		var d := pos(a).distance_to(at)
		if d <= bd:
			bd = d; best = a; _prey_at = int(e[0])
	return best


var _prey_at := -1
var _prey_removed := []


func _prey_gone(a: Array) -> void:
	for k in _prey_grid:
		if k is int:
			var lst: Array = _prey_grid[k]
			for j in lst.size():
				if is_same(lst[j][1], a):
					lst.remove_at(j)
					return


func _nearest(at: Vector2, r: float, kinds: Array):
	var best = null
	var bd := r
	for a in animals:
		if a[0] in kinds:
			var d := pos(a).distance_to(at)
			if d <= bd:
				bd = d; best = a
	return best


## Game a hunter can find: in his grounds, or tracked a few tiles beyond them.
const TRACK := 4.0
const GAME := ["deer", "boar", "hare", "wolf"]
const LEG := 11.0


func _game_near(b: Sim.Bld):
	var c := sim.work_center(b)
	var at := Vector2(c.x, c.y)
	var r := float(sim.work_radius(b)) + TRACK
	# (build 78) only the animals heading near the grounds (by the grid, as _any_game), not all of them:
	# the same answer as _nearest over the whole list (the closest, the later in the list on a tie)
	if _dgrid.is_empty():
		_dgrid["made"] = true
		for a2 in animals:
			_g_add(a2)
	var reach := r + LEG + 1.0
	var best = null
	var bd := r
	var ties := []
	for gy in range(maxi(0, int(at.y - reach)) >> DCELL, (maxi(0, int(at.y + reach)) >> DCELL) + 1):
		for gx in range(maxi(0, int(at.x - reach)) >> DCELL, (maxi(0, int(at.x + reach)) >> DCELL) + 1):
			for a: Array in _dgrid.get(gx * 4096 + gy, []):
				var dx := float(a[3]) - at.x
				var dy := float(a[4]) - at.y
				if dx * dx + dy * dy > (r + LEG) * (r + LEG):
					continue
				var d := pos(a).distance_to(at)
				if d < bd or (d == bd and best == null):
					bd = d; best = a; ties = [a]
				elif d == bd:
					ties.append(a)
	if ties.size() > 1:
		# equally close: the one latest in the list
		var at_i := -1
		for t: Array in ties:
			for i in range(animals.size() - 1, at_i, -1):
				if is_same(animals[i], t):
					if i > at_i:
						at_i = i; best = t
					break
	return best


## The animals by where they are heading, in cells of 8 tiles (build 66: a hunter with no game in
## reach looked at every animal on the map). Made when first needed after a load, then kept up to date as
## animals move, are born, die or are caught.
var _dgrid := {}
const DCELL := 3          # (8 tiles: x >> 3)


func _g_key(a: Array) -> int:
	return (maxi(0, int(a[3])) >> DCELL) * 4096 + (maxi(0, int(a[4])) >> DCELL)


func _g_add(a: Array) -> void:
	if _dgrid.has("made") and a[0] in GAME:
		var k := _g_key(a)
		if not _dgrid.has(k):
			_dgrid[k] = []
		(_dgrid[k] as Array).append(a)


func _g_del(a: Array) -> void:
	if _dgrid.has("made") and a[0] in GAME:
		var cell: Array = _dgrid.get(_g_key(a), [])
		cell.erase(a)


## True when any game is within the hunter's grounds (stops at the first one found).
func _any_game(b: Sim.Bld) -> bool:
	var c := sim.work_center(b)
	var at := Vector2(c.x, c.y)
	var r := float(sim.work_radius(b)) + TRACK
	var r2 := r * r
	if _dgrid.is_empty():
		_dgrid["made"] = true
		for a2 in animals:
			_g_add(a2)
	var near := []
	var reach := r + LEG + 1.0
	for gy in range(maxi(0, int(at.y - reach)) >> DCELL, (maxi(0, int(at.y + reach)) >> DCELL) + 1):
		for gx in range(maxi(0, int(at.x - reach)) >> DCELL, (maxi(0, int(at.x + reach)) >> DCELL) + 1):
			near.append_array(_dgrid.get(gx * 4096 + gy, []))
	for a in near:
		# a quick test on where it is heading first (one move is at most LEG tiles): only animals near
		# the grounds need the exact place
		var dx := float(a[3]) - at.x
		var dy := float(a[4]) - at.y
		if dx * dx + dy * dy > (r + LEG) * (r + LEG):
			continue
		if a[0] in GAME and pos(a).distance_squared_to(at) <= r2:
			return true
	return false


func work_block(_p: Sim.Player, b: Sim.Bld) -> String:
	if b.ty == "hunter" and not _any_game(b):
		return "No game in the hunting grounds"
	if scared.has(b.id):
		return "Wolves scared the herd"
	return ""


## A hunter's catch is one real animal from his grounds.
func on_cycle(_p: Sim.Player, b: Sim.Bld) -> void:
	if b.ty == "hunter":
		var g = _game_near(b)
		if g != null:
			_g_del(g)
			animals.erase(g)


func ai_steps(_p: Sim.Player, _have: Callable) -> Array:
	return []


func building_lines(b: Sim.Bld) -> PackedStringArray:
	if b.ty != "hunter":
		return PackedStringArray()
	var c := sim.work_center(b)
	var n := 0
	var r := float(sim.work_radius(b)) + TRACK
	for a in animals:
		if pos(a).distance_to(Vector2(c.x, c.y)) <= r:
			n += 1
	return PackedStringArray(["Game in the hunting grounds: %d animal%s" % [n, "" if n == 1 else "s"]])


const WIDTH := {"deer": 0.62, "boar": 0.5, "hare": 0.3, "wolf": 0.6}
var _fish_rows: Array = []   # water tiles with fish (for the jumping fish), by map row, refreshed every 2 minutes
var _fish_t := -100.0


## The animals by map rows of AROW tiles (where each set out), made again each game second, or when
## animals are born or hunted.
const AROW := 8
var _rows: Array = []
var _rows_t := -1.0
var _rows_n := -1


func _index_rows() -> void:
	_rows_t = sim.time
	_rows_n = animals.size()
	_rows = []
	_rows.resize((sim.h + AROW - 1) / AROW)
	for r in _rows.size():
		_rows[r] = []
	for a in animals:
		(_rows[clampi(int(float(a[2])) / AROW, 0, _rows.size() - 1)] as Array).append(a)


func draw_map(view: CanvasItem, rect: Rect2i) -> void:
	var mv = view
	if float(mv.zoom) < 10.0:
		return
	var fog = sim.get_feature("fog")
	var r := Rect2(rect.position - Vector2i(1, 1), rect.size + Vector2i(2, 2))
	var anim := bool(mv.animate)
	var rx0 := r.position.x
	var ry0 := r.position.y
	var rx1 := r.end.x
	var ry1 := r.end.y
	# only the map rows on screen (an animal is listed by where it set out, as of up to a second ago:
	# within two moves of LEG tiles)
	if absf(sim.time - _rows_t) >= 1.0 or _rows.size() != (sim.h + AROW - 1) / AROW or _rows_n != animals.size():
		_index_rows()
	var near := []
	for row in range(maxi(0, int(ry0 - 2.0 * LEG) / AROW), mini(_rows.size() - 1, int(ry1 + 2.0 * LEG) / AROW) + 1):
		near.append_array(_rows[row])
	for a in near:
		# a quick test on where it set out from and where it is going first: on a big map nearly all of
		# the thousands of animals are off screen
		var ax: float = a[1]
		var bx: float = a[3]
		if (ax < rx0 and bx < rx0) or (ax > rx1 and bx > rx1):
			continue
		var ay: float = a[2]
		var by: float = a[4]
		if (ay < ry0 and by < ry0) or (ay > ry1 and by > ry1):
			continue
		var at := pos(a)
		if not r.has_point(at):
			continue
		if fog != null and not fog.visible_at(sim.idx(clampi(roundi(at.x), 0, sim.w - 1), clampi(roundi(at.y), 0, sim.h - 1))):
			continue
		var moving := sim.time < float(a[6])
		var k := String(a[0])
		var wd := float(WIDTH.get(k, 0.5))
		var f := int(sim.time * 6.0 + float(a[1]) * 3.0) % 4 if (moving and anim) else 0
		mv._sprite("unit_" + k, at + Vector2(0.5, 0.8 - float(mv.lift_at(at.x + 0.5, at.y + 0.8))), wd, f, float(a[3]) < float(a[1]))
	# fish jumping in the fishing grounds, now and then
	if anim and float(mv.zoom) >= 14.0:
		var w := sim.w
		# the fishing grounds by map row, found again only now and then (fished-out tiles are skipped
		# below), so only the rows on screen are looked at
		if absf(sim.time - _fish_t) >= 120.0 or _fish_rows.size() != sim.h:
			_fish_t = sim.time
			_fish_rows = []
			_fish_rows.resize(sim.h)
			for y in sim.h:
				var row := PackedInt32Array()
				for x in w:
					var i := y * w + x
					if sim.ter[i] == Sim.WATER and sim.amt[i] != 0:
						row.append(i)
				_fish_rows[y] = row
		for y in range(maxi(0, rect.position.y), mini(sim.h - 1, rect.end.y) + 1):
			for i in (_fish_rows[y] as PackedInt32Array):
				var x := i % w
				if x < rect.position.x or x > rect.end.x:
					continue
				if sim.amt[i] == 0 or (fog != null and not fog.visible_at(i)):
					continue
				var ph := fmod(sim.time * 0.15 + float((i * 2654435761) % 1000) / 1000.0, 1.0)
				if ph < 0.06:
					var u := ph / 0.06
					var c := Vector2(x + 0.5, y + 0.6)
					var p0 := c + Vector2(-0.18 + u * 0.36, -sin(u * PI) * 0.3)
					view.draw_line(p0, p0 + Vector2(0.12, 0.02 - cos(u * PI) * 0.06), Color(0.85, 0.9, 0.95, 0.9), 0.05)
					if u > 0.85:
						view.draw_arc(c, 0.12 + (u - 0.85) * 1.2, 0, TAU, 12, Color(1, 1, 1, 0.5), 0.03)


func save_state() -> Dictionary:
	return {"animals": animals, "scared": scared, "rng": rng.state, "seed": rng.seed, "t": _t}


func load_state(d: Dictionary) -> void:
	animals = d.get("animals", [])
	_dgrid = {}
	scared = {}
	for k in d.get("scared", {}):
		scared[int(k)] = float(d.scared[k])
	_t = int(d.get("t", 0))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng", 0))
