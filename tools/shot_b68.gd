extends SceneTree
## Screenshots for build 68: stores split by metal, and the production targets by metal.
## xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b68.gd -- out=/dir
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
	me.metal_order["tools"] = [1, 2, 3]
	me.metal_lim["weapons"] = [-1, 10, -1, -1]
	me.metal_keep["tools"] = {"iron": 10}
	sim.give(me, "pickaxes", 2.0); sim.arms.add(me, "pickaxes", SimArms.STEEL, 2)
	var view: MapView = main.view
	view.center_on(Vector2(wc.x, wc.y))
	view.zoom = 40.0
	main._refresh_all()
	await _shot(out + "b68_stores.png")
	main._open_targets()
	for i in 3: await process_frame
	var sc: ScrollContainer = main.targets_ui.targets_grid.get_parent().get_parent()
	sc.scroll_vertical = 100000
	await _shot(out + "b68_targets.png")
	quit()
