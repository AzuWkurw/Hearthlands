extends SceneTree
## The interface in Polish: the new-game screen, a game a few minutes in (event log open, a building
## selected), and Settings.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_lang.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	I18n.set_language("pl")
	main.setup.visible = true
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "lang_pl_menu.png")
	main.settings.guide = true
	main._start("showcase", 3, 6, true); main.setup.visible = false
	main.log_ui.set_open(true)
	for i in 1800: main.sim.tick(Sim.TICK)
	for b in main.sim.blds:
		if b.p == 1 and (b.ty == "sawmill" or b.ty == "hq"):
			main.view.sel_id = b.id
	main._refresh_all()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "lang_pl.png")
	main._open_settings()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "lang_pl_settings.png")
	I18n.set_language("en")
	quit()
