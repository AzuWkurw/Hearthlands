extends SceneTree
## Hiding problems in the Problems list.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_hide.gd.gd -- out=/dir
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
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 10 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	main.paused = true
	main.log_ui.set_open(false)
	if sim.get_feature("fog") != null: sim.set_feature("fog", false)
	# 1. problems
	main.problems_ui.toggle()
	main._refresh_all()
	main.view.center_on(Vector2(me.hq.x, me.hq.y)); main.view.zoom = 26.0
	for i in 5: await process_frame
	var before: int = main.problems_ui.count
	# hide the first two
	var ps: Array = main.problems_ui.shown(main.problems_ui.problems())
	for p in ps.slice(0, 2):
		main.problems_ui.hide_one(int(p[5]), String(p[1]))
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	print("problems before ", before, " after hiding two ", main.problems_ui.count, " hidden ", main.problems_ui.hidden_now)
	root.get_texture().get_image().save_png(out + "problems_hidden.png")
	main.problems_ui.show_hidden = true
	main.problems_ui.refresh()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "problems_show_hidden.png")
	print("with show hidden: count ", main.problems_ui.count)
	quit()
