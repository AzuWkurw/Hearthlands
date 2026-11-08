extends SceneTree
## Build 34 additions: the Problems list with minimap alerts, and the attack window.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_b34.gd -- out=/dir
func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = false
	main._start("showcase", 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 10 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	main.paused = true
	main.log_ui.set_open(false)
	if sim.get_feature("fog") != null: sim.set_feature("fog", false)
	# 1. problems
	main.problems_ui.toggle()
	main._refresh_all()
	main.view.center_on(Vector2(me.hq.x, me.hq.y)); main.view.zoom = 26.0
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	print("problems: ", main.problems_ui.count)
	root.get_texture().get_image().save_png(out + "problems.png")
	main.problems_ui.toggle()
	# 2. the attack window: put up a manned tower of ours near a rival's military building
	var tgt: Sim.Bld = null
	var bd := 1e9
	for b in sim.blds:
		if b.p != 1 and sim.is_mil(b) and b.state == "ready" and b.ty != "hq":
			var d := Vector2(b.x - me.hq.x, b.y - me.hq.y).length()
			if d < bd: bd = d; tgt = b
	var placed: Sim.Bld = null
	for r in range(6, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x: int = tgt.x + dx; var y: int = tgt.y + dy
				if placed == null and sim.inb(x, y) and sim.bmap[sim.idx(x, y)] == 0 and sim.ter[sim.idx(x, y)] == Sim.GRASS and sim.owner[sim.idx(x, y)] == 0 and sim.deco[sim.idx(x, y)] == 0:
					placed = sim.add_bld("tower", x, y, me, true, 0)
	placed.garrison = 7
	placed.gmix = [2, 3, 2, 0, 0, 0]
	tgt.garrison = maxi(tgt.garrison, 3)
	sim.recompute_territory()
	main.view.center_on(Vector2((placed.x + tgt.x) / 2.0, (placed.y + tgt.y) / 2.0))
	print("war ", Diplomacy.at_war(sim, 1, tgt.p), " placed alive ", not placed.dead, " dist ", Vector2(tgt.x - placed.x, tgt.y - placed.y).length(), " sources ", main.attack_ui.sources(tgt).size())
	if not Diplomacy.at_war(sim, 1, tgt.p): Diplomacy.declare_war(sim, 1, tgt.p)
	main._on_tile(Vector2i(tgt.x, tgt.y))
	main._refresh_all()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "attack.png")
	main.attack_ui.slider.value = 4
	(main.attack_ui.kinds[2] as CheckBox).button_pressed = false
	main.attack_ui._go()
	var a: Sim.Attack = sim.attacks[-1] if not sim.attacks.is_empty() else null
	print("attack sent: ", a.n if a else -1, " mix ", a.amix if a else [], " tower left ", placed.garrison)
	quit()
