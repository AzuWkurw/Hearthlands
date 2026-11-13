extends SceneTree
## Screenshots of a mid-game town at three zooms, for judging the graphics:
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_look.gd -- out=/dir [tag=now]
func _init() -> void:
	var out := "user://"
	var tag := "now"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
		if a.begins_with("tag="): tag = a.substr(4)
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("lookshot", 2, 5, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 6; me.pers = "balanced"; me.prod = 1.0; me.think = 3.0; me.max_b = 2
	while sim.time < 1200.0:
		for i in 50: sim.tick(Sim.TICK)
	me.ai = false
	main.side_box.visible = false
	main.guide_ui.box.visible = false
	var c := Vector2(me.hq.x + 3.5, me.hq.y + 2.5)
	for z in [[14.0, "far"], [30.0, "mid"], [56.0, "near"]]:
		main.view.center_on(c); main.view.zoom = z[0]
		for i in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "look_%s_%s.png" % [tag, z[1]])
	quit()
