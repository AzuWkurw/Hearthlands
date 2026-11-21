extends SceneTree
## Simulation cost late in a big game: loads a saved game (by default the one testbench.gd keeps with
## save=user://bench120.save), plays it on for a while and prints the time per game second in each part,
## the slowest moments, and a state checksum every 30 game seconds. Two versions that should play the
## same must print the same checksums; the times show which is faster.
##   godot --headless --script res://tools/late_profile.gd -- [save=user://bench120.save] [secs=120]
##   (make the save first: testbench.gd -- mins=120 save=user://bench120.save)
func _init() -> void:
	GameData.ensure()
	var path := "user://bench120.save"
	var secs := 120.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("save="): path = a.substr(5)
		if a.begins_with("secs="): secs = float(a.substr(5))
	if not FileAccess.file_exists(path):
		print("LATE PROFILE: no save at ", path)
		quit()
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var d = f.get_var()
	f.close()
	var sim := Sim.new()
	var why := sim.from_save(d)
	if why != "":
		print("LATE PROFILE: ", why)
		quit()
		return
	print("LATE PROFILE: %s, minute %d, %d realms, %d buildings, %d trips" % [path, int(sim.time / 60.0), sim.players.size(), sim.blds.size(), sim.trips.size()])
	sim.perf = {}
	var start := sim.time
	var next := start + 30.0
	var t_real := Time.get_ticks_usec()
	var worst := 0.0
	var slow := 0
	var ticks: Array[float] = []
	var sim_ms := 0.0
	while sim.time < start + secs - 0.05:
		var tk := Time.get_ticks_usec()
		sim.tick(Sim.TICK)
		var ms := (Time.get_ticks_usec() - tk) / 1000.0
		ticks.append(ms)
		sim_ms += ms
		worst = maxf(worst, ms)
		if ms > 50.0:
			slow += 1
		if sim.time >= next - 0.05:
			print("  t=%d checksum %d" % [roundi(sim.time), sim.checksum()])
			next += 30.0
	var real_ms := (Time.get_ticks_usec() - t_real) / 1000.0
	var played := sim.time - start
	var keys := sim.perf.keys()
	keys.sort_custom(func(x, y): return int(sim.perf[x]) > int(sim.perf[y]))
	var parts := []
	for k in keys.slice(0, 14):
		parts.append("%s %.1f" % [k, float(sim.perf[k]) / played / 1000.0])
	ticks.sort()
	print("parts (ms per game second): ", ", ".join(parts))
	print("worst moment %.0f ms, %d moments over 50 ms, 99th percentile %.1f ms" % [worst, slow, ticks[int(ticks.size() * 0.99)]])
	print("LATE PROFILE: %.1f ms per game second, %.1fx real time at most (%.0f s in all with the checksums)" % [sim_ms / played, played * 1000.0 / sim_ms, real_ms / 1000.0])
	quit()
