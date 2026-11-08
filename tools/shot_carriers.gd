extends SceneTree
## Road carriers mode: loads waiting at flags on busy roads.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_carriers.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = false
	main._start("showcase", 3, 6, true, 0, true, {"road_carriers": true}); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 10 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	main.log_ui.set_open(false)
	# the busiest flag: where most of your loads are waiting now
	var count := {}
	for t in sim.trips:
		if t.p == 1 and not t.legs.is_empty():
			var lp: Vector3 = main.view._leg_pos(t)
			if lp.z < 0.0:
				count[int(lp.x)] = int(count.get(int(lp.x), 0)) + 1
	var best := sim.idx(me.hq.x, me.hq.y)
	var bn := 0
	for k in count:
		if int(count[k]) > bn: bn = count[k]; best = k
	print("loads waiting at flags: ", count.values().reduce(func(a, b): return a + b, 0), ", most at one flag ", bn, ", stretch carriers ", me.road_carriers)
	main.view.center_on(Vector2(best % sim.w, best / sim.w))
	main.view.zoom = 44.0
	main.paused = true
	main._refresh_all()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "road_carriers.png")
	quit()
