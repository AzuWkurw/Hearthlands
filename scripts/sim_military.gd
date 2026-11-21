class_name SimMilitary
extends RefCounted
## Territory, soldiers, attacks, duels and conquest.
## Part of the simulation: sim.gd holds the shared state and calls in here; the functions reach
## the rest of the game through `sim`.

var sim: Sim

var _owned: Array = []
var _owned_mtn: Array = []


func _init(p_sim: Sim) -> void:
	sim = p_sim


func recompute_territory() -> void:
	var t0 := Time.get_ticks_usec()
	var before := sim.owner.duplicate()
	sim.owner = compute_owner(0)
	sim._owned_dirty = true
	sim.territory_version += 1
	sim._territory_nets(before)
	for b in sim.blds.duplicate():
		if b.ty != "hq" and sim.owner[sim.idx(b.x, b.y)] != b.p:
			sim.destroy(b, "was lost with the territory.")
	sim._pf("territory", t0)


## Who owns each tile, worked out from the military buildings (leaving out building `without`, to see
## what demolishing it would do). Boundary stones (`claim_only`) claim land without soldiers, but only
## land no soldiers hold: they come last, so any military building's land wins over theirs.
func compute_owner(without: int) -> PackedByteArray:
	var own := PackedByteArray()
	own.resize(sim.w * sim.h)
	var mils: Array[Sim.Bld] = []
	var stones: Array[Sim.Bld] = []
	for b in sim.blds:
		if b.id != without and b.state == "ready" and (b.ty == "hq" or (b.def.has("garrison") and b.garrison > 0)):
			mils.append(b)
		elif b.id != without and b.state == "ready" and not b.dead and b.def.get("claim_only", false):
			stones.append(b)
	for b in mils:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if sim.inb(b.x + dx, b.y + dy) and own[sim.idx(b.x + dx, b.y + dy)] == 0:
					own[sim.idx(b.x + dx, b.y + dy)] = b.p
		own[sim.idx(b.x, b.y)] = b.p
	# (build 78) each disc row by row, over only the tiles inside it (the same tiles in the same order)
	for b in mils:
		_claim_disc(own, b.x, b.y, int(b.def.get("radius", 6)), b.p)
	for b in stones:
		_claim_disc(own, b.x, b.y, int(b.def.get("radius", 4)), b.p)
	return own


## For each radius: how far a disc of that radius reaches sideways on each row (dy from -r to r), the
## largest dx with dx * dx + dy * dy <= r * r.
static var _disc_rows := {}

static func disc_rows(r: int) -> PackedInt32Array:
	var rows = _disc_rows.get(r)
	if rows == null:
		rows = PackedInt32Array()
		for dy in range(-r, r + 1):
			var dx := 0
			while (dx + 1) * (dx + 1) + dy * dy <= r * r:
				dx += 1
			rows.append(dx)
		_disc_rows[r] = rows
	return rows


## Gives the tiles nobody holds yet within r tiles of (cx, cy) to realm pid.
func _claim_disc(own: PackedByteArray, cx: int, cy: int, r: int, pid: int) -> void:
	var rows := disc_rows(r)
	var W: int = sim.w
	var y0 := maxi(0, cy - r)
	var y1 := mini(sim.h - 1, cy + r)
	for y in range(y0, y1 + 1):
		var half := rows[y - cy + r]
		var a := y * W
		var i := a + maxi(0, cx - half)
		var e := a + mini(W - 1, cx + half)
		while i <= e:
			if own[i] == 0:
				own[i] = pid
			i += 1


## What demolishing military building b would cost its realm: {"tiles": land lost,
## "rival": how much of it a rival gets, "blds": buildings left outside the border}.
func territory_loss(b: Sim.Bld) -> Dictionary:
	var out := {"tiles": PackedInt32Array(), "rival": 0, "blds": []}
	if not (b.state == "ready" and ((b.def.has("garrison") and b.garrison > 0) or b.def.get("claim_only", false))):
		return out
	var after := compute_owner(b.id)
	var tiles := PackedInt32Array()
	for i in sim.owner.size():
		if sim.owner[i] == b.p and after[i] != b.p:
			tiles.append(i)
			if after[i] != 0:
				out.rival += 1
	out.tiles = tiles
	for o in sim.blds:
		if o.p == b.p and o.id != b.id and o.ty != "hq" and after[sim.idx(o.x, o.y)] != b.p:
			out.blds.append(o)
	return out


## Each realm's tiles (and its mountain tiles with ore left), in map order. (Build 73) Made again
## only for the map rows whose owners changed since: on the biggest maps a whole new count took 30 ms
## and came after every change of the borders. Each row keeps its own lists; a realm's list is its rows'
## lists one after the other, so the order is the same as before. A vein running dry counts everything
## again (sim._owned_full).
var _rows: Array = []          # per map row: [[tiles of realm 1, 2, ...], [mountain tiles of 1, 2, ...]]
var _own_seen := PackedByteArray()

func owned(pid: int) -> Array:
	if sim._owned_dirty:
		var w: int = sim.w
		var np := sim.players.size()
		var full: bool = sim._owned_full or _own_seen.size() != sim.owner.size() or _rows.size() != sim.h \
				or (_rows.size() > 0 and (_rows[0][0] as Array).size() != np)
		if full:
			_rows = []
			_rows.resize(sim.h)
			_own_seen = PackedByteArray()
			_own_seen.resize(sim.owner.size())
			_own_seen.fill(255)
		var owner: PackedByteArray = sim.owner
		for y in sim.h:
			var a := y * w
			if not full and owner.slice(a, a + w) == _own_seen.slice(a, a + w):
				continue
			var lt := []
			var lm := []
			for k in np:
				lt.append(PackedInt32Array())
				lm.append(PackedInt32Array())
			for i in range(a, a + w):
				var o := owner[i]
				if o == 0:
					continue
				lt[o - 1].append(i)
				if sim.ter[i] == Sim.MOUNT and sim.ore[i] != 0 and sim.vein_left(i) > 0:
					lm[o - 1].append(i)
			_rows[y] = [lt, lm]
		_own_seen = owner.duplicate()
		_owned = []
		_owned_mtn = []
		for k in np:
			var t := PackedInt32Array()
			var m := PackedInt32Array()
			for y in sim.h:
				t.append_array(_rows[y][0][k])
				m.append_array(_rows[y][1][k])
			_owned.append(t)
			_owned_mtn.append(m)
		sim._owned_dirty = false
		sim._owned_full = false
	return [_owned[pid - 1], _owned_mtn[pid - 1]]


func own_def(b: Sim.Bld) -> int:
	return sim.players[b.p - 1].reserve if b.ty == "hq" else b.garrison


func helpers(t: Sim.Bld) -> Array:
	var out := []
	for b: Sim.Bld in sim.logistics.mil_near(t.x, t.y, 10):
		if b == t or b.state != "ready":
			continue
		if b.p != t.p and Diplomacy.relation(sim, b.p, t.p) != Diplomacy.ALLY:
			continue
		if Vector2(b.x - t.x, b.y - t.y).length() > 9.0:
			continue
		var av := own_def(b) - 1
		if av > 0:
			out.append([b, av])
	return out


## Peasants against a landing (build 59): when soldiers from the sea reach a building within MILITIA_R
## tiles of its realm's headquarters, up to MILITIA_MAX peasants (one in six) take up pitchforks first.
## Each fights one soldier: he wins MILITIA_WIN of the time (more behind town walls) or falls.
const MILITIA_R := 14.0
const MILITIA_MAX := 8
const MILITIA_WIN := 0.35
const LANDING_PEN := 0.03   # the defenders' edge a duel over soldiers just come ashore
const LANDING_WALL := 0.05  # and more for each of town walls and star forts

func _militia(a: Sim.Attack, p: Sim.Player, t: Sim.Bld) -> void:
	var op := sim.players[t.p - 1]
	if op.hq == null or op.hq.dead or Vector2(t.x, t.y).distance_to(Vector2(op.hq.x, op.hq.y)) > MILITIA_R:
		return
	var n := mini(op.peasant / 6, MILITIA_MAX)
	if n < 1:
		return
	var win := MILITIA_WIN + (0.1 if op.techs.has("town_walls") else 0.0)
	var killed := 0
	var fell := 0
	for i in n:
		if a.n <= 0:
			break
		if sim.rng.randf() < win:
			Sim.mix_remove(a.amix, Sim.mix_pick(a.amix, sim.rng))
			a.n -= 1
			a.blunt = mini(a.blunt, a.n)
			killed += 1
		else:
			op.peasant -= 1
			fell += 1
	a.era = Sim.mix_avg(a.amix) if a.n > 0 else a.era
	if t.p == 1:
		sim.emit_log("%d peasants took up arms on the shore: %d of the landing fell, %d peasants were killed." % [n, killed, fell], Color("e8c870"), Vector2i(t.x, t.y))
	elif a.p == 1:
		sim.emit_log("Peasants met your landing on the shore: %d of your soldiers fell." % killed, Color("e08a6a"), Vector2i(t.x, t.y))


func defenders(t: Sim.Bld) -> int:
	var n := own_def(t)
	for hh in helpers(t):
		n += int(hh[1])
	return n


## Marks each military building as near the border or not: another realm's land within BORDER_R
## tiles of it. (Soldiers go to border buildings first, and inner ones can hold fewer.)
const BORDER_R := 11

func mark_borders() -> void:
	for b: Sim.Bld in sim.mil_list():
		if b.dead:
			continue
		var near := false
		var y0 := maxi(0, b.y - BORDER_R)
		var y1 := mini(sim.h - 1, b.y + BORDER_R)
		var x0 := maxi(0, b.x - BORDER_R)
		var x1 := mini(sim.w - 1, b.x + BORDER_R)
		for y in range(y0, y1 + 1, 2):
			for x in range(x0, x1 + 1, 2):
				var o := sim.owner[y * sim.w + x]
				if o != 0 and o != b.p:
					near = true
					break
			if near:
				break
		b.border = near


# ---------------------------------------------------------------- archers
const ARCHER_RANGE := 6.0
const ARCHER_RELOAD := 4.0
const ARCHER_HIT := 0.3
const ARCHER_DUEL := 0.15   # an archer at the gate fights this much worse

# ---------------------------------------------------------------- weapons wear out
## A soldier's weapon wears out: after each fight there is a WEAPON_WEAR chance it is worn (blunt). A
## soldier with a worn weapon fights BLUNT_DUEL worse until he takes new weapons from the stores (one
## each, a building at a time, every second). A bow breaks after a volley with BOW_WEAR chance; the
## archer takes a new bow from the stores.
const WEAPON_WEAR := 0.1
const BLUNT_DUEL := 0.12
const BOW_WEAR := 0.04


## How likely realm pid's weapons wear out in a fight: by the metal it arms its soldiers with (build 66).
func _wear(pid: int) -> float:
	if pid < 1 or pid > sim.players.size():
		return WEAPON_WEAR
	var q: int = sim.players[pid - 1].arm_q
	return WEAPON_WEAR * (SimArms.ARM_WEAR[q] if q > 0 else 1.0)


func _blunt_of(b: Sim.Bld) -> int:
	return sim.players[b.p - 1].blunt if b.ty == "hq" else b.blunt


func _add_blunt(b: Sim.Bld, n: int) -> void:
	if b.ty == "hq":
		var p := sim.players[b.p - 1]
		p.blunt = clampi(p.blunt + n, 0, p.reserve)
	else:
		b.blunt = clampi(b.blunt + n, 0, b.garrison)


## Is the soldier who fights now one with a worn weapon? (more likely the more there are)
func _picks_blunt(blunt: int, n: int) -> bool:
	return blunt > 0 and sim.rng.randf() < float(blunt) / maxf(1.0, n)


## Every second: soldiers with worn weapons take new ones from the stores, one per building.
func rearm_tick() -> void:
	for p in sim.players:
		if not p.alive:
			continue
		p.blunt = clampi(p.blunt, 0, p.reserve)
		if p.blunt > 0 and float(p.stock.get("weapons", 0.0)) >= 1.0:
			sim.take(p, "weapons", 1.0)
			sim.used(p, "weapons", 1.0)
			p.arm_q = sim.arms.take_best(p, "weapons")
			sim.arms.rearmed(p, p.arm_q, sim.idx(p.hq.x, p.hq.y) if p.hq != null else -1)
			p.blunt -= 1
	for b: Sim.Bld in sim.mil_list():
		if b.ty == "hq" or b.dead:
			continue
		b.blunt = clampi(b.blunt, 0, b.garrison)
		var p2 := sim.players[b.p - 1]
		if b.blunt > 0 and b.state == "ready" and float(p2.stock.get("weapons", 0.0)) >= 1.0:
			sim.take(p2, "weapons", 1.0, sim.idx(b.x, b.y))
			sim.used(p2, "weapons", 1.0)
			p2.arm_q = sim.arms.take_best(p2, "weapons")
			sim.arms.rearmed(p2, p2.arm_q, sim.idx(b.x, b.y))
			b.blunt -= 1

## Every second: soldiers in military buildings take up bows (one from the stores each) or put them
## down, to match each building's archer setting.
func archers_tick() -> void:
	rearm_tick()
	for b: Sim.Bld in sim.mil_list():
		if b.ty == "hq" or b.state != "ready" or b.dead:
			continue
		var p := sim.players[b.p - 1]
		if p.ai:
			# rivals give a third of each garrison bows once they make them (warlords fewer: they attack)
			b.archer_want = archer_cap(b) / (2 if p.pers == "warlord" else 1)
		# no more archers than half the soldiers inside now (at least one while anyone is there)
		var room := 0 if b.garrison <= 0 else maxi(1, (b.garrison + 1) / 2)
		var want := mini(mini(b.archer_want, archer_cap(b)), room)
		if b.archers < want and float(p.stock.get("bows", 0.0)) >= 1.0:
			sim.take(p, "bows", 1.0)
			sim.used(p, "bows", 1.0)
			b.archers += 1
		elif b.archers > want and b.archers > 0:
			b.archers -= 1
			sim.give(p, "bows", 1.0)


## Archers a building can hold: half as many as the soldiers it holds when full (at least 1), and
## never more than half of those inside now. They are extra to the garrison: they shoot from the
## walls and do not fight at the gate.
func archer_cap(b: Sim.Bld) -> int:
	return 0 if b.ty == "hq" else maxi(1, (int(b.def.get("garrison", 0)) + 1) / 2)


## The archers of t shoot at an attack within ARCHER_RANGE (also at the gate, and at columns that
## only pass by on their way to another building).
func _arrows(a: Sim.Attack, p: Sim.Player, t: Sim.Bld, left: float) -> void:
	var n := t.archers if t.ty != "hq" else 0
	if n <= 0 or left > ARCHER_RANGE or t.state != "ready":
		return
	if sim.time < t.arrow_t:
		return
	t.arrow_t = sim.time + ARCHER_RELOAD
	a.arrow_t = sim.time
	a.arrow_src = Vector2(t.x, t.y)
	a.arrow_n = n
	var broke := 0
	for s in n:
		if a.n > 0 and sim.rng.randf() < ARCHER_HIT:
			Sim.mix_remove(a.amix, Sim.mix_pick(a.amix, sim.rng))
			a.n -= 1
			a.blunt = mini(a.blunt, a.n)
			p.vets = maxf(0.0, p.vets - a.vet)
		if sim.rng.randf() < BOW_WEAR:
			broke += 1
	# broken bows: those archers take new ones from the stores (archers_tick)
	t.archers = maxi(0, t.archers - broke)
	a.era = Sim.mix_avg(a.amix)


## Sally: when an attack is launched on t and t is set to march out (or a rival thinks it can win),
## part of its soldiers go to meet the column on the way; the two columns fight in the open.
func _sally(a: Sim.Attack, t: Sim.Bld) -> void:
	if t.ty == "hq" or t.state != "ready" or own_def(t) < 3:
		return
	var op := sim.players[t.p - 1]
	var go := t.sally if not op.ai else (own_def(t) - 1 > a.n + 1)
	if not go:
		return
	var src: Sim.Bld = sim.by_id.get(a.src)
	if src == null or src.dead:
		return
	var n := mini(own_def(t) - 1, maxi(1, a.n))
	var back := a.path.duplicate()
	back.reverse()
	if launch_attack(t, src, n, [], true, back) == "" and t.p == 1:
		sim.emit_log("Your soldiers from the %s march out to meet the attack." % String(t.def.name), Color("d8aa4a"), Vector2i(t.x, t.y))


## A defender of t falls: one of kind k (-1: any, picked at random) from the building defending it.
func kill_defender(t: Sim.Bld, k := -1) -> void:
	var op := sim.players[t.p - 1]
	var tot := maxf(1.0, sim.soldiers(op))
	op.vets = maxf(0.0, op.vets - op.vets / tot)
	var b := _defending(t)
	if own_def(b) <= 0:
		return
	var m := mix_of(b)
	Sim.mix_remove(m, k if k >= 0 else Sim.mix_pick(m, sim.rng))
	if b.ty == "hq":
		var hp := sim.players[b.p - 1]
		hp.reserve -= 1
		hp.res_era = Sim.mix_avg(m)
		if hp.blunt > hp.reserve or _picks_blunt(hp.blunt, hp.reserve + 1):
			hp.blunt = maxi(0, hp.blunt - 1)
	else:
		b.garrison -= 1
		b.sera = Sim.mix_avg(m)
		if b.blunt > b.garrison or _picks_blunt(b.blunt, b.garrison + 1):
			b.blunt = maxi(0, b.blunt - 1)
		# an archer falls first when most of the garrison are archers
		if b.archers > b.garrison or (b.archers > 0 and sim.rng.randf() < float(b.archers) / maxf(1.0, b.garrison + 1)):
			b.archers -= 1


## The soldiers in building b by kind (headquarters: the realm's reserve).
func mix_of(b: Sim.Bld) -> Array:
	return sim.rmix_of(sim.players[b.p - 1]) if b.ty == "hq" else sim.gmix_of(b)


## Kinds of soldier: what each is strong against. ADV[x][y] = 1 when kind x beats kind y.
## 0 bronze warrior, 1 legionary, 2 spearman, 3 man-at-arms, 4 pikeman, 5 musketeer, 6 rifleman.
const ADV := [
	[0, 0, 0, 0, 0, 0, 0],   # bronze warriors: the first soldiers, beaten by most who come after
	[1, 0, 1, 0, 0, 0, 0],   # legionaries beat bronze warriors and spearmen
	[0, 0, 0, 0, 0, 0, 0],   # spearmen: cheap and quick to train instead
	[1, 1, 1, 0, 0, 0, 0],   # men-at-arms beat bronze warriors, legionaries and spearmen
	[1, 1, 0, 1, 0, 0, 0],   # pikemen beat bronze warriors, legionaries and men-at-arms
	[1, 0, 0, 0, 1, 0, 0],   # musketeers beat bronze warriors and pikemen
	[1, 1, 1, 1, 1, 1, 0],   # riflemen beat everything older
]
const COUNTER := 0.12      # win chance gained by a kind against one it beats
## Guns: [range in tiles, seconds to reload, chance each shot fells a soldier]
const GUNS := {5: [4.0, 6.0, 0.2], 6: [7.0, 2.5, 0.25]}
const GUN0 := 5           # the first kind with guns (musketeers): a.vt[g - GUN0]


## Which of the kinds in mix m is best at fighting a soldier of kind k (the defenders always send it).
func best_counter(m: Array, k: int) -> int:
	var best := -1
	var bs := -1e9
	for d in m.size():
		if int(m[d]) <= 0:
			continue
		var sc := COUNTER * (int(ADV[d][k]) - int(ADV[k][d])) + 0.035 * (d - k) + _melee_edge(d, true) + int(m[d]) * 0.0001
		if sc > bs:
			bs = sc; best = d
	return best


## What a kind is worth hand to hand: legionaries' shield wall and pikemen's reach help them hold a
## gate; musketeers, reloading, are poor in a melee.
static func _melee_edge(k: int, defending: bool) -> float:
	match k:
		1: return 0.06 if defending else 0.0
		4: return 0.06 if defending else 0.0
		5: return -0.04
	return 0.0


## The building whose soldier fights the next duel: the target itself, or the first helper nearby.
func _defending(t: Sim.Bld) -> Sim.Bld:
	if own_def(t) > 0:
		return t
	var hs := helpers(t)
	return hs[0][0] if hs.size() > 0 else t


## Average experience of the soldiers defending t.
func defender_xp(t: Sim.Bld) -> float:
	var b := _defending(t)
	return sim.players[b.p - 1].res_xp if b.ty == "hq" else b.sxp


## Average age of the soldiers defending t (0 bronze warriors ... 6 riflemen).
func defender_era(t: Sim.Bld) -> float:
	return Sim.mix_avg(mix_of(_defending(t)))


## The defender who won a duel gains experience.
func _defender_gains_xp(t: Sim.Bld) -> void:
	var b := _defending(t)
	if b.ty == "hq":
		var q := sim.players[b.p - 1]
		q.res_xp += 3.0 / maxf(1.0, q.reserve)
	else:
		b.sxp += 3.0 / maxf(1.0, b.garrison)


## want: at most this many march (-1: as many as can); kinds: only these soldier kinds march (empty: any).
# ---------------------------------------------------------------- the way a column marches
## Soldiers do not walk on water: a column marches round lakes and rivers and over bridges. A way
## may be up to WAY_MAX times as long as the straight line.
const WAY_MAX := 2.2

func _walkable(i: int) -> bool:
	return sim.ter[i] != Sim.WATER or sim.road[i] != 0


## The tiles a column walks from (sx, sy) to (tx, ty), or empty when water bars the way.
func land_path(sx: int, sy: int, tx: int, ty: int) -> PackedInt32Array:
	var w := sim.w
	var start := sy * w + sx
	var goal := ty * w + tx
	var straight := Vector2(tx - sx, ty - sy).length()
	# open land between them: the straight line
	var clear := true
	var steps := maxi(1, ceili(straight * 2.0))
	for k in range(1, steps):
		var q := Vector2(sx, sy).lerp(Vector2(tx, ty), float(k) / steps).round()
		if not _walkable(int(q.y) * w + int(q.x)):
			clear = false
			break
	if clear:
		return PackedInt32Array([start, goal])
	var m := 14
	var x0 := maxi(0, mini(sx, tx) - m)
	var x1 := mini(w - 1, maxi(sx, tx) + m)
	var y0 := maxi(0, mini(sy, ty) - m)
	var y1 := mini(sim.h - 1, maxi(sy, ty) + m)
	var limit := straight * WAY_MAX + 4.0
	var g := {start: 0.0}
	var par := {start: -1}
	var heap := Sim.MinHeap.new()
	heap.push(straight, start)
	var done := {}
	while heap.size() > 0:
		var cur := heap.pop()
		if done.has(cur):
			continue
		done[cur] = true
		if cur == goal:
			break
		var cx := cur % w
		var cy := cur / w
		var gc: float = g[cur]
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx := cx + dx
				var ny := cy + dy
				if nx < x0 or nx > x1 or ny < y0 or ny > y1:
					continue
				var ni := ny * w + nx
				if done.has(ni) or (ni != goal and not _walkable(ni)):
					continue
				# no cutting a corner of the water
				if dx != 0 and dy != 0 and (not _walkable(cy * w + nx) or not _walkable(ny * w + cx)):
					continue
				var ng := gc + (1.0 if dx == 0 or dy == 0 else 1.4142)
				if ng > limit or ng >= float(g.get(ni, 1e9)):
					continue
				g[ni] = ng
				par[ni] = cur
				heap.push(ng + Vector2(tx - nx, ty - ny).length(), ni)
	if not par.has(goal):
		return PackedInt32Array()
	var out := PackedInt32Array()
	var c := goal
	while c >= 0:
		out.append(c)
		c = par[c]
	out.reverse()
	return out


static func path_len(sim_w: int, path: PackedInt32Array) -> float:
	var l := 0.0
	for k in range(1, path.size()):
		l += Vector2(path[k] % sim_w - path[k - 1] % sim_w, path[k] / sim_w - path[k - 1] / sim_w).length()
	return l


## The point at share f (0..1) of the way along a path.
func _along(path: PackedInt32Array, f: float) -> Vector2:
	var w := sim.w
	var total := path_len(w, path)
	var want := clampf(f, 0.0, 1.0) * total
	for k in range(1, path.size()):
		var a := Vector2(path[k - 1] % w, path[k - 1] / w)
		var b := Vector2(path[k] % w, path[k] / w)
		var l := a.distance_to(b)
		if want <= l or k == path.size() - 1:
			return a.lerp(b, clampf(want / maxf(0.001, l), 0.0, 1.0))
		want -= l
	return Vector2(path[0] % w, path[0] / w)


# ---------------------------------------------------------------- army supplies
## An army that marches further than SUPPLY_FREE tiles lives on what it carries: half a ration a
## soldier for the way, taken from the stores where it sets out, and a ration for every four soldiers
## each SUPPLY_EVERY seconds at the enemy's gate. It packs for the way and three rounds at the gate.
## Soldiers without food grow hungry, and every duel goes SUPPLY_PEN worse for a starving army: a long
## march needs full stores, and a siege far from home cannot last for ever.
const SUPPLY_FREE := 14.0
const SUPPLY_PER := 0.5
const SUPPLY_EVERY := 20.0
const SUPPLY_PEN := 0.12


## Rations column a eats at the gate each SUPPLY_EVERY seconds.
static func ration(n: int) -> int:
	return maxi(1, ceili(n / 4.0))


## Packs supplies for column a setting out from src: what the march needs, and three rounds at the gate.
func pack_supplies(a: Sim.Attack, p: Sim.Player, src: Sim.Bld) -> void:
	# cartridges for the musketeers and riflemen: enough for AMMO_VOLLEYS volleys, as far as there are
	var shooters := shooters_of(a.amix)
	if shooters > 0:
		var want := ceili(float(shooters * AMMO_VOLLEYS) / AMMO_SHOTS)
		a.ammo = int(sim.take(p, "ammunition", float(want)))
		if a.ammo > 0:
			sim.used(p, "ammunition", float(a.ammo))
	var dist := path_len(sim.w, a.path) if a.path.size() >= 2 else a.from.distance_to(a.to)
	a.far = dist - float(a.sea) > SUPPLY_FREE or a.sea > 0
	a.t_eat = a.t1 + SUPPLY_EVERY
	var dep := sim.naval.depot_near(p, a.to)
	a.depot = dep.id if dep != null else 0
	if not a.far:
		return
	var way := ceili(a.n * SUPPLY_PER)
	var want := way + ration(a.n) * 3
	var got := 0
	var at := sim.idx(src.x, src.y)
	for k in want:
		if sim.take_food(p, at) <= 0.0:
			break
		got += 1
	# the way's share is eaten on the march; short of it, they arrive hungry
	var eaten := mini(got, way)
	a.food = float(got - eaten)
	a.hunger = 1.0 - float(eaten) / float(way)


## At the gate a column far from home eats from what it carries; without food it grows hungry.
func _eat(a: Sim.Attack) -> void:
	if not a.far or sim.time < a.t_eat:
		return
	a.t_eat = sim.time + SUPPLY_EVERY
	var r := float(ration(a.n))
	# a field depot near the gate feeds them first
	var dep: Sim.Bld = sim.by_id.get(a.depot) if a.depot != 0 else null
	if dep != null and not dep.dead and dep.p == a.p and dep.state == "ready" and sim.logistics.food_at(dep, false) >= int(r):
		sim.naval.take_rations(dep, int(r))
		a.hunger = maxf(0.0, a.hunger - 0.5)
		return
	if a.food >= r:
		a.food -= r
		a.hunger = maxf(0.0, a.hunger - 0.5)
	else:
		a.food = 0.0
		a.hunger = minf(1.0, a.hunger + 0.5)
		if a.p == 1 and a.hunger >= 1.0:
			sim.emit_log("Your soldiers at the gate have run out of food and are starving.", Color("e08a6a"), Vector2i(a.to.round()))


## Words for what a column carries, for the player.
func supply_words(a: Sim.Attack) -> String:
	if not a.far:
		return "near home: no supplies needed"
	if a.depot != 0:
		return "%d rations, and a field depot near the gate" % int(a.food)
	if a.hunger >= 0.99:
		return "out of food, starving"
	return "%d rations left%s" % [int(a.food), ", hungry" if a.hunger > 0.01 else ""]


func launch_attack(src: Sim.Bld, tgt: Sim.Bld, want := -1, kinds: Array = [], sally := false, via := PackedInt32Array()) -> String:
	var p := sim.players[src.p - 1]
	if src.p == tgt.p or not sim.is_mil(tgt) or tgt.state != "ready" or src.state != "ready":
		return "Pick an enemy military building"
	if not Diplomacy.at_war(sim, src.p, tgt.p):
		return "You are not at war with %s. Declare war in Diplomacy first." % sim.players[tgt.p - 1].name
	var dist := Vector2(tgt.x - src.x, tgt.y - src.y).length()
	if dist > Sim.RANGE:
		return "Target out of range"
	var avail := own_def(src) - 1
	if avail < 1:
		return "Not enough soldiers here"
	var way := via if via.size() >= 2 else land_path(src.x, src.y, tgt.x, tgt.y)
	if way.is_empty():
		return "No way there by land: water lies between. Build a bridge, or attack from another building"
	var n := mini(avail, 16)
	if want >= 0:
		n = mini(n, want)
	# the best soldiers march; the oldest stay to hold the building, or one of the kind the player
	# chose to keep home
	var m := mix_of(src)
	var kept := -1
	if src.keep_kind >= 0 and src.keep_kind < m.size() and int(m[src.keep_kind]) > 0:
		kept = src.keep_kind
		m[kept] -= 1
	var sent: Array
	if kinds.is_empty():
		sent = Sim.mix_take_best(m, n)
	else:
		var m2 := m.duplicate()
		for k in m2.size():
			if not kinds.has(k):
				m2[k] = 0
		sent = Sim.mix_take_best(m2, n)
		for k in mini(m.size(), sent.size()):
			m[k] -= int(sent[k])
		n = 0
		for v in sent:
			n += int(v)
	if kept >= 0:
		m[kept] += 1
	if n < 1:
		return "None of the chosen kinds can go from here"
	var sb := _blunt_of(src)
	var go_blunt := mini(sb, roundi(float(sb) * n / maxf(1.0, own_def(src))))
	_add_blunt(src, -go_blunt)
	if src.ty == "hq": p.reserve -= n
	else:
		src.garrison -= n
		src.blunt = mini(src.blunt, src.garrison)
	var a := Sim.Attack.new()
	a.p = src.p; a.src = src.id; a.tgt = tgt.id; a.n = n; a.n0 = n; a.t0 = sim.time
	a.path = way
	a.t1 = sim.time + path_len(sim.w, way) * 1.1 + 1.0
	a.from = Vector2(src.x, src.y); a.to = Vector2(tgt.x, tgt.y)
	a.vet = clampf(p.vets / maxf(1.0, sim.soldiers(p) + n), 0.0, 1.0)
	a.sxp = p.res_xp if src.ty == "hq" else src.sxp
	a.amix = sent
	a.era = Sim.mix_avg(sent)
	a.vt = [a.t0, a.t0]
	a.dvt = [a.t0, a.t0]
	a.blunt = mini(go_blunt, n)
	sim._bid += 1
	a.uid = sim._bid
	sim.naval.take_general(a, p)
	pack_supplies(a, p, src)
	sim.attacks.append(a)
	p.attacks_made += 1
	Diplomacy.on_attacked(sim, tgt.p, src.p)
	if not sally:
		_sally(a, tgt)
	if tgt.p == 1:
		sim.emit_log("%s attacks your %s with %d soldiers!" % [p.name, String(tgt.def.name), n], Color("e0603a"), Vector2i(tgt.x, tgt.y))
	elif src.p == 1:
		sim.emit_log("Your %d soldiers march on %s (%s)." % [n, sim.players[tgt.p - 1].name, supply_words(a)], Color("d8aa4a"), Vector2i(tgt.x, tgt.y))
	return ""


## Sends soldiers waiting at the headquarters across the water from harbour h to attack building tgt:
## ships carry them (one for every SimSea.LANDING_PER_SHIP), land them on the nearest beach to it, and
## sail home. "" when they set sail, else why not.
func launch_landing(h: Sim.Bld, tgt: Sim.Bld, want := -1) -> String:
	var p := sim.players[h.p - 1]
	if not sim.sea.is_harbour(h) or h.state != "ready" or h.dead:
		return "Landings set sail from a harbour"
	if h.p == tgt.p or not sim.is_mil(tgt) or tgt.state != "ready":
		return "Pick an enemy military building"
	if not Diplomacy.at_war(sim, h.p, tgt.p):
		return "You are not at war with %s. Declare war in Diplomacy first." % sim.players[tgt.p - 1].name
	var ships := sim.sea.free_ships(p)
	if ships < 1:
		return "No free ship: build a shipyard and let it build one"
	if sim.sea.stormy(h.x, h.y):
		return "A storm keeps the ships in harbour: wait for it to pass"
	if p.reserve < 1:
		return "A landing takes soldiers waiting at the headquarters"
	var route := sim.sea.landing_route(h, tgt)
	if route.is_empty():
		return "No way by sea from this harbour to a beach near that building"
	var n := mini(mini(p.reserve, ships * SimSea.LANDING_PER_SHIP), SimSea.LANDING_MAX)
	if want >= 0:
		n = mini(n, want)
	if n < 1:
		return "No soldiers to send"
	var need_ships := ceili(float(n) / SimSea.LANDING_PER_SHIP)
	var sea: PackedInt32Array = route[0]
	var land: PackedInt32Array = route[1]
	var sent := Sim.mix_take_best(sim.rmix_of(p), n)
	var go_blunt := mini(p.blunt, roundi(float(p.blunt) * n / maxf(1.0, p.reserve)))
	p.blunt -= go_blunt
	p.reserve -= n
	p.ships_out += need_ships
	var a := Sim.Attack.new()
	a.p = h.p; a.src = h.id; a.tgt = tgt.id; a.n = n; a.n0 = n; a.t0 = sim.time
	var way := sea.duplicate()
	way.append_array(land.slice(1))
	a.path = way
	a.sea = sea.size()
	a.ships = need_ships
	a.t_land = sim.time + path_len(sim.w, sea) / SimSea.SHIP_SPEED + 2.0
	a.t1 = a.t_land + path_len(sim.w, land) * 1.1 + 1.0
	a.from = Vector2(h.x, h.y); a.to = Vector2(tgt.x, tgt.y)
	a.vet = clampf(p.vets / maxf(1.0, sim.soldiers(p) + n), 0.0, 1.0)
	a.sxp = p.res_xp
	a.amix = sent
	a.era = Sim.mix_avg(sent)
	a.vt = [a.t0, a.t0]
	a.dvt = [a.t0, a.t0]
	a.blunt = mini(go_blunt, n)
	sim._bid += 1
	a.uid = sim._bid
	sim.naval.take_general(a, p)
	pack_supplies(a, p, h)
	sim.attacks.append(a)
	var escn := sim.naval.escort(a, p)
	p.attacks_made += 1
	Diplomacy.on_attacked(sim, tgt.p, h.p)
	if tgt.p == 1:
		sim.emit_log("A fleet of %s is sailing for your %s with %d soldiers!" % [p.name, String(tgt.def.name), n], Color("e0603a"), Vector2i(tgt.x, tgt.y))
	elif h.p == 1:
		sim.emit_log("%d ships sail with %d of your soldiers for %s's coast (%s%s)." % [need_ships, n, sim.players[tgt.p - 1].name, supply_words(a), (", %d warship%s escorting" % [escn, "s" if escn > 1 else ""]) if escn > 0 else ""], Color("d8aa4a"), Vector2i(tgt.x, tgt.y))
	return ""


## Landings' ships: they sail home once the soldiers are ashore; a fleet beaten at sea goes down
## with them. at_start: the fleets at sea when this tick began.
func _fleets_tick(at_start: Array) -> void:
	for a: Sim.Attack in at_start:
		if a.ships <= 0:
			continue
		var p := sim.players[a.p - 1]
		var gone := not sim.attacks.has(a)
		if gone and a.n <= 0 and sim.time < a.t_land:
			# beaten at sea: the ships are lost
			p.ships = maxi(0, p.ships - a.ships)
			p.ships_out = maxi(0, p.ships_out - a.ships)
			if a.p == 1:
				sim.emit_log("Your fleet was sunk at sea.", Color("e08a6a"), Vector2i(column_pos(a).round()))
			a.ships = 0
		elif gone or sim.time >= a.t_land:
			p.ships_out = maxi(0, p.ships_out - a.ships)
			a.ships = 0


func attack_tick(dt: float) -> void:
	sim.naval.tick(dt)
	var fleets := []
	var gens := []
	for a0 in sim.attacks:
		if a0.ships > 0:
			fleets.append(a0)
		if a0.general:
			gens.append(a0)
	_attack_tick(dt)
	for a1: Sim.Attack in gens:
		if not sim.attacks.has(a1):
			sim.naval.general_column_gone(a1)
	if not fleets.is_empty():
		_fleets_tick(fleets)
		if int(sim.time * 2.0) != int((sim.time - dt) * 2.0):
			sim.sea.fleets_meet_ships()


func _attack_tick(dt: float) -> void:
	_field_battles(dt)
	for k in range(sim.attacks.size() - 1, -1, -1):
		var a := sim.attacks[k]
		var p := sim.players[a.p - 1]
		var t: Sim.Bld = sim.by_id.get(a.tgt)
		if a.chase == 0 and (t == null or t.p == a.p or not p.alive or not Diplomacy.at_war(sim, a.p, t.p)):
			_retreat(a, p)
			sim.attacks.remove_at(k)
			continue
		Sim.mix_fix(a.amix, a.n, roundi(a.era))
		if a.chase != 0:
			if not _chase_tick(a, dt):
				sim.attacks.remove_at(k)
			continue
		if a.field != 0:
			continue                  # held up by a battle in the open (see _field_battles)
		if not a.fighting:
			# marching in: volleys both ways, then the fight at the gate
			_passing(a, p, column_pos(a))
			if a.n <= 0:
				sim.attacks.remove_at(k)
				if a.p == 1:
					sim.emit_log("Your column was shot to pieces on the way.", Color("e08a6a"), Vector2i(column_pos(a).round()))
				continue
			_volleys(a, p, t)
			if a.n <= 0:
				sim.attacks.remove_at(k)
				if a.p == 1 or t.p == 1:
					sim.emit_log("The attack on %s was shot to pieces before it reached the gate." % String(t.def.name), Color("86ad5c") if t.p == 1 else Color("e08a6a"), Vector2i(t.x, t.y))
				continue
			if sim.time >= a.t1 and a.sea > 0 and not a.militia:
				a.militia = true
				_militia(a, p, t)
				if a.n <= 0:
					sim.attacks.remove_at(k)
					if a.p == 1 or t.p == 1:
						sim.emit_log("The landing at %s was thrown back into the sea by the peasants." % String(t.def.name).to_lower(), Color("86ad5c") if t.p == 1 else Color("e08a6a"), Vector2i(t.x, t.y))
					continue
			if sim.time >= a.t1 and defenders(t) <= 0:
				_capture(a, t, p, sim.players[t.p - 1])
				sim.attacks.remove_at(k)
				continue
			if sim.time >= a.t1:
				a.fighting = true; a.step = 0.0
			continue
		# at the gate: the building's guns and archers keep firing at the attackers outside the walls
		_cannon(a, p, t, 0.0)
		_arrows(a, p, t, 0.0)
		if a.n <= 0:
			sim.attacks.remove_at(k)
			Chronicle.note(sim, sim.players[t.p - 1], "repelled", {"o": a.p})
			if a.p == 1 or t.p == 1:
				sim.emit_log("The attack on %s was beaten back." % String(t.def.name), Color("86ad5c") if t.p == 1 else Color("e08a6a"), Vector2i(t.x, t.y))
			continue
		_eat(a)
		a.step += dt
		if a.step < 1.0:
			continue
		a.step = 0.0
		var op := sim.players[t.p - 1]
		var dvet := clampf(op.vets / maxf(1.0, sim.soldiers(op)), 0.0, 1.0)
		var rounds := mini(3, mini(a.n, maxi(1, defenders(t))))
		for r in rounds:
			if a.n <= 0 or defenders(t) <= 0:
				break
			var dw := 0.55 if (t.ty == "hq" or t.ty == "castle") else 0.5
			# walls: guardhouses, keeps and forts help whoever holds their gate
			dw += float(t.def.get("wall", 0.0))
			dw += 0.15 * (dvet - a.vet) + sim.mod(op, "defense") - sim.mod(p, "attack")
			dw += 0.03 * (Sim.level(defender_xp(t), Sim.SOLDIER_XP) - Sim.level(a.sxp, Sim.SOLDIER_XP))
			# hungry soldiers far from home
			dw += SUPPLY_PEN * a.hunger
			# soldiers just come ashore, against town walls and star forts (build 59)
			if a.sea > 0:
				dw += LANDING_PEN + (LANDING_WALL if op.techs.has("town_walls") else 0.0) + (LANDING_WALL if op.techs.has("star_forts") else 0.0)
			# the general's experience
			dw -= sim.naval.duel_edge(a)
			# one soldier of each side: the attacker comes as he is, the defenders send their best
			# answer to him. Later ages are stronger (+3.5% a duel per age, about 15% in strength);
			# some kinds beat others; and each kind has its own edge.
			var ak := Sim.mix_pick(a.amix, sim.rng)
			var dk := best_counter(mix_of(_defending(t)), ak)
			if dk < 0:
				dk = 1
			dw += 0.035 * (dk - ak) + COUNTER * (int(ADV[dk][ak]) - int(ADV[ak][dk]))
			dw += _melee_edge(dk, true) - _melee_edge(ak, false)
			var db2 := _defending(t)
			# worn weapons on either side
			var a_blunt := _picks_blunt(a.blunt, a.n)
			var d_blunt := _picks_blunt(_blunt_of(db2), own_def(db2))
			if a_blunt: dw += BLUNT_DUEL
			if d_blunt: dw -= BLUNT_DUEL
			# each fight may wear out the weapons of the two who fought
			if not a_blunt and sim.rng.randf() < _wear(a.p):
				a.blunt = mini(a.blunt + 1, a.n)
				a_blunt = true
			if not d_blunt and sim.rng.randf() < _wear(db2.p):
				_add_blunt(db2, 1)
			if sim.rng.randf() < dw:
				# men-at-arms' armour turns half the blows that would fell them (not pikes or bullets)
				if ak == 3 and dk < 4 and sim.rng.randf() < 0.5:
					continue
				Sim.mix_remove(a.amix, ak)
				a.n -= 1
				if a_blunt:
					a.blunt = maxi(0, a.blunt - 1)
				a.blunt = mini(a.blunt, a.n)
				a.era = Sim.mix_avg(a.amix)
				p.vets = maxf(0.0, p.vets - a.vet)
				_defender_gains_xp(t)
			else:
				if dk == 3 and ak < 4 and sim.rng.randf() < 0.5:
					continue
				kill_defender(t, dk)
				a.sxp += 3.0 / maxf(1.0, a.n)
				sim.naval.general_learns(a, 1.0)
		if a.n > 0 and p.ai and a.n0 >= 3 and a.n * 2 < a.n0 and defenders(t) > a.n:
			# a rival sees the attack going badly and calls the rest back
			_retreat(a, p)
			sim.attacks.remove_at(k)
			Chronicle.note(sim, sim.players[t.p - 1], "repelled", {"o": a.p})
			if t.p == 1:
				sim.emit_log("%s's attack on your %s falls back." % [p.name, String(t.def.name)], Color("86ad5c"), Vector2i(t.x, t.y))
			continue
		if a.n <= 0:
			sim.attacks.remove_at(k)
			Chronicle.note(sim, sim.players[t.p - 1], "repelled", {"o": a.p})
			if a.p == 1 or t.p == 1:
				sim.emit_log("The attack on %s was beaten back." % String(t.def.name), Color("86ad5c") if t.p == 1 else Color("e08a6a"), Vector2i(t.x, t.y))
			continue
		if defenders(t) <= 0:
			_capture(a, t, p, op)
			sim.attacks.remove_at(k)


## Where a marching column is now, in tiles.
func column_pos(a: Sim.Attack) -> Vector2:
	if a.chase != 0:
		return a.from
	if a.fighting:
		return a.to
	if a.sea > 0:
		return _landing_pos(a, sim.time)
	var f := clampf((sim.time - a.t0) / maxf(0.01, a.t1 - a.t0), 0.0, 1.0)
	if a.path.size() > 2:
		return _along(a.path, f)
	return a.from.lerp(a.to, f)


## Where a landing is at game time tm: on the ships along the crossing (the first a.sea tiles of its
## path) until a.t_land, then marching from the beach.
func _landing_pos(a: Sim.Attack, tm: float) -> Vector2:
	if tm < a.t_land:
		var f := clampf((tm - a.t0) / maxf(0.01, a.t_land - a.t0), 0.0, 1.0)
		return _along(a.path.slice(0, a.sea), f)
	var f2 := clampf((tm - a.t_land) / maxf(0.01, a.t1 - a.t_land), 0.0, 1.0)
	return _along(a.path.slice(a.sea - 1), f2)


## Whether column a is still on its ships, crossing the water.
func at_sea(a: Sim.Attack) -> bool:
	return a.sea > 0 and sim.time < a.t_land and not a.fighting


## The way a column faces (a unit vector).
func column_dir(a: Sim.Attack) -> Vector2:
	if a.sea > 0 and not a.fighting:
		var d0 := _landing_pos(a, sim.time + 0.5) - _landing_pos(a, sim.time - 0.2)
		return d0.normalized() if d0.length() > 0.01 else Vector2.RIGHT
	if a.chase != 0:
		var c := _by_uid(a.chase)
		var d0 := (column_pos(c) - a.from) if c != null else (a.to - a.from)
		return d0.normalized() if d0.length() > 0.01 else Vector2.RIGHT
	if a.path.size() > 2 and not a.fighting:
		var f := clampf((sim.time - a.t0) / maxf(0.01, a.t1 - a.t0), 0.0, 1.0)
		var d := _along(a.path, minf(1.0, f + 0.04)) - _along(a.path, maxf(0.0, f - 0.01))
		if d.length() > 0.01:
			return d.normalized()
	var d2 := a.to - a.from
	return d2.normalized() if d2.length() > 0.01 else Vector2.RIGHT


# ---------------------------------------------------------------- reacting to a column passing by
const INTERCEPT_R := 5.0     # a building set to march out stops enemy columns passing this near
const CHASE_SPEED := 1.1     # tiles a second

## A column on its way to another building passes military buildings of realms it is at war with:
## their archers shoot at it, and one set to march out (rivals: one with clearly more soldiers) sends
## soldiers to stop it in the open.
func _passing(a: Sim.Attack, p: Sim.Player, pos: Vector2) -> void:
	# (build 75) only the forts by the column, in the same order as going over every fort
	var reach := ceili(maxf(ARCHER_RANGE, INTERCEPT_R)) + 1
	for b: Sim.Bld in sim.logistics.mil_near(floori(pos.x), floori(pos.y), reach):
		if b.p == a.p or b.id == a.tgt or b.state != "ready" or b.dead or b.ty == "hq":
			continue
		var d := Vector2(b.x, b.y).distance_to(pos)
		if d > ARCHER_RANGE or not Diplomacy.at_war(sim, a.p, b.p):
			continue
		if b.archers > 0:
			_arrows(a, p, b, d)
			if a.n <= 0:
				return
		if d <= INTERCEPT_R and a.field == 0:
			var op := sim.players[b.p - 1]
			var go := b.sally if not op.ai else (own_def(b) - 1 > a.n + 1)
			if go and own_def(b) >= 3 and not _chased(a.uid, b.id):
				_intercept(b, a)


func _chased(uid: int, src: int) -> bool:
	for c in sim.attacks:
		if c.chase == uid and c.src == src:
			return true
	return false


## Soldiers of b march out to stop column a in the open; afterwards they go home.
func _intercept(b: Sim.Bld, a: Sim.Attack) -> void:
	var n := mini(own_def(b) - 1, maxi(2, a.n + 1))
	if n < 1:
		return
	var p := sim.players[b.p - 1]
	var sent := Sim.mix_take_best(mix_of(b), n)
	var sb := b.blunt
	var go_blunt := mini(sb, roundi(float(sb) * n / maxf(1.0, b.garrison)))
	b.garrison -= n
	b.blunt = clampi(b.blunt - go_blunt, 0, b.garrison)
	var c := Sim.Attack.new()
	c.p = b.p; c.src = b.id; c.tgt = a.src; c.n = n; c.n0 = n
	c.t0 = sim.time; c.t1 = sim.time + 600.0
	c.from = Vector2(b.x, b.y); c.to = Vector2(b.x, b.y)
	c.vet = clampf(p.vets / maxf(1.0, sim.soldiers(p) + n), 0.0, 1.0)
	c.sxp = b.sxp
	c.amix = sent
	c.era = Sim.mix_avg(sent)
	c.vt = [c.t0, c.t0]; c.dvt = [c.t0, c.t0]
	c.blunt = mini(go_blunt, n)
	c.chase = a.uid
	# a sally takes cartridges from the stores, as a garrison's guns do
	var sh := shooters_of(sent)
	if sh > 0:
		c.ammo = int(sim.take(p, "ammunition", float(ceili(float(sh * AMMO_VOLLEYS) / AMMO_SHOTS))))
		if c.ammo > 0:
			sim.used(p, "ammunition", float(c.ammo))
	sim._bid += 1
	c.uid = sim._bid
	sim.attacks.append(c)
	if b.p == 1:
		sim.emit_log("Your %d soldiers from the %s march out to stop %s's column." % [n, String(b.def.name).to_lower(), sim.players[a.p - 1].name], Color("d8aa4a"), Vector2i(b.x, b.y))
	elif a.p == 1:
		sim.emit_log("%d of %s's soldiers march out of a %s to stop your column." % [n, p.name, String(b.def.name).to_lower()], Color("e08a6a"), Vector2i(b.x, b.y))


## A column marching out to stop another: it walks at it; when that one is gone it goes home.
## Returns whether the column is still on the map.
func _chase_tick(c: Sim.Attack, dt: float) -> bool:
	var p := sim.players[c.p - 1]
	var a := _by_uid(c.chase)
	var home: Sim.Bld = sim.by_id.get(c.src)
	if a == null or a.n <= 0 or a.fighting or not Diplomacy.at_war(sim, c.p, a.p) or home == null or home.p != c.p \
			or (a.field == 0 and c.from.distance_to(Vector2(home.x, home.y)) > INTERCEPT_R + 4.0):
		_retreat(c, p)
		return false
	if c.field != 0:
		return true
	var to := column_pos(a)
	var d := to - c.from
	var step := CHASE_SPEED * dt
	var nxt := to if d.length() <= step else c.from + d.normalized() * step
	if _walkable(int(roundf(nxt.y)) * sim.w + int(roundf(nxt.x))):
		c.from = nxt
	c.to = c.from
	return true


func _by_uid(uid: int) -> Sim.Attack:
	for a in sim.attacks:
		if a.uid == uid:
			return a
	return null


## Columns of realms at war that meet on the march stop and fight in the open: volleys while they close
## in, then duels with no walls and no defender's bonus. The winners march on; the losers are gone.
func _field_battles(dt: float) -> void:
	var n := sim.attacks.size()
	if n < 2:
		return
	# volleys between columns closing in, and new meetings
	for i in n:
		var a := sim.attacks[i]
		if a.fighting or a.field != 0 or a.n <= 0:
			continue
		var pa := column_pos(a)
		for j in range(i + 1, n):
			var b := sim.attacks[j]
			if b.fighting or b.field != 0 or b.n <= 0 or b.p == a.p or not Diplomacy.at_war(sim, a.p, b.p):
				continue
			var d := pa.distance_to(column_pos(b))
			if d <= 1.2:
				a.field = b.uid; b.field = a.uid
				a.fstep = 0.0; b.fstep = 0.0
				if a.p == 1 or b.p == 1:
					var mine := a if a.p == 1 else b
					var theirs := b if a.p == 1 else a
					sim.emit_log("Your %s met %s of %s's in the field." % [_column_words(mine), _column_words(theirs), sim.players[theirs.p - 1].name], Color("e6c070"), Vector2i(pa.round()))
				break
			if d <= 7.5:
				_column_volleys(a, b, d)
				_column_volleys(b, a, d)
	# battles under way
	var done := {}
	for a: Sim.Attack in sim.attacks.duplicate():
		if a.field == 0 or done.has(a.uid):
			continue
		var b := _by_uid(a.field)
		if b == null or b.n <= 0 or not Diplomacy.at_war(sim, a.p, b.p):
			a.field = 0
			continue
		done[a.uid] = true; done[b.uid] = true
		# both stand still while they fight: their march waits
		a.t0 += dt; a.t1 += dt; b.t0 += dt; b.t1 += dt
		a.fstep += dt
		if a.fstep < 1.0:
			continue
		a.fstep = 0.0
		var pa := sim.players[a.p - 1]
		var pb := sim.players[b.p - 1]
		for r in mini(3, mini(a.n, b.n)):
			if a.n <= 0 or b.n <= 0:
				break
			var ak := Sim.mix_pick(a.amix, sim.rng)
			var bk := Sim.mix_pick(b.amix, sim.rng)
			var aw: float = 0.5 + 0.15 * (a.vet - b.vet) + sim.mod(pa, "attack") - sim.mod(pb, "attack")
			aw += 0.03 * (Sim.level(a.sxp, Sim.SOLDIER_XP) - Sim.level(b.sxp, Sim.SOLDIER_XP))
			aw += 0.035 * (ak - bk) + COUNTER * (int(ADV[ak][bk]) - int(ADV[bk][ak]))
			aw += _melee_edge(ak, false) - _melee_edge(bk, false)
			var ab := _picks_blunt(a.blunt, a.n)
			var bb := _picks_blunt(b.blunt, b.n)
			if ab: aw -= BLUNT_DUEL
			if bb: aw += BLUNT_DUEL
			if not ab and sim.rng.randf() < _wear(a.p):
				a.blunt = mini(a.blunt + 1, a.n)
			if not bb and sim.rng.randf() < _wear(b.p):
				b.blunt = mini(b.blunt + 1, b.n)
			if sim.rng.randf() < aw:
				if bk == 3 and ak < 4 and sim.rng.randf() < 0.5:
					continue
				_fall(b, pb, bk)
				a.sxp += 3.0 / maxf(1.0, a.n)
			else:
				if ak == 3 and bk < 4 and sim.rng.randf() < 0.5:
					continue
				_fall(a, pa, ak)
				b.sxp += 3.0 / maxf(1.0, b.n)
		if a.n <= 0 or b.n <= 0:
			_field_end(a if a.n > 0 else b, b if a.n > 0 else a)
	# the fallen columns go
	for k in range(sim.attacks.size() - 1, -1, -1):
		if sim.attacks[k].n <= 0 and not sim.attacks[k].fighting:
			sim.attacks.remove_at(k)


## A soldier of kind k falls in column a.
func _fall(a: Sim.Attack, p: Sim.Player, k: int) -> void:
	Sim.mix_remove(a.amix, k)
	a.n -= 1
	if _picks_blunt(a.blunt, a.n + 1):
		a.blunt -= 1
	a.blunt = clampi(a.blunt, 0, a.n)
	a.era = Sim.mix_avg(a.amix)
	p.vets = maxf(0.0, p.vets - a.vet)


func _field_end(won: Sim.Attack, lost: Sim.Attack) -> void:
	won.field = 0
	lost.field = 0
	Chronicle.note(sim, sim.players[won.p - 1], "field_won", {"o": lost.p})
	if won.p == 1 or lost.p == 1:
		var t: Sim.Bld = sim.by_id.get(won.tgt)
		var where := String(t.def.name).to_lower() if t != null else "their target"
		if won.p == 1 and won.chase != 0:
			sim.emit_log("Field battle won: the enemy column is stopped. %d of yours go home." % won.n, Color("86ad5c"), Vector2i(column_pos(won).round()))
		elif lost.p == 1 and won.chase != 0:
			sim.emit_log("Field battle lost: your column was stopped on the way and all fell.", Color("e08a6a"), Vector2i(column_pos(won).round()))
		elif won.p == 1:
			sim.emit_log("Field battle won: %d of yours left, marching on to the %s." % [won.n, where], Color("86ad5c"), Vector2i(column_pos(won).round()))
		else:
			sim.emit_log("Field battle lost: all your soldiers fell. %d of %s's march on to your %s." % [won.n, sim.players[won.p - 1].name, where], Color("e08a6a"), Vector2i(column_pos(won).round()))


func _column_words(a: Sim.Attack) -> String:
	var k := Sim.mix_newest(a.amix)
	var only := k >= 0 and int(a.amix[k]) == a.n
	if only:
		return "%d %s" % [a.n, Sim.soldier_name(k) if a.n == 1 else Sim.soldier_plural(k)]
	return "%d soldier%s" % [a.n, "" if a.n == 1 else "s"]


## Cartridges (build 57): musketeers and riflemen fire only with them. One cartridge is AMMO_SHOTS
## shots; a column carries enough for AMMO_VOLLEYS volleys when it sets out (as far as the stores have
## them), and a garrison's guns take theirs from the realm's stores as they fire.
const AMMO_SHOTS := 10
const AMMO_VOLLEYS := 4


static func shooters_of(mix: Array) -> int:
	var n := 0
	for g in GUNS:
		if mix.size() > g:
			n += int(mix[g])
	return n


## How many of `shooters` can fire a volley with the cartridges column a carries (they are used).
func _ammo_for(a: Sim.Attack, shooters: int) -> int:
	var can := mini(shooters, a.ammo * AMMO_SHOTS)
	a.ammo -= ceili(float(can) / AMMO_SHOTS)
	return can


## ... and for a garrison of realm p, from its stores.
func _ammo_from_stores(p: Sim.Player, shooters: int) -> int:
	var need := ceili(float(shooters) / AMMO_SHOTS)
	var got := int(sim.take(p, "ammunition", float(need)))
	if got > 0:
		sim.used(p, "ammunition", float(got))
	return mini(shooters, got * AMMO_SHOTS)


## Column a's musketeers and riflemen fire on column b, d tiles away.
func _column_volleys(a: Sim.Attack, b: Sim.Attack, d: float) -> void:
	var pb := sim.players[b.p - 1]
	for g: int in GUNS:
		var gun: Array = GUNS[g]
		var shooters := int(a.amix[g]) if a.amix.size() > g else 0
		if shooters > 0 and d <= float(gun[0]) and sim.time >= float(a.vt[g - GUN0]):
			shooters = _ammo_for(a, shooters)
		if shooters <= 0 or d > float(gun[0]) or sim.time < float(a.vt[g - GUN0]):
			continue
		a.vt[g - GUN0] = sim.time + float(gun[1])
		a.shot_t = sim.time
		for s in shooters:
			if b.n > 0 and sim.rng.randf() < float(gun[2]):
				_fall(b, pb, Sim.mix_pick(b.amix, sim.rng))


func _retreat(a: Sim.Attack, p: Sim.Player) -> void:
	var s: Sim.Bld = sim.by_id.get(a.src)
	Sim.mix_fix(a.amix, a.n, roundi(a.era))
	if s != null and s.p == a.p and s.ty != "hq" and a.sea == 0:
		s.sxp = Sim.mix_xp(s.sxp, s.garrison, a.sxp, a.n)
		Sim.mix_add(sim.gmix_of(s), a.amix)
		s.garrison += a.n
		s.blunt = mini(s.blunt + a.blunt, s.garrison)
		s.sera = Sim.mix_avg(s.gmix)
	else:
		p.res_xp = Sim.mix_xp(p.res_xp, p.reserve, a.sxp, a.n)
		Sim.mix_add(sim.rmix_of(p), a.amix)
		p.reserve += a.n
		p.blunt = mini(p.blunt + a.blunt, p.reserve)
		p.res_era = Sim.mix_avg(p.rmix)


func _capture(a: Sim.Attack, t: Sim.Bld, p: Sim.Player, op: Sim.Player) -> void:
	Sim.mix_fix(a.amix, a.n, roundi(a.era))
	sim.naval.general_learns(a, 5.0)
	if t.ty == "hq":
		p.res_xp = Sim.mix_xp(p.res_xp, p.reserve, a.sxp, a.n)
		Sim.mix_add(sim.rmix_of(p), a.amix)
		p.reserve += a.n
		p.blunt = mini(p.blunt + a.blunt, p.reserve)
		p.res_era = Sim.mix_avg(p.rmix)
		eliminate(op, p)
		return
	var old_p := t.p
	# a captured store (a harbour) keeps its goods: they are the winner's now
	var plunder := {}
	if t.def.has("store"):
		plunder = t.inv.duplicate()
		for k in plunder:
			sim.logistics.store_add(t, op, k, -float(plunder[k]))
	sim.logistics._set_ver += 1
	t.p = p.id; t.garrison = 1; t.staffed = false; t.path = PackedInt32Array(); t.out_buf = {}
	t.blunt = 0; t.archers = 0; t.archer_want = 0; t.sally = false
	p.blunt = mini(p.blunt + a.blunt, p.reserve + a.n - 1)
	if t.def.has("store"):
		for k in plunder:
			sim.logistics.store_add(t, p, k, float(plunder[k]))
		sim.logistics._store_ver += 1
		sim._recount_stores(p)
		sim._recount_stores(op)
		sim._clamp_stock(op)
	# the loser's roads lost a building (a full rebuild); the winner gained one
	sim.net_dirty(old_p)
	sim._after_building_change(t)
	t.sxp = a.sxp; t.wxp = 0.0
	# the best of them holds the captured building; the rest go home
	t.gmix = Sim.mix_take_best(a.amix, 1)
	t.sera = Sim.mix_avg(t.gmix)
	# (to the building they came from while it has room, so it can attack again; else headquarters)
	var back: Sim.Bld = sim.by_id.get(a.src)
	var rest := a.n - 1
	if back != null and back.p == p.id and back.ty != "hq" and back.state == "ready" and not back.dead:
		var room := maxi(0, sim.garrison_wanted(back) - back.garrison - back.walking)
		var home_n := mini(room, rest)
		if home_n > 0:
			var hm := Sim.mix_take_best(a.amix, home_n)
			back.sxp = Sim.mix_xp(back.sxp, back.garrison, a.sxp, home_n)
			Sim.mix_add(sim.gmix_of(back), hm)
			back.garrison += home_n
			back.sera = Sim.mix_avg(back.gmix)
			rest -= home_n
	p.res_xp = Sim.mix_xp(p.res_xp, p.reserve, a.sxp, rest)
	Sim.mix_add(sim.rmix_of(p), a.amix)
	p.reserve += rest
	p.res_era = Sim.mix_avg(p.rmix)
	Chronicle.note(sim, p, "capture", {"o": op.id, "b": t.ty})
	if sim.spectating():
		sim.emit_log("%s captured a %s from %s." % [p.name, String(t.def.name), op.name], Color("d8aa4a"), Vector2i(t.x, t.y))
	elif p.id == 1 or op.id == 1:
		sim.emit_log("%s captured a %s%s" % [p.name, String(t.def.name), " from you!" if op.id == 1 else " from %s." % op.name], Color("e0603a") if op.id == 1 else Color("d8aa4a"), Vector2i(t.x, t.y))
	recompute_territory()


func eliminate(op: Sim.Player, by: Sim.Player) -> void:
	op.alive = false
	Chronicle.note(sim, op, "fall", {"by": by.id})
	var you := op.id == 1 and not sim.spectating()
	sim.emit_log("%s %s been defeated by %s!" % [op.name, "have" if you else "has", by.name], Color("e0603a") if you else Color("d8aa4a"))
	for b in sim.blds.duplicate():
		if b.p == op.id:
			b.garrison = 0
			b.gmix = []
			sim.destroy(b)
	var kept: Array[Sim.Trip] = []
	for t in sim.trips:
		if t.p != op.id: kept.append(t)
	sim.trips = kept
	var ka: Array[Sim.Attack] = []
	for a in sim.attacks:
		if a.p != op.id: ka.append(a)
	sim.attacks = ka
	Diplomacy.drop_proposals(sim, op.id, 0)
	recompute_territory()
	_check_end()


func _check_alliance_end() -> void:
	if sim.spectating():
		return
	var allied := 0
	var alive := 0
	for p in sim.players:
		if p.ai and p.alive:
			alive += 1
			if Diplomacy.relation(sim, 1, p.id) == Diplomacy.ALLY:
				allied += 1
	if alive > 0 and allied == alive and alive * 2 <= sim.players.size() - 1:
		_check_end()


func _check_end() -> void:
	if sim.over:
		return
	# spectator mode (build 77): the game ends when one realm is left standing
	if sim.spectating():
		var left: Array = sim.players.filter(func(q): return q.alive)
		if left.size() <= 1:
			sim.over = true
			if left.size() == 1:
				sim.emit_log("%s is the last realm standing." % (left[0] as Sim.Player).name, Color("d8aa4a"))
			sim.ended.emit(true)
		return
	if not sim.players[0].alive:
		sim.over = true
		sim.ended.emit(false)
		return
	var alive := 0
	var allied := 0
	for p in sim.players:
		if p.ai and p.alive:
			alive += 1
			if Diplomacy.relation(sim, 1, p.id) == Diplomacy.ALLY:
				allied += 1
	if alive > 0 and (allied < alive or alive * 2 > sim.players.size() - 1):
		return
	sim.over = true
	if alive > 0:
		sim.emit_log("Every remaining realm is your ally. Allied victory!", Color("d8aa4a"))
	sim.ended.emit(true)


## Gunfire while an attack approaches: the attackers' musketeers and riflemen fire on the defenders
## once in range, and the defenders' guns fire back, each kind with its own range and reload time.
func _volleys(a: Sim.Attack, p: Sim.Player, t: Sim.Bld) -> void:
	var left := column_pos(a).distance_to(a.to)
	for g: int in GUNS:
		var gun: Array = GUNS[g]
		if left > float(gun[0]):
			# (build 75) out of this gun's range nobody fires: only the column's age is brought up to
			# date, as below, without looking for the defenders unless it changed
			if a.era != Sim.mix_avg(a.amix) and own_def(_defending(t)) > 0:
				a.era = Sim.mix_avg(a.amix)
			continue
		var shooters := int(a.amix[g]) if a.amix.size() > g else 0
		if shooters > 0 and left <= float(gun[0]) and sim.time >= float(a.vt[g - GUN0]):
			shooters = _ammo_for(a, shooters)
		if shooters > 0 and left <= float(gun[0]) and sim.time >= float(a.vt[g - GUN0]):
			a.vt[g - GUN0] = sim.time + float(gun[1])
			a.shot_t = sim.time
			var hits := 0
			for s in shooters:
				if sim.rng.randf() < float(gun[2]):
					hits += 1
			a.hits = 0
			for h in hits:
				if defenders(t) <= 0:
					break
				kill_defender(t)
				a.hits += 1
		var db := _defending(t)
		if own_def(db) <= 0:
			continue
		# the defenders' musketeers and riflemen fire back (the building's cannon fire below)
		var dm := mix_of(db)
		var dshooters := int(dm[g])
		if dshooters > 0 and left <= float(gun[0]) and sim.time >= float(a.dvt[g - GUN0]):
			dshooters = _ammo_from_stores(sim.players[db.p - 1], dshooters)
		if dshooters > 0 and left <= float(gun[0]) and sim.time >= float(a.dvt[g - GUN0]):
			a.dvt[g - GUN0] = sim.time + float(gun[1])
			a.dshot_t = sim.time
			for s in dshooters:
				if a.n > 0 and sim.rng.randf() < float(gun[2]):
					Sim.mix_remove(a.amix, Sim.mix_pick(a.amix, sim.rng))
					a.n -= 1
					p.vets = maxf(0.0, p.vets - a.vet)
			a.era = Sim.mix_avg(a.amix)
	_cannon(a, p, t, left)
	_arrows(a, p, t, left)


## Forts with cannon (gun battery, star fort, redoubt) fire on an approaching attack while they
## have at least one soldier to work the guns: [range, seconds to reload, guns, chance each hits].
func _cannon(a: Sim.Attack, p: Sim.Player, t: Sim.Bld, left: float) -> void:
	var gun: Array = t.def.get("cannon", [])
	if gun.is_empty() or t.state != "ready" or own_def(t) <= 0 or left > float(gun[0]):
		return
	# the guns fire only with gunpowder in store: a charge for each volley
	if t.def.has("in") and int(t.inbuf.get("gunpowder", 0)) <= 0:
		return
	while a.dvt.size() < 3:
		a.dvt.append(0.0)
	if sim.time < float(a.dvt[2]):
		return
	a.dvt[2] = sim.time + float(gun[1])
	a.dshot_t = sim.time
	if t.def.has("in"):
		_use_powder(t)
	for s in int(gun[2]):
		if a.n > 0 and sim.rng.randf() < float(gun[3]):
			Sim.mix_remove(a.amix, Sim.mix_pick(a.amix, sim.rng))
			a.n -= 1
			p.vets = maxf(0.0, p.vets - a.vet)
	a.era = Sim.mix_avg(a.amix)


## A fort's guns fire a volley: one charge of gunpowder from its store.
func _use_powder(t: Sim.Bld) -> void:
	var n := int(t.inbuf.get("gunpowder", 0))
	if n <= 1:
		t.inbuf.erase("gunpowder")
	else:
		t.inbuf["gunpowder"] = n - 1
	sim.used(sim.players[t.p - 1], "gunpowder", 1.0)
