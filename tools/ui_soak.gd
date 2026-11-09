extends SceneTree
## The interface through a long game: every few game seconds a frame is drawn with something else on
## (traffic map, minimap filters, a followed carrier, fires, an info box, the windows), to catch errors
## in drawing and windows. xvfb-run -a godot --rendering-driver opengl3 --script res://tools/ui_soak.gd -- mins=25
func _init() -> void:
	var mins := 25
	for a in OS.get_cmdline_user_args():
		if a.begins_with("mins="): mins = int(a.substr(5))
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = false
	main._start("ridge", 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 6; me.pers = "balanced"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9
	main.paused = true
	var step := 0
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	while sim.time < mins * 60.0 and not sim.over:
		for i in 100: sim.tick(Sim.TICK)
		main.traffic_ui.update()
		step += 1
		match step % 9:
			0: main.traffic_ui.toggle()
			1: main.minimap.set_filter(["", "roads", "land", "good:planks", "good:bread"][rng.randi() % 5])
			2:
				if sim.trips.size() > 0: main.view.follow = sim.trips[rng.randi() % sim.trips.size()]
			3:
				var mine := sim.realm_blds(me)
				if mine.size() > 0:
					var b: Sim.Bld = mine[rng.randi() % mine.size()]
					main.view.sel_id = b.id
					main.view.center_on(Vector2(b.x, b.y))
			4:
				var f = sim.get_feature("fires")
				var mine2 := sim.realm_blds(me)
				if f != null and mine2.size() > 0: f.ignite(mine2[rng.randi() % mine2.size()])
			5: main._open_diplomacy()
			6: main.dip_panel.visible = false
			7: main.problems_ui.toggle()
			8:
				main.view.zoom = [8.0, 14.0, 24.0, 40.0][rng.randi() % 4]
				main._jump_idle()
		main._refresh_all()
		await process_frame
		await process_frame
	main.campaign_ui.show()
	await process_frame
	main.campaign_ui.win.visible = false
	main._show_achievements()
	await process_frame
	print("ui soak done at minute %d" % int(sim.time / 60.0))
	quit()
