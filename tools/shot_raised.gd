extends SceneTree
## Raised ground (2.5D) on and off, same view: xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_raised.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	var seed := "ridge"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
		if a.begins_with("seed="): seed = a.substr(5)
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = false
	main._start(seed, 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 10 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	main.paused = true
	main.log_ui.set_open(false)
	# look toward the mountains nearest the headquarters
	var best := Vector2(me.hq.x, me.hq.y)
	var bd := 1e9
	for i in sim.w * sim.h:
		if sim.ter[i] == 3:
			var d := Vector2(i % sim.w - me.hq.x, i / sim.w - me.hq.y).length()
			if d < bd: bd = d; best = Vector2(i % sim.w, i / sim.w)
	var c := (Vector2(me.hq.x, me.hq.y) + best) / 2.0
	for z in [28.0, 12.0]:
		main.view.center_on(c)
		main.view.zoom = z
		for on in [true, false]:
			main.view.raised = on
			main._refresh_all()
			for i in 20: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out + "raised_%s_z%d.png" % ["on" if on else "off", int(z)])
	# picking: the tile under the screen centre with raised ground
	main.view.raised = true
	main.view.zoom = 28.0
	for i in 3: await process_frame
	print("centre tile flat ", Vector2i(floori(c.x), floori(c.y)), " raised pick ", main.view.screen_to_tile(main.view.size / 2.0), " lift there ", main.view.lift_at(c.x, c.y))
	quit()
