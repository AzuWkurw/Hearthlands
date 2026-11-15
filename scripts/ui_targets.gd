class_name UiTargets
extends RefCounted
## Production targets: how many of each good to keep in stock.
## Part of the interface: main.gd holds the shared state and calls in here; the functions reach
## the rest of the game through `main`.

var main: Main

var targets_grid: GridContainer


func _init(p_owner: Main) -> void:
	main = p_owner


## A "keep in stock" control for good id: − and + step through TARGET_STEPS.
func _target_ctrl(id: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var p := main.sim.human()
	var cur := main.sim.target_of(p, id)
	var lbl := main._label("no limit" if cur < 0 else "keep %d" % cur, 14)
	lbl.custom_minimum_size = Vector2(72, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var step := func(dir: int):
		var now := main.sim.target_of(p, id)
		var i := Main.TARGET_STEPS.find(now)
		if i < 0:
			i = 0
			for k in Main.TARGET_STEPS.size():
				if int(Main.TARGET_STEPS[k]) <= now: i = k
		var nxt: int = Main.TARGET_STEPS[clampi(i + dir, 0, Main.TARGET_STEPS.size() - 1)]
		p.targets[id] = nxt
		lbl.text = "no limit" if nxt < 0 else "keep %d" % nxt
		if main.sel_res == id:
			main.sel_label.text = main._res_info(id)
	hb.add_child(main._button("−", step.bind(-1)))
	hb.add_child(lbl)
	hb.add_child(main._button("+", step.bind(1)))
	return hb


func _build_targets_panel() -> void:
	main.targets_panel = main._overlay()
	var v: VBoxContainer = main.targets_panel.find_child("Body", true, false)
	var head := HBoxContainer.new(); v.add_child(head)
	var tl := main._label("Production targets", 20, Main.BRASS); tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(tl)
	head.add_child(main._button("Close (Esc)", func(): main.targets_panel.visible = false))
	var info := main._label("Buildings stop making a good once this many are in store, and start again when stock drops. Tools keep 2 of each unless you change it; the toolsmith makes whichever tool is most wanted.", 13, Main.DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(900, 0)
	v.add_child(info)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(940, 560)
	v.add_child(sc)
	targets_grid = GridContainer.new()
	targets_grid.columns = 3
	targets_grid.add_theme_constant_override("h_separation", 24)
	sc.add_child(targets_grid)
	main.targets_panel.visible = false


func _open_targets() -> void:
	for c in targets_grid.get_children():
		targets_grid.remove_child(c)
		c.queue_free()
	var p := main.sim.human()
	for r in GameData.resources:
		if not main.res_shown(String(r.id)):
			continue
		var hb := HBoxContainer.new()
		var ic := TextureRect.new()
		ic.texture = Tex.get_tex("res_" + String(r.id))
		ic.custom_minimum_size = Vector2(20, 20)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hb.add_child(ic)
		var nm := main._label(tr("%s (%d)") % [String(r.name), int(p.stock.get(r.id, 0.0))], 14)
		nm.custom_minimum_size = Vector2(150, 0)
		hb.add_child(nm)
		hb.add_child(_target_ctrl(String(r.id)))
		targets_grid.add_child(hb)
	_metal_section(p)
	main.targets_panel.visible = true


const KEEP_STEPS := [0, 2, 5, 10, 15, 20, 30, 50, 80, 120]


## A − value + stepper: steps through vals, shown by fmt (a Callable value -> text), set by on_set.
func _stepper(vals: Array, cur: int, fmt: Callable, on_set: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var lbl := main._label(fmt.call(cur), 14)
	lbl.custom_minimum_size = Vector2(70, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var st := [cur]
	var step := func(dir: int):
		var i := 0
		for k in vals.size():
			if int(vals[k]) <= int(st[0]): i = k
		var nxt: int = vals[clampi(i + dir, 0, vals.size() - 1)]
		st[0] = nxt
		on_set.call(nxt)
		lbl.text = fmt.call(nxt)
	hb.add_child(main._button("−", step.bind(-1)))
	hb.add_child(lbl)
	hb.add_child(main._button("+", step.bind(1)))
	return hb


## Build 68: tools and weapons by metal: which metal is used first, the most of each metal to keep in
## store, and how much of each metal the tool smiths and weapon smiths leave for each other.
func _metal_section(p: Sim.Player) -> void:
	var title := main._label("Tools and weapons by metal", 18, Main.BRASS)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	# the grid has three columns: fill the row, then a full-width box under it
	var sc: ScrollContainer = targets_grid.get_parent()
	var outer: VBoxContainer = sc.get_child(0) if sc.get_child(0) is VBoxContainer else null
	if outer == null:
		outer = VBoxContainer.new()
		sc.remove_child(targets_grid)
		sc.add_child(outer)
		outer.add_child(targets_grid)
	for c in outer.get_children():
		if c != targets_grid:
			outer.remove_child(c)
			c.queue_free()
	outer.add_child(HSeparator.new())
	outer.add_child(title)
	var info := main._label("Which metal workers and soldiers take first; the most of each metal a smith keeps in store (of each kind of tool, or of weapons): once that many are there, he makes another kind or waits; and how much of each metal the tool smiths leave in store for the weapon smiths, and the other way round.", 13, Main.DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(900, 0)
	outer.add_child(info)
	outer.add_child(box)
	for grp in ["tools", "weapons"]:
		var g: String = grp
		box.add_child(main._label("Tools (each kind)" if g == "tools" else "Weapons", 15))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 14)
		box.add_child(row)
		row.add_child(main._label("Used first:", 14, Main.DIM))
		var ob := OptionButton.new()
		var cur: Array = p.metal_order.get(g, [3, 2, 1])
		for k in SimArms.ORDERS.size():
			var o: Array = SimArms.ORDERS[k]
			ob.add_item(", ".join(o.map(func(t): return SimArms.NAMES[t])), k)
			if o == cur:
				ob.select(k)
		ob.item_selected.connect(func(k): p.metal_order[g] = (SimArms.ORDERS[k] as Array).duplicate())
		row.add_child(ob)
		var row2 := HFlowContainer.new()
		row2.add_theme_constant_override("h_separation", 14)
		box.add_child(row2)
		row2.add_child(main._label("At most in store:", 14, Main.DIM))
		for t in [SimArms.BRONZE, SimArms.IRON, SimArms.STEEL]:
			var tt: int = t
			var ic := TextureRect.new()
			ic.texture = Tex.get_tex(SimArms.icon_id("axes" if g == "tools" else "weapons", tt))
			ic.custom_minimum_size = Vector2(20, 20)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row2.add_child(ic)
			row2.add_child(main._label(SimArms.NAMES[tt], 14))
			row2.add_child(_stepper(Main.TARGET_STEPS, main.sim.arms.limit_of(p, g, tt),
				func(v): return "no limit" if v < 0 else "%d" % v,
				func(v):
					if not p.metal_lim.has(g): p.metal_lim[g] = [-1, -1, -1, -1]
					p.metal_lim[g][tt] = v))
		var row3 := HFlowContainer.new()
		row3.add_theme_constant_override("h_separation", 14)
		box.add_child(row3)
		row3.add_child(main._label("Leave for the %s:" % ("weapon smiths" if g == "tools" else "tool smiths"), 14, Main.DIM))
		for m in ["bronze", "iron", "steel"]:
			if not main.res_shown(m):
				continue
			var mm: String = m
			var ic2 := TextureRect.new()
			ic2.texture = Tex.get_tex("res_" + mm)
			ic2.custom_minimum_size = Vector2(20, 20)
			ic2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row3.add_child(ic2)
			row3.add_child(main._label(GameData.res_name(mm), 14))
			row3.add_child(_stepper(KEEP_STEPS, main.sim.arms.keep_of(p, g, mm),
				func(v): return "none" if v <= 0 else "%d" % v,
				func(v):
					if not p.metal_keep.has(g): p.metal_keep[g] = {}
					p.metal_keep[g][mm] = v))
