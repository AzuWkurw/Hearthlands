class_name UiPriorities
extends RefCounted
## Two windows of priorities set with numbers: 1 comes first, 9 last, 5 is as
## usual.
##   Transport priorities (K): which goods the carriers take first: goods waiting at workshops are
##   picked up, workshops get what they use, and building sites get their materials, lower numbers
##   first. "Any food" counts for inns, mines and others that take whatever food there is.
##   Worker priorities (L): which kinds of building get new workers and builders first, when there
##   are not enough for all.
## A building's own priority (High, Normal, Low, Paused in its info) still comes first: these numbers
## order the buildings within it. The numbers are kept with your realm (Player.carry_rank,
## Player.work_rank) and saved with the game.

const MODE_CARRY := 0
const MODE_WORK := 1

var main: Main
var mode := MODE_CARRY
var win: Window
var head: Label
var grid: GridContainer
var show_all: CheckBox
var _spins := {}         # good or building type -> SpinBox
var presets: OptionButton
var save_name: LineEdit


func _init(p_owner: Main, p_mode: int) -> void:
	main = p_owner
	mode = p_mode


func build() -> void:
	win = Window.new()
	win.title = "Transport priorities" if mode == MODE_CARRY else "Worker priorities"
	win.transient = true
	win.wrap_controls = false
	win.size = Vector2i(640, 620)
	win.theme = UiLog.window_theme()
	win.visible = false
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", main._panel_style(0.96))
	win.add_child(bg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	bg.add_child(v)
	head = main._label("", 14)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.text = tr("Carriers take goods with a lower number first: 1 first, 9 last, 5 as usual. A building's own priority (in its info) still comes first.") if mode == MODE_CARRY \
		else tr("Kinds of building with a lower number get new workers and builders first when there are not enough for all: 1 first, 9 last, 5 as usual. A building's own priority (in its info) still comes first.")
	v.add_child(head)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	show_all = CheckBox.new()
	show_all.text = tr("Show every good") if mode == MODE_CARRY else tr("Show every kind (also those you have none of)")
	show_all.toggled.connect(func(_on): refresh())
	top.add_child(show_all)
	top.add_child(main._button(tr("All back to 5"), func():
		var p := main.sim.human()
		if mode == MODE_CARRY:
			p.carry_rank = {}
		else:
			p.work_rank = {}
			main.sim.staffing(p)
		refresh()))
	v.add_child(top)
	# ready-made sets, and your own (build 54): transport and worker numbers together
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 8)
	pr.add_child(main._label(tr("Sets:"), 14, Main.DIM))
	presets = OptionButton.new()
	presets.custom_minimum_size = Vector2(170, 0)
	pr.add_child(presets)
	var use := main._button(tr("Use"), func(): _use_preset())
	use.tooltip_text = tr("Puts this set's transport and worker numbers on your realm (all others back to 5).")
	pr.add_child(use)
	save_name = LineEdit.new()
	save_name.placeholder_text = tr("name for your set")
	save_name.custom_minimum_size = Vector2(150, 0)
	pr.add_child(save_name)
	var sv := main._button(tr("Save"), func(): _save_preset())
	sv.tooltip_text = tr("Keeps your transport and worker numbers now as a set of your own, for this and later games.")
	pr.add_child(sv)
	var dl := main._button(tr("Delete"), func(): _delete_preset())
	dl.tooltip_text = tr("Deletes the chosen set of your own.")
	pr.add_child(dl)
	v.add_child(pr)
	var hint := main._label(tr("Drag a row onto another to move it: it takes that row's number, one less when dragged up, one more when dragged down."), 12, Main.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(grid)
	win.close_requested.connect(func(): win.visible = false)
	main.add_child(win)


func toggle() -> void:
	if win.visible:
		win.visible = false
		return
	_fill_presets()
	refresh()
	win.popup_centered()


## The rows: goods (or kinds of building) in the order they are served, numbers you can change.
func refresh() -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	_spins = {}
	_order = []
	var sim: Sim = main.sim
	var p := sim.human()
	var items := []        # [key, name, icon, note]
	if mode == MODE_CARRY:
		items.append(["food", tr("Any food"), Tex.get_tex("res_bread"), tr("for inns, mines and others that take any food")])
		for r in GameData.resources:
			var id := String(r.id)
			if id == "research" or id == "ship":
				continue
			if not show_all.button_pressed and float(p.stock.get(id, 0.0)) < 1.0 and not p.carry_rank.has(id) and not _used(p, id):
				continue
			items.append([id, String(r.name), Tex.get_tex("res_" + id), ""])
	else:
		var have := {}
		for b: Sim.Bld in sim.realm_blds(p):
			if not have.has(b.ty):
				have[b.ty] = [0, 0]
			have[b.ty][0] += 1
			if b.staffed:
				have[b.ty][1] += 1
		for ty in GameData.bld:
			var d: Dictionary = GameData.bld[ty]
			if String(d.get("worker", "")) == "" or not sim.bld_enabled(ty):
				continue
			if not show_all.button_pressed and not have.has(ty) and not p.work_rank.has(ty):
				continue
			var note := ""
			if have.has(ty):
				note = tr("%d of %d have workers") % [int(have[ty][1]), int(have[ty][0])]
			items.append([ty, String(d.name), main.view.bld_texture(ty, p.age), note])
	# the order they are served in: by number, then by name
	items.sort_custom(func(a, b):
		var ra := _rank(p, String(a[0]))
		var rb := _rank(p, String(b[0]))
		return ra < rb or (ra == rb and String(a[1]) < String(b[1])))
	for it in items:
		var ic := DragIcon.new()
		ic.key = String(it[0])
		ic.ui = self
		ic.mouse_filter = Control.MOUSE_FILTER_STOP
		ic.tooltip_text = tr("Drag onto another row")
		ic.texture = it[2]
		ic.custom_minimum_size = Vector2(28, 28)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		grid.add_child(ic)
		var nl0 := DragName.new()
		nl0.text = String(it[1])
		nl0.add_theme_font_size_override("font_size", 14)
		nl0.key = String(it[0])
		nl0.ui = self
		nl0.mouse_filter = Control.MOUSE_FILTER_STOP
		nl0.mouse_default_cursor_shape = Control.CURSOR_DRAG
		grid.add_child(nl0)
		_order.append(String(it[0]))
		var sp := SpinBox.new()
		sp.min_value = 1
		sp.max_value = 9
		sp.step = 1
		sp.value = _rank(p, String(it[0]))
		sp.custom_minimum_size = Vector2(90, 0)
		var key := String(it[0])
		sp.value_changed.connect(func(v): _set_rank(key, int(v)))
		_spins[key] = sp
		grid.add_child(sp)
		var nl := main._label(String(it[3]), 12, Main.DIM)
		grid.add_child(nl)


func _rank(p: Sim.Player, key: String) -> int:
	if mode == MODE_CARRY:
		return int(p.carry_rank.get(key, SimLogistics.RANK_DEFAULT))
	return int(p.work_rank.get(key, SimLogistics.RANK_DEFAULT))


## Sets a number (5 is not kept: it is what every good and kind has anyway).
func _set_rank(key: String, v: int) -> void:
	var p := main.sim.human()
	var d: Dictionary = p.carry_rank if mode == MODE_CARRY else p.work_rank
	if v == SimLogistics.RANK_DEFAULT:
		d.erase(key)
	else:
		d[key] = clampi(v, 1, 9)
	if mode == MODE_WORK:
		main.sim.staffing(p)


## Whether any of your buildings uses or makes good id (so it is worth listing).
func _used(p: Sim.Player, id: String) -> bool:
	for b: Sim.Bld in main.sim.realm_blds(p):
		if b.def.get("in", {}).has(id) or b.def.get("out", {}).has(id) or b.def.get("cost", {}).has(id):
			return true
	return false


# ---------------------------------------------------------------- sets and dragging (build 54)
var _order: Array = []     # the keys in the order shown


func _fill_presets() -> void:
	presets.clear()
	for name in PrioPresets.BUILT_IN:
		presets.add_item(tr(name))
		presets.set_item_metadata(presets.item_count - 1, ["built", name])
		presets.set_item_tooltip(presets.item_count - 1, tr(String(PrioPresets.BUILT_IN[name][0])))
	for name in main.settings.prio_presets:
		presets.add_item(String(name) + " " + tr("(yours)"))
		presets.set_item_metadata(presets.item_count - 1, ["mine", name])
	var cur := PrioPresets.current(main.sim.human())
	for i in presets.item_count:
		if (presets.get_item_metadata(i) as Array)[1] == cur:
			presets.select(i)


func _use_preset() -> void:
	if presets.selected < 0:
		return
	var md: Array = presets.get_item_metadata(presets.selected)
	var p := main.sim.human()
	if md[0] == "built":
		PrioPresets.apply_named(p, String(md[1]))
	else:
		var e: Dictionary = main.settings.prio_presets.get(md[1], {})
		PrioPresets.apply(p, e.get("carry", {}), e.get("work", {}))
	main.sim.staffing(p)
	main._show_hint(tr("Priorities set: %s") % presets.get_item_text(presets.selected), 2.5)
	refresh()
	# the other window shows the other half of the set
	var other: UiPriorities = main.work_prio_ui if mode == MODE_CARRY else main.carry_prio_ui
	if other.win.visible:
		other.refresh()


func _save_preset() -> void:
	var name := save_name.text.strip_edges()
	if name == "":
		main._show_hint(tr("Give your set a name first."), 2.5)
		return
	var p := main.sim.human()
	main.settings.prio_presets[name] = {"carry": p.carry_rank.duplicate(), "work": p.work_rank.duplicate()}
	main.settings.save_file()
	save_name.text = ""
	_fill_presets()
	main._show_hint(tr("Saved your set \"%s\".") % name, 2.5)


func _delete_preset() -> void:
	if presets.selected < 0:
		return
	var md: Array = presets.get_item_metadata(presets.selected)
	if md[0] != "mine":
		main._show_hint(tr("Only sets of your own can be deleted."), 2.5)
		return
	main.settings.prio_presets.erase(md[1])
	main.settings.save_file()
	_fill_presets()


## Row `from` was dragged onto row `onto`: it takes that row's number, one less when it moved up (so it
## comes before it), one more when it moved down.
func move(from: String, onto: String) -> void:
	if from == onto:
		return
	var p := main.sim.human()
	var r := _rank(p, onto)
	var up := _order.find(from) > _order.find(onto)
	_set_rank(from, clampi(r - 1 if up else r + 1, 1, 9))
	refresh()


class DragName extends Label:
	var key := ""
	var ui: UiPriorities

	func _get_drag_data(_at: Vector2) -> Variant:
		var l := Label.new()
		l.text = text
		set_drag_preview(l)
		return {"prio_key": key}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data as Dictionary).has("prio_key")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		ui.move(String(data.prio_key), key)


class DragIcon extends TextureRect:
	var key := ""
	var ui: UiPriorities

	func _get_drag_data(_at: Vector2) -> Variant:
		var t := TextureRect.new()
		t.texture = texture
		t.custom_minimum_size = Vector2(28, 28)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		set_drag_preview(t)
		return {"prio_key": key}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data as Dictionary).has("prio_key")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		ui.move(String(data.prio_key), key)
