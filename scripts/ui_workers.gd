class_name UiWorkers
extends RefCounted
## The Buildings and workers window (J, or the Buildings button): every kind of building you have,
## how many, how many are still being built, how many have their worker and how many wait for one.
## For each kind with workers you can set a priority for all of them at once and a limit on how many
## get workers (the rest stand idle, so the peasants go elsewhere). Next jumps the map to them one
## after another. At the top: idle people, and keeping one peasant free as a builder for new sites.

const LIMITS := [-1, 0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 30]

var main: Main
var win: Window
var head: Label
var grid: GridContainer
var spare: CheckBox
var filter: OptionButton
var _rows := {}          # building type -> [count label, building label, staffed label, waiting label]
var _sig := ""
var _next := {}          # building type -> index of the last one jumped to
var _t := 0.0


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	win = Window.new()
	win.title = "Buildings and workers"
	win.transient = true
	win.wrap_controls = false
	win.size = Vector2i(820, 620)
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
	v.add_child(head)
	var top := HBoxContainer.new()
	spare = CheckBox.new()
	spare.text = "Keep one builder free for new building sites"
	spare.tooltip_text = "One peasant stays at headquarters as a builder, so a new building site starts at once instead of taking a worker from his job."
	spare.toggled.connect(func(on):
		main.sim.human().spare_builder = on
		main.sim.staffing(main.sim.human())
		refresh(true))
	top.add_child(spare)
	top.add_child(main._label("   Show", 14, Main.DIM))
	filter = OptionButton.new()
	filter.focus_mode = Control.FOCUS_NONE
	for f in ["every kind", "kinds with workers", "kinds waiting for workers"]:
		filter.add_item(f)
	filter.item_selected.connect(func(_i): refresh(true))
	top.add_child(filter)
	v.add_child(top)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	grid = GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(grid)
	var foot := main._label("Limit: at most this many of the kind get workers (the others stand idle and their peasants work elsewhere). Priority applies to all of the kind; you can still change one building on its own.", 12, Main.DIM)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(foot)
	win.close_requested.connect(func(): win.visible = false)
	main.add_child(win)


func toggle() -> void:
	if win.visible:
		win.visible = false
		return
	refresh(true)
	win.popup_centered()


## Once a game second while open: the numbers (the rows are rebuilt only when the kinds change).
func update(delta: float) -> void:
	if win == null or not win.visible:
		return
	_t += delta
	if _t >= 1.0:
		_t = 0.0
		refresh(false)


func _kinds(p: Sim.Player) -> Dictionary:
	var out := {}    # type -> [have, building, staffed, waiting, prios {prio: n}]
	for b: Sim.Bld in main.sim.realm_blds(p):
		if b.dead:
			continue
		var e: Array = out.get(b.ty, [0, 0, 0, 0, {}])
		e[0] += 1
		if b.state == "build":
			e[1] += 1
		elif b.def.has("worker"):
			if b.staffed:
				e[2] += 1
			elif b.prio != Sim.PRIO_PAUSED:
				e[3] += 1
		(e[4] as Dictionary)[b.prio] = int((e[4] as Dictionary).get(b.prio, 0)) + 1
		out[b.ty] = e
	return out


func refresh(rebuild: bool) -> void:
	var sim: Sim = main.sim
	if sim == null or sim.players.is_empty():
		return
	var p := sim.human()
	spare.set_pressed_no_signal(p.spare_builder)
	var idle_p := p.peasant - p.used_peasant - p.away
	var idle_a := p.artisan - p.used_artisan
	var total := 0
	var kinds := _kinds(p)
	for k in kinds:
		total += int(kinds[k][0])
	head.text = tr("%d buildings of %d kinds. Peasants: %d at work, %d idle. Artisans: %d at work, %d idle." % [total, kinds.size(), p.used_peasant, maxi(0, idle_p), p.used_artisan, maxi(0, idle_a)])
	var types: Array = kinds.keys()
	var f := filter.selected
	types = types.filter(func(t):
		if f == 1: return GameData.bld[t].has("worker")
		if f == 2: return int(kinds[t][3]) > 0
		return true)
	types.sort_custom(func(a, b): return String(GameData.bld[a].name) < String(GameData.bld[b].name))
	var sig := "%s|%d|%s" % [str(types), f, str(p.job_limit)]
	if rebuild or sig != _sig:
		_sig = sig
		_build_rows(types, kinds, p)
	for t in types:
		var r: Array = _rows.get(t, [])
		if r.is_empty():
			continue
		var e: Array = kinds[t]
		(r[0] as Label).text = str(e[0])
		(r[1] as Label).text = str(e[1]) if int(e[1]) > 0 else ""
		var has_w: bool = GameData.bld[t].has("worker")
		(r[2] as Label).text = str(e[2]) if has_w else "-"
		(r[3] as Label).text = str(e[3]) if has_w and int(e[3]) > 0 else ""
		(r[3] as Label).add_theme_color_override("font_color", Color("e0b060"))


func _build_rows(types: Array, kinds: Dictionary, p: Sim.Player) -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	_rows = {}
	for h in ["Building", "Have", "Being built", "Working", "No worker", "Priority (all)", "Limit", ""]:
		grid.add_child(main._label(h, 13, Main.BRASS))
	for t in types:
		var d: Dictionary = GameData.bld[t]
		var e: Array = kinds[t]
		var nm := main._label(String(d.name), 14)
		nm.custom_minimum_size = Vector2(170, 0)
		grid.add_child(nm)
		var row := []
		for k in 4:
			var l := main._label("", 14)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.custom_minimum_size = Vector2(60, 0)
			grid.add_child(l)
			row.append(l)
		_rows[t] = row
		# priority for all of the kind (shows "mixed" when they differ)
		if main.sim.has_priority(main.sim.realm_blds(p).filter(func(b): return b.ty == t)[0]):
			var ob := OptionButton.new()
			ob.focus_mode = Control.FOCUS_NONE
			var prios: Dictionary = e[4]
			var sel := -1
			for pr in [Sim.PRIO_HIGH, Sim.PRIO_NORMAL, Sim.PRIO_LOW, Sim.PRIO_PAUSED]:
				ob.add_item(Sim.PRIO_NAMES[pr], pr)
				if prios.size() == 1 and prios.has(pr):
					sel = ob.item_count - 1
			if sel < 0:
				ob.add_item("mixed", 99)
				sel = ob.item_count - 1
			ob.select(sel)
			ob.item_selected.connect(func(i):
				var pr2 := ob.get_item_id(i)
				if pr2 == 99:
					return
				for b: Sim.Bld in main.sim.realm_blds(p):
					if b.ty == t and main.sim.has_priority(b):
						main.sim.set_priority(b, pr2)
				main._click()
				refresh(true))
			grid.add_child(ob)
		else:
			grid.add_child(main._label("", 13))
		# limit on how many of the kind get workers
		if d.has("worker"):
			var lb := OptionButton.new()
			lb.focus_mode = Control.FOCUS_NONE
			var cur := int(p.job_limit.get(t, -1))
			for n in LIMITS:
				lb.add_item("no limit" if n < 0 else str(n), n + 1)
				if n == cur:
					lb.select(lb.item_count - 1)
			lb.item_selected.connect(func(i):
				var n2 := lb.get_item_id(i) - 1
				if n2 < 0:
					p.job_limit.erase(t)
				else:
					p.job_limit[t] = n2
				main.sim.staffing(p)
				main._click()
				refresh(false))
			grid.add_child(lb)
		else:
			grid.add_child(main._label("", 13))
		grid.add_child(main._button("Next", _jump.bind(t)))


## Moves the map to the next building of kind t and selects it.
func _jump(t: String) -> void:
	var list: Array = main.sim.realm_blds(main.sim.human()).filter(func(b): return b.ty == t and not b.dead)
	if list.is_empty():
		return
	var k := (int(_next.get(t, -1)) + 1) % list.size()
	_next[t] = k
	var b: Sim.Bld = list[k]
	main.view.center_on(Vector2(b.x + 0.5, b.y + 0.5))
	main.view.sel_id = b.id
	main._refresh_all()
