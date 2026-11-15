extends SceneTree
## Screenshots for build 60: a town quarter (tavern, chapel and market with homes round them), a home's
## info, and a rival's town after 40 minutes. xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b60.gd -- out=/dir
func _shot(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _spot(sim: Sim, ty: String, near: Vector2i, pid := 1) -> Vector2i:
	for r in range(1, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r: continue
				if sim.can_place(ty, near.x + dx, near.y + dy, pid, 0) == "":
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
	main._start("quarters", 2, 5, false, 128, false, {"features": Features.default_ids().filter(func(f): return f != "fog"), "start_goods": 4.0})
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	for y in range(maxi(0, me.hq.y - 22), mini(sim.h, me.hq.y + 23)):
		for x in range(maxi(0, me.hq.x - 22), mini(sim.w, me.hq.x + 23)):
			if sim.owner[sim.idx(x, y)] == 0: sim.owner[sim.idx(x, y)] = 1
	sim.net_dirty(1)
	var c := Vector2i(me.hq.x + 8, me.hq.y + 4)
	var ct = sim.get_feature("contentment")
	var home: Sim.Bld = null
	for ty in ["tavern", "chapel", "market", "house", "house", "house", "house", "house", "house"]:
		var at := _spot(sim, ty, c)
		if at.x >= 0 and sim.place(ty, at.x, at.y, me, 0, true) == "":
			var b := sim.bld_at(at.x, at.y)
			sim.production._finish_site(b, me)
			if ty == "tavern" or ty == "chapel": ct.served[b.id] = 1e9
			if ty == "house" and home == null: home = b
	for i in int(8.0 / Sim.TICK): sim.tick(Sim.TICK)
	main.paused = true
	main.view.center_on(Vector2(c))
	main.view.zoom = 30.0
	main.view.sel_id = home.id
	main._refresh_sel()
	main._refresh_all()
	await _shot(out + "b60_quarter.png")
	# a rival's town after a while
	main.view.sel_id = 0
	main._refresh_sel()
	var q := sim.players[1]
	for i in int(40.0 * 60.0 / Sim.TICK): sim.tick(Sim.TICK)
	var cq: Vector2 = sim.ai._town_centre(q)
	print("rival centre %s, taverns %d, markets %d, landings %d, quarter %d%%" % [cq, sim.realm_blds(q).filter(func(b): return b.ty == "tavern").size(), sim.realm_blds(q).filter(func(b): return b.ty == "market").size(), sim.realm_blds(q).filter(func(b): return b.ty == "river_landing").size(), roundi(ct.quarter_share(q) * 100)])
	var fog = sim.get_feature("fog")
	main.view.center_on(cq if cq.x >= 0 else Vector2(q.hq.x, q.hq.y))
	main.view.zoom = 22.0
	main._refresh_all()
	await _shot(out + "b60_rival_town.png")
	quit()
