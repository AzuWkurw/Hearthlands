class_name UiHandbook
extends RefCounted
## The handbook window (F1, or Handbook on the top bar): a page for every building, good, tech, age, law
## and game feature, written from the data files by handbook.gd. A search box on the left narrows the
## list as you type; gold words on a page lead to other pages, and Back returns. The question mark in a
## building's info box opens that building's page.

var main: Main
var win: Window
var find: LineEdit
var tree: Tree
var text: RichTextLabel
var back_btn: Button
var book := Handbook.new()
var page := "home"
var history: Array = []
var _locale := ""
var _items: Dictionary = {}      # page id -> TreeItem


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	win = Window.new()
	win.title = "Handbook"
	win.transient = true
	win.visible = false
	win.wrap_controls = false
	win.size = Vector2i(980, 720)
	win.min_size = Vector2i(560, 380)
	win.theme = UiLog.window_theme()
	win.close_requested.connect(func(): win.visible = false)
	win.window_input.connect(_on_input)
	main.add_child(win)
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", main._panel_style(1.0))
	win.add_child(bg)
	var split := HSplitContainer.new()
	split.split_offset = 290
	bg.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(230, 0)
	left.add_theme_constant_override("separation", 6)
	split.add_child(left)
	find = LineEdit.new()
	find.placeholder_text = "Search the handbook"
	find.clear_button_enabled = true
	find.text_changed.connect(func(_t): _fill_tree())
	find.text_submitted.connect(func(_t):
		var ids := book.search(find.text)
		if not ids.is_empty():
			show_page(String(ids[0])))
	left.add_child(find)
	tree = Tree.new()
	tree.hide_root = true
	tree.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.item_selected.connect(func():
		var it := tree.get_selected()
		if it == null:
			return
		if String(it.get_metadata(0)) != "":
			show_page(String(it.get_metadata(0)), true, false)
		elif it.get_child_count() > 0:
			# a heading opens or folds its list
			it.collapsed = not it.collapsed
			it.deselect(0))
	left.add_child(tree)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	split.add_child(right)
	var top := HBoxContainer.new()
	right.add_child(top)
	back_btn = main._button("Back", go_back)
	top.add_child(back_btn)
	top.add_child(main._button("Contents", func(): show_page("home")))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(main._button("Close", func(): win.visible = false))
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.selection_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# the pages are written already translated (handbook.gd)
	text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_font_size_override("bold_font_size", 15)
	text.add_theme_font_size_override("italics_font_size", 15)
	text.add_theme_color_override("default_color", Color("e6e2d3"))
	text.meta_clicked.connect(func(m): show_page(str(m)))
	right.add_child(text)


func _on_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		if e.keycode == KEY_ESCAPE:
			win.visible = false
		elif e.keycode == KEY_BACKSPACE and e.alt_pressed:
			go_back()
		elif e.keycode == main.key_for("handbook") and not find.has_focus():
			win.visible = false


## Writes the pages again when the language changed since they were last written.
func _ensure() -> void:
	var loc := TranslationServer.get_locale()
	if loc != _locale or book.pages.is_empty():
		_locale = loc
		book.make()
		_fill_tree()


func toggle() -> void:
	if win.visible:
		win.visible = false
	else:
		open()


## Opens the window on a page ("bld:sawmill"), or where it was left.
func open(id := "") -> void:
	_ensure()
	if not win.visible:
		win.popup_centered()
	win.move_to_foreground()
	show_page(id if id != "" else page)


func show_page(id: String, remember := true, select := true) -> void:
	_ensure()
	if not book.by_id.has(id):
		id = "home"
	if remember and id != page:
		history.append(page)
		if history.size() > 50:
			history.pop_front()
	page = id
	text.text = String(book.by_id[id].text)
	text.scroll_to_line(0)
	back_btn.disabled = history.is_empty()
	if select and _items.has(id):
		var it: TreeItem = _items[id]
		var up := it.get_parent()
		while up != null:
			up.collapsed = false
			up = up.get_parent()
		it.select(0)
		tree.scroll_to_item(it)


func go_back() -> void:
	if history.is_empty():
		return
	var id := String(history.pop_back())
	show_page(id, false)
	back_btn.disabled = history.is_empty()


func _to_top() -> void:
	var r := tree.get_root()
	if r != null and r.get_first_child() != null:
		tree.scroll_to_item(r.get_first_child())


## The list on the left: every page by group, or only those matching the search.
func _fill_tree() -> void:
	tree.clear()
	_items = {}
	var root := tree.create_item()
	var q := find.text.strip_edges()
	var groups := {}
	var subs := {}
	if q == "":
		var home := tree.create_item(root)
		home.set_text(0, tr("Handbook"))
		home.set_metadata(0, "home")
		_items["home"] = home
	var ids := book.search(q)
	var shown := {}
	for id in ids:
		shown[id] = true
	if q != "":
		# a search lists the matches best first, without groups
		for id in ids:
			var p: Dictionary = book.by_id[id]
			var it := tree.create_item(root)
			it.set_text(0, "%s  ·  %s" % [p.title, tr(String(p.group))])
			it.set_metadata(0, id)
			_items[id] = it
		if ids.is_empty():
			var none := tree.create_item(root)
			none.set_text(0, tr("Nothing found"))
			none.set_metadata(0, "")
			none.set_selectable(0, false)
		# the best match at the top of the list
		_to_top.call_deferred()
		return
	for p: Dictionary in book.pages:
		if p.id == "home" or not shown.has(p.id):
			continue
		var g := String(p.group)
		if not groups.has(g):
			var gi := tree.create_item(root)
			gi.set_text(0, tr(g))
			gi.set_metadata(0, "")
			gi.set_custom_color(0, Main.BRASS)
			gi.collapsed = true
			groups[g] = gi
		var parent: TreeItem = groups[g]
		var s := String(p.sub)
		if s != "":
			var key := g + "/" + s
			if not subs.has(key):
				var si := tree.create_item(parent)
				si.set_text(0, s)
				si.set_metadata(0, "")
				si.set_custom_color(0, Color("c8b88a"))
				si.collapsed = true
				subs[key] = si
			parent = subs[key]
		var it := tree.create_item(parent)
		it.set_text(0, String(p.title))
		it.set_metadata(0, p.id)
		_items[p.id] = it
