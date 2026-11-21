extends SceneTree
## Screenshots of the final score: the end screen, the end of the chronicle, the high-score window and
## the new-game screen with the map of the day, in English and Polish:
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_score.gd -- out=/dir
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
	for lang in ["en", "pl"]:
		I18n.set_language(lang)
		var d := Score.daily_setup()
		main._start(String(d.seed), int(d.foes), int(d.strength), true)
		main.seed_edit.text = String(d.seed)
		main.setup.visible = false
		var sim: Sim = main.sim
		for i in 6000: sim.tick(Sim.TICK)   # 10 minutes
		sim.over = true
		main._on_end(true)
		await _shot(out + "score_end_%s.png" % lang)
		main.chronicle_ui.open(true)
		await process_frame
		main.chronicle_ui.text.scroll_to_line(main.chronicle_ui.text.get_line_count() - 1)
		await _shot(out + "score_chronicle_%s.png" % lang)
		main.chronicle_ui.win.visible = false
		main.end_panel.visible = false
		main.setup.visible = true
		main._update_seed_best()
		await _shot(out + "score_setup_%s.png" % lang)
		main._show_scores()
		await _shot(out + "score_list_%s.png" % lang)
		for c in main.get_children():
			if c is AcceptDialog: c.queue_free()
		main.setup.visible = false
	I18n.set_language("en")
	quit()
