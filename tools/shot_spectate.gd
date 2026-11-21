extends SceneTree
## Spectator mode (build 77): a game the computer plays on every side, after a few minutes, with the
## Realms board and no toolbar; then checks that order keys and the info box's controls stay out.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_spectate.gd -- out=/dir [lang=pl]
func _init() -> void:
	var out := "user://"
	var lang := "en"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
		if a.begins_with("lang="): lang = a.substr(5)
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	TranslationServer.set_locale(lang)
	var feats: Array = Features.default_ids().duplicate()
	if not feats.has("fog"):
		feats.append("fog")
	main._start("showcase", 3, 6, true, 0, true, {"spectate": true, "features": feats}); main.setup.visible = false
	main.log_ui.set_open(false)
	for i in 2400: main.sim.tick(Sim.TICK)
	main._refresh_all()
	var ok := true
	ok = ok and main.spectate_ui.section.visible and not main.toolbar.bar.visible
	ok = ok and main.play_btns.all(func(b): return not b.visible)
	ok = ok and main.sim.get_feature("fog") == null
	# the info box of a building: text, no controls
	for b in main.sim.realm_blds(main.sim.players[1]):
		if b.state == "ready" and b.ty != "hq":
			main.view.sel_id = b.id
			break
	main._refresh_sel()
	ok = ok and not main.prio_row.visible and not main.sel_actions.visible
	# an order key does nothing
	var ev := InputEventKey.new(); ev.keycode = KEY_T; ev.pressed = true
	main._unhandled_input(ev)
	ok = ok and not main.targets_panel.visible
	var far: Sim.Player = main.sim.players[2]
	main.spectate_ui.go_to(far.id)
	ok = ok and main.view.cam.distance_to(Vector2(far.hq.x + 0.5, far.hq.y + 0.5)) < 1.0
	print("camera at %s, realm 3's headquarters at %d,%d" % [main.view.cam, far.hq.x, far.hq.y])
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "spectate_%s.png" % lang)
	# a normal game afterwards has its toolbar back
	main._start("showcase", 3, 6, true); main.setup.visible = false
	main._refresh_all()
	ok = ok and not main.spectate_ui.section.visible and main.toolbar.bar.visible and main.play_btns.all(func(b): return b.visible)
	print("SPECTATE UI: %s" % ("PASS" if ok else "FAIL"))
	TranslationServer.set_locale("en")
	quit()
