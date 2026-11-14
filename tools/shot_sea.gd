extends SceneTree
## Screenshots for build 49: the harbour start, and a landing fleet at sea.
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_sea.gd -- out=/dir
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
	main._start("islands", 3, 5, false, 160, false, {"features": Features.default_ids(), "sea_start": true})
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	main.paused = false
	for i in 30: sim.tick(Sim.TICK)
	main.view.center_on(Vector2(me.hq.x + 0.5, me.hq.y))
	main.view.zoom = 34.0
	main.paused = true
	await _shot(out + "sea_start.png")
	# a landing on a rival's coast
	var tgt: Sim.Bld = null
	for q in sim.players:
		if q.id != 1 and not sim.sea.landing_route(me.hq, q.hq).is_empty():
			tgt = q.hq
			break
	if tgt != null:
		me.reserve = 12; me.rmix = [6, 6, 0, 0, 0, 0]; me.ships = 2
		sim.give(me, "bread", 40.0)
		Diplomacy.declare_war(sim, 1, tgt.p)
		# the attack window for a building across the water
		main.view.center_on(Vector2(tgt.x, tgt.y))
		main.view.zoom = 24.0
		main.attack_ui.open(tgt)
		await _shot(out + "landing_window.png")
		main.attack_ui.close()
		print("landing: '%s'" % sim.military.launch_landing(me.hq, tgt, 12))
		for i in int(30.0 / Sim.TICK): sim.tick(Sim.TICK)
		for i in 3:
			main.paused = false
			sim.tick(Sim.TICK)
			sim.get_feature("fog").on_second()
		for a in sim.attacks:
			if a.p == 1:
				main.view.center_on(sim.military.column_pos(a))
		main.view.zoom = 30.0
		main._refresh_all()
		await _shot(out + "landing.png")
	quit()
