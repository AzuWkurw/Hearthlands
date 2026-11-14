extends SceneTree
## Screenshots for build 55: the isles map, a disaster that asks you to choose, a river boat.
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b55.gd -- out=/dir
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
	main._start("isles-shot", 4, 5, false, 160, false, {"features": Features.default_ids().filter(func(f): return f != "fog"), "gen": {"shape": "isles"}})
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	for i in 30: sim.tick(Sim.TICK)
	main.paused = true
	main.view.center_on(Vector2(sim.w * 0.5, sim.h * 0.5))
	main.view.zoom = 5.5
	main._refresh_all()
	await _shot(out + "b55_isles.png")
	# a river boat between two landings
	for y in range(maxi(0, me.hq.y - 30), mini(sim.h, me.hq.y + 31)):
		for x in range(maxi(0, me.hq.x - 30), mini(sim.w, me.hq.x + 31)):
			if sim.owner[sim.idx(x, y)] == 0:
				sim.owner[sim.idx(x, y)] = 1
	me.techs["timber_framing"] = true
	var spots := []
	for y in range(4, sim.h - 4, 2):
		for x in range(4, sim.w - 4, 2):
			if sim.owner[sim.idx(x, y)] == 1 and sim.can_place("river_landing", x, y, 1) == "":
				spots.append(Vector2i(x, y))
	var pair := []
	for a: Vector2i in spots:
		for b: Vector2i in spots:
			if pair.is_empty() and Vector2(a - b).length() > 10.0 and Vector2(a - b).length() < 16.0 and not sim.sea.water_path(a.x, a.y, b.x, b.y).is_empty():
				pair = [a, b]
	if not pair.is_empty():
		var la := sim.add_bld("river_landing", pair[0].x, pair[0].y, me, true)
		var lb := sim.add_bld("river_landing", pair[1].x, pair[1].y, me, true)
		for i in 12: sim.tick(Sim.TICK)
		sim.logistics.store_add(la, me, "planks", 20.0)
		var boat: Sim.Trip = null
		var t_end := sim.time + 60.0
		while sim.time < t_end and boat == null:
			sim.tick(Sim.TICK)
			for t in sim.trips:
				if t.kind == "boat": boat = t
		if boat != null:
			while sim.time < (boat.t0 + boat.t1) / 2.0:
				sim.tick(Sim.TICK)
			var pts := boat.path
			main.view.center_on(Vector2(pts[pts.size() / 2] % sim.w, pts[pts.size() / 2] / sim.w))
		main.view.zoom = 46.0
		main._refresh_all()
		await _shot(out + "b55_boat.png")
	# a disaster that asks you to choose
	var ev = sim.get_feature("events")
	me.peasant = 60
	ev.pending[me.id] = ["revolt", sim.time]
	main.view.center_on(Vector2(me.hq.x, me.hq.y))
	main.view.zoom = 30.0
	main.choice_ui.check()
	await _shot(out + "b55_revolt.png")
	quit()
