class_name UiBlueprints
extends RefCounted
## The Blueprints window (U, build 58): your saved groups of buildings sorted into categories, one tab
## each. Copy a group from the map, name it and pick its category; place it again with one click;
## rename, move, share as a code or delete. The blueprints themselves are in Blueprints.

var main: Main
var bps: Blueprints
var win: Window
var tabs: TabContainer
var head: Label
var new_cat: LineEdit
var code_edit: LineEdit
# the window that names a blueprint just copied
var save_win: Window
var save_name: LineEdit
var save_cat: OptionButton
var save_info: Label
var save_prev: Preview
var _pending: Dictionary = {}
var _tab := 0


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	bps = Blueprints.new()
	win = Window.new()
	win.title = "Blueprints"
	win.transient = true
	win.wrap_controls = false
	win.size = Vector2i(820, 640)
	win.theme = UiLog.window_theme()
	win.visible = false
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", main._panel_style(0.96))
	win.add_child(bg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	bg.add_child(v)
	head = main._label(tr("A blueprint is a group of your buildings and the roads between them, kept for every game. Copy one from the map, then place it again anywhere with one click: all its building sites and roads go down at once. Trees or roads in the way? You are asked whether to clear them."), 13, Main.DIM)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var cb := main._button(tr("Copy from the map"), start_copy)
	cb.tooltip_text = tr("Click two corners of an area of your land: its buildings and roads become a blueprint")
	row.add_child(cb)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = tr("Paste a blueprint code here")
	code_edit.custom_minimum_size = Vector2(220, 0)
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(code_edit)
	row.add_child(main._button(tr("Add from code"), _from_code))
	row.add_child(VSeparator.new())
	new_cat = LineEdit.new()
	new_cat.placeholder_text = tr("New category")
	new_cat.custom_minimum_size = Vector2(130, 0)
	new_cat.text_submitted.connect(func(_t): _add_cat())
	row.add_child(new_cat)
	row.add_child(main._button(tr("Add"), _add_cat))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.tab_changed.connect(func(i): _tab = i)
	v.add_child(tabs)
	win.close_requested.connect(func(): win.visible = false)
	main.add_child(win)
	_build_save_win()


func toggle() -> void:
	if win.visible:
		win.visible = false
		return
	refresh()
	win.popup_centered()


func refresh() -> void:
	for c in tabs.get_children():
		tabs.remove_child(c)
		c.queue_free()
	for cat in bps.cats:
		var sc := ScrollContainer.new()
		sc.name = "%s (%d)" % [tr(cat), bps.in_cat(cat).size()]
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var lv := VBoxContainer.new()
		lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lv.add_theme_constant_override("separation", 6)
		sc.add_child(lv)
		tabs.add_child(sc)
		var ids := bps.in_cat(cat)
		if ids.is_empty():
			var e := main._label(tr("No blueprints here yet. Press \"Copy from the map\", or move one here from another category."), 13, Main.DIM)
			e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lv.add_child(e)
		for i in ids:
			lv.add_child(_row(i))
		if cat != "Other":
			var rm := main._button(tr("Remove the category \"%s\" (its blueprints go to Other)") % tr(cat), func():
				bps.remove_cat(cat)
				refresh())
			rm.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			lv.add_child(rm)
	tabs.current_tab = clampi(_tab, 0, maxi(0, tabs.get_tab_count() - 1))


func _row(i: int) -> Control:
	var bp: Dictionary = bps.list[i]
	var pc := PanelContainer.new()
	var sb := main._panel_style(0.5)
	pc.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	pc.add_child(h)
	var pv := Preview.new()
	pv.bp = bp
	pv.custom_minimum_size = Vector2(96, 96)
	h.add_child(pv)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(mid)
	var ne := LineEdit.new()
	ne.text = String(bp.name)
	ne.tooltip_text = tr("Type a new name and press Enter")
	ne.text_submitted.connect(func(t): bps.rename(i, t); refresh())
	mid.add_child(ne)
	var info := main._label(Blueprints.summary(bp), 13)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(info)
	var c := Blueprints.cost(bp)
	var cs := []
	for k in c:
		cs.append("%d %s" % [c[k], GameData.res_name(k).to_lower()])
	var cl := main._label(tr("%d×%d tiles, %d road tiles. Costs %s.") % [int(bp.w), int(bp.h), (bp.roads as Array).size(), ", ".join(cs) if not cs.is_empty() else tr("nothing")], 12, Main.DIM)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(cl)
	var right := VBoxContainer.new()
	h.add_child(right)
	var pb := main._button(tr("Place"), func(): start_place(i))
	pb.tooltip_text = tr("Put it down on the map (hold Shift to place it again)")
	right.add_child(pb)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	for k in bps.cats.size():
		ob.add_item(tr(bps.cats[k]))
		if bps.cats[k] == bp.cat:
			ob.select(k)
	ob.tooltip_text = tr("Its category")
	ob.item_selected.connect(func(k): bps.set_cat(i, bps.cats[k]); refresh())
	right.add_child(ob)
	var row2 := HBoxContainer.new()
	right.add_child(row2)
	var kb := main._button(tr("Code"), func():
		DisplayServer.clipboard_set(Blueprints.to_code(bps.list[i]))
		main._show_hint(tr("The blueprint's code is copied: paste it into the Blueprints window of another game to add it there."), 4.0))
	kb.tooltip_text = tr("Copy it as a code to share")
	row2.add_child(kb)
	row2.add_child(main._button(tr("Delete"), func():
		main.confirm(tr("Delete the blueprint \"%s\"?") % String(bp.name), tr("Delete"), func(): bps.remove(i); refresh())))
	return pc


func _add_cat() -> void:
	if bps.add_cat(new_cat.text):
		new_cat.text = ""
		_tab = bps.cats.size() - 1
		refresh()


func _from_code() -> void:
	var bp := Blueprints.from_code(code_edit.text)
	if bp.is_empty():
		main._show_hint(tr("That is not a blueprint code (it starts with HLBP1:)."), 3.0)
		return
	code_edit.text = ""
	bps.add(bp)
	_tab = bps.cats.find(bp.cat)
	refresh()
	main._show_hint(tr("Blueprint \"%s\" added.") % String(bp.name), 3.0)


# ---------------------------------------------------------------- copying and placing

## The copy tool: two clicks on the map mark the area.
func start_copy() -> void:
	win.visible = false
	main._cancel_place()
	main.view.place_type = "@bp_copy"
	main.view.bp_corner = Vector2i(-1, -1)
	main._show_hint(tr("Click one corner of the area to copy, then the opposite corner (Esc cancels)."), 5.0)


func start_place(i: int) -> void:
	if i < 0 or i >= bps.list.size():
		return
	win.visible = false
	main._cancel_place()
	main.view.place_type = "@bp_place"
	main.view.blueprint = bps.list[i]
	main._show_hint(tr("Placing \"%s\": click where it should go (Esc cancels). Hold Shift to place it again.") % String(bps.list[i].name), 4.0)


## A click with the copy tool (see Main._use_tool).
func copy_click(t: Vector2i) -> void:
	var view: MapView = main.view
	if view.bp_corner.x < 0:
		view.bp_corner = t
		return
	var r := Rect2i(view.bp_corner, t - view.bp_corner).abs()
	r.size += Vector2i.ONE
	view.bp_corner = Vector2i(-1, -1)
	var bp := Blueprints.capture(main.sim, 1, r, _guess_name(r), "Other")
	if bp.is_empty():
		main._show_hint(tr("No buildings of yours in that area (the headquarters and wonders are never copied)."), 3.5)
		return
	main.view.place_type = ""
	ask_save(bp)


func _guess_name(r: Rect2i) -> String:
	var bp := Blueprints.capture(main.sim, 1, r)
	if bp.is_empty():
		return "Blueprint"
	var first: Dictionary = GameData.bld[bp.items[0][0]]
	return "%s group" % String(first.name) if bp.items.size() > 1 else String(first.name)


## A blueprint's category guessed from its buildings: homes, military, food or industry.
static func guess_cat(bp: Dictionary) -> String:
	var n := {"Homes": 0, "Military": 0, "Food": 0, "Industry": 0}
	for it in bp.items:
		var d: Dictionary = GameData.bld[it[0]]
		if d.has("housing"):
			n.Homes += 1
		elif d.has("radius") or d.has("garrison"):
			n.Military += 1
		elif GameData.trade(String(it[0])) in ["farming", "hunting", "victuals"]:
			n.Food += 1
		else:
			n.Industry += 1
	var best := "Other"
	var most := 0
	for k in n:
		if int(n[k]) > most:
			most = int(n[k]); best = k
	return best


func _build_save_win() -> void:
	save_win = Window.new()
	save_win.title = "New blueprint"
	save_win.transient = true
	save_win.exclusive = true
	save_win.wrap_controls = false
	save_win.size = Vector2i(520, 300)
	save_win.theme = UiLog.window_theme()
	save_win.visible = false
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", main._panel_style(0.97))
	save_win.add_child(bg)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	bg.add_child(h)
	save_prev = Preview.new()
	save_prev.custom_minimum_size = Vector2(150, 150)
	h.add_child(save_prev)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	h.add_child(v)
	v.add_child(main._label(tr("Name"), 13, Main.DIM))
	save_name = LineEdit.new()
	save_name.text_submitted.connect(func(_t): _save_pending())
	v.add_child(save_name)
	v.add_child(main._label(tr("Category"), 13, Main.DIM))
	save_cat = OptionButton.new()
	v.add_child(save_cat)
	save_info = main._label("", 13)
	save_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(save_info)
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(main._button(tr("Save blueprint"), _save_pending))
	row.add_child(main._button(tr("Cancel"), func(): save_win.visible = false))
	save_win.close_requested.connect(func(): save_win.visible = false)
	main.add_child(save_win)


## Asks the name and category for blueprint bp, just copied from the map.
func ask_save(bp: Dictionary) -> void:
	_pending = bp
	save_name.text = String(bp.name)
	save_cat.clear()
	var guess := guess_cat(bp)
	for k in bps.cats.size():
		save_cat.add_item(tr(bps.cats[k]))
		if bps.cats[k] == guess:
			save_cat.select(k)
	save_info.text = tr("%s, and %d road tiles.") % [Blueprints.summary(bp), (bp.roads as Array).size()]
	save_prev.bp = bp
	save_prev.queue_redraw()
	save_win.popup_centered()
	save_name.grab_focus()
	save_name.select_all()


func _save_pending() -> void:
	if _pending.is_empty():
		return
	_pending.name = save_name.text.strip_edges().left(40) if save_name.text.strip_edges() != "" else "Blueprint"
	_pending.cat = bps.cats[maxi(0, save_cat.selected)]
	bps.add(_pending)
	_tab = bps.cats.find(_pending.cat)
	main._show_hint(main.keys.keyed("Blueprint \"%s\" saved in %s. Open Blueprints (U) to place it.") % [String(_pending.name), tr(_pending.cat)], 4.0)
	_pending = {}
	save_win.visible = false


## A click with the placing tool: asks first when trees or roads are in the way.
func place_click(t: Vector2i) -> void:
	var sim: Sim = main.sim
	var bp: Dictionary = main.view.blueprint
	if bp.is_empty():
		return
	var at := corner_at(bp, t)
	var obs := Blueprints.obstacles(sim, 1, bp, at)
	var nt := (obs.trees as PackedInt32Array).size()
	var nr := (obs.roads as PackedInt32Array).size()
	if nt + nr > 0:
		var parts := []
		if nt > 0: parts.append(tr("%d trees") % nt if nt != 1 else tr("a tree"))
		if nr > 0: parts.append(tr("%d road tiles") % nr if nr != 1 else tr("a road tile"))
		main.confirm(tr("In the way of this blueprint: %s. Clear the way and build? (The wood of felled trees is lost; taking up roads can cut buildings off.)") % " and ".join(parts),
			tr("Clear and build"), func():
				Blueprints.clear(sim, 1, obs)
				_do_place(bp, at))
		return
	_do_place(bp, at)


func _do_place(bp: Dictionary, at: Vector2i) -> void:
	var sim: Sim = main.sim
	var res := Blueprints.place(sim, sim.human(), bp, at)
	var placed := int(res[0])
	var why: Dictionary = res[1]
	for b in sim.realm_blds(sim.human()):
		if b.state == "build" and b.x >= at.x and b.y >= at.y and b.x < at.x + int(bp.w) and b.y < at.y + int(bp.h):
			main.undo_ui.placed(b)
	if placed > 0:
		if main.sound != null:
			main.sound.play("place", 0.8)
		sim.emit_log("Placing the blueprint %s: %d building sites." % [String(bp.name), placed], Main.DIM, at)
	var msg := tr("%d of %d buildings placed.") % [placed, (bp.items as Array).size()]
	for r in why:
		msg += " " + tr("%d not: %s.") % [int(why[r]), tr(r)]
	main._show_hint(msg, 5.0)
	if not Input.is_key_pressed(KEY_SHIFT) and placed > 0:
		main.view.place_type = ""
		main.view.blueprint = {}
	main._refresh_all()


## The top-left corner of blueprint bp when the mouse is on tile t (the mouse holds its middle).
static func corner_at(bp: Dictionary, t: Vector2i) -> Vector2i:
	return t - Vector2i(int(bp.w) / 2, int(bp.h) / 2)


static func _cap(t: String) -> String:
	return t.left(1).to_upper() + t.substr(1)


## A small picture of a blueprint: its roads and buildings (by size) on a dark ground.
class Preview extends Control:
	var bp: Dictionary = {}

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.1, 0.07, 0.9))
		if bp.is_empty():
			return
		var w := maxf(1.0, float(bp.w))
		var h := maxf(1.0, float(bp.h))
		var s := minf((size.x - 6.0) / w, (size.y - 6.0) / h)
		var o := (size - Vector2(w, h) * s) / 2.0
		for r in bp.roads:
			draw_rect(Rect2(o + Vector2(r[0], r[1]) * s, Vector2(s, s)), Color(0.66, 0.55, 0.37))
		for it in bp.items:
			var sz := String(GameData.bld[it[0]].get("size", "mine" if GameData.bld[it[0]].has("mine") else "medium"))
			var col := Color("d8aa4a") if sz == "large" else (Color("86ad5c") if sz == "small" else Color("c97b54"))
			for off: Vector2i in Sim.PLOTS.get(sz, Sim.PLOTS.medium):
				draw_rect(Rect2(o + Vector2(int(it[1]) + off.x, int(it[2]) + off.y) * s, Vector2(s, s)), Color(col, 0.45))
			draw_rect(Rect2(o + Vector2(it[1], it[2]) * s, Vector2(s, s)), col)
