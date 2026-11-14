extends SceneTree
## Screenshot of the new age's window: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_age.gd -- out=/dir
func _shot(path: String) -> void:
	for i in 6: await process_frame
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
	main._start("showcase", 3, 6, true)
	main.setup.visible = false
	main.paused = false
	var sim: Sim = main.sim
	var me := sim.human()
	for t in ["new_kingdoms", "iron_axes", "coppicing", "fish_traps", "heavy_plough", "monasteries", "longbows", "chainmail", "stone_masonry", "watermills", "bellows", "rise_of_towns"]:
		sim.complete_tech(me, t)
	me.age_bonus["1"] = "royal_estates"
	main._refresh_all()
	await _shot(out + "age_window.png")
	main.age_ui._choose(2, "merchant_guilds")
	main._refresh_all()
	await _shot(out + "age_after.png")
	quit()
