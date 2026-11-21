extends SceneTree
## Screenshots for judging the map's look: a town at night (with Day and night on) and a corner of the
## map, where it meets the dark beyond its edge.
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_gfx.gd -- out=/dir [tag=now]
func _snap(out: String) -> void:
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("saved ", out)

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
	# game time 1200 is the middle of the night (MapView.DAY_LENGTH 480)
	while sim.time < 1200.0:
		for i in 50: sim.tick(Sim.TICK)
	me.ai = false
	main.side_box.visible = false
	main.guide_ui.box.visible = false
	main.log_ui.set_open(false)
	var c := Vector2(me.hq.x + 3.5, me.hq.y + 2.5)
	main.view.daynight = true
	main.view.center_on(c); main.view.zoom = 34.0
	await _snap(out + "night_%s.png" % tag)
	main.view.daynight = false
	# the bottom right corner of the map
	main.view.center_on(Vector2(sim.w - 6, sim.h - 4)); main.view.zoom = 24.0
	await _snap(out + "edge_%s.png" % tag)
	quit()
