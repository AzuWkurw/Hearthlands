extends SceneTree
## Late-game drawing benchmark: a big game with every realm (yours too) played by the computer until
## there are about 750 buildings, then frame times at three zooms, with the map drawing split into its
## parts, and the frames while placing a building and turning its entrance.
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/late_bench.gd -- [blds=750] [fresh]
## The late game is kept in user://saves/late_bench.save and reused (fresh makes a new one).

var main
var sim: Sim


func _frames(n: int) -> Array:
	# [average ms per frame, average map drawing ms, worst frame ms]
	var draw := 0
	var worst := 0
	var t0 := Time.get_ticks_usec()
	var last := t0
	for i in n:
		main.view.queue_redraw()
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		draw += main.view.draw_usec
	return [(Time.get_ticks_usec() - t0) / 1000.0 / n, draw / 1000.0 / n, worst / 1000.0]


func _init() -> void:
	var want := 750
	var fresh := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("blds="): want = int(a.substr(5))
		if a == "fresh": fresh = true
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	sim = main.sim
	var path := Main.SAVE_DIR + "/late_bench.save"
	if fresh or not FileAccess.file_exists(path):
		main._start("latebench", 4, 6, true, 2)
		main.setup.visible = false
		var me := sim.human()
		me.ai = true; me.skill = 6; me.pers = "balanced"; me.prod = 1.0; me.think = 3.0; me.max_b = 2
		var t0 := Time.get_ticks_msec()
		while sim.blds.size() < want and sim.time < 7200.0:
			for i in 100: sim.tick(Sim.TICK)
		me.ai = false
		print("made a late game: %d min, %d buildings, %d trips (%d s)" % [int(sim.time / 60.0), sim.blds.size(), sim.trips.size(), (Time.get_ticks_msec() - t0) / 1000])
		main._save_game("late_bench", true)
	else:
		main._load_game("late_bench")
	main.setup.visible = false
	main.paused = false
	var me2 := sim.human()
	print("late game: %d min, %d buildings (%d yours), %d trips, map %dx%d" % [int(sim.time / 60.0), sim.blds.size(), sim.realm_blds(me2).size(), sim.trips.size(), sim.w, sim.h])
	# the middle of your buildings
	var c := Vector2.ZERO
	for b: Sim.Bld in sim.realm_blds(me2):
		c += Vector2(b.x, b.y)
	c /= maxf(1.0, sim.realm_blds(me2).size())
	main.view.center_on(c)
	main.paused = true
	for z in [[8.0, "far"], [20.0, "mid"], [34.0, "near"]]:
		main.view.zoom = z[0]
		await _frames(10)
		main.view.prof = {}
		main.view.prof_on = true
		var r: Array = await _frames(60)
		main.view.prof_on = false
		var parts := []
		var keys: Array = main.view.prof.keys()
		keys.sort_custom(func(a, b): return int(main.view.prof[a]) > int(main.view.prof[b]))
		for k in keys:
			var ms := int(main.view.prof[k]) / 1000.0 / 60.0
			if ms >= 0.2:
				parts.append("%s %.1f" % [k, ms])
		print("zoom %-4s %5.1f ms/frame (%.0f fps), map drawing %.1f ms, worst %.1f ms | %s" % [z[1], r[0], 1000.0 / r[0], r[1], r[2], ", ".join(parts)])
	# an empty corner of the map: what the carriers' loop costs with none on screen
	main.view.center_on(Vector2(2, 2))
	main.view.zoom = 20.0
	await _frames(5)
	main.view.prof = {}
	main.view.prof_on = true
	var re: Array = await _frames(30)
	main.view.prof_on = false
	print("empty corner: map drawing %.1f ms, carriers loop %.2f ms" % [re[1], int(main.view.prof.get("carriers", 0)) / 1000.0 / 30.0])
	main.view.center_on(c)
	# placing a tower close up, turning its entrance once a second
	main.view.zoom = 34.0
	main.view.place_type = "tower"
	main.view.ghost = Vector2i(c.round())
	await _frames(10)
	var worst := 0.0
	var tot := 0.0
	main.view.prof = {}
	main.view.prof_max = {}
	main.view.prof_on = true
	for k in 6:
		main.view.door = [0, 1, 3][k % 3]
		var r2: Array = await _frames(10)
		worst = maxf(worst, r2[2])
		tot += r2[0]
	main.view.prof_on = false
	var mx := []
	for k2 in main.view.prof_max:
		if int(main.view.prof_max[k2]) >= 1000:
			mx.append("%s %.1f" % [k2, int(main.view.prof_max[k2]) / 1000.0])
	print("placing a tower, turning its entrance: %.1f ms/frame on average, worst frame %.1f ms | worst parts: %s" % [tot / 6.0, worst, ", ".join(mx)])
	main.view.place_type = ""
	quit()
