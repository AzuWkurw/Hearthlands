class_name UiInfo
extends RefCounted
## The building info box: what the selected building is doing, and its buttons (priority, stores, garrison...).
## Part of the interface: main.gd holds the shared state and calls in here; the functions reach
## the rest of the game through `main` (main.gd keeps a one-line wrapper for each, so callers did
## not change).

var main: Main


func _init(p_main: Main) -> void:
	main = p_main


func _refresh_sel() -> void:
	for c in main.sel_actions.get_children():
		c.queue_free()
	var gb: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
	if not (gb != null and gb.p == 1 and gb.ty != "hq" and gb.def.has("garrison") and gb.state == "ready") and main._gar_sig != "":
		main._gar_sig = ""
		for c in main.garrison_box.get_children():
			main.garrison_box.remove_child(c)
			c.queue_free()
	for c in main.prio_row.get_children():
		main.prio_row.remove_child(c)
		c.queue_free()
	var b: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
	main.sel_box.visible = b != null or main.sel_res != "" or main.view.sel_tile >= 0
	if b == null and main.sel_res != "":
		main.sel_label.text = main._res_info(main.sel_res)
		main.sel_actions.add_child(main._label("Keep in stock:", 14, Main.DIM))
		main.sel_actions.add_child(main._target_ctrl(main.sel_res))
		var res := main.sel_res
		var cb := main._button("Production chain", func(): main.chain_ui.open(res))
		cb.tooltip_text = "Who makes it, what they need, who uses it, and where the chain is short"
		main.sel_actions.add_child(cb)
		return
	if b == null and main.view.sel_tile >= 0:
		main.sel_label.text = main._tile_info(main.view.sel_tile)
		return
	if b == null:
		return
	var d := b.def
	var owner := main.sim.players[b.p - 1]
	var t := "[b]%s[/b]%s%s\n%s\n" % [String(d.name), (" of " + b.town) if b.town != "" else "", "" if b.p == 1 else " (" + owner.name + ")", main.sim.status(b)]
	if b.state == "build" and b.mat_total > 0:
		t += "Materials: %s\n[color=#9a9c88]Carriers bring them from the stores as the site needs them; nothing is set aside before.[/color]\n" % main.sim.materials_text(b)
	# people walking here (a builder, the worker, soldiers), with how long until they arrive
	var coming: Array = []
	for tr0: Sim.Trip in main.sim.trips:
		if tr0.site == b.id and (tr0.kind == "builder" or tr0.kind == "worker" or tr0.kind == "soldier"):
			coming.append("%s in %d s" % ["a builder" if tr0.kind == "builder" else ("the worker" if tr0.kind == "worker" else "a soldier"), maxi(1, ceili(tr0.t1 - main.sim.time))])
	if not coming.is_empty():
		coming.sort()
		t += "On the way: %s%s\n" % [", ".join(coming.slice(0, 4)), " and %d more" % (coming.size() - 4) if coming.size() > 4 else ""]
	if b.reno_to >= 0 and b.mat_total > 0:
		t += "Renovation materials: %s\n" % main.sim.materials_text(b).replace("/" , " of ")
	if b.era >= 0:
		var my_age: int = owner.age
		t += "Style: %s%s\n" % [GameData.age_name(b.era), (" [color=#9a9c88](its realm is in the %s age: it can be renovated)[/color]" % GameData.age_name(my_age)) if b.era < my_age and b.reno_to < 0 and b.state == "ready" and b.p == 1 else ""]
		if (main.sim.reno_queue.get(b.p, []) as Array).has(b.id):
			t += "Waiting its turn to be renovated.\n"
	if b.state == "ready" and main.sim.is_mil(b) and main.sim.own_def(b) > 0:
		t += "Soldiers: %s\n" % Sim.mix_text(main.sim.military.mix_of(b))
		if b.p == 1:
			t += "[color=#9a9c88]Each kind has its strengths (Military tab: Soldier kinds). Defenders always send their best answer to each attacker.[/color]\n"
	if d.has("info"):
		t += "[color=#9a9c88]%s[/color]\n" % String(d.info)
	if d.has("in"):
		t += "Uses: %s\n" % ", ".join((d["in"] as Dictionary).keys().map(func(k): return "%d %s" % [int(d["in"][k]), GameData.res_name(k).to_lower()]))
	if Crops.is_farm(b):
		var cn := Crops.now(main.sim, b)
		var co: Dictionary = Crops.LIST[cn].out
		if b.state == "ready":
			t += Crops.fields_line(main.sim, b) + "\n"
		t += "Sows: [b]%s[/b]%s, %s a harvest\n[color=#9a9c88]Growth by season: %s[/color]\n" % [String(Crops.LIST[cn].name), " (winter rotation)" if cn != Crops.chosen(b) else "", ", ".join(co.keys().map(func(k): return "%d %s" % [int(co[k]), GameData.res_name(k).to_lower()])), Crops.season_text(cn)]
	elif d.has("out"):
		t += "Makes: %s\n" % ", ".join((d.out as Dictionary).keys().map(func(k): return "%d %s" % [int(d.out[k]), GameData.res_name(k).to_lower()]))
	# goods carried here from the stores for its work
	if d.has("in") and b.state == "ready" and b.p == 1:
		var parts := []
		var keys := {}
		for k in b.inbuf: keys[k] = true
		for k in b.incoming: keys[k] = true
		for k in keys:
			var way := int(b.incoming.get(k, 0))
			parts.append("%d %s%s" % [int(b.inbuf.get(k, 0)), GameData.res_name(k).to_lower(), (" (+%d on the way)" % way) if way > 0 else ""])
		t += "Here for its work: %s\n" % (", ".join(parts) if not parts.is_empty() else "nothing yet (carriers fetch it from the nearest store that has it)")
	# a store's own goods
	if main.sim.is_store(b) and b.p == 1 and b.state == "ready":
		var items := b.inv.keys().filter(func(k): return float(b.inv[k]) >= 1.0)
		items.sort_custom(func(x, y): return float(b.inv[x]) > float(b.inv[y]))
		var total := 0
		for k in items: total += int(b.inv[k])
		t += "In this store: [b]%d goods[/b]%s\n" % [total, (": " + ", ".join(items.map(func(k): return "%d %s" % [int(b.inv[k]), GameData.res_name(k).to_lower()]))) if not items.is_empty() else ""]
	# idle people waiting here
	if b.p == 1 and b.state == "ready":
		var av := main.sim.home_avail(main.sim.human())
		var here := []
		for cls in ["peasant", "artisan", "scout", "soldier"]:
			var n := int((av[cls] as Dictionary).get(b.id, 0))
			if n > 0:
				here.append("%d %s%s" % [n, cls, "" if n == 1 else "s"])
		var room := int(d.get("residence", 0))
		if not here.is_empty() or room > 0:
			t += "Waiting here: %s%s\n" % [", ".join(here) if not here.is_empty() else "nobody", (" (room for %d)" % room) if room > 0 else ""]
	if d.has("worker") and b.state == "ready" and String(d.worker) != "scout":
		var tr := GameData.trade(b.ty)
		if b.staffed:
			var lv := Sim.level(b.wxp, Sim.WORKER_XP)
			var rank := "master " if lv >= 5 else ("" if lv >= Sim.SPECIALIST else "apprentice ")
			t += "Worker: %s%s (%s), trade: %s%s\n" % [rank, GameData.trade_title(tr), String(d.worker), GameData.trade_name(tr), " [color=#e0b060](on his way here)[/color]" if b.worker == 1 else ""]
		else:
			t += "Worker: %s (missing)\n" % String(d.worker)
		var tool := main.sim.tool_of(b)
		if tool != "":
			t += "New workers need %s (%d in store)\n" % [GameData.res_name(tool).to_lower(), int(main.sim.human().stock.get(tool, 0.0))]
		if b.staffed and d.has("cycle"):
			t += _xp_line("Worker", b.wxp, Sim.WORKER_XP, "work cycles", roundi(Sim.LEVEL_BONUS * 100))
			t += "[color=#9a9c88]Experience counts only in %s work; idle %s are hired first.[/color]\n" % [GameData.trade_name(tr).to_lower(), GameData.trade_plural(tr)]
	if b.state == "ready" and main.sim.is_mil(b) and main.sim.own_def(b) > 0:
		t += _xp_line("Soldiers here", main.sim.players[b.p - 1].res_xp if b.ty == "hq" else b.sxp, Sim.SOLDIER_XP, "battle experience", 3)
	if b.p == 1 and main.sim.is_mil(b):
		t += "[color=#d8aa4a]Click an enemy military building within the dashed circle to attack with all but one soldier.[/color]\n"
	var waiting := 0
	for r in b.out_buf:
		waiting += int(b.out_buf[r])
	if waiting > 0:
		t += "Waiting for carriers: %d goods\n" % waiting
	if b.state == "ready" and b.cyc > 0.0 and not main.sim.is_store(b):
		var dist := main.sim.net_dist(b.p, main.sim.idx(b.x, b.y))
		t += "Road to the nearest store: %s\n" % ("none, build a road" if dist >= Sim.INF else "%d s walk" % roundi(dist))
	var wr := main.sim.work_radius(b)
	if wr > 0:
		var wc := main.sim.work_center(b)
		var moved := wc != Vector2i(b.x, b.y)
		t += "Work area: %d tiles across%s\n" % [wr * 2 + 1, (", moved %d tiles away (+%.1f s walking per cycle)" % [roundi(Vector2(wc.x - b.x, wc.y - b.y).length()), main.sim.walk_time(b)]) if moved else ", around the building"]
	for f: Feature in main.sim.features:
		for line in f.building_lines(b):
			t += line + "\n"
	if b.p == 1 and b.def.has("mine") and b.dry_t >= 0.0:
		if main.settings.demolish_dry_mines:
			t += "[color=#e0b060]Its vein has run dry: it will be demolished in %d s (switch this off in Settings).[/color]\n" % maxi(0, ceili(Main.DRY_MINE_WAIT - (main.sim.time - b.dry_t)))
		else:
			t += "[color=#e0b060]Its vein has run dry: demolish it to get back 40%% of its cost.[/color]\n"
	if b.p == 1 and main.sim.has_priority(b):
		t += "Priority: [b]%s[/b]. %s\n" % [Sim.PRIO_NAMES[b.prio], Main.PRIO_HELP[b.prio]]
	main.sel_label.text = t
	if b.p == 1 and b.ty != "hq" and b.def.has("garrison") and b.state == "ready":
		_garrison_ui(b)
	if b.p == 1 and main.sim.has_priority(b):
		main.prio_row.add_child(main._label("Priority", 14, Main.DIM))
		for pr in [Sim.PRIO_HIGH, Sim.PRIO_NORMAL, Sim.PRIO_LOW, Sim.PRIO_PAUSED]:
			var pb := main._button(Sim.PRIO_NAMES[pr], _set_prio.bind(pr))
			pb.toggle_mode = true
			pb.set_pressed_no_signal(b.prio == pr)
			pb.tooltip_text = Main.PRIO_HELP[pr]
			main.prio_row.add_child(pb)
	# a store's town name, which you can change
	if b.p == 1 and b.town != "":
		var rn := main._button(tr("Rename %s") % b.town, func():
			var dlg := AcceptDialog.new()
			dlg.title = "Rename the town"
			dlg.theme = UiLog.window_theme()
			var le := LineEdit.new()
			le.text = b.town
			le.custom_minimum_size = Vector2(260, 0)
			dlg.add_child(le)
			main.add_child(dlg)
			var done := func():
				var nn := le.text.strip_edges()
				if nn != "":
					b.town = nn.left(24)
				dlg.queue_free()
				_refresh_sel()
			dlg.confirmed.connect(done)
			le.text_submitted.connect(func(_t): done.call())
			dlg.canceled.connect(dlg.queue_free)
			dlg.popup_centered()
			le.grab_focus()
			le.select_all())
		rn.tooltip_text = "Each store is a town; its name shows on the map and in messages about the land around it."
		main.prio_row.add_child(rn)
	# a store: normal, gather goods here, or send them away
	if b.p == 1 and main.sim.is_store(b) and b.state == "ready" and main.sim.logistics.stores_of(main.sim.human()).size() > 1:
		main.prio_row.add_child(main._label("This store", 14, Main.DIM))
		var helps := ["Takes goods from nearby buildings and passes on what it has too much of.", "Other stores send their goods here, a load at a time.", "Takes nothing new; its goods are carried to other stores."]
		for k in 3:
			var sb := main._button(["Normal", "Gather here", "Send away"][k], func():
				var bb: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
				if bb:
					bb.policy = k
					_refresh_sel())
			sb.toggle_mode = true
			sb.set_pressed_no_signal(b.policy == k)
			sb.tooltip_text = helps[k]
			main.prio_row.add_child(sb)
	# a workshop: how many work cycles of inputs to keep here
	if b.p == 1 and b.state == "ready" and b.def.has("in") and b.def.has("cycle"):
		main.prio_row.add_child(main._label("Keep inputs for", 14, Main.DIM))
		for k in [1, 2, 4]:
			var kb := main._button(tr("%d cycle%s") % [k, "s" if k > 1 else ""], func():
				var bb: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
				if bb:
					bb.keep = k
					_refresh_sel())
			kb.toggle_mode = true
			kb.set_pressed_no_signal((b.keep if b.keep > 0 else 2) == k)
			kb.tooltip_text = tr("Carriers bring enough for %d work cycle%s (food for %d). More keeps it working through gaps; less leaves more in the stores for others.") % [k, "s" if k > 1 else "", maxi(1, k / 2)]
			main.prio_row.add_child(kb)
	# the numbers of the priority windows for this kind and its goods (build 54), changed from here too
	if b.p == 1 and b.state == "ready" and (String(b.def.get("worker", "")) != "" or b.def.has("in")):
		_prio_numbers(b)
	# a farm: which crop it sows (seeds come from research)
	if b.p == 1 and Crops.is_farm(b) and b.state != "dead":
		_crop_ui(b)
	# a harbour: ships, and an expedition to another coast
	if b.p == 1 and b.ty == "harbour" and b.state == "ready":
		var me := main.sim.human()
		main.prio_row.add_child(main._label("Ships: %d (%d at sea)" % [me.ships, me.ships_out], 14, Main.DIM))
		var eb := main._button("Send an expedition", func():
			main.expedition_from = b.id
			main.view.place_type = "@expedition"
			main._show_hint("Click a free coast across the water (Esc to stop).", 4.0))
		eb.tooltip_text = "A ship, 4 planks and 2 stone from this harbour and a soldier from the headquarters sail to another coast and found a harbour there, with land around it."
		eb.disabled = main.sim.sea.free_ships(me) < 1
		main.sel_actions.add_child(eb)
	# warships: how many, and whether they sail with your landings
	if b.p == 1 and b.state == "ready" and (main.sim.sea.is_harbour(b) or b.ty == "naval_yard") and (me_warships() > 0 or b.ty == "naval_yard"):
		var me2 := main.sim.human()
		main.prio_row.add_child(main._label(tr("Warships: %d of %d") % [me2.warships, SimNavy.MAX_WARSHIPS], 14, Main.DIM))
		var xb := main._button(tr("Escort landings: %s") % (tr("on") if me2.escort else tr("off")), func():
			main.sim.human().escort = not main.sim.human().escort
			_refresh_sel())
		xb.tooltip_text = tr("When on, up to 3 free warships sail with each landing you send, to fight off enemy warships and coastal guns on the way. When off, they all stay to guard your harbours.")
		main.sel_actions.add_child(xb)
	# a building site: ring a bell when it is finished
	if b.p == 1 and (b.state == "build" or b.reno_to >= 0):
		var wb := main._button(tr("Bell when done: %s") % ("on" if main.watch.has(b.id) else "off"), func():
			var bb: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
			if bb:
				if main.watch.has(bb.id): main.watch.erase(bb.id)
				else: main.watch[bb.id] = true
				_refresh_sel())
		wb.tooltip_text = "Play a sound and say so when this building is finished."
		main.sel_actions.add_child(wb)
	if b.p == 1 and b.ty != "hq" and b.state == "ready" and not main.sim.is_mil(b) and not b.def.get("claim_only", false):
		var mb := main._button("Move building", func():
			var bb: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
			if bb:
				main.moving_id = bb.id
				main.view.place_type = bb.ty
				main.view.door = bb.door if bb.door >= 0 else 0
				main._show_hint(tr("Click where the new %s should stand. The old one keeps working until the new one is finished.") % String(bb.def.name).to_lower(), 4.0)
				main._refresh_build())
		mb.tooltip_text = "Build this building again somewhere else (full cost). The old one keeps working until the new one is finished, then it is pulled down and hands over its settings; 40% of its materials come back."
		main.sel_actions.add_child(mb)
	if b.p == 1 and wr > 0 and b.state == "ready":
		main.sel_actions.add_child(main._button("Move work area", func():
			main.view.place_type = "@work"
			main._refresh_build()))
		if b.work.x >= 0:
			main.sel_actions.add_child(main._button("Reset work area", func():
				var bb: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
				if bb:
					main.sim.set_work_area(bb, bb.x, bb.y)
					_refresh_sel()))
	# upgrading where it stands (the mule station to an ox cart yard; military ones have their own row)
	if b.p == 1 and b.state == "ready" and b.def.has("upgrade_to"):
		if b.upg != "":
			main.sel_actions.add_child(main._label(tr("Upgrading to a %s: %d%%") % [String(GameData.bld[b.upg].name).to_lower(), roundi(b.reno_prog * 100.0)], 13, Color("9fd0e8")))
		elif b.reno_to < 0:
			var ups := main.sim.upgrades_of(b)
			for ty in ups:
				var cost := main.sim.upgrade_cost(b, ty)
				var ub := main._button(tr("Upgrade to %s") % String(GameData.bld[ty].name), func():
					var bb: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
					if bb:
						var r := main.sim.upgrade(bb, ty)
						main._show_hint(r if r != "" else tr("Upgrade started: carriers bring %s.") % Diplomacy.goods_text(main.sim.upgrade_cost(bb, ty)), 3.5)
						_refresh_sel())
				ub.tooltip_text = tr("Rebuild it as a %s where it stands. Costs %s.\n%s") % [String(GameData.bld[ty].name).to_lower(), Diplomacy.goods_text(cost), String(GameData.bld[ty].get("info", ""))]
				main.sel_actions.add_child(ub)
			for ty in b.def.upgrade_to:
				if not ups.has(ty) and GameData.bld.has(ty) and GameData.bld[ty].has("tech"):
					main.sel_actions.add_child(main._label(tr("Upgrade to %s after studying %s") % [String(GameData.bld[ty].name), GameData.tech_name(GameData.bld[ty].tech)], 12, Main.DIM))
	if b.p == 1 and b.state == "ready":
		var why := main.sim.can_renovate(b)
		if why == "":
			var rb := main._button("Renovate", func():
				var bb: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
				if bb:
					var r := main.sim.renovate(bb)
					main._show_hint(r if r != "" else ("Renovation starts: carriers bring half the building's materials." if bb.reno_to >= 0 else "Renovation queued: two run at a time."), 3.0)
					_refresh_sel())
			rb.tooltip_text = tr("Rebuild it in the %s style: half its building cost, carried here, and half its building time. Work stops meanwhile; the worker keeps his job.") % GameData.age_name(main.sim.human().age)
			main.sel_actions.add_child(rb)
			var same := 0
			for x: Sim.Bld in main.sim.realm_blds(main.sim.human()):
				if x.ty == b.ty and main.sim.can_renovate(x) == "":
					same += 1
			if same > 1:
				main.sel_actions.add_child(main._button(tr("Renovate all %d") % same, func():
					var bb: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
					if bb:
						main._show_hint(tr("%d %s queued for renovation; two at a time.") % [main.sim.renovate_all(main.sim.human(), bb.ty), String(bb.def.name).to_lower()], 3.0)
						_refresh_sel()))
	if b.p == 1 and b.ty != "hq":
		main.sel_actions.add_child(main._button("Demolish", func():
			var bb: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
			if bb:
				main._ask_demolish(bb)))


## Changes the selected building's priority (also bound to Page Up / Page Down and P).
func _set_prio(pr: int) -> void:
	var b: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
	if b == null or b.p != 1 or not main.sim.has_priority(b):
		return
	main.sim.set_priority(b, pr)
	main._show_hint(tr("%s: priority %s.") % [String(b.def.name), Sim.PRIO_NAMES[b.prio].to_lower()], 2.5)
	_refresh_sel()


func _xp_line(who: String, xp: float, table: Array, unit: String, pct: int) -> String:
	var lv := Sim.level(xp, table)
	var nxt := "max level" if lv >= table.size() else "%d / %d %s to level %d" % [int(xp), int(table[lv]), unit, lv + 1]
	return "%s level [b]%d[/b] (%s), %+d%% %s\n" % [who, lv, nxt, (lv - 1) * pct, "win chance" if table == Sim.SOLDIER_XP else "speed"]


## The crop choice of your farm b: a button for each seed, locked ones greyed with the study that
## unlocks them, and the winter rye rotation.
func _crop_ui(b: Sim.Bld) -> void:
	var me := main.sim.human()
	main.prio_row.add_child(main._label("Crop", 14, Main.DIM))
	for id in Crops.ORDER:
		var cd: Dictionary = Crops.LIST[id]
		if String(cd.need) != "" and main.sim.get_feature(String(cd.need)) == null:
			continue
		var ok := Crops.known(main.sim, me, id)
		var cb := main._button(String(cd.name), func():
			var bb: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
			if bb:
				bb.crop = id
				main._click()
				_refresh_sel())
		cb.toggle_mode = true
		cb.set_pressed_no_signal(Crops.chosen(b) == id)
		cb.disabled = not ok
		var tip := "%s\n%s\nGrowth by season: %s" % [String(cd.name), String(cd.info), Crops.season_text(id)]
		if not ok:
			tip += "\nLocked: study %s to get the seed." % String(GameData.techs[String(cd.tech)].name)
		cb.tooltip_text = tip
		main.prio_row.add_child(cb)
	# a crop for each season (blank: the main crop above)
	var sg := GridContainer.new()
	sg.columns = 4
	var cur_s := Crops.season_now(main.sim)
	for s in 4:
		var sl := main._label(["Spring", "Summer", "Autumn", "Winter"][s] + (" (now)" if s == cur_s else ""), 12, Main.BRASS if s == cur_s else Main.DIM)
		sg.add_child(sl)
	for s in 4:
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.add_item("main crop", 0)
		ob.set_item_metadata(0, "")
		var sel := 0
		for id in Crops.ORDER:
			var cd: Dictionary = Crops.LIST[id]
			if String(cd.need) != "" and main.sim.get_feature(String(cd.need)) == null:
				continue
			ob.add_item(String(cd.name) + ("" if Crops.grows(id, s) else " (idle)"), ob.item_count)
			ob.set_item_metadata(ob.item_count - 1, id)
			ob.set_item_disabled(ob.item_count - 1, not Crops.known(main.sim, me, id))
			if b.season_crop.size() == 4 and String(b.season_crop[s]) == id:
				sel = ob.item_count - 1
		ob.select(sel)
		ob.tooltip_text = "What this farm sows in %s. 'main crop' uses the crop chosen above. A crop marked (idle) does not grow then." % ["spring", "summer", "autumn", "winter"][s]
		ob.item_selected.connect(func(i):
			var bb: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
			if bb:
				if bb.season_crop.size() != 4:
					bb.season_crop = ["", "", "", ""]
				bb.season_crop[s] = String(ob.get_item_metadata(i))
				if bb.season_crop == ["", "", "", ""]:
					bb.season_crop = []
				main._click()
				_refresh_sel())
		sg.add_child(ob)
	main.prio_row.add_child(sg)
	var rk := CheckBox.new()
	rk.text = "Winter rye when out of season"
	rk.button_pressed = b.rotate
	rk.disabled = not (me.techs.has(Crops.ROTATE_TECH) and Crops.known(main.sim, me, "rye"))
	rk.tooltip_text = "While its crop does not grow, the farm sows winter rye instead of standing idle." + ("" if not rk.disabled else "\nNeeds Winter rye seed and the Three-field system.")
	rk.toggled.connect(func(on):
		var bb: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
		if bb:
			bb.rotate = on
			_refresh_sel())
	main.prio_row.add_child(rk)
	var ga := main._button("Use for all farms", func():
		var bb: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
		if bb:
			main._show_hint(tr("%d other farms now sow the same crops by season.") % Crops.apply_to_all(main.sim, bb), 3.0)
			_refresh_sel())
	ga.tooltip_text = "Give every farm of yours this farm's crops: the main crop, the crop for each season and the winter rye setting."
	main.prio_row.add_child(ga)


## The garrison settings of your military building b: how many soldiers, which kinds, and who stays
## home when it attacks.
func _garrison_ui(b: Sim.Bld) -> void:
	var p := main.sim.human()
	var cap := int(b.def.garrison)
	var want := main.sim.garrison_wanted(b)
	var rm := main.sim.rmix_of(p)
	var gm := main.sim.gmix_of(b)
	# rebuilt only when something it shows changes, so a menu that is open stays open
	var sig := "%d|%d|%s|%d|%s|%s|%d|%d|%d|%s|%d|%d|%d|%s|%d|%s|%d|%s|%d" % [b.id, b.want_n, str(b.want_kinds), b.keep_kind, str(rm), str(gm), p.age, b.archer_want, b.archers, str(b.sally), int(p.stock.get("bows", 0.0)), b.blunt, int(p.stock.get("weapons", 0.0)), b.upg, int(b.reno_prog * 20.0), str(b.border), p.inner_pct, str(p.border_first), p.techs.size()]
	if sig == main._gar_sig:
		return
	main._gar_sig = sig
	for c in main.garrison_box.get_children():
		main.garrison_box.remove_child(c)
		c.queue_free()
	main.garrison_box.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_child(main._label("Soldiers wanted", 14, Main.DIM))
	var minus := main._button("-", func(): main._set_want(b, want - 1))
	minus.disabled = want <= 1
	row.add_child(minus)
	var n := main._label(tr("%d of %d") % [want, cap], 15)
	n.custom_minimum_size = Vector2(60, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(n)
	var plus := main._button("+", func(): main._set_want(b, want + 1))
	plus.disabled = want >= cap
	row.add_child(plus)
	if b.want_n >= 0:
		row.add_child(main._button("Full", func(): main._set_want(b, -1)))
	main.garrison_box.add_child(row)
	var row2 := HBoxContainer.new()
	var kl := main._label("Kinds that may serve here", 14, Main.DIM)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(kl)
	if not b.want_kinds.is_empty():
		row2.add_child(main._button("Any", func():
			b.want_kinds = []
			main.sim.mil_fill(main.sim.human())
			_refresh_sel()))
	main.garrison_box.add_child(row2)
	var grid := GridContainer.new()
	grid.columns = 2
	for k in 6:
		var tb := Button.new()
		tb.focus_mode = Control.FOCUS_NONE
		tb.toggle_mode = true
		tb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tb.custom_minimum_size = Vector2(190, 0)
		tb.add_theme_font_size_override("font_size", 13)
		var at := AtlasTexture.new()
		at.atlas = Tex.get_tex("unit_soldier_e%d" % k)
		at.region = Tex.frame_rect("unit_soldier_e%d" % k, 0)
		tb.icon = at
		tb.add_theme_constant_override("icon_max_width", 22)
		var here := int(gm[k])
		var trainable := k <= p.age or int(rm[k]) > 0 or here > 0
		var info := ("%d at headquarters" % int(rm[k])) + ((", %d here" % here) if here > 0 else "")
		tb.text = tr("%s\n%s") % [Sim.soldier_plural(k).capitalize(), info if trainable else "not yet (%s age)" % GameData.age_name(k)]
		var ok := main.sim.kind_allowed(b, k)
		tb.set_pressed_no_signal(ok)
		# allowed kinds in gold, the others faded
		tb.add_theme_color_override("font_pressed_color", Main.BRASS)
		tb.add_theme_color_override("font_hover_pressed_color", Main.BRASS)
		if not ok:
			tb.modulate = Color(1, 1, 1, 0.55)
		tb.disabled = not trainable
		tb.tooltip_text = tr("Untick to keep %s out of this building: they are swapped for an allowed kind as soon as headquarters has one.") % Sim.soldier_plural(k)
		var kk := k
		tb.toggled.connect(func(on):
			if b.want_kinds.is_empty():
				b.want_kinds = [true, true, true, true, true, true]
			b.want_kinds[kk] = on
			if not b.want_kinds.has(true):
				b.want_kinds[kk] = true       # at least one kind must be allowed
				main._show_hint("At least one kind must be allowed.", 2.0)
			if not b.want_kinds.has(false):
				b.want_kinds = []
			main._click()
			if main.sim.mil_fill(main.sim.human()):
				main.sim.recompute_territory()
			_refresh_sel())
		grid.add_child(tb)
	main.garrison_box.add_child(grid)
	var row3 := HBoxContainer.new()
	row3.add_child(main._label("Stays home when it attacks", 14, Main.DIM))
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_item("The oldest kind", 0)
	for k in 6:
		ob.add_item(Sim.soldier_name(k).capitalize(), k + 1)
	ob.select(b.keep_kind + 1)
	ob.tooltip_text = "When this building attacks, all but one soldier march. This picks who stays to hold it (if one of that kind is here)."
	ob.item_selected.connect(func(i):
		b.keep_kind = i - 1
		main._gar_sig = "-"
		main._click())
	row3.add_child(ob)
	main.garrison_box.add_child(row3)
	# archers: soldiers here who take up bows from the stores
	var row4 := HBoxContainer.new()
	var al := main._label("Archers", 14, Main.DIM)
	al.tooltip_text = "Archers are extra to the soldiers here (up to half as many); each takes a bow from the stores. They shoot at attackers and at enemy columns passing within 6 tiles. They do not fight at the gate and are not counted as soldiers."
	row4.add_child(al)
	var am := main._button("-", func():
		b.archer_want = maxi(0, b.archer_want - 1)
		main._gar_sig = "-"
		main._click())
	am.disabled = b.archer_want <= 0
	row4.add_child(am)
	var an := main._label(tr("%d (want %d of %d)") % [b.archers, b.archer_want, main.sim.military.archer_cap(b)], 15)
	an.custom_minimum_size = Vector2(90, 0)
	an.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row4.add_child(an)
	var ap := main._button("+", func():
		b.archer_want = mini(main.sim.military.archer_cap(b), b.archer_want + 1)
		main._gar_sig = "-"
		main._click())
	ap.disabled = b.archer_want >= main.sim.military.archer_cap(b)
	row4.add_child(ap)
	row4.add_child(main._label(tr("  bows in store: %d") % int(p.stock.get("bows", 0.0)), 12, Main.DIM))
	main.garrison_box.add_child(row4)
	# weapons wear out in fights; worn ones are swapped for new ones from the stores
	var bl := b.blunt if b.ty != "hq" else p.blunt
	var wl := main._label(tr("Weapons: all sharp") if bl == 0 else (tr("Weapons: %d soldiers fight with worn weapons (%s)") % [bl, tr("new ones on the way") if float(p.stock.get("weapons", 0.0)) >= 1.0 else tr("no weapons in store!")]), 13, Main.DIM if bl == 0 else Color("e0b060"))
	wl.tooltip_text = "Each fight may wear out a soldier's weapon (1 in 10). Worn weapons fight about 12% worse until a new one comes from the stores, one a second. Bows break now and then too."
	main.garrison_box.add_child(wl)
	var sc := CheckBox.new()
	sc.text = "March out to meet attackers"
	sc.tooltip_text = "When an enemy attacks this building, or an enemy column marches past within 5 tiles on its way elsewhere, its soldiers (all but one) go out to fight it in the open."
	sc.button_pressed = b.sally
	sc.toggled.connect(func(on):
		b.sally = on
		main._gar_sig = "-")
	main.garrison_box.add_child(sc)
	main.garrison_box.add_child(main._label("Extra soldiers go back to headquarters; missing ones come from there, newest allowed kind first.", 12, Main.DIM))
	(main.garrison_box.get_child(main.garrison_box.get_child_count() - 1) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# upgrading where it stands: a bigger military building of the same size
	main.garrison_box.add_child(HSeparator.new())
	if b.upg != "":
		main.garrison_box.add_child(main._label(tr("Upgrading to a %s: %d%% (soldiers stay inside)") % [String(GameData.bld[b.upg].name).to_lower(), roundi(b.reno_prog * 100.0)], 14, Color("9fd0e8")))
	elif b.reno_to < 0:
		var ups := main.sim.upgrades_of(b)
		if ups.is_empty():
			main.garrison_box.add_child(main._label("No upgrade: no bigger %s military building is known yet." % String(Sim.SIZE_NAMES.get(main.sim.size_of(b.ty), "")).to_lower(), 12, Main.DIM))
		else:
			var ur := HFlowContainer.new()
			ur.add_child(main._label("Upgrade to", 14, Main.DIM))
			for ty in ups:
				var cost := main.sim.upgrade_cost(b, ty)
				var ub := main._button("%s (%d)" % [String(GameData.bld[ty].name), int(GameData.bld[ty].garrison)], func():
					var bb: Sim.Bld = main.sim.by_id.get(main.view.sel_id)
					if bb:
						var r := main.sim.upgrade(bb, ty)
						main._show_hint(r if r != "" else tr("Upgrade started: carriers bring %s.") % Diplomacy.goods_text(main.sim.upgrade_cost(bb, ty)), 3.5)
						main._gar_sig = "-"
						_refresh_sel())
				ub.tooltip_text = tr("Rebuild it as a %s where it stands: room for %d soldiers instead of %d, radius %d instead of %d. Costs %s. Its soldiers stay inside and it keeps its land meanwhile.") % [String(GameData.bld[ty].name).to_lower(), int(GameData.bld[ty].garrison), int(b.def.garrison), int(GameData.bld[ty].get("radius", 0)), int(b.def.get("radius", 0)), Diplomacy.goods_text(cost)]
				ur.add_child(ub)
			main.garrison_box.add_child(ur)
	# the realm's border settings
	main.garrison_box.add_child(HSeparator.new())
	var where := main._label(tr("This building is near the border.") if b.border else tr("This building is inland (no other realm within %d tiles).") % SimMilitary.BORDER_R, 13, Color("e0b060") if b.border else Main.DIM)
	main.garrison_box.add_child(where)
	var br := HBoxContainer.new()
	br.add_child(main._label("All inland buildings hold", 14, Main.DIM))
	var ib := OptionButton.new()
	ib.focus_mode = Control.FOCUS_NONE
	for pct in [100, 75, 50, 25]:
		ib.add_item(tr("%d%% of their soldiers") % pct if pct < 100 else tr("all their soldiers"), pct)
		if p.inner_pct == pct:
			ib.select(ib.item_count - 1)
	ib.tooltip_text = "For your whole realm: military buildings away from the border keep only this share (at least one soldier); the rest wait at headquarters for the border. A building with its own 'Soldiers wanted' keeps that."
	ib.item_selected.connect(func(i):
		p.inner_pct = ib.get_item_id(i)
		main._gar_sig = "-"
		main._click())
	br.add_child(ib)
	main.garrison_box.add_child(br)
	var bf := CheckBox.new()
	bf.text = "New soldiers go to the border first"
	bf.button_pressed = p.border_first
	bf.tooltip_text = "For your whole realm: soldiers leaving headquarters fill buildings near the border before inland ones."
	bf.toggled.connect(func(on):
		p.border_first = on
		main._gar_sig = "-")
	main.garrison_box.add_child(bf)


func me_warships() -> int:
	return main.sim.human().warships


## A row with the worker number of building b's kind (L) and the transport number of each good it
## takes (K): 1 first, 9 last, 5 as usual.
func _prio_numbers(b: Sim.Bld) -> void:
	var p := main.sim.human()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	if String(b.def.get("worker", "")) != "":
		var wl := main._label(tr("Worker no."), 13, Main.DIM)
		wl.tooltip_text = tr("Worker priority of all your %s (L): kinds with a lower number get workers first.") % String(b.def.name).to_lower()
		row.add_child(wl)
		var ty := b.ty
		row.add_child(_num_box(int(p.work_rank.get(ty, SimLogistics.RANK_DEFAULT)), func(v: int):
			var pp := main.sim.human()
			if v == SimLogistics.RANK_DEFAULT: pp.work_rank.erase(ty)
			else: pp.work_rank[ty] = v
			main.sim.staffing(pp)))
	var inp: Dictionary = b.def.get("in", {})
	if not inp.is_empty():
		var tl := main._label(tr("  Transport no."), 13, Main.DIM)
		tl.tooltip_text = tr("Transport priority of each good it takes (K): goods with a lower number are carried first.")
		row.add_child(tl)
		for k in inp:
			var key := String(k)
			var ic := TextureRect.new()
			ic.texture = Tex.get_tex("res_bread" if key == "food" else "res_" + key)
			ic.custom_minimum_size = Vector2(20, 20)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.tooltip_text = tr("Any food") if key == "food" else GameData.res_name(key)
			row.add_child(ic)
			row.add_child(_num_box(int(p.carry_rank.get(key, SimLogistics.RANK_DEFAULT)), func(v: int):
				var pp := main.sim.human()
				if v == SimLogistics.RANK_DEFAULT: pp.carry_rank.erase(key)
				else: pp.carry_rank[key] = v))
	main.sel_actions.add_child(row)


func _num_box(v: int, cb: Callable) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = 1
	sp.max_value = 9
	sp.step = 1
	sp.value = v
	sp.custom_minimum_size = Vector2(64, 0)
	sp.value_changed.connect(func(x): cb.call(int(x)))
	return sp
