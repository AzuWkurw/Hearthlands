extends SceneTree
## A bridge over a channel, with carriers going over it.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_bridge.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = false
	main._start("showcase", 1, 4, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	main.log_ui.set_open(false)
	var hx := me.hq.x
	var hy := me.hq.y
	for y in range(hy - 8, hy + 9):
		for x in [hx + 4, hx + 5]:
			if sim.bmap[sim.idx(x, y)] == 0 and sim.road[sim.idx(x, y)] == 0:
				sim.ter[sim.idx(x, y)] = Sim.WATER; sim.deco[sim.idx(x, y)] = 0
	for x in range(hx + 6, hx + 10):
		for y in range(hy - 3, hy + 4):
			sim.deco[sim.idx(x, y)] = 0
	sim.height = WorldGen.heights(sim.seed_str, sim.ter, sim.w, sim.h)
	sim.logistics.net_dirty(1)
	main.view.reset_world()
	print(sim.place("woodcutter", hx + 8, hy - 1, me))
	print(sim.place("quarry", hx + 8, hy + 3, me))
	sim.build_road(hx, hy, hx + 3, hy - 3, 1)
	print(sim.build_road(hx + 3, hy - 3, hx + 7, hy - 3, 1))
	print(sim.pave_road(hx + 4, hy - 3, me))
	for i in 600: sim.tick(Sim.TICK)
	main.view.center_on(Vector2(hx + 4.5, hy)); main.view.zoom = 44.0
	main._refresh_all()
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "bridge.png")
	quit()
