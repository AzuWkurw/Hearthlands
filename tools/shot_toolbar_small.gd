extends SceneTree
## The toolbar in a 1280 x 720 window (compact, icons only): xvfb-run ... --script res://tools/shot_toolbar_small.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1280, 720)); root.size = Vector2i(1280, 720)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("showcase", 3, 6, true); main.setup.visible = false
	DisplayServer.window_set_size(Vector2i(1280, 720)); root.size = Vector2i(1280, 720)
	main.settings.apply_scale(root)
	main._refresh_all()
	for i in 10: await process_frame
	print("compact ", main.toolbar.compact, " bar ", main.toolbar.bar.size, " row ", main.toolbar.row.size)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "small.png")
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	main.settings.apply_scale(root)
	for i in 10: await process_frame
	print("compact ", main.toolbar.compact, " bar ", main.toolbar.bar.size)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "big.png")
	quit()
