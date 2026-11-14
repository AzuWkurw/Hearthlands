extends SceneTree
## Screenshots for build 56: notices you can click, the sea and supplies guide.
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b56.gd -- out=/dir
func _shot(path: String) -> void:
	for i in 8: await process_frame
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
	main._start("notices", 3, 5, false, 128, false, {"features": Features.default_ids()})
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	for i in 30: sim.tick(Sim.TICK)
	main.paused = true
	var q := sim.players[1]
	sim.emit_log("%s attacks your guard hut with 8 soldiers!" % q.name, Color("e0603a"), Vector2i(me.hq.x + 6, me.hq.y + 2))
	sim.emit_log("Your fleet was sunk at sea.", Color("e08a6a"), Vector2i(me.hq.x - 9, me.hq.y + 5))
	sim.emit_log("Your soldiers at the gate have run out of food and are starving.", Color("e08a6a"), Vector2i(q.hq.x, q.hq.y))
	sim.emit_log("A peasant became an artisan.", Color("86ad5c"), Vector2i(me.hq.x, me.hq.y))
	main.view.center_on(Vector2(me.hq.x, me.hq.y))
	main.view.zoom = 30.0
	main._refresh_all()
	await _shot(out + "b56_notices.png")
	main.sea_guide_ui.open()
	await _shot(out + "b56_sea_guide.png")
	quit()
