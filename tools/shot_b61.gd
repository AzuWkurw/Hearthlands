extends SceneTree
## Screenshots for build 61: the market window with lots of 50 and standing orders, and the realms graph.
## xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b61.gd -- out=/dir save=user_save
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
	var sim: Sim = main.sim
	var me := sim.human()
	sim.market.add_route(me, "planks", true, 50, 2, 80)
	sim.market.add_route(me, "stone", false, 25, 5, 60)
	sim.market.add_route(me, "fish", true, 10, 1, 40)
	for i in int(300.0 / Sim.TICK): sim.tick(Sim.TICK)
	main.paused = true
	main.market_ui.toggle()
	await _shot(out + "b61_market.png")
	main.market_ui.win.visible = false
	var st = sim.get_feature("statistics")
	st.open_realms()
	st.realm_metric.select(8)
	st.refresh()
	await _shot(out + "b61_realms.png")
	quit()
