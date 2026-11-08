extends SceneTree
## The same game with and without road carriers: how far each realm gets.
## godot --headless --script res://tools/carriers_compare.gd [-- seed=showcase mins=15]
func _init() -> void:
	GameData.ensure()
	var seed := "showcase"; var mins := 15
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="): seed = a.substr(5)
		if a.begins_with("mins="): mins = int(a.substr(5))
	for on in [false, true]:
		var sim := Sim.new()
		sim.new_game(seed, 3, 6, true, 0, true, {"road_carriers": on})
		sim.players[0].ai = true
		while sim.time < mins * 60.0: sim.tick(Sim.TICK)
		var parts := []
		for p in sim.players:
			parts.append("%s %d bld %d pop" % [p.name, sim.realm_blds(p).size(), sim.pop_total(p)])
		print("road carriers %s: %s" % ["on " if on else "off", ", ".join(parts)])
		sim.dispose()
	quit()
