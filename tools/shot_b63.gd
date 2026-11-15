extends SceneTree
## Screenshots for build 63: people in their age's hats, and the sandbox goals box.
## xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b63.gd -- out=/dir
func _shot(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 3: await process_frame
	var was_guide: bool = main.settings.guide
	main.settings.guide = false
	main._start("hats", 1, 5, false, 128, false, {"features": Features.default_ids().filter(func(f): return f != "fog"), "start_goods": 4.0})
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true
	for i in int(420.0 / Sim.TICK): sim.tick(Sim.TICK)
	me.ai = false
	me.peasant = 40
	for i in int(6.0 / Sim.TICK): sim.tick(Sim.TICK)
	main.paused = true
	for age in [1, 4, 5]:
		me.age = age
		for a in range(1, 7): me.age_bonus[str(a)] = "x"
		if main.age_ui.panel != null: main.age_ui.panel.visible = false
		for i in 2: sim.tick(Sim.TICK)
		await process_frame
		main.view.center_on(Vector2(me.hq.x, me.hq.y + 2))
		main.view.zoom = 64.0
		main._refresh_all()
		main.guide_ui.refresh()
		if main.age_ui.panel != null: main.age_ui.panel.visible = false
		main.paused = true
		await _shot(out + "b63_hats_age%d.png" % age)
	main.view.zoom = 30.0
	if main.log_ui.win != null and main.log_ui.win.visible: main.log_ui.toggle()
	main._refresh_all()
	await _shot(out + "b63_goals.png")
	main.settings.guide = was_guide
	quit()
