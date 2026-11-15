class_name UiResearch
extends RefCounted
## The research window: the tech tree from Rome to the Industrial Revolution.
## Part of the interface: main.gd holds the shared state and calls in here; the functions reach
## the rest of the game through `main`.

var main: Main

var tree: TechTreeView
var stats: RichTextLabel
var detail: RichTextLabel
var actions: VBoxContainer
var queue_row: HBoxContainer
var age_row: HBoxContainer
var search: LineEdit
var zoom_btn: Button
var compact_btn: Button
var rate := 0.0                 # research points a minute, for the time estimates


func _init(p_owner: Main) -> void:
	main = p_owner


func _rp_rate(p: Sim.Player) -> float:
	main.rp_hist.append([main.sim.time, p.rp_total])
	while main.rp_hist.size() > 2 and main.sim.time - float(main.rp_hist[0][0]) > 30.0:
		main.rp_hist.pop_front()
	var dt := main.sim.time - float(main.rp_hist[0][0])
	rate = (p.rp_total - float(main.rp_hist[0][1])) / dt * 60.0 if dt > 1.0 else 0.0
	return rate


func _refresh_research() -> void:
	var p := main.sim.human()
	var rate := _rp_rate(p)
	var total := 0
	for id in GameData.techs:
		if main.sim.tech_enabled(id): total += 1
	var t := "Age: [b]%s[/b]   %d of %d techs\n" % [GameData.age_name(p.age), p.techs.size(), total]
	if p.research != "":
		var cost := main.sim.research_cost(p, p.research)
		t += "Studying [b]%s[/b]: %d / %d" % [GameData.tech_name(p.research), int(p.rp), int(cost)]
		if rate > 0.01:
			t += "  (about %d min)" % ceili(maxf(0.0, cost - p.rp) / rate)
		main.research_bar.max_value = cost
		main.research_bar.value = minf(p.rp, cost)
	else:
		t += "[color=#e0b060]Nothing being studied.[/color] %d points saved" % int(p.rp)
		main.research_bar.max_value = 1
		main.research_bar.value = 0
	t += "\n[color=#9a9c88]%.1f research points per minute[/color]" % rate
	# the way to the next age
	var gate := GameData.gate_of(p.age + 1)
	if gate != "" and not p.techs.has(gate) and main.sim.tech_enabled(gate):
		var need := int(GameData.techs[gate].get("need", 0))
		var have := mini(main.sim.gate_have(p, gate), need)
		if have < need:
			t += "\n" + tr("Next age: [color=#d8aa4a]%s[/color] after %d of %d %s techs") % [GameData.tech_name(gate), have, need, GameData.age_name(p.age)]
		else:
			t += "\n" + tr("Next age: [color=#d8aa4a]%s[/color] can be studied now") % GameData.tech_name(gate)
	if not p.rqueue.is_empty():
		var names := []
		for k in mini(3, p.rqueue.size()):
			names.append(GameData.tech_name(p.rqueue[k]))
		t += "\n[color=#9a9c88]Next: %s%s[/color]" % [", ".join(names), (" and %d more" % (p.rqueue.size() - 3)) if p.rqueue.size() > 3 else ""]
	main.research_label.text = t


func _build_tech_panel() -> void:
	# a window over the whole map: the tree needs the room
	var o := Control.new()
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.offset_right = -Main.SIDE_W
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	main.add_child(o)
	main.tech_panel = o
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.04, 0.85)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.add_child(bg)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", main._panel_style(1.0))
	pc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pc.offset_left = 8; pc.offset_top = 8; pc.offset_right = -8; pc.offset_bottom = -8
	o.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	row.add_child(main._label("Research", 22, Main.BRASS))
	stats = main._rich()
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.autowrap_mode = TextServer.AUTOWRAP_OFF
	stats.custom_minimum_size = Vector2(120, 0)
	row.add_child(stats)
	search = LineEdit.new()
	search.placeholder_text = "Find a tech or building"
	search.custom_minimum_size = Vector2(170, 0)
	search.clear_button_enabled = true
	search.text_changed.connect(func(q):
		var h := tree.set_search(q)
		if not h.is_empty(): tree.center_on(h[0]))
	search.text_submitted.connect(func(q):
		var h := tree.set_search(q)
		if not h.is_empty():
			# found: show it and stop dimming the rest
			search.text = ""
			tree.set_search("")
			search.release_focus()
			_select(h[0], true))
	# Esc in the search box clears it, or closes the window when it is empty
	search.gui_input.connect(func(e):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			if search.text != "":
				search.text = ""
				tree.set_search("")
			else:
				search.release_focus()
				main.tech_panel.visible = false
			search.accept_event())
	row.add_child(search)
	compact_btn = main._button("Compact", func():
		tree.compact = not tree.compact
		compact_btn.text = "Full cards" if tree.compact else "Compact"
		tree.rebuild())
	compact_btn.tooltip_text = "Smaller cards, so more of the tree fits"
	row.add_child(compact_btn)
	row.add_child(main._button("-", func(): tree.set_zoom(tree.zoom / 1.25)))
	zoom_btn = main._button("100%", func():
		if absf(tree.zoom - 1.0) < 0.01: tree.fit()
		else: tree.set_zoom(1.0))
	zoom_btn.tooltip_text = "Click: the whole tree / back to 100%.\nCtrl + wheel or a pinch zooms; drag or the wheel moves."
	zoom_btn.custom_minimum_size = Vector2(58, 0)
	row.add_child(zoom_btn)
	row.add_child(main._button("+", func(): tree.set_zoom(tree.zoom * 1.25)))
	row.add_child(main._button("Close", func(): main.tech_panel.visible = false))

	age_row = HBoxContainer.new()
	age_row.add_theme_constant_override("separation", 4)
	v.add_child(age_row)

	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 8)
	v.add_child(mid)
	tree = TechTreeView.new()
	tree.sim = main.sim
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.selected.connect(func(id): _select(id, false))
	tree.activated.connect(_activate)
	tree.zoom_changed.connect(func(z): zoom_btn.text = tr("%d%%") % roundi(z * 100.0))
	mid.add_child(tree)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(290, 0)
	side.add_theme_constant_override("separation", 6)
	mid.add_child(side)
	detail = main._rich(200)
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.meta_clicked.connect(func(m): _select(String(m), true))
	side.add_child(detail)
	actions = VBoxContainer.new()
	side.add_child(actions)

	var qr := HBoxContainer.new()
	qr.add_theme_constant_override("separation", 6)
	v.add_child(qr)
	qr.add_child(main._label("Queue", 16, Main.BRASS))
	var qs := ScrollContainer.new()
	qs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	qs.custom_minimum_size = Vector2(0, 44)
	qr.add_child(qs)
	queue_row = HBoxContainer.new()
	queue_row.add_theme_constant_override("separation", 4)
	qs.add_child(queue_row)
	qr.add_child(main._button("Clear", func():
		main.sim.human().rqueue.clear()
		_fill_tech()))

	main.tech_panel.visible = false
	main.sim.tech_done.connect(func(pid, _t): if pid == 1 and main.tech_panel.visible: _fill_tech())


func _open_tech() -> void:
	if main.sim.players.is_empty():
		return
	main.tech_panel.visible = true
	tree.sim = main.sim
	search.text = ""
	tree.set_search("")
	tree.rebuild()
	if tree.sel == "":
		tree.show_age(main.sim.human().age)
	_fill_tech()


## Shows a tech in the side box (and, with go, moves the tree to it).
func _select(id: String, go: bool) -> void:
	tree.sel = id
	if go:
		tree.center_on(id)
	_fill_tech()


## Double click: add it to the end of the queue, or (locked) everything it needs.
func _activate(id: String) -> void:
	var p := main.sim.human()
	match tree.state_of(id):
		"avail":
			# goes to the end of the queue (or starts at once when nothing is being studied)
			main.sim.queue_research(p, id)
		"locked":
			if not GameData.reps.has(id):
				for x in main.sim.research_path(p, id):
					main.sim.queue_research(p, x)
	tree.sel = id
	_fill_tech()
	main._refresh_research()


func _mins(points: float) -> String:
	if rate <= 0.01:
		return "time unknown"
	var m := points / rate
	if m < 1.0: return "under a minute"
	if m < 60.0: return "%d min" % ceili(m)
	return "%d h %d min" % [floori(m / 60.0), roundi(fmod(m, 60.0))]


## Points needed before entry i of the queue is done (-1: the study under way), counting what is saved.
func _points_until(p: Sim.Player, i: int) -> float:
	var seen := {}
	var total := 0.0
	var list := ([p.research] if p.research != "" else []) + p.rqueue
	var upto := i + (1 if p.research != "" else 0)
	for k in mini(upto + 1, list.size()):
		var id: String = list[k]
		var ahead: int = seen.get(id, 0)
		seen[id] = ahead + 1
		total += main.sim.research_cost(p, id, ahead)
	return maxf(0.0, total - p.rp)


func _fill_tech() -> void:
	var p := main.sim.human()
	tree.queue_redraw()
	# the status line
	var total := 0
	for id in GameData.techs:
		if main.sim.tech_enabled(id): total += 1
	var st := "Age: [b]%s[/b]   %d of %d techs" % [GameData.age_name(p.age), p.techs.size(), total]
	st += "   Points: [b]%d[/b]" % int(p.rp)
	if rate > 0.01:
		st += "   [color=#9a9c88]%.0f a minute[/color]" % rate
	stats.text = st
	# ages: how far through each, click to go there
	for c in age_row.get_children():
		c.queue_free()
	for a in GameData.ages.size():
		var n := 0
		var done := 0
		for id in GameData.techs:
			if int(GameData.techs[id].get("age", 0)) == a and main.sim.tech_enabled(id):
				n += 1
				if p.techs.has(id): done += 1
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		b.text = tr("%s  %s") % [GameData.age_name(a), ("start" if n == 0 else "%d/%d" % [done, n])]
		if a == p.age:
			b.add_theme_color_override("font_color", TechTreeView.C_STUDY)
			b.text = "◆ " + b.text
		elif a < p.age:
			b.add_theme_color_override("font_color", TechTreeView.C_DONE)
		b.tooltip_text = "Your age now" if a == p.age else (("Study \"%s\" to enter this age" % GameData.tech_name(GameData.gate_of(a))) if a == p.age + 1 and GameData.gate_of(a) != "" else ("Finish any %s tech to enter this age" % GameData.age_name(a) if a == p.age + 1 else ""))
		var aa := a
		b.pressed.connect(func(): tree.show_age(aa))
		age_row.add_child(b)
	_fill_queue(p)
	_fill_detail(p)


func _fill_queue(p: Sim.Player) -> void:
	for c in queue_row.get_children():
		c.queue_free()
	var list := ([p.research] if p.research != "" else []) + p.rqueue
	if list.is_empty():
		queue_row.add_child(main._label("Nothing queued. Click a tech, then Add to the queue. Double-click adds a tech (and everything it needs) to the end of the queue.", 13, Main.DIM))
		return
	var seen := {}
	for k in list.size():
		var id: String = list[k]
		var ahead: int = seen.get(id, 0)
		seen[id] = ahead + 1
		var qi := k - (1 if p.research != "" else 0)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.icon = Tex.get_tex("tech_" + id)
		b.add_theme_constant_override("icon_max_width", 22)
		b.add_theme_font_size_override("font_size", 13)
		var nm := GameData.tech_name(id)
		if GameData.reps.has(id):
			nm += " %d" % (int(p.reps.get(id, 0)) + ahead + 1)
		var c := main.sim.research_cost(p, id, ahead)
		b.text = tr("%s  %s") % [nm, ("%d/%d" % [int(minf(p.rp, c)), int(c)]) if qi < 0 else (_mins(_points_until(p, qi)) if rate > 0.01 else "")]
		if qi < 0:
			b.add_theme_color_override("font_color", TechTreeView.C_STUDY)
		b.tooltip_text = "Click to show it in the tree"
		b.pressed.connect(func(): _select(id, true))
		queue_row.add_child(b)
		var x := Button.new()
		x.focus_mode = Control.FOCUS_NONE
		x.flat = true
		x.text = "x"
		x.tooltip_text = "Take it off the queue (and what needs it)"
		x.add_theme_color_override("font_color", Main.DIM)
		x.pressed.connect(func():
			main.sim.unqueue_research(p, qi)
			_fill_tech()
			main._refresh_research())
		queue_row.add_child(x)


func _chip(p: Sim.Player, id: String) -> String:
	var st := tree.state_of(id)
	var col: String = {"done": "8fc070", "avail": "d8aa4a", "study": "8fc0ff", "locked": "9a9c88"}[st]
	return "[url=%s][color=#%s]%s%s[/color][/url]" % [id, col, ("✓ " if st == "done" else ""), GameData.tech_name(id)]


func _fill_detail(p: Sim.Player) -> void:
	for c in actions.get_children():
		c.queue_free()
	var id := tree.sel
	if id == "" or not (GameData.techs.has(id) or GameData.reps.has(id)):
		detail.text = tr("[font_size=18][color=#d8aa4a]The tech tree[/color][/font_size]\n\nEach card is a tech. Lines run from what a tech [b]needs[/b] to what it [b]leads to[/b]. Ages run left to right; each band is a branch of your realm.\n\nHover a card to light up its whole line. Click it to see what it does. Double-click a tech to [b]add it to the end of the queue[/b], with everything it needs.\n\n[color=#8fc070]Green[/color]: done.  [color=#8fc0ff]Blue[/color]: being studied.  [color=#d8aa4a]Gold[/color]: ready to study.  Grey: needs another tech first.\n\n[b]Mastery[/b] (the bottom band): each age has three studies you can take again and again, a few times each, for a small bonus every time. They open when your realm enters their age.\n\n[color=#9a9c88]Drag or use the wheel to move around. Ctrl + wheel, a pinch, or the - and + buttons zoom. Scriptoriums, libraries and universities make research points; nobles add a little. Points carry over, so you can save them up.%s[/color]") % (" Research victory is on: the first realm to finish the Industrial Revolution wins." if main.sim.research_victory else "")
		return
	var st := tree.state_of(id)
	var label: String = {"done": "[color=#8fc070]Done[/color]", "study": "[color=#8fc0ff]Being studied[/color]", "avail": "[color=#d8aa4a]Ready to study[/color]", "locked": "[color=#9a9c88]Locked[/color]"}[st]
	if GameData.reps.has(id):
		_fill_rep(p, id, st, label)
		return
	var t: Dictionary = GameData.techs[id]
	var lane := ""
	for ln in GameData.lanes:
		if String(ln[0]) == String(t.get("lane", "")): lane = String(ln[1])
	var s := "[font_size=18][b]%s[/b][/font_size]\n[color=#9a9c88]%s age%s[/color]\n%s   %d research points\n\n%s" % [String(t.name), GameData.age_name(int(t.get("age", 0))), (" · " + lane) if lane != "" else "", label, int(t.cost), String(t.get("info", ""))]
	var eff := GameData.effect_text(t.get("effects", {}))
	if eff != "":
		s += "\n\n[color=#9a9c88]EFFECTS[/color]\n" + eff
	var ub := tree.unlocks(id)
	var seeds := Crops.seeds_of(id)
	if not ub.is_empty() or not seeds.is_empty():
		var names: Array = ub.map(func(b): return String(GameData.bld[b].name))
		for sd in seeds:
			names.append(("%s seed" % sd) if not sd.contains("rotation") else sd)
		s += "\n\n[color=#9a9c88]UNLOCKS[/color]\n" + ", ".join(names)
	var req: Array = t.get("requires", [])
	var needs_txt := "  ".join(req.map(func(r): return _chip(p, r)))
	var need_n := int(t.get("need", 0))
	if t.get("gate", false) and need_n > 0:
		var have := main.sim.gate_have(p, id)
		var prev := GameData.age_name(int(t.get("age", 0)) - 1)
		needs_txt += ("  " if needs_txt != "" else "") + "[color=%s]%d of %d %s techs[/color]" % ["#8fc070" if have >= need_n else "#e0a060", mini(have, need_n), need_n, prev]
	s += "\n\n[color=#9a9c88]NEEDS[/color]\n" + (needs_txt if needs_txt != "" else "nothing: open from the start")
	if t.get("gate", false):
		s += "\n\n[color=#d8aa4a]This study ends the %s age and opens the %s age: every %s tech needs it.[/color]" % [GameData.age_name(int(t.get("age", 0)) - 1), GameData.age_name(int(t.get("age", 0))), GameData.age_name(int(t.get("age", 0)))]
	var ks: Array = tree.kids.get(id, [])
	if not ks.is_empty():
		s += "\n\n[color=#9a9c88]LEADS TO[/color]\n" + "  ".join(ks.map(func(k): return _chip(p, k)))
	var queued := p.rqueue.has(id)
	if st == "locked":
		var path := main.sim.research_path(p, id)
		var pts := 0.0
		var todo := []
		for x in path:
			pts += main.sim.research_cost(p, x)
			if not (x == p.research or p.rqueue.has(x)):
				todo.append(x)
		s += "\n\n[color=#9a9c88]THE WAY THERE[/color]\n%d more tech%s first, %d points in all (%s):\n" % [path.size() - 1, "" if path.size() == 2 else "s", int(pts), _mins(maxf(0.0, pts - p.rp))]
		s += "\n".join(path.map(func(x): return "  %s  [color=#9a9c88]%d[/color]" % [_chip(p, x), int(main.sim.research_cost(p, x))]))
		if not todo.is_empty():
			_action("Queue the way there (%d)" % todo.size(), func():
				for x in todo: main.sim.queue_research(p, x)
				main.sim.human())
	elif st == "avail":
		# new techs go to the end of the queue; studying one at once is the second choice
		if not queued:
			_action("Add to the queue" if p.research != "" else "Study it", func(): main.sim.queue_research(p, id), true)
		if p.research != "":
			_action("Study it now (ahead of the queue)", func(): main.sim.set_research(p, id))
	elif st == "study":
		var c := main.sim.research_cost(p, id)
		s += "\n\n%d of %d points; about %s to go." % [int(minf(p.rp, c)), int(c), _mins(maxf(0.0, c - p.rp))]
		if p.rqueue.is_empty():
			_action("Stop studying it", func(): main.sim.unqueue_research(p, -1))
		else:
			_action("Skip it: study %s instead" % GameData.tech_name(p.rqueue[0]), func(): main.sim.unqueue_research(p, -1))
	if queued:
		var qi := p.rqueue.find(id)
		s += "\n\nNumber %d in the queue: done in about %s." % [qi + 1, _mins(_points_until(p, qi))]
		_action("Take it off the queue", func(): main.sim.unqueue_research(p, qi))
	detail.text = s


func _fill_rep(p: Sim.Player, id: String, st: String, label: String) -> void:
	var r: Dictionary = GameData.reps[id]
	var lv := int(p.reps.get(id, 0))
	var mx := int(r.get("max", 1))
	var planned := (1 if p.research == id else 0) + p.rqueue.count(id)
	var s := "[font_size=18][b]%s[/b][/font_size]\n[color=#9a9c88]%s age · repeatable[/color]\n%s   level %d of %d\n\n%s" % [String(r.name), GameData.age_name(int(r.get("age", 0))), label, lv, mx, String(r.get("info", ""))]
	s += "\n\n[color=#9a9c88]EACH LEVEL[/color]\n" + GameData.effect_text(r.get("effects", {}))
	if lv > 0:
		var so_far := {}
		for k in r.effects: so_far[k] = float(r.effects[k]) * lv
		s += "\n\n[color=#9a9c88]SO FAR[/color]\n" + GameData.effect_text(so_far)
	var lvls := []
	for k in mx:
		var c := int(GameData.rep_cost(id, k))
		var col := "8fc070" if k < lv else ("d8aa4a" if k < lv + planned else "9a9c88")
		lvls.append("[color=#%s]%d: %d[/color]" % [col, k + 1, c])
	s += "\n\n[color=#9a9c88]LEVELS (points)[/color]\n" + "   ".join(lvls)
	s += "\n[color=#9a9c88]Each level costs half the first again. The %s age allows %d levels; later ages bring their own studies.[/color]" % [GameData.age_name(int(r.get("age", 0))), mx]
	if st == "locked":
		s += "\n\nOpens when your realm enters the %s age." % GameData.age_name(int(r.get("age", 0)))
	elif lv + planned < mx:
		_action(("Queue level %d" if p.research != "" else "Study level %d") % (lv + planned + 1), func(): main.sim.queue_research(p, id), true)
		if st != "study" and p.research != "":
			_action("Study level %d now (ahead of the queue)" % (lv + 1), func(): main.sim.set_research(p, id))
	if p.rqueue.has(id):
		_action("Take one level off the queue", func(): main.sim.unqueue_research(p, p.rqueue.rfind(id)))
	detail.text = s


func _action(text: String, cb: Callable, main_one := false) -> void:
	var b := main._button(text, func():
		cb.call()
		_fill_tech()
		main._refresh_research())
	if main_one:
		b.add_theme_color_override("font_color", Main.BRASS)
	actions.add_child(b)
