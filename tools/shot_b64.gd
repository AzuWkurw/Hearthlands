extends SceneTree
## Screenshots for build 64 on a save: a railway between two stations with a train on it, the
## station's info, and workshops with steam engines.
## xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b64.gd -- out=/dir save=user_save
func _shot(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _spot(sim: Sim, ty: String, near: Vector2i) -> Vector2i:
	for r in range(0, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r: continue
				if sim.can_place(ty, near.x + dx, near.y + dy, 1, 0) == "":
					return Vector2i(near.x + dx, near.y + dy)
	return Vector2i(-1, -1)


func _init() -> void:
	var out := "user://"
	var save := "user_save"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
		if a.begins_with("save="): save = a.substr(5)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 3: await process_frame
	main._load_game(save)
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	var rw := sim.railway
	me.techs["railways"] = true
	me.techs["steam_engine"] = true
	for r in [["rails", 200.0], ["locomotive", 2.0], ["coal", 60.0], ["steel", 20.0], ["iron", 40.0], ["bricks", 60.0]]:
		sim.give(me, String(r[0]), float(r[1]))
	# two stores far apart: a station by each, track between them
	var stores: Array = sim.logistics.stores_of(me)
	var pair := []
	var bd := 0.0
	for a in stores:
		for b in stores:
			var d := Vector2(a.x - b.x, a.y - b.y).length()
			if d > bd and d < 34.0:
				bd = d; pair = [a, b]
	var sa := _spot(sim, "railway_station", Vector2i(pair[0].x + 2, pair[0].y + 2))
	var sb := _spot(sim, "railway_station", Vector2i(pair[1].x + 2, pair[1].y + 2))
	var st_a := sim.add_bld("railway_station", sa.x, sa.y, me, true, 0)
	var st_b := sim.add_bld("railway_station", sb.x, sb.y, me, true, 0)
	for i in 12: sim.tick(Sim.TICK)
	var why := rw.build(st_a.x, st_a.y, st_b.x, st_b.y, 1)
	print("track: '%s', line %d tiles" % [why, rw.line_path(st_a, st_b).size()])
	sim.logistics.store_add(st_a, me, "planks", 50.0)
	sim.logistics.store_add(st_a, me, "stone", 40.0)
	# steam engines in the busiest workshops
	var n := 0
	for b: Sim.Bld in sim.realm_blds(me):
		if n < 10 and rw.steam_why(b) == "":
			rw.fit_steam(b)
			b.steam_at = sim.time
			n += 1
	var train: Sim.Trip = null
	main.paused = false
	var t_end := sim.time + 90.0
	while sim.time < t_end:
		sim.tick(Sim.TICK)
		for t in sim.trips:
			if t.kind == "train" and not t.delivered and sim.time > t.t0 + (t.t1 - t.t0) * 0.45:
				train = t
		if train != null:
			break
	main.paused = true
	if main.log_ui.win != null and main.log_ui.win.visible: main.log_ui.toggle()
	var view: MapView = main.view
	var line := rw.line_path(st_a, st_b)
	view.center_on(Vector2(line[line.size() / 2] % sim.w, line[line.size() / 2] / sim.w))
	view.zoom = 24.0
	main._refresh_all()
	await _shot(out + "b64_line.png")
	if train != null:
		var f := clampf((sim.time - train.t0 - 2.0) / maxf(0.01, train.t1 - train.t0 - 4.0), 0.0, 1.0)
		var at: int = train.path[int(f * (train.path.size() - 1))]
		view.center_on(Vector2(at % sim.w, at / sim.w))
	view.zoom = 56.0
	main._refresh_all()
	await _shot(out + "b64_train.png")
	view.center_on(Vector2(st_a.x, st_a.y))
	view.zoom = 44.0
	view.sel_id = st_a.id
	main._refresh_sel()
	main._refresh_all()
	await _shot(out + "b64_station.png")
	for b: Sim.Bld in sim.realm_blds(me):
		if b.steam:
			view.center_on(Vector2(b.x, b.y))
			view.sel_id = b.id
			break
	view.zoom = 44.0
	main._refresh_sel()
	main._refresh_all()
	await _shot(out + "b64_steam.png")
	quit()
