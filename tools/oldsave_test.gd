extends SceneTree
## A save from before build 31 (one shared stock) loads with its goods in the stores:
## run with "-- make=/path" in the old game folder, then "-- load=/path" in this one.
func _init() -> void:
	GameData.ensure()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("make="):
			var sim := Sim.new()
			sim.new_game("valley", 3, 6, true)
			sim.players[0].ai = true
			while sim.time < 6 * 60.0: sim.tick(Sim.TICK)
			var f := FileAccess.open(a.substr(5), FileAccess.WRITE)
			f.store_var(sim.to_save())
			print("saved: You have ", int(sim.players[0].stock.planks), " planks, ", sim.blds.size(), " buildings")
		if a.begins_with("load="):
			var f := FileAccess.open(a.substr(5), FileAccess.READ)
			var d: Dictionary = f.get_var()
			var sim := Sim.new()
			print("load: '", sim.from_save(d), "'")
			var p := sim.players[0]
			print("You: %d planks in stock, HQ holds %d planks; stock = stores: %s" % [int(p.stock.planks), int(p.hq.inv.get("planks", 0.0)), "yes" if sim.logistics.stock_matches() == "" else sim.logistics.stock_matches()])
			var working := 0
			for b in sim.blds:
				if b.worker == 2: working += 1
			print("workers kept at work: ", working)
			for i in 3 * 600: sim.tick(Sim.TICK)
			print("3 min later: %d buildings, stock = stores: %s" % [sim.blds.size(), "yes" if sim.logistics.stock_matches() == "" else sim.logistics.stock_matches()])
	quit()
