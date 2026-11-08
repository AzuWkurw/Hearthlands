extends SceneTree
## Performance benchmark. Simulation only:  godot --headless --script res://tools/bench.gd
## With drawing (needs a display):         godot --script res://tools/bench.gd -- draw
## Plays a heavy game (200-tile map, 8 rivals, every realm run by the AI) and prints timings.

func _init() -> void:
	var draw := "draw" in OS.get_cmdline_user_args()
	var main = null
	var sim: Sim
	if draw:
		root.size = Vector2i(1600, 900)
		main = load("res://main.tscn").instantiate()
		root.add_child(main)
		for i in 3: await process_frame
		main._start("bench", 8, 8, false, 200, false)
		main.setup.visible = false
		sim = main.sim
	else:
		sim = Sim.new()
		sim.new_game("bench", 8, 8, false, 200, false)
	var me: Sim.Player = sim.players[0]
	me.ai = true; me.skill = 8; me.pers = "builder"; me.prod = 1.4; me.think = 3.0; me.max_b = 3; me.odds = 99.0; me.grace = 1e9; me.attack_t = 1e9
	var windows := [10, 20, 30]
	if draw:
		windows = [12]
	for m in windows:
		sim.perf.clear()
		var t0 := Time.get_ticks_usec()
		while sim.time < m * 60.0:
			sim.tick(Sim.TICK)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if "nets" in OS.get_cmdline_user_args(): print("network rebuilds so far: ", sim._net_builds)
		print("sim minutes %d-%d: %.0f ms total, %.1f ms per game second (%d buildings, %d carriers)" % [m - 10, m, ms, ms / 600.0, sim.blds.size(), sim.trips.size()])
		var keys := sim.perf.keys()
		keys.sort_custom(func(a, b): return sim.perf[a] > sim.perf[b])
		print("   ", ", ".join(keys.map(func(k): return "%s %.1f" % [k, sim.perf[k] / 600000.0])), "  (ms per game second)")
	if not draw:
		quit()
		return
	me.ai = false
	var hq := me.hq
	for case in [["close, still", 32.0, Vector2.ZERO], ["close, panning", 32.0, Vector2(0.4, 0.15)], ["far, still", 9.0, Vector2.ZERO], ["far, panning", 9.0, Vector2(1.2, 0.5)], ["whole map", 4.5, Vector2.ZERO]]:
		main.view.zoom = case[1]
		main.view.center_on(Vector2(hq.x, hq.y))
		for i in 10: await process_frame
		var t0 := Time.get_ticks_usec()
		var n := 60
		var draw_us := 0
		for i in n:
			main.view.pan(case[2])
			await process_frame
			draw_us += main.view.draw_usec + main.view.ground_usec
		var per := (Time.get_ticks_usec() - t0) / 1000.0 / n
		print("frame %-15s %.1f ms (%.0f fps), of which the map's drawing code %.1f ms" % [case[0], per, 1000.0 / per, draw_us / 1000.0 / n])
	# the game running at 8x while you watch: borders move, chunks may need baking again
	main.view.zoom = 32.0
	main.view.center_on(Vector2(hq.x, hq.y))
	for i in 10: await process_frame
	var frames := 300
	var worst := 0
	var draw_total := 0
	var t1 := Time.get_ticks_usec()
	var tv := sim.territory_version
	for i in frames:
		var f0 := Time.get_ticks_usec()
		for k in 2:
			sim.tick(Sim.TICK)
		main._process(0.0)
		await process_frame
		draw_total += main.view.draw_usec + main.view.ground_usec
		worst = maxi(worst, Time.get_ticks_usec() - f0)
	var avg := (Time.get_ticks_usec() - t1) / 1000.0 / frames
	print("frame %-15s %.1f ms average, worst %.1f ms, map's drawing code %.1f ms; borders moved %d times" % ["game at 8x", avg, worst / 1000.0, draw_total / 1000.0 / frames, sim.territory_version - tv])
	quit()
