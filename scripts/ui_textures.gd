class_name UiTextures
extends RefCounted
## The texture browser: every picture the game uses, and your replacements.
## Part of the interface: main.gd holds the shared state and calls in here; the functions reach
## the rest of the game through `main`.

var main: Main

var tex_grid: GridContainer
var tex_info: Label


func _init(p_owner: Main) -> void:
	main = p_owner


func _build_tex_panel() -> void:
	main.tex_panel = main._overlay()
	var v := main._body(main.tex_panel)
	var row := HBoxContainer.new(); v.add_child(row)
	var t := main._label("Textures", 24, Main.BRASS); t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(t)
	row.add_child(main._button("Close", func(): main.tex_panel.visible = false))
	tex_info = main._label("", 13, Main.DIM)
	tex_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tex_info.custom_minimum_size = Vector2(820, 0)
	v.add_child(tex_info)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(840, 520)
	v.add_child(sc)
	tex_grid = GridContainer.new(); tex_grid.columns = 6
	sc.add_child(tex_grid)
	main.tex_panel.visible = false


func _open_textures() -> void:
	for c in tex_grid.get_children():
		c.queue_free()
	var ids := Tex.all_ids()
	var n_custom := 0
	for id: String in ids:
		var cell := VBoxContainer.new()
		cell.custom_minimum_size = Vector2(134, 0)
		var tr := TextureRect.new()
		tr.texture = Tex.get_tex(id)
		tr.custom_minimum_size = Vector2(64, 64)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		cell.add_child(tr)
		var custom := Tex.custom.has(id)
		if custom:
			n_custom += 1
		var l := main._label(id + (" (custom)" if custom else ""), 11, Main.BRASS if custom else Main.DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		l.custom_minimum_size = Vector2(130, 0)
		cell.add_child(l)
		cell.tooltip_text = tr("%s.png, %dx%d") % [id, tr.texture.get_width(), tr.texture.get_height()]
		tex_grid.add_child(cell)
	tex_info.text = tr("%d textures, %d custom. Custom files go in %s and use the names below with .png. Any size works: buildings keep their proportions, terrain and roads fill one tile. Unit and flag textures are tinted with each realm's colour, so draw them light.") % [ids.size(), n_custom, Tex.ensure_user_dir()]
	main.tex_panel.visible = true


func _reload_textures() -> void:
	Tex.reload()
	main.view.refresh_textures()
	for id in main.stock_icons:
		main.stock_icons[id].texture = Tex.get_tex("res_" + String(id))
	main._refresh_build()
	main._show_hint(tr("Textures reloaded. %d custom in use.") % Tex.custom.size(), 4.0)
