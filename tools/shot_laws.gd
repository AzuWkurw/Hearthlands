extends SceneTree
## Screenshots of the Laws window (F8), in English and in Polish.
## xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_laws.gd -- out=/dir
func _shot(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 3: await process_frame
	main._start("lawful", 3, 5, false, 128, false, {"features": Features.default_ids().filter(func(f): return f != "fog"), "start_goods": 4.0})
	main.setup.visible = false
	var sim: Sim = main.sim
	for i in 300: sim.tick(Sim.TICK)
	var lw = sim.get_feature("laws")
	lw.set_law(sim.human(), "tax", "heavy")
	lw.set_law(sim.human(), "workday", "long")
	lw.open()
	lw.win.position = Vector2i(380, 120)
	await _shot(out + "laws_en.png")
	print("saved ", out + "laws_en.png")
	TranslationServer.set_locale("pl")
	main._rebuild_feature_ui()
	lw = sim.get_feature("laws")
	lw.open()
	lw.win.position = Vector2i(380, 120)
	await _shot(out + "laws_pl.png")
	print("saved ", out + "laws_pl.png")
	quit()
