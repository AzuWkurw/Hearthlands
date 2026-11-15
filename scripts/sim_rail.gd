class_name SimRail
extends RefCounted
## Steam and rails (build 64).
##
## Railways: track is laid tile by tile (Sim.rail, 1 where a rail lies; whose it is goes with the land,
## Sim.owner), one rail (the good) a tile, three a tile on a bridge. Railway stations are stores; a station
## joins the track touching its plot. Two stations on the same track make a line. Every locomotive in a
## realm's stores is a train: every few seconds a free train takes up to TRAIN_LOAD goods from a station
## with plenty to one on the same track with little (as river boats do), for 1 coal a trip, and comes
## back empty. Enemy columns marching over a line tear up a few tiles of it.
##
## Steam engines: with the Steam engine study a workshop of the kinds in STEAM_KINDS can take a steam
## engine (STEAM_COST, fitted in STEAM_FIT seconds while it keeps working): it then works STEAM faster for
## 1 coal every 2 work cycles (none in store: as before), and its smoke makes homes within SMOKE_R tiles
## a little less content (Contentment).

const TRAIN_LOAD := 40
const SPEED := 4.0               # tiles a second
const BRIDGE_MAX := 5
const BRIDGE_RAILS := 3
const STEAM := 0.6
const STEAM_FIT := 40.0
const STEAM_COST := {"iron": 4, "bricks": 6, "steel": 2}
const SMOKE_R := 4
const STEAM_KINDS := ["sawmill", "mill", "bakery", "brewery", "weaver", "tailor", "brickworks", "iron_smelter",
	"copper_smelter", "toolsmith", "weaponsmith", "armorer", "tannery", "paper_mill", "carpenter", "glassworks",
	"textile_mill", "powder_mill", "gunsmith", "cartridge_works", "lead_smelter", "mint", "butcher", "smokehouse"]

var sim: Sim
var ver := 0                     # goes up whenever a rail is laid or taken up
var _comp := {}                  # realm id -> [ver, PackedInt32Array: track piece of each tile (-1: none)]


func _init(p_sim: Sim) -> void:
	sim = p_sim


## A new or loaded game: nothing worked out is kept.
func reset() -> void:
	ver = 0
	_comp = {}


func has_rail(i: int, pid: int) -> bool:
	return sim.rail[i] != 0 and sim.owner[i] == pid


static func is_station(b: Sim.Bld) -> bool:
	return b != null and b.ty == "railway_station"


func stations(p: Sim.Player) -> Array:
	return sim.realm_blds(p).filter(func(b): return is_station(b) and b.state == "ready" and not b.dead)


## The rail tiles touching station b: next to its own tile or its plot.
func station_rails(b: Sim.Bld) -> PackedInt32Array:
	var out := PackedInt32Array()
	var tiles := sim.plot_tiles(b.ty, b.x, b.y)
	if not tiles.has(sim.idx(b.x, b.y)):
		tiles.append(sim.idx(b.x, b.y))
	for t in tiles:
		var x := t % sim.w
		var y := t / sim.w
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := x + d.x
			var ny := y + d.y
			if sim.inb(nx, ny):
				var ni := sim.idx(nx, ny)
				if has_rail(ni, b.p) and not out.has(ni):
					out.append(ni)
	return out


## The track pieces of realm pid: for each tile the piece it belongs to (-1: no rail of pid).
func comp(pid: int) -> PackedInt32Array:
	# the pieces follow the rails and the borders (a rail belongs to whoever holds its land)
	var key := Vector2i(ver, sim.territory_version)
	var e = _comp.get(pid)
	if e != null and e[0] == key:
		return e[1]
	var c := PackedInt32Array()
	c.resize(sim.w * sim.h)
	c.fill(-1)
	var k := 0
	for i in sim.w * sim.h:
		if c[i] != -1 or not has_rail(i, pid):
			continue
		var q := [i]
		c[i] = k
		while not q.is_empty():
			var cur: int = q.pop_back()
			for n in _nbrs(cur):
				if c[n] == -1 and has_rail(n, pid):
					c[n] = k
					q.append(n)
		k += 1
	_comp[pid] = [key, c]
	return c


func _nbrs(i: int) -> Array:
	var x := i % sim.w
	var y := i / sim.w
	var out := []
	if x > 0: out.append(i - 1)
	if x < sim.w - 1: out.append(i + 1)
	if y > 0: out.append(i - sim.w)
	if y < sim.h - 1: out.append(i + sim.w)
	return out


## The track piece station b stands on (-1: none).
func station_piece(b: Sim.Bld) -> int:
	var c := comp(b.p)
	for t in station_rails(b):
		if c[t] >= 0:
			return c[t]
	return -1


# ---------------------------------------------------------------- laying track

## Why realm pid can't lay rails ("" when it can).
func can_lay(pid: int) -> String:
	if not sim.players[pid - 1].techs.has("railways"):
		return "Study Railways (Industrial age) to lay track"
	return ""


## The way for new track from (sx, sy) to (gx, gy) through realm pid's land: over open land, across
## roads (level crossings) and straight over water as a bridge (up to BRIDGE_MAX tiles). It starts at a
## rail of pid's or next to one of its stations. Empty when there is none.
func find_path(sx: int, sy: int, gx: int, gy: int, pid: int) -> PackedInt32Array:
	if not sim.inb(sx, sy) or not sim.inb(gx, gy):
		return PackedInt32Array()
	var starts := PackedInt32Array()
	var s := sim.idx(sx, sy)
	var sb := sim.bld_at(sx, sy)
	if is_station(sb) and sb.p == pid:
		# from any free tile next to the station's plot
		var tiles := sim.plot_tiles(sb.ty, sb.x, sb.y)
		tiles.append(sim.idx(sb.x, sb.y))
		for t in tiles:
			for n in _nbrs(t):
				if not starts.has(n) and _open(n, pid):
					starts.append(n)
	elif _open(s, pid):
		starts.append(s)
	var g := sim.idx(gx, gy)
	var goals := {}
	var gb := sim.bld_at(gx, gy)
	if is_station(gb) and gb.p == pid:
		var tiles2 := sim.plot_tiles(gb.ty, gb.x, gb.y)
		tiles2.append(sim.idx(gb.x, gb.y))
		for t in tiles2:
			for n in _nbrs(t):
				if _open(n, pid):
					goals[n] = true
	elif _open(g, pid):
		goals[g] = true
	if starts.is_empty() or goals.is_empty():
		return PackedInt32Array()
	var dist := {}
	var came := {}
	var hp := Sim.MinHeap.new()
	for st in starts:
		dist[st] = 0.0
		came[st] = -1
		hp.push(0.0, st)
	var done := {}
	var nodes := 0
	while hp.size() > 0:
		var cur := hp.pop()
		if done.has(cur):
			continue
		done[cur] = true
		if goals.has(cur):
			var path := PackedInt32Array()
			var c = cur
			while c != -1:
				path.append(c)
				c = came[c]
			path.reverse()
			return path
		nodes += 1
		if nodes > 30000:
			break
		for n in _nbrs(cur):
			if done.has(n):
				continue
			var step := 0.0
			if sim.ter[n] == Sim.WATER:
				# a bridge goes straight on: no turning on the water, and not too long
				if sim.owner[n] != pid:
					continue
				var prev = came.get(cur, -1)
				if sim.ter[cur] == Sim.WATER and prev != -1 and cur - int(prev) != n - cur:
					continue
				if _water_run(cur, n) > BRIDGE_MAX:
					continue
				step = 3.0
			else:
				if sim.ter[cur] == Sim.WATER:
					var prev2 = came.get(cur, -1)
					if prev2 != -1 and cur - int(prev2) != n - cur:
						continue
				if not _open(n, pid):
					continue
				step = 0.3 if sim.rail[n] != 0 else (1.4 if sim.road[n] != 0 else 1.0)
				if sim.deco[n] == Sim.D_TREE:
					step += 0.5
			var nd := float(dist[cur]) + step
			if nd < float(dist.get(n, INF)):
				dist[n] = nd
				came[n] = cur
				hp.push(nd, n)
	return PackedInt32Array()


## How many water tiles a bridge from cur over n would have crossed when it reaches n.
func _water_run(cur: int, n: int) -> int:
	var d := n - cur
	var k := 1
	var c := cur
	while sim.ter[c] == Sim.WATER and k <= BRIDGE_MAX + 1:
		k += 1
		c -= d
		if c < 0 or c >= sim.w * sim.h:
			break
	return k


## Whether a rail may lie on land tile i of realm pid: its own land, no building or plot, no rocks, no
## mountain.
func _open(i: int, pid: int) -> bool:
	if sim.owner[i] != pid or sim.ter[i] == Sim.WATER or sim.ter[i] == Sim.MOUNT:
		return false
	if sim.bmap[i] != 0 or sim.plot[i] != 0:
		return false
	return sim.deco[i] != Sim.D_ROCK and sim.deco[i] != Sim.D_CLAY


## Rails a path takes: one for each new land tile, BRIDGE_RAILS for each new water tile.
func cost_of(path: PackedInt32Array) -> int:
	var n := 0
	for i in path:
		if sim.rail[i] == 0:
			n += BRIDGE_RAILS if sim.ter[i] == Sim.WATER else 1
	return n


## Lays track along path for realm p, taking the rails from its stores. "" when done.
func lay(path: PackedInt32Array, p: Sim.Player) -> String:
	var need := cost_of(path)
	if need == 0:
		return "The track is there already"
	if not sim.creative(p):
		if float(p.stock.get("rails", 0.0)) < need:
			return "This track needs %d rails (%d in store): a rolling mill makes them from steel" % [need, int(p.stock.get("rails", 0.0))]
		sim.take(p, "rails", float(need), path[0])
		sim.used(p, "rails", float(need))
	for i in path:
		if sim.rail[i] == 0:
			sim.rail[i] = 1
			if sim.deco[i] == Sim.D_TREE:
				sim.deco[i] = 0
			sim.changed_tiles.append(i)
	ver += 1
	return ""


## Lays track from (sx, sy) to (gx, gy) for realm pid. "" when done, else why not.
func build(sx: int, sy: int, gx: int, gy: int, pid: int) -> String:
	var why := can_lay(pid)
	if why != "":
		return why
	var path := find_path(sx, sy, gx, gy, pid)
	if path.is_empty():
		return "No way for track there (over open land of yours, straight across water up to %d tiles)" % BRIDGE_MAX
	return lay(path, sim.players[pid - 1])


## Takes up the stretch of track through (x, y), up to the next junction; half the rails come back.
## Returns how many tiles.
func remove(x: int, y: int, pid: int) -> int:
	if not sim.inb(x, y) or not has_rail(sim.idx(x, y), pid):
		return 0
	var i := sim.idx(x, y)
	var gone := PackedInt32Array()
	var stack := [i]
	var seen := {i: true}
	while not stack.is_empty():
		var c: int = stack.pop_back()
		var nb := _nbrs(c).filter(func(n): return has_rail(n, pid))
		if c != i and nb.size() >= 3:
			continue
		gone.append(c)
		if c == i and nb.size() >= 3:
			continue
		for n in nb:
			if not seen.has(n):
				seen[n] = true
				stack.append(n)
	var back := 0
	for c in gone:
		back += BRIDGE_RAILS if sim.ter[c] == Sim.WATER else 1
		sim.rail[c] = 0
		sim.changed_tiles.append(c)
	sim.give(sim.players[pid - 1], "rails", float(back / 2), i)
	ver += 1
	return gone.size()


# ---------------------------------------------------------------- trains

## Trains realm p has: one for each locomotive in its stores.
func trains(p: Sim.Player) -> int:
	return int(float(p.stock.get("locomotive", 0.0)))


func trains_out(p: Sim.Player) -> int:
	var n := 0
	for t in sim.trips:
		if t.kind == "train" and t.p == p.id:
			n += 1
	return n


## The way along the track from station a to station b: the tiles a train runs over, from beside a to
## beside b. Empty when they are not on the same track.
func line_path(a: Sim.Bld, b: Sim.Bld) -> PackedInt32Array:
	var starts := station_rails(a)
	var ends := {}
	for t in station_rails(b):
		ends[t] = true
	if starts.is_empty() or ends.is_empty():
		return PackedInt32Array()
	var came := {}
	var q := []
	for s in starts:
		came[s] = -1
		q.append(s)
	var head := 0
	while head < q.size():
		var cur: int = q[head]
		head += 1
		if ends.has(cur):
			var path := PackedInt32Array()
			var c = cur
			while c != -1:
				path.append(c)
				c = came[c]
			path.reverse()
			return path
		for n in _nbrs(cur):
			if not came.has(n) and has_rail(n, a.p):
				came[n] = cur
				q.append(n)
	return PackedInt32Array()


## Every few seconds: each realm's free trains take loads from stations with plenty to stations with
## little on the same track (the biggest gap first), for 1 coal a trip.
func transfers() -> void:
	for p in sim.players:
		if not p.alive:
			continue
		var free := trains(p) - trains_out(p)
		if free <= 0:
			continue
		var sts := stations(p)
		if sts.size() < 2:
			continue
		var pieces := {}
		for s: Sim.Bld in sts:
			pieces[s.id] = station_piece(s)
		for k in free:
			if float(p.stock.get("coal", 0.0)) < 1.0:
				break
			var best := []
			var gap := 0.0
			for a: Sim.Bld in sts:
				if int(pieces[a.id]) < 0 or a.busy >= 2:
					continue
				for b: Sim.Bld in sts:
					if a == b or int(pieces[b.id]) != int(pieces[a.id]):
						continue
					for r in a.inv:
						var have := float(a.inv.get(r, 0.0))
						var there := float(b.inv.get(r, 0.0))
						if have >= 12.0 and have - there > gap and have > there * 2.0 + 6.0:
							gap = have - there
							best = [a, b, String(r)]
			if best.is_empty():
				break
			_send(p, best[0], best[1], best[2])


func _send(p: Sim.Player, a: Sim.Bld, b: Sim.Bld, r: String) -> void:
	var path := line_path(a, b)
	if path.size() < 2:
		return
	var n := mini(TRAIN_LOAD, int(float(a.inv.get(r, 0.0)) / 2.0))
	if n <= 0:
		return
	sim.logistics.store_add(a, p, r, -float(n))
	# the rest of the load: the next good with the biggest gap
	var r2 := ""
	var n2 := 0
	var gap2 := 0.0
	for k in a.inv:
		if String(k) == r:
			continue
		var have := float(a.inv.get(k, 0.0))
		var there := float(b.inv.get(k, 0.0))
		if have >= 12.0 and have - there > gap2 and have > there * 2.0 + 6.0:
			gap2 = have - there
			r2 = String(k)
	if r2 != "" and n < TRAIN_LOAD:
		n2 = mini(TRAIN_LOAD - n, int(float(a.inv.get(r2, 0.0)) / 2.0))
		if n2 > 0:
			sim.logistics.store_add(a, p, r2, -float(n2))
		else:
			r2 = ""
	sim.take(p, "coal", 1.0, sim.idx(a.x, a.y))
	sim.used(p, "coal", 1.0)
	a.busy += 1
	var run := float(path.size()) / SPEED
	var t := Sim.Trip.new()
	t.p = p.id; t.kind = "train"; t.res = r; t.n = n; t.res2 = r2; t.n2 = n2
	t.site = a.id; t.dest = b.id; t.station = -1
	t.path = path
	t.t0 = sim.time; t.t1 = sim.time + run + 4.0; t.t2 = t.t1 + run + 2.0
	sim.trips.append(t)


func train_arrival(t: Sim.Trip, p: Sim.Player) -> void:
	var a: Sim.Bld = sim.by_id.get(t.site)
	if a != null:
		a.busy = maxi(0, a.busy - 1)
	var dest: Sim.Bld = sim.by_id.get(t.dest)
	var ok := dest != null and not dest.dead and dest.p == p.id
	for pair in [[t.res, t.n], [t.res2, t.n2]]:
		if String(pair[0]) == "" or int(pair[1]) <= 0:
			continue
		if ok:
			sim.logistics.store_add(dest, p, String(pair[0]), float(pair[1]))
		elif p.alive:
			sim.give(p, String(pair[0]), float(pair[1]))
	if ok:
		dest.carried += t.n + t.n2
	if a != null:
		a.carried += t.n + t.n2


## Once a second: columns marching over an enemy's line tear up the track under them and next to it.
func second() -> void:
	for a: Sim.Attack in sim.attacks:
		if a.fighting or a.n <= 0 or sim.military.at_sea(a):
			continue
		var pos := sim.military.column_pos(a)
		var x := int(pos.x)
		var y := int(pos.y)
		if not sim.inb(x, y):
			continue
		var i := sim.idx(x, y)
		var o := int(sim.owner[i])
		if sim.rail[i] == 0 or o == 0 or o == a.p or not Diplomacy.at_war(sim, a.p, o):
			continue
		var torn := 0
		for c in [i] + _nbrs(i):
			if sim.rail[c] != 0 and int(sim.owner[c]) == o:
				sim.rail[c] = 0
				sim.changed_tiles.append(c)
				torn += 1
		ver += 1
		if o == 1 and not a.tore:
			a.tore = true
			sim.emit_log("Enemy soldiers tore up %d tiles of your railway. Lay them again once the column has passed." % torn, Color("e08a6a"), Vector2i(x, y))
		elif a.p == 1 and not a.tore:
			a.tore = true
			sim.emit_log("Your column tore up %s's railway as it marched." % sim.players[o - 1].name, Color("d8aa4a"), Vector2i(x, y))


# ---------------------------------------------------------------- steam engines

## Why building b can't take a steam engine now ("" when it can).
func steam_why(b: Sim.Bld) -> String:
	var p := sim.players[b.p - 1]
	if not STEAM_KINDS.has(b.ty):
		return "This kind of building takes no steam engine"
	if b.steam:
		return "It has its steam engine already"
	if not p.techs.has("steam_engine"):
		return "Study Steam engine (Industrial age) first"
	if b.state != "ready":
		return "Only a finished building"
	if not sim.creative(p):
		var m := sim.missing(p, STEAM_COST)
		if m != "":
			return "Not enough %s in store" % GameData.res_name(m).to_lower()
	return ""


## Fits a steam engine into building b: the materials come from the stores at once and it is ready in
## STEAM_FIT seconds (the building keeps working meanwhile). "" when done.
func fit_steam(b: Sim.Bld) -> String:
	var why := steam_why(b)
	if why != "":
		return why
	var p := sim.players[b.p - 1]
	if not sim.creative(p):
		for k in STEAM_COST:
			sim.take(p, k, float(STEAM_COST[k]), sim.idx(b.x, b.y))
			sim.used(p, k, float(STEAM_COST[k]))
	b.steam = true
	b.steam_at = sim.time + STEAM_FIT
	b.steam_coal = 0.0
	return ""


func remove_steam(b: Sim.Bld) -> void:
	b.steam = false
	b.steam_at = 0.0
	b.steam_coal = 0.0


## Whether building b's steam engine is fitted and running (it may still lack coal).
func steam_on(b: Sim.Bld) -> bool:
	return b.steam and sim.time >= b.steam_at


## At the start of each work cycle: a fitted engine burns half a coal and the cycle goes STEAM faster;
## with no coal in store it goes at the old speed. Returns the factor.
func steam_cycle(b: Sim.Bld, p: Sim.Player) -> float:
	if not steam_on(b):
		return 1.0
	if b.steam_coal < 0.5 and float(p.stock.get("coal", 0.0)) >= 1.0:
		sim.take(p, "coal", 1.0, sim.idx(b.x, b.y))
		sim.used(p, "coal", 1.0)
		b.steam_coal += 1.0
	if b.steam_coal >= 0.5:
		b.steam_coal -= 0.5
		return 1.0 + STEAM
	return 1.0
