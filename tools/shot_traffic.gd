extends SceneTree
## The traffic map on a town that grew for 12 minutes, with a jammed road clicked.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_traffic.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = false
	main._start("showcase", 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	main.log_ui.set_open(false)
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	var last := 0
	while sim.time < 12 * 60.0:
		sim.tick(Sim.TICK)
		if int(sim.time) != last:
			last = int(sim.time)
			if sim.time > 9 * 60.0: main.traffic_ui.update()
	me.ai = false
	main.paused = true
	main.traffic_ui.toggle()
	# the busiest road tile
	var best := -1
	for i in main.traffic_ui.busy.size():
		if sim.road[i] == 1 and (best < 0 or main.traffic_ui.busy[i] + main.traffic_ui.wait[i] > main.traffic_ui.busy[best] + main.traffic_ui.wait[best]): best = i
	print("busiest ", best, " busy ", main.traffic_ui.busy[best], " level ", main.traffic_ui.level(best))
	main.view.center_on(Vector2(best % sim.w, best / sim.w)); main.view.zoom = 22.0
	main.view.sel_tile = best
	main._refresh_all()
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "traffic.png")
	quit()
