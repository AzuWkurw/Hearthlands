extends SceneTree
func _sig(sim: Sim) -> String:
	var parts := ["t=%.1f" % sim.time, "blds=%d" % sim.blds.size(), "trips=%d" % sim.trips.size()]
	for p in sim.players:
		parts.append("%s:%d/%d r%d rp%.1f wood%d planks%d carriers%d" % [p.name, p.peasant, p.artisan, p.reserve, p.rp, int(p.stock.wood), int(p.stock.get("planks", 0)), p.road_carriers])
	return " ".join(parts)

## Road carriers mode (one carrier per stretch of road): goods still get through, loads wait at flags
## on busy roads, stock matches the stores, and a saved game goes on exactly the same.
## godot --headless --script res://tools/stretch_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("valley", 3, 6, true, 0, true, {"road_carriers": true})
	sim.players[0].ai = true
	var waits := 0
	var chains := 0
	var max_carriers := 0
	while sim.time < 12 * 60.0:
		sim.tick(Sim.TICK)
		if sim._ticks % 50 == 0:
			for t in sim.trips:
				if not t.legs.is_empty():
					chains += 1
					# a load that had to wait at a flag: some stretch started later than the one before ended
					for k in range(1, t.legs.size() / 4):
						if t.legs[k * 4 + 2] > t.legs[k * 4 - 1] + 0.01:
							waits += 1
							break
			for p in sim.players:
				max_carriers = maxi(max_carriers, p.road_carriers)
	var made := 0
	for p in sim.players:
		made += sim.blds.filter(func(b): return b.p == p.id).size()
	var ok_stock := sim.logistics.stock_matches() == ""
	print("chained loads seen %d, of them waiting at a flag %d, most stretch carriers %d, buildings %d, stock = stores: %s" % [chains, waits, max_carriers, made, "yes" if ok_stock else sim.logistics.stock_matches()])
	# save, load, and both go on the same
	var d = bytes_to_var(var_to_bytes(sim.to_save()))
	var sim2 := Sim.new()
	sim2.from_save(d)
	var same0 := _sig(sim) == _sig(sim2)
	while sim.time < 15 * 60.0:
		sim.tick(Sim.TICK)
		sim2.tick(Sim.TICK)
	var same1 := _sig(sim) == _sig(sim2)
	print("match after load: %s, after 3 more minutes: %s" % [same0, same1])
	if not same1:
		print(_sig(sim)); print(_sig(sim2))
	var growing := made > 60
	if chains > 0 and waits > 0 and ok_stock and same1 and growing:
		print("stretch test: ok")
	else:
		print("stretch test: FAILED")
	quit()
