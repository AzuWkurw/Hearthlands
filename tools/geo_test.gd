extends SceneTree
## Tests geologists: ore hidden until surveyed, mines only on surveyed ore, a survey trip, rivals surveying.
## Run: godot --headless --script res://tools/geo_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("geotest", 3, 5, false, 0, true, {})
	var me := sim.human()
	var geo = sim.get_feature("geology")
	# a mountain tile with ore near the headquarters, in or close to our land
	var target := -1
	for r in range(2, 16):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x: int = me.hq.x + dx
				var y: int = me.hq.y + dy
				if target < 0 and sim.inb(x, y) and sim.ter[sim.idx(x, y)] == Sim.MOUNT and sim.ore[sim.idx(x, y)] != 0 and sim.owner[sim.idx(x, y)] == 1:
					target = sim.idx(x, y)
	if target < 0:
		print("no ore in our land on this map"); quit(); return
	var kind := int(sim.ore[target])
	var mine_ty := ""
	for b in GameData.bld:
		if int(GameData.bld[b].get("mine", 0)) == kind: mine_ty = b
	print("ore %s at %d,%d known=%s; place %s: '%s'" % [GameData.ORE_NAMES[kind], target % sim.w, target / sim.w, sim.ore_known(1, target), mine_ty, sim.can_place(mine_ty, target % sim.w, target / sim.w, 1)])
	var pk := int(me.stock.pickaxes)
	print("send: '%s' (pickaxes %d -> %d, away %d)" % [geo.send(me, target % sim.w, target / sim.w), pk, int(me.stock.pickaxes), me.away])
	print("again x2: '%s' / '%s'" % [geo.send(me, target % sim.w, target / sim.w), geo.send(me, target % sim.w, target / sim.w)])
	while geo.trips.any(func(t): return int(t[0]) == 1) and sim.time < 400.0:
		sim.tick(Sim.TICK)
	print("home at %.0f s: known=%s, pickaxes %d, away %d, markers %d" % [sim.time, sim.ore_known(1, target), int(me.stock.pickaxes), me.away, geo.marks.size()])
	var why: String = sim.can_place(mine_ty, target % sim.w, target / sim.w, 1)
	print("place %s now: '%s'" % [mine_ty, why])
	for p in sim.players: p.ai = p.id != 1
	while sim.time < 15 * 60.0: sim.tick(Sim.TICK)
	for p in sim.players:
		if p.ai:
			var mines := sim.realm_blds(p).filter(func(b): return b.def.has("mine")).size()
			print("%s: %d tiles surveyed, %d mines" % [p.name, (geo.known[p.id] as PackedByteArray).count(1), mines])
	var d := sim.to_save()
	var sim2 := Sim.new()
	print("load '%s' known %d" % [sim2.from_save(d), (sim2.get_feature("geology").known[1] as PackedByteArray).count(1)])
	sim.dispose(); sim2.dispose()
	quit()
