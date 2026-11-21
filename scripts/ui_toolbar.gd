class_name UiToolbar
extends RefCounted
## The toolbar along the bottom of the map: a button per building group
## (each opens a panel of its buildings just above the bar), the road tools and Auto roads, Demolish,
## and the tools of the game features (send a scout, send a geologist). Esc closes the panel.

const BAR_H := 84          # height of the bar, without the gap below it
const BTN := Vector2(60, 58)
## The building shown on each group's button.
const CAT_ICONS := {"raw": "woodcutter", "food": "farm", "industry": "iron_smelter", "crafts": "toolsmith",
	"folk": "house", "science": "scriptorium", "logistics": "storehouse", "mil": "tower"}
const CAT_SHORT := {"logistics": "Stores", "mil": "Military"}
const ROAD_TOOLS := [["@road", "Road", "road_5", "Build road: click one of your roads or buildings (or a building's entrance flag), then where the road should go. Esc stops."],
	["@pave", "Pave", "road_paved_5", "Pave road: click a road to pave up to 12 tiles with stone (1 stone each). Carriers walk paved roads faster."],
	["@unroad", "Remove", "road_15", "Remove road: click a road to take up that stretch, up to the next junction or building."],
	["@rail", "Rail", "rail_icon", "Lay railway track (Railways, Industrial age): click one of your railway stations or rails, then where the track should go. One rail a tile, three on a bridge. Esc stops."],
	["@unrail", "No rail", "rail_remove_icon", "Take up railway track: click a rail to take up that stretch, up to the next junction (half the rails come back)."],
	["@flag", "Flag", "unit_flag", "Flag (road carriers): click one of your roads to set a flag or take it away. Each flag splits a stretch, so more carriers share the road and goods move faster."]]

var main: Main
var bar: PanelContainer
var popup: PanelContainer
var pop_title: Label
var open_cat := ""
var cat_btns := {}        # group id -> Button
var tool_btns := {}       # tool id ("@road", "@demolish", "@scout"...) -> Button
var auto_btn: Button
var explore_row: HBoxContainer
var explore_box: VBoxContainer
var _tools_sig := ""
var sites_on := false      # the Sites button (B): building places shown on the map
var sites_btn: Button
var row: HBoxContainer
var compact := false       # icons only, when the map is too narrow for the full bar
var _full_w := 0.0         # width the full bar needs


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	bar = PanelContainer.new()
	bar.add_theme_stylebox_override("panel", main._panel_style(0.94))
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 8; bar.offset_right = -Main.SIDE_W - 8
	bar.offset_top = -BAR_H - 8; bar.offset_bottom = -8
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	main.add_child(bar)
	row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 7)
	bar.add_child(row)

	var bg := _group(row, "BUILD")
	sites_btn = _btn("Sites", _sites_icon(), "Sites (B): show building places on the map.\nA small house: room for a small building; a bigger house: medium; a castle: large; a mine sign: a mine (where a geologist found ore).\nClose up only: zoom in to see them.", toggle_sites)
	main.key_text(sites_btn, "tooltip_text")
	bg.add_child(sites_btn)
	for c in GameData.CATEGORIES:
		var id := String(c[0])
		var b := _btn(String(CAT_SHORT.get(id, c[1])), _cat_icon(id), "%s buildings" % String(c[1]), _on_cat.bind(id))
		b.set_meta("cat_name", String(c[1]))
		bg.add_child(b)
		cat_btns[id] = b
	row.add_child(VSeparator.new())
	var rg := _group(row, "ROADS")
	for t in ROAD_TOOLS:
		var tex: Texture2D = Tex.get_tex(String(t[2]))
		if Tex.frames(String(t[2])) > 1:
			# a strip of animation frames: the first one is the icon
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Tex.frame_rect(String(t[2]), 0)
			tex = at
		var b := _btn(String(t[1]), tex, String(t[3]), _on_tool.bind(String(t[0])))
		rg.add_child(b)
		tool_btns[t[0]] = b
	auto_btn = _btn("Auto", _auto_icon(), "Auto roads. On: a new building gets its road to your network at once, from its entrance.\nOff: after placing it you lay its road yourself, from its entrance flag.", _on_auto)
	rg.add_child(auto_btn)
	row.add_child(VSeparator.new())
	var dg := _group(row, "CLEAR")
	var db := _btn("Demolish", _demolish_icon(), "Demolish: click one of your buildings to pull it down (you get back part of its cost). Delete does it for the selected building. Esc stops.", _on_tool.bind("@demolish"))
	dg.add_child(db)
	tool_btns["@demolish"] = db
	explore_box = VBoxContainer.new()
	explore_box.add_theme_constant_override("separation", 2)
	row.add_child(explore_box)
	explore_box.add_child(VSeparator.new())   # replaced in rebuild_tools
	rebuild_tools()

	# the panel of one group's buildings, above the bar
	popup = PanelContainer.new()
	popup.add_theme_stylebox_override("panel", main._panel_style(0.97))
	popup.visible = false
	main.add_child(popup)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	popup.add_child(pv)
	var head := HBoxContainer.new()
	pv.add_child(head)
	pop_title = main._label("", 16, Main.BRASS)
	pop_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(pop_title)
	head.add_child(main._button("Close (Esc)", close_popup))
	main.build_grid = GridContainer.new()
	main.build_grid.columns = 4
	pv.add_child(main.build_grid)


## A titled group of buttons: a small caption over a row.
func _group(row: HBoxContainer, title: String) -> HBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	row.add_child(v)
	var l := main._label(title, 10, Main.DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.visible = not compact
	v.add_child(l)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	v.add_child(h)
	return h


func _btn(text: String, icon: Texture2D, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.text = text
	b.icon = icon
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_constant_override("icon_max_width", 44)
	b.add_theme_font_size_override("font_size", 11)
	b.custom_minimum_size = BTN
	b.tooltip_text = tip if tip.begins_with(text) else "%s\n%s" % [text, tip]
	b.set_meta("label", text)
	b.pressed.connect(cb)
	if compact:
		_compact_btn(b, true)
	return b


func _compact_btn(b: Button, on: bool) -> void:
	b.text = "" if on else String(b.get_meta("label", ""))
	b.custom_minimum_size = Vector2(46, 50) if on else BTN
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER if on else VERTICAL_ALIGNMENT_TOP


## Switches between the full bar and icons only, so the bar always fits beside the side panel.
func fit() -> void:
	if bar == null:
		return
	var avail := main.size.x - Main.SIDE_W - 16.0 - 24.0
	if not compact:
		_full_w = row.get_combined_minimum_size().x
	var want := _full_w > avail
	if want == compact:
		return
	compact = want
	for b in _all_buttons(row):
		_compact_btn(b, compact)
	for v in row.find_children("*", "Label", true, false):
		(v as Label).visible = not compact


func _all_buttons(n: Node) -> Array:
	var out := []
	for c in n.find_children("*", "Button", true, false):
		if c.has_meta("label"):
			out.append(c)
	return out


## The game features' tools (send scout, send geologist...), whatever group they belong to.
## Rebuilt when the set of switched-on features changes.
func rebuild_tools() -> void:
	var tools := []
	for f: Feature in main.sim.features:
		for c in GameData.CATEGORIES:
			for t in f.tools(String(c[0])):
				tools.append(t)
	var sig := ",".join(tools.map(func(t): return String(t[0])))
	if sig == _tools_sig and explore_row != null:
		return
	_tools_sig = sig
	for ch in explore_box.get_children():
		ch.queue_free()
	for k in tool_btns.keys():
		if not (k in ["@road", "@pave", "@unroad", "@rail", "@unrail", "@flag", "@demolish"]):
			tool_btns.erase(k)
	explore_row = null
	if tools.is_empty():
		return
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 7)
	explore_box.add_child(h)
	h.add_child(VSeparator.new())
	explore_row = _group(h, "EXPLORE")
	for t in tools:
		var text := String(t[1]).trim_prefix("Send ").capitalize()
		var b := _btn(text, _frame_tex(String(t[2])), String(t[3]), _on_tool.bind(String(t[0])))
		explore_row.add_child(b)
		tool_btns[t[0]] = b


func _on_cat(id: String) -> void:
	if open_cat == id:
		close_popup()
		return
	open_cat = id
	if main.view.place_type.begins_with("@"):
		main._cancel_place()
	main._set_cat(id)
	for c in GameData.CATEGORIES:
		if String(c[0]) == id:
			pop_title.text = String(c[1])
	popup.visible = true
	popup.reset_size()
	refresh()
	_place_popup.call_deferred()


## Shows or hides the building places (the Sites button, or B).
func toggle_sites() -> void:
	sites_on = not sites_on
	refresh()
	if sites_on and main.view.zoom < 20.0:
		main._show_hint("Zoom in to see the building places.", 2.5)


func close_popup() -> void:
	open_cat = ""
	if popup != null:
		popup.visible = false
	refresh()


func _on_tool(id: String) -> void:
	close_popup()
	main._pick_build(id)
	refresh()


func _on_auto() -> void:
	main.settings.auto_roads = auto_btn.button_pressed
	main.view.auto_roads = main.settings.auto_roads
	main.settings.save_file()
	main._show_hint(tr("Auto roads %s." % ("on: new buildings get their road at once" if main.settings.auto_roads else "off: you lay each new building's road yourself")), 2.5)


## The panel sits above its group's button, kept inside the map area.
func _place_popup() -> void:
	if not popup.visible or not cat_btns.has(open_cat):
		return
	popup.reset_size()
	var b: Button = cat_btns[open_cat]
	var right := main.size.x - Main.SIDE_W - 8
	var x := clampf(b.global_position.x + b.size.x / 2.0 - popup.size.x / 2.0, 8.0, maxf(8.0, right - popup.size.x))
	popup.position = Vector2(x, bar.global_position.y - popup.size.y - 6)


## Groups holding a building research just unlocked show a gold dot until it is picked.
func mark_new() -> void:
	for id in cat_btns:
		var b: Button = cat_btns[id]
		var any := false
		for t in main.new_blds:
			if String(GameData.bld[t].get("cat", "")) == id:
				any = true
		b.modulate = Color(1.0, 0.88, 0.45) if any else Color.WHITE
		var base := "%s buildings" % String(b.get_meta("cat_name", id))
		b.tooltip_text = base + ("\nNew from research!" if any else "")


## Pressed states follow what is going on: the open group, the tool in use.
func refresh() -> void:
	if bar == null:
		return
	rebuild_tools()
	for id in cat_btns:
		(cat_btns[id] as Button).set_pressed_no_signal(open_cat == id or (open_cat == "" and GameData.bld.has(main.view.place_type) and String(GameData.bld[main.view.place_type].get("cat", "")) == id))
	for id in tool_btns:
		if is_instance_valid(tool_btns[id]):
			(tool_btns[id] as Button).set_pressed_no_signal(main.view.place_type == id)
	auto_btn.set_pressed_no_signal(main.settings.auto_roads)
	# the rail tools only once your realm has studied Railways (build 64)
	var rails_known: bool = main.sim != null and not main.sim.players.is_empty() and main.sim.human().techs.has("railways")
	for rid in ["@rail", "@unrail"]:
		if tool_btns.has(rid) and is_instance_valid(tool_btns[rid]):
			(tool_btns[rid] as Button).visible = rails_known
	# a building picked from the panel: the panel steps aside so the map is free to place it
	if popup.visible and GameData.bld.has(main.view.place_type):
		open_cat = ""
		popup.visible = false
	if popup.visible:
		_place_popup()
	main.view.show_sites = popup.visible or sites_on
	sites_btn.set_pressed_no_signal(sites_on)
	fit()


func _cat_icon(id: String) -> Texture2D:
	var ty := String(CAT_ICONS.get(id, ""))
	if not GameData.bld.has(ty):
		for k in GameData.bld:
			if String(GameData.bld[k].get("cat", "")) == id:
				ty = k
				break
	if ty == "":
		return null
	return _trimmed(main.view.bld_texture(ty, 0))


## The picture cut down to its visible part, so it fills the button.
func _trimmed(t: Texture2D) -> Texture2D:
	if t == null:
		return null
	var img := t.get_image()
	if img == null:
		return t
	if img.is_compressed():
		img.decompress()
	var r := img.get_used_rect()
	if r.size.x <= 0 or r.size == img.get_size():
		return t
	var a := AtlasTexture.new()
	a.atlas = t
	a.region = Rect2(r)
	return a


## Frame 0 of an animated strip (a walking scout), or the whole picture.
func _frame_tex(id: String) -> Texture2D:
	var t := Tex.get_tex(id)
	if Tex.frames(id) <= 1:
		return t
	var a := AtlasTexture.new()
	a.atlas = t
	a.region = Tex.frame_rect(id, 0)
	return a


## The site markers in small: a little house and a castle, in gold.
func _sites_icon() -> Texture2D:
	var n := 40
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var gold := Color("f2cf5a"); var edge := Color(0.18, 0.12, 0.04)
	# house (left): body and roof
	for y in n:
		for x in n:
			var c := Color(0, 0, 0, 0)
			if x >= 3 and x <= 17 and y >= 20 and y <= 33: c = gold
			elif y >= 11 and y < 20 and absi(x - 10) <= (y - 11) + 1: c = gold.darkened(0.15)
			# castle (right): wall and three battlements
			if x >= 21 and x <= 37 and y >= 17 and y <= 33: c = gold
			if y >= 11 and y < 17 and ((x >= 21 and x <= 24) or (x >= 28 and x <= 31) or (x >= 34 and x <= 37)): c = gold
			img.set_pixel(x, y, c)
	# dark outlines where gold meets nothing
	var out := img.duplicate() as Image
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			if img.get_pixel(x, y).a == 0.0:
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if img.get_pixel(x + d.x, y + d.y).a > 0.0:
						out.set_pixel(x, y, edge)
						break
	return ImageTexture.create_from_image(out)


## A small house with a red cross over it.
func _demolish_icon() -> Texture2D:
	var n := 40
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var wall := Color("c9b28a"); var roof := Color("a2452e"); var dark := Color("3a2a1c"); var red := Color("e0402f")
	for y in n:
		for x in n:
			# roof: a triangle; walls: a box under it; door: a dark slot
			if y >= 6 and y < 18 and absi(x - 20) <= (y - 6) + 3:
				img.set_pixel(x, y, roof)
			elif y >= 18 and y < 34 and x >= 9 and x <= 31:
				img.set_pixel(x, y, dark if (x >= 17 and x <= 23 and y >= 24) else wall)
	for k in range(4, 37):
		for t in range(-2, 3):
			for p in [Vector2i(k, k + t), Vector2i(k, n - 1 - k + t)]:
				if p.y >= 0 and p.y < n:
					img.set_pixel(p.x, p.y, red)
	return ImageTexture.create_from_image(img)


## A road with a small gear: roads that lay themselves.
func _auto_icon() -> Texture2D:
	var base: Image = Tex.get_tex("road_5").get_image()
	if base == null:
		return Tex.get_tex("road_5")
	var img := base.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(40, 40)
	var c := Vector2(29, 11)
	for y in 22:
		for x in range(18, 40):
			var d := Vector2(x, y).distance_to(c)
			var ang := atan2(y - c.y, x - c.x)
			var r := 7.5 + (2.0 if fmod(ang + TAU, TAU / 8.0) < TAU / 16.0 else 0.0)
			if d <= r and d >= 3.0:
				img.set_pixel(x, y, Color("e8c060"))
			elif d < 3.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
