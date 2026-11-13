extends SceneTree
## Screenshot of a farm with its fields: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_fields.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("fields", 2, 5, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 6; me.pers = "balanced"; me.prod = 1.0; me.think = 3.0; me.max_b = 2
	var farm: Sim.Bld = null
	while sim.time < 1200.0 and farm == null:
		for i in 50: sim.tick(Sim.TICK)
		for b: Sim.Bld in sim.blds:
			if b.p == 1 and b.ty == "farm" and Crops.count(sim, b).x >= 5 and Crops.count(sim, b).y >= 1:
				farm = b
	me.ai = false
	print("time %d, farm %s" % [int(sim.time), str(farm != null)])
	if farm == null:
		quit(); return
	main.view.center_on(Vector2(farm.x + 1.0, farm.y + 1.5)); main.view.zoom = 64.0
	main.view.sel_id = -1
	main.side_box.visible = false
	main.view.sel_id = -1
	main._refresh_all()
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "fields.png")
	quit()
