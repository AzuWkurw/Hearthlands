class_name UiProblems
extends RefCounted
## The Problems list: every one of your buildings that cannot work and why, and attacks on you, longest
## waiting first, each with a Go button. Opened from the top bar (or the key, O by default). The same
## problems blink on the minimap: red where you are attacked, amber where a building is stuck.
## Only the interface: it reads the game and changes nothing in it.

var main: Main
var box: PanelContainer
var list: VBoxContainer
var title: Label
var since := {}          # building id (or -attack uid) -> real time the problem was first seen
var count := 0


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
	var foot := Label.new()
	foot.text = "Longest waiting first. Go moves the map there."
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Main.DIM)
	v.add_child(foot)
	box.visible = false
	main.add_child(box)


func toggle() -> void:
	box.visible = not box.visible
	refresh()


## [sort key, text, colour, tile, building id] for every problem now.
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
			out.append([1e9, tr("%s attacks your %s (%d soldiers)") % [sim.players[a.p - 1].name, String(t.def.name), a.n], Color("d9483d"), Vector2i(t.x, t.y), t.id])
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
		out.append([now - float(since[b.id]), "%s: %s" % [String(b.def.name), why], col, Vector2i(b.x, b.y), b.id])
	for k in since.keys():
		if not seen.has(k):
			since.erase(k)
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
	if b.reno_to >= 0:
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
	if "no patients" in b.msg:
		return ""
	# the first part of the message is enough here; the info box has the rest
	var m := b.msg.get_slice(": ", 0) if b.msg.begins_with("Stores are full") else b.msg
	return m.to_lower() if m.length() > 1 else m


## Called once a second.
func refresh() -> void:
	if box == null or main.sim == null or main.sim.w == 0:
		return
	var ps := problems()
	count = ps.size()
	# the minimap shows them all, the list the first twelve
	var alerts := []
	for p in ps:
		alerts.append([p[3], p[2]])
	main.minimap.alerts = alerts
	main.problems_btn.text = tr("Problems (%d)") % count
	if not box.visible:
		return
	title.text = tr("PROBLEMS (%d)") % count
	for c in list.get_children():
		c.queue_free()
	if ps.is_empty():
		list.add_child(main._label("Nothing is stuck. Well done.", 13, Main.DIM))
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
		row.add_child(main._button("Go", func():
			main.view.center_on(Vector2(tile.x + 0.5, tile.y + 0.5))
			main.view.sel_id = id
			main._refresh_sel()))
		list.add_child(row)
	if ps.size() > 12:
		list.add_child(main._label(tr("and %d more") % (ps.size() - 12), 12, Main.DIM))
