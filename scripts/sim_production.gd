class_name SimProduction
extends RefCounted
## Production: buildings working in cycles (inputs, outputs, tools, experience) and construction sites.
## Part of the simulation: sim.gd holds the shared state and calls in here; the functions reach
## the rest of the game through `sim` (sim.gd keeps a one-line wrapper for each, so callers did
## not change).

var sim: Sim


func _init(p_sim: Sim) -> void:
	sim = p_sim


func start_check(b: Sim.Bld, p: Sim.Player) -> String:
	var d := b.def
	if b.reno_to >= 0:
		return "Being renovated"
	if not sim.connected(b):
		return "Not connected by road to a store"
	var waiting := 0
	for k in b.out_buf:
		waiting += int(b.out_buf[k])
	if waiting >= 6:
		return "Waiting for carriers"
	var inp: Dictionary = d.get("in", {})
	# what it works with must have been carried here from a store first
	for k in inp:
		var n := int(inp[k])
		var here := sim.logistics.food_at(b, false) if k == "food" else int(b.inbuf.get(k, 0))
		if here < n:
			var name := "food" if k == "food" else GameData.res_name(k).to_lower()
			var way := sim.logistics.food_at(b) - here if k == "food" else int(b.incoming.get(k, 0))
			if way > 0:
				return "Waiting for %s on its way" % name
			return "Needs " + name
	if d.has("siege"):
		var tgt := siege_target(b)
		if tgt == null:
			return "No enemy fort in range"
		b.target = sim.idx(tgt.x, tgt.y)
	# full stores first: it is quick to see, and a full store stops the work whatever else is ready
	var outs: Dictionary = Crops.out_of(sim, b)
	if outs.size() > 0:
		# goods already on their way (waiting at buildings, on a carrier's back, or being made) count
		# as in store, so the stores never take more than they hold
		var extra := _extra_out(p, b.ty)
		var full := true
		var by_target := false
		var full_res := ""
		for o in outs:
			if o == "research":
				full = false
				continue
			if o == "ship":
				full = p.ships >= SimSea.MAX_SHIPS
				continue
			if o == "warship":
				full = p.warships >= SimNavy.MAX_WARSHIPS
				continue
			var cap := sim.capacity(p, o)
			var have := float(p.stock.get(o, 0.0))
			# goods on their way only matter near the top: far below it, skip counting them
			if have + float(outs[o]) + extra > cap - maxf(30.0, cap * 0.5):
				have += coming(p, o)
			var tg := sim.target_of(p, o)
			if tg >= 0 and have >= tg:
				by_target = true
			elif have + float(outs[o]) + extra <= cap:
				full = false
			elif full_res == "":
				full_res = o
		if full:
			if by_target:
				var o0: String = outs.keys()[0]
				return "Target reached: %d %s in store" % [int(p.stock.get(o0, 0.0)), GameData.res_name(o0).to_lower()]
			return "Stores are full of %s (%d of %d): production stops until some is used, or build a storehouse" % [GameData.res_name(full_res).to_lower(), int(p.stock.get(full_res, 0.0)), int(sim.capacity(p, full_res))]
	var wc := sim.work_center(b)
	var wr := sim.work_radius(b)
	match String(d.get("act", "")):
		"cut_tree":
			b.target = sim.find_near(wc.x, wc.y, wr, "tree")
			if b.target < 0: return "No trees left in the work area"
		"cut_rock":
			b.target = sim.find_near(wc.x, wc.y, wr, "rock")
			if b.target < 0: return "No stone left in the work area"
		"fish":
			b.target = sim.find_near(wc.x, wc.y, wr, "fish")
			if b.target < 0: return "No fish left in the work area"
		"dig_clay":
			b.target = sim.find_near(wc.x, wc.y, wr, "clay")
			if b.target < 0: return "No clay left in the work area"
		"plant":
			b.target = sim.find_near(wc.x, wc.y, wr, "plant", 0, b.p)
			if b.target < 0: return "No room to plant in the work area"
	if d.has("mine"):
		b.target = sim.find_near(b.x, b.y, 2, "ore", int(d.mine))
		if b.target < 0: return "Deposit exhausted"
	var sc := sim.site_check(d, wc.x, wc.y, true)
	if sc != "": return sc
	var keeps_food := String(d.get("train", "")) == "noble" or (d.get("out", {}) as Dictionary).has("research")
	if keeps_food and sim.food_total(p) < sim.pop_total(p) * 0.2 + 10.0:
		return "Saving food for the people"
	match String(d.get("train", "")):
		"artisan":
			if sim.idle(p, "peasant") < 1: return "No idle peasant"
			if sim.idle(p, "artisan") >= 2: return "Enough artisans for now"
			if p.peasant < p.artisan * 2 or p.starve > 0: return "Peasants are needed on the land"
		"soldier":
			# with no artisan to train, an old soldier at headquarters is retrained to the current kind
			b.retrain = false
			if sim.idle(p, "artisan") < 1:
				if Sim.mix_oldest(sim.rmix_of(p)) < p.age:
					b.retrain = true
				else:
					return "No idle artisan"
		"noble":
			if sim.idle(p, "artisan") < 1: return "No idle artisan"
		"scout":
			if sim.idle(p, "peasant") < 1: return "No idle peasant"
			if p.scout - p.used_scout - p.scout_out >= 2: return "Enough scouts for now (2 idle)"
	if String(d.get("train", "")) == "noble" and p.noble >= maxi(2, p.artisan / 2):
		return "Enough nobles for now"
	if d.has("makes_tools") and sim.wanted_tool(p) == "":
		return "Every tool is in stock (see production targets)"
	if Crops.is_farm(b):
		var fw := Crops.farm_start(sim, b)
		if fw != "":
			return fw
	else:
		var cb := Crops.block(sim, b)
		if cb != "":
			return cb
	return ""


## Goods of res on their way to realm p's stores: waiting at buildings for a carrier, carried, or
## being made right now. Worked out at most once a game second (COMING_TICKS) and kept up to date in
## between: a cycle that starts adds to it, goods that reach a store come off it.
const COMING_TICKS := 10

func coming(p: Sim.Player, res: String) -> float:
	if sim._ticks - sim._coming_tick >= COMING_TICKS or sim._coming_tick > sim._ticks or not sim._coming.has(p.id):
		_count_coming()
	return float((sim._coming[p.id] as Dictionary).get(res, 0.0))


## Counts the goods on their way for every realm at once: one walk over the buildings and one over
## the trips. All realms are counted at the same moment, so a loaded game (which keeps the counts)
## goes on exactly as before.
func _count_coming() -> void:
	sim._coming_tick = sim._ticks
	sim._coming = {}
	for q: Sim.Player in sim.players:
		sim._coming[q.id] = {}
	for b: Sim.Bld in sim.blds:
		if b.dead or not sim._coming.has(b.p):
			continue
		var c: Dictionary = sim._coming[b.p]
		if not b.out_buf.is_empty():
			for k in b.out_buf:
				c[k] = float(c.get(k, 0.0)) + float(b.out_buf[k])
		if b.working and b.def.has("out"):
			var p := sim.players[b.p - 1]
			if Crops.is_farm(b):
				_count_cycle(b, p, c)
			else:
				# what a cycle of this type makes, with research's extra, worked out once per type
				if not sim._type_bonus.has(p.id):
					sim._type_bonus[p.id] = {}
				var tb: Dictionary = sim._type_bonus[p.id]
				var key := "*" + b.ty
				if not tb.has(key):
					var adds := []
					var extra := _extra_out(p, b.ty)
					for k in b.def.out:
						if k != "research" and k != "ship" and k != "warship":
							adds.append([k, float(b.def.out[k]) + extra])
					tb[key] = adds
				for a2 in tb[key]:
					c[a2[0]] = float(c.get(a2[0], 0.0)) + float(a2[1])
	# goods carried to the stores
	for t: Sim.Trip in sim.trips:
		if not t.delivered and t.site == 0 and t.dest == 0 and sim._coming.has(t.p):
			var c: Dictionary = sim._coming[t.p]
			c[t.res] = float(c.get(t.res, 0.0)) + t.n


func _count_cycle(b: Sim.Bld, p: Sim.Player, c: Dictionary) -> void:
	var out: Dictionary = Crops.out_of(sim, b)
	var extra := _extra_out(p, b.ty)
	for k in out:
		if k != "research" and k != "ship" and k != "warship":
			c[k] = float(c.get(k, 0.0)) + float(out[k]) + extra


## Extra goods a cycle of building type ty makes for realm p (research "out:" effects), remembered
## until the realm's research changes.
func _extra_out(p: Sim.Player, ty: String) -> int:
	if not sim._type_bonus.has(p.id):
		sim._type_bonus[p.id] = {}
	var tb: Dictionary = sim._type_bonus[p.id]
	var key := "+" + ty
	if not tb.has(key):
		tb[key] = int(sim.mod(p, "out:" + ty))
	return tb[key]


## Puts n of res in realm p's stores, as much as there is room for (the rest is lost).
func store_goods(p: Sim.Player, res: String, n: float, at := -1) -> void:
	sim.give(p, res, n, at)


## Goods carried to a store have arrived: they are in the stores now, no longer on their way.
func arrived(p: Sim.Player, res: String, n: float) -> void:
	if sim._coming.has(p.id):
		var c: Dictionary = sim._coming[p.id]
		if c.has(res):
			c[res] = maxf(0.0, float(c[res]) - n)


func deliver(b: Sim.Bld, p: Sim.Player, res: String, n: int) -> void:
	sim.made(p, res, n)
	for f: Feature in sim.features:
		f.on_made_at(b, p, res, n)
	if res == "warship":
		sim.naval.launch(p, b)
		return
	if res == "ship":
		p.ships = mini(SimSea.MAX_SHIPS, p.ships + n)
		if not p.ai:
			sim.emit_log("A new ship is ready (%d in all)." % p.ships, Color("8fc0ff"), Vector2i(b.x, b.y))
		return
	if res == "research":
		var gain := n * (1.0 + sim.mod(p, "research")) * float(sim.opts.research)
		p.rp += gain
		p.rp_total += gain
		return
	if sim.is_store(b):
		store_goods(p, res, n, sim.idx(b.x, b.y))
		return
	b.out_buf[res] = int(b.out_buf.get(res, 0)) + n
	sim._pending[b.id] = true


## What catapult b aims at: the nearest military building in range of a realm it is at war with that has
## defenders, or null.
func siege_target(b: Sim.Bld) -> Sim.Bld:
	var r := float(b.def.siege.range)
	var best: Sim.Bld = null
	var bd := 1e9
	for t: Sim.Bld in sim.mil_list():
		if t.p == b.p or t.state != "ready" or not Diplomacy.at_war(sim, b.p, t.p):
			continue
		var dd := Vector2(t.x - b.x, t.y - b.y).length()
		if dd > r or sim.own_def(t) <= 0:
			continue
		if dd < bd or (dd == bd and t.id < best.id):
			bd = dd; best = t
	return best


## A catapult's stone lands: it may kill one of the defenders.
func _siege_hit(b: Sim.Bld, p: Sim.Player) -> void:
	var t := sim.bld_at(b.target % sim.w, b.target / sim.w)
	if t == null or t.p == b.p or not sim.is_mil(t) or not Diplomacy.at_war(sim, b.p, t.p) or sim.own_def(t) <= 0:
		return
	b.sxp = sim.time       # (when the last stone landed, for drawing the dust)
	if sim.rng.randf() < float(b.def.siege.kill):
		sim.military.kill_defender(t)
		if b.p == 1:
			sim.emit_log("Your catapult hit the %s of %s: one defender fewer (%d left)." % [String(t.def.name), sim.players[t.p - 1].name, sim.own_def(t)], Color("d8aa4a"), Vector2i(t.x, t.y))
		elif t.p == 1:
			sim.emit_log("A catapult of %s hit your %s: one defender fell (%d left)." % [p.name, String(t.def.name), sim.own_def(t)], Color("e0603a"), Vector2i(t.x, t.y))
		Diplomacy.on_attacked(sim, t.p, b.p)
	# a stone through a wooden roof may start a fire
	var fires = sim.get_feature("fires")
	if fires != null and not t.dead and sim.rng.randf() < 0.15 and fires.ignite(t) and b.p == 1:
		sim.emit_log("Your catapult set the %s of %s on fire!" % [String(t.def.name), sim.players[t.p - 1].name], Color("d8aa4a"), Vector2i(t.x, t.y))


func finish_prod(b: Sim.Bld, p: Sim.Player) -> void:
	var d := b.def
	var tg := b.target
	if d.has("siege"):
		_siege_hit(b, p)
		return
	if Crops.is_farm(b):
		var got := Crops.farm_finish(sim, b)
		var fx := int(sim.mod(p, "out:" + b.ty))
		for k in got:
			deliver(b, p, k, int(got[k]) + fx)
		return
	match String(d.get("act", "")):
		"cut_tree":
			if tg < 0 or sim.deco[tg] != Sim.D_TREE: return
			sim.deco[tg] = 0; sim.changed_tiles.append(tg)
			sim.tree_felled.emit(tg)
		"cut_rock":
			if tg < 0: return
			if sim.deco[tg] == Sim.D_ROCK:
				if not sim.opts.endless_raw:
					sim.amt[tg] -= 1
				if sim.amt[tg] == 0: sim.deco[tg] = 0; sim.changed_tiles.append(tg)
			elif not sim.take_ore(tg, 4, sim.rng.randf() < sim.mod(p, "vein")):
				return
		"fish":
			if tg < 0 or sim.amt[tg] == 0: return
			if not sim.opts.endless_raw:
				sim.amt[tg] -= 1
		"dig_clay":
			if tg < 0 or sim.deco[tg] != Sim.D_CLAY or sim.amt[tg] == 0: return
			if not sim.opts.endless_raw:
				sim.amt[tg] -= 1
			if sim.amt[tg] == 0: sim.deco[tg] = 0; sim.changed_tiles.append(tg)
		"plant":
			if tg >= 0 and sim.deco[tg] == 0 and sim.bmap[tg] == 0 and sim.plot[tg] == 0 and sim.road[tg] == 0:
				sim.deco[tg] = Sim.D_TREE; sim.changed_tiles.append(tg)
			return
	if d.has("mine"):
		if tg < 0 or not sim.take_ore(tg, int(d.mine), sim.rng.randf() < sim.mod(p, "vein")): return
	if d.has("makes_tools"):
		# the toolsmith makes, one by one, whichever tool is wanted most at that moment
		for n in int(d.makes_tools) + int(sim.mod(p, "out:" + b.ty)):
			var tool := sim.wanted_tool(p)
			if tool == "":
				break
			deliver(b, p, tool, 1)
	match String(d.get("train", "")):
		"artisan":
			if p.peasant > 3:
				p.peasant -= 1; p.artisan += 1
				if not p.ai: sim.emit_log("A peasant became an artisan.", Color("86ad5c"), Vector2i(b.x, b.y))
			return
		"soldier":
			if b.retrain:
				b.retrain = false
				var rm := sim.rmix_of(p)
				for k in clampi(p.age, 0, Sim.KINDS - 1):
					if int(rm[k]) > 0:
						rm[k] -= 1
						rm[clampi(p.age, 0, Sim.KINDS - 1)] += 1
						p.res_era = Sim.mix_avg(rm)
						if not p.ai: sim.emit_log("A %s was retrained as a %s." % [Sim.soldier_name(k), Sim.soldier_name(p.age)], Color("86ad5c"), Vector2i(b.x, b.y))
						break
				return
			if p.artisan > 0:
				p.artisan -= 1
				p.res_xp = Sim.mix_xp(p.res_xp, p.reserve, 0.0, 1)
				var rm := sim.rmix_of(p)
				rm[clampi(p.age, 0, Sim.KINDS - 1)] += 1
				p.reserve += 1
				p.res_era = Sim.mix_avg(rm)
				var vet := false
				if p.stock.get("armor", 0.0) >= 1.0:
					sim.take(p, "armor", 1.0, sim.idx(b.x, b.y)); p.vets += 1.0; vet = true
				if not p.ai: sim.emit_log("A new %s joins the headquarters." % ("veteran" if vet else "soldier"), Color("86ad5c"), Vector2i(p.hq.x, p.hq.y) if p.hq != null else Vector2i(-1, -1))
			return
		"noble":
			if p.artisan > 0:
				p.artisan -= 1; p.noble += 1
				if not p.ai: sim.emit_log("An artisan was raised to noble.", Color("86ad5c"), Vector2i(b.x, b.y))
			return
		"scout":
			if p.peasant > 3:
				p.peasant -= 1; p.scout += 1
				if not p.ai: sim.emit_log("A new scout is ready. Send him exploring, or he will man a watch tower.", Color("86ad5c"), Vector2i(p.hq.x, p.hq.y) if p.hq != null else Vector2i(-1, -1))
			return
	var out: Dictionary = Crops.out_of(sim, b)
	var extra := int(sim.mod(p, "out:" + b.ty))
	for k in out:
		deliver(b, p, k, int(out[k]) + (extra if k != "research" else 0))


func build_tick(b: Sim.Bld, p: Sim.Player, dt: float) -> void:
	if sim.creative(p) and b.mat_total == 0:
		b.prog = 1.0
		_finish_site(b, p)
		return
	if not b.staffed:
		b.msg = "Paused" if b.prio == Sim.PRIO_PAUSED else "Waiting for a builder"
		return
	if not sim.connected(b):
		b.msg = "Waiting for a road connection"
		return
	if b.builder != 2:
		b.msg = "The builder is on his way" if b.builder == 1 else "Waiting for a builder"
		return
	# work goes only as far as the materials used so far allow; the builder uses the next one when
	# he needs it, and waits when none has arrived
	if b.mat_total > 0 and b.prog >= float(b.mat_used) / b.mat_total - 0.0001 and b.mat_used < b.mat_total:
		var got := ""
		for k in b.onsite:
			if int(b.onsite[k]) > 0:
				got = k
				break
		if got == "":
			b.msg = "Waiting for materials"
			return
		b.onsite[got] = int(b.onsite[got]) - 1
		if int(b.onsite[got]) <= 0:
			b.onsite.erase(got)
		b.spent[got] = int(b.spent.get(got, 0)) + 1
		b.mat_used += 1
	var fk := 1.0
	for f: Feature in sim.features:
		fk *= f.build_factor(p, b)
	b.prog += dt * fk * (0.6 if p.starve > 0 else 1.0) * (1.0 + sim.mod(p, "build")) * float(sim.opts.build) / maxf(1.0, float(b.def.get("time", 10)))
	if b.mat_total > 0:
		b.prog = minf(b.prog, float(b.mat_used) / b.mat_total)
	b.msg = "Under construction"
	if b.prog >= 1.0:
		_finish_site(b, p)


func _finish_site(b: Sim.Bld, p: Sim.Player) -> void:
	if b.builder == 2:
		# the builder walks back to the store (only to be seen: he is free at once)
		var path := sim.logistics.store_path(b)
		if path.size() >= 2:
			var t := Sim.Trip.new()
			t.p = p.id; t.kind = "builder"; t.res = "@builder"; t.n = 0; t.site = 0
			t.t0 = sim.time; t.t1 = sim.time + sim.logistics.net_dist(b.p, sim.idx(b.x, b.y)) + 0.5; t.t2 = t.t1
			t.path = path
			sim.trips.append(t)
	b.builder = 0
	if b.queue_n > 0:
		sim.queue_site(b, false)
	if true:
		b.state = "ready"; b.prog = 0.0; b.msg = ""
		sim._after_building_change(b)
		sim.building_done.emit(b.id)
		if sim.is_store(b):
			sim._recount_stores(p)
		if b.def.has("garrison"):
			sim.mil_fill(p)
			sim.recompute_territory()
		elif b.def.get("claim_only", false):
			sim.recompute_territory()
		if not p.ai:
			sim.emit_log("%s is finished." % String(b.def.name), Color("d8aa4a"), Vector2i(b.x, b.y))
		if b.def.has("wonder"):
			_wonder_done(b, p)
		# a building moved here: the old one hands over its settings and is pulled down
		if b.replaces != 0:
			var old: Sim.Bld = sim.by_id.get(b.replaces)
			b.replaces = 0
			if old != null and not old.dead and old.p == b.p and old.ty == b.ty:
				b.prio = old.prio; b.crop = old.crop; b.rotate = old.rotate
				b.want_n = old.want_n; b.want_kinds = old.want_kinds.duplicate(); b.keep_kind = old.keep_kind
				b.archer_want = old.archer_want; b.sally = old.sally; b.wxp = old.wxp
				sim.demolish(old)
				if not p.ai:
					sim.emit_log("The old %s is pulled down: the new one has taken over." % String(b.def.name).to_lower(), Color("d8aa4a"), Vector2i(b.x, b.y))


## Runs only when a building wakes up: its work cycle ended, its last start check asked to be
## repeated now, or its worker left. While a cycle runs the building sleeps until b.t_end, so
## hundreds of busy buildings cost nothing in between.
func prod_tick(b: Sim.Bld, p: Sim.Player, _dt: float) -> void:
	var d := b.def
	var cyc := b.cyc
	if cyc <= 0.0:
		return
	if b.working:
		if not b.staffed:
			# the worker left in the middle of a cycle: the work so far is lost
			b.working = false
		elif sim.time < b.t_end:
			b.retry = b.t_end
			return
		else:
			b.working = false
			var before := Sim.level(b.wxp, Sim.WORKER_XP)
			b.wxp += 1.0 + sim.mod(p, "xp")
			var after := Sim.level(b.wxp, Sim.WORKER_XP)
			if after > before and after >= Sim.SPECIALIST and not p.ai:
				sim.emit_log("The %s's %s reached level %d." % [String(d.name).to_lower(), GameData.trade_title(GameData.trade(b.ty)), after], Color("a0d070"), Vector2i(b.x, b.y))
			finish_prod(b, p)
			for f: Feature in sim.features:
				f.on_cycle(p, b)
	if not b.staffed:
		if b.prio == Sim.PRIO_PAUSED:
			b.msg = "Paused"
		elif b.need_tool != "":
			b.msg = "Needs %s for a new worker" % GameData.res_name(b.need_tool).to_lower()
		else:
			b.msg = "No %s available" % String(d.get("worker", "worker"))
		b.retry = sim.time + 1.0
		return
	if b.worker != 2 and sim.walks_to_work(b):
		b.msg = "The worker is on his way" if b.worker == 1 else "Waiting for a worker (no road from a home?)"
		b.retry = sim.time + 1.0
		return
	var t0 := Time.get_ticks_usec()
	var why := start_check(b, p)
	if why == "":
		for f: Feature in sim.features:
			why = f.work_block(p, b)
			if why != "":
				break
	sim._pf("start checks", t0)
	if why != "":
		b.msg = why
		# wait before checking again: 1 second at first, up to 3 if it keeps failing;
		# high-priority buildings keep checking every half second, so they grab goods as soon as they arrive
		if b.prio == Sim.PRIO_HIGH:
			b.retry = sim.time + 0.5
		else:
			# waiting for goods: look again soon; waiting for the land or the stores to change (trees to
			# grow, a store to empty): that takes a while, so look less often
			var cap := 3.0 if why.begins_with("Needs") or why.begins_with("No idle") or why.begins_with("Waiting") else 6.0
			# waiting for its inputs: a carrier bringing them wakes it at once (input_arrival), so it
			# need not look often itself (build 59)
			if d.has("in") and (why.begins_with("Needs ") or (why.begins_with("Waiting for ") and why.ends_with("on its way"))):
				cap = 8.0
			b.retry = sim.time + minf(1.0 + b.fails * 0.5, cap) + sim.rng.randf() * 0.3
		b.fails += 1
		return
	b.fails = 0
	var inp: Dictionary = d.get("in", {})
	b.in_next = 0.0           # it uses its inputs now: the carriers look again at once
	for k in inp:
		if k == "food":
			# the cheapest food it has
			var left := int(inp[k])
			for f in GameData.food_ids:
				while left > 0 and int(b.inbuf.get(f, 0)) > 0:
					b.inbuf[f] = int(b.inbuf[f]) - 1
					if int(b.inbuf[f]) <= 0: b.inbuf.erase(f)
					sim.used(p, f, 1.0)
					left -= 1
		else:
			b.inbuf[k] = int(b.inbuf.get(k, 0)) - int(inp[k])
			if int(b.inbuf[k]) <= 0: b.inbuf.erase(k)
			sim.used(p, k, float(inp[k]))
	# the cycle's length is fixed now, from the walk and the current work speed
	b.working = true
	if sim._coming.has(p.id):
		_count_cycle(b, p, sim._coming[p.id])     # so the next building to check sees it
	b.msg = "Working"
	b.t_start = sim.time
	b.rate_c = sim.rate(p, b)
	# a steam engine (build 64): half a coal a cycle, and the cycle goes faster
	if b.steam:
		b.rate_c *= sim.railway.steam_cycle(b, p)
	# blasting (build 57): with Blasting powder, mines and quarries charge the rock with gunpowder from
	# the stores when there is some, and break it 30% faster
	if String(d.get("trade", "")) == "mining" and p.techs.has("blasting_powder") and float(p.stock.get("gunpowder", 0.0)) >= BLAST_MIN:
		sim.used(p, "gunpowder", sim.take(p, "gunpowder", 1.0))
		b.rate_c *= 1.0 + BLAST
	b.t_end = sim.time + (cyc + sim.walk_time(b)) / maxf(0.05, b.rate_c)
	b.retry = b.t_end


const BLAST := 0.3
const BLAST_MIN := 4.0      # (gunpowder kept back for the guns: blasting only uses it above this)


## How far the current work cycle has got, from 0 to 1.
func work_progress(b: Sim.Bld) -> float:
	if not b.working or b.t_end <= b.t_start:
		return 0.0
	return clampf((sim.time - b.t_start) / (b.t_end - b.t_start), 0.0, 1.0)


## A wonder is finished: its bonus counts from now on, everyone hears of it, and the first realm with
## every wonder wins (when the research victory, the peaceful way to win, is on).
func _wonder_done(b: Sim.Bld, p: Sim.Player) -> void:
	sim._recompute_mods(p)
	var n := sim.wonders_of(p).size()
	var all := Sim.wonder_count()
	if p.ai:
		sim.emit_log("%s has built the %s (%d of %d wonders)." % [p.name, String(b.def.name), n, all], Color("c0a0e0"), Vector2i(b.x, b.y))
	else:
		sim.emit_log("The %s stands: %d of %d wonders. %s" % [String(b.def.name), n, all, GameData.effect_text(b.def.wonder)], Color("d8aa4a"), Vector2i(b.x, b.y))
	if n >= all and sim.research_victory and not sim.over:
		sim.over = true
		if p.id == 1 or Diplomacy.relation(sim, p.id, 1) == Diplomacy.ALLY:
			sim.emit_log("All the wonders of the ages stand in your realm! Victory." if p.id == 1 else "Your ally %s built every wonder. Shared victory!" % p.name, Color("d8aa4a"))
			sim.ended.emit(true)
		else:
			sim.emit_log("%s built every wonder of the ages first." % p.name, Color("e0603a"))
			sim.ended.emit(false)
