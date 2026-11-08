extends SceneTree
## Screenshot of a battle in the open: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_field.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("fieldshot", 1, 5, true, 0, {"features": ["seasons"]}) if false else main._start("fieldshot", 1, 5, true)
	main.setup.visible = false
	var sim: Sim = main.sim
	var p1 := sim.players[0]; var p2 := sim.players[1]
	Diplomacy.set_relation(sim, 1, 2, Diplomacy.WAR)
	var c := Vector2(p1.hq.x + 4, p1.hq.y + 2)
	for side in [[1, 3, 6, c - Vector2(6, 0), c + Vector2(30, 0), p2.hq.id], [2, 4, 4, c + Vector2(6, 0), c - Vector2(30, 0), p1.hq.id]]:
		var a := Sim.Attack.new()
		a.p = side[0]; a.n = side[2]; a.amix = [0, 0, 0, 0, 0, 0]; a.amix[side[1]] = side[2]; a.era = float(side[1])
		a.from = side[3]; a.to = side[4]; a.tgt = side[5]; a.t0 = sim.time; a.t1 = sim.time + 40.0
		a.vt = [sim.time, sim.time]; a.dvt = [sim.time, sim.time]
		sim._bid += 1; a.uid = sim._bid
		sim.attacks.append(a)
	var t0 := sim.time
	while sim.attacks.size() == 2 and sim.attacks[0].field == 0 and sim.time < t0 + 30.0:
		sim.tick(Sim.TICK)
	for i in 30: sim.tick(Sim.TICK)
	main.view.center_on(c); main.view.zoom = 40.0
	main._refresh_all()
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "field.png")
	print("log: ", sim.logs.slice(-3).map(func(l): return l[1]))
	quit()
