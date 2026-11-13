extends SceneTree
## Build 40 screenshots: the Buildings window, a tower's upgrade and border settings, a farm's crops
## by season, the geologist's work area.
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b40.gd -- out=/dir
var out := "user://"
var main

func _shot(name: String) -> void:
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("shot40", 2, 5, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 6; me.pers = "balanced"; me.prod = 1.0; me.think = 3.0; me.max_b = 2
	while sim.time < 1500.0:
		for i in 50: sim.tick(Sim.TICK)
	me.ai = false
	main.paused = true
	sim.complete_tech(me, "open_fields"); sim.complete_tech(me, "heavy_plough"); sim.complete_tech(me, "shield_walls")
	# the Buildings window
	main.workers_ui.toggle()
	await _shot("b40_buildings.png")
	main.workers_ui.win.visible = false
	# a tower (or hut) with its upgrade and border settings
	var mil: Sim.Bld = null
	for b: Sim.Bld in sim.realm_blds(me):
		if b.state == "ready" and b.def.has("garrison") and b.ty != "hq" and not sim.upgrades_of(b).is_empty():
			mil = b
	if mil != null:
		main.view.center_on(Vector2(mil.x + 3.0, mil.y + 0.5)); main.view.zoom = 30.0
		main.view.sel_id = mil.id
		main._refresh_all()
		await _shot("b40_tower.png")
	# a farm's crops by season
	var farm: Sim.Bld = null
	for b: Sim.Bld in sim.realm_blds(me):
		if b.ty == "farm" and b.state == "ready":
			farm = b
	if farm != null:
		farm.season_crop = ["vegetables", "", "", "rye"]
		main.view.center_on(Vector2(farm.x + 3.0, farm.y + 0.5)); main.view.zoom = 30.0
		main.view.sel_id = farm.id
		main._refresh_all()
		await _shot("b40_farm.png")
	# the geologist's work area
	var mt := -1
	for i in sim.w * sim.h:
		if mt < 0 and sim.ter[i] == Sim.MOUNT and Vector2(i % sim.w - me.hq.x, i / sim.w - me.hq.y).length() < 16:
			mt = i
	if mt >= 0:
		main.view.sel_id = -1
		main._refresh_all()
		main.view.place_type = "@geologist"
		main.view.ghost = Vector2i(mt % sim.w, mt / sim.w)
		main.view.center_on(Vector2(mt % sim.w + 0.5, mt / sim.w + 0.5)); main.view.zoom = 34.0
		await _shot("b40_geologist.png")
	quit()
