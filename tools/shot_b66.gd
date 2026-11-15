extends SceneTree
## Screenshots for build 66: a worker's tool in the building panel (and a worn-out one), the build menu
## with the buildings research will open, and the axes' panel with tools by metal.
## xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b66.gd -- out=/dir
func _shot(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _spot(sim: Sim, ty: String, near: Vector2i) -> Vector2i:
	for r in range(0, 16):
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
	var feats: Array = Features.default_ids().filter(func(f): return f != "seasons" and f != "fog")
	main._start("toolshow", 2, 5, false, 0, false, {"features": feats})
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	for i in 10: sim.tick(Sim.TICK)
	var hq := Vector2i(me.hq.x, me.hq.y)
	var at := _spot(sim, "woodcutter", hq + Vector2i(5, 2))
	var wc := sim.add_bld("woodcutter", at.x, at.y, me, true, 0)
	sim.build_road(wc.x, wc.y, me.hq.x, me.hq.y, 1)
	sim.arms.add(me, "axes", SimArms.IRON, 3)
	main.paused = false
	for i in int(20.0 / Sim.TICK): sim.tick(Sim.TICK)
	wc.wxp = 30.0
	main.paused = true
	if main.log_ui.win != null and main.log_ui.win.visible: main.log_ui.toggle()
	var view: MapView = main.view
	view.center_on(Vector2(wc.x, wc.y))
	view.zoom = 48.0
	view.sel_id = wc.id
	main._refresh_sel()
	main._refresh_all()
	await _shot(out + "b66_tool.png")
	# worn out, none in store
	var at2 := _spot(sim, "quarry", hq + Vector2i(-5, 3))
	var q := sim.add_bld("quarry", at2.x, at2.y, me, true, 0)
	sim.build_road(q.x, q.y, me.hq.x, me.hq.y, 1)
	for i in int(15.0 / Sim.TICK): sim.tick(Sim.TICK)
	q.tool_q = SimArms.BRONZE
	sim.get_feature("tool_quality").held[q.id] = [-1.0, 0.0]
	sim.take(me, "pickaxes", float(me.stock.get("pickaxes", 0.0)))
	view.center_on(Vector2(q.x, q.y))
	view.sel_id = q.id
	main._refresh_sel()
	main._refresh_all()
	await _shot(out + "b66_worn.png")
	# the build menu: what research will open
	view.sel_id = -1
	main._refresh_sel()
	main.show_locked = true
	main.toolbar._on_cat("industry")
	main._refresh_all()
	await _shot(out + "b66_locked.png")
	main.toolbar.close_popup()
	quit()
