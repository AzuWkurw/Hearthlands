extends SceneTree
## Tests the looks of the ages, renovation and soldier kinds.
## Run: godot --headless --script res://tools/age_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("agetest", 3, 5, false, 0, true, {})
	var me := sim.human()
	print("start: hq era %d, soldiers %s (res_era %.1f)" % [me.hq.era, Sim.soldier_name(roundi(me.res_era)), me.res_era])
	for p in sim.players: p.ai = true
	while sim.time < 6 * 60.0: sim.tick(Sim.TICK)
	for p in sim.players: p.ai = p.id != 1
	var old: Sim.Bld = sim.realm_blds(me).filter(func(b): return b.state == "ready" and b.ty != "hq" and b.def.has("cost")).front()
	me.age = 2
	print("now High Medieval; %s (era %d) can renovate: '%s'" % [old.ty, old.era, sim.can_renovate(old)])
	var planks := int(me.stock.planks)
	print("renovate: '%s', need %s" % [sim.renovate(old), old.need])
	var t0 := sim.time
	while old.reno_to >= 0 and sim.time < t0 + 200.0: sim.tick(Sim.TICK)
	print("renovated after %.0f s: era %d, spent %s, planks %d -> %d, working again: %s" % [sim.time - t0, old.era, old.spent, planks, int(me.stock.planks), old.msg != "Being renovated"])
	var n := sim.renovate_all(me, "woodcutter")
	print("renovate all woodcutters: %d queued, running %d, waiting %d" % [n, sim._renos_running(me), (sim.reno_queue.get(1, []) as Array).size()])
	# soldiers: a new one is of the current kind, an idle barracks retrains old ones
	var e0 := me.res_era
	me.reserve += 0
	print("soldiers before: %.2f (%s)" % [e0, Sim.soldier_name(roundi(e0))])
	var spot := Vector2i(-1, -1)
	for r in range(2, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if spot.x < 0 and sim.can_place("barracks", me.hq.x + dx, me.hq.y + dy, 1) == "":
					spot = Vector2i(me.hq.x + dx, me.hq.y + dy)
	var bk: Sim.Bld = null
	if spot.x >= 0:
		sim.place("barracks", spot.x, spot.y, me)
		bk = sim.bld_at(spot.x, spot.y)
	else:
		# no medium spot on this map yet: put one up at once next to the headquarters' road (the test is
		# about the soldiers it trains, not about placing)
		for i in sim.owned(1)[0]:
			if bk == null and sim.bmap[i] == 0 and sim.road[i] == 0 and sim.plot[i] == 0 and sim.ter[i] != Sim.WATER and sim.deco[i] == 0 and sim.logistics.net_dist(1, sim.door_at(i % sim.w, i / sim.w, 0)) < Sim.INF:
				bk = sim.add_bld("barracks", i % sim.w, i / sim.w, me, true, 0)
				sim.net_dirty(1)
		print("no medium spot free: barracks put up at once")
	me.stock.weapons = 10.0; me.stock.bread = 40.0; me.stock.planks = 40.0; me.stock.stone = 40.0
	while sim.time < t0 + 900.0: sim.tick(Sim.TICK)
	print("barracks %s; soldiers now %.2f (%s), reserve %d" % [bk.state, me.res_era, Sim.soldier_name(roundi(me.res_era)), me.reserve])
	var olds := 0
	for p in sim.players:
		if p.ai:
			for b in sim.realm_blds(p):
				if b.era < p.age: olds += 1
	print("rival ages: %s" % str(sim.players.map(func(p): return p.age)))
	var d := sim.to_save()
	var sim2 := Sim.new()
	print("load: '%s', renovations running %d" % [sim2.from_save(d), sim2._reno.size()])
	sim.dispose(); sim2.dispose()
	quit()
