extends SceneTree
## Screenshots of the transport and worker priority windows:
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_prio.gd -- out=/dir
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
	main._start("showcase", 3, 6, true, 0, true, {"features": Features.default_ids()})
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 6; me.pers = "balanced"; me.prod = 1.0; me.think = 3.0; me.max_b = 2
	for i in int(900.0 / Sim.TICK): sim.tick(Sim.TICK)
	me.ai = false
	me.carry_rank = {"food": 1, "stone": 2, "planks": 2, "iron_ore": 7}
	me.work_rank = {"bakery": 1, "mill": 2, "farm": 2, "woodcutter": 8}
	sim.staffing(me)
	main._refresh_all()
	main.carry_prio_ui.toggle()
	await _shot(out + "transport_priorities.png")
	main.carry_prio_ui.toggle()
	main.work_prio_ui.toggle()
	await _shot(out + "worker_priorities.png")
	quit()
