extends SceneTree
## Screenshots of a battle: a column of riflemen and musketeers firing on the way in, pikemen and
## musketeers in the hut firing back, then the fight at the gate.
## xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_battle.gd -- out=/dir
var out := "user://"
func _snap(name: String) -> void:
	for i in 2: await process_frame
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
	main._start("battle", 1, 5, true)
	main.setup.visible = false
	main.log_ui.set_open(false)
	var sim: Sim = main.sim
	var me := sim.human()
	var foe := sim.players[1]
	Diplomacy.set_relation(sim, 1, 2, Diplomacy.WAR)
	var fog = sim.get_feature("fog")
	# a hut of the rival's near our headquarters, open land in between
	var spot := Vector2i(-1, -1)
	for r in range(9, 14):
		for dy in range(-r, r + 1):
			for dx in [-r, r]:
				var x: int = me.hq.x + dx
				var y: int = me.hq.y + dy
				if spot.x < 0 and sim.inb(x, y) and sim.ter[sim.idx(x, y)] == Sim.GRASS and sim.bmap[sim.idx(x, y)] == 0:
					spot = Vector2i(x, y)
	var hut := sim.add_bld("hut", spot.x, spot.y, foe, true)
	hut.era = 3
	hut.garrison = 5; hut.gmix = [0, 0, 0, 3, 2, 0]
	if fog != null:
		fog._reveal(spot.x, spot.y, 6); fog._sig = ""
	var at := Sim.Attack.new()
	at.p = 1; at.src = me.hq.id; at.tgt = hut.id; at.n = 9
	at.amix = [0, 0, 0, 0, 4, 5]
	at.era = Sim.mix_avg(at.amix)
	at.from = Vector2(me.hq.x, me.hq.y); at.to = Vector2(spot.x, spot.y)
	at.t0 = sim.time; at.t1 = sim.time + at.from.distance_to(at.to) * 1.1 + 1.0
	at.vt = [sim.time, sim.time]; at.dvt = [sim.time, sim.time]
	sim.attacks.append(at)
	main.view.center_on((at.from + at.to) / 2.0 + Vector2(0.5, 0.5))
	main.view.zoom = 46.0
	main.paused = true
	var shots := 0
	var fight := false
	for step in 400:
		sim.time += 0.05
		sim.military.attack_tick(0.05)
		if fog != null: fog.vis.fill(1)
		if not sim.attacks.has(at): break
		if (sim.time - at.shot_t < 0.12 or sim.time - at.dshot_t < 0.12) and shots < 2:
			shots += 1
			await _snap("battle_volley_%d" % shots)
		if at.fighting and not fight:
			fight = true
			for i in 8:
				sim.time += 0.05
				sim.military.attack_tick(0.05)
			main.view.center_on(at.to + Vector2(0.5, 0.5))
			await _snap("battle_gate")
	quit()
