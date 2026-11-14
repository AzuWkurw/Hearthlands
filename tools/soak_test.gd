extends SceneTree
## A long game with every rival (and you played by the AI) to catch errors and broken rules:
## godot --headless --script res://tools/soak_test.gd -- seed=valley mins=60 [size=320] [foes=7] [places]
## (places: a dozen ruins and bandit camps scattered between the realms)
## Every minute it checks: stock equals the sum of the stores, no negative stocks or people, no dead
## building still listed, every building on its tile, archers never above the garrison, carts and
## fires only for living buildings. It prints what it saw of the new things (trades, fires, bridges...).
func _init() -> void:
	GameData.ensure()
	var seed := "valley"; var mins := 60; var size := 0; var foes := 5; var places := false
	var opts := {}     # new-game options switched on: opt=road_carriers,all_research
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="): seed = a.substr(5)
		if a.begins_with("mins="): mins = int(a.substr(5))
		if a.begins_with("size="): size = int(a.substr(5))
		if a.begins_with("foes="): foes = int(a.substr(5))
		if a == "places": places = true
		if a.begins_with("shape="):
			opts["gen"] = {"shape": a.substr(6)}
		if a.begins_with("opt="):
			for o in a.substr(4).split(","):
				opts[o] = true
	var sim := Sim.new()
	sim.new_game(seed, foes, 6, true, size, false, opts)
	if places:
		# ruins and bandit camps on free grass between the realms (as a hand-made map would have)
		var put := 0
		for k in 4000:
			if put >= 12: break
			var x := sim.rng.randi() % sim.w
			var y := sim.rng.randi() % sim.h
			var i := sim.idx(x, y)
			if sim.ter[i] != Sim.GRASS or sim.deco[i] != 0 or not Places.at(sim, x, y, 8).is_empty():
				continue
			var near_hq := false
			for p in sim.players:
				if Vector2(p.hq.x - x, p.hq.y - y).length() < 7: near_hq = true
			if near_hq: continue
			sim.places.append(Places.make("bandits" if put % 2 == 0 else "ruins", x, y))
			put += 1
		print("places: ", put)
	var me := sim.human()
	me.ai = true; me.skill = 6; me.pers = "balanced"; me.prod = 1.0; me.think = 3.0; me.max_b = 2
	var bad := 0
	var seen := {"trades": 0, "fires": 0, "burned": 0, "bridges": 0, "archers": 0, "sallies": 0, "markets": 0, "taverns": 0, "festivals": 0, "tributes": 0, "warnings": 0}
	var t_real := Time.get_ticks_msec()
	var last_min := -1
	while sim.time < mins * 60.0 and not sim.over:
		sim.tick(Sim.TICK)
		var m := int(sim.time / 60.0)
		if m == last_min:
			continue
		last_min = m
		for p in sim.players:
			for k in p.stock:
				if float(p.stock[k]) < -0.001:
					bad += 1; print("BAD %s stock %s = %f at minute %d" % [p.name, k, p.stock[k], m])
			if p.peasant < 0 or p.artisan < 0 or p.reserve < 0:
				bad += 1; print("BAD %s people peasant %d artisan %d reserve %d" % [p.name, p.peasant, p.artisan, p.reserve])
			# stock = the stores' goods
			if p.alive:
				var sum := {}
				for b in sim.blds:
					if b.p == p.id and not b.dead and b.def.has("store"):
						for k in b.inv:
							sum[k] = float(sum.get(k, 0.0)) + float(b.inv[k])
				for k in p.stock:
					if absf(float(p.stock[k]) - float(sum.get(k, 0.0))) > 0.01:
						bad += 1; print("BAD %s %s: stock %f, stores %f at minute %d" % [p.name, k, p.stock[k], sum.get(k, 0.0), m])
						break
		for b in sim.blds:
			if b.dead:
				bad += 1; print("BAD dead building listed: ", b.ty)
			elif sim.bmap[sim.idx(b.x, b.y)] != b.id:
				bad += 1; print("BAD building not on its tile: ", b.ty, " ", b.id)
			if b.archers > b.garrison and b.ty != "hq":
				bad += 1; print("BAD archers %d > garrison %d in %s" % [b.archers, b.garrison, b.ty])
			if b.archers > 0: seen.archers = maxi(seen.archers, b.archers)
		for pl: Dictionary in sim.places:
			if int(pl.n) < 0:
				bad += 1; print("BAD bandits below zero at ", pl.x, ",", pl.y)
			# (looting is checked once a second, so land taken during the last second may not have been)
			if pl.kind == "ruins" and not bool(pl.done) and sim.owner[sim.idx(int(pl.x), int(pl.y))] != 0:
				if bool(pl.get("_owned_before", false)):
					bad += 1; print("BAD ruins on owned land not looted at ", pl.x, ",", pl.y)
				pl["_owned_before"] = true
			var party: Dictionary = pl.party
			if not party.is_empty() and (int(party.n) <= 0 or (party.mix as Array).is_empty()):
				bad += 1; print("BAD an empty party on its way: ", party)
		var f = sim.get_feature("fires")
		if f != null:
			for bid in f.burning:
				if not sim.by_id.has(bid):
					bad += 1; print("BAD a fire on a building that is gone")
	for p in sim.players:
		seen.trades += p.trades
	var f2 = sim.get_feature("fires")
	if f2 != null:
		for k in f2.put_out: seen.fires += int(f2.put_out[k])
		for k in f2.lost: seen.burned += int(f2.lost[k])
	var co = sim.get_feature("contentment")
	if co != null:
		for k in co.feasts: seen.festivals += int(co.feasts[k])
	for i in sim.w * sim.h:
		if sim.road[i] != 0 and sim.ter[i] == Sim.WATER: seen.bridges += 1
	for b in sim.blds:
		if b.ty == "market": seen.markets += 1
		if b.ty == "tavern": seen.taverns += 1
	for l in sim.logs:
		var s := String(l[1])
		if "tribute" in s: seen.tributes += 1
		if "patience" in s or "borders press" in s or "counted your soldiers" in s: seen.warnings += 1
	if co != null:
		var moods := []
		for p in sim.players: moods.append(snappedf(co.mood(p), 0.01))
		print("contentment: ", moods, " served taverns: ", co.served.size())
	if not sim.places.is_empty():
		var cl := 0
		var lo := 0
		for pl: Dictionary in sim.places:
			if pl.kind == "bandits" and bool(pl.done): cl += 1
			if pl.kind == "ruins" and bool(pl.done): lo += 1
		print("camps cleared: %d, ruins looted: %d of %d places" % [cl, lo, sim.places.size()])
	print("seen: ", seen)
	print("soak %s %d min: %d problems, %d s real, over %s" % [seed, mins, bad, (Time.get_ticks_msec() - t_real) / 1000, sim.over])
	quit()
