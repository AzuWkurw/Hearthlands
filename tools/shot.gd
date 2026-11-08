extends SceneTree
## Renders screenshots: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot.gd -- out=/path/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "shot_setup.png")
	main._start("showcase", 3, 6, true)
	main.setup.visible = false
	var sim: Sim = main.sim
	var me: Sim.Player = sim.players[0]
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.odds = 99.0; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 9 * 60.0:
		sim.tick(Sim.TICK)
	me.ai = false
	var hq := me.hq
	main.view.center_on(Vector2(hq.x + 0.5, hq.y + 2.5))
	main.view.zoom = 34.0
	main.view.sel_id = hq.id
	main._set_cat("food")
	main._refresh_all()
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "shot_game.png")
	main.view.zoom = 9.0
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "shot_far.png")
	main.view.zoom = 34.0
	for t in ["heavy_plough", "monasteries", "feudalism", "watermills", "guilds", "papermaking"]:
		sim.complete_tech(me, t)
	sim.set_research(me, "printing_press")
	me.rp = 300.0
	main._open_tech()
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "shot_research.png")
	main.tech_panel.visible = false
	main._save_game("Showcase at minute 9")
	main._open_saves()
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "shot_saves.png")
	main.save_panel.visible = false
	main.setup.visible = true
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "shot_setup.png")
	quit()
