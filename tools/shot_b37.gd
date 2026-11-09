extends SceneTree
## Build 37 additions on a town grown for 12 minutes: fire, a workshop's history, archers, trade,
## the minimap filter and town names, achievements, and a tavern's festival.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_b37.gd -- out=/dir
var out := "user://"

func _snap(name: String) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name + ".png")

func _near(sim: Sim, me: Sim.Player, ty: String, r0 := 3) -> Vector2i:
	for r in range(r0, 16):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if sim.can_place(ty, me.hq.x + dx, me.hq.y + dy, 1) == "":
					return Vector2i(me.hq.x + dx, me.hq.y + dy)
	return Vector2i(-1, -1)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = false
	main._start("showcase", 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	main.log_ui.set_open(false)
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 12 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	main.paused = true
	main._refresh_all()
	# 1. a workshop's last 30 minutes, and the town name on the map
	var ws: Sim.Bld = null
	for b in sim.realm_blds(me):
		if b.ty == "sawmill" or (ws == null and b.ty == "woodcutter"): ws = b
	main.view.sel_id = ws.id
	main.view.center_on(Vector2(ws.x, ws.y)); main.view.zoom = 28.0
	main._refresh_all()
	await _snap("b37_history")
	main.view.sel_id = 0
	# 2. a fire among wooden buildings, with bucket carriers from a well
	var fires = sim.get_feature("fires")
	var lit: Sim.Bld = null
	for b in sim.realm_blds(me):
		if lit == null and fires.flammable(b) and b.ty != "well" and Vector2(b.x - me.hq.x, b.y - me.hq.y).length() > 4: lit = b
	fires.ignite(lit)
	for i in 30: sim.tick(Sim.TICK)
	if fires.burning.has(lit.id): fires.burning[lit.id].heat = 0.9
	main.view.center_on(Vector2(lit.x, lit.y)); main.view.zoom = 34.0
	main.view.sel_id = lit.id
	main._refresh_all()
	await _snap("b37_fire")
	main.view.sel_id = 0
	fires.burning.clear()
	# 3. archers in a guard building
	var g: Sim.Bld = null
	for b in sim.realm_blds(me):
		if b.ty != "hq" and b.def.has("garrison") and b.state == "ready": g = b
	if g != null:
		sim.give(me, "bows", 6.0)
		g.archer_want = mini(2, int(g.def.garrison)); g.sally = true
		for i in 40: sim.tick(Sim.TICK)
		main.view.sel_id = g.id
		main.view.center_on(Vector2(g.x, g.y)); main.view.zoom = 30.0
		main._refresh_all()
		await _snap("b37_archers")
		main.view.sel_id = 0
	# 4. trade: a market, peace with a rival, the window with a standing offer
	var ms := _near(sim, me, "market")
	sim.add_bld("market", ms.x, ms.y, me, true, 0)
	Diplomacy.set_relation(sim, 1, 2, Diplomacy.PEACE)
	sim.give(me, "planks", 30.0)
	sim.give(sim.players[1], "ore_iron", 30.0)
	Diplomacy.propose(sim, 1, 2, "trade", {"planks": 10}, {"ore_iron": 6})
	Diplomacy.add_standing(sim, 2, {"planks": 10}, {"ore_iron": 6}, 300.0)
	main._open_diplomacy()
	for i in main.trade_give.item_count:
		if String(main.trade_give.get_item_metadata(i)) == "planks": main.trade_give.select(i)
	for i in main.trade_want.item_count:
		if String(main.trade_want.get_item_metadata(i)) == "ore_iron": main.trade_want.select(i)
	main.diplomacy_ui._update_hint()
	await _snap("b37_trade")
	main.dip_panel.visible = false
	# 5. the minimap showing where planks are made, and town names far out
	main.minimap.set_filter("good:planks")
	for i in main.minimap_filter.item_count:
		if String(main.minimap_filter.get_item_metadata(i)) == "good:planks": main.minimap_filter.select(i)
	main.view.center_on(Vector2(me.hq.x, me.hq.y)); main.view.zoom = 16.0
	main._refresh_all()
	await _snap("b37_minimap_towns")
	main.minimap.set_filter("")
	# 6. a tavern holding a festival: the People panel
	var co = sim.get_feature("contentment")
	var tp := _near(sim, me, "tavern")
	var tav := sim.add_bld("tavern", tp.x, tp.y, me, true, 0)
	co.served[tav.id] = sim.time
	co.cover[1] = co._cover(me)
	co.festival[1] = sim.time + 150.0
	for i in 12: sim.tick(Sim.TICK)
	main.view.sel_id = tav.id
	main.view.center_on(Vector2(tav.x, tav.y)); main.view.zoom = 30.0
	main._refresh_all()
	await _snap("b37_tavern")
	quit()
