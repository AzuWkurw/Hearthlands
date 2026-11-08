extends Feature
## Geologists. What lies under the mountains is unknown until a geologist has surveyed it: ore veins
## don't show on the map, and mines can only be built on surveyed tiles with the right ore.
## Send geologist (Industry tab), then click a mountain in or near your land: an idle peasant takes a
## pickaxe from the store (he brings it back), walks there over land, checks up to 12 mountain tiles
## around the spot (18 with Prospecting) and plants a marker on each: coal, iron, gold, copper,
## granite or nothing, bigger for richer veins. The markers fade after five minutes but your realm
## remembers what was found; picking a mine to build shows every surveyed tile of its ore again.
## Prospecting also lets 4 geologists out at once instead of 2; Geological survey makes one find
## reveal its whole vein. Rivals send geologists too.

const SURVEY_TIME := 3.5           # seconds a geologist spends on each tile
const WALK_SPEED := 1.1
const FADE := 300.0                # seconds the markers stay on the map
const ORE_COL := {1: Color("3a3a3a"), 2: Color("b07850"), 3: Color("f0c840"), 4: Color("c8c8c0"), 5: Color("d0783a")}

var known: Dictionary = {}         # realm id -> PackedByteArray, 1 where surveyed
var marks: Array = []              # your markers: [tile, time planted]
var trips: Array = []              # geologists out: [realm, path, t0, t_arrive, tiles to survey, t_done, t_home, done count]
var rng := RandomNumberGenerator.new()
var _ai_t: Dictionary = {}         # realm id -> game time of the rival's next survey decision


func _init() -> void:
	id = "geology"
	title = "Geologists"
	info = "Ore veins stay hidden until a geologist surveys the mountain; mines need surveyed veins. Send geologists from the Industry tab."
	default_on = true


func on_start(loaded: bool) -> void:
	if not loaded or rng.seed == 0:
		rng.seed = (sim.seed_str + ":geology").hash()
	var n := sim.w * sim.h
	for p: Sim.Player in sim.players:
		var k: PackedByteArray = known.get(p.id, PackedByteArray())
		if k.size() != n:
			k = PackedByteArray()
			k.resize(n)
			# a game that ran without geologists: the land around existing mines is known
			for b: Sim.Bld in sim.blds:
				if b.p == p.id and b.def.has("mine"):
					_mark_area(k, b.x, b.y, 2)
			known[p.id] = k
	for p: Sim.Player in sim.players:
		if not trips.any(func(t): return int(t[0]) == p.id):
			p.away = 0


func _mark_area(k: PackedByteArray, cx: int, cy: int, r: int) -> void:
	for y in range(maxi(0, cy - r), mini(sim.h - 1, cy + r) + 1):
		for x in range(maxi(0, cx - r), mini(sim.w - 1, cx + r) + 1):
			k[y * sim.w + x] = 1


func known_at(pid: int, i: int) -> bool:
	var k: PackedByteArray = known.get(pid, PackedByteArray())
	return i >= 0 and i < k.size() and k[i] == 1


func _max_out(p: Sim.Player) -> int:
	return 4 if p.techs.has("prospecting") else 2


func _out(p: Sim.Player) -> int:
	var n := 0
	for t in trips:
		if int(t[0]) == p.id:
			n += 1
	return n


## Sends a geologist of realm p to survey around tile (x, y). Returns "" or why not.
func send(p: Sim.Player, x: int, y: int) -> String:
	if not sim.inb(x, y):
		return "Outside the map"
	var i := sim.idx(x, y)
	# in or near your land: within 3 tiles of it
	var near := false
	for yy in range(maxi(0, y - 3), mini(sim.h - 1, y + 3) + 1):
		for xx in range(maxi(0, x - 3), mini(sim.w - 1, x + 3) + 1):
			if sim.owner[yy * sim.w + xx] == p.id:
				near = true
	if not near:
		return "Too far from your land: geologists survey your land and up to 3 tiles beyond"
	var r := 4 if p.techs.has("prospecting") else 3
	var most := 18 if p.techs.has("prospecting") else 12
	var tiles := []
	# tiles another of your geologists is already on the way to survey are left to him
	var taken := {}
	for t in trips:
		if int(t[0]) == p.id:
			for j in (t[4] as PackedInt32Array):
				taken[j] = true
	for yy in range(maxi(0, y - r), mini(sim.h - 1, y + r) + 1):
		for xx in range(maxi(0, x - r), mini(sim.w - 1, x + r) + 1):
			var j := yy * sim.w + xx
			if sim.ter[j] == Sim.MOUNT and not known_at(p.id, j) and not taken.has(j):
				tiles.append([Vector2(xx - x, yy - y).length_squared(), j])
	if tiles.is_empty():
		return "No unsurveyed mountain there"
	if _out(p) >= _max_out(p):
		return "All your geologists are out (%d)" % _max_out(p)
	if p.peasant - p.used_peasant - p.away < 1:
		return "No idle peasant to send"
	if float(p.stock.get("pickaxes", 0.0)) < 1.0 and bool(sim.opts.get("tools", true)):
		return "No pickaxe in store for him"
	tiles.sort_custom(func(a, b): return a[0] < b[0])
	var list := PackedInt32Array()
	for e in tiles.slice(0, most):
		list.append(int(e[1]))
	# from the nearest store, over land
	var best: Sim.Bld = p.hq
	var bd := 1e9
	for b: Sim.Bld in sim.realm_blds(p):
		if sim.is_store(b) and b.state == "ready":
			var d := Vector2(b.x - x, b.y - y).length()
			if d < bd:
				bd = d; best = b
	var path := sim.logistics.land_path(sim.idx(best.x, best.y), list[0])
	if path.is_empty() or path[path.size() - 1] != list[0] and Vector2(path[path.size() - 1] % sim.w - x, path[path.size() - 1] / sim.w - y).length() > r + 1:
		return "He can't get there over land"
	if bool(sim.opts.get("tools", true)):
		sim.take(p, "pickaxes", 1.0, sim.idx(best.x, best.y))
	p.away += 1
	var walk := path.size() / WALK_SPEED
	var t_arr := sim.time + walk
	var t_done := t_arr + list.size() * SURVEY_TIME
	trips.append([p.id, path, sim.time, t_arr, list, t_done, t_done + walk, 0])
	sim.staffing(p)
	return ""


## Where a geologist is now: walking out, going from tile to tile, or walking home.
func trip_pos(t: Array) -> Vector2:
	var path: PackedInt32Array = t[1]
	var list: PackedInt32Array = t[4]
	var now := sim.time
	var w := sim.w
	if now < float(t[3]) or now >= float(t[5]):
		var f := clampf((now - float(t[2])) / maxf(0.01, float(t[3]) - float(t[2])), 0.0, 1.0) if now < float(t[3]) else 1.0 - clampf((now - float(t[5])) / maxf(0.01, float(t[6]) - float(t[5])), 0.0, 1.0)
		var n := path.size() - 1
		if n < 1:
			return Vector2(path[0] % w, path[0] / w)
		var k := mini(floori(f * n), n - 1)
		return Vector2(path[k] % w, path[k] / w).lerp(Vector2(path[k + 1] % w, path[k + 1] / w), f * n - k)
	var s := (now - float(t[3])) / SURVEY_TIME
	var k2 := mini(int(s), list.size() - 1)
	var a := list[k2]
	var b := list[mini(k2 + 1, list.size() - 1)]
	var g := clampf((s - k2) * 2.0 - 1.0, 0.0, 1.0)     # half the time on the tile, half walking on
	return Vector2(a % w, a / w).lerp(Vector2(b % w, b / w), g)


func _survey(p: Sim.Player, i: int) -> void:
	var k: PackedByteArray = known[p.id]
	var tiles := PackedInt32Array([i])
	# Geological survey: a find reveals the whole vein
	if p.techs.has("geological_survey") and sim.ore[i] != 0 and sim.vein[i] > 0:
		tiles = sim.vein_tiles[sim.vein[i]]
	for j in tiles:
		if k[j] == 0:
			k[j] = 1
			if p.id == sim.human().id:
				sim.changed_tiles.append(j)
	if p.id == sim.human().id:
		marks.append([i, sim.time])


func on_second() -> void:
	for idx in range(trips.size() - 1, -1, -1):
		var t: Array = trips[idx]
		var p: Sim.Player = sim.players[int(t[0]) - 1]
		var list: PackedInt32Array = t[4]
		# tiles surveyed so far
		var due := clampi(int((sim.time - float(t[3])) / SURVEY_TIME) + 1, 0, list.size()) if sim.time >= float(t[3]) else 0
		while int(t[7]) < due:
			_survey(p, list[int(t[7])])
			t[7] = int(t[7]) + 1
		if sim.time >= float(t[6]):
			trips.remove_at(idx)
			p.away = maxi(0, p.away - 1)
			if bool(sim.opts.get("tools", true)):
				sim.give(p, "pickaxes", 1.0)
			if not p.ai:
				sim.emit_log("A geologist is back: %s" % _report(list), Color("c8b070"))
	for k in range(marks.size() - 1, -1, -1):
		if sim.time - float(marks[k][1]) > FADE:
			marks.remove_at(k)
	_ai_surveys()


func _report(list: PackedInt32Array) -> String:
	var found := {}
	for i in list:
		if sim.ore[i] != 0 and sim.vein_left(i) > 0:
			var nm := String(GameData.ORE_NAMES.get(int(sim.ore[i]), "ore"))
			found[nm] = int(found.get(nm, 0)) + 1
	if found.is_empty():
		return "nothing under those %d tiles." % list.size()
	var parts := []
	for k in found:
		parts.append("%s on %d tile%s" % [k, found[k], "" if found[k] == 1 else "s"])
	return "found " + ", ".join(parts) + "."


## Rivals survey their own mountains, a few at a time, when they have some left unsurveyed.
func _ai_surveys() -> void:
	for p: Sim.Player in sim.players:
		if not p.ai or not p.alive:
			continue
		if sim.time < float(_ai_t.get(p.id, 60.0 + p.id * 7.0)):
			continue
		_ai_t[p.id] = sim.time + rng.randf_range(25.0, 45.0)
		if _out(p) >= 1:
			continue
		var mtn: PackedInt32Array = sim.owned(p.id)[1]
		var cands := []
		for i in mtn:
			if not known_at(p.id, i):
				cands.append(i)
		if cands.is_empty():
			continue
		var i: int = cands[rng.randi() % cands.size()]
		send(p, i % sim.w, i / sim.w)


# ---------------------------------------------------------------- interface

func tools(cat: String) -> Array:
	if cat == "industry":
		return [["@geologist", "Send geologist", "unit_worker_pick", "Click a mountain in or near your land: a geologist surveys up to 12 tiles around it and marks what lies beneath."]]
	return []


func use_tool(tool: String, t: Vector2i) -> String:
	if tool != "@geologist":
		return "?"
	var r := send(sim.human(), t.x, t.y)
	return r if r != "" else "A geologist sets out with his pickaxe."


func panel_lines(p: Sim.Player) -> PackedStringArray:
	var n := 0
	var k: PackedByteArray = known.get(p.id, PackedByteArray())
	for i in sim.owned(p.id)[1]:
		if k.size() > i and k[i] == 0:
			n += 1
	return PackedStringArray(["Geologists  %d of %d out; %d of your mountain tiles unsurveyed" % [_out(p), _max_out(p), n]])


func tile_lines(i: int) -> PackedStringArray:
	if sim.ter[i] != Sim.MOUNT:
		return PackedStringArray()
	if not known_at(sim.human().id, i):
		return PackedStringArray(["[color=#c8b070]Not surveyed: send a geologist (Industry tab) to find out what lies beneath.[/color]"])
	if sim.ore[i] == 0 or sim.vein_left(i) == 0:
		return PackedStringArray(["Surveyed: nothing worth mining here."])
	return PackedStringArray()


func _vein_size(i: int) -> float:
	var v := sim.vein[i]
	if v <= 0:
		return 0.5
	var per := float(sim.vein_left(i)) / maxf(1.0, (sim.vein_tiles[v] as PackedInt32Array).size())
	return 0.35 if per < 15.0 else (0.5 if per < 35.0 else 0.7)


## Markers: a pole with a pennant in the ore's colour (bigger for richer veins), an empty pole for
## nothing. While a mine is being placed, every surveyed tile of its ore lights up.
func draw_map(view: CanvasItem, rect: Rect2i) -> void:
	var mv = view
	var w := sim.w
	var me := sim.human().id
	var placing := String(mv.place_type)
	var want := int(GameData.bld.get(placing, {}).get("mine", 0))
	if want > 0:
		var k: PackedByteArray = known.get(me, PackedByteArray())
		for y in range(maxi(0, rect.position.y), mini(sim.h, rect.end.y + 1)):
			for x in range(maxi(0, rect.position.x), mini(w, rect.end.x + 1)):
				var i := y * w + x
				if k.size() > i and k[i] == 1 and int(sim.ore[i]) == want and sim.vein_left(i) > 0:
					var ly := float(mv.lift_at(x + 0.5, y + 0.5))
					view.draw_rect(Rect2(x + 0.08, y + 0.08 - ly, 0.84, 0.84), Color(ORE_COL[want], 0.35))
					view.draw_rect(Rect2(x + 0.08, y + 0.08 - ly, 0.84, 0.84), Color(1, 1, 0.7, 0.8), false, 0.05)
	for m in marks:
		var i: int = m[0]
		var x := i % w
		var y := i / w
		if x < rect.position.x - 1 or y < rect.position.y - 1 or x > rect.end.x + 1 or y > rect.end.y + 1:
			continue
		var a := clampf((FADE - (sim.time - float(m[1]))) / 60.0, 0.0, 1.0)
		var base := Vector2(x + 0.5, y + 0.85 - float(mv.lift_at(x + 0.5, y + 0.85)))
		view.draw_line(base, base + Vector2(0, -0.6), Color(0.35, 0.25, 0.15, a), 0.05)
		var o := int(sim.ore[i]) if sim.vein_left(i) > 0 else 0
		if o != 0:
			var s := _vein_size(i)
			view.draw_colored_polygon(PackedVector2Array([base + Vector2(0.02, -0.6), base + Vector2(0.02 + s * 0.6, -0.6 + s * 0.2), base + Vector2(0.02, -0.6 + s * 0.4)]), Color(ORE_COL[o], a))
		else:
			view.draw_circle(base + Vector2(0, -0.62), 0.05, Color(0.85, 0.85, 0.85, a))


func draw_top(view: CanvasItem, _rect: Rect2i) -> void:
	var mv = view
	var fog = sim.get_feature("fog")
	for t in trips:
		var at := trip_pos(t)
		var mine := int(t[0]) == sim.human().id
		if not mine and fog != null and not fog.visible_at(sim.idx(roundi(at.x), roundi(at.y))):
			continue
		var surveying := sim.time >= float(t[3]) and sim.time < float(t[5])
		var f := (4 + int(sim.time * 3.0) % 2) if surveying else int(sim.time * 5.0) % 4
		mv._sprite("unit_worker_pick", at + Vector2(0.5, 0.85 - float(mv.lift_at(at.x + 0.5, at.y + 0.85))), 0.42, f, false, sim.players[int(t[0]) - 1].color.lightened(0.35))


func save_state() -> Dictionary:
	return {"known": known, "marks": marks, "trips": trips, "rng": rng.state, "seed": rng.seed, "ai_t": _ai_t}


func load_state(d: Dictionary) -> void:
	known = {}
	for k in d.get("known", {}):
		known[int(k)] = d.known[k]
	marks = d.get("marks", [])
	trips = d.get("trips", [])
	_ai_t = {}
	for k in d.get("ai_t", {}):
		_ai_t[int(k)] = float(d.ai_t[k])
	rng.seed = int(d.get("seed", 0))
	rng.state = int(d.get("rng", 0))
