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
		var nm := main._label("%s (%d)" % [String(r.name), int(p.stock.get(r.id, 0.0))], 14)
		nm.custom_minimum_size = Vector2(150, 0)
		hb.add_child(nm)
		hb.add_child(_target_ctrl(String(r.id)))
		targets_grid.add_child(hb)
	main.targets_panel.visible = true
