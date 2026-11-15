extends SceneTree
## Build 57: sulfur, saltpeter, charcoal and gunpowder; guns that need powder.
## godot --headless --script res://tools/powder_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


func _spot(sim: Sim, ty: String, near: Vector2i) -> Vector2i:
	for r in range(1, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var x := near.x + dx
				var y := near.y + dy
				if sim.can_place(ty, x, y, 1) == "":
					return Vector2i(x, y)
	return Vector2i(-1, -1)


## One work cycle of building b: what it yields (straight into the stores, as no carrier is needed here).
func _make(sim: Sim, b: Sim.Bld, _secs: float) -> void:
	sim.production.finish_prod(b, sim.players[b.p - 1])


func _init() -> void:
	GameData.ensure()
	check(GameData.res_by_id.has("sulfur") and GameData.res_by_id.has("gunpowder") and GameData.ORE_NAMES.get(6) == "sulfur", "sulfur, saltpeter, charcoal and gunpowder are goods; sulfur is an ore")
	var sim := Sim.new()
	sim.new_game("powder", 2, 5, false, 192, false, {"all_research": true, "features": []})
	var me := sim.human()
	var n_sulfur := 0
	for i in sim.ore.size():
		if sim.ore[i] == 6: n_sulfur += 1
	check(n_sulfur > 0, "the map has sulfur deposits (%d tiles)" % n_sulfur)
	for i in 20: sim.tick(Sim.TICK)
	# own a wide area so everything fits
	for y in range(maxi(0, me.hq.y - 28), mini(sim.h, me.hq.y + 29)):
		for x in range(maxi(0, me.hq.x - 28), mini(sim.w, me.hq.x + 29)):
			if sim.owner[sim.idx(x, y)] == 0: sim.owner[sim.idx(x, y)] = 1
	var at := Vector2i(me.hq.x, me.hq.y)
	# charcoal and saltpeter from logs, gunpowder from the three
	var cb := sim.add_bld("charcoal_burner", _spot(sim, "charcoal_burner", at).x, _spot(sim, "charcoal_burner", at).y, me, true)
	cb.inbuf = {"wood": 4}
	_make(sim, cb, 30.0)
	check(int(cb.out_buf.get("charcoal", 0)) + int(me.stock.get("charcoal", 0.0)) >= 1, "the charcoal burner burns logs into charcoal (%s)" % cb.msg)
	var sp := _spot(sim, "powder_mill", at)
	var pm := sim.add_bld("powder_mill", sp.x, sp.y, me, true)
	var g0 := int(me.stock.get("gunpowder", 0.0))
	pm.inbuf = {"sulfur": 2, "saltpeter": 4, "charcoal": 2}
	_make(sim, pm, 40.0)
	check(int(pm.out_buf.get("gunpowder", 0)) + int(me.stock.get("gunpowder", 0.0)) >= g0 + 2, "the powder mill makes 2 gunpowder from sulfur, saltpeter and charcoal (%s)" % pm.msg)
	# a sulfur mine only on sulfur
	var su := -1
	for i in sim.ore.size():
		if sim.ore[i] == 6 and sim.vein_left(i) > 0:
			su = i; break
	var cx := su % sim.w
	var cy := su / sim.w
	for y in range(maxi(0, cy - 3), mini(sim.h, cy + 4)):
		for x in range(maxi(0, cx - 3), mini(sim.w, cx + 4)):
			sim.owner[sim.idx(x, y)] = 1
	check(sim.can_place("sulfur_mine", cx, cy, 1) == "" or sim.can_place("sulfur_mine", cx, cy, 1).contains("road") or sim.can_place("sulfur_mine", cx, cy, 1).contains("building"), "a sulfur mine fits on a sulfur deposit (%s)" % sim.can_place("sulfur_mine", cx, cy, 1))
	var off := -1
	for i in sim.ore.size():
		if sim.ore[i] == 1 and sim.owner[i] == 1:
			off = i; break
	if off >= 0:
		check(sim.can_place("sulfur_mine", off % sim.w, off / sim.w, 1).contains("sulfur"), "but not on coal")
	# a gun battery fires only with powder, and uses a charge a volley
	var bp := _spot(sim, "battery", at)
	var bt := sim.add_bld("battery", bp.x, bp.y, me, true)
	bt.garrison = 4
	for i in 12: sim.tick(Sim.TICK)
	sim.staffing(me)
	check(bt.staffed, "a battery takes goods (carriers bring it gunpowder)")
	var q := sim.players[1]
	var a := Sim.Attack.new()
	a.p = q.id; a.n = 10; a.amix = [0, 10, 0, 0, 0, 0, 0]; a.dvt = [0.0, 0.0, 0.0]
	bt.inbuf = {}
	sim.military._cannon(a, q, bt, 3.0)
	check(a.n == 10 and a.dshot_t < sim.time, "no gunpowder: the guns stay quiet")
	bt.inbuf = {"gunpowder": 2}
	var shots := 0
	for k in 20:
		var n0 := a.n
		sim.military._cannon(a, q, bt, 3.0)
		if a.dshot_t == sim.time: shots += 1
		a.dvt[2] = 0.0
		if int(bt.inbuf.get("gunpowder", 0)) <= 0: break
	check(shots == 2 and int(bt.inbuf.get("gunpowder", 0)) == 0, "with 2 charges the battery fires 2 volleys (%d)" % shots)
	check((GameData.bld["naval_yard"]["in"] as Dictionary).has("gunpowder") and (GameData.bld["gunsmith"]["in"] as Dictionary).has("gunpowder"), "naval yards and gunsmiths use gunpowder")
	# lead and cartridges
	check(GameData.ORE_NAMES.get(7) == "lead" and GameData.res_by_id.has("lead") and GameData.res_by_id.has("ammunition"), "lead ore, lead and cartridges are goods; lead is an ore")
	var n_lead := 0
	for i in sim.ore.size():
		if sim.ore[i] == 7: n_lead += 1
	check(n_lead > 0, "the map has lead deposits (%d tiles)" % n_lead)
	var ls := _spot(sim, "lead_smelter", at)
	var lsb := sim.add_bld("lead_smelter", ls.x, ls.y, me, true)
	var l0 := int(me.stock.get("lead", 0.0))
	_make(sim, lsb, 0.0)
	check(int(me.stock.get("lead", 0.0)) + int(lsb.out_buf.get("lead", 0)) >= l0 + 2, "the lead smelter makes 2 lead")
	var cw := _spot(sim, "cartridge_works", at)
	var cwb := sim.add_bld("cartridge_works", cw.x, cw.y, me, true)
	var a0 := int(me.stock.get("ammunition", 0.0))
	_make(sim, cwb, 0.0)
	check(int(me.stock.get("ammunition", 0.0)) + int(cwb.out_buf.get("ammunition", 0)) >= a0 + 3, "the cartridge works makes 3 cartridges")
	# musketeers fire only with cartridges
	var col := Sim.Attack.new()
	col.p = 1; col.n = 10; col.amix = [0, 0, 0, 0, 0, 10, 0]
	sim.take(me, "ammunition", float(me.stock.get("ammunition", 0.0)))
	sim.military.pack_supplies(col, me, me.hq)
	check(col.ammo == 0 and sim.military._ammo_for(col, 10) == 0, "no cartridges in store: the musketeers set out without, and cannot fire")
	sim.give(me, "ammunition", 20.0)
	sim.military.pack_supplies(col, me, me.hq)
	check(col.ammo == 4, "10 musketeers take 4 cartridges (4 volleys of 10 shots) (%d)" % col.ammo)
	check(sim.military._ammo_for(col, 10) == 10 and col.ammo == 3, "a volley of 10 uses one cartridge")
	var st0 := float(me.stock.get("ammunition", 0.0))
	check(sim.military._ammo_from_stores(me, 12) == 12 and float(me.stock.get("ammunition", 0.0)) == st0 - 2.0, "a garrison's 12 musketeers take 2 cartridges from the stores")
	sim.take(me, "ammunition", float(me.stock.get("ammunition", 0.0)))
	check(sim.military._ammo_from_stores(me, 12) == 0, "and stay silent without")
	# fireworks
	check(GameData.res_by_id.has("fireworks") and (GameData.bld["pyrotechnist"]["in"] as Dictionary).has("sulfur"), "a pyrotechnist makes fireworks from sulfur, saltpeter and charcoal")
	print("POWDER TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
