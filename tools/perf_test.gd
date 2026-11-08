extends SceneTree
## Simulation cost in a big game: godot --headless --script res://tools/perf_test.gd [-- foes=7 mins=60]
## Prints, every 10 game minutes, the time per game second spent in each part of the simulation.
func _init() -> void:
	GameData.ensure()
	var foes := 7
	var mins := 60
	var seed := "perf"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="): seed = a.substr(5)
		if a.begins_with("foes="): foes = int(a.substr(5))
		if a.begins_with("mins="): mins = int(a.substr(5))
	var sim := Sim.new()
	sim.new_game(seed, foes, 7, true)
	sim.players[0].ai = true
	var next := 10
	var t_real := Time.get_ticks_usec()
	var ticks := 0
	sim.perf = {}
	while sim.time < mins * 60.0:
		sim.tick(Sim.TICK)
		ticks += 1
		if sim.time >= next * 60.0:
			var total := Time.get_ticks_usec() - t_real
			var secs := ticks * Sim.TICK
			var parts := []
			var keys := sim.perf.keys()
			keys.sort_custom(func(x, y): return int(sim.perf[x]) > int(sim.perf[y]))
			for k in keys.slice(0, 8):
				parts.append("%s %.1f" % [k, float(sim.perf[k]) / secs / 1000.0])
			var pop := 0
			for q in sim.players: pop += sim.pop_total(q)
			print("min %d: %d buildings, %d people, %d carriers, %.1f ms per game second (%s)" % [next, sim.blds.size(), pop, sim.trips.size(), total / secs / 1000.0, ", ".join(parts)])
			sim.perf = {}
			t_real = Time.get_ticks_usec()
			ticks = 0
			next += 10
	sim.dispose()
	quit()
