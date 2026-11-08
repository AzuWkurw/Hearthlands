extends SceneTree
## Frames of the town close up, for a moving picture of townsfolk and carriers:
## xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_folk.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("showcase", 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.odds = 99.0; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 14 * 60.0:
		sim.tick(Sim.TICK)
	me.ai = false
	main.paused = true
	main.view.center_on(Vector2(me.hq.x + 1.0, me.hq.y + 2.0))
	main.view.zoom = 64.0
	main._refresh_all()
	for i in 20: await process_frame
	for n in 48:
		sim.tick(Sim.TICK)
		main.view.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "f%02d.png" % n)
	print("people ", sim.pop_total(me), " trips ", sim.trips.size())
	quit()
