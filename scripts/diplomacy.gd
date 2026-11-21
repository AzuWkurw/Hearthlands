class_name Diplomacy
extends RefCounted
## Relations between realms (war, peace or alliance), each rival's opinion of every other realm,
## proposals (peace, alliance, trade, gifts and surrender) and how rival AIs decide on them.
## A realm losing a war badly can become another's vassal: it keeps its land, but pays tribute, fights
## its overlord's wars and makes no treaties of its own, until it breaks free (Player.overlord).
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
	var pa := sim.players[a - 1]
	var pb := sim.players[b - 1]
	if pa.overlord == b:
		# a vassal that takes up arms against its overlord breaks free
		break_free(sim, a, true)
		return
	if pa.overlord != 0:
		return    # a vassal goes to war only when its overlord does
	if pb.overlord == a:
		release(sim, b)
	elif pb.overlord != 0:
		# war on a vassal is war on its overlord, and so on all its vassals
		b = pb.overlord
		pb = sim.players[b - 1]
	var was := relation(sim, a, b)
	if was == WAR:
		return
	set_relation(sim, a, b, WAR)
	adjust(sim.players[b - 1], a, -50.0)
	for q in sim.players:
		if q.alive and q.id != a and q.id != b:
			adjust(q, a, -15.0 if was == ALLY else -8.0)
	drop_proposals(sim, a, b)
	sync_vassals(sim)


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


# ---------------------------------------------------------------- rivals' words
## A rival says something to you: in the event log, in its colour.
static func say(sim: Sim, p: Sim.Player, text: String) -> void:
	sim.emit_log("%s: \"%s\"" % [p.name, text], p.color.lightened(0.35))


const THANKS := ["A fair deal. May the roads stay open between us.", "Good trading with you, neighbour.", "Our carts will come again.", "Your goods are welcome in my halls."]
## How fast a rival at peace grows tired of a neighbour (opinion lost per diplomacy turn).
const FRICTION := {"builder": 1.4, "balanced": 3.0, "warlord": 3.6}
const WARNINGS := ["Your borders press on mine. Keep your soldiers back, or there will be war.", "My patience with you is wearing thin.", "I have counted your soldiers. I have more."]


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


## (build 76) The way a trade cart takes from tile a to tile b: [tiles, cost in flat-land tiles]. Over
## land a tile costs 1, a mountain CART_MOUNT; over water CART_WATER (the cart goes on a
## boat). Worked out from the ground only, which never changes in a game, so each way is kept.
const CART_MOUNT := 4.0
const CART_WATER := 2.5
const CART_NODES := 150000

static func cart_route(sim: Sim, a: int, b: int) -> Array:
	var key := a * 1000003 + b
	var known = sim.cart_routes.get(key)
	if known != null:
		return known
	var W := sim.w
	var H := sim.h
	var n := W * H
	var dist := PackedFloat32Array(); dist.resize(n); dist.fill(INF)
	var par := PackedInt32Array(); par.resize(n); par.fill(-1)
	var done := PackedByteArray(); done.resize(n)
	var ter: PackedByteArray = sim.ter
	var bx := b % W
	var by := b / W
	var hp := Sim.MinHeap.new()
	dist[a] = 0.0
	hp.push(0.0, a)
	var seen := 0
	var found := false
	while hp.size() > 0:
		var cur := hp.pop()
		if done[cur] == 1:
			continue
		done[cur] = 1
		if cur == b:
			found = true
			break
		seen += 1
		if seen > CART_NODES:
			break
		var cx := cur % W
		var cy := cur / W
		for dd in 4:
			var ni: int
			if dd == 0:
				if cx + 1 >= W: continue
				ni = cur + 1
			elif dd == 1:
				if cx < 1: continue
				ni = cur - 1
			elif dd == 2:
				if cy + 1 >= H: continue
				ni = cur + W
			else:
				if cy < 1: continue
				ni = cur - W
			if done[ni] == 1:
				continue
			var tr := ter[ni]
			var c := CART_WATER if tr == Sim.WATER else (CART_MOUNT if tr == Sim.MOUNT else 1.0)
			var nd := dist[cur] + c
			if nd < dist[ni]:
				dist[ni] = nd
				par[ni] = cur
				# A*: the straight distance left, at the cheapest cost a tile can have
				hp.push(nd + float(absi(ni % W - bx) + absi(ni / W - by)), ni)
	var out: Array
	if found:
		var path := PackedInt32Array()
		var c2 := b
		while c2 != -1:
			path.append(c2)
			c2 = par[c2]
		path.reverse()
		out = [path, float(dist[b])]
	else:
		var line := _line(sim, Vector2i(a % W, a / W), Vector2i(b % W, b / W))
		out = [line, float(line.size())]
	# (only the ground counts, which stays as it is: the same way every time, before and after loading)
	sim.cart_routes[key] = out
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
	# (build 76) along a real way over the land, round mountains, and by boat only over water that
	# must be crossed (it went in a straight line over sea and mountains)
	var route := cart_route(sim, sim.idx(src.x, src.y), sim.idx(dst.x, dst.y))
	t.path = route[0]
	var tt := maxf(4.0, float(route[1]) / CART_SPEED)
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
		if at_war(sim, 1, q.id):
			sim.standing.erase(so)
			sim.emit_log("Your standing offer to %s has stopped: you are at war." % q.name, Color("e0b060"))
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
	if p.overlord != 0 and kind in ["peace", "alliance", "vassal", "submit"] and p.overlord != from:
		return "%s is a vassal of %s: its overlord speaks for it." % [p.name, sim.players[p.overlord - 1].name]
	if q.overlord != 0 and kind in ["peace", "alliance", "vassal", "submit"]:
		return "A vassal makes no treaties of its own."
	match kind:
		"vassal", "submit":
			return surrender_answer(sim, p, kind, from)
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
		"vassal":
			make_vassal(sim, from, to)
		"submit":
			make_vassal(sim, to, from)
		"peace":
			set_relation(sim, from, to, PEACE)
			adjust(a, to, 10.0); adjust(b, from, 10.0)
			sync_vassals(sim)
		"alliance":
			set_relation(sim, from, to, ALLY)
			adjust(a, to, 10.0); adjust(b, from, 10.0)
		"trade", "gift", "tribute":
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
			adjust(a, to, 15.0 if kind == "tribute" else 3.0)
			if kind == "tribute":
				if to == 1:
					sim.emit_log("You pay %s as tribute to %s. The carts are on their way." % [goods_text(want), a.name], Color("e0b060"))
					say(sim, a, "Wise. We remain at peace.")
				sim.diplomacy_changed.emit()
				return
			if kind == "trade" and (from == 1 or to == 1):
				var them := a if to == 1 else b
				if them.ai and sim.rng.randf() < 0.6:
					say(sim, them, THANKS[sim.rng.randi() % THANKS.size()])
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
		"tribute":
			say(sim, sim.players[from - 1], "Send me %s, or there will be war between us." % goods_text(want))
			sim.emit_log("%s demands tribute. Answer in Diplomacy." % who, Color("e0b060"))
		"peace": sim.emit_log("%s offers peace. Answer in Diplomacy." % who, Color("8fc0ff"))
		"vassal":
			say(sim, sim.players[from - 1], "Enough. Spare my realm, and I will serve you as your vassal.")
			sim.emit_log("%s offers to surrender and become your vassal. Answer in Diplomacy." % who, Color("8fc0ff"))
		"submit":
			say(sim, sim.players[from - 1], "Your armies are broken. Kneel, and keep your land as my vassal.")
			sim.emit_log("%s demands your surrender. Answer in Diplomacy." % who, Color("e0b060"))
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
			"vassal", "submit":
				var why := surrender_check(sim, int(pr.from), int(pr.to))
				if why != "": return why
			"help":
				# your ally asked you to join its war
				var foe := int(pr.get("target", 0))
				if relation(sim, pr.from, pr.to) != ALLY: return "You are no longer allies."
				if foe <= 0 or not sim.players[foe - 1].alive or relation(sim, pr.from, foe) != WAR: return "That war is over."
				if relation(sim, pr.to, foe) != WAR:
					declare_war(sim, int(pr.to), foe)
				adjust(them, int(pr.to), 25.0)
				say(sim, them, "A true friend! Together we will crush %s." % sim.players[foe - 1].name)
				sim.diplomacy_changed.emit()
				return ""
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
			var who := sim.players[int(pr.from) - 1]
			if String(pr.kind) == "help":
				# an ally left to fight alone remembers it
				adjust(who, int(pr.to), -18.0)
				say(sim, who, "So that is what your friendship is worth.")
			elif String(pr.kind) == "submit":
				adjust(who, int(pr.to), -8.0)
				say(sim, who, "Then we finish this on the field.")
			elif String(pr.kind) == "tribute":
				adjust(who, int(pr.to), -20.0)
				who.warned[int(pr.to)] = sim.time - 120.0
				say(sim, who, "You will regret this.")
			else:
				adjust(who, int(pr.to), -3.0)
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
			if String(pr.kind) == "help":
				adjust(sim.players[int(pr.from) - 1], int(pr.to), -12.0)
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
		elif rel == PEACE:
			o += 0.9
			# neighbours rub: at peace with a realm whose land touches its own, a rival grows tired of it
			# (a warlord fast, a builder hardly), and more so when it is the stronger; gifts and trades
			# win it back
			if borders(sim, p.id, q.id):
				o -= FRICTION.get(p.pers, 3.0)
				if strength(sim, p) > strength(sim, q) * 1.5:
					o -= 0.8
		for r in others:
			if r.id != q.id and opinion(p, r.id) < -30.0 and r.opinion.get(q.id, 0.0) < -30.0:
				o += 1.0
		if p.overlord == q.id:
			o += vassal_mood(sim, p, q)
		p.opinion[q.id] = clampf(o, -100.0, 100.0)
	if sim.time < 90.0:
		return
	if p.overlord != 0:
		_ai_vassal(sim, p, others)
		return
	for i in range(others.size() - 1, 0, -1):
		var j := sim.rng.randi() % (i + 1)
		var t = others[i]; others[i] = others[j]; others[j] = t
	for q in others:
		if q.overlord == p.id:
			continue    # its own vassals: they pay and fight for it
		if q.overlord != 0:
			continue    # another realm's vassal: its overlord is the one to deal with
		if _ai_leave_alliance(sim, p, q):
			return
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
				if _warn_first(sim, p, q):
					return
				declare_war(sim, p.id, q.id)
				return
			# a much stronger rival that thinks little of you may demand tribute instead
			if not q.ai and rel == PEACE and op < 0.0 and ratio > 1.5 and sim.time - float(p.warned.get(q.id, -1e9)) > 600.0 and sim.rng.randf() < (0.2 if p.pers == "warlord" else 0.06):
				var what := "gold" if float(q.stock.get("gold", 0.0)) >= 10.0 else "planks"
				p.warned[q.id] = sim.time
				propose(sim, p.id, q.id, "tribute", {}, {what: 10 if what == "gold" else 20})
				return
			# crowded for a while with soldiers to spare: land has to come from somewhere, whatever it
			# thinks of the neighbour (allies excepted)
			if crowded and sim.time - p.crowded_t > 180.0 and p.reserve >= 6 and ratio > 0.8 and sim.rng.randf() < 0.15:
				if _warn_first(sim, p, q):
					return
				declare_war(sim, p.id, q.id)
				return
		if rel == WAR:
			if _ai_surrender(sim, p, q, ratio):
				return
			var score := op + (1.0 / maxf(0.2, ratio) - 1.0) * 25.0 + (-15.0 if p.pers == "warlord" else 5.0) + distance_bonus(sim, p.id, q.id) - (20.0 if p.crowded else 0.0)
			if score > 4.0 and sim.rng.randf() < 0.25:
				propose(sim, p.id, q.id, "peace")
				return
		elif rel == PEACE:
			var need := 60.0 if p.pers == "warlord" else (40.0 if p.pers == "builder" else 50.0)
			if op >= need and since(sim, p.id, q.id) > 240.0 and sim.rng.randf() < 0.4:
				propose(sim, p.id, q.id, "alliance")
				return
		if rel == ALLY and not q.ai and _ai_call_for_help(sim, p, q):
			return
		if rel != WAR and sim.rng.randf() < (0.3 if not q.ai else 0.15) and _ai_offer_trade(sim, p, q):
			return


## An ally at war asks you to join it, once in a while for each war: say yes and it trusts you more,
## say no (or let the offer lapse) and it trusts you less. Allies that keep being let down break the
## alliance (their opinion falls below the line for keeping it).
static func _ai_call_for_help(sim: Sim, p: Sim.Player, q: Sim.Player) -> bool:
	for r in sim.players:
		if not r.alive or r.id == p.id or r.id == q.id:
			continue
		if relation(sim, p.id, r.id) != WAR or relation(sim, q.id, r.id) == WAR:
			continue
		var k := "help:%d" % r.id
		if sim.time - float(p.warned.get(k, -1e9)) < 480.0:
			continue
		p.warned[k] = sim.time
		for pr in sim.proposals:
			if int(pr.from) == p.id and pr.kind == "help":
				return false
		sim._prop_id += 1
		sim.proposals.append({"id": sim._prop_id, "from": p.id, "to": q.id, "kind": "help", "give": {}, "want": {}, "t": sim.time, "target": r.id})
		say(sim, p, "%s makes war on me. Stand with me, as allies should!" % r.name)
		sim.emit_log("Your ally %s asks you to join its war against %s. Answer in Diplomacy." % [p.name, r.name], Color("e0b060"))
		sim.diplomacy_changed.emit()
		return true
	return false


## An ally whose trust has fallen low leaves the alliance (it stays at peace).
static func _ai_leave_alliance(sim: Sim, p: Sim.Player, q: Sim.Player) -> bool:
	if relation(sim, p.id, q.id) != ALLY or opinion(p, q.id) > 5.0:
		return false
	set_relation(sim, p.id, q.id, PEACE)
	adjust(q, p.id, -10.0)
	if not q.ai:
		say(sim, p, "You have been no friend to me. Our alliance is over.")
		sim.emit_log("%s ends its alliance with you (it stays at peace)." % p.name, Color("e0b060"))
	sim.diplomacy_changed.emit()
	return true


## Before going to war with you, a rival warns you once (and waits at least a minute).
static func _warn_first(sim: Sim, p: Sim.Player, q: Sim.Player) -> bool:
	if q.ai:
		return false
	var w := float(p.warned.get(q.id, -1e9))
	if sim.time - w > 600.0:
		p.warned[q.id] = sim.time
		say(sim, p, WARNINGS[sim.rng.randi() % WARNINGS.size()])
		return true
	return sim.time - w < 60.0


static func _ai_offer_trade(sim: Sim, p: Sim.Player, q: Sim.Player) -> bool:
	var wanted := {"planks": true, "stone": true}
	for f in GameData.food_ids:
		wanted[f] = true
	for b in sim.blds:
		if b.p == p.id:
			for k in b.def.get("in", {}):
				if k != "food":
					wanted[k] = true
	# realms with nobles want the luxuries they don't make
	if p.noble > 0:
		for k in GameData.luxury.get("noble", {}):
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


# ---------------------------------------------------------------- vassals
## How often a vassal pays tribute, and what: a share of what it has of each good, at most CAP of each.
const TRIBUTE_EVERY := 120.0
const TRIBUTE := {"gold": 0.2, "planks": 0.1, "stone": 0.1}
const TRIBUTE_CAP := 30
## A realm surrenders when its army is at most this share of the enemy's (by personality).
const GIVE_UP := {"builder": 0.45, "balanced": 0.35, "warlord": 0.25}
## A vassal stays at least this long before it may break free on its own.
const VASSAL_MIN := 300.0


## The realm that speaks for realm id: its overlord, or itself when it is free.
static func head(sim: Sim, id: int) -> int:
	var o := sim.players[id - 1].overlord
	return o if o != 0 else id


## The ids of realm id's vassals, in id order.
static func vassals_of(sim: Sim, id: int) -> Array:
	var out := []
	for q in sim.players:
		if q.alive and q.overlord == id:
			out.append(q.id)
	return out


static func any_vassals(sim: Sim) -> bool:
	for q in sim.players:
		if q.overlord != 0:
			return true
	return false


## Why realm v cannot become realm o's vassal now ("" when it can).
static func surrender_check(sim: Sim, v: int, o: int) -> String:
	var pv := sim.players[v - 1]
	var po := sim.players[o - 1]
	if not pv.alive or not po.alive:
		return "That realm is gone."
	if relation(sim, v, o) != WAR:
		return "Only a realm at war can surrender."
	if pv.overlord != 0 or po.overlord != 0:
		return "A vassal cannot take or give a surrender."
	return ""


## Whether AI realm p takes a surrender: "vassal" (from offers to serve p) or "submit" (from wants p to serve it).
static func surrender_answer(sim: Sim, p: Sim.Player, kind: String, from: int) -> String:
	var q := sim.players[from - 1]
	var why := surrender_check(sim, from if kind == "vassal" else p.id, p.id if kind == "vassal" else from)
	if why != "":
		return why
	if kind == "vassal":
		# tribute and a soldier on its side are worth more than a long siege, unless a warlord can see
		# the end of the other realm already
		var ratio := strength(sim, p) / maxf(1.0, strength(sim, q))
		if p.pers == "warlord" and ratio > 4.0:
			return "%s wants your land, not your service." % p.name
		if opinion(p, from) < -80.0:
			return "%s hates you too much to spare you." % p.name
		return ""
	# a demand to surrender: only when its own army is broken
	var share := strength(sim, p) / maxf(1.0, strength(sim, q))
	var line: float = GIVE_UP.get(p.pers, 0.35)
	if since(sim, p.id, from) < 120.0:
		return "%s will not give up a war that has only just begun." % p.name
	if share > line:
		return "%s will not surrender: its army is still %d against your %d." % [p.name, roundi(strength(sim, p)), roundi(strength(sim, q))]
	return ""


## Realm v becomes realm o's vassal: peace between them (they count as allies), tribute every few
## minutes, and from now on it is at war with o's enemies and at peace with everyone else. Its own
## vassals, if it had any, go free.
static func make_vassal(sim: Sim, v: int, o: int) -> void:
	var pv := sim.players[v - 1]
	var po := sim.players[o - 1]
	for x in vassals_of(sim, v):
		var px := sim.players[x - 1]
		px.overlord = 0
		_set_rel(sim, x, v, PEACE)
		_tell(sim, [x, v], "%s goes free: its overlord %s has surrendered." % [px.name, pv.name])
	pv.overlord = o
	pv.vassal_t = sim.time
	pv.tribute_t = sim.time + TRIBUTE_EVERY
	_set_rel(sim, v, o, ALLY)
	drop_proposals(sim, v, o)
	adjust(po, v, 20.0)
	pv.opinion[o] = maxf(opinion(pv, o), 10.0)
	Chronicle.note(sim, pv, "vassal", {"o": o})
	if v == 1 and not sim.spectating():
		sim.emit_log("You surrender to %s. Your realm keeps its land, but pays tribute and fights its wars." % po.name, Color("e0b060"))
	elif o == 1 and not sim.spectating():
		sim.emit_log("%s surrenders and becomes your vassal: it pays you tribute and fights your wars." % pv.name, Color("d8aa4a"))
	else:
		sim.emit_log("%s surrenders and becomes a vassal of %s." % [pv.name, po.name], Color("b0a8d0"))
	sync_vassals(sim)
	sim.diplomacy_changed.emit()


## An overlord lets its vassal go: they stay at peace.
static func release(sim: Sim, v: int) -> void:
	var pv := sim.players[v - 1]
	var o := pv.overlord
	if o == 0:
		return
	pv.overlord = 0
	_set_rel(sim, v, o, PEACE)
	adjust(pv, o, 25.0)
	Chronicle.note(sim, pv, "free", {"o": o})
	_tell(sim, [v, o], "%s releases %s: it is a free realm again." % [sim.players[o - 1].name, pv.name])
	sync_vassals(sim)
	sim.diplomacy_changed.emit()


## A vassal breaks free of its overlord: with war (rebel) or, quietly, at peace.
static func break_free(sim: Sim, v: int, rebel: bool) -> void:
	var pv := sim.players[v - 1]
	var o := pv.overlord
	if o == 0:
		return
	var po := sim.players[o - 1]
	pv.overlord = 0
	_set_rel(sim, v, o, WAR if rebel else PEACE)
	adjust(po, v, -40.0 if rebel else -20.0)
	Chronicle.note(sim, pv, "free", {"o": o, "rebel": rebel})
	if rebel:
		_tell(sim, [v, o], "%s rises against its overlord %s: war!" % [pv.name, po.name], Color("e0603a"))
		if pv.ai and o == 1:
			say(sim, pv, "No more tribute. Come and take it, if you can.")
	else:
		_tell(sim, [v, o], "%s stops paying tribute to %s and goes its own way." % [pv.name, po.name], Color("e0b060"))
	sync_vassals(sim)
	sim.diplomacy_changed.emit()


## A realm fell: its vassals go free (at peace with the rest), and it is nobody's vassal any more.
static func on_fallen(sim: Sim, id: int) -> void:
	var p := sim.players[id - 1]
	p.overlord = 0
	for x in vassals_of(sim, id):
		sim.players[x - 1].overlord = 0
		Chronicle.note(sim, sim.players[x - 1], "free", {"o": id})
		_tell(sim, [x], "%s is free: its overlord has fallen." % sim.players[x - 1].name)
	sync_vassals(sim)


## Vassals follow their overlords: a vassal is at war with exactly the realms its overlord is at war
## with (and their vassals), at peace with everyone else, and allied with its overlord.
static func sync_vassals(sim: Sim) -> void:
	if not any_vassals(sim):
		return
	var n := sim.players.size()
	var changed := false
	for i in n:
		var a := sim.players[i]
		if not a.alive:
			continue
		for j in range(i + 1, n):
			var b := sim.players[j]
			if not b.alive or (a.overlord == 0 and b.overlord == 0):
				continue
			var ha := head(sim, a.id)
			var hb := head(sim, b.id)
			var now := relation(sim, a.id, b.id)
			var want := now
			if a.overlord == b.id or b.overlord == a.id:
				want = ALLY
			elif ha == hb:
				want = PEACE if now == WAR else now
			elif relation(sim, ha, hb) == WAR:
				want = WAR
			elif now == WAR or (now == ALLY and relation(sim, ha, hb) != ALLY):
				want = PEACE
			if want == now:
				continue
			_set_rel(sim, a.id, b.id, want)
			changed = true
			var v := a if a.overlord != 0 else b
			var other := b if v == a else a
			var lord := sim.players[v.overlord - 1]
			if want == WAR:
				_tell(sim, [a.id, b.id, lord.id], "%s joins its overlord %s in the war against %s." % [v.name, lord.name, other.name], Color("e0603a"))
				drop_proposals(sim, a.id, b.id)
			elif want == PEACE and now == WAR:
				_tell(sim, [a.id, b.id, lord.id], "%s lays down its arms against %s, as its overlord %s has." % [v.name, other.name, lord.name])
	if changed:
		sim.diplomacy_changed.emit()


## Every few seconds: vassals whose overlord is gone go free, vassals follow their overlord's wars,
## and pay tribute when it is due.
static func vassal_tick(sim: Sim) -> void:
	if not any_vassals(sim):
		return
	for p in sim.players:
		if p.overlord != 0 and (not p.alive or not sim.players[p.overlord - 1].alive):
			p.overlord = 0
	sync_vassals(sim)
	for p in sim.players:
		if p.alive and p.overlord != 0 and sim.time >= p.tribute_t:
			p.tribute_t = sim.time + TRIBUTE_EVERY
			pay_tribute(sim, p)


## What vassal p would pay now.
static func tribute_due(p: Sim.Player) -> Dictionary:
	var out := {}
	for k in TRIBUTE:
		var n := mini(TRIBUTE_CAP, floori(float(p.stock.get(k, 0.0)) * float(TRIBUTE[k])))
		if n > 0:
			out[k] = n
	return out


## Vassal p sends its tribute to its overlord by cart. Paying wears on its goodwill a little.
static func pay_tribute(sim: Sim, p: Sim.Player) -> void:
	var lord := sim.players[p.overlord - 1]
	var due := tribute_due(p)
	for k in due:
		var g := sim.take(p, k, float(due[k]))
		send_cart(sim, p, lord, k, g)
	adjust(p, lord.id, -2.0)
	adjust(lord, p.id, 2.0)
	if due.is_empty():
		return
	if p.id == 1 and not sim.spectating():
		sim.emit_log("You send %s as tribute to your overlord %s." % [goods_text(due), lord.name], Color("e0b060"))
	elif lord.id == 1 and not sim.spectating():
		sim.emit_log("Your vassal %s sends %s as tribute." % [p.name, goods_text(due)], Color("d8aa4a"))


## How a vassal's goodwill to its overlord drifts each diplomacy turn: a strong overlord is respected,
## a weak one resented, and proud realms (warlords) chafe the most.
static func vassal_mood(sim: Sim, p: Sim.Player, lord: Sim.Player) -> float:
	var d: float = {"builder": -0.3, "balanced": -0.8, "warlord": -1.6}.get(p.pers, -0.8)
	var ratio := strength(sim, lord) / maxf(1.0, strength(sim, p))
	if ratio > 2.0:
		d += 1.5
	elif ratio < 1.0:
		d -= 4.0 * (1.0 - ratio) + 1.0
	return d


## A rival that is a vassal: it trades, and it breaks free once its goodwill to its overlord is gone
## (or once it is clearly the stronger), though not in its first minutes of service.
static func _ai_vassal(sim: Sim, p: Sim.Player, others: Array) -> void:
	var lord := sim.players[p.overlord - 1]
	var op := opinion(p, lord.id)
	var ratio := strength(sim, p) / maxf(1.0, strength(sim, lord))
	if sim.time - p.vassal_t >= VASSAL_MIN and (op < -30.0 or (ratio > 1.3 and op < 20.0)) and sim.rng.randf() < 0.3:
		# strong enough to fight for it: a rising; else it simply stops paying
		break_free(sim, p.id, ratio > 0.9)
		return
	for q in others:
		if relation(sim, p.id, q.id) != WAR and sim.rng.randf() < (0.3 if not q.ai else 0.15) and _ai_offer_trade(sim, p, q):
			return


## A rival losing a war badly offers to become the enemy's vassal; one winning it by far demands that
## the enemy surrender. Each at most once in a while for each enemy.
static func _ai_surrender(sim: Sim, p: Sim.Player, q: Sim.Player, ratio: float) -> bool:
	if p.overlord != 0 or q.overlord != 0 or since(sim, p.id, q.id) < 180.0:
		return false
	var k := "surrender:%d" % q.id
	if sim.time - float(p.warned.get(k, -1e9)) < 480.0:
		return false
	var line: float = GIVE_UP.get(p.pers, 0.35)
	if ratio <= line and vassals_of(sim, p.id).is_empty() and sim.rng.randf() < 0.35:
		p.warned[k] = sim.time
		propose(sim, p.id, q.id, "vassal")
		return true
	if ratio >= 1.0 / line and sim.rng.randf() < (0.3 if p.pers == "warlord" else 0.15):
		p.warned[k] = sim.time
		propose(sim, p.id, q.id, "submit")
		return true
	return false


## Changes a relation without the usual log line (the vassal code writes its own).
static func _set_rel(sim: Sim, a: int, b: int, r: int) -> void:
	sim.rel[key(a, b)] = r
	sim.rel_since[key(a, b)] = sim.time


## A log line about vassals: bright when it touches you, dim between rivals.
static func _tell(sim: Sim, who: Array, text: String, col := Color("8fc0ff")) -> void:
	sim.emit_log(text, col if (1 in who and not sim.spectating()) else Color("b0a8d0"))
