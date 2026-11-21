class_name UiWelcome
extends Control
## The welcome screen shown when the game starts, over the realm the menu has waiting behind it.
## It offers to continue the last game, start a new realm, the campaign, saved games, Settings and quitting.
## Three looks are built while one is chosen (settings.welcome_style):
##   0 "Hearth fire": the title over the slowly drifting map, with embers rising from the bottom
##   1 "Seven ages": the seven ages in pictures along the top, the menu and what is new in this build
##   2 "First steps": a welcome card for new players with three short lessons and the last game to go on with

const STYLES := ["Hearth fire", "Seven ages", "First steps"]
const EMBER := Color("ff9a3c")

var main: Main
var style := 0
var _t := 0.0
var _age_cards: Array = []
var _age_lit := -1
var _tip_lbl: Label
var _tip_i := 0
var _last: Dictionary = {}     # the newest save: {"base", "meta"}, empty when there is none
var _cam0 := Vector2.ZERO     # where the map was when the screen opened (it drifts round there)
var _hidden: Array = []        # the interface parts hidden while the screen is open, shown again after


func _init(m: Main) -> void:
	main = m
	name = "Welcome"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## Builds the screen in the chosen look and shows it.
func open(st: int) -> void:
	style = clampi(st, 0, STYLES.size() - 1)
	for c in get_children():
		c.queue_free()
	_age_cards.clear()
	_age_lit = -1
	_tip_lbl = null
	_last = _newest_save()
	match style:
		0: _build_hearth()
		1: _build_ages()
		_: _build_first()
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
	if style == 0 and main.view != null:
		main.view.cam = _cam0 + Vector2(sin(_t * 0.05) * 10.0, sin(_t * 0.037) * 5.0)
		main.view.queue_redraw()
	if style == 1 and not _age_cards.is_empty():
		var lit := int(_t / 1.6) % _age_cards.size()
		if lit != _age_lit:
			_age_lit = lit
			for i in _age_cards.size():
				var c: Control = _age_cards[i]
				var tw := create_tween()
				tw.tween_property(c, "modulate", Color(1, 1, 1, 1.0) if i == lit else Color(0.55, 0.55, 0.5, 1.0), 0.5)
	if _tip_lbl != null and int(_t / 7.0) != _tip_i:
		_tip_i = int(_t / 7.0)
		_tip_lbl.text = tr(TIPS[_tip_i % TIPS.size()])


# ---------------------------------------------------------------- shared parts

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
func _menu(v: VBoxContainer, compact := false) -> void:
	if not _last.is_empty():
		v.add_child(_menu_button("Continue", _save_line(), _continue, true))
	v.add_child(_menu_button("New realm", "" if compact else tr("Pick a map, rivals and difficulty"), close, _last.is_empty()))
	v.add_child(_menu_button("Campaign", "" if compact else tr("Eleven chapters, Bronze Age to the railways"), func(): close(); main.campaign_ui.show()))
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


func _save_thumb() -> Texture2D:
	var tb: PackedByteArray = _last.get("meta", {}).get("thumb", PackedByteArray())
	if tb.size() == 0:
		return null
	var img := Image.new()
	if img.load_png_from_buffer(tb) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _continue() -> void:
	close()
	main.saves_ui._load_game(String(_last.base))


## The newest build's notes from the change log: its title line and its first points, each cut to
## the words before its first colon.
static func news(count := 6) -> Array:
	var out := []
	var f := FileAccess.open("res://CHANGELOG.md", FileAccess.READ)
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
			var head := s.get_slice(":", 0).get_slice(". ", 0)
			out.append(head)
	return out


# ---------------------------------------------------------------- 0: Hearth fire

func _build_hearth() -> void:
	_shade(0.45)
	_vignette()
	_embers()
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(v)
	v.add_child(_title("HEARTHLANDS", 84))
	var sub := main._label("Build a realm from the first bronze to the railways", 18, Color("e6d6b0"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var gap := Control.new(); gap.custom_minimum_size = Vector2(0, 28); v.add_child(gap)
	var mc := CenterContainer.new(); v.add_child(mc)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 6)
	mc.add_child(mv)
	_menu(mv, true)
	add_child(_version_label())


# ---------------------------------------------------------------- 1: Seven ages

func _build_ages() -> void:
	_shade(0.82)
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right"]: root.add_theme_constant_override(m, 48)
	root.add_theme_constant_override("margin_top", 28)
	root.add_theme_constant_override("margin_bottom", 28)
	add_child(root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	root.add_child(v)
	v.add_child(_title("HEARTHLANDS", 56))
	# the ages, one picture each: the headquarters as it is built in that age
	var strip := HBoxContainer.new()
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 10)
	v.add_child(strip)
	var n := maxi(1, GameData.ages.size())
	for i in n:
		var card := PanelContainer.new()
		var sb := main._panel_style(0.9)
		sb.set_corner_radius_all(4)
		card.add_theme_stylebox_override("panel", sb)
		card.modulate = Color(0.55, 0.55, 0.5)
		var cv := VBoxContainer.new()
		card.add_child(cv)
		var pic := TextureRect.new()
		pic.texture = Tex.bld_era_tex("bld_hq", i)
		pic.custom_minimum_size = Vector2(168, 120)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cv.add_child(pic)
		var nm := main._label(GameData.age_name(i), 14, Main.BRASS)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(nm)
		strip.add_child(card)
		_age_cards.append(card)
	var tag := main._label("Seven ages, one realm. Every good is made, carried and stored by your people.", 16, Color("e6d6b0"))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 6)
	row.add_child(mv)
	_menu(mv)
	# what is new in this build, from the change log
	var np := PanelContainer.new()
	np.add_theme_stylebox_override("panel", main._panel_style(0.9))
	np.custom_minimum_size = Vector2(520, 0)
	np.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(np)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 6)
	np.add_child(nv)
	var items := news(7)
	nv.add_child(main._label(tr("WHAT'S NEW") + ("  ·  " + String(items[0]) if items.size() > 0 else ""), 14, Main.BRASS))
	for k in range(1, items.size()):
		var l := main._label("•  " + String(items[k]), 14)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(500, 0)
		nv.add_child(l)
	add_child(_version_label())


# ---------------------------------------------------------------- 2: First steps

const TIPS := [
	"Every building needs a road to a store. Carriers walk the roads with one load at a time.",
	"Keep a store near busy workshops: short walks mean more goods.",
	"Houses grow when their people have food, goods and a place of worship nearby.",
	"Right-click a building to see what it lacks. Red flags show the bottlenecks.",
	"Research opens the next age. Each age asks you to pick wealth, war or learning.",
	"Soldiers guard your borders. Towers and castles push your land further out.",
]

const LESSONS := [
	["res_wood", "Roads carry everything", "Woodcutters, mines and farms send their goods along the roads. No road, no goods."],
	["res_planks", "Stores hold the realm", "Goods wait in stores until a workshop or a house asks for them. Build stores where work is busy."],
	["res_bread", "People want more", "Feed your people, then clothe and please them. Content houses grow and send new workers."],
]


func _build_first() -> void:
	_shade(0.7)
	_embers(30)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.11, 0.08, 0.97)
	sb.border_color = Color("6b5a32")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(26)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	card.add_theme_stylebox_override("panel", sb)
	cc.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	var head := HBoxContainer.new(); v.add_child(head)
	var hl := VBoxContainer.new(); hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(hl)
	hl.add_child(main._label("Welcome to the Hearthlands", 34, Main.BRASS))
	hl.add_child(main._label("A realm starts with a headquarters, a few carriers and a store of goods. Here is how it grows.", 15, Color("d9cfb4")))
	var ver := main._label(Version.long(), 12, Main.DIM)
	ver.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(ver)
	# three short lessons, each with a good's picture
	var lr := HBoxContainer.new()
	lr.add_theme_constant_override("separation", 12)
	v.add_child(lr)
	for i in LESSONS.size():
		var les: Array = LESSONS[i]
		var lp := PanelContainer.new()
		var ls := main._panel_style(1.0)
		ls.set_corner_radius_all(4)
		ls.set_content_margin_all(12)
		lp.add_theme_stylebox_override("panel", ls)
		lp.custom_minimum_size = Vector2(250, 0)
		lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lr.add_child(lp)
		var lv := VBoxContainer.new(); lp.add_child(lv)
		var top := HBoxContainer.new(); lv.add_child(top)
		var ic := TextureRect.new()
		ic.texture = Tex.get_tex(String(les[0]))
		ic.custom_minimum_size = Vector2(40, 40)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		top.add_child(ic)
		top.add_child(main._label(tr("%d. %s" % [i + 1, tr(String(les[1]))]), 16, Main.BRASS))
		var body := main._label(String(les[2]), 14)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(226, 0)
		lv.add_child(body)
	# what to do now: the last game, or a first one
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 14)
	v.add_child(act)
	var lp2 := PanelContainer.new()
	lp2.add_theme_stylebox_override("panel", main._panel_style(1.0))
	lp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act.add_child(lp2)
	var lh := HBoxContainer.new(); lh.add_theme_constant_override("separation", 12); lp2.add_child(lh)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(88, 88)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var lv2 := VBoxContainer.new(); lv2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _last.is_empty():
		pic.texture = Tex.bld_era_tex("bld_hq", 0)
		lv2.add_child(main._label("Your first realm", 16, Main.BRASS))
		var t := main._label("The campaign teaches one thing at a time. Or found a realm of your own on a gentle setting.", 14)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(300, 0)
		lv2.add_child(t)
	else:
		pic.texture = _save_thumb()
		if pic.texture == null:
			pic.texture = Tex.bld_era_tex("bld_hq", maxi(0, GameData.ages.find(String(_last.meta.get("age", "")))))
		lv2.add_child(main._label("Your last game", 16, Main.BRASS))
		lv2.add_child(main._label(_save_line(), 14))
	lh.add_child(pic)
	lh.add_child(lv2)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	act.add_child(bv)
	if not _last.is_empty():
		var cb := _menu_button("Continue", "", _continue, true)
		cb.custom_minimum_size = Vector2(240, 46)
		bv.add_child(cb)
	var ca := _menu_button("Start the campaign", "", func(): close(); main.campaign_ui.show(), _last.is_empty())
	ca.custom_minimum_size = Vector2(240, 46 if _last.is_empty() else 36)
	bv.add_child(ca)
	var nr := _menu_button("New realm", "", close)
	nr.custom_minimum_size = Vector2(240, 36)
	bv.add_child(nr)
	# a tip that changes every few seconds, and the switch for this screen
	var foot := HBoxContainer.new(); v.add_child(foot)
	_tip_lbl = main._label(TIPS[0], 13, Color("bfb79a"))
	_tip_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_lbl.custom_minimum_size = Vector2(520, 0)
	foot.add_child(_tip_lbl)
	var show := CheckBox.new()
	show.text = "Show at startup"
	show.button_pressed = main.settings.welcome
	show.focus_mode = Control.FOCUS_NONE
	show.toggled.connect(func(on):
		main.settings.welcome = on
		main.settings.save_file())
	foot.add_child(show)
