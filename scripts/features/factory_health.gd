extends Feature
## Factory smoke and health: the troubles of the Industrial age (build 77).
##
## From the Industrial age on, working smelters, steelworks, mills and every workshop with a steam engine
## fill the air of the homes near them with smoke (data/health.json says which buildings, how much and
## how far). Smoke thins with distance; a park takes away half the smoke of the homes near it. Homes also
## want clean water: a waterworks burning coal pipes it to the homes near it.
##
## Each realm's health (0 to 1) falls with the smoke its homes breathe and with homes that lack clean
## water. Poor health slows work (up to 15%), raises the risk of fevers and dysentery (Diseases), and
## below half some people die of it. Artisans and nobles of the age want clean water, nobles a park as
## well, near their homes: what they lack makes them less content (Contentment).
##
## Everything is worked out every 5 game seconds from the buildings standing, and kept in the save.

const SPEED_LOSS := 0.15        # work speed lost at health 0
const DEATH_RATE := 0.0003      # deaths per person per second for each point of health under DEATH_BELOW
const DEATH_BELOW := 0.5
const NEED_MOOD := 0.1          # contentment lost when every want of the age goes unmet
const SERVED_FOR := 75.0        # seconds a waterworks counts as working after its last cycle
const SMOG_HIGH := 0.5          # a home with this much smoke counts as smoky

var cfg: Dictionary = {}
var air := {}          # realm id -> how much smoke its homes breathe, by room (0 clean, 1 thick)
var smoky := {}        # realm id -> share of its homes (by room) with SMOG_HIGH smoke or more
var water := {}        # realm id -> share of its homes (by room) with clean water
var parks := {}        # realm id -> share of its homes (by room) near a park
var health := {}       # realm id -> health, 0 to 1
var served := {}       # waterworks id -> time of its last cycle
var dying := {}        # realm id -> deaths waiting to happen (fractional)
var died := {}         # realm id -> people who died of the smoke
var told := {}         # realm id -> true once the player was told about the smoke
var _t := 0
var _src_cache := {}   # realm id -> [tick, buildings, sources]: not saved, worked out again


func _init() -> void:
	id = "factory_health"
	title = "Factory smoke and health"
	info = "In the Industrial age factories and steam engines fill nearby homes with smoke and people want clean water: build parks and waterworks, or health, work and contentment suffer."
	default_on = true
	cfg = load_cfg()


## data/health.json, with the same file in the mods folder merged over it.
static func load_cfg() -> Dictionary:
	var out := {}
	for path in ["res://data/health.json", "user://data/health.json"]:
		if not FileAccess.file_exists(path):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			for k in d:
				if out.get(k) is Dictionary and d[k] is Dictionary:
					var m: Dictionary = (out[k] as Dictionary).duplicate()
					m.merge(d[k], true)
					out[k] = m
				else:
					out[k] = d[k]
	return out


func _radius() -> float:
	return float(cfg.get("smog_radius", 6))


## Whether realm p has reached the age of factory smoke.
func active(p: Sim.Player) -> bool:
	return p.age >= int(cfg.get("from_age", 6))


## How much smoke building b gives off now (0 when it gives none).
func smoke_of(b: Sim.Bld) -> float:
	if b.dead or b.state != "ready":
		return 0.0
	var s := 0.0
	if b.staffed:
		s = float((cfg.get("smog", {}) as Dictionary).get(b.ty, 0.0))
	if b.steam and sim.railway.steam_on(b):
		s += float(cfg.get("steam_smog", 0.8))
	return s


func is_polluter(ty: String) -> bool:
	return (cfg.get("smog", {}) as Dictionary).has(ty)


func _cleaner(ty: String) -> Dictionary:
	return (cfg.get("cleaners", {}) as Dictionary).get(ty, {})


func _water(ty: String) -> Dictionary:
	return (cfg.get("water", {}) as Dictionary).get(ty, {})


func _water_on(b: Sim.Bld) -> bool:
	return b.state == "ready" and not b.dead and sim.time - float(served.get(b.id, -1e9)) < SERVED_FOR


static func _d2(ax: int, ay: int, bx: int, by: int) -> int:
	return (ax - bx) * (ax - bx) + (ay - by) * (ay - by)


## The realm's polluters [x, y, smoke], cleaners [x, y, radius, share] and waterworks [x, y, radius].
## Kept for the rest of the tick (rival plans score many spots at once).
func _sources(p: Sim.Player) -> Array:
	var ck: Array = _src_cache.get(p.id, [])
	if not ck.is_empty() and float(ck[0]) == sim.time and int(ck[1]) == sim.blds.size():
		return ck[2]
	var out := _sources_now(p)
	_src_cache[p.id] = [sim.time, sim.blds.size(), out]
	return out


func _sources_now(p: Sim.Player) -> Array:
	var pol := []
	var cln := []
	var wat := []
	for b: Sim.Bld in sim.realm_blds(p):
		if b.dead or b.state != "ready":
			continue
		var s := smoke_of(b)
		if s > 0.0:
			pol.append([b.x, b.y, s])
		var c := _cleaner(b.ty)
		if not c.is_empty():
			cln.append([b.x, b.y, int(c.get("radius", 6)), float(c.get("clean", 0.5))])
		var w := _water(b.ty)
		if not w.is_empty() and _water_on(b):
			wat.append([b.x, b.y, int(w.get("radius", 12))])
	return [pol, cln, wat]


## Smoke at tile (x, y) from the given polluters and cleaners.
func _smoke_at(x: int, y: int, pol: Array, cln: Array) -> float:
	var r := _radius()
	var s := 0.0
	for f: Array in pol:
		var d := sqrt(float(_d2(x, y, int(f[0]), int(f[1]))))
		if d < r:
			s += float(f[2]) * (1.0 - d / r)
	if s > 0.0:
		for c: Array in cln:
			if _d2(x, y, int(c[0]), int(c[1])) <= int(c[2]) * int(c[2]):
				s *= 1.0 - float(c[3])
				break
	return minf(s, 3.0)


## Smoke at tile (x, y) for realm p (0 before its Industrial age). For homes, rival plans and the map.
func smoke_at(p: Sim.Player, x: int, y: int) -> float:
	if not active(p):
		return 0.0
	var src := _sources(p)
	return _smoke_at(x, y, src[0], src[1])


func _near(x: int, y: int, list: Array, ri: int) -> bool:
	for c: Array in list:
		if _d2(x, y, int(c[0]), int(c[1])) <= int(c[ri]) * int(c[ri]):
			return true
	return false


## Works out the air, the water and the parks of realm p's homes, and its health.
func _measure(p: Sim.Player) -> void:
	if not active(p):
		air[p.id] = 0.0
		smoky[p.id] = 0.0
		water[p.id] = 1.0
		parks[p.id] = 1.0
		health[p.id] = 1.0
		return
	var src := _sources(p)
	var room := 0.0
	var a := 0.0
	var sm := 0.0
	var wa := 0.0
	var pk := 0.0
	for h: Sim.Bld in sim.realm_blds(p):
		if h.dead or h.state != "ready" or not h.def.has("housing"):
			continue
		var n := float(h.def.housing)
		room += n
		var s := _smoke_at(h.x, h.y, src[0], src[1])
		a += n * minf(1.0, s)
		if s >= SMOG_HIGH:
			sm += n
		if _near(h.x, h.y, src[2], 2):
			wa += n
		if _near(h.x, h.y, src[1], 2):
			pk += n
	if room <= 0.0:
		air[p.id] = 0.0
		smoky[p.id] = 0.0
		water[p.id] = 1.0
		parks[p.id] = 1.0
	else:
		air[p.id] = a / room
		smoky[p.id] = sm / room
		water[p.id] = wa / room
		parks[p.id] = pk / room
	health[p.id] = clampf(1.0 - 0.6 * float(air[p.id]) - 0.3 * (1.0 - float(water[p.id])), 0.0, 1.0)


func health_of(p: Sim.Player) -> float:
	return float(health.get(p.id, 1.0))


func air_of(p: Sim.Player) -> float:
	return float(air.get(p.id, 0.0))


func water_share(p: Sim.Player) -> float:
	return float(water.get(p.id, 0.0 if active(p) else 1.0))


func park_share(p: Sim.Player) -> float:
	return float(parks.get(p.id, 0.0 if active(p) else 1.0))


## How much of what the age's artisans and nobles want (clean water, parks) realm p leaves unmet, 0 to 1,
## weighted by how many of each there are.
func unmet(p: Sim.Player) -> float:
	if not active(p):
		return 0.0
	var needs: Dictionary = cfg.get("needs", {})
	var tot := 0.0
	var gap := 0.0
	for cls in needs:
		var count := float(p.artisan if cls == "artisan" else (p.noble if cls == "noble" else (p.peasant if cls == "peasant" else 0)))
		if count <= 0.0:
			continue
		for nd in needs[cls]:
			tot += count
			gap += count * (1.0 - (water_share(p) if nd == "water" else park_share(p)))
	return gap / tot if tot > 0.0 else 0.0


## Contentment lost to unmet wants (read by the contentment feature).
func mood_loss(p: Sim.Player) -> float:
	return NEED_MOOD * unmet(p)


func on_cycle(_p: Sim.Player, b: Sim.Bld) -> void:
	if not _water(b.ty).is_empty():
		served[b.id] = sim.time


func work_block(p: Sim.Player, b: Sim.Bld) -> String:
	if not _water(b.ty).is_empty() and not active(p):
		return tr("Not needed before the Industrial age")
	return ""


func on_second() -> void:
	_t += 1
	for p: Sim.Player in sim.players:
		if not p.alive:
			continue
		if _t % 5 == 0 or not health.has(p.id):
			_measure(p)
		if not active(p):
			continue
		if not p.ai and not told.has(p.id) and float(smoky.get(p.id, 0.0)) > 0.0:
			told[p.id] = true
			sim.emit_log(tr("Factory smoke hangs over your homes. Parks clean the air near them, waterworks bring clean water; poor health slows work and in the end kills."), Color("e0b060"))
		# poor health: some die of it
		var h := health_of(p)
		if h < DEATH_BELOW and sim.pop_total(p) > 30:
			var d := float(dying.get(p.id, 0.0)) + float(sim.pop_total(p)) * (DEATH_BELOW - h) * DEATH_RATE
			while d >= 1.0:
				d -= 1.0
				_kill(p)
			dying[p.id] = d


func _kill(p: Sim.Player) -> void:
	var who := ""
	if p.peasant > 4:
		p.peasant -= 1
		who = tr("peasant")
	elif p.artisan > 1:
		p.artisan -= 1
		who = tr("artisan")
	else:
		return
	died[p.id] = int(died.get(p.id, 0)) + 1
	if not p.ai:
		sim.emit_log(tr("A %s died of the factory smoke and foul water.") % who, Color("e08a6a"))


func speed_bonus(p: Sim.Player, _b: Sim.Bld) -> float:
	return -SPEED_LOSS * (1.0 - health_of(p))


func ai_steps(p: Sim.Player, have: Callable) -> Array:
	if not active(p):
		return []
	var pop := sim.pop_total(p)
	var homes := 0
	for b: Sim.Bld in sim.realm_blds(p):
		if not b.dead and b.def.has("housing"):
			homes += 1
	var parks_n := int(have.call("park"))
	var water_n := int(have.call("waterworks"))
	var want_parks := parks_n + (1 if (float(smoky.get(p.id, 0.0)) > 0.1 or air_of(p) > 0.08 or (p.noble > 0 and park_share(p) < 0.7)) else 0)
	var want_water := water_n + (1 if water_share(p) < 0.8 and (pop > 40 or p.artisan + p.noble > 0) else 0)
	var out := [
		["waterworks", mini(want_water, 1 + homes / 8)],
		["park", mini(want_parks, 1 + homes / 5)],
	]
	# waterworks burn coal: another coal mine when they stand idle for want of it
	var mines := int(have.call("coal_mine"))
	if water_n > 0 and float(p.stock.get("coal", 0.0)) < 4.0 and mines < 5:
		out.append(["coal_mine", mines + 1])
	return out


## Extra score for a rival's building spot: parks where the homes breathe the most smoke, waterworks
## among homes without clean water, homes away from smoke, smoky workshops away from homes.
func ai_site_score(p: Sim.Player, ty: String, x: int, y: int) -> float:
	if not active(p):
		return 0.0
	var d: Dictionary = GameData.bld.get(ty, {})
	var c := _cleaner(ty)
	var w := _water(ty)
	if not c.is_empty() or not w.is_empty():
		var src := _sources(p)
		var r := int(c.get("radius", w.get("radius", 8)))
		var gain := 0.0
		for h: Sim.Bld in sim.realm_blds(p):
			if h.dead or not h.def.has("housing") or _d2(x, y, h.x, h.y) > r * r:
				continue
			var n := float(h.def.housing)
			if not c.is_empty():
				if not _near(h.x, h.y, src[1], 2):
					gain += n * (0.3 + minf(1.0, _smoke_at(h.x, h.y, src[0], src[1])))
			elif not _near(h.x, h.y, src[2], 2):
				gain += n
		return gain * 0.4
	if d.has("housing"):
		return -smoke_at(p, x, y) * 6.0
	if is_polluter(ty):
		var near := 0.0
		var rr := int(_radius())
		for h: Sim.Bld in sim.realm_blds(p):
			if not h.dead and h.def.has("housing") and _d2(x, y, h.x, h.y) < rr * rr:
				near += float(h.def.housing)
		return -near * 0.15
	return 0.0


func _health_col(h: float) -> String:
	return "#86ad5c" if h >= 0.8 else ("#d9483d" if h < DEATH_BELOW else "#e0b060")


func panel_lines(p: Sim.Player) -> PackedStringArray:
	if not active(p):
		return PackedStringArray()
	var h := health_of(p)
	var t := tr("Factory towns  health [color=%s][b]%d%%[/b][/color] (work -%d%%): %d%% of homes in thick smoke, clean water for %d%%, parks near %d%%") % [_health_col(h), roundi(h * 100.0), roundi(SPEED_LOSS * (1.0 - h) * 100.0), roundi(float(smoky.get(p.id, 0.0)) * 100.0), roundi(water_share(p) * 100.0), roundi(park_share(p) * 100.0)]
	if int(died.get(p.id, 0)) > 0:
		t += tr(", %d died of it") % int(died[p.id])
	var out := PackedStringArray([t])
	var u := unmet(p)
	if u > 0.05:
		out.append(tr("[color=#e0b060]Artisans want clean water near their homes, nobles clean water and a park: %d%% of that is missing (contentment -%d%%).[/color]") % [roundi(u * 100.0), roundi(mood_loss(p) * 100.0)])
	return out


func top_text(p: Sim.Player) -> String:
	if active(p) and health_of(p) < DEATH_BELOW:
		return tr("Smog!")
	return ""


func building_lines(b: Sim.Bld) -> PackedStringArray:
	if b.p < 1 or b.p > sim.players.size():
		return PackedStringArray()
	var p: Sim.Player = sim.players[b.p - 1]
	if not active(p):
		if not _cleaner(b.ty).is_empty() or not _water(b.ty).is_empty():
			return PackedStringArray([tr("Needed from the Industrial age on, when factory smoke and crowded towns come.")])
		return PackedStringArray()
	var src := _sources(p)
	if b.def.has("housing"):
		var s := _smoke_at(b.x, b.y, src[0], src[1])
		var what := tr("clean") if s < 0.15 else (tr("some smoke") if s < SMOG_HIGH else tr("[color=#e0b060]thick smoke[/color]"))
		return PackedStringArray([tr("Air: %s · clean water: %s · park nearby: %s") % [what, tr("yes") if _near(b.x, b.y, src[2], 2) else tr("[color=#e0b060]no[/color]"), tr("yes") if _near(b.x, b.y, src[1], 2) else tr("no")]])
	var c := _cleaner(b.ty)
	var w := _water(b.ty)
	var r := int(c.get("radius", w.get("radius", 0)))
	if r > 0:
		var n := 0
		for h: Sim.Bld in sim.realm_blds(p):
			if not h.dead and h.def.has("housing") and _d2(b.x, b.y, h.x, h.y) <= r * r:
				n += 1
		if not c.is_empty():
			return PackedStringArray([tr("Takes away %d%% of the smoke of %d homes within %d tiles") % [roundi(float(c.get("clean", 0.5)) * 100.0), n, r]])
		return PackedStringArray([tr("Clean water for %d homes within %d tiles%s") % [n, r, "" if _water_on(b) else tr(" [color=#e0b060](not while it lacks coal)[/color]")]])
	var s2 := smoke_of(b)
	if s2 > 0.0:
		var rr := int(_radius())
		var n2 := 0
		for h: Sim.Bld in sim.realm_blds(p):
			if not h.dead and h.def.has("housing") and _d2(b.x, b.y, h.x, h.y) < rr * rr:
				n2 += 1
		return PackedStringArray([tr("Smoke reaches %d homes within %d tiles; a park near them takes half of it away") % [n2, rr]])
	return PackedStringArray()


func draw_map(view: CanvasItem, rect: Rect2i) -> void:
	var mv = view
	if not ("place_type" in mv) or sim.players.is_empty():
		return
	var me: Sim.Player = sim.players[0]
	if not active(me):
		return
	var r := _radius()
	var grown := rect.grow(int(r) + 1)
	# a haze round the player's smoky buildings
	for b: Sim.Bld in sim.realm_blds(me):
		if not grown.has_point(Vector2i(b.x, b.y)):
			continue
		var s := smoke_of(b)
		if s <= 0.0:
			continue
		var c := Vector2(b.x, b.y) + Vector2(0.5, 0.5)
		var a := clampf(0.05 * s, 0.03, 0.09)
		for k in 3:
			view.draw_circle(c, r * (0.4 + 0.3 * k), Color(0.32, 0.3, 0.28, a))
	# while placing a park, a waterworks or a smoky workshop, the ring it reaches
	var pt := String(mv.place_type)
	if pt != "" and mv.ghost.x >= 0:
		var rr := 0.0
		var col := Color(0.6, 0.9, 0.5, 0.6)
		if not _cleaner(pt).is_empty():
			rr = float(_cleaner(pt).get("radius", 6))
		elif not _water(pt).is_empty():
			rr = float(_water(pt).get("radius", 12))
			col = Color(0.5, 0.75, 1.0, 0.6)
		elif is_polluter(pt):
			rr = r
			col = Color(0.55, 0.5, 0.45, 0.7)
		if rr > 0.0:
			view.draw_arc(Vector2(mv.ghost) + Vector2(0.5, 0.5), rr, 0.0, TAU, 64, col, 0.08)


func save_state() -> Dictionary:
	for k in served.keys():
		if not sim.by_id.has(k):
			served.erase(k)
	return {"air": air, "smoky": smoky, "water": water, "parks": parks, "health": health, "served": served,
		"dying": dying, "died": died, "told": told, "t": _t}


func on_start(_loaded: bool) -> void:
	_src_cache = {}


func load_state(d: Dictionary) -> void:
	_src_cache = {}
	for key in ["air", "smoky", "water", "parks", "health", "served", "dying", "died", "told"]:
		var dst: Dictionary = get(key)
		dst.clear()
		var src: Dictionary = d.get(key, {})
		for k in src:
			dst[int(k)] = src[k]
	_t = int(d.get("t", 0))
