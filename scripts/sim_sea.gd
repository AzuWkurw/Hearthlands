class_name SimSea
extends RefCounted
## Ships and harbours. A shipyard on the coast builds ships (Player.ships). A harbour is a store on the
## coast that also holds a little land and a soldier, and people can wait there. From a harbour an
## expedition (a ship, 4 planks, 2 stone and a soldier) sails to another free coast and founds a new
## harbour there: a colony. Ships then carry goods between harbours that no road joins, from where
## there is plenty to where there is little. Ships are Trips of kind "ship" along a path over water;
## `aim` is the tile an expedition lands on.

var sim: Sim

const EXPEDITION := {"planks": 4, "stone": 2}
const SHIP_LOAD := 8
const SHIP_SPEED := 1.6      # tiles a second on open water
const MAX_SHIPS := 6


func _init(p_sim: Sim) -> void:
	sim = p_sim


func harbours(p: Sim.Player) -> Array:
	return sim.realm_blds(p).filter(func(b): return is_harbour(b) and b.state == "ready" and not b.dead)


## A harbour, or the headquarters of a realm that landed from the sea (it stands on the coast).
func is_harbour(b: Sim.Bld) -> bool:
	return b != null and (b.ty == "harbour" or (b.ty == "hq" and sim.players[b.p - 1].landed))


func free_ships(p: Sim.Player) -> int:
	return p.ships - p.ships_out


## Water tiles within two tiles of building b (where its ships moor).
func _moorings(x: int, y: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if sim.inb(x + dx, y + dy) and sim.ter[sim.idx(x + dx, y + dy)] == Sim.WATER:
				out.append(sim.idx(x + dx, y + dy))
	return out


## The way over water from near (ax, ay) to near (bx, by), or empty if the seas are not joined.
## Breadth-first over water tiles, eight directions, so ships cut corners like boats do.
func water_path(ax: int, ay: int, bx: int, by: int) -> PackedInt32Array:
	var starts := _moorings(ax, ay)
	var goals := _moorings(bx, by)
	if starts.is_empty() or goals.is_empty():
		return PackedInt32Array()
	var goal := {}
	for g in goals:
		goal[g] = true
	var came := {}
	var q := []
	for s in starts:
		came[s] = -1
		q.append(s)
	var head := 0
	var found := -1
	while head < q.size() and head < 60000:
		var cur: int = q[head]
		head += 1
		if goal.has(cur):
			found = cur
			break
		var cx := cur % sim.w
		var cy := cur / sim.w
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx := cx + dx
				var ny := cy + dy
				if not sim.inb(nx, ny):
					continue
				var ni := ny * sim.w + nx
				if came.has(ni) or sim.ter[ni] != Sim.WATER:
					continue
				came[ni] = cur
				q.append(ni)
	if found < 0:
		return PackedInt32Array()
	var path := PackedInt32Array()
	var c := found
	while c != -1:
		path.append(c)
		c = came[c]
	path.reverse()
	return path


func _sail_time(path: PackedInt32Array) -> float:
	var d := 0.0
	for k in range(1, path.size()):
		d += Vector2(path[k] % sim.w - path[k - 1] % sim.w, path[k] / sim.w - path[k - 1] / sim.w).length()
	return d / SHIP_SPEED


## Whether a colony's harbour could stand at (x, y): coast land nobody holds (or p holds), room for the
## plot, open water next to it.
func landing_ok(x: int, y: int, pid: int) -> String:
	if not sim.inb(x, y):
		return "Outside the map"
	var i := sim.idx(x, y)
	if sim.ter[i] != Sim.GRASS and sim.ter[i] != Sim.BEACH:
		return "Land on grass or beach by the water"
	for t in sim.plot_tiles("harbour", x, y):
		if sim.ter[t] == Sim.WATER or sim.ter[t] == Sim.MOUNT or sim.bmap[t] != 0 or sim.plot[t] != 0 or sim.road[t] != 0:
			return "No room for a harbour here"
		if sim.owner[t] != 0 and sim.owner[t] != pid:
			return "Another realm holds this coast"
	if sim.count_near(x, y, 2, "water") < 2:
		return "A harbour needs open water next to it"
	return ""


## Sends an expedition from harbour h to land at (x, y). "" when it set sail, else why not.
func expedition(p: Sim.Player, h: Sim.Bld, x: int, y: int) -> String:
	if h == null or h.dead or not is_harbour(h) or h.state != "ready":
		return "Expeditions leave from a harbour"
	if free_ships(p) < 1:
		return "No free ship: build a shipyard and let it build one"
	var why := landing_ok(x, y, p.id)
	if why != "":
		return why
	if sim.owner[sim.idx(x, y)] == p.id and sim.logistics.reach(p.id)[sim.idx(x, y)] == 1:
		return "That coast is yours already: build there by road"
	for k in EXPEDITION:
		if float(h.inv.get(k, 0.0)) < float(EXPEDITION[k]):
			return "The harbour needs %d planks and %d stone in store for an expedition" % [EXPEDITION.planks, EXPEDITION.stone]
	if p.reserve < 1:
		return "An expedition needs a soldier waiting at the headquarters"
	var path := water_path(h.x, h.y, x, y)
	if path.is_empty():
		return "No sea way from this harbour to that coast"
	for k in EXPEDITION:
		sim.logistics.store_add(h, p, k, -float(EXPEDITION[k]))
	p.reserve -= 1
	p.ships_out += 1
	var t := Sim.Trip.new()
	t.p = p.id; t.kind = "ship"; t.res = "@expedition"; t.n = 1; t.site = h.id; t.aim = sim.idx(x, y)
	t.path = path
	var st := _sail_time(path)
	t.t0 = sim.time; t.t1 = sim.time + st + 2.0; t.t2 = t.t1 + st
	sim.trips.append(t)
	if not p.ai:
		sim.emit_log("An expedition sets sail.", Color("8fc0ff"), Vector2i(x, y))
	return ""


## A ship reached its goal: an expedition founds its colony (or, if the coast was taken meanwhile,
## brings everything back); a cargo goes into the harbour's store.
func ship_arrival(t: Sim.Trip, p: Sim.Player) -> void:
	if t.res == "@expedition":
		var x := t.aim % sim.w
		var y := t.aim / sim.w
		if p.alive and landing_ok(x, y, p.id) == "":
			var b := sim.add_bld("harbour", x, y, p, true, -1)
			p.colonies += 1
			b.garrison = 1
			b.gmix = []          # (filled with a soldier of the realm's age, see mix_fix)
			for k in EXPEDITION:
				sim.logistics.store_add(b, p, k, float(EXPEDITION[k]))
			for tt in sim.plot_tiles("harbour", x, y):
				sim.deco[tt] = 0
			sim.recompute_territory()
			sim.net_dirty(p.id)
			sim._mil_dirty = true
			if not p.ai:
				sim.emit_log("The expedition founds a colony across the water.", Color("86ad5c"), Vector2i(x, y))
		else:
			# the coast was taken: the soldier and the goods go home
			p.reserve += 1
			var h: Sim.Bld = sim.by_id.get(t.site)
			for k in EXPEDITION:
				if h != null and not h.dead:
					sim.logistics.store_add(h, p, k, float(EXPEDITION[k]))
			if not p.ai:
				sim.emit_log("The expedition found that coast taken and sails home.", Color("e0b060"))
		return
	var dest: Sim.Bld = sim.by_id.get(t.dest)
	if dest != null and not dest.dead and dest.p == p.id:
		sim.logistics.store_add(dest, p, t.res, float(t.n))
	else:
		sim.give(p, t.res, float(t.n))


## Every few seconds: one cargo per realm from a harbour with plenty to a harbour no road joins to it
## that has little. The goods a young colony needs most come first.
const CARGO := ["planks", "stone", "bread", "fish", "meat", "grain", "water", "axes", "pickaxes", "farm_tools", "weapons", "wood", "iron", "coal"]

func sea_transfers() -> void:
	for p in sim.players:
		if not p.alive or free_ships(p) < 1:
			continue
		var hs := harbours(p)
		if hs.size() < 2:
			continue
		var best := []
		var best_gap := 0.0
		for a: Sim.Bld in hs:
			for b: Sim.Bld in hs:
				if a == b or b.policy == 2:
					continue
				# joined by road: the porters do it (store transfers)
				var f := sim.logistics.store_field(b, sim.idx(a.x, a.y))
				if (f[1] as PackedFloat32Array)[sim.idx(a.x, a.y)] < INF:
					continue
				for r: String in CARGO:
					var have := float(a.inv.get(r, 0.0))
					var there := float(b.inv.get(r, 0.0))
					var gap := have - there
					if have >= 12.0 and there < 10.0 and gap > best_gap:
						best_gap = gap
						best = [a, b, r]
		if best.is_empty():
			continue
		var a: Sim.Bld = best[0]
		var b: Sim.Bld = best[1]
		var r: String = best[2]
		var path := water_path(a.x, a.y, b.x, b.y)
		if path.is_empty():
			continue
		var n := mini(SHIP_LOAD, int(float(a.inv.get(r, 0.0)) / 2.0))
		if n <= 0:
			continue
		sim.logistics.store_add(a, p, r, -float(n))
		p.ships_out += 1
		var t := Sim.Trip.new()
		t.p = p.id; t.kind = "ship"; t.res = r; t.n = n; t.dest = b.id; t.site = a.id
		t.path = path
		var st := _sail_time(path)
		t.t0 = sim.time; t.t1 = sim.time + st + 2.0; t.t2 = t.t1 + st
		sim.trips.append(t)


# ---------------------------------------------------------------- landings
const LANDING_PER_SHIP := 6      # soldiers a ship carries to a landing
const LANDING_MAX := 24          # soldiers in one landing
const LAND_R := 10               # a landing goes ashore at most this far from its target


## The way for soldiers from harbour h to building t across the water: [the crossing (water tiles,
## then the beach), the march from the beach], or [] when no sea joins them. The ships take the
## shortest way to any beach within LAND_R of the target, then the soldiers march.
func landing_route(h: Sim.Bld, t: Sim.Bld) -> Array:
	var starts := _moorings(h.x, h.y)
	if starts.is_empty():
		return []
	# beaches near the target: land tiles with water beside them, and that water
	var goal := {}         # water tile -> the beach tile next to it nearest the target
	var gd := {}
	for dy in range(-LAND_R, LAND_R + 1):
		for dx in range(-LAND_R, LAND_R + 1):
			var x := t.x + dx
			var y := t.y + dy
			if not sim.inb(x, y) or dx * dx + dy * dy > LAND_R * LAND_R:
				continue
			var i := sim.idx(x, y)
			if sim.ter[i] == Sim.WATER or sim.ter[i] == Sim.MOUNT or sim.bmap[i] != 0:
				continue
			var d := float(dx * dx + dy * dy)
			for ny in range(y - 1, y + 2):
				for nx in range(x - 1, x + 2):
					if sim.inb(nx, ny) and sim.ter[sim.idx(nx, ny)] == Sim.WATER:
						var wi := sim.idx(nx, ny)
						if not goal.has(wi) or d < float(gd[wi]):
							goal[wi] = i
							gd[wi] = d
	if goal.is_empty():
		return []
	# breadth-first over the water from the harbour to the first such beach
	var came := {}
	var q := []
	for s in starts:
		came[s] = -1
		q.append(s)
	var head := 0
	var found := -1
	while head < q.size() and head < 120000:
		var cur: int = q[head]
		head += 1
		if goal.has(cur):
			found = cur
			break
		var cx := cur % sim.w
		var cy := cur / sim.w
		for ddy in range(-1, 2):
			for ddx in range(-1, 2):
				var nx := cx + ddx
				var ny := cy + ddy
				if (ddx == 0 and ddy == 0) or not sim.inb(nx, ny):
					continue
				var ni := ny * sim.w + nx
				if came.has(ni) or sim.ter[ni] != Sim.WATER:
					continue
				came[ni] = cur
				q.append(ni)
	if found < 0:
		return []
	var sea := PackedInt32Array()
	var c := found
	while c != -1:
		sea.append(c)
		c = came[c]
	sea.reverse()
	var beach: int = goal[found]
	sea.append(beach)
	var land := sim.military.land_path(beach % sim.w, beach / sim.w, t.x, t.y)
	if land.is_empty():
		return []
	return [sea, land]


## Where ship trip t is now (cargo ships and expeditions).
func ship_pos(t: Sim.Trip) -> Vector2:
	var n := t.path.size() - 1
	if n < 1:
		return Vector2(-99, -99)
	var prog := 0.0
	if not t.delivered:
		prog = clampf((sim.time - t.t0) / maxf(0.01, t.t1 - t.t0), 0.0, 1.0)
	else:
		prog = 1.0 - clampf((sim.time - t.t1) / maxf(0.01, t.t2 - t.t1), 0.0, 1.0)
	var f := prog * n
	var k := mini(floori(f), n - 1)
	return Vector2(t.path[k] % sim.w, t.path[k] / sim.w).lerp(Vector2(t.path[k + 1] % sim.w, t.path[k + 1] / sim.w), f - k)


## A fleet at sea sinks the cargo ships and expeditions of realms it is at war with that it meets.
func fleets_meet_ships() -> void:
	for a: Sim.Attack in sim.attacks:
		if not sim.military.at_sea(a) or a.n <= 0:
			continue
		var fp := sim.military.column_pos(a)
		for k in range(sim.trips.size() - 1, -1, -1):
			var t := sim.trips[k]
			if t.kind != "ship" or t.p == a.p or not Diplomacy.at_war(sim, a.p, t.p):
				continue
			if ship_pos(t).distance_to(fp) > 1.6:
				continue
			var q := sim.players[t.p - 1]
			q.ships = maxi(0, q.ships - 1)
			q.ships_out = maxi(0, q.ships_out - 1)
			sim.trips.remove_at(k)
			if t.p == 1:
				sim.emit_log("%s's fleet sank your ship%s." % [sim.players[a.p - 1].name, " and its expedition" if t.res == "@expedition" else (" with %d %s" % [t.n, t.res] if not t.delivered else "")], Color("e08a6a"), Vector2i(fp.round()))
			elif a.p == 1:
				sim.emit_log("Your fleet sank a ship of %s." % q.name, Color("86ad5c"), Vector2i(fp.round()))


## A rival with a free ship and a harbour sends an expedition to the nearest free coast, when its land
## is crowded or it has been at it a while.
func ai_expedition(p: Sim.Player) -> void:
	if free_ships(p) < 1 or p.reserve < 2:
		return
	var hs := harbours(p)
	if hs.is_empty():
		return
	var h: Sim.Bld = hs[0]
	if float(h.inv.get("planks", 0.0)) < EXPEDITION.planks or float(h.inv.get("stone", 0.0)) < EXPEDITION.stone:
		return
	var best := -1
	var bd := 1e9
	# coast tiles nobody holds, sampled over the map
	for k in 400:
		var i := sim.rng.randi() % (sim.w * sim.h)
		var x := i % sim.w
		var y := i / sim.w
		if sim.owner[i] != 0 or (sim.ter[i] != Sim.BEACH and sim.ter[i] != Sim.GRASS):
			continue
		var d := Vector2(x - h.x, y - h.y).length()
		if d < bd and d > 10.0 and landing_ok(x, y, p.id) == "":
			bd = d; best = i
	if best >= 0:
		expedition(p, h, best % sim.w, best / sim.w)
