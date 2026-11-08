extends SceneTree
## Ground details and day and night: xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_detail.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = false
	main._start("ridge", 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 8 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	main.paused = true
	main.log_ui.set_open(false)
	if sim.get_feature("fog") != null: sim.set_feature("fog", false)
	# a coast near the headquarters, with some mountain in view
	var best := Vector2(me.hq.x, me.hq.y)
	var bd := 1e9
	for i in sim.w * sim.h:
		if sim.ter[i] == Sim.WATER:
			var d := Vector2(i % sim.w - me.hq.x, i / sim.w - me.hq.y).length()
			if d < bd and d > 4: bd = d; best = Vector2(i % sim.w, i / sim.w)
	var c := (Vector2(me.hq.x, me.hq.y) * 2.0 + best) / 3.0
	main.view.center_on(c)
	main.view.zoom = 48.0
	var shots := [["detail_off", false, false, 0.0], ["detail_on", true, false, 0.0], ["night", true, true, 0.5], ["dusk", true, true, 0.3]]
	for s in shots:
		main.view.set_details(s[1])
		main.view.daynight = s[2]
		if s[2]:
			sim.time = (floorf(sim.time / main.view.DAY_LENGTH) + float(s[3])) * main.view.DAY_LENGTH
		main._refresh_all()
		for i in 40: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "%s.png" % s[0])
	main.view.zoom = 20.0
	sim.time = (floorf(sim.time / main.view.DAY_LENGTH) + 0.5) * main.view.DAY_LENGTH
	for i in 40: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "night_far.png")
	quit()
