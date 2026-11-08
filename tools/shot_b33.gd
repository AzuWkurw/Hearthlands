extends SceneTree
## Build 33 interface additions: the first-game guide, expand hints while placing a military building,
## the workshop input setting and walkers' arrival times, keys in Settings, and save thumbnails.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_b33.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = true
	main._start("showcase", 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	main.log_ui.set_open(false)
	# 1. the guide at the very start, after placing a woodcutter
	for i in 50: sim.tick(Sim.TICK)
	for r in range(3, 10):
		var done := false
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if not done and sim.can_place("woodcutter", me.hq.x + dx, me.hq.y + dy, 1, 0) == "":
					sim.place("woodcutter", me.hq.x + dx, me.hq.y + dy, me, 0, false); done = true
		if done: break
	main._refresh_all()
	main.view.center_on(Vector2(me.hq.x + 1.0, me.hq.y + 1.0)); main.view.zoom = 30.0
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "b33_guide.png")
	# 2. a while later: placing a guard hut shows where it claims the most land
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 8 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	main.paused = true
	main.guide_ui.box.visible = false
	main.view.zoom = 22.0
	main.view.place_type = "hut"
	main.view.ghost = Vector2i(me.hq.x + 4, me.hq.y + 2)
	main._refresh_all()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	print("expand spots ", main.view._gain, " sites ", main.view._sites.size())
	root.get_texture().get_image().save_png(out + "b33_expand.png")
	main.view.place_type = ""
	# 3. a workshop's info: inputs kept, people on the way
	var ws: Sim.Bld = null
	for b in sim.blds:
		if b.p == 1 and b.state == "ready" and b.def.has("in") and b.def.has("cycle"):
			ws = b; break
	if ws != null:
		main.view.sel_id = ws.id
		main.view.center_on(Vector2(ws.x, ws.y)); main.view.zoom = 34.0
		main._refresh_all()
		for i in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "b33_inputs.png")
	# 4. settings with the keys
	main.settings.keys = {"sites": KEY_V}
	main._open_settings()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "b33_keys.png")
	main.set_panel.visible = false
	main.settings.keys = {}
	# 5. save list with pictures
	main._save_game("b33 thumbnail test")
	main._open_saves()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "b33_saves.png")
	DirAccess.remove_absolute(Main.SAVE_DIR + "/b33 thumbnail test.save")
	quit()
