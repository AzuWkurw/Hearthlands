extends SceneTree
## Drawing cost at different zoom levels in a busy game:
## xvfb-run godot --rendering-driver opengl3 --script res://tools/zoom_bench.gd
func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("bench", 4, 7, true)
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.odds = 99.0; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 30 * 60.0:
		sim.tick(Sim.TICK)
	me.ai = false
	main.paused = true
	print("buildings %d, carriers %d" % [sim.blds.size(), sim.trips.size()])
	main.view.center_on(Vector2(me.hq.x, me.hq.y))
	var variant := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("v="): variant = a.substr(2)
	if variant == "nofog": sim.set_feature("fog", false)
	if variant == "nofeat":
		for f in sim.feature_ids(): sim.set_feature(f, false)
	if variant == "noside": main.get_child(0).visible = true
	for z in [5.0, 8.0, 11.0, 14.0, 20.0, 32.0]:
		main.view.zoom = z
		for i in 30: await process_frame
		var d := 0.0; var g := 0.0; var fr := 0.0
		var n := 60
		var t0 := Time.get_ticks_usec()
		for i in n:
			main.view.queue_redraw()
			await process_frame
			d += main.view.draw_usec; g += main.view.ground_usec
		fr = (Time.get_ticks_usec() - t0) / float(n)
		print("zoom %4.0f: draw %5.2f ms, ground %4.2f ms, whole frame %5.1f ms" % [z, d / n / 1000.0, g / n / 1000.0, fr / 1000.0])
	quit()
