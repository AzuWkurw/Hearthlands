extends SceneTree
## Screenshots of the research window: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_research.gd -- out=/dir
func _shot(path: String) -> void:
	for i in 4: await process_frame
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
	main._start("showcase", 3, 6, true)
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	for t in ["iron_axes", "coppicing", "fish_traps", "heavy_plough", "monasteries", "longbows", "chainmail", "stone_masonry", "watermills", "bellows"]:
		sim.complete_tech(me, t)
	sim.set_research(me, "guilds")
	me.rp = 120.0
	print("queue r1_tools: ", sim.queue_research(me, "r1_tools"), sim.queue_research(me, "r1_tools"))
	for x in sim.research_path(me, "printing_press"):
		sim.queue_research(me, x)
	print("queue: ", me.research, " ", me.rqueue)
	main._open_tech()
	await _shot(out + "res_1.png")
	main.research_ui._select("printing_press", true)
	await _shot(out + "res_2.png")
	main.research_ui._select("r1_tools", true)
	await _shot(out + "res_3.png")
	main.research_ui.tree.fit()
	await _shot(out + "res_4.png")
	quit()
