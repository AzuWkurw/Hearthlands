extends SceneTree
## Screenshots of the bottom toolbar: xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_toolbar.gd -- out=/dir
var out := "user://"

func shot(name: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name + ".png")

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("showcase", 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 10 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	main.paused = true
	main.log_ui.set_open(false)
	main.view.center_on(Vector2(me.hq.x + 2.0, me.hq.y + 3.0))
	main.view.zoom = 48.0
	main._refresh_all()
	await shot("1_bar")
	main.toolbar._on_cat("raw")
	await shot("2_raw")
	main.toolbar._on_cat("mil")
	await shot("3_mil")
	main.toolbar.close_popup()
	main.toolbar._on_tool("@demolish")
	var b: Sim.Bld = null
	for x in sim.blds:
		if x.p == 1 and x.ty != "hq" and x.state == "ready" and absi(x.x - me.hq.x) < 5 and absi(x.y - me.hq.y) < 5: b = x
	main.view.ghost = Vector2i(b.x, b.y)
	main._refresh_all()
	await shot("4_demolish")
	main._on_tile(Vector2i(b.x, b.y))
	await shot("5_demolish_ask")
	main._cancel_place()
	if main.confirm_panel != null: main.confirm_panel.visible = false
	main.demolish_ui._end_preview()
	print("tools: ", main.toolbar.tool_btns.keys())
	if main.toolbar.tool_btns.has("@scout"):
		main.toolbar._on_tool("@scout")
		main.view.ghost = Vector2i(me.hq.x + 9, me.hq.y - 4)
		main._refresh_all()
		await shot("6_scout")
	quit()
