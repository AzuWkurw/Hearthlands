extends SceneTree
## Trees, peaks and boulders standing on hilly ground, close up and further out.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_scenery.gd -- out=/dir tag=new
func _init() -> void:
	var out := "user://"
	var tag := "new"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
		if a.begins_with("tag="): tag = a.substr(4)
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = false
	main._start("showcase", 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	main.log_ui.set_open(false)
	main.paused = true
	# the hilliest wooded spot with mountains near
	var best := Vector2i(sim.w / 2, sim.h / 2)
	var bs := -1.0
	for y in range(8, sim.h - 8, 3):
		for x in range(8, sim.w - 8, 3):
			var trees := 0; var mtn := 0; var lo := 255; var hi := 0
			for dy in range(-5, 6, 2):
				for dx in range(-7, 8, 2):
					var i := sim.idx(x + dx, y + dy)
					if sim.deco[i] == Sim.D_TREE: trees += 1
					if sim.ter[i] == Sim.MOUNT: mtn += 1
					lo = mini(lo, sim.height[i]); hi = maxi(hi, sim.height[i])
			var sc := float(trees) * float(hi - lo) * (1.0 + mini(mtn, 8))
			if sim.owner[sim.idx(x, y)] == 0 and sc > bs: bs = sc; best = Vector2i(x, y)
	print("spot ", best, " score ", bs)
	for z in [36.0, 20.0]:
		main.view.center_on(Vector2(best)); main.view.zoom = z
		for i in 40: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "scenery_%s_z%d.png" % [tag, int(z)])
	# frame time far out with the scenery
	main.view.zoom = 12.0
	for i in 30: await process_frame
	var t0 := Time.get_ticks_usec()
	for i in 30:
		main.view.queue_redraw(); await process_frame
	print("frame ms at zoom 12: ", (Time.get_ticks_usec() - t0) / 30000.0, " draw usec ", main.view.draw_usec if "draw_usec" in main.view else -1)
	quit()
