extends SceneTree
## Screenshots for build 62: the build queue's numbers over its sites, a guild in a sawmill's info.
## xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b62.gd -- out=/dir
func _shot(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _spot(sim: Sim, ty: String, near: Vector2i) -> Vector2i:
	for r in range(1, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r: continue
				if sim.can_place(ty, near.x + dx, near.y + dy, 1, 0) == "":
					return Vector2i(near.x + dx, near.y + dy)
	return Vector2i(-1, -1)


func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 3: await process_frame
	main._start("guilds", 2, 5, false, 128, false, {"features": Features.default_ids().filter(func(f): return f != "fog"), "start_goods": 4.0})
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.techs["guilds"] = true
	for y in range(maxi(0, me.hq.y - 22), mini(sim.h, me.hq.y + 23)):
		for x in range(maxi(0, me.hq.x - 22), mini(sim.w, me.hq.x + 23)):
			if sim.owner[sim.idx(x, y)] == 0: sim.owner[sim.idx(x, y)] = 1
	sim.net_dirty(1)
	var near := Vector2i(me.hq.x + 5, me.hq.y + 2)
	var mills := []
	for k in 4:
		var at := _spot(sim, "sawmill", near)
		if at.x >= 0 and sim.place("sawmill", at.x, at.y, me, 0, true) == "":
			var b := sim.bld_at(at.x, at.y)
			sim.production._finish_site(b, me)
			mills.append(b)
			near = at
	near = Vector2i(me.hq.x - 6, me.hq.y + 3)
	var sites := []
	for ty in ["house", "house", "well", "bakery"]:
		var at2 := _spot(sim, ty, near)
		if at2.x >= 0 and sim.place(ty, at2.x, at2.y, me, 0, true) == "":
			sites.append(sim.bld_at(at2.x, at2.y))
			near = at2
	for k in [2, 0, 3]:
		if k < sites.size(): sim.queue_site(sites[k], true)
	for i in int(20.0 / Sim.TICK): sim.tick(Sim.TICK)
	main.paused = true
	main.view.center_on(Vector2(me.hq.x, me.hq.y + 3))
	main.view.zoom = 30.0
	main.view.sel_id = sites[3].id
	main._refresh_sel()
	main._refresh_all()
	await _shot(out + "b62_queue.png")
	main.view.sel_id = mills[0].id
	main._refresh_sel()
	await _shot(out + "b62_guild.png")
	quit()
