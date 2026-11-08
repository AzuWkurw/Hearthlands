extends SceneTree
## Screenshots of building entrances, manual roads and the Go buttons in the event log:
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_door.gd -- out=/dir
var main
var out := "user://"

func shot(name: String) -> void:
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name + ".png")

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("showcase", 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 6 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	# a few events of your own, so the log has Go buttons
	for i in 400: sim.tick(Sim.TICK)
	main.paused = true
	main.settings.auto_roads = false; main.view.auto_roads = false
	main._set_cat("raw")
	# a free spot a few tiles from the headquarters, whose entrance can face south and east
	var spot := Vector2i(-1, -1)
	for r in range(3, 10):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x: int = me.hq.x + dx; var y: int = me.hq.y + dy
				if spot.x < 0 and sim.can_place("woodcutter", x, y, 1, 0) == "" and sim.can_place("woodcutter", x, y, 1, 1) == "" and sim.connected(sim.bld_at(me.hq.x, me.hq.y)):
					var near := false
					for k in [-1, 1]:
						if sim.inb(x + k * 2, y + 2) and sim.road[sim.idx(x + k * 2, y + 2)] == 1: near = true
					if near or r > 6: spot = Vector2i(x, y)
	print("spot ", spot)
	main.view.center_on(Vector2(spot.x + 0.5, spot.y + 0.5))
	main.view.zoom = 72.0
	main._refresh_all()
	main.log_ui.set_open(true)
	main.log_dirty = true
	# 1: placing, entrance south; 2: after R, entrance east
	main._pick_build("woodcutter")
	main.view.ghost = spot; main.view.door = 0
	await shot("1_place_south")
	main.view.door = 1
	await shot("2_place_east")
	# 3: auto roads on: the road it would get
	main.settings.auto_roads = true; main.view.auto_roads = true
	main._rebuild_build_list()
	var sc = main.build_grid.get_parent()
	while sc != null and not (sc is ScrollContainer): sc = sc.get_parent()
	if sc != null: (sc as ScrollContainer).ensure_control_visible(main.build_grid)
	for i in 4: await process_frame
	var gr: Rect2 = main.build_grid.get_global_rect()
	print("grid ", gr.position.x, " ", gr.position.y, " ", gr.size.x, " ", gr.size.y)
	await shot("3_auto_roads")
	main.settings.auto_roads = false; main.view.auto_roads = false
	main._rebuild_build_list()
	# 4: placed with roads by hand: the road tool starts at its entrance
	main._on_tile(spot)
	var b := sim.bld_at(spot.x, spot.y)
	print("placed ", b != null, " door ", b.door if b else -9, " connected ", sim.connected(b) if b else false, " tool ", main.view.place_type)
	# the mouse on the nearest road tile
	var best := -1; var bd := 1e9
	for i in sim.road.size():
		if sim.road[i] == 1:
			var d := Vector2(i % sim.w - spot.x, i / sim.w - spot.y).length()
			if d < bd and d > 2.0: bd = d; best = i
	main.view.ghost = Vector2i(best % sim.w, best / sim.w)
	await shot("4_manual_road")
	main._on_tile(main.view.ghost)
	print("after road: connected ", sim.connected(b), " tool '", main.view.place_type, "'")
	main.view.ghost = Vector2i(-50, -50)
	for i in 60: sim.tick(Sim.TICK)
	main._refresh_all()
	await shot("5_joined")
	# 6: Go in the event log
	var last = null
	for l in sim.logs: if l.size() >= 5: last = l
	var n := 0
	for l in sim.logs: if l.size() >= 5: n += 1
	print("logs with place: ", n, " of ", sim.logs.size())
	main.view.center_on(Vector2(me.hq.x - 20, me.hq.y - 12))
	main.log_dirty = true
	await shot("6_log_before")
	main.log_ui._go("%d,%d" % [int(last[3]), int(last[4])])
	print("went to ", last[1], " cam ", main.view.cam)
	await shot("7_log_after")
	main._open_settings()
	await shot("8_settings")
	quit()
