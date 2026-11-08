extends SceneTree
## Screenshot of the garrison settings: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_garrison.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("garshot", 2, 5, true); main.setup.visible = false
	var sim: Sim = main.sim
	var p := sim.human()
	for t in ["heavy_plough", "monasteries", "feudalism", "guilds", "chainmail", "castles", "gunpowder"]:
		sim.complete_tech(p, t)
	var tw: Sim.Bld = null
	for y in range(p.hq.y - 8, p.hq.y + 9):
		for x in range(p.hq.x - 8, p.hq.x + 9):
			if tw == null and Vector2(x - p.hq.x, y - p.hq.y).length() > 5 and sim.can_place("tower", x, y, p.id) == "":
				tw = sim.add_bld("tower", x, y, p, true)
	p.reserve = 14; p.rmix = [0, 3, 4, 5, 2, 0]
	sim.mil_fill(p)
	tw.want_n = 3; tw.want_kinds = [false, false, true, true, true, false]; tw.keep_kind = 3
	sim.mil_fill(p)
	main.view.center_on(Vector2(tw.x + 0.5, tw.y + 0.5)); main.view.zoom = 34.0
	main.view.sel_id = tw.id
	main._refresh_all()
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "garrison.png")
	print("tower: ", Sim.mix_text(sim.gmix_of(tw)))
	quit()
