class_name UiPriorities
extends RefCounted
## Two windows of priorities set with numbers, as in The Settlers II: 1 comes first, 9 last, 5 is as
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
	refresh()
	win.popup_centered()


## The rows: goods (or kinds of building) in the order they are served, numbers you can change.
func refresh() -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	_spins = {}
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
		var ic := TextureRect.new()
		ic.texture = it[2]
		ic.custom_minimum_size = Vector2(28, 28)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		grid.add_child(ic)
		grid.add_child(main._label(String(it[1]), 14))
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
