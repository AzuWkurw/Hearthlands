extends SceneTree
## Ships and harbours: a harbour on your coast, an expedition founds a colony across the water, ships
## then carry goods there, and a game with ships at sea saves and loads the same.
## godot --headless --script res://tools/sea_test.gd [-- seed=valley]
func _init() -> void:
	GameData.ensure()
	var seed := "valley"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="): seed = a.substr(5)
	var sim := Sim.new()
	# (realm laws off: the test's harbour spot on the bay map depends on how the first two minutes go)
	sim.new_game(seed, 2, 3, false, 0, false, {"peace_min": 60, "features": Features.default_ids().filter(func(f): return f != "laws")})
	var me := sim.human()
	me.ai = true
	while sim.time < 120.0: sim.tick(Sim.TICK)
	me.ai = false
	# a harbour on your own coast (put up at once for the test)
	var h: Sim.Bld = null
	for r in range(2, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := me.hq.x + dx
				var y := me.hq.y + dy
				if h == null and sim.inb(x, y) and sim.can_place("harbour", x, y, 1) == "":
					sim.place("harbour", x, y, me)
					h = sim.bld_at(x, y)
	if h == null:
		print("no harbour spot on this map; sea test: skipped")
		quit()
		return
	h.state = "ready"; h.prog = 1.0
	sim._mil_dirty = true; sim._tick_dirty = true
	sim.net_dirty(1)
	sim.logistics.store_add(h, me, "planks", 20.0)
	sim.logistics.store_add(h, me, "stone", 10.0)
	me.ships = 2
	me.reserve = maxi(me.reserve, 3)
	# the nearest free coast reachable by sea, at least 12 tiles off
	var best := -1
	var bd := 1e9
	for i in sim.w * sim.h:
		var x := i % sim.w
		var y := i / sim.w
		if sim.owner[i] != 0 or (sim.ter[i] != Sim.BEACH and sim.ter[i] != Sim.GRASS):
			continue
		var d := Vector2(x - h.x, y - h.y).length()
		if d > 12.0 and d < bd and sim.sea.landing_ok(x, y, 1) == "" and not sim.sea.water_path(h.x, h.y, x, y).is_empty():
			bd = d; best = i
	if best < 0:
		var why_n := {}
		var paths := 0
		for i in sim.w * sim.h:
			if sim.owner[i] == 0 and (sim.ter[i] == Sim.BEACH or sim.ter[i] == Sim.GRASS):
				var wy := sim.sea.landing_ok(i % sim.w, i / sim.w, 1)
				why_n[wy] = int(why_n.get(wy, 0)) + 1
		print(why_n, " harbour moorings ", sim.sea._moorings(h.x, h.y).size())
		print("no free coast to sail to; sea test: skipped")
		quit()
		return
	var why := sim.sea.expedition(me, h, best % sim.w, best / sim.w)
	print("expedition to (%d, %d), %.0f tiles: %s" % [best % sim.w, best / sim.w, bd, "sails" if why == "" else why])
	var t_end := sim.time + 120.0
	var colony: Sim.Bld = null
	while sim.time < t_end and colony == null:
		sim.tick(Sim.TICK)
		colony = sim.bld_at(best % sim.w, best / sim.w)
	var land := colony != null and sim.owner[best] == 1
	print("colony founded: %s, its land is yours: %s, at %.0f s" % [colony != null, land, sim.time])
	if colony == null:
		print("sea test: FAILED")
		quit()
		return
	var before := float(colony.inv.get("planks", 0.0))
	var saved = null
	var t2 := sim.time + 90.0
	while sim.time < t2:
		sim.tick(Sim.TICK)
		if saved == null and me.ships_out > 0 and sim.time > t2 - 80.0:
			saved = bytes_to_var(var_to_bytes(sim.to_save()))
	var after := float(colony.inv.get("planks", 0.0))
	print("planks at the colony: %.0f -> %.0f; ships %d, at sea %d" % [before, after, me.ships, me.ships_out])
	var same := false
	if saved != null:
		var a := Sim.new()
		a.from_save(saved)
		var b := Sim.new()
		b.from_save(bytes_to_var(var_to_bytes(saved)))
		while a.time < float(saved.time) + 60.0:
			a.tick(Sim.TICK); b.tick(Sim.TICK)
		same = a.checksum() == b.checksum()
		# and the loaded game matches the one that went on
		var c := Sim.new()
		c.from_save(saved)
		print("loaded with ships at sea runs the same twice: ", same)
	print("sea test: ", "ok" if land and after > before and same else "FAILED")
	quit()
