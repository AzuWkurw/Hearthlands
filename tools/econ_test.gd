extends SceneTree
## Build 53: prices that move, selling and buying at a market, children who grow up (and go to school),
## the bottleneck finder. godot --headless --script res://tools/econ_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("econ", 2, 5, false, 128, false, {})
	var me := sim.human()
	for i in 20: sim.tick(Sim.TICK)
	# 1. prices: a good nobody has grows dear, one everybody has plenty of grows cheap
	for p in sim.players:
		p.stock["iron"] = 0.0
		sim.give(p, "stone", 200.0)
	var t_end := sim.time + 12 * 60.0
	while sim.time < t_end:
		sim.tick(Sim.TICK)
		for p in sim.players:
			p.stock["iron"] = 0.0
	check(sim.market.factor("iron") > 1.5, "iron that nobody has is dear (%.2f of its worth)" % sim.market.factor("iron"))
	check(sim.market.factor("stone") < 0.9, "stone everyone has plenty of is cheap (%.2f)" % sim.market.factor("stone"))
	check(sim.market.trend("iron") >= 0 and (sim.price_hist.get("iron", []) as Array).size() >= 10, "prices keep a history (%d minutes)" % (sim.price_hist.get("iron", []) as Array).size())
	# 2. the market: no market, no trade; with one, sell and buy
	check(sim.market.sell(me, "stone", 10) != "", "no selling without a market")
	var mk: Sim.Bld = null
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			if mk == null and sim.can_place("market", me.hq.x + dx, me.hq.y + dy, 1) == "":
				mk = sim.add_bld("market", me.hq.x + dx, me.hq.y + dy, me, true)
	for i in 12: sim.tick(Sim.TICK)
	check(mk != null and sim.market.has_market(me), "a market")
	sim.give(me, "stone", 30.0)
	var g0 := float(me.stock.get("gold", 0.0))
	var s0 := float(me.stock.get("stone", 0.0))
	var f0 := sim.market.factor("stone")
	var expect := sim.market.sell_price("stone", 10)
	check(sim.market.sell(me, "stone", 10) == "" and float(me.stock.get("gold", 0.0)) == g0 + expect and float(me.stock.get("stone", 0.0)) == s0 - 10.0, "sold 10 stone for %d gold" % expect)
	check(sim.market.factor("stone") < f0, "selling pushes the price down")
	sim.give(me, "gold", 200.0)
	var cost := sim.market.buy_price("iron", 10)
	var i0 := float(me.stock.get("iron", 0.0))
	check(sim.market.buy(me, "iron", 10) == "" and float(me.stock.get("iron", 0.0)) == i0 + 10.0, "bought 10 iron for %d gold (dear)" % cost)
	check(cost > expect * 2, "dear iron costs more than cheap stone")
	# 3. children: born while there is food and room, grown up after 5 minutes
	me.kids = []
	me.born = 0.0
	me.peasant = 40
	sim.give(me, "bread", 120.0)
	print("  housing %d, people %d" % [sim.housing(me), sim.pop_total(me)])
	me.kids = [sim.time - SimPeople.GROW - 1.0, sim.time - 10.0]
	var p0 := me.peasant
	var a0 := me.artisan
	sim.people.families(me)
	check(me.kids.size() == 1 and me.peasant + me.artisan == p0 + a0 + 1, "a grown child joins the people (peasant %d->%d, artisan %d->%d)" % [p0, me.peasant, a0, me.artisan])
	# with a school at work and bread for lunch, the child comes out an artisan
	var sc: Sim.Bld = null
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			if sc == null and sim.can_place("school", me.hq.x + dx, me.hq.y + dy, 1) == "":
				sc = sim.add_bld("school", me.hq.x + dx, me.hq.y + dy, me, true)
	for i in 12: sim.tick(Sim.TICK)
	sc.staffed = true
	sc.inbuf = {"bread": 3}
	me.peasant = 40
	me.kids = [sim.time - SimPeople.GROW - 1.0]
	var art := me.artisan
	sim.people.families(me)
	check(me.artisan == art + 1 and me.schooled >= 1 and int(sc.inbuf.get("bread", 0)) == 2, "with a school at work the child becomes an artisan (and eats a bread)")
	# births
	me.kids = []
	me.born = 0.99
	sim.people.families(me)
	check(me.kids.size() == 1 or sim.pop_total(me) + 0 >= sim.housing(me), "a child is born (room %d of %d)" % [sim.pop_total(me), sim.housing(me)])
	# 4. the bottleneck finder
	check(UiBottlenecks.good_of("Needs flour") == "flour" and UiBottlenecks.good_of("Waiting for grain on its way") == "grain" and UiBottlenecks.good_of("Needs axes for a new worker") == "", "reads which good a workshop waits for")
	var bk: Sim.Bld = null
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			if bk == null and sim.can_place("bakery", me.hq.x + dx, me.hq.y + dy, 1) == "":
				bk = sim.add_bld("bakery", me.hq.x + dx, me.hq.y + dy, me, true)
	for i in 12: sim.tick(Sim.TICK)
	bk.staffed = true
	bk.working = false
	bk.msg = "Needs flour"
	var found := UiBottlenecks.find(sim, me)
	var line := ""
	for e in found:
		if String(e[3]) == "flour":
			line = String(e[1])
	print("  " + line)
	check(line.contains("bakery") and line.contains("flour") and line.contains("in store"), "the finder names the bakery waiting for flour and looks at who makes it")
	# 5. saved and loaded
	var s2 := Sim.new()
	s2.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	check(s2.market.factor("iron") == sim.market.factor("iron") and s2.human().kids.size() == me.kids.size(), "prices and children are saved")
	print("ECON TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
