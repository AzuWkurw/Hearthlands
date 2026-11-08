extends SceneTree
## Goods kept in each store: godot --headless --script res://tools/stores_test.gd [-- mins=15]
func _init() -> void:
	GameData.ensure()
	var mins := 15
	for a in OS.get_cmdline_user_args():
		if a.begins_with("mins="): mins = int(a.substr(5))
	var sim := Sim.new()
	sim.new_game("valley", 3, 6, true)
	sim.players[0].ai = true
	var bad := ""
	var next := 60.0
	while sim.time < mins * 60.0:
		sim.tick(Sim.TICK)
		if sim.time >= next:
			next += 60.0
			var m: String = sim.logistics.stock_matches()
			if m != "" and bad == "": bad = "min %d: %s" % [int(sim.time / 60), m]
	for p in sim.players:
		var parts := []
		for s: Sim.Bld in sim.logistics.stores_of(p):
			var n := 0.0
			for k in s.inv: n += float(s.inv[k])
			parts.append("%s %d" % [s.ty, int(n)])
		var tot := 0.0
		for k in p.stock: tot += float(p.stock[k])
		print("%s: %d goods in %s" % [p.name, int(tot), ", ".join(parts)])
	print("stock = sum of stores all game: ", "yes" if bad == "" else "NO, " + bad)
	quit()
