extends SceneTree
## Screenshots for build 70: a scrap forge and armorers on the map; scrap and armor by metal in the stores.
## xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b70.gd -- out=/dir
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
	main._start("metalshow", 2, 5, false, 0, false, {"features": feats})
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	for i in 10: sim.tick(Sim.TICK)
	# stores: steel axes, bronze pickaxes, iron saws; weapons of all three
	sim.give(me, "axes", 4.0); sim.arms.add(me, "axes", SimArms.STEEL, 4)
	sim.give(me, "pickaxes", 3.0); sim.arms.add(me, "pickaxes", SimArms.BRONZE, 3)
	sim.give(me, "weapons", 6.0); sim.arms.add(me, "weapons", SimArms.STEEL, 2); sim.arms.add(me, "weapons", SimArms.BRONZE, 4)
	me.arm_n = [0, 4, 7, 2]
	var hq := Vector2i(me.hq.x, me.hq.y)
	var at := _spot(sim, "woodcutter", hq + Vector2i(5, 2))
	var wc := sim.add_bld("woodcutter", at.x, at.y, me, true, 0)
	sim.build_road(wc.x, wc.y, me.hq.x, me.hq.y, 1)
	main.paused = false
	for i in int(20.0 / Sim.TICK): sim.tick(Sim.TICK)
	sim.arms.fit_arms(me)
	main.paused = true
	if main.log_ui.win != null and main.log_ui.win.visible: main.log_ui.toggle()
	sim.give(me, "armor", 3.0); sim.arms.add(me, "armor", SimArms.BRONZE, 3)
	sim.give(me, "scrap", 5.0); sim.arms.add(me, "scrap", SimArms.BRONZE, 3); sim.arms.add(me, "scrap", SimArms.IRON, 2)
	var sfa := _spot(sim, "scrap_forge", hq + Vector2i(-4, 4))
	var sf := sim.add_bld("scrap_forge", sfa.x, sfa.y, me, true, 0)
	var baa := _spot(sim, "bronze_armorer", hq + Vector2i(3, 6))
	sim.add_bld("bronze_armorer", baa.x, baa.y, me, true, 0)
	var view: MapView = main.view
	view.center_on(Vector2(sf.x + 2, sf.y))
	view.zoom = 48.0
	view.sel_id = sf.id
	main._refresh_sel()
	main._refresh_all()
	await _shot(out + "b70_forge.png")
	view.sel_id = 0
	main.sel_res = "scrap"
	main._refresh_sel()
	main._refresh_all()
	await _shot(out + "b70_scrap.png")
	quit()
