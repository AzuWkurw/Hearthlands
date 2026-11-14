extends SceneTree
## Screenshots for build 54 from a save: the priority sets, and the numbers in a building's info.
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b54.gd -- out=/dir save=user_save
func _shot(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var out := "user://"
	var save := "user_save"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
		if a.begins_with("save="): save = a.substr(5)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 3: await process_frame
	main._load_game(save)
	main.setup.visible = false
	main.paused = true
	var sim: Sim = main.sim
	PrioPresets.apply_named(sim.human(), "Feed everyone")
	main.carry_prio_ui.toggle()
	await _shot(out + "b54_sets.png")
	main.carry_prio_ui.win.visible = false
	for b in sim.realm_blds(sim.human()):
		if b.ty == "bakery" and b.state == "ready":
			main.view.sel_id = b.id
			main.view.center_on(Vector2(b.x, b.y))
			main.view.zoom = 34.0
			break
	main._refresh_sel()
	main._refresh_all()
	await _shot(out + "b54_info.png")
	quit()
