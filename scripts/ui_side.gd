class_name UiSide
extends RefCounted
## The side panel: stores, people, the build list, research and rivals, refreshed once a second.
## Part of the interface: main.gd holds the shared state and calls in here; the functions reach
## the rest of the game through `main` (main.gd keeps a one-line wrapper for each, so callers did
## not change).

var main: Main


func _init(p_main: Main) -> void:
	main = p_main


## Shows the stock rows of the goods your realm knows of, hides the rest.
func _refresh_stock_rows() -> void:
	for id in main.stock_labels:
		(main.stock_labels[id] as Control).get_parent().visible = main.res_shown(id)
		if main.metal_rows.has(id):
			main._metal_split(main.sim.human(), id, (main.stock_labels[id] as Control).get_parent())


func _refresh_folk() -> void:
	var p := main.sim.human()
	var t := ""
	t += "Peasants  [b]%d[/b] (%d at work)\n" % [p.peasant, p.used_peasant]
	t += "Artisans  [b]%d[/b] (%d at work)  content %d%%\n" % [p.artisan, p.used_artisan, roundi(float(p.sat.get("artisan", 0.0)) * 100)]
	t += "Nobles  [b]%d[/b]  content %d%%\n" % [p.noble, roundi(float(p.sat.get("noble", 0.0)) * 100)]
	var lux_n := 0
	for c in GameData.luxury:
		lux_n += (GameData.luxury[c] as Dictionary).size() if c == "noble" else 0
	if p.noble > 0 and lux_n > 0 and (p.lux > 0 or p.age >= 3):
		t += "Luxuries  [b]%d[/b] of %d%s\n" % [p.lux, lux_n, ("  [color=#8fc070](noble tax +%d%%)[/color]" % roundi(p.lux * Sim.LUX_TAX * 100)) if p.lux > 0 else "  [color=#9a9c88](spices, silk, porcelain, coffee)[/color]"]
	t += "Soldiers  [b]%d[/b] (%d in HQ, %d veterans): %s\n" % [main.sim.soldiers(p), p.reserve, int(p.vets), Sim.mix_text(main.sim.soldier_mix(p))]
	if main.sim.soldiers(p) > 0 and main.sim.arms.arms_text(p) != "":
		t += "  Arms  %s\n" % main.sim.arms.arms_text(p, true)
	var worn := p.blunt
	for wb: Sim.Bld in main.sim.realm_blds(p):
		worn += wb.blunt
	if worn > 0:
		t += "[color=#e0b060]  %d soldiers have worn weapons; new ones come from the stores (%d weapons there)[/color]\n" % [worn, int(p.stock.get("weapons", 0.0))]
	t += "Housing  [b]%d / %d[/b]\n" % [main.sim.pop_total(p), main.sim.housing(p)]
	t += tr("Children  [b]%s[/b]") % main.sim.people.kids_text(p) + (tr(", %d schooled") % p.schooled if p.schooled > 0 else "") + "\n"
	# specialists: workers level up only in their own trade
	var ts := main.sim.trade_summary(p)
	var parts := []
	var trs := ts.keys()
	trs.sort_custom(func(a, c): return int(ts[a].work) > int(ts[c].work))
	for tr: String in trs:
		var e: Dictionary = ts[tr]
		var bit := "%s %d" % [GameData.trade_plural(tr).capitalize(), int(e.work)]
		if int(e.work) > 0:
			bit += " lv %.1f" % (float(e.levels) / int(e.work))
		if int(e.idle) > 0:
			bit += " +%d idle" % int(e.idle)
		parts.append(bit)
	if not parts.is_empty():
		t += "Trades  %s\n" % ", ".join(parts)
	for f: Feature in main.sim.features:
		for line in f.panel_lines(p):
			t += line + "\n"
	var mules := [0, 0]
	var carts := [0, 0]
	for b in main.sim.realm_blds(p):
		if b.def.has("carriers") and b.state == "ready":
			var c: Dictionary = b.def.carriers
			var pair: Array = mules if String(c.kind) == "mule" else carts
			pair[0] += int(c.count) - b.busy if b.working else 0
			pair[1] += int(c.count) if b.working else 0
	t += "Carriers  [b]%d[/b] porters free%s%s\n" % [maxi(0, main.sim.porters_free(p)), (", %d of %d mules" % mules) if mules[1] > 0 else "", (", %d of %d carts" % carts) if carts[1] > 0 else ""]
	t += "Storage  [b]%d[/b] of each good\n" % int(main.sim.capacity(p, "planks"))
	if p.starve > 0:
		t += "Food  [color=#f0a090][b]Starving[/b][/color]"
	else:
		t += "Food  [b]%d[/b] in store" % int(main.sim.food_total(p))
	main.folk_label.text = t


func _refresh_build() -> void:
	if main.sim.players.is_empty():
		return
	var p := main.sim.human()
	# research unlocked something: show it
	if p.techs.size() != main._list_techs:
		main._rebuild_build_list()
		_refresh_stock_rows()
	for id in main.tool_buttons:
		(main.tool_buttons[id] as Button).set_pressed_no_signal(main.view.place_type == id)
	main.toolbar.refresh()
	for id in main.build_buttons:
		var b: Button = main.build_buttons[id]
		var d: Dictionary = GameData.bld[id]
		var locked: bool = d.has("tech") and not p.techs.has(d.tech)
		b.disabled = locked
		b.text = tr("%s\n%s") % [String(d.name), ("Needs " + GameData.tech_name(d.tech)) if locked else "%s · %s" % [GameData.cost_text(d.get("cost", {})), String(Sim.SIZE_NAMES[main.sim.size_of(id)]).to_lower()]]
		b.modulate = Color(1, 1, 1, 0.5) if (locked or main.sim.missing(p, d.get("cost", {})) != "") else Color.WHITE
		b.set_pressed_no_signal(main.view.place_type == id)


func _refresh_rivals() -> void:
	var t := ""
	for q in main.sim.players:
		if not q.ai:
			continue
		var n := 0
		for b in main.sim.blds:
			if b.p == q.id: n += 1
		var name_s := "[color=#%s]■[/color] %s [color=#9a9c88]%s, level %d[/color]" % [q.color.to_html(false), q.name, q.pers, q.skill]
		if q.alive:
			t += "%s  %d buildings, %d soldiers\n" % [name_s, n, main.sim.soldiers(q)]
		else:
			t += "%s  [s]defeated[/s]\n" % name_s
	main.rivals_label.text = t


func _res_info(id: String) -> String:
	var p := main.sim.human()
	var r: Dictionary = GameData.res_by_id.get(id, {})
	var t := "[b]%s[/b]\nIn store: [b]%d[/b] of %d room" % [GameData.res_name(id), int(p.stock.get(id, 0.0)), int(main.sim.capacity(p, id))]
	var on_way := int(main.sim.coming(p, id))
	if on_way > 0:
		t += ", %d more on the way" % on_way
	if float(p.stock.get(id, 0.0)) + on_way >= main.sim.capacity(p, id) - 0.5:
		t += "\n[color=#e0a050]Full: buildings that make it have stopped until some is used. Build a storehouse for more room.[/color]\n"
	else:
		t += "\n[color=#9a9c88]When the stores are full, buildings that make it stop (goods on the way count).[/color]\n"
	if r.has("food"):
		t += "Food: each one feeds %.1f people-meals\n" % float(r.food)
	t += "Worth about %.1f in trade\n" % GameData.res_value(id)
	var makers := []
	var users := []
	var costs := []
	for b in GameData.bld:
		var d: Dictionary = GameData.bld[b]
		var mine := 0
		for x in main.sim.blds:
			if x.p == 1 and x.ty == b:
				mine += 1
		var have := " (you have %d)" % mine if mine > 0 else ""
		if (d.get("out", {}) as Dictionary).has(id):
			makers.append("%s: %d every %d s%s" % [String(d.name), int(d.out[id]), int(d.get("cycle", 0)), have])
		elif d.has("makes_tools") and GameData.is_tool_res(id):
			makers.append("%s: %d tools every %d s, the kind most wanted%s" % [String(d.name), int(d.makes_tools), int(d.get("cycle", 0)), have])
		if (d.get("in", {}) as Dictionary).has(id):
			users.append("%s uses %d%s" % [String(d.name), int(d["in"][id]), have])
		if (d.get("cost", {}) as Dictionary).has(id):
			costs.append(String(d.name))
	if id in ["coal", "ore_iron", "ore_gold", "ore_copper", "stone"]:
		makers.append("mines and quarries draw it from veins on the map; click a deposit to see what is left")
	t += "Made by: %s\n" % ("; ".join(makers) if makers.size() > 0 else "nothing")
	if users.size() > 0:
		t += "Used by: %s\n" % "; ".join(users)
	if r.has("food"):
		t += "Eaten by everyone; miners eat it too\n"
	if r.has("tool"):
		var tr := String(r.tool)
		var waiting := int(p.tool_wait.get(id, 0))
		t += "Each new %s (%s) needs one, and a new one when it wears out; an idle specialist keeps his%s\n" % [GameData.trade_title(tr), GameData.trade_name(tr).to_lower(), (". [color=#f08a7a]%d building%s waiting for one[/color]" % [waiting, "s" if waiting != 1 else ""]) if waiting > 0 else ""]
		t += "%s tools work %d%% slower and wear out in %d%% of the time of %s ones; %s tools work %d%% faster and last %d%% longer\n" % [SimArms.tag(1, true), roundi((1.0 - SimArms.TOOL_SPEED[1]) * 100), roundi(SimArms.TOOL_LIFE[1] * 100), SimArms.tag(2, true), SimArms.tag(3, true), roundi((SimArms.TOOL_SPEED[3] - 1.0) * 100), roundi((SimArms.TOOL_LIFE[3] - 1.0) * 100)]
	if r.has("tool") or id == "weapons":
		var sp := main.sim.arms.split_bb(p, id)
		if sp != "":
			t += "In store by metal: %s\n" % sp
	if id == "weapons":
		if main.sim.soldiers(p) > 0:
			t += "Your soldiers' arms: %s\n" % main.sim.arms.arms_text(p, true)
		t += "Bronze arms make bronze warriors only; iron arms soldiers up to musketeers; riflemen need steel arms (machine works). Better arms train faster and wear out less in a fight\n"
	var tg := main.sim.target_of(p, id)
	t += "Production target: %s\n" % ("none (makes up to the store room)" if tg < 0 else "keep %d in store, then pause" % tg)
	if costs.size() > 0:
		t += "Needed to build: %s\n" % ", ".join(costs)
	for cls in GameData.luxury:
		if (GameData.luxury[cls] as Dictionary).has(id):
			t += "A luxury: each kind the %ss have had lately raises their tax by %d%%\n" % [cls, roundi(Sim.LUX_TAX * 100)]
	for cls in GameData.needs:
		for key: String in GameData.needs[cls]:
			var opts := GameData.need_options(key)
			if id in opts:
				var others := []
				for o in opts:
					if o != id:
						others.append(GameData.res_name(o).to_lower())
				t += "Keeps %ss content%s\n" % [cls, "" if others.is_empty() else " (or " + " or ".join(others) + " instead)"]
	return t


func _refresh_research() -> void:
	main.research_ui._refresh_research()
