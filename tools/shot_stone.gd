extends SceneTree
## Boundary stones: one built at the border, another being placed with the land it would claim.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_stone.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = false
	main._start("showcase", 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	main.log_ui.set_open(false)
	for i in 50: sim.tick(Sim.TICK)
	var spots := []
	for y in range(me.hq.y - 10, me.hq.y + 11):
		for x in range(me.hq.x - 10, me.hq.x + 11):
			if sim.inb(x, y) and sim.can_place("boundary_stone", x, y, 1) == "":
				var g := 0
				for dy in range(-4, 5):
					for dx in range(-4, 5):
						if dx * dx + dy * dy <= 16 and sim.inb(x + dx, y + dy) and sim.owner[sim.idx(x + dx, y + dy)] == 0: g += 1
				spots.append([g, x, y])
	spots.sort_custom(func(a, b): return a[0] > b[0])
	var s0: Array = spots[0]
	sim.place("boundary_stone", s0[1], s0[2], me)
	var t0 := sim.time
	while sim.time - t0 < 40.0: sim.tick(Sim.TICK)
	main.paused = true
	# the next one being placed: on the spot the game marks as claiming the most
	main.cat = "mil"; main._rebuild_build_list()
	main.view.place_type = "boundary_stone"
	main.view.ghost = Vector2i(s0[1], s0[2])
	main.view.center_on(Vector2(s0[1] + 2, s0[2] - 1)); main.view.zoom = 34.0
	main._refresh_all()
	for i in 10: await process_frame
	var ghost := Vector2i(-1, -1)
	var bg := -1
	for t in main.view._gain:
		if t >= 0 and int(main.view._gain[t]) > bg: bg = int(main.view._gain[t]); ghost = Vector2i(t % sim.w, t / sim.w)
	main.view.ghost = ghost
	main.view.center_on(Vector2((s0[1] + ghost.x) / 2.0 + 1.5, (s0[2] + ghost.y) / 2.0))
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "boundary_stone.png")
	print("stone at ", s0, " ghost ", ghost)
	quit()
