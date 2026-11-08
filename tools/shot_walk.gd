extends SceneTree
## Pictures of a builder and soldiers walking to their buildings:
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_walk.gd -- out=/dir
var out := "user://"
var main

func shot(name: String) -> void:
	main.view.queue_redraw()
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name + ".png")

func walker_pos(sim: Sim, kind: String, site: int) -> Vector2:
	for t in sim.trips:
		if t.kind == kind and t.site == site:
			var n := t.path.size() - 1
			var prog := 1.0 - clampf((sim.time - t.t0) / maxf(0.01, t.t1 - t.t0), 0.0, 0.999)
			var f := prog * n
			var k := mini(floori(f), n - 1)
			return Vector2(t.path[k] % sim.w, t.path[k] / sim.w)
	return Vector2(-1, -1)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("showcase", 2, 4, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	for i in 50: sim.tick(Sim.TICK)
	main.log_ui.set_open(false)
	var spot := Vector2i(-1, -1); var bd := 0.0
	for i in sim.owner.size():
		if sim.owner[i] != 1: continue
		var x := i % sim.w; var y := i / sim.w
		var d := Vector2(x - me.hq.x, y - me.hq.y).length()
		if d > bd and d < 8.5 and sim.can_place("hut", x, y, 1) == "" and sim._path_to_net(x, y, 1).size() > 1:
			bd = d; spot = Vector2i(x, y)
	sim.place("hut", spot.x, spot.y, me)
	var b := sim.bld_at(spot.x, spot.y)
	main.paused = true
	main.view.zoom = 64.0
	# the builder halfway there
	while b.builder != 1 or sim.time < 1.0: sim.tick(Sim.TICK)
	for i in 25: sim.tick(Sim.TICK)
	var wp := walker_pos(sim, "builder", b.id)
	main.view.center_on(wp + Vector2(0.5, 0.5))
	main._refresh_all()
	await shot("1_builder")
	# the soldiers on their way
	while b.walking == 0: sim.tick(Sim.TICK)
	for i in 25: sim.tick(Sim.TICK)
	wp = walker_pos(sim, "soldier", b.id)
	main.view.center_on(wp + Vector2(0.5, 0.0))
	main._refresh_all()
	await shot("2_soldiers")
	main.view.sel_id = b.id
	main._refresh_all()
	await shot("3_info")
	quit()
