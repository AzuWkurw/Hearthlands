extends SceneTree
## Build 61: standing orders at the market (sell or buy every few minutes, keeping a reserve), lots of
## 50, and gold and wealth in the realms graph. godot --headless --script res://tools/route_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("routes", 1, 5, false, 128, false, {"features": Features.default_ids()})
	var me := sim.human()
	for i in 10: sim.tick(Sim.TICK)
	var mk: Sim.Bld = null
	for r in range(2, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if mk == null and sim.can_place("market", me.hq.x + dx, me.hq.y + dy, 1) == "":
					mk = sim.add_bld("market", me.hq.x + dx, me.hq.y + dy, me, true)
	check(mk != null, "a market")
	# 1. orders
	check(sim.market.add_route(me, "planks", true, 10, 1, 30) == "", "an order to sell 10 planks a minute, keeping 30")
	check(sim.market.add_route(me, "stone", false, 10, 2, 25) == "", "an order to buy 10 stone every 2 minutes, up to 25")
	check(sim.market.add_route(me, "gold", true, 10, 1, 0) != "", "gold itself cannot be sold")
	sim.take(me, "planks", float(me.stock.get("planks", 0.0)))
	sim.give(me, "planks", 55.0)
	sim.take(me, "stone", float(me.stock.get("stone", 0.0)))
	sim.give(me, "stone", 4.0)
	sim.give(me, "gold", 30.0)
	var g0 := float(me.stock.get("gold", 0.0))
	var t_end := sim.time + 5.0 * 60.0 + 1.0
	while sim.time < t_end:
		sim.tick(Sim.TICK)
	var pl := int(me.stock.get("planks", 0.0))
	var st := int(me.stock.get("stone", 0.0))
	check(pl >= 30 and pl <= 35 and int(me.routes[0].done) >= 20 and int(me.routes[0].gold) > 0, "planks sold down to the reserve: %d left, %d sold for %+d gold" % [pl, int(me.routes[0].done), int(me.routes[0].gold)])
	check(st >= 14 and st <= 25 + 4 and int(me.routes[1].done) >= 10 and int(me.routes[1].gold) < 0, "stone bought up to 25: %d now (%d bought, %d gold)" % [st, int(me.routes[1].done), int(me.routes[1].gold)])
	var said := false
	for l in sim.logs:
		if String(l[1]).begins_with("Standing orders at your market"): said = true
	check(said, "the log tells what went through")
	# 2. without a market nothing goes
	sim.demolish(mk)
	for i in int(3.0 / Sim.TICK): sim.tick(Sim.TICK)
	var d0 := int(me.routes[0].done)
	sim.give(me, "planks", 50.0)
	t_end = sim.time + 120.0
	while sim.time < t_end:
		sim.tick(Sim.TICK)
	check(int(me.routes[0].done) == d0, "no market, no trade")
	# 3. lots of 50: a cheap good is worth selling
	check(sim.market.sell_price("planks", 50) >= 3, "50 planks sell for %d gold (10 for %d)" % [sim.market.sell_price("planks", 50), sim.market.sell_price("planks", 10)])
	# 4. saved and loaded; removed
	var s2 := Sim.new()
	s2.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	check(s2.human().routes.size() == 2 and int(s2.human().routes[0].done) == d0, "the orders are saved")
	sim.market.remove_route(me, 0)
	check(me.routes.size() == 1 and String(me.routes[0].res) == "stone", "an order removed")
	# 5. the realms graph counts gold and wealth
	var stf = sim.get_feature("statistics")
	var last: Dictionary = (stf.hist[1] as Array)[-1]
	check(last.has("gold") and float(last.get("wealth", 0.0)) > float(last.get("gold", 0.0)), "each minute the realms graph keeps gold (%d) and wealth (%d)" % [int(last.get("gold", 0)), int(last.get("wealth", 0))])
	print("ROUTE TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
