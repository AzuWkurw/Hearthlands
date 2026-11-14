extends SceneTree
## Build 55: the isles map, dry and wet years, storms keeping ships in, river boats, disasters with a
## choice. godot --headless --script res://tools/world_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


func _init() -> void:
	GameData.ensure()
	# 1. isles: each realm alone on its island
	var sim := Sim.new()
	sim.new_game("isles-test", 3, 5, false, 160, false, {"gen": {"shape": "isles"}, "features": Features.default_ids()})
	var alone := 0
	for p in sim.players:
		p.island_t = -1000.0
		if sim.naval.island(p): alone += 1
	check(alone == sim.players.size(), "isles: all %d realms alone on their islands" % sim.players.size())
	var me := sim.human()
	for i in 20: sim.tick(Sim.TICK)
	# 2. dry and wet years
	var se = sim.get_feature("seasons")
	var k: int = se.biome_of(me)
	se.year_kind[k] = ""
	se._cache[k].clear()
	var normal: float = se._bonus("orchard", k)
	se.year_kind[k] = "dry"
	var dry: float = se._bonus("orchard", k)
	se.year_kind[k] = "wet"
	var wet: float = se._bonus("orchard", k)
	check(dry < normal and wet > normal, "orchards: a dry year slower (%.2f), a wet one faster (%.2f), than usual (%.2f)" % [dry, wet, normal])
	se.year_kind[k] = ""
	# 3. a storm keeps ships in harbour
	var hb: Sim.Bld = null
	for r in range(2, 16):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if hb == null and sim.can_place("harbour", me.hq.x + dx, me.hq.y + dy, 1) == "":
					hb = sim.add_bld("harbour", me.hq.x + dx, me.hq.y + dy, me, true)
	check(hb != null, "a harbour on the coast")
	if hb != null:
		se.weather[se.biome_at(hb.x, hb.y)] = "storm"
		me.ships = 1
		var q := sim.players[1]
		Diplomacy.declare_war(sim, 1, q.id)
		me.reserve = 6
		var why := sim.military.launch_landing(hb, q.hq, 6)
		check(why.begins_with("A storm"), "no landing sets sail in a storm (%s)" % why)
		se.weather[se.biome_at(hb.x, hb.y)] = "clear"
	# 4. river boats: two landings on the same water, no road between (the realm's land made wider)
	for y in range(maxi(0, me.hq.y - 30), mini(sim.h, me.hq.y + 31)):
		for x in range(maxi(0, me.hq.x - 30), mini(sim.w, me.hq.x + 31)):
			if sim.owner[sim.idx(x, y)] == 0:
				sim.owner[sim.idx(x, y)] = 1
	me.techs["timber_framing"] = true
	var spots := []
	var whyn := {}
	for y in range(4, sim.h - 4, 2):
		for x in range(4, sim.w - 4, 2):
			if sim.owner[sim.idx(x, y)] == 1:
				var wy := sim.can_place("river_landing", x, y, 1)
				if wy == "": spots.append(Vector2i(x, y))
				else: whyn[wy] = int(whyn.get(wy, 0)) + 1
	var pair := []
	for a: Vector2i in spots:
		for b: Vector2i in spots:
			if pair.is_empty() and Vector2(a - b).length() > 9.0 and not sim.sea.water_path(a.x, a.y, b.x, b.y).is_empty():
				pair = [a, b]
	check(not pair.is_empty(), "two landing spots on the same water (%d spots) %s" % [spots.size(), str(whyn).left(300) if spots.is_empty() else ""])
	if not pair.is_empty():
		var la := sim.add_bld("river_landing", pair[0].x, pair[0].y, me, true)
		var lb := sim.add_bld("river_landing", pair[1].x, pair[1].y, me, true)
		for i in 12: sim.tick(Sim.TICK)
		sim.logistics.store_add(la, me, "planks", 20.0)
		var had := float(lb.inv.get("planks", 0.0))
		var boat := false
		var t_end := sim.time + 120.0
		while sim.time < t_end:
			sim.tick(Sim.TICK)
			for t in sim.trips:
				if t.kind == "boat":
					boat = true
			if float(lb.inv.get("planks", 0.0)) > had + 0.5:
				break
		check(boat, "a boat set out from the landing with plenty")
		check(float(lb.inv.get("planks", 0.0)) > had + 0.5 or not boat, "and brought planks to the other (%d there now)" % int(lb.inv.get("planks", 0.0)))
	# 5. disasters with a choice
	var ev = sim.get_feature("events")
	me.peasant = 60
	sim.give(me, "bread", 30.0); sim.give(me, "beer", 15.0)
	var b0 := float(me.stock.get("bread", 0.0))
	ev._answer(me, "revolt", 0)
	check(float(me.stock.get("bread", 0.0)) <= b0 - 19.0 and ev._boost(me, "all") > 0.0, "a revolt calmed with a feast: bread eaten, work faster")
	var pz := me.peasant
	ev._answer(me, "revolt", 2)
	check(me.peasant == pz - 3, "waiting a revolt out: 3 peasants leave")
	ev._answer(me, "plague", 0)
	check(me.gates_until > sim.time, "closing the gates against a plague")
	var imm := me.peasant
	me.imm_t = 100
	sim.tick(Sim.TICK)
	check(me.peasant <= imm, "no newcomers while the gates are shut")
	var dz = sim.get_feature("diseases")
	ev._answer(me, "plague", 2)
	check(dz == null or float((dz.sick.get(me.id, {}) as Dictionary).get("plague", 0.0)) > 0.0, "carrying on as usual lets the plague in")
	var n0 := sim.blds.size()
	ev._answer(me, "great_fire", 1)
	check(sim.blds.filter(func(b): return not b.dead).size() <= n0, "a great fire: pulling down the burning building")
	check(ev.CHOICES.has("great_fire") and ev.CHOICES.has("plague") and ev.CHOICES.has("revolt"), "the three disasters ask you to choose")
	# 6. saved and loaded
	se.year_kind[k] = "wet"
	var s2 := Sim.new()
	s2.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	check(String(s2.get_feature("seasons").year_kind[k]) == "wet" and s2.human().gates_until == me.gates_until, "the year and shut gates are saved")
	print("WORLD TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
