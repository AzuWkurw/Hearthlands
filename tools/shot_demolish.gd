extends SceneTree
## Screenshot of the demolish question for a border building: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_demolish.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("demshot", 2, 5, true); main.setup.visible = false
	var sim: Sim = main.sim
	var p := sim.human()
	# a tower near the edge of the land, so it claims land of its own
	var tw: Sim.Bld = null
	var best := 0.0
	for y in range(p.hq.y - 11, p.hq.y + 12):
		for x in range(p.hq.x - 11, p.hq.x + 12):
			var d := Vector2(x - p.hq.x, y - p.hq.y).length()
			if d > best and sim.can_place("tower", x, y, p.id) == "":
				best = d; tw = null
				tw = Sim.Bld.new(); tw.x = x; tw.y = y
	tw = sim.add_bld("tower", tw.x, tw.y, p, true)
	p.reserve = 10
	sim.mil_fill(p); sim.recompute_territory()
	# two buildings on land only the tower holds
	var after := sim.military.compute_owner(tw.id)
	var placed := 0
	for ty in ["woodcutter", "quarry", "well"]:
		var done := false
		for y in range(tw.y - 8, tw.y + 9):
			for x in range(tw.x - 8, tw.x + 9):
				if not done and sim.inb(x, y) and after[sim.idx(x, y)] != p.id and sim.can_place(ty, x, y, p.id) == "":
					sim.add_bld(ty, x, y, p, true); done = true; placed += 1
	main.view.center_on(Vector2(tw.x, tw.y)); main.view.zoom = 30.0
	main._refresh_all()
	main.demolish_ui._ask_demolish(tw) if main.get("demolish_ui") != null else main._ask_demolish(tw)
	for i in 60: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "demolish.png")
	var loss := sim.territory_loss(tw)
	print("placed %d; loss: %d tiles, %d rival, lost %s" % [placed, (loss.tiles as PackedInt32Array).size(), loss.rival, (loss.blds as Array).map(func(o): return o.ty)])
	print("text: ", main.confirm_text.get_parsed_text().replace("\n", " | "))
	main.confirm_panel.visible = false
	await process_frame
	print("after close: preview %d, zoom %.0f" % [main.view.preview_tiles.size(), main.view.zoom])
	quit()
