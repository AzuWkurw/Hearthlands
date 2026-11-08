extends SceneTree
## Tests the Settings window: display mode, resolution, interface size, a renderer trial that fails,
## and continuing the autosaved game after a restart. Run it twice: first with "-- step1", then "-- resume".

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 4: await process_frame
	var win := root
	if "resume" in args:
		print("after restart: game time %.0f s, setup shown %s" % [main.sim.time, main.setup.visible])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
		quit()
		return
	main._start("settings", 2, 5, true)
	main.setup.visible = false
	main.paused = false
	while main.sim.time < 120.0:
		main.sim.tick(Sim.TICK)
	main._open_settings()
	await process_frame
	var opts: Array = main.set_body.find_children("*", "OptionButton", true, false)
	print("settings rows: %d drop-downs, renderer now: %s" % [opts.size(), Settings.running_renderer()])
	main.settings.mode = "windowed"; main.settings.resolution = Vector2i(1280, 720); main._apply_settings()
	for i in 4: await process_frame
	print("window 1280x720: size %s, layout space %s" % [win.size, win.get_visible_rect().size])
	main.settings.ui_scale = 1.3; main._apply_settings()
	for i in 4: await process_frame
	print("interface 130%%: layout space %s" % win.get_visible_rect().size)
	main.settings.ui_scale = 1.0; main.settings.mode = "fullscreen"; main.settings.resolution = Vector2i(1024, 576); main._apply_settings()
	for i in 6: await process_frame
	print("fullscreen at 1024x576: window %s mode %d, drawing at %s" % [win.size, win.mode, win.get_visible_rect().size])
	main.settings.mode = "windowed"; main.settings.resolution = Vector2i(1600, 900); main._apply_settings()
	# a Vulkan trial that never started: the next normal start reports it and stays on OpenGL
	main.settings.trial = "forward_plus"
	main._after_restart()
	print("failed trial: '%s' trial now '%s'" % [main.hint.text, main.settings.trial])
	main._save_game("autosave", true)
	print("autosaved at %.0f s" % main.sim.time)
	quit()
