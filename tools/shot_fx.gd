extends SceneTree
## Screenshot of the work effects: a tree falling, a building just finished, a site being built.
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_fx.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("fxshot", 1, 5, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	main.paused = true
	main.side_box.visible = false
	main.guide_ui.box.visible = false
	# a tree near the headquarters, a house to finish, a site with its builder
	var tree := -1
	for r in range(3, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var i := sim.idx(me.hq.x + dx, me.hq.y + dy)
				if tree < 0 and sim.deco[i] == Sim.D_TREE and dx > 0:
					tree = i
	var spot := []
	for y in range(me.hq.y + 2, me.hq.y + 8):
		for x in range(me.hq.x - 7, me.hq.x + 8):
			if spot.size() < 2 and sim.can_place("house", x, y, 1) == "" and (spot.is_empty() or absi(x - spot[0].x) + absi(y - spot[0].y) > 3):
				spot.append(Vector2i(x, y))
	var done := sim.add_bld("house", spot[0].x, spot[0].y, me, true, 0)
	var site := sim.add_bld("house", spot[1].x, spot[1].y, me, false, 0)
	site.prog = 0.55; site.builder = 2
	main.view.center_on(Vector2(me.hq.x + 2.0, me.hq.y + 1.0)); main.view.zoom = 48.0
	for i in 5: await process_frame
	sim.deco[tree] = 0; sim.changed_tiles.append(tree)
	main.view.fx_tree(tree)
	main.view.fx_done(done.id)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 750: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "fx_a.png")
	while Time.get_ticks_msec() - t0 < 1250: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "fx_b.png")
	quit()
