extends SceneTree
## Simulation profile from a fixed late game: the bench game (200 tiles, 9 realms all played by the
## computer) at minute `at` is made once and kept in user://saves/prof_<at>.save; each run loads it,
## plays `mins` more game minutes and prints where the time went (sim.perf), with a checksum so a
## faster version can be checked to play the same game:
##   godot --headless --script res://tools/sim_prof.gd -- [at=20] [mins=2] [fresh]

func _init() -> void:
	var at := 20
	var mins := 2.0
	var fresh := false
	var size := 200
	for a in OS.get_cmdline_user_args():
		if a.begins_with("at="): at = int(a.substr(3))
		if a.begins_with("mins="): mins = float(a.substr(5))
		if a == "fresh": fresh = true
		if a.begins_with("size="): size = int(a.substr(5))
	var path := ("user://saves/prof_%d.save" % at) if size == 200 else ("user://saves/prof_%d_%d.save" % [at, size])
	var sim := Sim.new()
	if fresh or not FileAccess.file_exists(path):
		sim.new_game("bench", 8, 8, false, size, false)
		var me: Sim.Player = sim.players[0]
		me.ai = true; me.skill = 8; me.pers = "builder"; me.prod = 1.4; me.think = 3.0; me.max_b = 3; me.odds = 99.0; me.grace = 1e9; me.attack_t = 1e9
		while sim.time < at * 60.0:
			sim.tick(Sim.TICK)
		DirAccess.make_dir_recursive_absolute("user://saves")
		var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
		f.store_var(sim.to_save())
		f.close()
		print("made ", path)
	var g := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var data = g.get_var()
	g.close()
	sim = Sim.new()
	var err := sim.from_save(data)
	if err != "":
		print("load: ", err)
	sim.perf.clear()
	var t0 := Time.get_ticks_usec()
	var end := sim.time + mins * 60.0
	while sim.time < end:
		sim.tick(Sim.TICK)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var secs := mins * 60.0
	print("from minute %d, %.0f game seconds: %.1f ms per game second (%d buildings, %d trips)" % [at, secs, ms / secs, sim.blds.size(), sim.trips.size()])
	var keys := sim.perf.keys()
	keys.sort_custom(func(a, b): return sim.perf[a] > sim.perf[b])
	for k in keys:
		print("   %-24s %6.2f ms/s" % [k, sim.perf[k] / 1000.0 / secs])
	print("checksum ", sim.checksum())
	quit()
