extends SceneTree
## Records short frame sequences of the animations for checking and for animated previews.
## Run: godot --rendering-driver opengl3 --script res://tools/anim_shot.gd -- out=/some/folder
## Plays an AI-run realm for a while, then films a few busy spots frame by frame while the game
## clock moves on a little between frames. Writes <spot>_<frame>.png files.

func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	root.size = Vector2i(960, 600)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 4: await process_frame
	main._start("anim", 2, 4, true)
	main.setup.visible = false
	var sim: Sim = main.sim
	var me: Sim.Player = sim.players[0]
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.odds = 99.0; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 12 * 60.0:
		sim.tick(Sim.TICK)
	me.ai = false
	# film spots: the headquarters, a busy outdoor worker, a fisher by the coast, a mill or kiln
	var spots := {"hq": me.hq}
	for b in sim.blds:
		if b.p != 1 or b.state != "ready":
			continue
		if b.ty == "woodcutter" and not spots.has("woodcutter"): spots["woodcutter"] = b
		if b.ty == "fisher" and not spots.has("coast"): spots["coast"] = b
		if (b.ty == "mill" or b.ty == "charcoal_burner" or b.ty == "brickworks") and not spots.has("workshop"): spots["workshop"] = b
	main.view.sel_id = 0
	for name in spots:
		var b: Sim.Bld = spots[name]
		main.view.center_on(Vector2(b.x + 0.5, b.y + 0.5))
		main.view.zoom = 64.0
		for f in 24:
			for k in 2:
				sim.tick(Sim.TICK)
			main._process(0.016)
			for i in 2: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out + "%s_%02d.png" % [name, f])
	main.view.center_on(Vector2(me.hq.x + 0.5, me.hq.y + 1.5))
	main.view.zoom = 30.0
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "overview.png")
	quit()
