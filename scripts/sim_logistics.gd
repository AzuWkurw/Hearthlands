class_name SimLogistics
extends RefCounted
## Roads, the road network, stores, carriers and work areas.
## Part of the simulation: sim.gd holds the shared state and calls in here; the functions reach
## the rest of the game through `sim`.

var sim: Sim

var _net_par: Array = []           # per realm: next tile on the way to that store
var net_ver: Array = []            # per realm: counts rebuilds, so cached paths know when they are stale
var _mil: Array = []               # all military buildings and headquarters
var _pb: Array = []                # per realm: its buildings, rebuilt once a second
var _stations: Array = []          # per realm: working mule stations and cart yards


func _init(p_sim: Sim) -> void:
	sim = p_sim


## Bridges. A road may cross water only straight across, from land to land, over at most
## BRIDGE_MAX water tiles inside the realm. Each new bridge tile costs BRIDGE_PLANKS planks (paving it
## with stone makes it a stone bridge). Ships pass under them.
const BRIDGE_MAX := 3
const BRIDGE_PLANKS := 2

var last_laid := PackedInt32Array()   # the tiles the last road laid made new (for undo)
var last_bridge_planks := 0

## From land tile cur onto water tile ni: the land tile where a bridge straight on would come ashore,
## or -1 when there is none close enough (or it is not a place for a road).
func bridge_landing(cur: int, ni: int, pid: int) -> int:
	var d := ni - cur
	var c := ni
	for k in BRIDGE_MAX:
		var nx := c % sim.w + (d if absi(d) == 1 else 0)
		var nxt := c + d
		if nxt < 0 or nxt >= sim.w * sim.h or nx < 0 or nx >= sim.w:
			return -1
		if sim.ter[nxt] != Sim.WATER:
			if sim.owner[nxt] != pid or sim.deco[nxt] == Sim.D_ROCK or sim.deco[nxt] == Sim.D_CLAY or (sim.plot[nxt] != 0 and sim.bmap[nxt] == 0):
				return -1
			return nxt
		if sim.owner[nxt] != pid:
			return -1
		c = nxt
	return -1


## In a road search: may the road step from cur onto water tile ni? Along a bridge already there, or
## starting a new one from land with a landing in reach, or carrying straight on over the water.
func bridge_step(cur: int, ni: int, pid: int) -> bool:
	if sim.road[ni] == pid:
		return true
	if sim.ter[cur] == Sim.WATER:
		var prev := sim._came[cur]
		return prev >= 0 and cur - prev == ni - cur
	return bridge_landing(cur, ni, pid) >= 0


## New bridge tiles on path (water tiles not yet carrying a road of pid).
func bridge_tiles(path: PackedInt32Array, pid: int) -> int:
	var n := 0
	for i in path:
		if sim.ter[i] == Sim.WATER and sim.road[i] != pid:
			n += 1
	return n


func find_path(sx: int, sy: int, gx: int, gy: int, pid: int) -> PackedInt32Array:
	sim._stamp += 1
	var st := sim._stamp
	var s := sim.idx(sx, sy)
	var g := sim.idx(gx, gy)
	var hp := Sim.MinHeap.new()
	sim._gs[s] = 0.0; sim._came[s] = -1; sim._seen[s] = st
	hp.push(0.0, s)
	var nodes := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while hp.size() > 0:
		var cur := hp.pop()
		if sim._closed[cur] == st:
			continue
		sim._closed[cur] = st
		if cur == g:
			var path := PackedInt32Array()
			var c := g
			while c != -1:
				path.append(c)
				c = sim._came[c]
			path.reverse()
			return path
		nodes += 1
		if nodes > 20000:
			break
		var cx := cur % sim.w
		var cy := cur / sim.w
		for d in dirs:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if nx < 0 or ny < 0 or nx >= sim.w or ny >= sim.h:
				continue
			var ni := ny * sim.w + nx
			if sim._closed[ni] == st:
				continue
			if ni != g:
				if sim.owner[ni] != pid or sim.deco[ni] == Sim.D_ROCK or sim.deco[ni] == Sim.D_CLAY or sim.bmap[ni] != 0 or sim.plot[ni] != 0:
					continue
				if sim.ter[ni] == Sim.WATER and not bridge_step(cur, ni, pid):
					continue
			# off a bridge only straight on
			if sim.ter[cur] == Sim.WATER and sim._came[cur] >= 0 and cur - sim._came[cur] != ni - cur:
				continue
			# a road leaves or reaches a building only at its entrance
			if (sim.bmap[cur] != 0 or sim.bmap[ni] != 0) and not sim.links(cur, ni):
				continue
			var tc := 0.35 if sim.road[ni] == pid else (4.0 if sim.deco[ni] == Sim.D_TREE else (2.5 if sim.ter[ni] == Sim.MOUNT else (3.0 if sim.ter[ni] == Sim.WATER else 1.0)))
			tc *= float(Sim.SLOPE_MUL[sim.slope_level(cur, ni)])
			var ng := sim._gs[cur] + tc
			if sim._seen[ni] != st or ng < sim._gs[ni]:
				sim._seen[ni] = st; sim._gs[ni] = ng; sim._came[ni] = cur
				hp.push(ng + (absi(nx - gx) + absi(ny - gy)) * 0.4, ni)
	return PackedInt32Array()


## Units left in the vein this tile belongs to.
func vein_left(i: int) -> int:
	var v := sim.vein[i] if i >= 0 and i < sim.vein.size() else 0
	return int(sim.vein_amt[v]) if v > 0 else 0


## Takes one unit from the vein under tile i, if it holds ore of this kind. A vein that runs dry vanishes.
func take_ore(i: int, kind: int, keep := false) -> bool:
	if i < 0 or sim.ore[i] != kind:
		return false
	var v := sim.vein[i]
	if v <= 0 or int(sim.vein_amt[v]) <= 0:
		return false
	# endless veins (a difficulty option), or a lucky dig thanks to surveying research, take nothing away
	if keep or bool(sim.opts.endless_ore):
		return true
	sim.vein_amt[v] = int(sim.vein_amt[v]) - 1
	if int(sim.vein_amt[v]) == 0:
		for t in sim.vein_tiles[v]:
			sim.ore[t] = 0
			sim.changed_tiles.append(t)
		sim._owned_dirty = true
		if sim.owner[i] == 1:
			sim.emit_log("A %s vein has run dry." % String(GameData.ORE_NAMES.get(kind, "ore")), Color("e0b060"), Vector2i(i % sim.w, i / sim.w))
	return true


## "" when the realm has the planks for the new bridge tiles on path, else why not.
func bridge_cost_ok(path: PackedInt32Array, pid: int) -> String:
	var n := bridge_tiles(path, pid)
	if n == 0 or sim.creative(sim.players[pid - 1]):
		return ""
	var need := n * BRIDGE_PLANKS
	if float(sim.players[pid - 1].stock.get("planks", 0.0)) < need:
		return "A bridge here needs %d planks." % need
	return ""


func lay_road(path: PackedInt32Array, pid: int) -> void:
	var p := sim.players[pid - 1]
	var nb := bridge_tiles(path, pid)
	last_bridge_planks = 0
	if nb > 0 and not sim.creative(p):
		take(p, "planks", float(nb * BRIDGE_PLANKS), path[0])
		last_bridge_planks = nb * BRIDGE_PLANKS
	last_laid = PackedInt32Array()
	for i in path:
		if sim.bmap[i] != 0:
			continue
		if sim.road[i] != pid:
			last_laid.append(i)
		sim.road[i] = pid
		if sim.deco[i] == Sim.D_TREE:
			sim.deco[i] = 0
		sim.changed_tiles.append(i)
	net_touch(pid, path)


## After borders moved: a realm that lost a tile carrying its road or a building gets its network rebuilt;
## its own old roads coming back inside its border are added. Rows are compared a piece at a time with a
## fast built-in comparison, and only pieces that differ are looked at tile by tile.
func _territory_nets(before: PackedByteArray) -> void:
	var lost := {}
	for y in sim.h:
		var row := y * sim.w
		for x0 in range(0, sim.w, 32):
			var a := row + x0
			var e := mini(a + 32, row + sim.w)
			if before.slice(a, e) == sim.owner.slice(a, e):
				continue
			for i in range(a, e):
				var was := int(before[i])
				var now := int(sim.owner[i])
				if was == now:
					continue
				if was != 0 and (sim.road[i] == was or sim.bmap[i] != 0):
					lost[was] = true
				if now != 0 and sim.road[i] == now:
					net_touch(now, PackedInt32Array([i]))
	for pid in lost:
		net_dirty(pid)


## Called whenever a building appears, disappears, finishes or changes hands.
func _after_building_change(b: Sim.Bld) -> void:
	_store_ver += 1
	sim._mil_dirty = true
	sim._tick_dirty = true
	if b.dead or b.x < 0:
		net_dirty(b.p)
	else:
		net_touch(b.p, PackedInt32Array([sim.idx(b.x, b.y)]))
	if b.x >= 0:
		sim.changed_tiles.append(sim.idx(b.x, b.y))


func _reset_nets() -> void:
	sim._net_dist.clear(); _net_par.clear(); sim._net_dirty.clear(); net_ver.clear(); sim._net_add.clear()
	for p in sim.players:
		sim._net_dist.append(PackedFloat32Array())
		_net_par.append(PackedInt32Array())
		sim._net_dirty.append(true)
		sim._net_add.append([])
		net_ver.append(0)


## Marks the road network of realm pid (or of every realm, for 0) as needing a rebuild.
func net_dirty(pid := 0) -> void:
	for i in sim._net_dirty.size():
		if pid == 0 or i == pid - 1:
			sim._net_dirty[i] = true
			(sim._net_add[i] as Array).clear()


## Something only got better for realm pid's roads on these tiles (a new road or building, a store
## finished, a tile paved). Distances can only shrink, so the network is updated from these tiles
## outward the next time it is needed, instead of being rebuilt from scratch.
func net_touch(pid: int, tiles: PackedInt32Array) -> void:
	var k := pid - 1
	if k < 0 or k >= sim._net_dirty.size() or sim._net_dirty[k]:
		return
	(sim._net_add[k] as Array).append_array(Array(tiles))


## Brings realm pid's road network up to date: a full rebuild after something was lost, otherwise just
## the tiles that got better.
func _net_ready(pid: int) -> void:
	var k := pid - 1
	if sim._net_dirty[k]:
		_build_net(pid)
	elif not (sim._net_add[k] as Array).is_empty():
		_relax_net(pid)


var _reach := {}           # realm id -> [key, PackedByteArray: 1 where a new road can get to]

## Tiles of realm pid that a new road could reach from its road network: everything connected to the
## network over its own land that a road may cross (no water, rocks, clay or building plots). Building
## spots whose entrance is not among them are closed in. Worked out again when the roads or buildings
## change.
func reach(pid: int) -> PackedByteArray:
	var k := pid - 1
	_net_ready(pid)
	var key := "%d/%d" % [int(net_ver[k]), _store_ver]
	var e = _reach.get(pid)
	if e != null and String(e[0]) == key:
		return e[1]
	var r := PackedByteArray()
	r.resize(sim.w * sim.h)
	var q := PackedInt32Array()
	for i in sim.owned(pid)[0]:
		if net_dist(pid, i) < INF and (sim.road[i] == pid or sim.bmap[i] != 0):
			r[i] = 1
			q.append(i)
	var head := 0
	while head < q.size():
		var cur := q[head]
		head += 1
		var cx := cur % sim.w
		var cy := cur / sim.w
		for dd in 4:
			var nx := cx + (1 if dd == 0 else (-1 if dd == 1 else 0))
			var ny := cy + (1 if dd == 2 else (-1 if dd == 3 else 0))
			if nx < 0 or ny < 0 or nx >= sim.w or ny >= sim.h:
				continue
			var ni := ny * sim.w + nx
			if r[ni] == 1 or sim.owner[ni] != pid:
				continue
			if sim.deco[ni] == Sim.D_ROCK or sim.deco[ni] == Sim.D_CLAY:
				continue
			if sim.plot[ni] != 0 or sim.bmap[ni] != 0:
				continue
			if sim.bmap[cur] != 0 and not sim.links(cur, ni):
				continue
			if sim.ter[ni] == Sim.WATER:
				# along a bridge that is there, or from the shore over water a bridge could cross: the
				# far shore can be reached
				if sim.road[ni] == pid:
					r[ni] = 1
					q.append(ni)
				elif sim.ter[cur] != Sim.WATER:
					var land := bridge_landing(cur, ni, pid)
					if land >= 0 and r[land] == 0:
						r[land] = 1
						q.append(land)
				continue
			r[ni] = 1
			q.append(ni)
	_reach[pid] = [key, r]
	return r


# Road searches round each new distance to the precision they are stored in, and on equal distances
# take the way through the lower tile number. Then the result does not depend on the order the roads
# were built in, so a loaded game (whose network is built in one go) finds the same ways as the game
# that was saved (whose network grew a piece at a time).
var _f32 := PackedFloat32Array([0.0])


## Whether walking may continue from tile i: roads and stores pass carriers on, other buildings are
## only ends of the line.
func _net_spreads(i: int) -> bool:
	return sim.bmap[i] == 0 or is_store(sim.by_id.get(sim.bmap[i]))


## Whether tile i can be part of realm pid's road network at all.
func _net_open(i: int, pid: int) -> bool:
	if sim.owner[i] != pid:
		return false
	if sim.bmap[i] != 0:
		var nb: Sim.Bld = sim.by_id.get(sim.bmap[i])
		return nb != null and nb.p == pid
	return sim.road[i] == pid


## Updates distances after additions only. Each touched tile first takes the best way on from a
## neighbour already on the network (or becomes a source if it is a finished store), then improvements
## spread outward like in _build_net, stopping wherever nothing gets shorter.
func _relax_net(pid: int) -> void:
	var t0 := Time.get_ticks_usec()
	var k := pid - 1
	var dist: PackedFloat32Array = sim._net_dist[k]
	var par: PackedInt32Array = _net_par[k]
	var hp := Sim.MinHeap.new()
	for t: int in sim._net_add[k]:
		if t < 0 or not _net_open(t, pid):
			continue
		var b: Sim.Bld = sim.by_id.get(sim.bmap[t])
		if b != null and b.state == "ready" and is_store(b):
			if dist[t] > 0.0:
				dist[t] = 0.0
				par[t] = -1
			hp.push(0.0, t)
			continue
		var tx := t % sim.w
		var ty := t / sim.w
		for dd in 4:
			var nx := tx + (1 if dd == 0 else (-1 if dd == 1 else 0))
			var ny := ty + (1 if dd == 2 else (-1 if dd == 3 else 0))
			if nx < 0 or ny < 0 or nx >= sim.w or ny >= sim.h:
				continue
			var ni := ny * sim.w + nx
			if dist[ni] < INF and _net_spreads(ni) and sim.links(ni, t):
				_f32[0] = dist[ni] + step_cost(ni, t)
				var cand := _f32[0]
				if cand < dist[t] or (cand == dist[t] and ni < par[t]):
					dist[t] = cand
					par[t] = ni
		if dist[t] < INF:
			hp.push(dist[t], t)
	(sim._net_add[k] as Array).clear()
	while hp.size() > 0:
		var cur := hp.pop()
		if not _net_spreads(cur):
			continue
		var cx := cur % sim.w
		var cy := cur / sim.w
		for dd in 4:
			var nx := cx + (1 if dd == 0 else (-1 if dd == 1 else 0))
			var ny := cy + (1 if dd == 2 else (-1 if dd == 3 else 0))
			if nx < 0 or ny < 0 or nx >= sim.w or ny >= sim.h:
				continue
			var ni := ny * sim.w + nx
			if not _net_open(ni, pid) or not sim.links(cur, ni):
				continue
			_f32[0] = dist[cur] + step_cost(cur, ni)
			var nd := _f32[0]
			if nd < dist[ni] or (nd == dist[ni] and cur < par[ni]):
				var better := nd < dist[ni]
				dist[ni] = nd
				par[ni] = cur
				if better: hp.push(nd, ni)
	sim._net_dist[k] = dist
	_net_par[k] = par
	net_ver[k] = int(net_ver[k]) + 1
	sim._pf("road network", t0)


## Seconds a porter needs to walk from tile a onto its neighbour b: the ground of b, made longer by the
## climb or descent between them (Sim.SLOPE_MUL).
func step_cost(a: int, b: int) -> float:
	return tile_cost(b) * float(Sim.SLOPE_MUL[sim.slope_level(a, b)])


## Seconds a porter needs to walk onto tile i: paved roads and building doorsteps are faster than dirt.
func tile_cost(i: int) -> float:
	if sim.bmap[i] != 0 or sim.pave[i] == 1:
		return Sim.PAVED_COST
	return Sim.DIRT_COST


func is_store(b: Sim.Bld) -> bool:
	return b != null and b.def.has("store")


## Works out, for every road tile and building of realm pid, the walking time to its nearest store
## and which way to go (Dijkstra's shortest-path search, starting from all stores at once).
func _build_net(pid: int) -> void:
	var t0 := Time.get_ticks_usec()
	var k := pid - 1
	var dist := PackedFloat32Array(); dist.resize(sim.w * sim.h); dist.fill(INF)
	var par := PackedInt32Array(); par.resize(sim.w * sim.h); par.fill(-1)
	var done := PackedByteArray(); done.resize(sim.w * sim.h)
	var hp := Sim.MinHeap.new()
	for b in sim.blds:
		if b.p == pid and b.state == "ready" and is_store(b):
			var i := sim.idx(b.x, b.y)
			dist[i] = 0.0
			hp.push(0.0, i)
	while hp.size() > 0:
		var cur := hp.pop()
		if done[cur] == 1:
			continue
		done[cur] = 1
		if sim.bmap[cur] != 0 and not is_store(sim.by_id.get(sim.bmap[cur])):
			continue
		var cx := cur % sim.w
		var cy := cur / sim.w
		for dd in 4:
			var nx := cx + (1 if dd == 0 else (-1 if dd == 1 else 0))
			var ny := cy + (1 if dd == 2 else (-1 if dd == 3 else 0))
			if nx < 0 or ny < 0 or nx >= sim.w or ny >= sim.h:
				continue
			var ni := ny * sim.w + nx
			if done[ni] == 1 or sim.owner[ni] != pid:
				continue
			if sim.bmap[ni] != 0:
				var nb: Sim.Bld = sim.by_id.get(sim.bmap[ni])
				if nb == null or nb.p != pid:
					continue
			elif sim.road[ni] != pid:
				continue
			if (sim.bmap[cur] != 0 or sim.bmap[ni] != 0) and not sim.links(cur, ni):
				continue
			_f32[0] = dist[cur] + step_cost(cur, ni)
			var nd := _f32[0]
			if nd < dist[ni] or (nd == dist[ni] and cur < par[ni]):
				var better := nd < dist[ni]
				dist[ni] = nd
				par[ni] = cur
				if better: hp.push(nd, ni)
	sim._net_dist[k] = dist
	_net_par[k] = par
	sim._net_dirty[k] = false
	(sim._net_add[k] as Array).clear()
	net_ver[k] = int(net_ver[k]) + 1
	sim._pf("road network", t0)
	sim._net_builds += 1


## Walking seconds from tile i to realm pid's nearest store, or INF if no road leads there.
func net_dist(pid: int, i: int) -> float:
	_net_ready(pid)
	var d: PackedFloat32Array = sim._net_dist[pid - 1]
	return d[i]


func connected(b: Sim.Bld) -> bool:
	return net_dist(b.p, sim.idx(b.x, b.y)) < INF


## The road route from building b to its nearest store, kept until the network changes.
func store_path(b: Sim.Bld) -> PackedInt32Array:
	var k := b.p - 1
	_net_ready(b.p)
	if b.path_ver == int(net_ver[k]):
		return b.path
	var path := PackedInt32Array()
	var c := sim.idx(b.x, b.y)
	if (sim._net_dist[k] as PackedFloat32Array)[c] < INF:
		var par: PackedInt32Array = _net_par[k]
		while c != -1 and path.size() < 5000:
			path.append(c)
			c = par[c]
	b.path = path
	b.path_ver = int(net_ver[k])
	return path


## Plans a new building's road: the join to the network with the lowest cost of new road plus walk
## from there to a store, so new roads lead somewhere useful instead of just to the nearest road.
func _path_to_net(sx: int, sy: int, pid: int, door := -1, doors: Array = [0, 1, 2, 3]) -> PackedInt32Array:
	var t0 := Time.get_ticks_usec()
	var r := _path_to_net_inner(sx, sy, pid, door, doors)
	sim._pf("road laying", t0)
	return r


## door: the side the new building's entrance faces, so its road starts there (-1: any side).
## doors: the sides allowed when door is -1 (the new building's size decides them).
func _path_to_net_inner(sx: int, sy: int, pid: int, door := -1, doors: Array = [0, 1, 2, 3]) -> PackedInt32Array:
	if net_dist(pid, sim.idx(sx, sy)) < INF:
		return PackedInt32Array([sim.idx(sx, sy)])
	var nd: PackedFloat32Array = sim._net_dist[pid - 1]
	sim._stamp += 1
	var st := sim._stamp
	var s := sim.idx(sx, sy)
	var hp := Sim.MinHeap.new()
	sim._gs[s] = 0.0; sim._came[s] = -1; sim._seen[s] = st
	hp.push(0.0, s)
	var nodes := 0
	# The best join so far: the cost of the new road to it plus the walk from there to a store.
	# A join close by on a long detour can lose to one a little further away that is near a store.
	var best := -1
	var best_total := INF
	var front := sim.door_at(sx, sy, door)
	while hp.size() > 0:
		var cur := hp.pop()
		if sim._closed[cur] == st:
			continue
		sim._closed[cur] = st
		# nothing reached from here on can beat the best join found
		if sim._gs[cur] >= best_total:
			break
		if cur != s and nd[cur] < INF and (sim.road[cur] == pid or is_store(sim.by_id.get(sim.bmap[cur]))):
			var total := sim._gs[cur] + nd[cur]
			if total < best_total:
				best_total = total
				best = cur
			continue
		nodes += 1
		if nodes > 8000:
			break
		var cx := cur % sim.w
		var cy := cur / sim.w
		for dd in 4:
			var nx := cx + (1 if dd == 0 else (-1 if dd == 1 else 0))
			var ny := cy + (1 if dd == 2 else (-1 if dd == 3 else 0))
			if nx < 0 or ny < 0 or nx >= sim.w or ny >= sim.h:
				continue
			var ni := ny * sim.w + nx
			if sim._closed[ni] == st or sim.owner[ni] != pid:
				continue
			if cur == s and front >= 0 and ni != front:
				continue
			if cur == s and front < 0 and not doors.has(sim.side_of(s, ni)):
				continue
			# other buildings' plots (and the new building's own) are no place for a road
			if sim.plot[ni] != 0 and sim.bmap[ni] == 0:
				continue
			if sim.bmap[ni] != 0:
				if not is_store(sim.by_id.get(sim.bmap[ni])) or (sim.by_id.get(sim.bmap[ni]) as Sim.Bld).p != pid:
					continue
				if not sim.links(ni, cur):
					continue
			elif sim.deco[ni] == Sim.D_ROCK or sim.deco[ni] == Sim.D_CLAY:
				continue
			elif sim.ter[ni] == Sim.WATER and not bridge_step(cur, ni, pid):
				continue
			if sim.ter[cur] == Sim.WATER and sim._came[cur] >= 0 and cur - sim._came[cur] != ni - cur:
				continue
			# a new road tile costs its walk plus the work of laying it; mountains, trees and bridges cost more
			var tc := Sim.DIRT_COST if sim.road[ni] == pid else Sim.NEW_ROAD_COST + Sim.DIRT_COST + (3.0 if sim.deco[ni] == Sim.D_TREE else (1.5 if sim.ter[ni] == Sim.MOUNT else (4.0 if sim.ter[ni] == Sim.WATER else 0.0)))
			# slopes slow the carriers for good, so new roads go round hills where they can
			tc *= float(Sim.SLOPE_MUL[sim.slope_level(cur, ni)])
			var ng := sim._gs[cur] + tc
			if sim._seen[ni] != st or ng < sim._gs[ni]:
				sim._seen[ni] = st; sim._gs[ni] = ng; sim._came[ni] = cur
				hp.push(ng, ni)
	if best < 0:
		return PackedInt32Array()
	var path := PackedInt32Array()
	var c := best
	while c != -1:
		path.append(c)
		c = sim._came[c]
	path.reverse()
	return path


## Store room for one good: every ready store adds its tier's space; goods with a "cap" in the data
## (bricks, gold...) take more room, so less of them fits.
# ---------------------------------------------------------------- goods in each store
## Every store (headquarters, storehouse, warehouse, depot) keeps its own goods in Bld.inv; the realm's
## stock (Player.stock) is only the total of them, kept in step by store_add. Goods made are carried to
## a store and stay there; goods needed are fetched from a store that has them.

var _store_ver := 0
var _stores_at := -1
var _stores := {}          # realm id -> its finished stores, by id


## Realm p's finished stores, by id (worked out again whenever a building appears, goes or finishes).
func stores_of(p: Sim.Player) -> Array:
	if _stores_at != _store_ver:
		_stores_at = _store_ver
		_stores = {}
		for b in sim.blds:
			if not b.dead and b.state == "ready" and is_store(b):
				if not _stores.has(b.p):
					_stores[b.p] = []
				(_stores[b.p] as Array).append(b)
	return _stores.get(p.id, [])


## Realm p's stores, the one nearest tile `at` first (as the crow flies); at -1: nearest the headquarters.
func stores_near(p: Sim.Player, at: int, exclude: Sim.Bld = null) -> Array:
	var list := []
	for s: Sim.Bld in stores_of(p):
		if s != exclude:
			list.append(s)
	if at < 0 and p.hq != null:
		at = sim.idx(p.hq.x, p.hq.y)
	if at >= 0 and list.size() > 1:
		var ax := at % sim.w
		var ay := at / sim.w
		list.sort_custom(func(a: Sim.Bld, c: Sim.Bld):
			var da := (a.x - ax) * (a.x - ax) + (a.y - ay) * (a.y - ay)
			var dc := (c.x - ax) * (c.x - ax) + (c.y - ay) * (c.y - ay)
			return da < dc or (da == dc and a.id < c.id))
	return list


## Room for res in store s alone.
func store_cap(s: Sim.Bld, p: Sim.Player, res: String) -> float:
	return float(s.def.store) * GameData.res_cap(res) / 80.0 * (1.0 + sim.mod(p, "store"))


func store_room(s: Sim.Bld, p: Sim.Player, res: String) -> float:
	return store_cap(s, p, res) - float(s.inv.get(res, 0.0))


## Adds n of res to store s (n < 0 takes), and to the realm's total.
func store_add(s: Sim.Bld, p: Sim.Player, res: String, n: float) -> void:
	var v := float(s.inv.get(res, 0.0)) + n
	if v <= 0.0001:
		s.inv.erase(res)
	else:
		s.inv[res] = v
	var t := float(p.stock.get(res, 0.0)) + n
	p.stock[res] = t if absf(t) > 0.0001 else 0.0


## Puts n of res into realm p's stores, the one nearest tile `at` first, as far as there is room; what
## does not fit goes on to the next nearest. Stores set to "send away" take goods only when no other
## store has room. Returns how much found room (the rest is lost).
func give(p: Sim.Player, res: String, n: float, at := -1, exclude: Sim.Bld = null) -> float:
	if n <= 0.0:
		return 0.0
	var left := n
	var list := stores_near(p, at, exclude)
	for pass_n in 2:
		for s: Sim.Bld in list:
			if (s.policy == 2) != (pass_n == 1):
				continue
			var room := store_room(s, p, res)
			if room <= 0.0:
				continue
			var put := minf(room, left)
			store_add(s, p, res, put)
			left -= put
			if left <= 0.0001:
				return n
	return n - left


## Takes up to n of res from realm p's stores, the one nearest tile `at` first. Returns how much it got.
func take(p: Sim.Player, res: String, n: float, at := -1) -> float:
	if n <= 0.0:
		return 0.0
	var left := n
	for s: Sim.Bld in stores_near(p, at):
		var have := float(s.inv.get(res, 0.0))
		if have <= 0.0:
			continue
		var got := minf(have, left)
		store_add(s, p, res, -got)
		left -= got
		if left <= 0.0001:
			break
	return n - left


## A carrier reached store tile path[-1] with goods: they go into that store as far as it has room;
## the rest is taken on to the next stores with room (and lost if there is none).
func arrive_at_store(t: Sim.Trip, p: Sim.Player) -> void:
	var at := t.path[t.path.size() - 1] if t.path.size() > 0 else -1
	var s: Sim.Bld = sim.by_id.get(sim.bmap[at]) if at >= 0 else null
	var left := float(t.n)
	if s != null and not s.dead and s.p == p.id and s.state == "ready" and is_store(s) and s.policy != 2:
		var put := minf(maxf(0.0, store_room(s, p, t.res)), left)
		if put > 0.0:
			store_add(s, p, t.res, put)
			left -= put
	if left > 0.0:
		give(p, t.res, left, at)


## Goods moving between stores, every 5 game seconds, one load per realm at a time:
## - a store set to "send away" sends its biggest pile to the nearest store that takes it;
## - a store set to "gather here" fetches the biggest pile from another store;
## - a store nearly full of a good (85%) sends a load to the nearest store with little of it (30%).
func transfers() -> void:
	for p in sim.players:
		if not p.alive or (porters_free(p) <= 1 and not road_carriers_on()):
			continue
		var list := stores_of(p)
		if list.size() < 2:
			continue
		var done := false
		for s: Sim.Bld in list:
			if done: break
			if s.policy == 2 and not s.inv.is_empty():
				var k := _biggest(s)
				for t: Sim.Bld in stores_near(p, sim.idx(s.x, s.y), s):
					if t.policy != 2 and store_room(t, p, k) >= 1.0:
						done = _transfer(p, s, t, k)
						break
		for g: Sim.Bld in list:
			if done: break
			if g.policy == 1:
				for o: Sim.Bld in stores_near(p, sim.idx(g.x, g.y), g):
					if o.policy == 1 or o.inv.is_empty():
						continue
					var k := _biggest(o)
					if store_room(g, p, k) >= 1.0:
						done = _transfer(p, o, g, k)
						break
		for a: Sim.Bld in list:
			if done: break
			if a.policy != 0:
				continue
			var keys := a.inv.keys()
			keys.sort()
			for k in keys:
				if float(a.inv[k]) < store_cap(a, p, k) * 0.85:
					continue
				for b2: Sim.Bld in stores_near(p, sim.idx(a.x, a.y), a):
					if b2.policy != 2 and float(b2.inv.get(k, 0.0)) <= store_cap(b2, p, k) * 0.3 and store_room(b2, p, k) >= 2.0:
						done = _transfer(p, a, b2, k)
						break
				if done: break


func _biggest(s: Sim.Bld) -> String:
	var best := ""
	var bn := 0.0
	var keys := s.inv.keys()
	keys.sort()
	for k in keys:
		if float(s.inv[k]) > bn:
			bn = float(s.inv[k]); best = k
	return best


## A porter carries a load of res from store a to store b along the roads.
func _transfer(p: Sim.Player, a: Sim.Bld, b: Sim.Bld, res: String) -> bool:
	var at := sim.idx(a.x, a.y)
	var f := store_field(b, at)
	var d: float = (f[1] as PackedFloat32Array)[at]
	if d >= INF:
		return false
	var n := mini(Sim.PORTER_LOAD, mini(int(float(a.inv.get(res, 0.0))), int(store_room(b, p, res))))
	if n <= 0:
		return false
	var par: PackedInt32Array = f[2]
	var path := PackedInt32Array()
	var c := at
	while c != -1 and path.size() < 5000:
		path.append(c)
		c = par[c]
	var chain := road_carriers_on()
	if chain and plan_chain(p, path, true, false).is_empty():
		return false
	store_add(a, p, res, -float(n))
	if not chain:
		p.busy_porters += 1
	var one_way := d / ((1.0 + sim.mod(p, "carry")) * sim.carry_factor(p))
	var t := Sim.Trip.new()
	t.p = p.id; t.res = res; t.n = n; t.t0 = sim.time; t.t1 = sim.time + one_way + 1.0; t.t2 = t.t1 + one_way
	t.path = path; t.kind = "porter"
	if chain:
		_chain_trip(p, t, path, true)
	sim.trips.append(t)
	return true


## Store s is gone: its goods go to the realm's other stores as far as they have room.
func store_lost(s: Sim.Bld, p: Sim.Player) -> void:
	var lost := 0
	for k in s.inv.keys():
		var n := float(s.inv[k])
		store_add(s, p, k, -n)
		lost += int(n - give(p, k, n, sim.idx(s.x, s.y), s))
	s.inv = {}
	if lost > 0 and not p.ai and p.alive:
		sim.emit_log("A store was lost: %d goods had nowhere to go." % lost, Color("e08a6a"), Vector2i(s.x, s.y))


## For tests: whether every realm's stock is exactly the total of its stores.
func stock_matches() -> String:
	for p in sim.players:
		var sum := {}
		for s: Sim.Bld in stores_of(p):
			for k in s.inv:
				sum[k] = float(sum.get(k, 0.0)) + float(s.inv[k])
		for k in p.stock:
			if absf(float(p.stock[k]) - float(sum.get(k, 0.0))) > 0.01:
				return "%s %s: stock %.2f, stores %.2f" % [p.name, k, float(p.stock[k]), float(sum.get(k, 0.0))]
	return ""


func capacity(p: Sim.Player, res: String) -> float:
	return p.store_total * GameData.res_cap(res) / 80.0 * (1.0 + sim.mod(p, "store"))


## The production target for a good: how many the realm wants to keep in stock, or -1 for no limit.
## Tools keep TOOL_TARGET of each unless the player sets something else.
func target_of(p: Sim.Player, res: String) -> int:
	if p.targets.has(res):
		return int(p.targets[res])
	return Sim.TOOL_TARGET if GameData.is_tool_res(res) else -1


## Tools of each kind made but not yet in store: waiting at the toolsmith or on a carrier's back.
func _tools_coming(p: Sim.Player) -> Dictionary:
	var out := {}
	for b: Sim.Bld in realm_blds(p):
		if b.def.has("makes_tools"):
			for k in b.out_buf:
				out[k] = int(out.get(k, 0)) + int(b.out_buf[k])
	for t in sim.trips:
		if t.p == p.id and not t.delivered and t.dest == 0 and GameData.is_tool_res(t.res):
			out[t.res] = int(out.get(t.res, 0)) + t.n
	return out


## The tool most wanted: buildings waiting for one count first, then the shortfall against the target.
## Returns "" when every tool is in stock.
func wanted_tool(p: Sim.Player) -> String:
	var coming := _tools_coming(p)
	var best := ""
	var best_need := 0.0
	for t: String in GameData.tool_ids:
		var tg := target_of(p, t)
		var need := float(p.tool_wait.get(t, 0)) * 2.0 + float(maxi(tg, 0)) - float(p.stock.get(t, 0.0)) - float(coming.get(t, 0))
		if need > best_need:
			best_need = need
			best = t
	return best


## The tool a new worker needs to start at building b, or "" if none (tools switched off in the
## difficulty options, a trade without a tool, or a toolsmith, who makes his own).
func tool_of(b: Sim.Bld) -> String:
	if not bool(sim.opts.tools) or b.def.has("makes_tools"):
		return ""
	return GameData.tool_for(GameData.trade(b.ty))


## Whether building b can take on a worker: an idle specialist of its trade brings his own tool,
## a newcomer needs one from the stores. Remembers what is missing so the toolsmith can make it.
func _can_hire(p: Sim.Player, b: Sim.Bld) -> bool:
	b.need_tool = ""
	var tool := tool_of(b)
	if tool == "" or not (p.spec.get(sim.spec_key(b), []) as Array).is_empty():
		return true
	if float(p.stock.get(tool, 0.0)) >= 1.0:
		return true
	b.need_tool = tool
	p.tool_wait[tool] = int(p.tool_wait.get(tool, 0)) + 1
	return false


func _recount_stores(p: Sim.Player) -> void:
	var t := 0
	var porters := 0
	for b in sim.blds:
		if b.p == p.id and b.state == "ready" and is_store(b):
			t += int(b.def.store)
			porters += int(b.def.get("porters", 0))
	p.store_total = t
	p.store_porters = porters


## After a store is lost, goods beyond the remaining room are lost too.
func _clamp_stock(_p: Sim.Player) -> void:
	pass    # since build 31 a lost store hands its goods on itself (store_lost)


## Porters free right now: those employed by the stores plus idle peasants, minus those out on the road.
func porters_free(p: Sim.Player) -> int:
	return p.store_porters + maxi(0, p.peasant - p.used_peasant) - p.busy_porters


# --- Road carriers (a new-game option, The Settlers style) --------------------------------------------
# Every stretch of road between two flags has its own carrier. Flags stand at buildings, where roads
# meet, and at least every FLAG_EVERY tiles. A load is handed from carrier to carrier at the flags; a
# carrier takes one load at a time and walks back before the next, so goods queue at the flags of busy
# stretches; when a stretch is busy a donkey helps (a second slot). Each load's whole journey is worked
# out when it sets off: on each stretch it starts when the load is at the flag and that stretch's carrier
# (or donkey) is free. A load that would queue too long is not sent yet. As in The Settlers, the stretch
# carriers come from the headquarters and do not use up porters; road_carriers only counts them.

const FLAG_EVERY := 4
const DONKEY_LEG := 1000000
const STRETCH_IDLE := 45.0     # a stretch unused this long gives its carrier back
const MAX_QUEUE := 30.0       # a load that would wait longer than this at flags in all is not sent yet


func road_carriers_on() -> bool:
	return bool(sim.opts.get("road_carriers", false))


func _is_flag(path: PackedInt32Array, k: int, pid: int) -> bool:
	if k == 0 or k == path.size() - 1:
		return true
	var i := path[k]
	if sim.bmap[i] != 0 or sim.players[pid - 1].flags.has(i):
		return true
	var n := 0
	var cx := i % sim.w
	var cy := i / sim.w
	for dd in 4:
		var nx: int = cx + Sim.DOOR_DX[dd]
		var ny: int = cy + Sim.DOOR_DY[dd]
		if sim.inb(nx, ny) and (sim.road[ny * sim.w + nx] == pid or sim.bmap[ny * sim.w + nx] != 0):
			n += 1
	return n >= 3


## Plans a load's journey along path (goods going from path[0] to the end when forward, else back):
## [arrival time, legs], or [] when it would wait more than MAX_QUEUE at flags (the roads are too busy
## now). Stretch carriers come from the headquarters as in The Settlers: they do not use up porters.
## commit: book the stretches (their carriers are busy until the load is through).
func plan_chain(p: Sim.Player, path: PackedInt32Array, forward: bool, commit: bool) -> Array:
	var n := path.size()
	if n < 2:
		return [sim.time, PackedFloat32Array()]
	var order := PackedInt32Array()
	for k in n:
		order.append(k if forward else n - 1 - k)
	var flags := PackedInt32Array([order[0]])
	var since := 0
	for j in range(1, n):
		since += 1
		if j == n - 1 or since >= FLAG_EVERY or _is_flag(path, order[j], p.id):
			flags.append(order[j]); since = 0
	var spd := (1.0 + sim.mod(p, "carry")) * sim.carry_factor(p)
	var tnow := sim.time + 0.5
	var waited := 0.0
	var new_donkeys := 0
	var legs := PackedFloat32Array()
	var need := 0
	var books := []
	for f in range(flags.size() - 1):
		var a := flags[f]
		var b := flags[f + 1]
		var key := mini(path[a], path[b]) * sim.w * sim.h + maxi(path[a], path[b])
		var cost := 0.0
		var step := 1 if b > a else -1
		var k := a
		while k != b:
			cost += step_cost(path[k], path[k + step])
			k += step
		cost /= spd
		# the stretch's carrier and a second carrier (x, y), and on a busy stretch a donkey too (z), as in
		# The Settlers: each the time it is free again
		var slots := Vector3(-1e9, -1e9, -1e9)
		if p.segs.has(key):
			var v = p.segs[key]
			slots = Vector3(v.x, v.y, -1e9) if v is Vector2 else v   # (build 33 saves had no donkeys)
		var slot := 0
		var free_at := slots.x
		if slots.x > tnow + 2.0 and slots.y < slots.x:
			slot = 1
			free_at = slots.y
		# still a wait: a donkey helps, where one is out already or a free one is in store
		var donkey_here := slots.z >= sim.time - STRETCH_IDLE
		if free_at > tnow + 2.0 and slots.z < free_at and (donkey_here or p.donkeys_used + new_donkeys < int(float(p.stock.get("donkey", 0.0)))):
			slot = 2
			free_at = slots.z
			if not donkey_here:
				new_donkeys += 1
		var start := maxf(tnow, free_at)
		waited += start - tnow
		if maxf(slots.x, slots.y) < sim.time - STRETCH_IDLE:
			need += 1                # a stretch nobody used for a while gets its carrier back
		var end := start + cost
		# (a donkey's leg is marked by DONKEY_LEG added to its end index, for drawing)
		legs.append_array(PackedFloat32Array([a, b + (DONKEY_LEG if slot == 2 else 0), start, end]))
		# the carrier walks back before he takes the next load (half way on average: he often
		# meets the next one at the far flag)
		if slot == 0:
			slots.x = end + cost * 0.5
		elif slot == 1:
			slots.y = end + cost * 0.5
		else:
			slots.z = end + cost * 0.5
		books.append([key, slots])
		tnow = end
	# roads this busy take no more loads for now: they go when the queue has shrunk
	if waited > MAX_QUEUE:
		return []
	if commit:
		for bk in books:
			p.segs[bk[0]] = bk[1]
		p.road_carriers += need
		p.donkeys_used += new_donkeys
	return [tnow + 0.5, legs]


## Once a second: stretches nobody used for a while give their carriers back; counts the rest.
func road_carrier_tick(p: Sim.Player) -> void:
	if p.segs.is_empty():
		p.road_carriers = 0
		return
	var keys := p.segs.keys()
	keys.sort()
	var n := 0
	var dk := 0
	for k in keys:
		var v = p.segs[k]
		var sl: Vector3 = Vector3(v.x, v.y, -1e9) if v is Vector2 else v
		if maxf(maxf(sl.x, sl.y), sl.z) < sim.time - STRETCH_IDLE:
			p.segs.erase(k)
		else:
			n += 1
			if sl.z >= sim.time - STRETCH_IDLE:
				dk += 1
	p.road_carriers = n
	p.donkeys_used = dk
	# rivals (and only they) split their busiest stretches with a flag every half minute
	if p.ai and int(sim.time) % 30 == p.id % 30:
		_ai_flags(p, keys)


## A rival sets a flag halfway along stretches where loads queue (the carrier booked well ahead), the
## way a Settlers player splits a jammed road. Only road tiles that are not already flags or buildings.
func _ai_flags(p: Sim.Player, keys: Array) -> void:
	var N := sim.w * sim.h
	var placed := 0
	for k in keys:
		if not p.segs.has(k) or placed >= 3:
			continue
		var sl = p.segs[k]
		if sl.x < sim.time + 12.0:
			continue
		var a: int = k / N
		var b: int = k % N
		var mx := (a % sim.w + b % sim.w) / 2
		var my := (a / sim.w + b / sim.w) / 2
		var best := -1
		var bd := 99
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if not sim.inb(mx + dx, my + dy):
					continue
				var i := sim.idx(mx + dx, my + dy)
				if i == a or i == b or sim.road[i] != p.id or sim.bmap[i] != 0 or p.flags.has(i):
					continue
				var d := absi(dx) + absi(dy)
				if d < bd:
					bd = d; best = i
		if best >= 0:
			p.flags[best] = true
			placed += 1


## Road carriers mode: the player sets or takes away a flag on one of his roads (a flag splits a stretch).
func toggle_flag(x: int, y: int, pid: int) -> String:
	if not sim.inb(x, y):
		return "Click one of your roads."
	var i := sim.idx(x, y)
	if sim.road[i] != pid or sim.bmap[i] != 0:
		return "Flags go on your own roads."
	var p := sim.players[pid - 1]
	if p.flags.has(i):
		p.flags.erase(i)
		return "Flag taken away."
	p.flags[i] = true
	return "Flag set: the stretch is split here." if road_carriers_on() else "Flag set. Flags matter in games with road carriers (a new-game option)."



## A porter trip t along path in road carriers mode: plans and books it. False if it cannot go now.
func _chain_trip(p: Sim.Player, t: Sim.Trip, path: PackedInt32Array, forward: bool) -> bool:
	var plan := plan_chain(p, path, forward, true)
	if plan.is_empty():
		return false
	t.t0 = sim.time
	t.t1 = float(plan[0])
	t.t2 = t.t1                  # no walk home: the carriers stay on their stretches
	t.legs = plan[1]
	t.station = -1               # marks a chain: no porter to free at the end
	return true


func _rebuild_realm_lists() -> void:
	_pb = []
	_stations = []
	for p in sim.players:
		_pb.append([])
		_stations.append([])
	for b in sim.blds:
		_pb[b.p - 1].append(b)
		if b.def.has("carriers") and b.state == "ready" and b.staffed and b.working:
			_stations[b.p - 1].append(b)


## The buildings of realm p (refreshed once a second).
func realm_blds(p: Sim.Player) -> Array:
	if _pb.size() != sim.players.size():
		_rebuild_realm_lists()
	return _pb[p.id - 1]


func mil_list() -> Array:
	if sim._mil_dirty:
		_mil = []
		for b in sim.blds:
			if sim.is_mil(b):
				_mil.append(b)
		sim._mil_dirty = false
	return _mil


## Sends carriers with materials from the stores to construction sites, high-priority sites first,
## then the oldest. Goods leave the store only when a carrier picks them up; nothing is reserved.
func _dispatch_supply() -> void:
	if sim._supply.is_empty():
		return
	var buckets := [[], [], []]
	for id in sim._supply:
		var b: Sim.Bld = sim.by_id.get(id)
		if b == null or b.need.is_empty() or (b.state != "build" and b.reno_to < 0):
			continue
		if b.prio == Sim.PRIO_PAUSED:
			continue
		buckets[Sim.PRIO_HIGH - b.prio].append(b)
	for list: Array in buckets:
		list.sort_custom(func(a, c): return a.id < c.id)
		for b: Sim.Bld in list:
			var p := sim.players[b.p - 1]
			if porters_free(p) <= 0 and (_stations[b.p - 1] as Array).is_empty() and not road_carriers_on():
				continue
			# a site holds only a few loads at a time, so materials go where work can go on
			var waiting := 0
			for k in b.onsite:
				waiting += int(b.onsite[k])
			for k in b.coming:
				waiting += int(b.coming[k])
			if waiting >= 6:
				continue
			var res := ""
			for k in b.need:
				if float(p.stock.get(k, 0.0)) >= 1.0:
					res = k
					break
			if res == "":
				continue
			var n := carry_to(b, p, res, int(b.need[res]), true)
			if n <= 0:
				continue
			b.need[res] = int(b.need[res]) - n
			if int(b.need[res]) <= 0:
				b.need.erase(res)
			b.coming[res] = int(b.coming.get(res, 0)) + n
			if b.need.is_empty():
				sim._supply.erase(b.id)


## The store a carrier fetches res from for building b: the nearest by road that has some, and the road
## from b to it. [store, path from b to the store, walking time] or [] when no store has any.
func source_for(p: Sim.Player, b: Sim.Bld, res: String) -> Array:
	var bt := sim.idx(b.x, b.y)
	var path := store_path(b)
	if path.size() >= 2:
		var sn: Sim.Bld = sim.by_id.get(sim.bmap[path[path.size() - 1]])
		if sn != null and float(sn.inv.get(res, 0.0)) >= 1.0:
			return [sn, path, net_dist(b.p, bt)]
	var best: Sim.Bld = null
	var bd := INF
	var bf: Array = []
	for s: Sim.Bld in stores_of(p):
		if float(s.inv.get(res, 0.0)) < 1.0:
			continue
		var f := store_field(s, bt)
		var d: float = (f[1] as PackedFloat32Array)[bt]
		if d < bd or (d == bd and best != null and s.id < best.id):
			bd = d; best = s; bf = f
	if best == null or bd == INF:
		return []
	var par: PackedInt32Array = bf[2]
	var pth := PackedInt32Array()
	var c := bt
	while c != -1 and pth.size() < 5000:
		pth.append(c)
		c = par[c]
	return [best, pth, bd]


var _sfield := {}          # store id -> [road network version, walking times from it, way back to it]

## Walking times over its realm's roads from store s, and the way back to s (the same search as
## _build_net, from this one store), worked out only as far as tile `to` (-1: everywhere). The search
## is kept half done and carried on when a farther tile is asked for, so asking about a nearby
## building costs little; it starts again when the network changes. Pausing never changes the order
## the search visits tiles in, so the answers are the same as a full search (and after loading).
## Returns [network version, walking times, way back, tiles settled, search heap].
func store_field(s: Sim.Bld, to := -1) -> Array:
	var k := s.p - 1
	_net_ready(s.p)
	var e = _sfield.get(s.id)
	if e == null or int(e[0]) != int(net_ver[k]):
		var dist := PackedFloat32Array(); dist.resize(sim.w * sim.h); dist.fill(INF)
		var par := PackedInt32Array(); par.resize(sim.w * sim.h); par.fill(-1)
		var done := PackedByteArray(); done.resize(sim.w * sim.h)
		var hp0 := Sim.MinHeap.new()
		var st0 := sim.idx(s.x, s.y)
		dist[st0] = 0.0
		hp0.push(0.0, st0)
		e = [int(net_ver[k]), dist, par, done, hp0]
		_sfield[s.id] = e
	var done2: PackedByteArray = e[3]
	if to >= 0 and done2[to] == 1:
		return e
	var hp: Sim.MinHeap = e[4]
	if hp.size() == 0:
		return e
	var dist2: PackedFloat32Array = e[1]
	var par2: PackedInt32Array = e[2]
	var pid := s.p
	var st := sim.idx(s.x, s.y)
	while hp.size() > 0:
		var cur := hp.pop()
		if done2[cur] == 1:
			continue
		done2[cur] = 1
		if sim.bmap[cur] != 0 and cur != st and not is_store(sim.by_id.get(sim.bmap[cur])):
			if cur == to: break
			continue
		var cx := cur % sim.w
		var cy := cur / sim.w
		for dd in 4:
			var nx := cx + (1 if dd == 0 else (-1 if dd == 1 else 0))
			var ny := cy + (1 if dd == 2 else (-1 if dd == 3 else 0))
			if nx < 0 or ny < 0 or nx >= sim.w or ny >= sim.h:
				continue
			var ni := ny * sim.w + nx
			if done2[ni] == 1 or sim.owner[ni] != pid:
				continue
			if sim.bmap[ni] != 0:
				var nb: Sim.Bld = sim.by_id.get(sim.bmap[ni])
				if nb == null or nb.p != pid:
					continue
			elif sim.road[ni] != pid:
				continue
			if (sim.bmap[cur] != 0 or sim.bmap[ni] != 0) and not sim.links(cur, ni):
				continue
			_f32[0] = dist2[cur] + step_cost(cur, ni)
			var nd := _f32[0]
			if nd < dist2[ni] or (nd == dist2[ni] and cur < par2[ni]):
				var better := nd < dist2[ni]
				dist2[ni] = nd
				par2[ni] = cur
				if better: hp.push(nd, ni)
		if cur == to:
			break
	# packed arrays are copied on write: put the updated ones back
	e[1] = dist2; e[2] = par2; e[3] = done2
	return e


## Sends a carrier with up to `want` of res from the nearest store that has it to building b: to a
## construction site (site true) or as input for its work. A mule or ox cart takes it when one is
## free close by, else a porter. Returns how many he carries (0: no store has any, or nobody free).
func carry_to(b: Sim.Bld, p: Sim.Player, res: String, want: int, site: bool) -> int:
	var src := source_for(p, b, res)
	if src.is_empty():
		return 0
	var s: Sim.Bld = src[0]
	var kind := "porter"
	var speed := 1.0
	var load := Sim.PORTER_LOAD
	var st: Sim.Bld = null
	for m: Sim.Bld in _stations[b.p - 1]:
		var c: Dictionary = m.def.carriers
		if m.busy < int(c.count) and int(c.load) > load and Vector2(m.x - b.x, m.y - b.y).length() <= float(c.range):
			st = m; kind = String(c.kind); speed = float(c.speed); load = int(c.load)
	var chain := st == null and road_carriers_on()
	if chain:
		if plan_chain(p, src[1], false, false).is_empty():
			return 0
	elif st == null and porters_free(p) <= 0:
		return 0
	var n := mini(mini(load, want), int(float(s.inv.get(res, 0.0))))
	if n <= 0:
		return 0
	if chain:
		pass
	elif st == null:
		p.busy_porters += 1
	else:
		st.busy += 1
	store_add(s, p, res, -float(n))
	if site:
		sim.used(p, res, float(n))
	else:
		b.incoming[res] = int(b.incoming.get(res, 0)) + n
	var one_way := float(src[2]) / (speed * ((1.0 + sim.mod(p, "carry")) * sim.carry_factor(p)))
	var t := Sim.Trip.new()
	t.p = p.id; t.res = res; t.n = n; t.t0 = sim.time; t.t1 = sim.time + one_way + 1.0; t.t2 = t.t1 + one_way
	t.path = src[1]; t.kind = kind; t.station = st.id if st != null else 0
	if chain:
		_chain_trip(p, t, t.path, false)
	if site:
		t.site = b.id
	else:
		t.dest = b.id
		# room left in the load: take another input this building is short of from the same store
		if n < load:
			var inp: Dictionary = b.def.get("in", {})
			var cyc := b.keep if b.keep > 0 else 2
			var ks := inp.keys()
			ks.sort()
			for k2: String in ks:
				if k2 == res or k2 == "food":
					continue
				var short := int(inp[k2]) * cyc - int(b.inbuf.get(k2, 0)) - int(b.incoming.get(k2, 0))
				var n2 := mini(mini(short, load - n), int(float(s.inv.get(k2, 0.0))))
				if n2 > 0:
					store_add(s, p, k2, -float(n2))
					b.incoming[k2] = int(b.incoming.get(k2, 0)) + n2
					t.res2 = k2; t.n2 = n2
					break
	sim.trips.append(t)
	return n


var _inb_at := -1
var _inb := {}             # realm id -> its buildings that use goods, by id

func _input_blds(p: Sim.Player) -> Array:
	if _inb_at != _store_ver:
		_inb_at = _store_ver
		_inb = {}
		for b in sim.blds:
			if not b.dead and b.def.has("in"):
				if not _inb.has(b.p):
					_inb[b.p] = []
				(_inb[b.p] as Array).append(b)
	return _inb.get(p.id, [])


## Food (any kind) at building b or on its way there.
func food_at(b: Sim.Bld, with_coming := true) -> int:
	var n := 0
	for f in GameData.food_ids:
		n += int(b.inbuf.get(f, 0))
		if with_coming:
			n += int(b.incoming.get(f, 0))
	return n


## Carriers bring workshops, mines and the like what they use, from the nearest store that has it, so
## each keeps enough for two work cycles. One load per building per round; high priority first.
func _dispatch_inputs() -> void:
	for p in sim.players:
		if not p.alive:
			continue
		var buckets := [[], [], []]
		for b: Sim.Bld in _input_blds(p):
			if b.dead or b.state != "ready" or not b.staffed or b.prio == Sim.PRIO_PAUSED or b.reno_to >= 0:
				continue
			buckets[Sim.PRIO_HIGH - b.prio].append(b)
		var out_of_carriers := false
		for list: Array in buckets:
			if out_of_carriers:
				break
			for b: Sim.Bld in list:
				if porters_free(p) <= 0 and (_stations[p.id - 1] as Array).is_empty() and not road_carriers_on():
					out_of_carriers = true     # this realm's carriers are all out; the next realm's turn
					break
				var inp: Dictionary = b.def["in"]
				for k in inp:
					# enough for two work cycles; food for one, so less of it sits about in workshops
					var cyc := b.keep if b.keep > 0 else 2
					var want := int(inp[k]) * (maxi(1, cyc / 2) if k == "food" else cyc)
					var have := food_at(b) if k == "food" else int(b.inbuf.get(k, 0)) + int(b.incoming.get(k, 0))
					if have >= want:
						continue
					var res := String(k)
					if k == "food":
						res = ""
						for f in GameData.food_ids:
							if float(p.stock.get(f, 0.0)) >= 1.0:
								res = f
								break
						if res == "":
							continue
					elif float(p.stock.get(k, 0.0)) < 1.0:
						continue
					if carry_to(b, p, res, want - have, false) > 0:
						break


## A carrier brought inputs to building b. If it is gone or changed hands, they go back to a store.
func input_arrival(t: Sim.Trip, p: Sim.Player) -> void:
	var b: Sim.Bld = sim.by_id.get(t.dest)
	if b != null and b.p == t.p:
		b.incoming[t.res] = int(b.incoming.get(t.res, 0)) - t.n
		if int(b.incoming[t.res]) <= 0:
			b.incoming.erase(t.res)
	if b != null and b.p == t.p and t.n2 > 0:
		b.incoming[t.res2] = int(b.incoming.get(t.res2, 0)) - t.n2
		if int(b.incoming[t.res2]) <= 0:
			b.incoming.erase(t.res2)
	if b != null and not b.dead and b.p == t.p and b.state == "ready":
		b.inbuf[t.res] = int(b.inbuf.get(t.res, 0)) + t.n
		if t.n2 > 0:
			b.inbuf[t.res2] = int(b.inbuf.get(t.res2, 0)) + t.n2
		b.retry = 0.0
	elif p.alive:
		give(p, t.res, float(t.n), t.path[0] if t.path.size() > 0 else -1)
		if t.n2 > 0:
			give(p, t.res2, float(t.n2), t.path[0] if t.path.size() > 0 else -1)


## Sends free carriers to buildings with goods waiting. Carts first, then mules, then porters.
func _dispatch() -> void:
	if _stations.size() != sim.players.size():
		_rebuild_realm_lists()
	_dispatch_supply()
	# goods from high-priority buildings are picked up first, from low-priority ones last
	var buckets := [[], [], [], []]
	for id in sim._pending:
		var pb: Sim.Bld = sim.by_id.get(id)
		buckets[Sim.PRIO_HIGH - (pb.prio if pb != null else Sim.PRIO_NORMAL)].append(id)
	# oldest building first within each priority, so the order never depends on how the list was
	# filled (a loaded game rebuilds it in another order, and must go on exactly the same)
	for bk: Array in buckets:
		bk.sort()
	for id in buckets[0] + buckets[1] + buckets[2] + buckets[3]:
		if not sim._pending.has(id):
			continue
		var b: Sim.Bld = sim.by_id.get(id)
		if b == null or b.out_buf.is_empty():
			sim._pending.erase(id)
			continue
		var p := sim.players[b.p - 1]
		if porters_free(p) <= 0 and (_stations[b.p - 1] as Array).is_empty() and not road_carriers_on():
			continue
		var path := store_path(b)
		if path.is_empty():
			continue
		var res: String = b.out_buf.keys()[0]
		var have := int(b.out_buf[res])
		var kind := "porter"
		var speed := 1.0
		var load := Sim.PORTER_LOAD
		var st: Sim.Bld = null
		for s: Sim.Bld in _stations[b.p - 1]:
			var c: Dictionary = s.def.carriers
			if s.busy < int(c.count) and int(c.load) > load and Vector2(s.x - b.x, s.y - b.y).length() <= float(c.range):
				st = s; kind = String(c.kind); speed = float(c.speed); load = int(c.load)
		var chain := st == null and road_carriers_on()
		if chain:
			if plan_chain(p, path, true, false).is_empty():
				continue
		elif st == null:
			if porters_free(p) <= 0:
				continue
			p.busy_porters += 1
		else:
			st.busy += 1
		var n := mini(load, have)
		if n >= have:
			b.out_buf.erase(res)
		else:
			b.out_buf[res] = have - n
		var one_way := net_dist(b.p, sim.idx(b.x, b.y)) / (speed * ((1.0 + sim.mod(p, "carry")) * sim.carry_factor(p)))
		var t := Sim.Trip.new()
		t.p = p.id; t.res = res; t.n = n; t.t0 = sim.time; t.t1 = sim.time + one_way + 1.0; t.t2 = t.t1 + one_way
		t.path = path; t.kind = kind; t.station = st.id if st != null else 0
		if chain:
			_chain_trip(p, t, path, true)
		sim.trips.append(t)
		if b.out_buf.is_empty():
			sim._pending.erase(id)
	_dispatch_inputs()


func _free_carrier(t: Sim.Trip) -> void:
	if t.kind == "ship":
		var sp := sim.players[t.p - 1]
		sp.ships_out = maxi(0, sp.ships_out - 1)   # the ship is home again
		return
	if t.kind == "builder" or t.kind == "soldier" or t.kind == "worker" or t.kind == "trade":
		return                     # builders, soldiers, workers and trade carts are not carriers
	if t.station < 0:
		return                     # road carriers mode: the carriers stay on their stretches
	if t.station != 0:
		var s: Sim.Bld = sim.by_id.get(t.station)
		if s != null:
			s.busy = maxi(0, s.busy - 1)
	else:
		var p := sim.players[t.p - 1]
		p.busy_porters = maxi(0, p.busy_porters - 1)


## Neighbouring tiles of c that are realm pid's roads or buildings (roads end at buildings).
func _road_nbrs(c: int, pid: int) -> Array:
	var out := []
	var cx := c % sim.w
	var cy := c / sim.w
	for dd in 4:
		var nx := cx + (1 if dd == 0 else (-1 if dd == 1 else 0))
		var ny := cy + (1 if dd == 2 else (-1 if dd == 3 else 0))
		if nx < 0 or ny < 0 or nx >= sim.w or ny >= sim.h:
			continue
		var ni := ny * sim.w + nx
		if (sim.road[ni] == pid or (sim.bmap[ni] != 0 and (sim.by_id.get(sim.bmap[ni]) as Sim.Bld).p == pid)) and sim.links(c, ni):
			out.append(ni)
	return out


## Lays a road from (sx, sy) to (gx, gy). It must start on one of your roads or buildings.
func build_road(sx: int, sy: int, gx: int, gy: int, pid: int) -> String:
	if not sim.inb(sx, sy) or not sim.inb(gx, gy):
		return "Outside the map"
	var s := sim.idx(sx, sy)
	var g := sim.idx(gx, gy)
	var sb := sim.bld_at(sx, sy)
	if sim.road[s] != pid and (sb == null or sb.p != pid):
		return "Start a road on one of your roads or buildings."
	if s == g:
		return "Pick a different end tile."
	if sim.owner[g] != pid:
		return "Roads must stay inside your territory."
	var gb := sim.bld_at(gx, gy)
	if gb != null and gb.p != pid:
		return "That building is not yours."
	if gb == null and (sim.ter[g] == Sim.WATER or sim.deco[g] == Sim.D_ROCK or sim.deco[g] == Sim.D_CLAY):
		return "A road cannot end there."
	var path := find_path(sx, sy, gx, gy, pid)
	if path.is_empty():
		return "There is no way through for a road."
	var why := bridge_cost_ok(path, pid)
	if why != "":
		return why
	lay_road(path, pid)
	return ""


## Removes the stretch of road through (x, y), up to the next junctions or buildings.
## Clicking a junction removes only that tile. Returns how many tiles were removed.
func remove_road(x: int, y: int, pid: int) -> int:
	if not sim.inb(x, y):
		return 0
	var i := sim.idx(x, y)
	if sim.road[i] != pid or sim.bmap[i] != 0:
		return 0
	var removed := PackedInt32Array()
	if _road_nbrs(i, pid).size() >= 3:
		removed.append(i)
	else:
		var stack := [i]
		var seen := {i: true}
		while stack.size() > 0:
			var c: int = stack.pop_back()
			var nb := _road_nbrs(c, pid)
			if c != i and nb.size() >= 3:
				continue
			removed.append(c)
			for n in nb:
				if not seen.has(n) and sim.bmap[n] == 0:
					seen[n] = true
					stack.append(n)
	for c in removed:
		sim.road[c] = 0
		sim.pave[c] = 0
		sim.changed_tiles.append(c)
	net_dirty(pid)
	return removed.size()


## Paves up to 12 connected road tiles around (x, y) with stone, 1 stone per tile.
func pave_road(x: int, y: int, p: Sim.Player) -> String:
	if not sim.inb(x, y) or sim.road[sim.idx(x, y)] != p.id:
		return "Click one of your roads."
	var queue := [sim.idx(x, y)]
	var seen := {sim.idx(x, y): true}
	var count := 0
	var looked := 0
	while queue.size() > 0 and count < 12 and looked < 60:
		var c: int = queue.pop_front()
		looked += 1
		if sim.pave[c] == 0:
			if float(p.stock.get("stone", 0.0)) < 1.0:
				break
			take(p, "stone", 1.0, c)
			sim.pave[c] = 1
			sim.changed_tiles.append(c)
			count += 1
		for n in _road_nbrs(c, p.id):
			if not seen.has(n) and sim.bmap[n] == 0:
				seen[n] = true
				queue.append(n)
	if count == 0:
		return "Not enough stone to pave." if float(p.stock.get("stone", 0.0)) < 1.0 else "This stretch is already paved."
	net_touch(p.id, PackedInt32Array(seen.keys()))
	return ""


func work_center(b: Sim.Bld) -> Vector2i:
	return b.work if b.work.x >= 0 else Vector2i(b.x, b.y)


func work_radius(b: Sim.Bld) -> int:
	return int((b.def.get("work", {}) as Dictionary).get("radius", 0))


## Extra seconds per cycle for walking to a moved work area and back.
func walk_time(b: Sim.Bld) -> float:
	if b.work.x < 0:
		return 0.0
	return Vector2(b.work.x - b.x, b.work.y - b.y).length() * 0.6


## Moves a building's work area so it is centred on (x, y), within the building's move limit.
func set_work_area(b: Sim.Bld, x: int, y: int) -> String:
	var wd: Dictionary = b.def.get("work", {})
	if wd.is_empty():
		return "This building has no work area to move."
	if not sim.inb(x, y):
		return "Outside the map"
	var lim := int(wd.get("move", 6))
	if Vector2(x - b.x, y - b.y).length() > lim + 0.01:
		return "Too far: the work area can move at most %d tiles from the building." % lim
	b.work = Vector2i(-1, -1) if (x == b.x and y == b.y) else Vector2i(x, y)
	b.retry = 0.0
	b.fails = 0
	return ""


## Short status line for a building, for the selection panel.
func status(b: Sim.Bld) -> String:
	var d := b.def
	if b.reno_to >= 0:
		return "Being renovated into the %s style: %d%%%s" % [GameData.age_name(b.reno_to), roundi(b.reno_prog * 100), "" if b.mat_used >= b.mat_total or not b.onsite.is_empty() or b.reno_prog < float(b.mat_used) / maxf(1, b.mat_total) else " (waiting for materials)"]
	if b.state == "build":
		if b.msg == "Waiting for materials":
			var miss := []
			var p := sim.players[b.p - 1]
			for k in b.need:
				if float(p.stock.get(k, 0.0)) < 1.0:
					miss.append(GameData.res_name(k).to_lower())
			if not b.coming.is_empty():
				return "Waiting for materials (on the way) %d%%" % roundi(b.prog * 100)
			if not miss.is_empty():
				return "Waiting for materials: no %s in store" % " or ".join(miss)
			return "Waiting for materials (no free carrier) %d%%" % roundi(b.prog * 100)
		if not b.staffed:
			return "Waiting for a builder (no idle peasants)"
		if b.msg == "Waiting for a road connection":
			return "Waiting for a road to a store"
		return "Under construction %d%%" % roundi(b.prog * 100)
	if b.ty == "hq":
		return "Soldiers in reserve: %d. Stores %d of each good." % [sim.players[b.p - 1].reserve, int(d.store)]
	if d.has("store"):
		return "Store: room for %d more of each good" % int(d.store)
	if d.has("carriers"):
		var c: Dictionary = d.carriers
		return "%d of %d %ss out on the road%s" % [b.busy, int(c.count), String(c.kind), "" if b.working else " (%s)" % (b.msg if b.msg != "" else "idle")]
	if d.has("vision"):
		return ("Lookout: a scout watches %d tiles around" % int(d.vision)) if b.staffed else "No scout inside (train scouts at a scout lodge)"
	if d.has("garrison"):
		return "Garrison %d/%d%s" % [b.garrison, int(d.garrison), "" if b.garrison > 0 else " (empty, claims no land)"]
	if d.has("housing"):
		return "Homes for %d people" % int(d.housing)
	if b.working:
		return "Working %d%%" % roundi(sim.work_progress(b) * 100)
	return b.msg if b.msg != "" else "Idle"


## The shortest walk over land (8 directions) from tile a towards tile b. If b can't be reached,
## it ends at the reachable land tile closest to b.
func land_path(a: int, b: int) -> PackedInt32Array:
	var w := sim.w
	var h := sim.h
	var par := PackedInt32Array()
	par.resize(w * h)
	par.fill(-2)
	par[a] = -1
	var q := PackedInt32Array([a])
	var head := 0
	var bx := b % w
	var by := b / w
	var best := a
	var bd := 1e9
	while head < q.size():
		var c := q[head]
		head += 1
		var cx := c % w
		var cy := c / w
		var d := Vector2(cx - bx, cy - by).length_squared()
		if d < bd:
			bd = d; best = c
		if c == b:
			break
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var nx: int = cx + dx
				var ny: int = cy + dy
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var ni := ny * w + nx
				if par[ni] != -2 or sim.ter[ni] == Sim.WATER:
					continue
				par[ni] = c
				q.append(ni)
	var out := PackedInt32Array()
	var c2 := best
	while c2 != -1 and out.size() < 4000:
		out.append(c2)
		c2 = par[c2]
	out.reverse()
	return out
