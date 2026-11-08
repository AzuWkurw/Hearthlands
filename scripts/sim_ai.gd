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
	var dist := Vector2(x - p.hq.x, y - p.hq.y).length()
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
	return -dist


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


func _ai_sites(p: Sim.Player, ty: String) -> Array:
	var d: Dictionary = GameData.bld[ty]
	var lists := sim.owned(p.id)
	var cands := PackedInt32Array()
	if d.has("mine"):
		for i in lists[1]:
			if sim.can_place(ty, i % sim.w, i / sim.w, p.id) == "":
				cands.append(i)
	else:
		# spots are drawn from the free, buildable tiles only, so the search rarely comes back empty
		var list := _free_tiles(p, lists[0])
		if list.is_empty():
			return []
		if list.size() <= 300:
			for i in list:
				if sim.can_place(ty, i % sim.w, i / sim.w, p.id) == "":
					cands.append(i)
		else:
			for k in 300:
				var i := list[sim.rng.randi() % list.size()]
				if sim.can_place(ty, i % sim.w, i / sim.w, p.id) == "":
					cands.append(i)
	var scored := []
	for i in cands:
		scored.append([_site_score(ty, i % sim.w, i / sim.w, p) + _pack_score(ty, i % sim.w, i / sim.w, p) + sim.rng.randf() * 0.8, i % sim.w, i / sim.w])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	return scored.slice(0, 6)


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
		if q.id != p.id and q.alive:
			var dd := Vector2(q.hq.x - p.hq.x, q.hq.y - p.hq.y).length()
			if dd < ed: ed = dd; enemy = q
	var r := int(d.radius)
	var out := []
	for k in 220:
		var i := list[sim.rng.randi() % list.size()]
		var x := i % sim.w
		var y := i / sim.w
		if sim.can_place(ty, x, y, p.id) != "":
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
	var sites := _ai_mil_sites(p, ty) if d.has("garrison") else _ai_sites(p, ty)
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
		["barracks", 2 if war else 1], ["weaponsmith", 2 if war else 1],
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
		["chandler", 1 if mins > 13 and c.call("apiary") > 0 and p.noble > 0 else 0],
		["sand_pit", 1 if mins > 16 and p.noble > 1 else 0], ["glassworks", 1 if c.call("sand_pit") > 0 else 0],
	]
	# features add their own buildings after the basic economy (food, water, first huts)
	var extra := []
	for f: Feature in sim.features:
		extra.append_array(f.ai_steps(p, c))
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
	for st in steps:
		if made >= p.max_b:
			break
		var t := String(st[0])
		if c.call(t) >= int(st[1]):
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
	# full: not even a small building fits, or no military building finds new land to claim
	if no_room.has("small") or no_border:
		if not p.crowded:
			p.crowded_t = sim.time
		p.crowded = true
	elif nosite == 0:
		p.crowded = false
		p.crowded_t = 0.0


## Military buildings of realm p still waiting for their first soldier.
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
		return false
	for s in best[0]:
		sim.launch_attack(s, best[1])
	return true
