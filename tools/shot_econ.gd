extends SceneTree
## Screenshots for build 53 from a save: the bottleneck finder, the chain overlay, the market window.
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_econ.gd -- out=/dir save=user_save
func _shot(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var out := "user://"
	var save := "user_save"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
		if a.begins_with("save="): save = a.substr(5)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 3: await process_frame
	main._load_game(save)
	main.setup.visible = false
	var sim: Sim = main.sim
	main.paused = false
	# a few minutes so prices and children get going
	for i in int(240.0 / Sim.TICK): sim.tick(Sim.TICK)
	main.paused = true
	main.neck_ui.toggle()
	await _shot(out + "econ_bottlenecks.png")
	main.neck_ui.win.visible = false
	# the chain of the good the finder puts first (or bread)
	var good := "bread"
	for e in UiBottlenecks.find(sim, sim.human()):
		if String(e[3]) != "" and String(e[3]) != "food" and not String(e[1]).contains("nothing of yours"):
			good = String(e[3]); break
	main.view.chain_res = good
	var me := sim.human()
	var at := Vector2(me.hq.x, me.hq.y)
	for b in sim.realm_blds(me):
		if (b.def.get("in", {}) as Dictionary).has(good):
			at = Vector2(b.x, b.y); break
	main.view.center_on(at)
	main.view.zoom = 11.0
	main._refresh_all()
	await _shot(out + "econ_chain.png")
	main.view.chain_res = ""
	main.market_ui.toggle()
	await _shot(out + "econ_market.png")
	print("good %s" % good)
	quit()
