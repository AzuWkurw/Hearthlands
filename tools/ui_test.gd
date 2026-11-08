extends SceneTree
## Headless UI smoke test: new game with a chosen map size, build through the click handler,
## research, save, load, and the tech/save/texture panels.
func _init() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.size_opt.select(3)
	print("start ok: ", main._start("uitest", 4, 6, true, 160, true), " map=", main.sim.w)
	main.setup.visible = false
	main.paused = false
	var sim: Sim = main.sim
	var hq := sim.human().hq
	var placed := []
	for ty in ["woodcutter", "sawmill", "quarry", "house", "scriptorium", "library", "hut"]:
		var done := false
		var last := ""
		for r in range(2, 9):
			if done: break
			for dy in range(-r, r + 1):
				if done: break
				for dx in range(-r, r + 1):
					var why: String = sim.can_place(ty, hq.x + dx, hq.y + dy, 1)
					if why == "":
						main.view.place_type = ty
						main._on_tile(Vector2i(hq.x + dx, hq.y + dy))
						placed.append(ty); done = true; break
					elif why.begins_with("Needs research"):
						last = why
		if not done: placed.append(ty + " (" + last + ")")
	print("placed via UI: ", placed)
	main._open_tech()
	sim.set_research(sim.human(), "monasteries")
	sim.human().rp = 200.0
	main.tech_panel.visible = false
	main.speed = 8.0
	for i in 40:
		await process_frame
		main._process(0.25)
	print("techs after research: ", sim.human().techs.keys(), " library button enabled: ", not main.build_buttons.get("library", Button.new()).disabled if main.cat == "science" else "n/a")
	main._set_cat("science"); main._refresh_all()
	print("library button enabled: ", not main.build_buttons["library"].disabled)
	main._save_game("ui test save")
	var t_saved: float = sim.time
	for i in 40:
		await process_frame
		main._process(0.25)
	main._load_game("ui test save")
	print("loaded back to time %.1f (saved at %.1f), techs %s" % [sim.time, t_saved, sim.human().techs.keys()])
	main._open_saves()
	print("save slots listed: ", main.save_list.get_child_count())
	main.save_panel.visible = false
	main._on_stock_click(_click(), "iron")
	print("resource info: ", main.sel_label.text.split("\n").slice(0, 4))
	var vein_tile := -1
	for i in sim.ore.size():
		if sim.ore[i] == 2 and sim.vein_left(i) > 0:
			vein_tile = i
			break
	main._on_tile(Vector2i(vein_tile % sim.w, vein_tile / sim.w))
	print("tile info: ", main.sel_label.text.split("\n").slice(0, 3))
	main._open_diplomacy()
	print("diplomacy rows: ", main.dip_rivals.get_child_count())
	main._dip_propose(2, "peace")
	print("peace reply: ", main.trade_result.text)
	Diplomacy.set_relation(sim, 1, 3, Diplomacy.PEACE)
	main._fill_diplomacy()
	sim.human().stock.planks = 80.0
	main.trade_who.select(0); main.trade_give.select(main.trade_give.get_item_index(1) if false else 13); main.trade_give_n.value = 30
	main.trade_want.select(2)
	main._trade_quote()
	print("quote: ", main.trade_result.text)
	main._trade_offer()
	print("offer: ", main.trade_result.text)
	main.dip_panel.visible = false
	# logistics: roads, paving, removing, a storehouse and a moved work area
	var me: Sim.Player = sim.human()
	me.stock.stone = 50.0; me.stock.planks = 50.0
	main._set_cat("logistics")
	main._pick_build("@road")
	main._on_tile(Vector2i(hq.x, hq.y))
	var end := Vector2i(-1, -1)
	for dx in range(6, 1, -1):
		var c := Vector2i(hq.x + dx, hq.y + 3)
		if sim.owner[sim.idx(c.x, c.y)] == 1 and sim.bmap[sim.idx(c.x, c.y)] == 0 and sim.road[sim.idx(c.x, c.y)] == 0 and sim.ter[sim.idx(c.x, c.y)] != Sim.WATER and sim.deco[sim.idx(c.x, c.y)] != Sim.D_ROCK:
			end = c
			break
	var before := 0
	for r in sim.road: if r == 1: before += 1
	main._on_tile(end)
	var after := 0
	for r in sim.road: if r == 1: after += 1
	print("road tool: %d -> %d road tiles, chain continues from %s" % [before, after, main.view.road_start])
	main._pick_build("@pave")
	main._on_tile(end)
	print("pave: ", main.hint.text, " stone left ", int(me.stock.stone))
	main._pick_build("@unroad")
	main._on_tile(end)
	print("remove: ", main.hint.text)
	main._cancel_place()
	var wc: Sim.Bld = null
	for b in sim.blds:
		if b.p == 1 and b.ty == "woodcutter": wc = b
	main.view.sel_id = wc.id
	main._refresh_sel()
	print("info: ", main.sel_label.text.split("\n").slice(-4))
	main.view.place_type = "@work"
	main._on_tile(Vector2i(wc.x + 9, wc.y))
	print("too far: ", main.hint.text)
	main.view.place_type = "@work"
	main._on_tile(Vector2i(wc.x + 3, wc.y + 1))
	print("work area now ", sim.work_center(wc), " walk %.1f s" % sim.walk_time(wc))
	var placed_store := false
	for r in range(4, 10):
		if placed_store: break
		for dy in range(-r, r + 1):
			if placed_store: break
			for dx in range(-r, r + 1):
				if sim.can_place("storehouse", hq.x + dx, hq.y + dy, 1) == "":
					main.view.place_type = "storehouse"
					main._on_tile(Vector2i(hq.x + dx, hq.y + dy))
					placed_store = true
					break
	for i in 400: sim.tick(0.1)
	print("storehouse placed=%s, storage now %d, porters free %d, carriers out %d" % [placed_store, int(sim.capacity(me, "planks")), sim.porters_free(me), sim.trips.size()])
	main._set_cat("science"); main._open_textures()
	print("texture ids: ", Tex.all_ids().size())
	# priorities: paused buildings let their worker go; with too few workers, high priority is served first
	main.view.sel_id = wc.id
	main._refresh_sel()
	print("priority buttons: ", main.prio_row.get_child_count() - 1, " pressed=", main.prio_row.get_children().filter(func(c): return c is Button and c.button_pressed).map(func(c): return c.text))
	main._set_prio(Sim.PRIO_PAUSED)
	for i in 12: sim.tick(0.1)
	print("paused: staffed=%s msg=%s" % [wc.staffed, wc.msg])
	var pk := InputEventKey.new(); pk.keycode = KEY_P; pk.pressed = true
	main._unhandled_input(pk)
	print("P again: priority %s staffed=%s" % [Sim.PRIO_NAMES[wc.prio], wc.staffed])
	var workers := sim.realm_blds(me).filter(func(b): return b.state == "ready" and String(b.def.get("worker", "")) == "peasant")
	var last: Sim.Bld = workers[-1]
	me.peasant = me.used_peasant - 1
	sim.staffing(me)
	print("one peasant short: last building %s staffed=%s" % [last.ty, last.staffed])
	sim.set_priority(last, Sim.PRIO_HIGH)
	print("after high priority: %s staffed=%s, staffed peasant buildings %d of %d" % [last.ty, last.staffed, workers.filter(func(b): return b.staffed).size(), workers.size()])
	sim.set_priority(last, Sim.PRIO_NORMAL)
	me.peasant += 20
	sim.staffing(me)
	# demolish asks first: Esc keeps the building, Enter demolishes it
	var n_before := sim.blds.size()
	main.view.sel_id = wc.id
	main._ask_demolish(wc)
	print("confirm shown=%s title=%s" % [main.confirm_panel.visible, main.confirm_title.text])
	print("confirm text: ", main.confirm_text.text.replace("\n", " | "))
	var esc := InputEventKey.new(); esc.keycode = KEY_ESCAPE; esc.pressed = true
	main._unhandled_input(esc)
	print("after Esc: shown=%s still standing=%s" % [main.confirm_panel.visible, sim.by_id.has(wc.id)])
	main._ask_demolish(wc)
	var enter := InputEventKey.new(); enter.keycode = KEY_ENTER; enter.pressed = true
	main._unhandled_input(enter)
	print("after Enter: shown=%s still standing=%s buildings %d -> %d" % [main.confirm_panel.visible, sim.by_id.has(wc.id), n_before, sim.blds.size()])
	quit()


func _click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e
