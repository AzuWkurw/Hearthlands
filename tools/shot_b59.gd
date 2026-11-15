extends SceneTree
## Screenshots for build 59: a landing seen off the coast (the warning), the peasants on the shore,
## a warship going out to meet the fleet. xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b59.gd -- out=/dir
func _shot(path: String) -> void:
	for i in 8: await process_frame
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
	var sim: Sim = null
	var route := []
	var tgt: Sim.Bld = null
	for sd in ["islands", "coast", "bay", "isles"]:
		main._start(sd, 3, 5, false, 160, false, {"sea_start": true, "features": Features.default_ids().filter(func(f): return f != "fog")})
		main.setup.visible = false
		sim = main.sim
		if not sim.human().landed:
			continue
		for q in sim.players:
			if q.id != 1 and tgt == null:
				var r := sim.sea.landing_route(sim.human().hq, q.hq)
				if not r.is_empty():
					tgt = q.hq; route = r
		if tgt != null:
			break
	var me := sim.human()
	var q := sim.players[tgt.p - 1]
	for i in 20: sim.tick(Sim.TICK)
	Diplomacy.declare_war(sim, q.id, 1)
	var beach: int = (route[0] as PackedInt32Array)[(route[0] as PackedInt32Array).size() - 1]
	sim.bmap[beach] = 0
	var qh := sim.add_bld("harbour", beach % sim.w, beach / sim.w, q, true)
	sim.naval.launch(me, me.hq)
	q.reserve = 12; q.rmix = [12, 0, 0, 0, 0, 0]; q.ships = 3; q.ships_out = 0; q.general_back = 0.0
	sim.give(q, "bread", 30.0)
	me.peasant = 48
	me.reserve = 20; me.rmix = [20, 0, 0, 0, 0, 0]
	sim.military.launch_landing(qh, me.hq, 12)
	var a: Sim.Attack = sim.attacks[-1]
	while not a.warned and sim.attacks.has(a):
		sim.tick(Sim.TICK)
	for i in 20: sim.tick(Sim.TICK)
	main.paused = true
	main.view.center_on(sim.military.column_pos(a).lerp(Vector2(me.hq.x, me.hq.y), 0.5))
	main.view.zoom = 20.0
	main.log_ui.toggle()
	main._refresh_all()
	await _shot(out + "b59_warning.png")
	while not a.militia and sim.attacks.has(a):
		sim.tick(Sim.TICK)
	for i in 5: sim.tick(Sim.TICK)
	main.view.center_on(Vector2(me.hq.x, me.hq.y + 2))
	main.view.zoom = 30.0
	main._refresh_all()
	await _shot(out + "b59_militia.png")
	quit()
