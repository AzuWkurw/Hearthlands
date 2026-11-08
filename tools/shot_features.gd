extends SceneTree
## Screenshots of the optional features: xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_features.gd -- out=/dir
## Plays an AI-run realm through a year and saves pictures of summer, rain, winter snow and the windows.

var main
var out := "user://"


func _snap(name: String) -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name + ".png")
	print("saved ", name)


func _run_to(sim: Sim, t: float) -> void:
	while sim.time < t:
		sim.tick(Sim.TICK)


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	root.size = Vector2i(1600, 900)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 4: await process_frame
	main._start("seasons", 3, 6, true)
	main.setup.visible = false
	main.log_ui.set_open(false)
	var sim: Sim = main.sim
	var me: Sim.Player = sim.players[0]
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.odds = 99.0; me.grace = 1e9; me.attack_t = 1e9
	var cl = sim.get_feature("seasons")
	_run_to(sim, 8.5 * 60.0)
	var hq := me.hq
	main.view.center_on(Vector2(hq.x + 0.5, hq.y + 2.5))
	main.view.zoom = 30.0
	var k: int = cl.biome_of(me)
	cl.weather[k] = "clear"
	main._refresh_all()
	await _snap("f_summer")
	cl.weather[k] = "rain"
	await _snap("f_rain")
	main.view.zoom = 9.0
	await _snap("f_biomes_far")
	main.view.zoom = 30.0
	_run_to(sim, 17.0 * 60.0)
	cl.weather[k] = "snow"
	for b in 4:
		cl._snow[b] = cl._snow_target(b)
	main._refresh_all()
	await _snap("f_winter")
	main.view.zoom = 9.0
	await _snap("f_winter_far")
	main.view.zoom = 30.0
	cl._toggle_window()
	main._refresh_all()
	await _snap("f_climate_window")
	cl._toggle_window()
	# a smaller window: the top bar wraps, and a long building info box stays on screen
	root.size = Vector2i(1280, 720)
	var pick: Sim.Bld = null
	for b in sim.blds:
		if b.p == 1 and b.def.has("mine") and b.state == "ready":
			pick = b
	if pick == null:
		for b in sim.blds:
			if b.p == 1 and b.ty == "farm":
				pick = b
	if pick != null:
		main.view.sel_id = pick.id
		main.view.center_on(Vector2(pick.x, pick.y))
	main._refresh_all()
	await _snap("f_info_small")
	root.size = Vector2i(1600, 900)
	# health, tools and events
	var dz = sim.get_feature("diseases")
	if dz != null:
		dz.outbreak(me, "flu")
	for b in sim.blds:
		if b.p == 1 and b.ty == "woodcutter" and b.staffed:
			main.view.sel_id = b.id
			main.view.center_on(Vector2(b.x, b.y))
			break
	main._refresh_all()
	await _snap("f_tools_health")
	var ev = sim.get_feature("events")
	if ev != null:
		ev._toggle()
		await _snap("f_events_window")
		ev._toggle()
	main._open_settings()
	await _snap("f_settings_features")
	root.size = Vector2i(1280, 720)
	await _snap("f_settings_small")
	main.set_panel.visible = false
	main._open_tech()
	await _snap("f_research_small")
	quit()
