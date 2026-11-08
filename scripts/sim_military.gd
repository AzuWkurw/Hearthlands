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
## what demolishing it would do).
func compute_owner(without: int) -> PackedByteArray:
	var own := PackedByteArray()
	own.resize(sim.w * sim.h)
	var mils: Array[Sim.Bld] = []
	for b in sim.blds:
		if b.id != without and b.state == "ready" and (b.ty == "hq" or (b.def.has("garrison") and b.garrison > 0)):
			mils.append(b)
	for b in mils:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if sim.inb(b.x + dx, b.y + dy) and own[sim.idx(b.x + dx, b.y + dy)] == 0:
					own[sim.idx(b.x + dx, b.y + dy)] = b.p
		own[sim.idx(b.x, b.y)] = b.p
	for b in mils:
		var r := int(b.def.get("radius", 6))
		var r2 := r * r
		for y in range(maxi(0, b.y - r), mini(sim.h - 1, b.y + r) + 1):
			for x in range(maxi(0, b.x - r), mini(sim.w - 1, b.x + r) + 1):
				var dx := x - b.x
				var dy := y - b.y
				if dx * dx + dy * dy <= r2 and own[y * sim.w + x] == 0:
					own[y * sim.w + x] = b.p
	return own


## What demolishing military building b would cost its realm: {"tiles": land lost,
## "rival": how much of it a rival gets, "blds": buildings left outside the border}.
func territory_loss(b: Sim.Bld) -> Dictionary:
	var out := {"tiles": PackedInt32Array(), "rival": 0, "blds": []}
	if not (b.state == "ready" and b.def.has("garrison") and b.garrison > 0):
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


func owned(pid: int) -> Array:
	if sim._owned_dirty:
		_owned = []
		_owned_mtn = []
		for p in sim.players:
			_owned.append(PackedInt32Array())
			_owned_mtn.append(PackedInt32Array())
		for i in sim.owner.size():
			var o := sim.owner[i]
			if o == 0:
				continue
			_owned[o - 1].append(i)
			if sim.ter[i] == Sim.MOUNT and sim.ore[i] != 0 and sim.vein_left(i) > 0:
				_owned_mtn[o - 1].append(i)
		sim._owned_dirty = false
	return [_owned[pid - 1], _owned_mtn[pid - 1]]


func own_def(b: Sim.Bld) -> int:
	return sim.players[b.p - 1].reserve if b.ty == "hq" else b.garrison


func helpers(t: Sim.Bld) -> Array:
	var out := []
	for b: Sim.Bld in sim.mil_list():
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


func defenders(t: Sim.Bld) -> int:
	var n := own_def(t)
	for hh in helpers(t):
		n += int(hh[1])
	return n


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
		sim.players[b.p - 1].reserve -= 1
		sim.players[b.p - 1].res_era = Sim.mix_avg(m)
	else:
		b.garrison -= 1
		b.sera = Sim.mix_avg(m)


## The soldiers in building b by kind (headquarters: the realm's reserve).
func mix_of(b: Sim.Bld) -> Array:
	return sim.rmix_of(sim.players[b.p - 1]) if b.ty == "hq" else sim.gmix_of(b)


## Kinds of soldier: what each is strong against. ADV[x][y] = 1 when kind x beats kind y.
## 0 legionary, 1 spearman, 2 man-at-arms, 3 pikeman, 4 musketeer, 5 rifleman.
const ADV := [
	[0, 1, 0, 0, 0, 0],   # legionaries beat spearmen
	[0, 0, 0, 0, 0, 0],   # spearmen: cheap and quick to train instead
	[1, 1, 0, 0, 0, 0],   # men-at-arms beat legionaries and spearmen
	[1, 0, 1, 0, 0, 0],   # pikemen beat legionaries and men-at-arms
	[0, 0, 0, 1, 0, 0],   # musketeers beat pikemen
	[1, 1, 1, 1, 1, 0],   # riflemen beat everything older
]
const COUNTER := 0.12      # win chance gained by a kind against one it beats
## Guns: [range in tiles, seconds to reload, chance each shot fells a soldier]
const GUNS := {4: [4.0, 6.0, 0.2], 5: [7.0, 2.5, 0.25]}


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
		0: return 0.06 if defending else 0.0
		3: return 0.06 if defending else 0.0
		4: return -0.04
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


## Average age of the soldiers defending t (0 legionaries ... 5 riflemen).
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
func launch_attack(src: Sim.Bld, tgt: Sim.Bld, want := -1, kinds: Array = []) -> String:
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
	if src.ty == "hq": p.reserve -= n
	else: src.garrison -= n
	var a := Sim.Attack.new()
	a.p = src.p; a.src = src.id; a.tgt = tgt.id; a.n = n; a.n0 = n; a.t0 = sim.time; a.t1 = sim.time + dist * 1.1 + 1.0
	a.from = Vector2(src.x, src.y); a.to = Vector2(tgt.x, tgt.y)
	a.vet = clampf(p.vets / maxf(1.0, sim.soldiers(p) + n), 0.0, 1.0)
	a.sxp = p.res_xp if src.ty == "hq" else src.sxp
	a.amix = sent
	a.era = Sim.mix_avg(sent)
	a.vt = [a.t0, a.t0]
	a.dvt = [a.t0, a.t0]
	sim._bid += 1
	a.uid = sim._bid
	sim.attacks.append(a)
	Diplomacy.on_attacked(sim, tgt.p, src.p)
	if tgt.p == 1:
		sim.emit_log("%s attacks your %s with %d soldiers!" % [p.name, String(tgt.def.name), n], Color("e0603a"), Vector2i(tgt.x, tgt.y))
	elif src.p == 1:
		sim.emit_log("Your %d soldiers march on %s." % [n, sim.players[tgt.p - 1].name], Color("d8aa4a"), Vector2i(tgt.x, tgt.y))
	return ""


func attack_tick(dt: float) -> void:
	_field_battles(dt)
	for k in range(sim.attacks.size() - 1, -1, -1):
		var a := sim.attacks[k]
		var p := sim.players[a.p - 1]
		var t: Sim.Bld = sim.by_id.get(a.tgt)
		if t == null or t.p == a.p or not p.alive or not Diplomacy.at_war(sim, a.p, t.p):
			_retreat(a, p)
			sim.attacks.remove_at(k)
			continue
		Sim.mix_fix(a.amix, a.n, roundi(a.era))
		if a.field != 0:
			continue                  # held up by a battle in the open (see _field_battles)
		if not a.fighting:
			# marching in: volleys both ways, then the fight at the gate
			_volleys(a, p, t)
			if a.n <= 0:
				sim.attacks.remove_at(k)
				if a.p == 1 or t.p == 1:
					sim.emit_log("The attack on %s was shot to pieces before it reached the gate." % String(t.def.name), Color("86ad5c") if t.p == 1 else Color("e08a6a"), Vector2i(t.x, t.y))
				continue
			if defenders(t) <= 0 and sim.time >= a.t1:
				_capture(a, t, p, sim.players[t.p - 1])
				sim.attacks.remove_at(k)
				continue
			if sim.time >= a.t1:
				a.fighting = true; a.step = 0.0
			continue
		# at the gate: the building's guns keep firing at the attackers outside the walls
		_cannon(a, p, t, 0.0)
		if a.n <= 0:
			sim.attacks.remove_at(k)
			if a.p == 1 or t.p == 1:
				sim.emit_log("The attack on %s was beaten back." % String(t.def.name), Color("86ad5c") if t.p == 1 else Color("e08a6a"), Vector2i(t.x, t.y))
			continue
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
			# one soldier of each side: the attacker comes as he is, the defenders send their best
			# answer to him. Later ages are stronger (+3.5% a duel per age, about 15% in strength);
			# some kinds beat others; and each kind has its own edge.
			var ak := Sim.mix_pick(a.amix, sim.rng)
			var dk := best_counter(mix_of(_defending(t)), ak)
			if dk < 0:
				dk = 1
			dw += 0.035 * (dk - ak) + COUNTER * (int(ADV[dk][ak]) - int(ADV[ak][dk]))
			dw += _melee_edge(dk, true) - _melee_edge(ak, false)
			if sim.rng.randf() < dw:
				# men-at-arms' armour turns half the blows that would fell them (not pikes or bullets)
				if ak == 2 and dk < 3 and sim.rng.randf() < 0.5:
					continue
				Sim.mix_remove(a.amix, ak)
				a.n -= 1
				a.era = Sim.mix_avg(a.amix)
				p.vets = maxf(0.0, p.vets - a.vet)
				_defender_gains_xp(t)
			else:
				if dk == 2 and ak < 3 and sim.rng.randf() < 0.5:
					continue
				kill_defender(t, dk)
				a.sxp += 3.0 / maxf(1.0, a.n)
		if a.n > 0 and p.ai and a.n0 >= 3 and a.n * 2 < a.n0 and defenders(t) > a.n:
			# a rival sees the attack going badly and calls the rest back
			_retreat(a, p)
			sim.attacks.remove_at(k)
			if t.p == 1:
				sim.emit_log("%s's attack on your %s falls back." % [p.name, String(t.def.name)], Color("86ad5c"), Vector2i(t.x, t.y))
			continue
		if a.n <= 0:
			sim.attacks.remove_at(k)
			if a.p == 1 or t.p == 1:
				sim.emit_log("The attack on %s was beaten back." % String(t.def.name), Color("86ad5c") if t.p == 1 else Color("e08a6a"), Vector2i(t.x, t.y))
			continue
		if defenders(t) <= 0:
			_capture(a, t, p, op)
			sim.attacks.remove_at(k)


## Where a marching column is now, in tiles.
func column_pos(a: Sim.Attack) -> Vector2:
	if a.fighting:
		return a.to
	return a.from.lerp(a.to, clampf((sim.time - a.t0) / maxf(0.01, a.t1 - a.t0), 0.0, 1.0))


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
			if sim.rng.randf() < aw:
				if bk == 2 and ak < 3 and sim.rng.randf() < 0.5:
					continue
				_fall(b, pb, bk)
				a.sxp += 3.0 / maxf(1.0, a.n)
			else:
				if ak == 2 and bk < 3 and sim.rng.randf() < 0.5:
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
	a.era = Sim.mix_avg(a.amix)
	p.vets = maxf(0.0, p.vets - a.vet)


func _field_end(won: Sim.Attack, lost: Sim.Attack) -> void:
	won.field = 0
	lost.field = 0
	if won.p == 1 or lost.p == 1:
		var t: Sim.Bld = sim.by_id.get(won.tgt)
		var where := String(t.def.name).to_lower() if t != null else "their target"
		if won.p == 1:
			sim.emit_log("Field battle won: %d of yours left, marching on to the %s." % [won.n, where], Color("86ad5c"), Vector2i(column_pos(won).round()))
		else:
			sim.emit_log("Field battle lost: all your soldiers fell. %d of %s's march on to your %s." % [won.n, sim.players[won.p - 1].name, where], Color("e08a6a"), Vector2i(column_pos(won).round()))


func _column_words(a: Sim.Attack) -> String:
	var k := Sim.mix_newest(a.amix)
	var only := k >= 0 and int(a.amix[k]) == a.n
	if only:
		return "%d %s" % [a.n, Sim.soldier_name(k) if a.n == 1 else Sim.soldier_plural(k)]
	return "%d soldier%s" % [a.n, "" if a.n == 1 else "s"]


## Column a's musketeers and riflemen fire on column b, d tiles away.
func _column_volleys(a: Sim.Attack, b: Sim.Attack, d: float) -> void:
	var pb := sim.players[b.p - 1]
	for g: int in GUNS:
		var gun: Array = GUNS[g]
		var shooters := int(a.amix[g]) if a.amix.size() > g else 0
		if shooters <= 0 or d > float(gun[0]) or sim.time < float(a.vt[g - 4]):
			continue
		a.vt[g - 4] = sim.time + float(gun[1])
		a.shot_t = sim.time
		for s in shooters:
			if b.n > 0 and sim.rng.randf() < float(gun[2]):
				_fall(b, pb, Sim.mix_pick(b.amix, sim.rng))


func _retreat(a: Sim.Attack, p: Sim.Player) -> void:
	var s: Sim.Bld = sim.by_id.get(a.src)
	Sim.mix_fix(a.amix, a.n, roundi(a.era))
	if s != null and s.p == a.p and s.ty != "hq":
		s.sxp = Sim.mix_xp(s.sxp, s.garrison, a.sxp, a.n)
		Sim.mix_add(sim.gmix_of(s), a.amix)
		s.garrison += a.n
		s.sera = Sim.mix_avg(s.gmix)
	else:
		p.res_xp = Sim.mix_xp(p.res_xp, p.reserve, a.sxp, a.n)
		Sim.mix_add(sim.rmix_of(p), a.amix)
		p.reserve += a.n
		p.res_era = Sim.mix_avg(p.rmix)


func _capture(a: Sim.Attack, t: Sim.Bld, p: Sim.Player, op: Sim.Player) -> void:
	Sim.mix_fix(a.amix, a.n, roundi(a.era))
	if t.ty == "hq":
		p.res_xp = Sim.mix_xp(p.res_xp, p.reserve, a.sxp, a.n)
		Sim.mix_add(sim.rmix_of(p), a.amix)
		p.reserve += a.n
		p.res_era = Sim.mix_avg(p.rmix)
		eliminate(op, p)
		return
	var old_p := t.p
	t.p = p.id; t.garrison = 1; t.staffed = false; t.path = PackedInt32Array(); t.out_buf = {}
	# the loser's roads lost a building (a full rebuild); the winner gained one
	sim.net_dirty(old_p)
	sim._after_building_change(t)
	t.sxp = a.sxp; t.wxp = 0.0
	# the best of them holds the captured building; the rest go home
	t.gmix = Sim.mix_take_best(a.amix, 1)
	t.sera = Sim.mix_avg(t.gmix)
	p.res_xp = Sim.mix_xp(p.res_xp, p.reserve, a.sxp, a.n - 1)
	Sim.mix_add(sim.rmix_of(p), a.amix)
	p.reserve += a.n - 1
	p.res_era = Sim.mix_avg(p.rmix)
	if p.id == 1 or op.id == 1:
		sim.emit_log("%s captured a %s%s" % [p.name, String(t.def.name), " from you!" if op.id == 1 else " from %s." % op.name], Color("e0603a") if op.id == 1 else Color("d8aa4a"), Vector2i(t.x, t.y))
	recompute_territory()


func eliminate(op: Sim.Player, by: Sim.Player) -> void:
	op.alive = false
	sim.emit_log("%s %s been defeated by %s!" % [op.name, "have" if op.id == 1 else "has", by.name], Color("e0603a") if op.id == 1 else Color("d8aa4a"))
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
	var f := clampf((sim.time - a.t0) / maxf(0.01, a.t1 - a.t0), 0.0, 1.0)
	var left := a.from.lerp(a.to, f).distance_to(a.to)
	for g: int in GUNS:
		var gun: Array = GUNS[g]
		var shooters := int(a.amix[g]) if a.amix.size() > g else 0
		if shooters > 0 and left <= float(gun[0]) and sim.time >= float(a.vt[g - 4]):
			a.vt[g - 4] = sim.time + float(gun[1])
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
		if dshooters > 0 and left <= float(gun[0]) and sim.time >= float(a.dvt[g - 4]):
			a.dvt[g - 4] = sim.time + float(gun[1])
			a.dshot_t = sim.time
			for s in dshooters:
				if a.n > 0 and sim.rng.randf() < float(gun[2]):
					Sim.mix_remove(a.amix, Sim.mix_pick(a.amix, sim.rng))
					a.n -= 1
					p.vets = maxf(0.0, p.vets - a.vet)
			a.era = Sim.mix_avg(a.amix)
	_cannon(a, p, t, left)


## Forts with cannon (gun battery, star fort, redoubt) fire on an approaching attack while they
## have at least one soldier to work the guns: [range, seconds to reload, guns, chance each hits].
func _cannon(a: Sim.Attack, p: Sim.Player, t: Sim.Bld, left: float) -> void:
	var gun: Array = t.def.get("cannon", [])
	if gun.is_empty() or t.state != "ready" or own_def(t) <= 0 or left > float(gun[0]):
		return
	while a.dvt.size() < 3:
		a.dvt.append(0.0)
	if sim.time < float(a.dvt[2]):
		return
	a.dvt[2] = sim.time + float(gun[1])
	a.dshot_t = sim.time
	for s in int(gun[2]):
		if a.n > 0 and sim.rng.randf() < float(gun[3]):
			Sim.mix_remove(a.amix, Sim.mix_pick(a.amix, sim.rng))
			a.n -= 1
			p.vets = maxf(0.0, p.vets - a.vet)
	a.era = Sim.mix_avg(a.amix)
