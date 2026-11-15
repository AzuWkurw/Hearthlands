class_name SimAI
extends RefCounted
## How rival realms think: what to build and where, when to attack, what to research.
## Part of the simulation: sim.gd holds the shared state and calls in here; the functions reach
## the rest of the game through `sim`.

var sim: Sim
var stats := {}     # for tests: how often each kind of building found no spot ("nosite:<type>")
var _free_pid := -1                     # realm whose free tiles _free holds (only during its ai_think)
var _free := PackedInt32Array()



func _init(p_sim: Sim) -> void:
	sim = p_sim


func _site_score(ty: String, x: int, y: int, p: Sim.Player) -> float:
	var d: Dictionary = GameData.bld[ty]
	var dist := Vector2(x - p.hq.x, y - p.hq.y).length() if p.hq != null else 0.0
	if d.has("mine"):
		return sim.count_near(x, y, 2, "ore", int(d.mine))
	match String(d.get("act", "")):
		"cut_tree": return sim.count_near(x, y, 5, "tree") - dist * 0.05
		"cut_rock": return sim.count_near(x, y, 4, "rock") - dist * 0.05
		"fish": return sim.count_near(x, y, 3, "fish") - dist * 0.05
		"dig_clay": return sim.count_near(x, y, 4, "clay") - dist * 0.05
		"plant":
			var bd := 30.0
			for b in sim.blds:
				if b.p == p.id and b.ty == "woodcutter":
					bd = minf(bd, Vector2(b.x - x, b.y - y).length())
			return -bd - dist * 0.02
	var s := String(d.get("site", ""))
	if d.has("siege"):
		# a catapult goes where it can reach an enemy fort
		var nd := 1e9
		for t: Sim.Bld in sim.mil_list():
			if t.p != p.id and t.state == "ready" and Diplomacy.at_war(sim, p.id, t.p):
				nd = minf(nd, Vector2(t.x - x, t.y - y).length())
		return (20.0 - nd) if nd <= float(d.siege.range) - 1.0 else -nd
	if d.has("store"):
		var nearest := 999.0
		for b in sim.blds:
			if b.p == p.id and sim.is_store(b):
				nearest = minf(nearest, Vector2(b.x - x, b.y - y).length())
		return minf(nearest, 18.0) - absf(nearest - 14.0) * 0.5
	if s.begins_with("open"): return sim.count_near(x, y, 2, "open") - dist * 0.12
	if ty == "lodge":
		# among the workshops, away from the headquarters and other homes
		var work := 0
		var homes := 0
		for b: Sim.Bld in sim.realm_blds(p):
			var dd := Vector2(b.x - x, b.y - y).length()
			if dd <= 6.0:
				if b.def.has("cycle"): work += 1
				elif b.def.has("housing") or b.def.has("residence"): homes += 1
		return work * 0.6 - homes * 1.0 + minf(dist, 14.0) * 0.25
	if s.begins_with("forest"): return sim.count_near(x, y, 8, "tree") - dist * 0.05
	if ty == "tavern" or ty == "chapel" or ty == "market":
		# among the homes, and away from the other taverns (chapels), so they reach as many as they can;
		# next to the town's other centre buildings, so the homes round them form a quarter (build 60)
		var room := 0.0
		var same := 0
		var centre := 0
		for b: Sim.Bld in sim.realm_blds(p):
			var dd := Vector2(b.x - x, b.y - y).length()
			if dd <= 9.0:
				room += float(b.def.get("housing", 0))
				if b.ty == ty:
					same += 1
			if dd <= 6.0 and b.ty != ty and (b.ty == "tavern" or b.ty == "chapel" or b.ty == "market"):
				centre += 1
		return room * 0.6 - same * 8.0 + centre * 5.0 - dist * 0.05
	if GameData.bld[ty].has("housing"):
		# homes in a ring round the town centre (its tavern, chapel and market), not on top of it
		var c := _town_centre(p)
		if c.x >= 0.0:
			return -absf(Vector2(x, y).distance_to(c) - 5.0) - dist * 0.03
		return -dist
	if ty == "river_landing":
		return _landing_score(x, y, p)
	return -dist


## Whether realm p's land has water inside it, away from the coast's open sea: a river or lake for boats.
## Worked out every few minutes.
func _river_land(p: Sim.Player) -> bool:
	if sim.time < p.river_t:
		return p.river
	var n := 0
	var tiles: PackedInt32Array = sim.owned(p.id)[0]
	for k in range(0, tiles.size(), 7):
		if sim.ter[tiles[k]] == Sim.WATER:
			n += 1
	var yes := n >= 6
	p.river_t = sim.time + 300.0
	p.river = yes
	return yes


## Where realm p's town centre is: the middle of its taverns, chapels and markets (any state), or
## (-1, -1) when it has none yet.
func _town_centre(p: Sim.Player) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for b: Sim.Bld in sim.realm_blds(p):
		if not b.dead and (b.ty == "tavern" or b.ty == "chapel" or b.ty == "market"):
			sum += Vector2(b.x, b.y)
			n += 1
	return sum / n if n > 0 else Vector2(-1, -1)


## A river landing: the first near home; the second far from it on the same water, so the boat saves
## a long walk (build 60).
func _landing_score(x: int, y: int, p: Sim.Player) -> float:
	var first: Sim.Bld = null
	for b: Sim.Bld in sim.realm_blds(p):
		if b.ty == "river_landing" and not b.dead:
			first = b
			break
	if first == null:
		return -Vector2(x - p.hq.x, y - p.hq.y).length() if p.hq != null else 0.0
	var d := Vector2(x - first.x, y - first.y).length()
	if d < 12.0 or sim.sea.water_path(first.x, first.y, x, y).is_empty():
		return -1000.0
	return minf(d, 30.0)


## How well a spot uses the land, now that buildings need room (Sim.PLOTS): a small building on a spot
## that would take a large one wastes it; a spot close to a road needs only a short new road, which
## cuts up less open land; and buildings packed next to others leave bigger free areas elsewhere.
func _pack_score(ty: String, x: int, y: int, p: Sim.Player) -> float:
	var need := sim.size_of(ty)
	var score := 0.0
	if need != "mine":
		var have := sim.site_size(x, y, p.id)
		if need == "small":
			score -= 0.7 if have == "medium" else (1.8 if have == "large" else 0.0)
		elif need == "medium" and have == "large":
			score -= 1.2
	var rd := 9
	var nb := 0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var nx := x + dx
			var ny := y + dy
			if nx < 0 or ny < 0 or nx >= sim.w or ny >= sim.h:
				continue
			var j := ny * sim.w + nx
			if sim.road[j] == p.id:
				rd = mini(rd, absi(dx) + absi(dy))
			if absi(dx) <= 2 and absi(dy) <= 2 and sim.plot[j] != 0:
				nb += 1
	# far from any road the new road may find no way through (rocks, water, other plots), and is long
	score += (3.0 - rd) * 0.6 if rd <= 3 else -6.0
	return score + nb * 0.08


## Spots looked at for a new building (each costs a full can_place), and how many good ones are enough
## to pick from.
const SITE_TRIES := 300
const SITE_CANDS := 40
const MIL_TRIES := 220
## Spots that had no room for a building of some size are skipped for this long (game seconds): the
## rivals test thousands of spots a minute, and most of the free tiles in a grown town are scraps
## between plots. Land that opens up meanwhile (a building pulled down) is found again after it.
const BAD_KEEP := 30.0


## The tiles of realm p known to have no room for a building of this size (see BAD_KEEP).
func _bad_of(p: Sim.Player, size: String) -> Dictionary:
	if sim.time - p.site_bad_t >= BAD_KEEP or sim.time < p.site_bad_t:
		p.site_bad = {}
		p.site_bad_t = sim.time
	if not p.site_bad.has(size):
		p.site_bad[size] = {}
	return p.site_bad[size]


## Whether can_place failed for want of room (the plot, its entrance, a way in), which holds for
## every building of that size, rather than for something about the building type.
static func _no_room(why: String) -> bool:
	return why == "x" or why.begins_with("No road can") or why.ends_with("of the plot") or why.begins_with("Too close to the edge")


## can_place for the rivals: remembers spots with no room, and skips them while they are remembered.
func _try_spot(p: Sim.Player, ty: String, i: int, bad: Dictionary) -> bool:
	var why := sim.can_place(ty, i % sim.w, i / sim.w, p.id)
	if why == "":
		return true
	if _no_room(why):
		bad[i] = true
	return false


func _ai_sites(p: Sim.Player, ty: String) -> Array:
	var d: Dictionary = GameData.bld[ty]
	var lists := sim.owned(p.id)
	var cands := PackedInt32Array()
	var bad := _bad_of(p, sim.size_of(ty))
	if d.has("mine"):
		for i in lists[1]:
			if not bad.has(i) and _try_spot(p, ty, i, bad):
				cands.append(i)
	else:
		# spots are drawn from the free, buildable tiles only, so the search rarely comes back empty
		var list := _free_tiles(p, lists[0])
		if list.is_empty():
			return []
		if list.size() <= SITE_TRIES:
			for i in list:
				if not bad.has(i) and _try_spot(p, ty, i, bad):
					cands.append(i)
		else:
			# SITE_TRIES real tries; spots known to have no room don't count (up to a limit of draws)
			var tries := 0
			var draws := 0
			while tries < SITE_TRIES and draws < SITE_TRIES * 4 and cands.size() < SITE_CANDS:
				draws += 1
				var i := list[sim.rng.randi() % list.size()]
				if bad.has(i):
					continue
				tries += 1
				if _try_spot(p, ty, i, bad):
					cands.append(i)
	var scored := []
	var large := sim.size_of(ty) == "large"
	var kin := _kin(p, ty)
	for i in cands:
		var x := i % sim.w
		var y := i / sim.w
		var sc := _site_score(ty, x, y, p) + _pack_score(ty, x, y, p) + _kin_score(kin, x, y) + sim.rng.randf() * 0.8
		# spots kept for large buildings: only large ones go there, and they like them
		var near_res := _near_reserved(p, x, y)
		if near_res == 0 and large:
			sc += 3.0
		elif near_res >= 0 and not large:
			continue
		scored.append([sc, x, y])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	return scored.slice(0, 6)


## The town plan (A2): a rival keeps a few large spots free early on, so a town full of houses still
## has room for farms and the like later. Spots that can no longer take a large building are dropped.
func _plan_town(p: Sim.Player) -> void:
	var kept := PackedInt32Array()
	for i in p.reserved:
		if sim.owner[i] == p.id and sim.bmap[i] == 0 and sim.site_size(i % sim.w, i / sim.w, p.id) == "large":
			kept.append(i)
	p.reserved = kept
	var want := 2 if sim.time < 20 * 60.0 else 1
	if p.reserved.size() >= want:
		return
	var list := _free_tiles(p, sim.owned(p.id)[0])
	if list.is_empty():
		return
	var best := -1
	var best_sc := -1e9
	for k in mini(120, list.size()):
		var i := list[sim.rng.randi() % list.size()]
		var x := i % sim.w
		var y := i / sim.w
		if sim.site_size(x, y, p.id) != "large" or _near_reserved(p, x, y, 6) >= 0:
			continue
		# open land not too far from the headquarters, near a road
		var d := Vector2(x - p.hq.x, y - p.hq.y).length() if p.hq != null else 9.0
		var sc := sim.count_near(x, y, 2, "open") - absf(d - 9.0) * 0.3 + _pack_score("farm", x, y, p)
		if sc > best_sc:
			best_sc = sc; best = i
	if best >= 0:
		p.reserved.append(best)


## How far (x, y) is from the nearest reserved spot if within r tiles (0: on it), or -1.
func _near_reserved(p: Sim.Player, x: int, y: int, r := 2) -> int:
	var out := -1
	for i in p.reserved:
		var d := maxi(absi(i % sim.w - x), absi(i / sim.w - y))
		if d <= r and (out < 0 or d < out):
			out = d
	return out


## The realm's buildings that trade goods with a building of type ty: those making what it uses, and
## those using what it makes. Grouping them shortens the carriers' walks.
func _kin(p: Sim.Player, ty: String) -> Array:
	var d: Dictionary = GameData.bld[ty]
	var ins: Dictionary = d.get("in", {})
	var outs: Dictionary = d.get("out", {})
	var out := []
	if ins.is_empty() and outs.is_empty():
		return out
	for b: Sim.Bld in sim.realm_blds(p):
		var bi: Dictionary = b.def.get("in", {})
		var bo: Dictionary = Crops.out_of(sim, b)
		var related := false
		for k in ins:
			if bo.has(k) or (k == "food" and b.def.get("cat", "") == "food" and not bo.is_empty()):
				related = true
		for k in outs:
			if bi.has(k):
				related = true
		if related:
			out.append(b)
	return out


func _kin_score(kin: Array, x: int, y: int) -> float:
	var sc := 0.0
	for b: Sim.Bld in kin:
		var d := absi(b.x - x) + absi(b.y - y)
		if d <= 8:
			sc += 0.5 * (1.0 - d / 10.0)
	return minf(sc, 2.0)


## Realm p's land tiles with nothing on them (no building, plot, road, tree or rock), worked out once
## per think; a building placed during the think takes its tiles out again by failing can_place.
func _free_tiles(p: Sim.Player, land: PackedInt32Array) -> PackedInt32Array:
	if _free_pid == p.id:
		return _free
	_free_pid = p.id
	_free = PackedInt32Array()
	for i in land:
		if sim.bmap[i] == 0 and sim.plot[i] == 0 and sim.road[i] == 0 and sim.deco[i] == 0 and sim.ter[i] != Sim.WATER:
			_free.append(i)
	return _free


func _ai_mil_sites(p: Sim.Player, ty: String) -> Array:
	var d: Dictionary = GameData.bld[ty]
	var list: PackedInt32Array = sim.owned(p.id)[0]
	var mtn: PackedInt32Array = sim.owned(p.id)[1]
	if list.is_empty():
		return []
	var have := {}
	for i in mtn:
		have[sim.ore[i]] = true
	var need_ore := have.size() < 4
	var enemy: Sim.Player = null
	var ed := 1e9
	for q in sim.players:
		if q.id != p.id and q.alive and q.hq != null and p.hq != null:
			var dd := Vector2(q.hq.x - p.hq.x, q.hq.y - p.hq.y).length()
			if dd < ed: ed = dd; enemy = q
	var r := int(d.radius)
	var out := []
	var bad := _bad_of(p, sim.size_of(ty))
	var tries := 0
	var draws := 0
	while tries < MIL_TRIES and draws < MIL_TRIES * 4:
		draws += 1
		var i := list[sim.rng.randi() % list.size()]
		if bad.has(i):
			continue
		tries += 1
		var x := i % sim.w
		var y := i / sim.w
		if _near_reserved(p, x, y) >= 0 or not _try_spot(p, ty, i, bad):
			continue
		var gain := 0.0
		for yy in range(maxi(0, y - r), mini(sim.h - 1, y + r) + 1):
			for xx in range(maxi(0, x - r), mini(sim.w - 1, x + r) + 1):
				var j := yy * sim.w + xx
				if (xx - x) * (xx - x) + (yy - y) * (yy - y) > r * r: continue
				if sim.owner[j] == 0 and sim.ter[j] != Sim.WATER:
					gain += 2.5 if (need_ore and sim.ter[j] == Sim.MOUNT and sim.ore[j] != 0 and not have.has(sim.ore[j])) else 1.0
		var sc := gain
		if enemy != null and p.pers == "warlord":
			sc -= Vector2(enemy.hq.x - x, enemy.hq.y - y).length() * 0.15
		if gain >= 10.0:
			out.append([sc, x, y])
	out.sort_custom(func(a, b): return a[0] > b[0])
	return out.slice(0, 4)


## Returns "ok", "poor" (wait for planks/stone), "skip" or "nosite".
func _ai_build(p: Sim.Player, ty: String) -> String:
	if not GameData.bld.has(ty):
		return "skip"
	var d: Dictionary = GameData.bld[ty]
	# materials already promised to its own construction sites don't count as available
	var promised := sim.committed(p)
	var miss := ""
	var cost: Dictionary = d.get("cost", {})
	for k in cost:
		if float(p.stock.get(k, 0.0)) - int(promised.get(k, 0)) < float(cost[k]):
			miss = k
			break
	if miss != "":
		return "poor" if miss in Sim.BASIC else "skip"
	if d.get("needs_noble", false) and p.noble < 1:
		return "skip"
	if d.has("tech") and not p.techs.has(d.tech):
		return "skip"
	var sites := _ai_mil_sites(p, ty) if d.has("garrison") or d.get("claim_only", false) else _ai_sites(p, ty)
	if sites.is_empty():
		stats["no candidates"] = int(stats.get("no candidates", 0)) + 1
	for s in sites:
		var why := sim.place(ty, s[1], s[2], p)
		if why == "":
			return "ok"
		stats["place: " + why] = int(stats.get("place: " + why, 0)) + 1
	stats["nosite:" + ty] = int(stats.get("nosite:" + ty, 0)) + 1
	stats["nosite_" + String(sim.size_of(ty))] = int(stats.get("nosite_" + String(sim.size_of(ty)), 0)) + 1
	return "nosite"


func ai_think(p: Sim.Player) -> void:
	_free_pid = -1
	_plan_town(p)
	_ai_priorities(p)
	var isl := sim.naval.island(p)
	if p.crowded or isl:
		sim.sea.ai_expedition(p)
	var cnt := {}
	var building := 0
	var unocc := 0
	for b in sim.blds:
		if b.p != p.id:
			continue
		cnt[b.ty] = int(cnt.get(b.ty, 0)) + 1
		if b.state == "build":
			building += 1
		elif b.def.has("mine") and b.msg == "Deposit exhausted":
			sim.destroy(b)
			return
		elif b.state == "ready" and (b.ty == "weaponsmith" or b.ty == "barracks" or b.ty == "toolsmith"):
			# short of soldiers (or out of room, so land must be taken): weapons and soldiers come first;
			# the toolsmith (who takes iron too) waits unless a new worker is waiting for a tool
			var short := p.crowded or p.reserve < 2
			var want := Sim.PRIO_HIGH if short else Sim.PRIO_NORMAL
			if b.ty == "toolsmith":
				want = Sim.PRIO_LOW if short and p.tool_wait.is_empty() and float(p.stock.get("weapons", 0.0)) < 2.0 else Sim.PRIO_NORMAL
			if b.prio != want and b.prio != Sim.PRIO_PAUSED:
				b.prio = want
		if b.state != "ready":
			continue
		if b.ty == "farm":
			_ai_crop(p, b)
		if b.fails >= 12 and _used_up(b):
			# its trees, rocks, fish or game have long been gone: pull it down (some of its cost comes back)
			# so that a new one goes up where there still are some
			sim.demolish(b)
			return
		elif b.def.has("garrison") and b.garrison == 0:
			unocc += 1
	if building >= maxi(2, p.peasant / 4):
		return
	var S := p.stock
	var pop := sim.pop_total(p)
	var mins := sim.time / 60.0
	var cap := 20 + int(cnt.get("house", 0)) * 8 + int(cnt.get("apartments", 0)) * 20
	var food := sim.food_total(p)
	var ex := 1.3 if p.pers == "builder" else (0.9 if p.pers == "warlord" else 1.0)
	var war := p.pers == "warlord"
	var need_house := pop + 5 >= cap
	var c := func(t: String) -> int: return int(cnt.get(t, 0))
	var houses: int = c.call("house")
	var farms: int = c.call("farm")
	var steps := [
		["woodcutter", mini(6, 2 + (1 if S.planks < 8 else 0) + pop / 28)],
		["sawmill", 1 + c.call("woodcutter") / 3],
		["quarry", 1 + pop / 40],
		["house", houses + 1 if need_house and (houses < 4 or S.bricks < 3) and houses < 14 else 0],
		["apartments", c.call("apartments") + 1 if need_house and houses >= 4 and S.bricks >= 3 else 0],
		["forester", (c.call("woodcutter") * 2 + 2) / 3],
		# food grows with the people: more mouths, more fishers, hunters and farms
		["fisher", mini(4, 1 + pop / 60) + (1 if food < pop * 0.3 + 6 and pop > 16 else 0)],
		["hunter", mini(3, 1 + pop / 80) + (1 if food < pop * 0.3 + 6 and pop > 24 else 0)],
		["farm", mini(6, 1 + pop / 35) + (1 if food < pop * 0.3 + 10 else 0)],
		["mill", ceili(farms * 0.9)], ["bakery", ceili(farms * 0.8)], ["well", maxi(1, ceili(c.call("bakery") / 1.5))],
		["hut", 0 if unocc > 0 or p.reserve < 1 else mini(12, roundi(2 + mins * 0.5 * ex))],
		["coal_mine", mini(4, 2 + int(mins / 10.0))], ["iron_mine", mini(3, 1 + int(mins / 12.0))], ["iron_smelter", 1], ["toolsmith", 1], ["school", mini(2, 1 + pop / 100)], ["weaponsmith", 1], ["barracks", 1],
		["clay_pit", 1 if mins > 4 else 0], ["brickworks", 1 if mins > 4 and c.call("clay_pit") > 0 else 0],
		["orchard", mini(3, (1 if mins > 5 else 0) + pop / 70)],
		["charcoal_burner", 1 if mins > 6 and S.coal < 4 and S.wood > 20 else 0],
		["tower", 0 if unocc > 0 or p.reserve < 2 else mini(10, int(mins * 0.3 * ex))],
		["palisade", 0 if unocc > 0 or p.reserve < 1 or mins > 12 else mini(3, 1 + int(mins * 0.3 * ex))],
		["guardhouse", 0 if unocc > 0 or p.reserve < 2 else mini(6, int(mins * 0.2 * ex))],
		["keep", 0 if unocc > 0 or p.reserve < 4 or mins < 12 else mini(4, int(mins * 0.1 * ex))],
		["hunter", 1], ["tannery", 1 if mins > 8 and S.hides > 2 else 0],
		["armorer", 1 if mins > 9 and (war or p.pers == "balanced") else 0],
		["saltworks", 1 if mins > 8 else 0], ["smokehouse", 1 if mins > 8 and c.call("saltworks") > 0 and c.call("fisher") > 0 else 0],
		["hop_farm", 1 if mins > 8 else 0], ["brewery", 1 if mins > 8 and c.call("hop_farm") > 0 else 0],
		["pig_farm", 1 if mins > 9 and pop > 40 else 0],
		["gold_mine", 1 if mins > 6 else 0], ["mint", 1 if mins > 6 else 0],
		["copper_mine", 1 if mins > 9 else 0], ["copper_smelter", 1 if mins > 9 and c.call("copper_mine") > 0 else 0],
		["barracks", 2 if war else 1], ["weaponsmith", 2 if war else 1], ["bowyer", 1 if war and mins > 15 else 0],
		["coal_mine", 3 if mins > 10 else 2], ["iron_mine", 2 if mins > 10 else 1], ["iron_smelter", 2 if mins > 10 else 1],
		["sheep_farm", 1 if mins > 11 and not war else 0], ["weaver", 1 if c.call("sheep_farm") > 0 else 0], ["tailor", 1 if c.call("weaver") > 0 else 0],
		["carpenter", 1 if mins > 12 else 0], ["jeweller", 1 if mins > 14 and S.gold > 5 and c.call("copper_smelter") > 0 else 0],
		["manor", 1 if mins > 14 and S.gold >= 5 and S.bricks >= 4 else 0],
		["castle", c.call("castle") + 1 if mins > 16 and p.noble > 0 and unocc == 0 and p.reserve > 3 else 0],
		["school", 2 if mins > 10 else 1], ["farm", mini(8, 2 + pop / 45 + (2 if food < pop * 0.3 + 10 else 0))], ["fisher", 3 if food < pop * 0.3 else 2], ["orchard", 2 if food < pop * 0.3 else 1], ["woodcutter", mini(8, 3 + pop / 25)],
		# research grows with the realm (warlords keep less of it): more scribes, more libraries
		["scriptorium", (mini(2 if war else 4, 1 + pop / 45) if mins > 3 else 0)], ["library", mini(2 if war else 3, 1 + pop / 90)], ["paper_mill", 1 + pop / 150], ["university", 1 if S.beer > 2 else 0],
		["fortress", c.call("fortress") + 1 if mins > 25 and unocc == 0 and p.reserve > 6 else 0],
		["battery", c.call("battery") + 1 if war and unocc == 0 and p.reserve > 4 and c.call("battery") < 4 else 0],
		# a market once it is at peace with someone, to trade
		["market", 1 if mins > 12 and _at_peace(p) else 0],
		["donkey_farm", 1 if mins > 10 and bool(sim.opts.get("road_carriers", false)) else 0],
		# crowded realms by the sea look for land across the water
		# rivals on an island of their own take to the sea early: harbour, ships, landings
		["harbour", 1 if (mins > 18 and p.crowded) or (mins > 8 and p.island) else 0], ["shipyard", (2 if p.island and mins > 20 else 1) if c.call("harbour") > 0 else 0],
		["catapult", mini(3, _siege_targets(p)) if mins > 14 and S.stone > 12 and p.techs.has("stone_masonry") else 0],
		["bastion", c.call("bastion") + 1 if mins > 28 and unocc == 0 and p.reserve > 8 and c.call("bastion") < 3 else 0],
		["redoubt", c.call("redoubt") + 1 if mins > 35 and unocc == 0 and p.reserve > 12 and c.call("redoubt") < 3 else 0],
		["storehouse", maxi((1 if mins > 8 else 0) + (1 if mins > 18 else 0), mini(5, c.call("storehouse") + (1 if _ai_needs_store(p) else 0)))],
		["lodge", (1 if mins > 12 else 0) + (1 if mins > 24 else 0)],
		["mule_station", 1 if mins > 5 else 0], ["mule_station", 2 if mins > 15 else 0], ["cart_yard", 1], ["warehouse", 1 if mins > 20 else 0], ["depot", 1],
		["toolsmith", 2 if mins > 12 else 1], ["toolsmith", 3 if mins > 25 and pop > 150 else 0],
		["steelworks", 1], ["machine_works", 1], ["textile_mill", 1 if c.call("sheep_farm") > 0 else 0],
		["apiary", 1 if mins > 7 else 0], ["butcher", 1 if mins > 9 and c.call("saltworks") > 0 and c.call("hunter") + c.call("pig_farm") > 1 else 0],
		["dairy", 1 if mins > 10 and pop > 40 else 0], ["cheesery", 1 if c.call("dairy") > 0 and c.call("saltworks") > 0 else 0],
		["vineyard", 1 if mins > 13 and p.noble > 0 else 0], ["winery", 1 if c.call("vineyard") > 0 else 0],
		["chandler", 1 if mins > 13 and c.call("apiary") > 0 and (p.noble > 0 or (c.call("tavern") > 0 and mins > 25)) else 0],
		["sand_pit", 1 if mins > 16 and p.noble > 1 else 0], ["glassworks", 1 if c.call("sand_pit") > 0 else 0],
		# luxuries for the nobles' taxes
		["mulberry_grove", 1 if mins > 16 and p.noble > 0 else 0], ["silk_weaver", 1 if c.call("mulberry_grove") > 0 else 0],
		["pepper_garden", 1 if mins > 20 and p.noble > 0 else 0], ["spice_mill", 1 if c.call("pepper_garden") > 0 and c.call("saltworks") > 0 else 0],
		["kaolin_pit", 1 if mins > 26 and p.noble > 1 else 0], ["porcelain_kiln", 1 if c.call("kaolin_pit") > 0 else 0],
		["coffee_plantation", 1 if mins > 26 and p.noble > 1 else 0], ["coffee_roaster", 1 if c.call("coffee_plantation") > 0 else 0],
		# a wonder once the goods for it are in store (builders and the learned want them most)
		["great_hall", 1 if mins > 14 and S.planks > 36 and S.stone > 30 and S.gold >= 8 and not war else 0],
		["cathedral", 1 if mins > 20 and S.stone > 56 and S.bricks > 20 and S.gold >= 14 else 0],
		["grand_academy", 1 if mins > 25 and S.bricks > 34 and S.paper > 18 and S.gold >= 18 else 0],
		["observatory", 1 if mins > 30 and S.bricks > 44 and S.glass > 18 and S.iron > 18 and S.gold >= 22 else 0],
		["exhibition_palace", 1 if mins > 35 and S.iron > 44 and S.glass > 32 and S.gold >= 26 else 0],
	]
	# features add their own buildings after the basic economy (food, water, first huts)
	var extra := []
	for f: Feature in sim.features:
		extra.append_array(f.ai_steps(p, c))
	# at war by the sea: warships and guns on the shore; warlords keep rations near the front; a rival
	# alone on its island makes for the sea. These few come early, once the basic economy stands.
	var war_by_sea: bool = c.call("harbour") > 0 and _at_war_any(p)
	# guns need powder: a rival with cannon forts, a coastal fort or a naval yard (or soon one) makes it
	var powder: bool = p.techs.has("gunpowder") and mins > 25 and (c.call("bastion") + c.call("battery") + c.call("redoubt") + c.call("coastal_fort") + c.call("naval_yard") > 0 or p.techs.has("drill_manuals"))
	# musketeers and riflemen need cartridges: lead and gunpowder
	var guns: bool = p.age >= 4 and p.techs.has("musketry") and p.techs.has("gunpowder")
	powder = powder or guns
	var have_sulfur := false
	var have_lead := false
	if powder:
		for i in (sim.owned(p.id)[1] as PackedInt32Array):
			if sim.ore[i] == 6 and sim.vein_left(i) > 0:
				have_sulfur = true
			elif sim.ore[i] == 7 and sim.vein_left(i) > 0:
				have_lead = true
	extra.append_array([
		# beer for the taverns, so the people are content and the realm holds festivals (build 53)
		["hop_farm", (2 if mins > 20 and c.call("tavern") > 0 else 1) if mins > 10 else 0],
		["brewery", (2 if mins > 20 and c.call("hop_farm") > 1 else 1) if mins > 10 and c.call("hop_farm") > 0 else 0],
		# a town centre: a market next to the tavern (and chapel), once the town has grown (build 60)
		["market", 1 if mins > 20 and c.call("tavern") > 0 and pop > 50 else 0],
		# river boats: two landings on the same water (build 60)
		["river_landing", 2 if mins > 25 and p.techs.has("timber_framing") and _river_land(p) else 0],
		["harbour", 1 if mins > 8 and p.island else 0],
		["shipyard", 1 if p.island and c.call("harbour") > 0 else 0],
		["naval_yard", 1 if mins > 40 and war_by_sea else 0],
		["coastal_fort", 1 if mins > 45 and war_by_sea else 0],
		["field_depot", 1 if mins > 30 and war else 0],
		# gunpowder for the cannon forts, coastal forts, naval yards and gunsmiths (build 57)
		["charcoal_burner", 1 if powder else 0],
		["saltpeter_works", (2 if c.call("powder_mill") > 0 else 1) if powder else 0],
		["sulfur_mine", 1 if powder and have_sulfur else 0],
		["powder_mill", 1 if powder and c.call("charcoal_burner") > 0 and c.call("saltpeter_works") > 0 and c.call("sulfur_mine") > 0 else 0],
		["gunsmith", 1 if c.call("powder_mill") > 0 and war and mins > 35 else 0],
		# cartridges once its soldiers carry guns (musketeers from the age of reason), lead for them
		["lead_mine", 1 if guns and have_lead else 0],
		["lead_smelter", 1 if guns and c.call("lead_mine") > 0 else 0],
		["cartridge_works", (2 if p.age >= 5 else 1) if guns and c.call("lead_smelter") > 0 and c.call("powder_mill") > 0 else 0],
		# fireworks for its festivals, once the powder chain stands and it has taverns
		["pyrotechnist", 1 if c.call("powder_mill") > 0 and c.call("tavern") > 0 and mins > 40 else 0],
	])
	if not extra.is_empty():
		var at := 13
		for e in extra:
			steps.insert(at, e)
			at += 1
	var made := 0
	# room was made for a key building: it goes up before anything else can take the spot
	if p.swap_key != "":
		var key0 := p.swap_key
		var rk := _ai_build(p, key0)
		if rk == "ok" or sim.time - p.swap_t > 90.0:
			p.swap_key = ""
		if rk == "ok":
			made += 1
			cnt[key0] = c.call(key0) + 1
		elif rk == "poor":
			return
	var nosite := 0
	var no_room := {}      # sizes that found no spot this time: others of that size will not either
	# every peasant at work and none idle: a new workshop's worker would come from the carriers, and a
	# realm without carriers starves with full stores. Only homes (more people), food and stores then.
	var no_hands := p.peasant - p.used_peasant <= 0 and p.store_porters <= 0
	for st in steps:
		if made >= p.max_b:
			break
		var t := String(st[0])
		if c.call(t) >= int(st[1]):
			continue
		if no_hands and t != "house" and t != "storehouse" and not SimLogistics.food_chain().has(t) \
				and not GameData.bld.get(t, {}).has("garrison"):
			continue
		if no_room.has(sim.size_of(t)) and not GameData.bld.get(t, {}).has("garrison"):
			continue
		var r := _ai_build(p, t)
		if r == "ok":
			made += 1
			cnt[t] = c.call(t) + 1
		elif r == "poor":
			break
		elif r == "nosite":
			# buildings need room (Sim.PLOTS): the land is full for this size
			nosite += 1
			no_room[sim.size_of(t)] = true
	# no room left for a medium building, yet a key one is missing (no barracks means no soldiers, so no
	# new land, so never room for one): pull down a house to make room, at most every 90 seconds
	if no_room.has("medium") and houses >= 3 and sim.time - p.swap_t > 90.0:
		var key := ""
		if c.call("barracks") == 0 and mins > 6: key = "barracks"
		elif c.call("school") == 0: key = "school"
		elif c.call("toolsmith") == 0: key = "toolsmith"
		elif c.call("iron_smelter") == 0 and c.call("iron_mine") > 0: key = "iron_smelter"
		elif c.call("storehouse") == 0 and mins > 12: key = "storehouse"
		if key != "":
			var old: Sim.Bld = null
			for b: Sim.Bld in sim.realm_blds(p):
				if b.ty == "house" and b.state == "ready" and not b.dead and (old == null or b.id > old.id):
					old = b
			if old != null:
				p.swap_t = sim.time
				p.swap_key = key
				sim.demolish(old)
				return
	# out of room and no soldier to spare: bring soldiers home from buildings deep inside the realm,
	# leaving one in each, so new military buildings at the border can be manned. A realm whose land
	# is full sends them to the front instead, to take land from its neighbours.
	if p.crowded:
		_man_the_front(p)
	elif nosite > 0 and p.reserve < 1:
		_free_inner_soldiers(p)
	# and keep two artisans out of the workshops so the barracks can train new soldiers (they need an
	# idle artisan each); once there are soldiers to spare, the workshops get them back
	if nosite > 0 and p.reserve < 2 and c.call("barracks") > 0:
		p.keep_artisans = 2
	elif p.reserve >= 3 or nosite == 0:
		p.keep_artisans = 0
	# out of room: push the border out with another military building, past the usual count
	var no_border := false
	if nosite > 0 and made < p.max_b and unocc == 0 and p.reserve >= 1 and _empty_mil(p) < 3:
		no_border = true
		for t in ["guardhouse", "hut", "palisade"]:
			var r2 := _ai_build(p, t)
			if r2 != "nosite" and r2 != "skip":
				no_border = false
			if r2 == "ok" or r2 == "poor":
				break
	# out of room with no soldier to spare: a boundary stone takes free land without one
	if nosite > 0 and made < p.max_b and p.reserve < 1 and int(cnt.get("boundary_stone", 0)) < 4 + int(mins / 4.0):
		var r3 := _ai_build(p, "boundary_stone")
		if r3 == "ok":
			no_border = false
	# full: not even a small building fits, or no military building finds new land to claim
	if no_room.has("small") or no_border:
		if not p.crowded:
			p.crowded_t = sim.time
		p.crowded = true
	elif nosite == 0:
		p.crowded = false
		p.crowded_t = 0.0


## Military buildings of realm p still waiting for their first soldier.
## What a rival's farm sows: mostly wheat, one in three food crops once it has the seed; winter rye
## while its crop is out of season (by hand, or the rotation once it knows the Three-field system).
func _ai_crop(p: Sim.Player, b: Sim.Bld) -> void:
	var base := "wheat"
	if b.id % 3 == 0:
		if Crops.known(sim, p, "potatoes"): base = "potatoes"
		elif Crops.known(sim, p, "vegetables"): base = "vegetables"
	var rye := Crops.known(sim, p, "rye")
	b.rotate = rye and p.techs.has(Crops.ROTATE_TECH)
	var s := Crops.season_now(sim)
	if not b.rotate and rye and not Crops.grows(base, s):
		b.crop = "rye"
	else:
		b.crop = base


func _empty_mil(p: Sim.Player) -> int:
	var n := 0
	for b: Sim.Bld in sim.realm_blds(p):
		if not b.dead and b.state == "ready" and b.def.has("garrison") and b.garrison == 0 and b.walking == 0:
			n += 1
	return n


## Whether gatherer b has nothing left to gather where it stands (and nobody to plant more).
func _used_up(b: Sim.Bld) -> bool:
	match b.ty:
		"quarry": return b.msg.begins_with("No stone left")
		"fisher": return b.msg.begins_with("No fish left")
		"hunter": return b.msg.begins_with("No game")
		"woodcutter":
			if not (b.msg.begins_with("No trees left") or b.msg.begins_with("Not enough forest")):
				return false
			for f: Sim.Bld in sim.realm_blds(sim.players[b.p - 1]):
				if f.ty == "forester" and not f.dead and Vector2(f.x - b.x, f.y - b.y).length() <= 7.0:
					return false
			return true
	return false


## A crowded realm's military buildings near another realm's (not an ally's) get a full garrison again,
## so soldiers from the reserve walk to the front and attacks can be launched from there.
func _man_the_front(p: Sim.Player) -> void:
	var foes: Array = []
	for b in sim.mil_list():
		if b.p != p.id and not b.dead and Diplomacy.relation(sim, p.id, b.p) != Diplomacy.ALLY:
			foes.append(b)
	for b: Sim.Bld in sim.realm_blds(p):
		if b.dead or b.state != "ready" or b.ty == "hq" or not b.def.has("garrison") or b.want_n < 0:
			continue
		for f: Sim.Bld in foes:
			if Vector2(f.x - b.x, f.y - b.y).length() <= Sim.RANGE + 2.0:
				b.want_n = -1
				break


## Military buildings of realm p with no other realm's land near them (their radius and 4 tiles more)
## keep only one soldier; the others go back to the reserve. Empty land is no threat.
func _free_inner_soldiers(p: Sim.Player) -> void:
	for b: Sim.Bld in sim.realm_blds(p):
		if b.dead or b.state != "ready" or b.ty == "hq" or not b.def.has("garrison") or b.garrison <= 1 or b.want_n == 1:
			continue
		var r := int(b.def.get("radius", 6)) + 4
		var inner := true
		for yy in range(b.y - r, b.y + r + 1, 2):
			for xx in range(b.x - r, b.x + r + 1, 2):
				if sim.inb(xx, yy):
					var o := int(sim.owner[sim.idx(xx, yy)])
					if o != 0 and o != p.id:
						inner = false
						break
			if not inner:
				break
		if inner:
			b.want_n = 1


## A rival wants another store when its goods are close to the limit, or its buildings are far from any store.
func _ai_needs_store(p: Sim.Player) -> bool:
	# goods are kept in each store now: a store close to the workshops shortens every carrier's walk,
	# and room runs out for several goods at once
	var nearly_full := 0
	for r in GameData.resources:
		var cap := sim.capacity(p, r.id)
		if cap > 0.0 and float(p.stock.get(r.id, 0.0)) >= cap * 0.85:
			nearly_full += 1
	if nearly_full >= 2:
		return true
	var far := 0
	for b: Sim.Bld in sim.realm_blds(p):
		if b.cyc > 0.0 and sim.net_dist(p.id, sim.idx(b.x, b.y)) > 14.0:
			far += 1
	return far >= 6


## Enemy forts (at war) close to realm p's military buildings: worth a catapult each, a few at most.
func _siege_targets(p: Sim.Player) -> int:
	var n := 0
	var mine: Array = []
	for b: Sim.Bld in sim.mil_list():
		if b.p == p.id and b.state == "ready":
			mine.append(b)
	for t: Sim.Bld in sim.mil_list():
		if t.p == p.id or t.state != "ready" or t.ty == "hq" or sim.own_def(t) < 3 or not Diplomacy.at_war(sim, p.id, t.p):
			continue
		for b: Sim.Bld in mine:
			if absi(b.x - t.x) + absi(b.y - t.y) <= 14:
				n += 1
				break
	return n


## What taking building `t` is worth besides the odds: the land it holds and the mines and workshops
## that would be lost with that land.
func _attack_value(t: Sim.Bld) -> float:
	var r := int(t.def.get("radius", 6))
	var v := 0.08 * (r - 6)
	var n := 0
	for b in sim.blds:
		if b.p == t.p and b.state == "ready" and not sim.is_mil(b) and absi(b.x - t.x) <= r and absi(b.y - t.y) <= r:
			n += 3 if b.def.get("size", "") == "mine" else 1
	return v + minf(1.0, n * 0.05)


func ai_attack(p: Sim.Player) -> bool:
	var srcs: Array[Sim.Bld] = []
	for b in sim.blds:
		if b.p == p.id and b.state == "ready" and sim.is_mil(b):
			srcs.append(b)
	var hq: Sim.Bld = null
	for b in sim.blds:
		if b.p == p.id and b.ty == "hq": hq = b; break
	var best = null
	var best_sc := -1e9
	for t in sim.blds:
		if t.p == p.id or t.state != "ready" or not sim.is_mil(t) or not sim.players[t.p - 1].alive:
			continue
		if not Diplomacy.at_war(sim, p.id, t.p):
			continue
		var near: Array[Sim.Bld] = []
		var total := 0
		for s in srcs:
			if Vector2(t.x - s.x, t.y - s.y).length() > Sim.RANGE:
				continue
			# buildings close to the headquarters keep one more man home to guard it
			var av := sim.own_def(s) - (2 if hq != null and absi(s.x - hq.x) + absi(s.y - hq.y) <= 8 else 1)
			if av >= 1:
				near.append(s); total += av
		if near.is_empty() or total < 3:
			continue
		var ratio := float(total) / maxf(1.0, sim.defenders(t))
		# a realm whose land is full takes worse odds: land is now only to be had by taking it
		if ratio < (maxf(1.05, p.odds * 0.75) if p.crowded else p.odds):
			continue
		var sc := ratio + (p.focus * 2.0 if t.p == 1 else 0.0) + (1.5 if t.ty == "hq" else 0.0) + _attack_value(t)
		if sc > best_sc:
			best_sc = sc; best = [near, t]
	if best == null:
		return _ai_landing(p)
	for s in best[0]:
		sim.launch_attack(s, best[1])
	return true


const AI_LANDING_FROM := 25 * 60.0

## No target by land: a rival with a harbour, a free ship and soldiers waiting lands on an enemy coast
## (it looks at most once a minute: finding the way by sea takes a while).
func _ai_landing(p: Sim.Player) -> bool:
	# not in the first 25 minutes: a landing from the sea must not end a game before anyone could
	# build a defence (a harbour start gives ships at once)
	if sim.time < AI_LANDING_FROM or sim.time - p.sea_try < 60.0 or p.reserve < 6 or sim.sea.free_ships(p) < 1:
		return false
	var hs := sim.sea.harbours(p)
	if hs.is_empty():
		return false
	p.sea_try = sim.time
	var n := mini(mini(p.reserve - 2, sim.sea.free_ships(p) * SimSea.LANDING_PER_SHIP), SimSea.LANDING_MAX)
	var cands := []
	for t: Sim.Bld in sim.mil_list():
		if t.p == p.id or t.state != "ready" or t.dead or not sim.players[t.p - 1].alive or not Diplomacy.at_war(sim, p.id, t.p):
			continue
		if float(n) / maxf(1.0, sim.defenders(t)) < p.odds:
			continue
		cands.append([float(n) / maxf(1.0, sim.defenders(t)) + _attack_value(t), t])
	cands.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and (a[1] as Sim.Bld).id < (b[1] as Sim.Bld).id))
	for c in cands.slice(0, 3):
		for h: Sim.Bld in hs.slice(0, 2):
			if sim.military.launch_landing(h, c[1], n) == "":
				return true
	return false


## A rival sets its priorities as a player would (build 54), once a minute: food first when its people
## go hungry, arms first at war when weapons run short, building materials first while many sites
## wait, and the usual numbers otherwise.
func _ai_priorities(p: Sim.Player) -> void:
	if sim.time - p.prio_t < 60.0:
		return
	p.prio_t = sim.time
	var want := ""
	var pop := sim.pop_total(p)
	var sites := 0
	for b: Sim.Bld in sim.realm_blds(p):
		if b.state == "build":
			sites += 1
	if p.starve > 0 or sim.food_total(p) < pop * 0.25 + 8.0:
		want = "Feed everyone"
	elif _at_war_any(p) and float(p.stock.get("weapons", 0.0)) < 4.0 and sim.time > 15 * 60.0:
		want = "War"
	elif sites >= 4 and float(p.stock.get("planks", 0.0)) < 12.0:
		want = "Build up"
	if want == p.prio_set:
		return
	p.prio_set = want
	if want == "":
		p.carry_rank = {}
		p.work_rank = {}
	else:
		PrioPresets.apply_named(p, want)
	sim.staffing(p)


func _at_war_any(p: Sim.Player) -> bool:
	for q in sim.players:
		if q.alive and q.id != p.id and Diplomacy.at_war(sim, p.id, q.id):
			return true
	return false


func _at_peace(p: Sim.Player) -> bool:
	for q in sim.players:
		if q.alive and q.id != p.id and not Diplomacy.at_war(sim, p.id, q.id):
			return true
	return false
