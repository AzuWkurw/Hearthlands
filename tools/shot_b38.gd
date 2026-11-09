extends SceneTree
## Build 38 screenshots: a farm's crop choice, and worn weapons in a tower:
## xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b38.gd -- out=/dir
func _shot(out: String, name: String) -> void:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name)

func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("cropshot", 2, 5, true); main.setup.visible = false
	var sim: Sim = main.sim
	var p := sim.human()
	for t in ["heavy_plough", "open_fields", "monasteries"]:
		sim.complete_tech(p, t)
	var farm: Sim.Bld = null
	for y in range(p.hq.y - 9, p.hq.y + 10):
		for x in range(p.hq.x - 9, p.hq.x + 10):
			if farm == null and Vector2(x - p.hq.x, y - p.hq.y).length() > 5 and sim.can_place("farm", x, y, p.id) == "":
				farm = sim.add_bld("farm", x, y, p, true)
	farm.crop = "vegetables"
	main.view.center_on(Vector2(farm.x + 0.5, farm.y + 0.5)); main.view.zoom = 34.0
	main.view.sel_id = farm.id
	main._refresh_all()
	await _shot(out, "farm_crops.png")
	var tw: Sim.Bld = null
	for y in range(p.hq.y - 9, p.hq.y + 10):
		for x in range(p.hq.x - 9, p.hq.x + 10):
			if tw == null and Vector2(x - p.hq.x, y - p.hq.y).length() > 5 and sim.can_place("tower", x, y, p.id) == "":
				tw = sim.add_bld("tower", x, y, p, true)
	p.reserve = 10
	sim.mil_fill(p)
	tw.garrison = 4; tw.gmix = [4, 0, 0, 0, 0, 0]; tw.staffed = true
	tw.blunt = 3
	main.view.center_on(Vector2(tw.x + 0.5, tw.y + 0.5))
	main.view.sel_id = tw.id
	main._refresh_all()
	await _shot(out, "tower_weapons.png")
	quit()
