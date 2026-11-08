extends SceneTree
## Where rival realms run out of room: godot --headless --script res://tools/ai_space_test.gd [-- seed=perf mins=20]
func _init() -> void:
	GameData.ensure()
	var seed := "perf"
	var mins := 20
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="): seed = a.substr(5)
		if a.begins_with("mins="): mins = int(a.substr(5))
	var sim := Sim.new()
	sim.new_game(seed, 7, 7, true)
	sim.players[0].ai = true
	var next := 5
	while sim.time < mins * 60.0:
		sim.tick(Sim.TICK)
		if sim.time >= next * 60.0:
			var land := 0; var c := {"small": 0, "medium": 0, "large": 0}
			var mil := 0; var unocc := 0
			for p in sim.players:
				for i in sim.owned(p.id)[0]:
					land += 1
					var s := sim.site_size(i % sim.w, i / sim.w, p.id)
					if c.has(s): c[s] += 1
			for b in sim.blds:
				if b.def.has("garrison"):
					mil += 1
					if b.garrison == 0: unocc += 1
			var reserve := 0
			for p in sim.players: reserve += p.reserve
			print("min %d: buildings %d, land %d, free spots large %d medium %d small %d, military %d (%d empty), soldiers in reserve %d" % [next, sim.blds.size(), land, c.large, c.medium, c.small, mil, unocc, reserve])
			next += 5
	var why := {}
	for p in sim.players:
		for i in sim.owned(p.id)[0]:
			if sim.site_size(i % sim.w, i / sim.w, p.id) == "medium":
				var r := String(sim.plot_check("large", i % sim.w, i / sim.w, p.id)).get_slice(":", 0).get_slice(" (", 0)
				if r.begins_with("Too close"): r = "Too close to a building"
				if r.begins_with("Keep the entrance"): r = "Keep an entrance free"
				if r == "": r = "(entrance)"
				why[r] = int(why.get(r, 0)) + 1
	print("medium spots that cannot take a large building, because: ", why)
	var keys := sim.ai.stats.keys()
	keys.sort_custom(func(a, b): return int(sim.ai.stats[a]) > int(sim.ai.stats[b]))
	print("no spot found: ", ", ".join(keys.slice(0, 16).map(func(k): return "%s %d" % [k, sim.ai.stats[k]])))
	quit()
