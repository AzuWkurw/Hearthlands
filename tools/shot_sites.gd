extends SceneTree
## The Sites button showing building places: xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_sites.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("showcase", 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 8 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	main.paused = true
	main.log_ui.set_open(false)
	main.view.center_on(Vector2(me.hq.x + 1.0, me.hq.y + 1.0))
	main.view.zoom = 34.0
	var ev := InputEventKey.new(); ev.keycode = KEY_B; ev.pressed = true
	main._unhandled_input(ev)
	main._refresh_all()
	for i in 10: await process_frame
	print("sites on ", main.toolbar.sites_on, " markers ", main.view._sites.size())
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "sites.png")
	quit()
