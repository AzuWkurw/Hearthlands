class_name Diplomacy
extends RefCounted
## Relations between realms (war, peace or alliance), each rival's opinion of every other realm,
## proposals (peace, alliance, trade and gifts) and how rival AIs decide on them.
## The state itself lives in Sim (rel, rel_since, proposals, and Player.opinion) so it is saved with the game.

const WAR := 0
const PEACE := 1
const ALLY := 2
const NAMES := ["War", "Peace", "Alliance"]
const PROPOSAL_LIFE := 150.0


static func key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


static func relation(sim: Sim, a: int, b: int) -> int:
	if a == b:
		return ALLY
	return int(sim.rel.get(key(a, b), WAR))


static func at_war(sim: Sim, a: int, b: int) -> bool:
	return a != b and relation(sim, a, b) == WAR


## Seconds since the relation between a and b last changed.
static func since(sim: Sim, a: int, b: int) -> float:
	return sim.time - float(sim.rel_since.get(key(a, b), 0.0))


static func set_relation(sim: Sim, a: int, b: int, r: int) -> void:
	if relation(sim, a, b) == r:
		return
	sim.rel[key(a, b)] = r
	sim.rel_since[key(a, b)] = sim.time
	var na := sim.players[a - 1].name
	var nb := sim.players[b - 1].name
	var text := ""
	match r:
		WAR: text = "%s declared war on %s." % [na, nb]
		PEACE: text = "%s and %s made peace." % [na, nb]
		ALLY: text = "%s and %s formed an alliance." % [na, nb]
	var col := Color("e0603a") if r == WAR else Color("8fc0ff")
	sim.emit_log(text, col if (a == 1 or b == 1) else Color("b0a8d0"))
	sim.diplomacy_changed.emit()


# ---------------------------------------------------------------- opinions
static func base_opinion(p: Sim.Player) -> float:
	return 10.0 if p.pers == "builder" else (-20.0 if p.pers == "warlord" else 0.0)


static func opinion(p: Sim.Player, other: int) -> float:
	return float(p.opinion.get(other, base_opinion(p)))


static func adjust(p: Sim.Player, other: int, d: float) -> void:
	p.opinion[other] = clampf(opinion(p, other) + d, -100.0, 100.0)


static func mood(v: float) -> String:
	if v >= 50.0: return "Trusting"
	if v >= 20.0: return "Friendly"
	if v > -20.0: return "Neutral"
	if v > -50.0: return "Wary"
	return "Hostile"


## Realms far apart have less to fight over: up to +15 towards peace.
static func distance_bonus(sim: Sim, a: int, b: int) -> float:
	var ha: Sim.Bld = sim.players[a - 1].hq
	var hb: Sim.Bld = sim.players[b - 1].hq
	if ha == null or hb == null:
		return 0.0
	return clampf((Vector2(ha.x - hb.x, ha.y - hb.y).length() - 40.0) / 2.0, 0.0, 15.0)


static func strength(sim: Sim, p: Sim.Player) -> float:
	return sim.soldiers(p) + p.vets * 0.5


## Called when `attacker` attacks one of `victim`'s buildings.
static func on_attacked(sim: Sim, victim: int, attacker: int) -> void:
	adjust(sim.players[victim - 1], attacker, -25.0)
	for q in sim.players:
		if q.alive and q.id != victim and q.id != attacker and relation(sim, q.id, victim) == ALLY:
			adjust(q, attacker, -10.0)


## Breaking a peace or an alliance makes every realm trust the breaker less.
## Whether realms a and b have military buildings within attack reach of each other.
static func borders(sim: Sim, a: int, b: int) -> bool:
	var ma: Array = []
	var mb: Array = []
	for m in sim.mil_list():
		if m.dead or m.state != "ready": continue
		if m.p == a: ma.append(m)
		elif m.p == b: mb.append(m)
	for x: Sim.Bld in ma:
		for y: Sim.Bld in mb:
			if Vector2(x.x - y.x, x.y - y.y).length() <= Sim.RANGE:
				return true
	return false


static func declare_war(sim: Sim, a: int, b: int) -> void:
	var was := relation(sim, a, b)
	if was == WAR:
		return
	set_relation(sim, a, b, WAR)
	adjust(sim.players[b - 1], a, -50.0)
	for q in sim.players:
		if q.alive and q.id != a and q.id != b:
			adjust(q, a, -15.0 if was == ALLY else -8.0)
	drop_proposals(sim, a, b)


# ---------------------------------------------------------------- goods and value
## What n units are worth to realm p. Things a realm is short of are worth more to it.
static func value(p: Sim.Player, res: String, n: int, receiving: bool) -> float:
	var base := GameData.res_value(res) * n
	var have := float(p.stock.get(res, 0.0))
	if receiving:
		return base * (1.6 if have < 10.0 else (1.0 if have < 40.0 else 0.6))
	return base * (1.8 if have - n < 10.0 else 1.0)


static func total(p: Sim.Player, goods: Dictionary, receiving: bool) -> float:
	var t := 0.0
	for k in goods:
		t += value(p, k, int(goods[k]), receiving)
	return t


static func has_goods(p: Sim.Player, goods: Dictionary) -> bool:
	for k in goods:
		if float(p.stock.get(k, 0.0)) < float(goods[k]):
			return false
	return true


static func goods_text(goods: Dictionary) -> String:
	var parts := []
	for k in goods:
		parts.append("%d %s" % [int(goods[k]), GameData.res_name(k).to_lower()])
	return ", ".join(parts) if parts.size() > 0 else "nothing"


## The most of `want_res` AI realm p would hand over in return for `give`.
static func fair_amount(sim: Sim, p: Sim.Player, from: int, give: Dictionary, want_res: String) -> int:
	var best := 0
	var have := int(p.stock.get(want_res, 0.0))
	for n in range(1, have + 1):
		if ai_answer(sim, p, "trade", from, give, {want_res: n}) == "":
			best = n
		else:
			break
	return best


# ---------------------------------------------------------------- carts
const CART_SPEED := 1.2      # tiles a second, overland

## Where realm p's trade carts leave from and arrive: its first market, else (for the far end of a
## trade only) its headquarters. null when it has neither.
static func market(sim: Sim, p: Sim.Player, or_hq := false) -> Sim.Bld:
	for b in sim.blds:
		if b.ty == "market" and b.p == p.id and b.state == "ready" and not b.dead:
			return b
	if or_hq and p.hq != null and not p.hq.dead:
		return p.hq
	return null


## The tiles of a straight line from a to b (the way a trade cart goes, overland).
static func _line(sim: Sim, a: Vector2i, b: Vector2i) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for k in n + 1:
		var t := float(k) / maxf(1.0, n)
		out.append(sim.idx(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t))))
	return out


## Sends n of res from realm a to realm b by cart: a Trip of kind "trade" from a's market to b's.
static func send_cart(sim: Sim, a: Sim.Player, b: Sim.Player, res: String, n: float) -> void:
	if n <= 0.0:
		return
	var src := market(sim, a, true)
	var dst := market(sim, b, true)
	if src == null or dst == null:
		sim.give(b, res, n)
		return
	var t := Sim.Trip.new()
	t.p = a.id; t.kind = "trade"; t.res = res; t.n = roundi(n); t.dest = dst.id; t.site = src.id; t.aim = b.id
	t.path = _line(sim, Vector2i(src.x, src.y), Vector2i(dst.x, dst.y))
	var tt := maxf(4.0, float(t.path.size()) / CART_SPEED)
	t.t0 = sim.time; t.t1 = sim.time + tt; t.t2 = t.t1 + tt
	sim.trips.append(t)


## A trade cart arrived: its goods go into the market (or headquarters) it went to. If the two
## realms went to war meanwhile, the goods are lost on the way.
static func cart_arrival(sim: Sim, t: Sim.Trip) -> void:
	var to := sim.players[t.aim - 1]
	if at_war(sim, t.p, t.aim) or not to.alive:
		if t.p == 1 or t.aim == 1:
			sim.emit_log("A trade cart with %d %s was lost: you are at war now." % [t.n, GameData.res_name(t.res).to_lower()], Color("e0b060"))
		return
	var dest: Sim.Bld = sim.by_id.get(t.dest)
	if dest != null and not dest.dead and dest.p == to.id and dest.def.has("store"):
		sim.logistics.store_add(dest, to, t.res, float(t.n))
	else:
		sim.give(to, t.res, float(t.n))
	if t.aim == 1:
		sim.emit_log("A trade cart from %s brought %d %s." % [sim.players[t.p - 1].name, t.n, GameData.res_name(t.res).to_lower()], Color("8fc0ff"))


# ---------------------------------------------------------------- standing offers
## Your standing offers: the same trade proposed again every `every` seconds. Each is
## {"to", "give", "want", "every", "next", "done"}.
static func add_standing(sim: Sim, to: int, give: Dictionary, want: Dictionary, every: float) -> void:
	sim.standing.append({"to": to, "give": give, "want": want, "every": every, "next": sim.time + every, "done": 1})
	sim.diplomacy_changed.emit()


static func standing_tick(sim: Sim) -> void:
	for so in sim.standing.duplicate():
		if sim.time < float(so.next):
			continue
		so.next = sim.time + float(so.every)
		var q := sim.players[int(so.to) - 1]
		if not q.alive:
			sim.standing.erase(so)
			continue
		var kind := "gift" if (so.want as Dictionary).is_empty() else "trade"
		var why := propose(sim, 1, q.id, kind, so.give, so.want)
		if why == "":
			so.done = int(so.done) + 1
		elif why != "pending":
			sim.emit_log("Standing offer to %s not made this time: %s" % [q.name, why], Color("e0b060"))
	sim.diplomacy_changed.emit()


# ---------------------------------------------------------------- deciding
## Would AI realm p accept this proposal from realm `from`? Returns "" for yes, or why not.
static func ai_answer(sim: Sim, p: Sim.Player, kind: String, from: int, give: Dictionary, want: Dictionary) -> String:
	var q := sim.players[from - 1]
	var op := opinion(p, from)
	var rel := relation(sim, p.id, from)
	match kind:
		"peace":
			if rel != WAR:
				return "You are not at war with %s." % p.name
			var ratio := strength(sim, q) / maxf(1.0, strength(sim, p))
			var score := op + (ratio - 1.0) * 25.0 + (-15.0 if p.pers == "warlord" else (5.0 if p.pers == "builder" else 0.0)) + distance_bonus(sim, p.id, from)
			return "" if score > -5.0 else "%s does not trust you enough for peace (opinion %d)." % [p.name, roundi(op)]
		"alliance":
			if rel != PEACE:
				return "You need to be at peace with %s first." % p.name
			if since(sim, p.id, from) < 180.0:
				return "%s wants to see the peace hold for a few minutes first." % p.name
			var need := 50.0 if p.pers == "warlord" else (30.0 if p.pers == "builder" else 40.0)
			return "" if op >= need else "%s is not friendly enough for an alliance (opinion %d, needs %d)." % [p.name, roundi(op), roundi(need)]
		"trade", "gift":
			if rel == WAR:
				return "%s will not trade while you are at war." % p.name
			if market(sim, q) == null:
				return "You need a market to trade: build one (Stores and roads)." if not q.ai else "%s has no market." % q.name
			if not has_goods(q, give):
				return "You do not have that much to give."
			if not has_goods(p, want):
				return "%s does not have that much to spare." % p.name
			if want.is_empty():
				return ""
			var gain := total(p, give, true)
			var loss := total(p, want, false)
			var margin := 1.15 - op / 400.0 + (0.1 if p.pers == "warlord" else 0.0)
			return "" if gain >= loss * margin else "%s does not think that is a fair deal." % p.name
	return "Unknown proposal."


## Carries out an accepted proposal.
static func execute(sim: Sim, kind: String, from: int, to: int, give: Dictionary, want: Dictionary) -> void:
	var a := sim.players[from - 1]
	var b := sim.players[to - 1]
	match kind:
		"peace":
			set_relation(sim, from, to, PEACE)
			adjust(a, to, 10.0); adjust(b, from, 10.0)
		"alliance":
			set_relation(sim, from, to, ALLY)
			adjust(a, to, 10.0); adjust(b, from, 10.0)
		"trade", "gift":
			# the goods leave now and go by cart, market to market (or to the headquarters of a realm
			# that has no market)
			for k in give:
				var g := sim.take(a, k, float(give[k]))
				send_cart(sim, a, b, k, g)
			for k in want:
				var g2 := sim.take(b, k, float(want[k]))
				send_cart(sim, b, a, k, g2)
			if kind == "trade":
				a.trades += 1
				b.trades += 1
			var got := total(b, give, true)
			adjust(b, from, clampf(got * (1.5 if want.is_empty() else 0.3), 1.0, 20.0))
			adjust(a, to, 3.0)
			if from == 1 or to == 1:
				var other := b if from == 1 else a
				var gave := give if from == 1 else want
				var received := want if from == 1 else give
				if received.is_empty():
					sim.emit_log("You gave %s to %s. The carts are on their way." % [goods_text(gave), other.name], Color("8fc0ff"))
				else:
					sim.emit_log("Trade with %s: you give %s for %s. The carts are on their way." % [other.name, goods_text(gave), goods_text(received)], Color("8fc0ff"))
	sim.diplomacy_changed.emit()


## A realm proposes something. Rival AIs answer at once; proposals to you wait in the Diplomacy window.
## Returns "" when accepted, "pending" when waiting for you, or the reason it was refused.
static func propose(sim: Sim, from: int, to: int, kind: String, give := {}, want := {}) -> String:
	if not sim.players[from - 1].alive or not sim.players[to - 1].alive:
		return "That realm is gone."
	var target := sim.players[to - 1]
	if target.ai:
		var why := ai_answer(sim, target, kind, from, give, want)
		if why == "":
			execute(sim, kind, from, to, give, want)
		elif kind == "trade":
			adjust(target, from, -1.0)
		return why
	for pr in sim.proposals:
		if int(pr.from) == from and pr.kind == kind:
			return "pending"
	sim._prop_id += 1
	sim.proposals.append({"id": sim._prop_id, "from": from, "to": to, "kind": kind, "give": give, "want": want, "t": sim.time})
	var who := sim.players[from - 1].name
	match kind:
		"peace": sim.emit_log("%s offers peace. Answer in Diplomacy." % who, Color("8fc0ff"))
		"alliance": sim.emit_log("%s proposes an alliance. Answer in Diplomacy." % who, Color("8fc0ff"))
		_: sim.emit_log("%s offers %s for %s. Answer in Diplomacy." % [who, goods_text(give), goods_text(want)], Color("8fc0ff"))
	sim.diplomacy_changed.emit()
	return "pending"


## You accept a proposal that a rival made to you.
static func accept(sim: Sim, id: int) -> String:
	for pr in sim.proposals.duplicate():
		if int(pr.id) != id:
			continue
		sim.proposals.erase(pr)
		var me := sim.players[int(pr.to) - 1]
		var them := sim.players[int(pr.from) - 1]
		if not them.alive:
			return "That realm is gone."
		match String(pr.kind):
			"peace":
				if relation(sim, pr.from, pr.to) != WAR: return "You are no longer at war."
			"alliance":
				if relation(sim, pr.from, pr.to) != PEACE: return "You are no longer at peace."
			_:
				if not has_goods(me, pr.want): return "You no longer have what they asked for."
				if not has_goods(them, pr.give): return "%s no longer has what they offered." % them.name
		execute(sim, pr.kind, pr.from, pr.to, pr.give, pr.want)
		return ""
	return "That offer has expired."


static func decline(sim: Sim, id: int) -> void:
	for pr in sim.proposals.duplicate():
		if int(pr.id) == id:
			sim.proposals.erase(pr)
			adjust(sim.players[int(pr.from) - 1], int(pr.to), -3.0)
	sim.diplomacy_changed.emit()


static func drop_proposals(sim: Sim, a: int, b: int) -> void:
	for pr in sim.proposals.duplicate():
		if (int(pr.from) == a and int(pr.to) == b) or (int(pr.from) == b and int(pr.to) == a) or not sim.players[int(pr.from) - 1].alive:
			sim.proposals.erase(pr)


static func expire(sim: Sim) -> void:
	var n := sim.proposals.size()
	for pr in sim.proposals.duplicate():
		if sim.time - float(pr.t) > PROPOSAL_LIFE:
			sim.proposals.erase(pr)
	if sim.proposals.size() != n:
		sim.diplomacy_changed.emit()


# ---------------------------------------------------------------- rival AI
## Runs every 20-30 seconds for each rival: opinions drift, and it may offer or break treaties or trade.
static func ai_tick(sim: Sim, p: Sim.Player) -> void:
	var others: Array = []
	for q in sim.players:
		if q.alive and q.id != p.id:
			others.append(q)
	for q in others:
		var o := opinion(p, q.id)
		o += (base_opinion(p) - o) * 0.04
		var rel := relation(sim, p.id, q.id)
		if rel == ALLY: o += 1.0
		elif rel == PEACE: o += 0.9
		for r in others:
			if r.id != q.id and opinion(p, r.id) < -30.0 and r.opinion.get(q.id, 0.0) < -30.0:
				o += 1.0
		p.opinion[q.id] = clampf(o, -100.0, 100.0)
	if sim.time < 90.0:
		return
	for i in range(others.size() - 1, 0, -1):
		var j := sim.rng.randi() % (i + 1)
		var t = others[i]; others[i] = others[j]; others[j] = t
	for q in others:
		var rel := relation(sim, p.id, q.id)
		var op := opinion(p, q.id)
		var ratio := strength(sim, p) / maxf(1.0, strength(sim, q))
		if rel != WAR:
			var hate := -60.0 if rel == ALLY else -45.0
			if p.pers == "warlord":
				hate += 30.0
			# a realm whose land is full looks for land next door: it goes to war far more readily with a
			# neighbour it can reach (never breaking an alliance for it)
			var crowded := p.crowded and rel == PEACE and borders(sim, p.id, q.id)
			if crowded:
				hate += 50.0
			if op < hate and ratio > (1.0 if crowded else (1.4 if p.pers == "warlord" else 1.2)) and sim.rng.randf() < 0.3:
				declare_war(sim, p.id, q.id)
				return
			# crowded for a while with soldiers to spare: land has to come from somewhere, whatever it
			# thinks of the neighbour (allies excepted)
			if crowded and sim.time - p.crowded_t > 180.0 and p.reserve >= 6 and ratio > 0.8 and sim.rng.randf() < 0.15:
				declare_war(sim, p.id, q.id)
				return
		if rel == WAR:
			var score := op + (1.0 / maxf(0.2, ratio) - 1.0) * 25.0 + (-15.0 if p.pers == "warlord" else 5.0) + distance_bonus(sim, p.id, q.id) - (20.0 if p.crowded else 0.0)
			if score > 4.0 and sim.rng.randf() < 0.25:
				propose(sim, p.id, q.id, "peace")
				return
		elif rel == PEACE:
			var need := 60.0 if p.pers == "warlord" else (40.0 if p.pers == "builder" else 50.0)
			if op >= need and since(sim, p.id, q.id) > 240.0 and sim.rng.randf() < 0.4:
				propose(sim, p.id, q.id, "alliance")
				return
		if rel != WAR and sim.rng.randf() < (0.3 if not q.ai else 0.15) and _ai_offer_trade(sim, p, q):
			return


static func _ai_offer_trade(sim: Sim, p: Sim.Player, q: Sim.Player) -> bool:
	var wanted := {"planks": true, "stone": true}
	for f in GameData.food_ids:
		wanted[f] = true
	for b in sim.blds:
		if b.p == p.id:
			for k in b.def.get("in", {}):
				if k != "food":
					wanted[k] = true
	var need := ""
	for r in wanted:
		if float(p.stock.get(r, 0.0)) < 6.0 and float(q.stock.get(r, 0.0)) >= 25.0:
			need = r
			break
	if need == "" or market(sim, p) == null:
		return false
	var surplus := ""
	var best := 0.0
	for r in GameData.res_by_id:
		var have := float(p.stock.get(r, 0.0))
		if r != need and have >= 40.0 and have > best:
			best = have; surplus = r
	if surplus == "":
		return false
	var m := ceili(GameData.res_value(need) * 10.0 * 1.1 / maxf(0.1, GameData.res_value(surplus)))
	m = mini(m, int(best) - 20)
	if m < 1:
		return false
	var r := propose(sim, p.id, q.id, "trade", {surplus: m}, {need: 10})
	return r == "pending" or r == ""
