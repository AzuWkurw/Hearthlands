extends SceneTree
## Screenshots of the fog of war, a scout, a watch tower and construction sites waiting for materials.
## xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_fog.gd -- out=/dir
var out := "user://"
func _snap(name: String) -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name + ".png")
	print("saved ", name)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 4: await process_frame
	main._start("fogshot", 3, 5, true)
	main.setup.visible = false
	main.log_ui.set_open(false)
	var sim: Sim = main.sim
	var me := sim.human()
	var fog = sim.get_feature("fog")
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 6 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	me.scout = 3
	# a watch tower near the edge of the realm
	var hq := me.hq
	var best := Vector2i(-1, -1)
	var bd := -1.0
	for y in sim.h:
		for x in sim.w:
			if sim.can_place("watch_tower", x, y, 1) == "":
				var d := Vector2(x - hq.x, y - hq.y).length()
				if d > bd: bd = d; best = Vector2i(x, y)
	sim.place("watch_tower", best.x, best.y, me)
	var tower := sim.bld_at(best.x, best.y)
	tower.state = "ready"; tower.prog = 0.0
	fog.send_scout(me, sim.players[1].hq.x, sim.players[1].hq.y)
	for i in 300: sim.tick(Sim.TICK)
	# two new sites, one with no stone to come
	main.view.center_on(Vector2(hq.x + 0.5, hq.y + 1.5))
	main.view.zoom = 30.0
	main._refresh_all()
	await _snap("fog_close")
	main.view.zoom = 9.0
	main.view.center_on(Vector2(sim.w / 2.0, sim.h / 2.0))
	await _snap("fog_far")
	var wk = fog.walks[0] if fog.walks.size() > 0 else null
	if wk != null:
		var at: Vector2 = fog.walk_pos(wk)
		main.view.center_on(at)
		main.view.zoom = 28.0
		await _snap("fog_scout")
	main.view.center_on(Vector2(tower.x, tower.y))
	main.view.zoom = 20.0
	main.view.sel_id = tower.id
	main._refresh_all()
	await _snap("fog_tower")
	quit()
