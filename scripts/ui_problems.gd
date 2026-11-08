class_name UiProblems
extends RefCounted
## The Problems list: every one of your buildings that cannot work and why, and attacks on you, longest
## waiting first, each with a Go button. Opened from the top bar (or the key, O by default). The same
## problems blink on the minimap: red where you are attacked, amber where a building is stuck.
## A problem can be hidden with its x (or all at once with "Hide all"): it leaves the list, the count and
## the minimap until its reason changes, or for an attack until that attack is over. "Show hidden"
## brings them all back. Only the interface: it reads the game and changes nothing in it.

var main: Main
var box: PanelContainer
var list: VBoxContainer
var title: Label
var since := {}          # building id (or -attack uid) -> real time the problem was first seen
var count := 0
var hidden := {}         # building id (or -attack uid) -> the text it was hidden with
var hidden_now := 0      # how many problems are hidden at the moment
var show_hidden := false
var foot_row: HBoxContainer


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	box = PanelContainer.new()
	box.add_theme_stylebox_override("panel", main._panel_style(0.92))
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.offset_right = -Main.SIDE_W - 10
	box.offset_left = box.offset_right - 380
	box.offset_top = 96
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	box.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Main.BRASS)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var x := Button.new()
	x.text = "x"
	x.flat = true
	x.pressed.connect(func(): box.visible = false)
	top.add_child(x)
	list = VBoxContainer.new()
	v.add_child(list)
	foot_row = HBoxContainer.new()
	v.add_child(foot_row)
	var foot := Label.new()
	foot.text = "Longest waiting first. Go moves the map there, x hides one until its reason changes."
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Main.DIM)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.custom_minimum_size = Vector2(360, 0)
	v.add_child(foot)
	box.visible = false
	main.add_child(box)


func toggle() -> void:
	box.visible = not box.visible
	refresh()


## Hides the problem with key k (a building id, or minus an attack's uid) while its reason stays that
## of text t (numbers in it may change: "stores are full of flour (29 of 30)" stays hidden at 30).
func hide_one(k: int, t: String) -> void:
	hidden[k] = reason(t)
	refresh()


static var _digits: RegEx

static func reason(t: String) -> String:
	if _digits == null:
		_digits = RegEx.create_from_string("\\d+")
	return _digits.sub(t, "#", true)


func is_hidden(k: int, t: String) -> bool:
	return hidden.has(k) and String(hidden[k]) == reason(t)


## The problems not hidden (or all of them while "Show hidden" is on), with hidden_now counted.
func shown(ps: Array) -> Array:
	var out := []
	hidden_now = 0
	for p in ps:
		var k: int = p[5]
		if is_hidden(k, String(p[1])):
			hidden_now += 1
			if not show_hidden:
				continue
		out.append(p)
	return out


## [sort key, text, colour, tile, building id, key] for every problem now.
func problems() -> Array:
	var sim: Sim = main.sim
	var out := []
	var now := Time.get_ticks_msec() / 1000.0
	var seen := {}
	for a: Sim.Attack in sim.attacks:
		var t: Sim.Bld = sim.by_id.get(a.tgt)
		if t != null and t.p == 1:
			var k := -a.uid
			seen[k] = true
			if not since.has(k): since[k] = now
			out.append([1e9, tr("%s attacks your %s (%d soldiers)") % [sim.players[a.p - 1].name, String(t.def.name), a.n], Color("d9483d"), Vector2i(t.x, t.y), t.id, k])
	for b: Sim.Bld in sim.realm_blds(sim.human()):
		if b.dead or b.ty == "hq":
			continue
		var why := _why(b)
		if why == "":
			continue
		seen[b.id] = true
		if not since.has(b.id): since[b.id] = now
		var col := Color("e0b060")
		if why.begins_with("Nothing left") or why.begins_with("stores are full") or b.prio == Sim.PRIO_LOW:
			col = Color("a3a28b")
		out.append([now - float(since[b.id]), "%s: %s" % [String(b.def.name), why], col, Vector2i(b.x, b.y), b.id, b.id])
	for k in since.keys():
		if not seen.has(k):
			since.erase(k)
	# a problem that went away is forgotten, so it shows again if it comes back
	for k in hidden.keys():
		if not seen.has(k):
			hidden.erase(k)
	out.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[4] < b[4]))
	return out


## Why building b cannot work, or "" when it is fine (working, or paused on purpose).
func _why(b: Sim.Bld) -> String:
	var sim: Sim = main.sim
	if b.prio == Sim.PRIO_PAUSED:
		return ""
	if b.state == "build":
		# a site waiting a little while for its first loads is normal
		if b.msg == "Waiting for a road connection":
			return tr("no road yet")
		if b.msg == "Waiting for materials" and b.coming.is_empty():
			return sim.status(b).trim_prefix("Waiting for materials: ").to_lower()
		return ""
	if b.reno_to >= 0 or b.def.get("claim_only", false):
		return ""
	if not sim.connected(b):
		return tr("no road yet")
	if b.def.has("garrison"):
		return tr("no soldiers yet") if b.garrison <= 0 and b.walking <= 0 else ""
	if not b.def.has("cycle"):
		return ""
	if b.working or b.msg == "" or b.msg == "Working" or b.msg == "The worker is on his way":
		return ""
	if b.fails >= 12 and b.def.has("act"):
		return tr("Nothing left to gather nearby")
	if "no patients" in b.msg.to_lower():
		return ""
	# the first part of the message is enough here; the info box has the rest
	var m := b.msg.get_slice(": ", 0) if b.msg.begins_with("Stores are full") else b.msg
	return m.to_lower() if m.length() > 1 else m


## Called once a second.
func refresh() -> void:
	if box == null or main.sim == null or main.sim.w == 0:
		return
	var ps := shown(problems())
	count = ps.size() if not show_hidden else ps.size() - hidden_now
	# the minimap shows them all, the list the first twelve
	var alerts := []
	for p in ps:
		if not (show_hidden and is_hidden(int(p[5]), String(p[1]))):
			alerts.append([p[3], p[2]])
	main.minimap.alerts = alerts
	main.problems_btn.text = tr("Problems (%d)") % count
	if not box.visible:
		return
	title.text = tr("PROBLEMS (%d)") % count
	for c in list.get_children():
		c.queue_free()
	for c in foot_row.get_children():
		c.queue_free()
	if count > 0:
		foot_row.add_child(main._button("Hide all", func():
			for p in ps:
				hidden[int(p[5])] = reason(String(p[1]))
			show_hidden = false
			refresh()))
	if hidden_now > 0:
		var sh := main._button(tr("Show hidden (%d)") % hidden_now, func():
			show_hidden = not show_hidden
			refresh())
		sh.toggle_mode = true
		sh.set_pressed_no_signal(show_hidden)
		foot_row.add_child(sh)
		foot_row.add_child(main._button("Unhide all", func():
			hidden.clear()
			show_hidden = false
			refresh()))
	if ps.is_empty():
		list.add_child(main._label("Nothing is stuck. Well done." if hidden_now == 0 else "Nothing else is stuck.", 13, Main.DIM))
	for p in ps.slice(0, 12):
		var row := HBoxContainer.new()
		var dot := ColorRect.new()
		dot.color = p[2]
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var l := main._label(String(p[1]), 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(280, 0)
		row.add_child(l)
		var tile: Vector2i = p[3]
		var id: int = p[4]
		var key: int = p[5]
		var txt := String(p[1])
		var hid := is_hidden(key, txt)
		if hid:
			l.add_theme_color_override("font_color", Main.DIM)
		row.add_child(main._button("Go", func():
			main.view.center_on(Vector2(tile.x + 0.5, tile.y + 0.5))
			main.view.sel_id = id
			main._refresh_sel()))
		if hid:
			var u := main._button("show", func():
				hidden.erase(key)
				refresh())
			u.tooltip_text = "Show this problem again"
			row.add_child(u)
		else:
			var xb := main._button("x", func(): hide_one(key, txt))
			xb.tooltip_text = "Hide this problem until its reason changes"
			row.add_child(xb)
		list.add_child(row)
	if ps.size() > 12:
		list.add_child(main._label(tr("and %d more") % (ps.size() - 12), 12, Main.DIM))
