extends SceneTree
## Screenshots of vassals: a vassal's headquarters flying its overlord's banner, and the Diplomacy window
## with a vassal and a surrender offer, in English and in Polish.
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_vassal.gd -- out=/dir
func _shot(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = false
	main._start("vassals", 3, 5, false, 128, false, {"features": Features.default_ids().filter(func(f): return f != "fog")})
	main.setup.visible = false
	var sim: Sim = main.sim
	for i in 1200: sim.tick(Sim.TICK)
	for q in sim.players:
		q.dip_t = 1e9
	sim.time = maxf(sim.time, 400.0)
	sim.human().reserve = 200
	sim.players[1].reserve = 0
	Diplomacy.propose(sim, 1, 2, "submit")
	sim.players[2].reserve = 0
	sim.rel_since[Diplomacy.key(1, 3)] = 0.0
	Diplomacy.propose(sim, 3, 1, "vassal")
	var hq: Sim.Bld = sim.players[1].hq
	main.log_ui.set_open(false)
	main.view.zoom = 48.0
	main.view.center_on(Vector2(hq.x + 0.5, hq.y + 0.5))
	main._refresh_all()
	await _shot(out + "vassal_banner.png")
	main._open_diplomacy()
	await _shot(out + "vassal_diplomacy_en.png")
	I18n.set_language("pl")
	main.dip_panel.visible = false
	main._open_diplomacy()
	await _shot(out + "vassal_diplomacy_pl.png")
	I18n.set_language("en")
	quit()
