class_name UiWelcome
extends Control
## The welcome screen shown when the game starts, over the realm the menu has waiting behind it.
## It offers to continue the last game, start a new realm, the campaign, saved games, Settings and quitting.
## Its look: the title over the slowly drifting map, embers rising from the bottom, the menu and, beside
## it, what is new in this build (from the change log).

var main: Main
var _t := 0.0
var _last: Dictionary = {}     # the newest save: {"base", "meta"}, empty when there is none
var _cam0 := Vector2.ZERO     # where the map was when the screen opened (it drifts round there)
var _hidden: Array = []        # the interface parts hidden while the screen is open, shown again after


func _init(m: Main) -> void:
	main = m
	name = "Welcome"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## Builds the screen and shows it.
func open() -> void:
	for c in get_children():
		c.queue_free()
	_last = _newest_save()
	_build()
	# only the map stays behind the screen: the rest of the interface (the new-game screen, the side
	# panel, the bars, the event log) is hidden and comes back after
	if not visible:
		_hidden.clear()
		for c in main.get_children():
			if c != self and c != main.view and (c is CanvasItem or c is Window) and c.visible:
				_hidden.append(c)
				c.visible = false
		# the map fills the whole window, side panel's room too
		main.view.offset_right = 0
		_cam0 = main.view.cam
		var hq = main.sim.human().hq if main.sim.w > 0 else null
		if hq != null:
			# near the headquarters, but far enough in that the map's edge stays off screen as it drifts
			var half := main.size / maxf(1.0, main.view.zoom) * 0.5 + Vector2(11, 6)
			var hi := Vector2(main.sim.w, main.sim.h) - half
			_cam0 = Vector2(clampf(hq.x + 0.5, half.x, maxf(half.x, hi.x)), clampf(hq.y + 0.5, half.y, maxf(half.y, hi.y)))
			main.view.cam = _cam0
	visible = true
	main.move_child(self, main.get_child_count() - 1)


## Closes the screen onto the new-game screen (an action that goes elsewhere hides that again itself).
func close() -> void:
	if not visible:
		return
	visible = false
	for c in _hidden:
		if is_instance_valid(c):
			c.visible = true
	_hidden.clear()
	main.view.offset_right = -Main.SIDE_W
	main.setup.visible = true


func _input(event: InputEvent) -> void:
	# Escape goes on to the new-game screen
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	# the map behind drifts slowly, so the realm seems alive
	if main.view != null:
		main.view.cam = _cam0 + Vector2(sin(_t * 0.05) * 10.0, sin(_t * 0.037) * 5.0)
		main.view.queue_redraw()


# ---------------------------------------------------------------- parts

func _shade(alpha: float) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.045, 0.03, alpha)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


## Dark edges round the screen, drawn as a soft gradient on each side.
func _vignette() -> void:
	for side in 4:
		var g := Gradient.new()
		g.set_color(0, Color(0.02, 0.02, 0.015, 0.85))
		g.set_color(1, Color(0.02, 0.02, 0.015, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = [Vector2(0, 0.5), Vector2(1, 0.5), Vector2(0.5, 0), Vector2(0.5, 1)][side]
		gt.fill_to = [Vector2(1, 0.5), Vector2(0, 0.5), Vector2(0.5, 1), Vector2(0.5, 0)][side]
		var r := TextureRect.new()
		r.texture = gt
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		match side:
			0: r.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE); r.offset_right = 360
			1: r.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE); r.offset_left = -360
			2: r.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE); r.offset_bottom = 220
			3: r.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE); r.offset_top = -260
		add_child(r)


## Sparks rising from the bottom of the screen, as from a fire just out of sight.
func _embers(amount := 70) -> void:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(1100, 10)
	p.direction = Vector2(0, -1)
	p.spread = 18.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 90.0
	p.gravity = Vector2(6, -8)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 4.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.35, 0.0))
	ramp.add_point(0.15, Color(1.0, 0.7, 0.3, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.8, 0.25, 0.1, 0.0))
	p.color_ramp = ramp
	add_child(p)
	# kept at the bottom middle when the window is resized
	var place := func(): p.position = Vector2(size.x * 0.5, size.y + 20)
	resized.connect(place)
	place.call()


func _title(text: String, fsize: int) -> Label:
	var l := main._label(text, fsize, Main.BRASS)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 4)
	return l


func _menu_button(text: String, sub: String, cb: Callable, big := false) -> Button:
	var b := main._button(text if sub == "" else tr(text) + "\n" + sub, cb)
	b.custom_minimum_size = Vector2(300, 58 if sub != "" else (50 if big else 40))
	b.add_theme_font_size_override("font_size", 18 if big else 15)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.13, 0.15, 0.125, 0.88)
	n.border_color = Color("5a5236") if big else Color("3a4136")
	n.set_border_width_all(1)
	n.set_corner_radius_all(3)
	n.set_content_margin_all(8)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(0.22, 0.2, 0.13, 0.95)
	h.border_color = Main.BRASS
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_color_override("font_hover_color", Color("ffe3a0"))
	return b


## The menu's buttons, in order: continue (when there is a save), new realm, campaign, saved games,
## settings, quit.
func _menu(v: VBoxContainer) -> void:
	if not _last.is_empty():
		v.add_child(_menu_button("Continue", _save_line(), _continue, true))
	v.add_child(_menu_button("New realm", "", close, _last.is_empty()))
	v.add_child(_menu_button("Campaign", "", func(): close(); main.campaign_ui.show()))
	v.add_child(_menu_button("Load a saved game", "", func(): close(); main._open_saves()))
	v.add_child(_menu_button("Settings", "", func(): close(); main._open_settings()))
	v.add_child(_menu_button("Quit", "", func(): get_tree().quit()))


func _version_label() -> Label:
	var l := main._label("Hearthlands " + Version.long(), 12, Main.DIM)
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.offset_right = -14
	l.offset_bottom = -10
	return l


func _newest_save() -> Dictionary:
	var dir := DirAccess.open(Main.SAVE_DIR)
	if dir == null:
		return {}
	var best := ""
	var best_t := -1
	for fn in dir.get_files():
		if fn.ends_with(".save"):
			var t := FileAccess.get_modified_time(Main.SAVE_DIR + "/" + fn)
			if t > best_t:
				best_t = t
				best = fn
	if best == "":
		return {}
	var d = main.saves_ui._read_save(Main.SAVE_DIR + "/" + best)
	var meta: Dictionary = d.get("meta", {}) if d is Dictionary else {}
	return {"base": best.get_basename(), "meta": meta}


func _save_line() -> String:
	var m: Dictionary = _last.get("meta", {})
	var gt := int(m.get("game_time", 0))
	return tr("%s · %s age · %d:%02d played" % [String(m.get("name", _last.base)), String(m.get("age", "?")), gt / 3600, (gt / 60) % 60])


func _continue() -> void:
	close()
	main.saves_ui._load_game(String(_last.base))


## The newest build's notes from the change log: its title line and its first points, each cut to
## the words before its first colon. In another language they come from CHANGELOG_<code>.md (written
## the same way) when that file has the newest build too; otherwise they stay English.
static func news(count := 6, lang := "") -> Array:
	var en := _news_from("res://CHANGELOG.md", count)
	if lang != "" and lang != "en" and not en.is_empty():
		var other := _news_from("res://CHANGELOG_%s.md" % lang, count)
		if not other.is_empty() and _build_no(String(other[0])) == _build_no(String(en[0])):
			return other
	return en


static func _news_from(path: String, count: int) -> Array:
	var out := []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var inside := false
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("## "):
			if inside:
				break
			inside = true
			out.append(line.substr(3).get_slice(" (", 0))
		elif inside and line.begins_with("- ") and out.size() <= count:
			var s := line.substr(2)
			out.append(s.get_slice(":", 0).get_slice(". ", 0))
	return out


## The build number in a change log heading ("Build 77" -> "77", "Wersja 75.1" -> "75.1").
static func _build_no(head: String) -> String:
	var m := RegEx.create_from_string("[0-9]+(\\.[0-9]+)?").search(head)
	return m.get_string() if m != null else head


# ---------------------------------------------------------------- the screen

func _build() -> void:
	_shade(0.45)
	_vignette()
	_embers()
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	cc.add_child(v)
	v.add_child(_title("HEARTHLANDS", 84))
	var sub := main._label("Build a realm from the first bronze to the railways", 18, Color("e6d6b0"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var gap := Control.new(); gap.custom_minimum_size = Vector2(0, 28); v.add_child(gap)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	v.add_child(row)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 6)
	row.add_child(mv)
	_menu(mv)
	# what is new in this build, from the change log (left out when the log can't be read)
	var items := news(7, TranslationServer.get_locale().get_slice("_", 0))
	if items.size() > 1:
		var np := PanelContainer.new()
		var sb := main._panel_style(0.88)
		sb.set_corner_radius_all(3)
		sb.set_content_margin_all(12)
		np.add_theme_stylebox_override("panel", sb)
		np.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(np)
		var nv := VBoxContainer.new()
		nv.add_theme_constant_override("separation", 6)
		np.add_child(nv)
		var head := main._label(tr("WHAT'S NEW") + "  ·  " + String(items[0]), 14, Main.BRASS)
		head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		nv.add_child(head)
		for k in range(1, items.size()):
			var l := main._label("•  " + String(items[k]), 14)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(420, 0)
			# already in the shown language (see news): not matched against translations again
			l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			nv.add_child(l)
	add_child(_version_label())
