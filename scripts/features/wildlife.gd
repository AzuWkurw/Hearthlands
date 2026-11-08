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
	if not loaded or rng.seed == 0:
		rng.seed = (sim.seed_str + ":wildlife").hash()
	_land = 0
	for i in sim.w * sim.h:
		if sim.ter[i] == Sim.GRASS:
			_land += 1
	if animals.is_empty():
		for k: String in KINDS:
			for n in maxi(2, _land / int(KINDS[k].per)):
				var at := _habitat_spot(k, -1, -1, 0)
				if at.x >= 0:
					animals.append([k, at.x, at.y, at.x, at.y, sim.time, sim.time + rng.randf_range(0.0, 6.0)])


func _cap(k: String) -> int:
	return maxi(3, int(_land / int(KINDS[k].per) * 2.0))


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
		var trees := sim.count_near(x, y, 2, "tree")
		if k in ["deer", "boar", "wolf"] and trees < 2 and r <= 0:
			continue
		if k == "hare" and trees > 6:
			continue
		if k == "wolf" and r <= 0:
			var cl = sim.get_feature("seasons")
			if cl != null and cl.biome_at(x, y) != cl.TAIGA and rng.randf() < 0.5:
				continue
		return Vector2(x, y)
	return Vector2(-1, -1)


func _near_building(x: int, y: int, r: int) -> bool:
	for yy in range(maxi(0, y - r), mini(sim.h - 1, y + r) + 1):
		for xx in range(maxi(0, x - r), mini(sim.w - 1, x + r) + 1):
			if sim.bmap[yy * sim.w + xx] != 0:
				return true
	return false


func pos(a: Array) -> Vector2:
	var f := clampf((sim.time - float(a[5])) / maxf(0.01, float(a[6]) - float(a[5])), 0.0, 1.0)
	return Vector2(float(a[1]), float(a[2])).lerp(Vector2(float(a[3]), float(a[4])), f)


func on_second() -> void:
	_t += 1
	for a in animals:
		if sim.time < float(a[6]) + rng.randf_range(1.0, 6.0):
			continue
		var here := Vector2(float(a[3]), float(a[4]))
		# mostly short moves; now and then a longer roam, so animals spread back into hunted land
		var to := _habitat_spot(String(a[0]), roundi(here.x), roundi(here.y), 6 if rng.randf() < 0.25 else 3)
		if to.x < 0:
			# boxed in by buildings: wander off further
			to = _habitat_spot(String(a[0]), roundi(here.x), roundi(here.y), 7)
		if to.x < 0:
			continue
		a[1] = here.x; a[2] = here.y; a[3] = to.x; a[4] = to.y
		a[5] = sim.time
		a[6] = sim.time + here.distance_to(to) / float(KINDS[a[0]].speed)
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
			count[k] = int(count.get(k, 0)) + 1


func _wolves() -> void:
	for wv in animals.filter(func(a): return a[0] == "wolf"):
		var wp := pos(wv)
		# a farm's herd nearby
		for f: Sim.Bld in _farms_near(wp, 3):
			if not scared.has(f.id) and rng.randf() < 0.1 and not _hunter_near(f):
				scared[f.id] = sim.time + 45.0
				if f.p == sim.human().id and sim.time - _warned > 60.0:
					_warned = sim.time
					sim.emit_log("Wolves scared the herd of your %s. A hunter nearby keeps them down." % String(f.def.name).to_lower(), Color("f0b070"))
		# or a deer or hare
		if rng.randf() < 0.02:
			var prey = _nearest(wp, 2.0, ["deer", "hare"])
			if prey != null:
				animals.erase(prey)
	for k in scared.keys():
		if sim.time >= float(scared[k]):
			scared.erase(k)


## A hunter whose grounds reach the farm keeps the wolves away from it.
func _hunter_near(f: Sim.Bld) -> bool:
	for b: Sim.Bld in sim.realm_blds(sim.players[f.p - 1]):
		if b.ty == "hunter" and b.staffed and Vector2(b.x - f.x, b.y - f.y).length() <= float(sim.work_radius(b)) + 1.0:
			return true
	return false


func _farms_near(at: Vector2, r: float) -> Array:
	var out := []
	for b: Sim.Bld in sim.blds:
		if b.ty in FARMS and b.state == "ready" and Vector2(b.x, b.y).distance_to(at) <= r:
			out.append(b)
	return out


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


func _game_near(b: Sim.Bld):
	var c := sim.work_center(b)
	return _nearest(Vector2(c.x, c.y), float(sim.work_radius(b)) + TRACK, ["deer", "boar", "hare", "wolf"])


func work_block(_p: Sim.Player, b: Sim.Bld) -> String:
	if b.ty == "hunter" and _game_near(b) == null:
		return "No game in the hunting grounds"
	if scared.has(b.id):
		return "Wolves scared the herd"
	return ""


## A hunter's catch is one real animal from his grounds.
func on_cycle(_p: Sim.Player, b: Sim.Bld) -> void:
	if b.ty == "hunter":
		var g = _game_near(b)
		if g != null:
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


func draw_map(view: CanvasItem, rect: Rect2i) -> void:
	var mv = view
	if float(mv.zoom) < 10.0:
		return
	var fog = sim.get_feature("fog")
	var r := Rect2(rect.position - Vector2i(1, 1), rect.size + Vector2i(2, 2))
	var anim := bool(mv.animate)
	for a in animals:
		var at := pos(a)
		if not r.has_point(at):
			continue
		if fog != null and not fog.visible_at(sim.idx(clampi(roundi(at.x), 0, sim.w - 1), clampi(roundi(at.y), 0, sim.h - 1))):
			continue
		var moving := sim.time < float(a[6])
		var k := String(a[0])
		var wd := {"deer": 0.62, "boar": 0.5, "hare": 0.3, "wolf": 0.6}[k] as float
		var f := int(sim.time * 6.0 + float(a[1]) * 3.0) % 4 if (moving and anim) else 0
		mv._sprite("unit_" + k, at + Vector2(0.5, 0.8), wd, f, float(a[3]) < float(a[1]))
	# fish jumping in the fishing grounds, now and then
	if anim and float(mv.zoom) >= 14.0:
		var w := sim.w
		for y in range(maxi(0, rect.position.y), mini(sim.h, rect.end.y + 1)):
			for x in range(maxi(0, rect.position.x), mini(w, rect.end.x + 1)):
				var i := y * w + x
				if sim.ter[i] != Sim.WATER or sim.amt[i] == 0:
					continue
				if fog != null and not fog.visible_at(i):
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
	scared = {}
	for k in d.get("scared", {}):
		scared[int(k)] = float(d.scared[k])
	_t = int(d.get("t", 0))
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng", 0))
