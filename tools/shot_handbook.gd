extends SceneTree
## Screenshots of the handbook (F1) and a first-time tip, in English and in Polish.
## xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_handbook.gd -- out=/dir
func _shot(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("saved ", path)


func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	var kept := FileAccess.get_file_as_bytes(Settings.PATH) if FileAccess.file_exists(Settings.PATH) else PackedByteArray()
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 3: await process_frame
	main._start("handbook", 3, 5, false, 128, false, {"features": Features.default_ids().filter(func(f): return f != "fog"), "start_goods": 4.0})
	main.setup.visible = false
	var sim: Sim = main.sim
	for i in 300: sim.tick(Sim.TICK)
	# the new age's path chosen, so its window stays shut
	var a: int = sim.missing_age_bonus(sim.human())
	if a > 0: sim.human().age_bonus[str(a)] = String(GameData.age_bonuses[str(a)][0].id)
	for lang in ["en", "pl"]:
		I18n.set_language(lang)
		if main.age_ui.panel != null: main.age_ui.panel.visible = false
		main.handbook_ui.open("bld:steelworks")
		main.handbook_ui.win.position = Vector2i(300, 90)
		await _shot(out + "handbook_%s.png" % lang)
		main.handbook_ui.find.text = "planks" if lang == "en" else "deski"
		main.handbook_ui.find.text_changed.emit(main.handbook_ui.find.text)
		main.handbook_ui.show_page("res:planks", true, false)
		await _shot(out + "handbook_search_%s.png" % lang)
		main.handbook_ui.find.text = ""
		main.handbook_ui.find.text_changed.emit("")
		main.handbook_ui.win.visible = false
		main.settings.tips = true
		main.settings.tips_seen = {}
		main.tips_ui.check()
		sim.human().tools_worn += 1
		main.tips_ui.check()
		await _shot(out + "tip_%s.png" % lang)
		main.tips_ui.close()
	if kept.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_buffer(kept)
		f.close()
	quit()
