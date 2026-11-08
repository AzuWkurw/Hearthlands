extends SceneTree
## Checks the Go buttons of the event log: xvfb-run godot --rendering-driver opengl3 --script res://tools/log_go_test.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("showcase", 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2
	while sim.time < 8 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	main.paused = true
	main.log_ui.set_open(true)
	main.log_dirty = true
	var with_at := 0
	for l in sim.logs: if l.size() >= 5: with_at += 1
	print("logs ", sim.logs.size(), " with place ", with_at)
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "log_before.png")
	# click the newest Go button
	var last = null
	for l in sim.logs: if l.size() >= 5: last = l
	print("go to ", last[3], ",", last[4], " : ", last[1])
	main.log_ui._go("%d,%d" % [last[3], last[4]])
	print("cam ", main.view.cam, " sel ", main.view.sel_id)
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "log_after.png")
	quit()
