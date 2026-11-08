extends SceneTree
## The map editor: ore painted onto a mountain shows at once, and a stroke re-bakes only what changed.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_editor.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.editor_ui.start("editor demo", 4, 0)
	var sim: Sim = main.sim
	var ed = main.editor_ui
	# find a big mountain patch
	var best := Vector2i(-1, -1)
	for y in range(4, sim.h - 4):
		for x in range(4, sim.w - 4):
			var ok := true
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					if sim.ter[sim.idx(x + dx, y + dy)] != Sim.MOUNT: ok = false
			if ok: best = Vector2i(x, y); break
		if best.x >= 0: break
	print("mountain at ", best)
	main.view.center_on(Vector2(best)); main.view.zoom = 30.0
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "editor_before.png")
	ed.size = 3
	for k in [9, 10, 11]:   # iron, gold, granite
		ed.brush = k
		ed._paint(best + Vector2i((k - 10) * 3, 0), true)
		ed._paint(best + Vector2i((k - 10) * 3, 2), false)
		# the ore shows during the stroke, before it ends
		for i in 3: await process_frame
		var t0 := Time.get_ticks_msec()
		ed._paint_done()
		print("stroke done in ", Time.get_ticks_msec() - t0, " ms")
	print("vein at centre: ", sim.vein[sim.idx(best.x, best.y)], " left ", sim.vein_left(sim.idx(best.x, best.y)))
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "editor_ore.png")
	# water painted: only the changed chunks re-bake (count them)
	ed.brush = 0
	ed._paint(best + Vector2i(0, 6), true)
	var t1 := Time.get_ticks_msec()
	ed._paint_done()
	print("water stroke done in ", Time.get_ticks_msec() - t1, " ms, chunks still baked: ", main.view.chunks._tex.size())
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "editor_water.png")
	quit()
