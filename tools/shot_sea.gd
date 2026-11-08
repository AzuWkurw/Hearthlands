extends SceneTree
## An expedition at sea and the colony it founds.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_sea.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = false
	main._start("valley", 2, 3, false, 0, false, {"peace_min": 60, "features": []}); main.setup.visible = false
	main.log_ui.set_open(false)
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true
	while sim.time < 240.0: sim.tick(Sim.TICK)
	me.ai = false
	var h: Sim.Bld = null
	for r in range(2, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := me.hq.x + dx
				var y := me.hq.y + dy
				if h == null and sim.inb(x, y) and sim.can_place("harbour", x, y, 1) == "":
					sim.place("harbour", x, y, me)
					h = sim.bld_at(x, y)
	h.state = "ready"; h.prog = 1.0
	sim._mil_dirty = true; sim._tick_dirty = true; sim.net_dirty(1)
	sim.logistics.store_add(h, me, "planks", 30.0)
	sim.logistics.store_add(h, me, "stone", 10.0)
	me.ships = 3
	me.reserve = maxi(me.reserve, 3)
	var best := -1
	var bd := 1e9
	for i in sim.w * sim.h:
		var x := i % sim.w
		var y := i / sim.w
		if sim.owner[i] != 0 or (sim.ter[i] != Sim.BEACH and sim.ter[i] != Sim.GRASS):
			continue
		var d := Vector2(x - h.x, y - h.y).length()
		if d > 16.0 and d < bd and sim.sea.landing_ok(x, y, 1) == "" and not sim.sea.water_path(h.x, h.y, x, y).is_empty():
			bd = d; best = i
	sim.sea.expedition(me, h, best % sim.w, best / sim.w)
	var tr: Sim.Trip = sim.trips[sim.trips.size() - 1]
	while sim.time < (tr.t0 + tr.t1) / 2.0: sim.tick(Sim.TICK)
	main.paused = true
	var mid := tr.path[tr.path.size() / 2]
	main.view.center_on(Vector2(mid % sim.w, mid / sim.w))
	main.view.zoom = 30.0
	main.view.sel_id = h.id
	main._refresh_all()
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "sea_expedition.png")
	main.paused = false
	while sim.time < tr.t1 + 70.0: sim.tick(Sim.TICK)
	main.paused = true
	var col := sim.bld_at(best % sim.w, best / sim.w)
	main.view.sel_id = col.id if col != null else 0
	main.view.center_on(Vector2(best % sim.w, best / sim.w))
	main.view.zoom = 24.0
	main._refresh_all()
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "sea_colony.png")
	quit()
