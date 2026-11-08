extends SceneTree
## Building spots no road can reach are refused: every spot that passes can_place finds a road route.
## godot --headless --script res://tools/reach_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("perf", 7, 6, true)
	sim.players[0].ai = true
	while sim.time < 15 * 60.0: sim.tick(Sim.TICK)
	var ok := 0; var bad := 0; var closed := 0
	for p in sim.players:
		for i in sim.owned(p.id)[0]:
			var x: int = i % sim.w; var y: int = i / sim.w
			var why := sim.can_place("house", x, y, p.id)
			if why.begins_with("No road can get"): closed += 1
			if why != "": continue
			var own := sim.plot_tiles("house", x, y)
			for t in own:
				if t != i: sim.plot[t] = -1
			var path: PackedInt32Array = sim._path_to_net(x, y, p.id, -1, [0, 1, 3])
			for t in own:
				if sim.plot[t] == -1: sim.plot[t] = 0
			if path.size() > 0: ok += 1
			else: bad += 1
	print("house spots: %d placeable, %d of them without a road route; %d refused as closed in" % [ok + bad, bad, closed])
	print("reach test: %d ok, %d bad" % [ok, bad])
	quit()
