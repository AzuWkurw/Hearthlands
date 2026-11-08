extends SceneTree
## Statistics: realms compared, and the border replay.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_stats.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = false
	main._start("valley", 3, 6, true); main.setup.visible = false
	main.log_ui.set_open(false)
	var sim: Sim = main.sim
	if sim.get_feature("statistics") == null:
		sim.set_feature("statistics", true)
		main._rebuild_feature_ui()
	var me := sim.human()
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2
	while sim.time < 25 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	main.paused = true
	var st = sim.get_feature("statistics")
	st.win.visible = true
	st.refresh()
	st.tab_box.current_tab = 1
	st.realm_metric.select(5)
	st.refresh()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "stats_realms.png")
	st.tab_box.current_tab = 2
	st.playing = false
	st.border_slider.value = 12
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "stats_borders.png")
	quit()
