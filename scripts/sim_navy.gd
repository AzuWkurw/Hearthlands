class_name SimNavy
extends RefCounted
## Warships, coastal forts' guns, field depots and generals (build 52).
##
## Warships: a naval yard on the coast builds them (planks, iron and weapons). Each sails out of the
## nearest harbour and guards the water within GUARD_R tiles of it: it chases enemy warships, fires on
## enemy landing fleets that come near and sinks enemy cargo ships and expeditions. With Player.escort
## on, up to ESCORTS free warships sail with each landing the realm sends, to shield it. Warships are
## dictionaries in Sim.navy (saved with the game): p, home (the harbour it guards), x, y (tiles), hp,
## esc (the uid of the landing it escorts, 0: none), id, gx, gy (where it is sailing), dx (facing).
##
## Coastal forts: while soldiers hold one, its guns fire every few seconds on enemy warships, landing
## fleets and cargo ships in range.
##
## Field depots: carriers fill them with food; an army attacking a building near one eats from it at
## the gate (SimMilitary._eat), so a siege far from home can last.
##
## Generals: each realm has one. He leads the first column of five or more that sets out while he is at
## home, and helps it win its fights (GEN_DUEL a duel for each level). He learns from every enemy his
## column kills and every building it takes (GENERAL_XP); if his column is wiped out he falls, and a
## new general (who knows nothing yet) is ready GENERAL_BACK seconds later.

var sim: Sim

const MAX_WARSHIPS := 8
const SPEED := 2.2          # tiles a second
const GUARD_R := 9.0        # how far from its harbour a warship patrols
const SEE := 6.0            # how far it spots a target
const GUARD_OUT := 14.0     # a guard goes out this much further than it patrols, to meet what comes
const GUN_R := 3.0          # how near it must be to fire
const HP := 3
const HIT := 0.35           # warship against warship, a second
const HIT_FLEET := 0.4      # a soldier on a landing fleet killed, a second
const FLEET_HITS := 0.12    # a landing fleet's soldiers hit back
const ESCORTS := 3

const GENERAL_XP := [0.0, 5.0, 15.0, 35.0, 70.0]
const GEN_DUEL := 0.02
const GENERAL_BACK := 180.0
const GENERAL_MIN := 5      # soldiers a column needs for the general to lead it

const DEPOT_R := 14.0

## Gun flashes and shots to draw: [from, to, time] (only for the eye: not saved).
var fx: Array = []

var _comp := PackedInt32Array()   # land areas (see island)


func _init(p_sim: Sim) -> void:
	sim = p_sim


# ---------------------------------------------------------------- warships
func ships_of(p: Sim.Player) -> Array:
	return sim.navy.filter(func(w): return int(w.p) == p.id)


## A naval yard finished a warship: it puts to sea from the nearest harbour (or from the yard).
func launch(p: Sim.Player, yard: Sim.Bld) -> void:
	if p.warships >= MAX_WARSHIPS:
		return
	var home := yard
	var bd := 1e9
	for h: Sim.Bld in sim.sea.harbours(p):
		var d := Vector2(h.x - yard.x, h.y - yard.y).length()
		if d < bd:
			bd = d; home = h
	var moor := sim.sea._moorings(home.x, home.y)
	if moor.is_empty():
		moor = sim.sea._moorings(yard.x, yard.y)
		home = yard
	if moor.is_empty():
		return
	var mi: int = moor[0]
	sim._bid += 1
	p.warships += 1
	sim.navy.append({"p": p.id, "home": home.id, "x": float(mi % sim.w), "y": float(mi / sim.w), "hp": HP, "esc": 0,
		"id": sim._bid, "gx": float(mi % sim.w), "gy": float(mi / sim.w), "dx": 1.0})
	if p.id == 1:
		sim.emit_log("A warship puts to sea from your %s (%d afloat)." % [String(home.def.name).to_lower(), p.warships], Color("a0d070"), Vector2i(home.x, home.y))


func _water(x: float, y: float) -> bool:
	var tx := floori(x + 0.5)
	var ty := floori(y + 0.5)
	return sim.inb(tx, ty) and sim.ter[sim.idx(tx, ty)] == Sim.WATER


## Moves warship w toward (tx, ty) over water, turning aside around land. True once there (or stuck).
func _sail(w: Dictionary, tx: float, ty: float, dt: float) -> bool:
	var pos := Vector2(w.x, w.y)
	var d := Vector2(tx, ty) - pos
	if d.length() < 0.3:
		return true
	var stepv := d.normalized() * minf(SPEED * dt, d.length())
	for ang in [0.0, 0.5, -0.5, 1.0, -1.0]:
		var np := pos + stepv.rotated(ang)
		if _water(np.x, np.y):
			w.x = np.x
			w.y = np.y
			if absf(np.x - pos.x) > 0.01:
				w.dx = signf(np.x - pos.x)
			return false
	return true


## Sails warship w toward (tx, ty): straight on while the water is open, else along a way found over
## the water (kept in w.way for a few seconds, then looked for again, as the target moves). True once
## there, or when there is no way.
func _go(w: Dictionary, tx: float, ty: float, dt: float) -> bool:
	var way: Array = w.get("way", [])
	if not way.is_empty() and sim.time - float(w.get("way_t", 0.0)) > 4.0:
		way = []
	if way.is_empty():
		var d0 := Vector2(w.x, w.y).distance_to(Vector2(tx, ty))
		if d0 < 0.5:
			return true
		if not _sail(w, tx, ty, dt) and Vector2(w.x, w.y).distance_to(Vector2(tx, ty)) < d0 - SPEED * dt * 0.4:
			return false
		# blocked by land: find the way round (not again for a while if there is none)
		if sim.time < float(w.get("noway", -1.0)):
			return true
		var path := _water_way(floori(float(w.x) + 0.5), floori(float(w.y) + 0.5), tx, ty)
		if path.size() < 2:
			w.noway = sim.time + 3.0
			return true
		way = Array(path)
		w.way_t = sim.time
	var nxt: int = way[0]
	if _sail(w, float(nxt % sim.w), float(nxt / sim.w), dt):
		way.pop_front()
	w.way = way
	return false


## The way over water from tile (ax, ay) to within a tile and a half of (tx, ty): breadth-first, eight
## directions but no cutting across a corner of land (both tiles beside a diagonal step are water), so a
## ship can sail it. Empty when there is none (within a limit).
func _water_way(ax: int, ay: int, tx: float, ty: float) -> PackedInt32Array:
	if not sim.inb(ax, ay) or sim.ter[sim.idx(ax, ay)] != Sim.WATER:
		return PackedInt32Array()
	var start := sim.idx(ax, ay)
	var came := {start: -1}
	var q := PackedInt32Array([start])
	var head := 0
	var found := -1
	var tgt := Vector2(tx, ty)
	while head < q.size() and head < 60000:
		var cur := q[head]
		head += 1
		var cx := cur % sim.w
		var cy := cur / sim.w
		if Vector2(cx, cy).distance_to(tgt) <= 1.5:
			found = cur
			break
		for ddy in range(-1, 2):
			for ddx in range(-1, 2):
				if ddx == 0 and ddy == 0:
					continue
				var nx := cx + ddx
				var ny := cy + ddy
				if not sim.inb(nx, ny):
					continue
				var ni := ny * sim.w + nx
				if came.has(ni) or sim.ter[ni] != Sim.WATER:
					continue
				if ddx != 0 and ddy != 0 and (sim.ter[cy * sim.w + nx] != Sim.WATER or sim.ter[ny * sim.w + cx] != Sim.WATER):
					continue
				came[ni] = cur
				q.append(ni)
	if found < 0:
		return PackedInt32Array()
	var out := PackedInt32Array()
	var c := found
	while c != -1:
		out.append(c)
		c = came[c]
	out.reverse()
	return out


## A new place to sail to on patrol: open water within GUARD_R of its harbour.
func _new_goal(w: Dictionary) -> void:
	var h: Sim.Bld = sim.by_id.get(int(w.home))
	var cx: float = float(h.x) if h != null else float(w.x)
	var cy: float = float(h.y) if h != null else float(w.y)
	for k in 12:
		var gx := cx + (sim.rng.randf() * 2.0 - 1.0) * GUARD_R
		var gy := cy + (sim.rng.randf() * 2.0 - 1.0) * GUARD_R
		if _water(gx, gy):
			w.gx = gx
			w.gy = gy
			return


func pos_of(w: Dictionary) -> Vector2:
	return Vector2(float(w.x), float(w.y))


## Every tick: warships sail; once a second they (and coastal forts) fire.
func tick(dt: float) -> void:
	var second := int(sim.time) != int(sim.time - dt)
	if not sim.navy.is_empty():
		_ships_tick(dt, second)
	if second:
		_forts_fire()
		_generals_check()
		if not fx.is_empty():
			fx = fx.filter(func(e): return sim.time - float(e[2]) < 1.0)


func _ships_tick(dt: float, second: bool) -> void:
	for k in range(sim.navy.size() - 1, -1, -1):
		if k >= sim.navy.size():
			continue
		var w: Dictionary = sim.navy[k]
		var p := sim.players[int(w.p) - 1]
		var home: Sim.Bld = sim.by_id.get(int(w.home))
		if not p.alive or home == null or home.dead or home.p != p.id:
			# its harbour is lost: it makes for another, or is lost with it (once it is not out
			# escorting a landing)
			var hs := sim.sea.harbours(p) if p.alive else []
			if hs.is_empty() and p.alive and int(w.esc) != 0 and sim.military._by_uid(int(w.esc)) != null:
				var fa := sim.military._by_uid(int(w.esc))
				if sim.military.at_sea(fa):
					var fp0 := sim.military.column_pos(fa)
					_go(w, fp0.x - 0.8, fp0.y + 0.6, dt)
					continue
			if hs.is_empty():
				sim.navy.remove_at(k)
				p.warships = maxi(0, p.warships - 1)
				continue
			w.home = (hs[0] as Sim.Bld).id
			home = hs[0]
		# escorting a landing: keep with its fleet while it is at sea
		var esc: Sim.Attack = null
		if int(w.esc) != 0:
			esc = sim.military._by_uid(int(w.esc))
			if esc == null or not sim.military.at_sea(esc):
				w.esc = 0
				esc = null
				_new_goal(w)
		var tgt = _target(w, p, home, esc != null)
		if tgt != null:
			var tp: Vector2 = tgt[1]
			# each closes in from its own side, so they do not pile onto one spot
			var off := Vector2.from_angle(float(w.id) * 2.4) * 1.3
			if pos_of(w).distance_to(tp + off) > 0.4:
				_go(w, tp.x + off.x, tp.y + off.y, dt)
			if second and pos_of(w).distance_to(tp) <= GUN_R:
				_fire(w, p, tgt)
		elif esc != null:
			var fp := sim.military.column_pos(esc)
			_go(w, fp.x - 0.8, fp.y + 0.6, dt)
		elif _go(w, float(w.gx), float(w.gy), dt):
			_new_goal(w)


## What warship w goes for: [kind, position, thing] or null. Enemy warships first, then landing fleets,
## then cargo ships. A guard keeps to the water near its harbour; an escort fights wherever its fleet is.
func _target(w: Dictionary, p: Sim.Player, home: Sim.Bld, escorting: bool):
	var pos := pos_of(w)
	var hp := Vector2(home.x, home.y)
	var cands := []          # [kind, position, thing]
	for o in sim.navy:
		if int(o.p) != p.id and Diplomacy.at_war(sim, p.id, int(o.p)):
			cands.append(["ship", pos_of(o), o])
	if cands.is_empty():
		for a: Sim.Attack in sim.attacks:
			if a.p != p.id and a.n > 0 and sim.military.at_sea(a) and Diplomacy.at_war(sim, p.id, a.p):
				cands.append(["fleet", sim.military.column_pos(a), a])
	if cands.is_empty():
		for t: Sim.Trip in sim.trips:
			if t.kind == "ship" and t.p != p.id and Diplomacy.at_war(sim, p.id, t.p):
				cands.append(["cargo", sim.sea.ship_pos(t), t])
	var best = null
	var bd := 1e9
	for c in cands:
		var cp: Vector2 = c[1]
		var d := pos.distance_to(cp)
		# an escort fights what comes near its fleet; a guard, whatever enters the water it guards
		if d <= SEE or (not escorting and hp.distance_to(cp) <= GUARD_R + GUARD_OUT):
			if d < bd:
				bd = d; best = c
	return best


func _fire(w: Dictionary, p: Sim.Player, tgt: Array) -> void:
	var from := pos_of(w)
	fx.append([from, tgt[1], sim.time])
	match String(tgt[0]):
		"ship":
			if sim.rng.randf() < HIT:
				hit_warship(tgt[2], p.id)
		"fleet":
			var a: Sim.Attack = tgt[2]
			if sim.rng.randf() < HIT_FLEET:
				kill_on_fleet(a, 1)
			if a.n > 0 and sim.rng.randf() < FLEET_HITS:
				hit_warship(w, a.p)
		"cargo":
			sink_trip(tgt[2], p.id, tgt[1])


## Warship w takes a hit from realm by; it sinks with its last.
func hit_warship(w: Dictionary, by: int) -> void:
	w.hp = int(w.hp) - 1
	if int(w.hp) > 0:
		return
	var k := sim.navy.find(w)
	if k < 0:
		return
	sim.navy.remove_at(k)
	var q := sim.players[int(w.p) - 1]
	q.warships = maxi(0, q.warships - 1)
	var at := Vector2i(pos_of(w).round())
	if q.id == 1:
		sim.emit_log("%s sank one of your warships." % sim.players[by - 1].name, Color("e08a6a"), at)
	elif by == 1:
		sim.emit_log("You sank a warship of %s." % q.name, Color("86ad5c"), at)


## n soldiers on landing a die at sea.
func kill_on_fleet(a: Sim.Attack, n: int) -> void:
	for i in n:
		if a.n <= 0:
			return
		var k := Sim.mix_pick(a.amix, sim.rng)
		Sim.mix_remove(a.amix, k)
		a.n -= 1
		a.blunt = mini(a.blunt, a.n)
		if a.n > 0:
			a.era = Sim.mix_avg(a.amix)


## Sinks ship trip t (a cargo ship or an expedition) of an enemy of realm by.
func sink_trip(t: Sim.Trip, by: int, at: Vector2) -> void:
	var k := sim.trips.find(t)
	if k < 0:
		return
	var q := sim.players[t.p - 1]
	q.ships = maxi(0, q.ships - 1)
	q.ships_out = maxi(0, q.ships_out - 1)
	sim.trips.remove_at(k)
	if t.p == 1:
		sim.emit_log("%s sank your ship%s." % [sim.players[by - 1].name, " and its expedition" if t.res == "@expedition" else (" with %d %s" % [t.n, t.res] if not t.delivered else "")], Color("e08a6a"), Vector2i(at.round()))
	elif by == 1:
		sim.emit_log("You sank a ship of %s." % q.name, Color("86ad5c"), Vector2i(at.round()))


## A landing sets sail: free warships of its realm go with it (when the realm wants escorts).
func escort(a: Sim.Attack, p: Sim.Player) -> int:
	if not p.escort:
		return 0
	var n := 0
	for w in sim.navy:
		if n >= ESCORTS:
			break
		if int(w.p) == p.id and int(w.esc) == 0:
			w.esc = a.uid
			n += 1
	return n


func escorts_of(a: Sim.Attack) -> int:
	var n := 0
	for w in sim.navy:
		if int(w.esc) == a.uid:
			n += 1
	return n


# ---------------------------------------------------------------- coastal forts
func _forts_fire() -> void:
	for b: Sim.Bld in sim.mil_list():
		if b.dead or b.state != "ready" or not b.def.has("guns"):
			continue
		var g: Dictionary = b.def.guns
		var every := maxi(1, int(g.get("every", 4.0)))
		if (int(sim.time) + b.id) % every != 0 or sim.defenders(b) <= 0:
			continue
		var r := float(g.get("range", 7.0))
		var hit := float(g.get("hit", 0.45))
		var c := Vector2(b.x, b.y)
		var best = null
		var bd := r
		for w in sim.navy:
			if int(w.p) == b.p or not Diplomacy.at_war(sim, b.p, int(w.p)):
				continue
			var d := c.distance_to(pos_of(w))
			if d <= bd:
				bd = d; best = ["ship", pos_of(w), w]
		if best == null:
			for a: Sim.Attack in sim.attacks:
				if a.p == b.p or a.n <= 0 or not sim.military.at_sea(a) or not Diplomacy.at_war(sim, b.p, a.p):
					continue
				var fp := sim.military.column_pos(a)
				var d := c.distance_to(fp)
				if d <= bd:
					bd = d; best = ["fleet", fp, a]
		if best == null:
			for t: Sim.Trip in sim.trips:
				if t.kind != "ship" or t.p == b.p or not Diplomacy.at_war(sim, b.p, t.p):
					continue
				var sp := sim.sea.ship_pos(t)
				var d := c.distance_to(sp)
				if d <= bd:
					bd = d; best = ["cargo", sp, t]
		if best == null:
			continue
		fx.append([c + Vector2(0, -1.0), best[1], sim.time])
		if sim.rng.randf() >= hit:
			continue
		match String(best[0]):
			"ship": hit_warship(best[2], b.p)
			"fleet": kill_on_fleet(best[2], 2)
			"cargo": sink_trip(best[2], b.p, best[1])


# ---------------------------------------------------------------- field depots
## The field depot of realm p with food nearest to tile `to`, within DEPOT_R, or null.
func depot_near(p: Sim.Player, to: Vector2) -> Sim.Bld:
	var best: Sim.Bld = null
	var bd := DEPOT_R
	for b: Sim.Bld in sim.realm_blds(p):
		if b.dead or b.state != "ready" or not b.def.has("rations"):
			continue
		var d := to.distance_to(Vector2(b.x, b.y))
		if d <= bd and sim.logistics.food_at(b, false) > 0:
			bd = d; best = b
	return best


## Takes n rations from depot b (the cheapest food first). How many it got.
func take_rations(b: Sim.Bld, n: int) -> int:
	var p := sim.players[b.p - 1]
	var got := 0
	for f in GameData.food_ids:
		while got < n and int(b.inbuf.get(f, 0)) > 0:
			b.inbuf[f] = int(b.inbuf[f]) - 1
			if int(b.inbuf[f]) <= 0:
				b.inbuf.erase(f)
			sim.used(p, f, 1.0)
			got += 1
	return got


# ---------------------------------------------------------------- generals
static func general_level(xp: float) -> int:
	var l := 0
	for k in GENERAL_XP.size():
		if xp >= float(GENERAL_XP[k]):
			l = k
	return l + 1


func general_ready(p: Sim.Player) -> bool:
	return p.general_uid == 0 and sim.time >= p.general_back


## Column a sets out: the general leads it if he is at home and it is big enough.
func take_general(a: Sim.Attack, p: Sim.Player) -> void:
	if a.n < GENERAL_MIN or not general_ready(p):
		return
	a.general = true
	p.general_uid = a.uid
	if p.id == 1:
		sim.emit_log("Your general (level %d) leads the column." % general_level(p.general_xp), Color("e8c860"), Vector2i(a.to.round()))


## The duel edge the general gives column a (subtracted from the defender's chance).
func duel_edge(a: Sim.Attack) -> float:
	if not a.general:
		return 0.0
	return GEN_DUEL * general_level(sim.players[a.p - 1].general_xp)


func general_learns(a: Sim.Attack, xp: float) -> void:
	if not a.general:
		return
	var p := sim.players[a.p - 1]
	var before := general_level(p.general_xp)
	p.general_xp += xp
	var after := general_level(p.general_xp)
	if after > before and p.id == 1:
		sim.emit_log("Your general reached level %d: his soldiers fight %d%% better." % [after, roundi(after * GEN_DUEL * 100.0)], Color("e8c860"), Vector2i(sim.military.column_pos(a).round()))


## Column a (that the general led) is gone: home with it, or fallen with it.
func general_column_gone(a: Sim.Attack) -> void:
	var p := sim.players[a.p - 1]
	if p.general_uid != a.uid:
		return
	p.general_uid = 0
	if a.n <= 0:
		var lvl := general_level(p.general_xp)
		p.general_xp = 0.0
		p.general_back = sim.time + GENERAL_BACK
		if p.id == 1:
			sim.emit_log("Your general (level %d) fell with his column. A new general will be ready in %d minutes." % [lvl, roundi(GENERAL_BACK / 60.0)], Color("e08a6a"), Vector2i(sim.military.column_pos(a).round()))
		else:
			for q in sim.players:
				if q.id == 1 and Diplomacy.at_war(sim, 1, p.id):
					sim.emit_log("The general of %s has fallen." % p.name, Color("86ad5c"), Vector2i(sim.military.column_pos(a).round()))


## A general whose column is no longer in the field (it went home some other way) is back.
func _generals_check() -> void:
	for p in sim.players:
		if p.general_uid != 0 and sim.military._by_uid(p.general_uid) == null:
			p.general_uid = 0


# ---------------------------------------------------------------- islands
## Whether realm p cannot reach any other realm by land (a rival then takes to the sea). Land areas
## are worked out once from the terrain.
func island(p: Sim.Player) -> bool:
	if sim.time - p.island_t < 120.0:
		return p.island
	p.island_t = sim.time
	if p.hq == null:
		p.island = false
		return false
	if _comp.size() != sim.w * sim.h:
		_label_land()
	var mine := _comp[sim.idx(p.hq.x, p.hq.y)]
	var any := false
	var apart := true
	for q in sim.players:
		if q.id == p.id or not q.alive or q.hq == null:
			continue
		any = true
		if _comp[sim.idx(q.hq.x, q.hq.y)] == mine:
			apart = false
			break
	p.island = any and apart
	return p.island


func _label_land() -> void:
	var n := sim.w * sim.h
	_comp = PackedInt32Array()
	_comp.resize(n)
	_comp.fill(-1)
	var lab := 0
	var q := PackedInt32Array()
	for s in n:
		if _comp[s] != -1 or sim.ter[s] == Sim.WATER:
			continue
		_comp[s] = lab
		q.resize(0)
		q.append(s)
		var head := 0
		while head < q.size():
			var c := q[head]
			head += 1
			var cx := c % sim.w
			var cy := c / sim.w
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = cx + d.x
				var ny: int = cy + d.y
				if nx < 0 or ny < 0 or nx >= sim.w or ny >= sim.h:
					continue
				var ni := ny * sim.w + nx
				if _comp[ni] == -1 and sim.ter[ni] != Sim.WATER:
					_comp[ni] = lab
					q.append(ni)
		lab += 1
