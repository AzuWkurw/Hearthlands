extends SceneTree
## Trade by cart between markets, standing offers, and war on the way:
## godot --headless --script res://tools/trade_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("showcase", 2, 4, true)
	var me := sim.human()
	var q := sim.players[1]
	var ok := true
	Diplomacy.set_relation(sim, 1, 2, Diplomacy.PEACE)
	sim.give(me, "planks", 60.0)
	sim.give(q, "ore_iron", 40.0)
	var why := Diplomacy.propose(sim, 1, 2, "trade", {"planks": 10}, {"ore_iron": 1})
	print("without a market: ", why)
	if not why.begins_with("You need a market"): ok = false; print("FAIL: a market should be needed")
	# a market next to the headquarters
	var m: Sim.Bld = null
	for r in range(3, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if m == null and sim.can_place("market", me.hq.x + dx, me.hq.y + dy, 1) == "":
					m = sim.add_bld("market", me.hq.x + dx, me.hq.y + dy, me, true, 0)
	print("market at ", Vector2i(m.x, m.y))
	var ore0 := float(me.stock.get("ore_iron", 0.0))
	var planks0 := float(me.stock.get("planks", 0.0))
	why = Diplomacy.propose(sim, 1, 2, "trade", {"planks": 10}, {"ore_iron": 1})
	print("with a market: '", why, "'")
	var carts := sim.trips.filter(func(t): return t.kind == "trade")
	print("carts on the way: ", carts.size(), ", planks now ", float(me.stock.get("planks", 0.0)), " (were ", planks0, ")")
	if why != "" or carts.size() != 2: ok = false; print("FAIL: the trade should go by two carts")
	var arrive: float = carts[0].t1
	while sim.time < arrive + 1.0: sim.tick(Sim.TICK)
	print("iron ore after the carts: ", float(me.stock.get("ore_iron", 0.0)), " (was ", ore0, ")")
	if float(me.stock.get("ore_iron", 0.0)) < ore0 + 1.0: ok = false; print("FAIL: the ore should have arrived")
	# a standing offer every 60 s: made again by itself
	Diplomacy.add_standing(sim, 2, {"planks": 5}, {}, 60.0)
	var t0 := sim.time
	while sim.time < t0 + 130.0: sim.tick(Sim.TICK)
	print("standing gift made ", sim.standing[0].done, " times")
	if int(sim.standing[0].done) < 3: ok = false; print("FAIL: the standing offer should repeat")
	# war while carts are on the way: the goods are lost
	Diplomacy.propose(sim, 1, 2, "gift", {"planks": 5}, {})
	var qp0 := float(q.stock.get("planks", 0.0))
	Diplomacy.declare_war(sim, 1, 2)
	var c2 := sim.trips.filter(func(t): return t.kind == "trade" and not t.delivered)
	var t1: float = 0.0
	for c in c2: t1 = maxf(t1, c.t1)
	while sim.time < t1 + 1.0: sim.tick(Sim.TICK)
	print("rival planks after war broke out: ", float(q.stock.get("planks", 0.0)), " (were ", qp0, ")")
	# save and load with carts on the way
	Diplomacy.set_relation(sim, 1, 2, Diplomacy.PEACE)
	# (a standing offer stops when war breaks out; set one up again for the save)
	if sim.standing.is_empty():
		Diplomacy.add_standing(sim, 2, {"planks": 5}, {}, 60.0)
	Diplomacy.propose(sim, 1, 2, "gift", {"planks": 5}, {})
	var d := sim.to_save()
	var s2 := Sim.new()
	s2.from_save(bytes_to_var(var_to_bytes(d)))
	print("after load: carts ", s2.trips.filter(func(t): return t.kind == "trade").size(), ", standing ", s2.standing.size())
	if s2.standing.size() != 1: ok = false; print("FAIL: standing offers should be saved")
	print("trade test: ", "ok" if ok else "FAILED")
	quit()
