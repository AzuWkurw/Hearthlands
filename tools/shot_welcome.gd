extends SceneTree
## The welcome screen in each of its looks (UiWelcome.STYLES), with a saved game to continue and, for
## the first-steps look, also without one (a first start).
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_welcome.gd -- out=/dir
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
	for st in UiWelcome.STYLES.size():
		main.welcome_ui.open(st)
		for i in 90: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "welcome_%d_%s.png" % [st + 1, lang])
	# a first start: no saves yet
	DirAccess.remove_absolute(Main.SAVE_DIR + "/autosave.save")
	main.welcome_ui.open(2)
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "welcome_3_first_%s.png" % lang)
	I18n.set_language("en")
	print("WELCOME SHOTS: done")
	quit()
