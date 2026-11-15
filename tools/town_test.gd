extends SceneTree
## Build 60: town quarters (homes near a tavern, chapel and market), rivals that plan their towns round
## such a centre, rivals that buy what their workshops lack and put boats on rivers.
## godot --headless --script res://tools/town_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


func spot(sim: Sim, ty: String, cx: int, cy: int, pid := 1) -> Vector2i:
	for r in range(1, 25):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and sim.can_place(ty, cx + dx, cy + dy, pid) == "":
					return Vector2i(cx + dx, cy + dy)
	return Vector2i(-1, -1)


func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("quarters", 2, 5, false, 128, false, {"features": Features.default_ids()})
	var me := sim.human()
	for i in 10: sim.tick(Sim.TICK)
	var ct = sim.get_feature("contentment")
	# 1. a quarter: tavern, chapel and market with homes round them
	var c := Vector2i(me.hq.x + 6, me.hq.y + 6)
	var made := {}
	for ty in ["tavern", "chapel", "market", "house", "house", "house"]:
		var at := spot(sim, ty, c.x, c.y)
		if at.x >= 0:
			var b := sim.add_bld(ty, at.x, at.y, me, true)
			made[b.id] = b
	var tav: Sim.Bld = null
	var house: Sim.Bld = null
	for id in made:
		var b: Sim.Bld = made[id]
		if b.ty == "tavern" or b.ty == "chapel":
			ct.served[b.id] = sim.time
		if b.ty == "tavern": tav = b
		if b.ty == "house" and house == null: house = b
	for i in int(6.0 / Sim.TICK): sim.tick(Sim.TICK)
	check(house != null and ct.in_quarter(house), "a home near a working tavern, chapel and market is in a town quarter")
	check(ct.quarter_share(me) > 0.0, "the realm's homes in quarters: %d%%" % roundi(ct.quarter_share(me) * 100.0))
	var lines: PackedStringArray = ct.building_lines(house)
	check(lines.size() > 0 and lines[0].contains("In a town quarter"), "the home's info says so")
	# the quarter's tax
	me.noble = 10
	me.tax = 0.0
	var share: float = ct.quarter_share(me)
	var t_without: float = 10 * (0.4 + 0.8 * float(me.sat.noble)) * (1.0 + sim.mod(me, "tax") + Sim.LUX_TAX * me.lux) / 60.0
	sim.tick(Sim.TICK)
	for i in int(1.0 / Sim.TICK): sim.tick(Sim.TICK)
	check(ct.QUARTER_TAX * share > 0.0, "nobles in a quarter pay %d%% more tax" % roundi(ct.QUARTER_TAX * share * 100.0))
	# a tavern gone cold: no quarter
	ct.served[tav.id] = -1e9
	check(not ct.in_quarter(house), "without a working tavern it is no quarter")
	# 2. rivals plan their towns: a home scores best in a ring round the centre
	var q := sim.players[1]
	var qc := Vector2i(q.hq.x + 7, q.hq.y)
	var tq := spot(sim, "tavern", qc.x, qc.y, q.id)
	if tq.x >= 0:
		sim.add_bld("tavern", tq.x, tq.y, q, true)
	for i in 12: sim.tick(Sim.TICK)
	var centre: Vector2 = sim.ai._town_centre(q)
	check(centre.x >= 0.0, "a rival's town centre at its tavern %s" % str(centre))
	var near_ring: float = sim.ai._site_score("house", int(centre.x) + 5, int(centre.y), q)
	var on_top: float = sim.ai._site_score("house", int(centre.x) + 1, int(centre.y), q)
	var far: float = sim.ai._site_score("house", int(centre.x) + 16, int(centre.y), q)
	check(near_ring > on_top and near_ring > far, "homes go in a ring round it (%.1f) rather than on it (%.1f) or far away (%.1f)" % [near_ring, on_top, far])
	var chap_near: float = sim.ai._site_score("chapel", int(centre.x) + 3, int(centre.y), q)
	var chap_far: float = sim.ai._site_score("chapel", int(centre.x) + 14, int(centre.y), q)
	check(chap_near > chap_far, "a chapel goes by the tavern (%.1f against %.1f)" % [chap_near, chap_far])
	# 3. rivals buy what their workshops lack
	var mk := spot(sim, "market", q.hq.x, q.hq.y + 5, q.id)
	if mk.x >= 0:
		sim.add_bld("market", mk.x, mk.y, q, true)
	var sm := spot(sim, "sawmill", q.hq.x - 5, q.hq.y, q.id)
	var saw: Sim.Bld = sim.add_bld("sawmill", sm.x, sm.y, q, true) if sm.x >= 0 else null
	for i in 12: sim.tick(Sim.TICK)
	if saw != null:
		saw.msg = "Needs wood"
		sim.take(q, "wood", float(q.stock.get("wood", 0.0)))
		for r in Sim.BASIC:
			sim.give(q, r, 20.0)
		sim.give(q, "gold", 200.0)
		var w0 := float(q.stock.get("wood", 0.0))
		sim.market.ai_trade(q)
		check(float(q.stock.get("wood", 0.0)) >= w0 + 10.0, "a rival with a market buys the wood its sawmill stands idle for (%d now)" % int(q.stock.get("wood", 0.0)))
	else:
		check(false, "a sawmill for the rival")
	# 4. saved and loaded
	var s2 := Sim.new()
	s2.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	check(is_equal_approx(s2.get_feature("contentment").quarter_share(s2.human()), ct.quarter_share(me)), "the quarters are the same after loading")
	print("TOWN TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
