extends SceneTree
## Screenshots of the end screen and the chronicle window after a short game with a few moments in it:
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_chronicle.gd -- out=/dir
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
	main._start("chronicle", 3, 6, true)
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	for i in 4800: sim.tick(Sim.TICK)   # 8 minutes
	sim.complete_tech(me, "new_kingdoms")
	var sb := sim.add_bld("storehouse", me.hq.x + 9, me.hq.y + 3, me, false, 0)
	sim.production._finish_site(sb, me)
	for i in 1200: sim.tick(Sim.TICK)
	Chronicle.note(sim, me, "capture", {"o": 2, "b": "outpost"})
	Chronicle.note(sim, sim.players[1], "capture", {"o": 1, "b": "outpost"})
	Chronicle.note(sim, me, "repelled", {"o": 2})
	Chronicle.fire(sim, me); Chronicle.burned(sim, me)
	for i in 1200: sim.tick(Sim.TICK)
	sim.military.eliminate(sim.players[3], me)
	sim.over = true   # (as when a game really ends: no age window over the end screen)
	main._on_end(true)
	await _shot(out + "end_screen.png")
	main.chronicle_ui.open(true)
	await _shot(out + "chronicle.png")
	quit()
