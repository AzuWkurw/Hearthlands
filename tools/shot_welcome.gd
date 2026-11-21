extends SceneTree
## The welcome screen at startup: with a saved game to continue, and on a first start with no saves.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_welcome.gd -- out=/dir [lang=pl]
func _init() -> void:
	var out := "user://"
	var lang := "en"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
		if a.begins_with("lang="): lang = a.substr(5)
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	I18n.set_language(lang)
	# a game some minutes in, saved, so there is one to continue
	main._start("welcome", 3, 5, true); main.setup.visible = false
	for i in 3000: main.sim.tick(Sim.TICK)
	main._refresh_all()
	for i in 20: await process_frame
	main.saves_ui._save_game("autosave", true)
	# the startup: a new realm waiting behind the menu
	main._start("hearth", 3, 5, true)
	main.setup.visible = true
	main.paused = true
	main.welcome_ui.open()
	for i in 90: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "welcome_%s.png" % lang)
	# a first start: no saves yet
	main.welcome_ui.close()
	for fn in DirAccess.get_files_at(Main.SAVE_DIR):
		if fn.begins_with("autosave"): DirAccess.remove_absolute(Main.SAVE_DIR + "/" + fn)
	main.welcome_ui.open()
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "welcome_first_%s.png" % lang)
	# closing it brings the new-game screen back
	main.welcome_ui.close()
	print("ok closed: ", not main.welcome_ui.visible and main.setup.visible)
	I18n.set_language("en")
	print("WELCOME SHOTS: done")
	quit()
