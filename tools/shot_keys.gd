extends SceneTree
## The key list in Settings: xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_keys.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	var kept: Dictionary = main.settings.keys.duplicate()
	main.settings.keys = {}
	main._start("showcase", 3, 6, true); main.setup.visible = false
	main.log_ui.set_open(false)
	for i in 30: main.sim.tick(Sim.TICK)
	main._refresh_all()
	main.keys.set_key("sites", KEY_Q)
	main.keys.set_key("market", KEY_MASK_CTRL | KEY_M)
	main._open_settings()
	main.settings_ui.keys_open = true
	main.key_wait = "diplomacy"
	main.settings_ui._fill_settings()
	for i in 6: await process_frame
	# scroll down to the keys
	var sc: ScrollContainer = null
	var n: Node = main.set_body
	while n != null and sc == null:
		if n is ScrollContainer: sc = n
		n = n.get_parent()
	for l in main.set_body.find_children("*", "Label", true, false):
		if (l as Label).text == "Keys" and sc != null:
			sc.scroll_vertical = int(l.global_position.y - sc.global_position.y) - 20
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "keys_settings.png")
	if sc != null:
		sc.scroll_vertical += 640
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "keys_settings2.png")
	main.key_wait = ""
	main.settings.keys = kept
	main.settings.save_file()
	quit()
