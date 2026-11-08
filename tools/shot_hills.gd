extends SceneTree
## Screenshot of hilly land with roads (slope marks): xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_hills.gd -- out=/dir
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
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.odds = 99.0; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 20 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	main.paused = true
	# the spot with the most steep road around it
	var best := Vector2i(me.hq.x, me.hq.y); var bs := -1
	for y in range(4, sim.h - 4, 2):
		for x in range(4, sim.w - 4, 2):
			var s := 0
			for dy in range(-5, 6):
				for dx in range(-7, 8):
					var i := (y + dy) * sim.w + x + dx
					if i >= 0 and i < sim.road.size() and sim.road[i] == 1:
						s += sim.road_slope(i, 1)
			if s > bs: bs = s; best = Vector2i(x, y)
	main.view.center_on(Vector2(best.x, best.y)); main.view.zoom = 40.0
	main._refresh_all()
	for i in 40: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "hills.png")
	print("spot ", best, " score ", bs)
	quit()
