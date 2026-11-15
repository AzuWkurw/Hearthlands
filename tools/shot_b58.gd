extends SceneTree
## Screenshots for build 58: copying an area into a blueprint, the Blueprints window with categories,
## placing a blueprint (trees in the way crossed), and the question before clearing them.
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b58.gd -- out=/dir
func _shot(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _spot(sim: Sim, ty: String, near: Vector2i) -> Vector2i:
	for r in range(2, 30):
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
	main._start("blueprints", 2, 5, false, 128, false, {"features": Features.default_ids().filter(func(f): return f != "fog"), "start_goods": 4.0})
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	# a file of its own, so the player's blueprints are left alone
	var path := "user://bp_shot.json"
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	main.blueprints_ui.bps = Blueprints.new(path)
	for i in 20: sim.tick(Sim.TICK)
	for y in range(maxi(0, me.hq.y - 22), mini(sim.h, me.hq.y + 23)):
		for x in range(maxi(0, me.hq.x - 22), mini(sim.w, me.hq.x + 23)):
			if sim.owner[sim.idx(x, y)] == 0: sim.owner[sim.idx(x, y)] = 1
	sim.net_dirty(1)
	# a bread corner: farm, mill, bakery, well and a house, with their roads
	var near := Vector2i(me.hq.x + 3, me.hq.y + 3)
	var placed := []
	for ty in ["farm", "mill", "bakery", "well", "house"]:
		var sp := _spot(sim, ty, near)
		if sp.x >= 0 and sim.place(ty, sp.x, sp.y, me, 0, true) == "":
			placed.append(sim.bld_at(sp.x, sp.y))
			near = sp
	for b in placed:
		sim.production._finish_site(b, me)
	for i in 30: sim.tick(Sim.TICK)
	var r := Rect2i(Vector2i(placed[0].x, placed[0].y), Vector2i.ZERO)
	for b in placed:
		r = r.expand(Vector2i(b.x, b.y))
	r = r.grow(1)
	var view: MapView = main.view
	view.center_on(Vector2(r.get_center()))
	view.zoom = 30.0
	main.paused = true
	# 1. the copy tool: the area marked
	main.blueprints_ui.start_copy()
	view.bp_corner = r.position
	view.ghost = r.end
	main._refresh_all()
	await _shot(out + "b58_copy.png")
	# 2. named and saved, plus a few more in other categories
	main.blueprints_ui.copy_click(r.end)
	main.blueprints_ui.save_name.text = "Bread corner"
	await _shot(out + "b58_save.png")
	main.blueprints_ui._save_pending()
	var bp: Dictionary = main.blueprints_ui.bps.list[0]
	var bps: Blueprints = main.blueprints_ui.bps
	var b2 := bp.duplicate(true); b2.name = "Second bread corner"
	bps.add(b2)
	bps.add_cat("Harbour towns")
	main.blueprints_ui.toggle()
	main.blueprints_ui.tabs.current_tab = bps.cats.find(bp.cat)
	await _shot(out + "b58_manager.png")
	main.blueprints_ui.win.visible = false
	# 3. placing it in a wood: trees in the way are crossed out
	var to := Vector2i(-1, -1)
	var best := -1
	for dy in range(-16, 17, 2):
		for dx in range(-16, 17, 2):
			var c := Vector2i(me.hq.x + dx, me.hq.y + dy)
			var at := UiBlueprints.corner_at(bp, c)
			var why := Blueprints.check(sim, 1, bp, at)
			var obs := Blueprints.obstacles(sim, 1, bp, at)
			var nt := (obs.trees as PackedInt32Array).size()
			var fits := 0
			for k in why.size():
				if why[k] == "" or String(why[k]).begins_with("Trees"): fits += 1
			if fits == why.size() and nt > best:
				best = nt; to = c
	if to.x < 0:
		to = Vector2i(me.hq.x - 8, me.hq.y + 8)
	main.blueprints_ui.start_place(0)
	view.center_on(Vector2(to))
	view.ghost = to
	main._refresh_all()
	await _shot(out + "b58_place.png")
	# 4. the question
	main.blueprints_ui.place_click(to)
	await _shot(out + "b58_ask.png")
	main._confirm_dlg.confirmed.emit()
	main._confirm_dlg.visible = false
	view.place_type = ""
	for i in 10: sim.tick(Sim.TICK)
	main._refresh_all()
	await _shot(out + "b58_placed.png")
	# 5. one building on a tree: the same question
	var one := Vector2i(-1, -1)
	for y in range(me.hq.y - 18, me.hq.y + 19):
		for x in range(me.hq.x - 18, me.hq.x + 19):
			if one.x < 0 and sim.inb(x, y) and sim.deco[sim.idx(x, y)] == Sim.D_TREE and sim.owner[sim.idx(x, y)] == 1:
				var obs1 := Blueprints.obstacles_one(sim, 1, "house", x, y)
				if Blueprints.fits_cleared(sim, 1, "house", x, y, 0, obs1):
					one = Vector2i(x, y)
	if one.x >= 0:
		view.center_on(Vector2(one))
		view.place_type = "house"
		view.door = 0
		view.ghost = one
		main._on_tile(one)
		await _shot(out + "b58_ask_one.png")
	print("trees in the way at the place: %d; buildings now %d" % [best, sim.realm_blds(me).size()])
	DirAccess.remove_absolute(path)
	quit()
