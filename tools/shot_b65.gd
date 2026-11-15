extends SceneTree
## Screenshots for build 65, the Bronze Age: a Bronze Age village (mud brick and thatch, a tin mine, a
## bronze foundry and smiths), bronze warriors, the foundry's info and the Bronze Age research.
## xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b65.gd -- out=/dir
func _shot(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _spot(sim: Sim, ty: String, near: Vector2i, r0 := 0) -> Vector2i:
	for r in range(r0, 16):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r: continue
				if sim.can_place(ty, near.x + dx, near.y + dy, 1, 0) == "":
					return Vector2i(near.x + dx, near.y + dy)
	return Vector2i(-1, -1)


func _put(main, sim: Sim, me, ty: String, near: Vector2i) -> Sim.Bld:
	var at := _spot(sim, ty, near)
	if at.x < 0:
		print("no spot for ", ty)
		return null
	var b := sim.add_bld(ty, at.x, at.y, me, true, 0)
	sim.build_road(b.x, b.y, me.hq.x, me.hq.y, 1)
	return b


func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 3: await process_frame
	var feats: Array = Features.default_ids().filter(func(f): return f != "seasons" and f != "fog")
	main._start("bronzeshow", 2, 5, false, 0, false, {"features": feats})
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	for i in 10: sim.tick(Sim.TICK)
	# a Bronze Age village round the headquarters
	var hq := Vector2i(me.hq.x, me.hq.y)
	var tin := Vector2i(-1, -1)
	var cop := Vector2i(-1, -1)
	for y in range(hq.y - 18, hq.y + 19):
		for x in range(hq.x - 18, hq.x + 19):
			if not sim.inb(x, y) or sim.owner[sim.idx(x, y)] != 1: continue
			if tin.x < 0 and sim.ore[sim.idx(x, y)] == 8 and sim.can_place("tin_mine", x, y, 1, 0) == "": tin = Vector2i(x, y)
			if cop.x < 0 and sim.ore[sim.idx(x, y)] == 5 and sim.can_place("copper_mine", x, y, 1, 0) == "": cop = Vector2i(x, y)
	if tin.x >= 0: sim.add_bld("tin_mine", tin.x, tin.y, me, true, 0)
	if cop.x >= 0: sim.add_bld("copper_mine", cop.x, cop.y, me, true, 0)
	var fd := _put(main, sim, me, "bronze_foundry", hq + Vector2i(4, 3))
	_put(main, sim, me, "bronze_smith", hq + Vector2i(-4, 3))
	_put(main, sim, me, "bronze_weaponsmith", hq + Vector2i(1, 5))
	_put(main, sim, me, "charcoal_burner", hq + Vector2i(6, -2))
	for k in 4:
		_put(main, sim, me, "house", hq + Vector2i(-5 + k * 3, -4))
	_put(main, sim, me, "farm", hq + Vector2i(-10, 2))
	_put(main, sim, me, "scriptorium", hq + Vector2i(-2, 7))
	_put(main, sim, me, "barracks", hq + Vector2i(5, 7))
	_put(main, sim, me, "well", hq + Vector2i(3, -6))
	_put(main, sim, me, "hut", hq + Vector2i(9, 4))
	_put(main, sim, me, "hut", hq + Vector2i(-9, 5))
	sim.give(me, "ore_copper", 10.0); sim.give(me, "ore_tin", 5.0); sim.give(me, "charcoal", 10.0)
	me.artisan += 4
	main.paused = false
	for i in int(25.0 / Sim.TICK): sim.tick(Sim.TICK)
	main.paused = true
	if main.log_ui.win != null and main.log_ui.win.visible: main.log_ui.toggle()
	var view: MapView = main.view
	view.center_on(Vector2(hq.x + 0.5, hq.y + 1.5))
	view.zoom = 54.0
	main._refresh_all()
	await _shot(out + "b65_village.png")
	# bronze warriors: a column of them beside the village
	var col := Sim.Attack.new()
	col.p = 1; col.n = 6; col.amix = [6, 0, 0, 0, 0, 0, 0]; col.era = 0.0
	col.t0 = sim.time; col.t1 = sim.time + 400.0
	var land := Vector2i(hq.x, hq.y + 3)
	for r in range(2, 12):
		var c2 := Vector2i(hq.x - r, hq.y + 3)
		if sim.inb(c2.x, c2.y) and sim.ter[sim.idx(c2.x, c2.y)] == Sim.GRASS and sim.bmap[sim.idx(c2.x, c2.y)] == 0:
			land = c2
			break
	col.from = Vector2(land.x, land.y); col.to = Vector2(land.x - 60, land.y)
	sim.attacks.append(col)
	view.center_on(Vector2(land.x - 0.5, land.y - 0.5))
	view.zoom = 110.0
	main._refresh_all()
	await _shot(out + "b65_warriors.png")
	sim.attacks.erase(col)
	# the foundry's info
	if fd != null:
		view.center_on(Vector2(fd.x, fd.y))
		view.zoom = 48.0
		view.sel_id = fd.id
		main._refresh_sel()
		main._refresh_all()
		await _shot(out + "b65_foundry.png")
	# the research window on the Bronze Age
	view.sel_id = -1
	main._refresh_sel()
	sim.set_research(me, "herding")
	main._open_tech()
	for i in 4: await process_frame
	main.research_ui.tree.set_zoom(0.62)
	main.research_ui._select("iron_working", true)
	for i in 4: await process_frame
	main.research_ui.tree.center_on("iron_working")
	await _shot(out + "b65_research.png")
	quit()
