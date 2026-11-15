extends SceneTree
## Missions and hand-made maps: every mission in data/missions.json starts, its goals are counted,
## a mission is won when its goals are met and lost at its deadline, and a game on a hand-made map
## saves and loads the same. godot --headless --script res://tools/mission_test.gd
var won := -1

func _init() -> void:
	GameData.ensure()
	var ok := true
	for ms in UiMissions.missions():
		var sim := Sim.new()
		var started := false
		if ms.has("map"):
			var m := WorldGen.load_map(String(ms.map))
			started = not m.is_empty() and sim.new_game(String(m.seed), int(ms.foes), int(ms.strength), true, 0, false, ms.get("opts", {}), m, ms)
		else:
			started = sim.new_game(String(ms.seed), int(ms.foes), int(ms.strength), true, int(ms.get("size", 0)), false, ms.get("opts", {}), {}, ms)
		var prog := []
		if started:
			sim.players[0].ai = true
			while sim.time < 180.0: sim.tick(Sim.TICK)
			for g in ms.goals:
				prog.append("%s %s" % [String(g.text), str(sim.goal_progress(g))])
		print("%s: started %s, %d realms, map %dx%d; %s" % [ms.name, started, sim.players.size(), sim.w, sim.h, "; ".join(prog)])
		ok = ok and started
		sim.dispose()
	# winning and losing
	var sim2 := Sim.new()
	sim2.ended.connect(func(w): won = 1 if w else 0)
	sim2.new_game("quick win", 1, 3, false, 0, false, {}, {}, {"name": "test", "goals": [{"kind": "pop", "n": 5, "text": "Have 5 people"}]})
	while sim2.time < 5.0: sim2.tick(Sim.TICK)
	print("easy mission won: ", won == 1, " (over ", sim2.over, ")")
	ok = ok and won == 1
	won = -1
	var sim3 := Sim.new()
	sim3.ended.connect(func(w): won = 1 if w else 0)
	sim3.new_game("quick loss", 1, 3, false, 0, false, {}, {}, {"name": "test", "minutes": 1, "goals": [{"kind": "pop", "n": 5000, "text": "Have 5000 people"}]})
	while sim3.time < 65.0: sim3.tick(Sim.TICK)
	print("impossible mission lost at its deadline: ", won == 0)
	ok = ok and won == 0
	# a hand-made map game saves and loads the same
	var m2 := WorldGen.load_map("res://data/map_iron_coast.json")
	var a := Sim.new()
	a.new_game(String(m2.seed), 2, 5, true, 0, false, {}, m2, {"name": "x", "goals": [{"kind": "pop", "n": 999, "text": "x"}]})
	a.players[0].ai = true
	a._recompute_mods(a.players[0])     # (a rival picks its age's path at once, as on loading)
	while a.time < 240.0: a.tick(Sim.TICK)
	var b := Sim.new()
	b.from_save(bytes_to_var(var_to_bytes(a.to_save())))
	while a.time < 360.0:
		a.tick(Sim.TICK); b.tick(Sim.TICK)
	var same := a.checksum() == b.checksum()
	print("hand-made map game matches after load: ", same, ", mission kept: ", String(b.mission.get("name", "")) == "x")
	ok = ok and same
	print("mission test: ", "ok" if ok else "FAILED")
	quit()
