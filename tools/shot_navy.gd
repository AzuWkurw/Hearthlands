extends SceneTree
## Screenshots for build 52: warships fighting by a harbour, a coastal fort's guns, a landing led by a
## general, the harbour's warship controls.
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_navy.gd -- out=/dir
func _shot(path: String) -> void:
	for i in 6: await process_frame
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
	main._start("islands", 3, 5, false, 160, false, {"features": Features.default_ids().filter(func(f): return f != "fog"), "sea_start": true})
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	main.paused = false
	for i in 30: sim.tick(Sim.TICK)
	var q: Sim.Player = null
	var route := []
	for p in sim.players:
		if p.id != 1:
			var r := sim.sea.landing_route(me.hq, p.hq)
			if not r.is_empty():
				q = p; route = r
				break
	if q == null:
		print("no rival by sea")
		quit()
		return
	Diplomacy.declare_war(sim, 1, q.id)
	if sim.get_feature("fog") != null:
		sim.get_feature("fog").reveal_all() if sim.get_feature("fog").has_method("reveal_all") else null
	# a harbour for the rival on its own coast
	var qh: Sim.Bld = null
	for r in range(2, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := q.hq.x + dx
				var y := q.hq.y + dy
				if qh != null or not sim.inb(x, y) or sim.owner[sim.idx(x, y)] != q.id or sim.ter[sim.idx(x, y)] == Sim.WATER or sim.bmap[sim.idx(x, y)] != 0:
					continue
				if sim.sea._moorings(x, y).size() >= 3 and sim.sea.water_path(x, y, me.hq.x, me.hq.y).size() > 1:
					qh = sim.add_bld("harbour", x, y, q, true)
	if qh == null:
		print("no harbour site for the rival")
		quit()
		return
	# a coastal fort by your harbour
	var fort: Sim.Bld = null
	for dy in range(-4, 5):
		for dx in range(-6, 7):
			var x := me.hq.x + dx
			var y := me.hq.y + dy
			if fort == null and absi(dx) + absi(dy) >= 3 and sim.inb(x, y) and sim.ter[sim.idx(x, y)] != Sim.WATER and sim.bmap[sim.idx(x, y)] == 0 \
					and not sim.sea._moorings(x, y).is_empty():
				fort = sim.add_bld("coastal_fort", x, y, me, true)
	if fort != null:
		fort.garrison = 3
	for k in 3:
		sim.naval.launch(me, me.hq)
	# the rival's landing, led by its general, with two warships
	q.reserve = 18; q.rmix = [10, 8, 0, 0, 0, 0]; q.ships = 3; q.general_xp = 20.0
	sim.give(q, "bread", 40.0)
	for k in 2:
		sim.naval.launch(q, qh)
	print("rival warships %d (%s)" % [q.warships, sim.navy.filter(func(z): return int(z.p) == q.id).map(func(z): return [z.x, z.y, z.home, z.esc])])
	me.reserve = 30; me.rmix = [30, 0, 0, 0, 0, 0]
	print("rival landing: '%s'" % sim.military.launch_landing(qh, me.hq, 18))
	var a: Sim.Attack = null
	for x in sim.attacks:
		if x.p == q.id: a = x
	# sail until the fleet nears the harbour and the shooting starts
	var t_end := sim.time + 200.0
	while sim.time < t_end and a != null and sim.attacks.has(a) and sim.military.at_sea(a):
		sim.tick(Sim.TICK)
		if sim.military.column_pos(a).distance_to(Vector2(me.hq.x, me.hq.y)) < 16.0 and sim.naval.fx.size() > 2:
			break
		if int(sim.time * 10) % 50 == 0:
			print("  t %d rival ws %d mine %d fleet %s" % [int(sim.time), q.warships, me.warships, sim.military.column_pos(a)])
	print("fleet %s soldiers %d, warships me %d rival %d, fx %d" % [sim.military.column_pos(a) if a != null else Vector2.ZERO, a.n if a != null else 0, me.warships, q.warships, sim.naval.fx.size()])
	for i in 3:
		main.paused = false
		sim.tick(Sim.TICK)
		if sim.get_feature("fog") != null: sim.get_feature("fog").on_second()
	var mid := Vector2(me.hq.x, me.hq.y)
	if a != null and sim.attacks.has(a):
		mid = sim.military.column_pos(a) + Vector2(-2.5, 2.5)
		print("my warships %s" % [sim.navy.filter(func(z): return int(z.p) == 1).map(func(z): return sim.naval.pos_of(z))])
	main.view.center_on(mid)
	main.view.zoom = 40.0
	main.paused = true
	main._refresh_all()
	await _shot(out + "navy_battle.png")
	# the harbour's controls: warships and escorts
	main.view.sel_id = me.hq.id
	main.view.center_on(Vector2(me.hq.x, me.hq.y))
	main.view.zoom = 34.0
	main._refresh_all()
	await _shot(out + "navy_harbour.png")
	main.view.sel_id = 0
	# the attack window: the general's line
	main.attack_ui.open(q.hq)
	main.view.center_on(Vector2(q.hq.x, q.hq.y))
	await _shot(out + "navy_general.png")
	main.attack_ui.close()
	quit()
