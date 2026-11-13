extends SceneTree
## Screenshots of a battle: a column marching under arrows with its banner, then the fight at the gate.
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_battle.gd -- out=/dir
var main
var sim: Sim

func _shot(out: String, name: String) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name)

func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("battleshot", 1, 5, true); main.setup.visible = false
	sim = main.sim
	var me := sim.human(); var foe := sim.players[1]
	main.side_box.visible = false
	main.guide_ui.box.visible = false
	var mx := me.hq.x; var my := me.hq.y
	for y in range(my + 1, my + 16):
		for x in range(mx - 6, mx + 10):
			if sim.inb(x, y):
				var i := y * sim.w + x
				sim.ter[i] = Sim.GRASS; sim.deco[i] = 0
	sim.changed_tiles.append(sim.idx(mx, my))
	main.view.chunks.mark_all()
	var a := sim.add_bld("tower", mx + 2, my + 3, me, true, 0)
	a.garrison = 4; a.gmix = [0, 0, 4, 0, 0, 0]
	var d := sim.add_bld("tower", mx + 2, my + 11, foe, true, 0)
	d.garrison = 3; d.gmix = [3, 0, 0, 0, 0, 0]; d.archers = 2; d.archer_want = 2
	foe.stock["bows"] = 5.0
	Diplomacy.declare_war(sim, 1, 2)
	var fog = sim.get_feature("fog")
	if fog != null: fog.explored.fill(1); fog.vis.fill(1); fog._img_dirty = true; fog._make_image()
	main.view.center_on(Vector2(mx + 2.5, my + 7.5)); main.view.zoom = 44.0
	for i in 10: await process_frame
	sim.military.launch_attack(a, d, 3)
	main.paused = true
	var got_arrows := false
	while sim.time < 60.0 and not sim.attacks.is_empty():
		sim.tick(Sim.TICK)
		var at = sim.attacks[0]
		if not got_arrows and sim.time - at.arrow_t < 0.55 and sim.time - at.arrow_t > 0.3:
			got_arrows = true
			var cp: Vector2 = sim.military.column_pos(at)
			main.view.center_on(cp + Vector2(0.5, 1.0)); main.view.zoom = 80.0
			await _shot(out, "battle_march.png")
		if at.fighting:
			main.view.center_on(Vector2(d.x + 0.5, d.y + 0.5)); main.view.zoom = 90.0
			for k in 25:
				sim.tick(Sim.TICK)
				await process_frame
			await _shot(out, "battle_gate.png")
			break
		if int(sim.time * 10) % 3 == 0:
			await process_frame
	quit()
