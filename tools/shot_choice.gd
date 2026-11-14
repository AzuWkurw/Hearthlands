extends SceneTree
## Screenshot of an event that asks you to choose: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_choice.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 3: await process_frame
	main._start("showcase", 3, 6, true, 0, true, {"features": Features.default_ids()})
	main.setup.visible = false
	main.paused = false
	var ev = main.sim.get_feature("events")
	ev.pending[1] = ["comet", main.sim.time]
	main._refresh_all()
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "choice.png")
	quit()
