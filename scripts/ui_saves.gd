class_name UiSaves
extends RefCounted
## Saving and loading games, and the Save / Load window.
## Part of the interface: main.gd holds the shared state and calls in here; the functions reach
## the rest of the game through `main`.

var main: Main

var save_name: LineEdit


func _init(p_owner: Main) -> void:
	main = p_owner


func _build_save_panel() -> void:
	main.save_panel = main._overlay()
	var v := main._body(main.save_panel)
	var row := HBoxContainer.new(); v.add_child(row)
	var tl := main._label("Save and load", 24, Main.BRASS); tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(tl)
	row.add_child(main._button("Close", func(): main.save_panel.visible = false))
	var r2 := HBoxContainer.new(); v.add_child(r2)
	save_name = LineEdit.new(); save_name.placeholder_text = "Save name"; save_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(save_name)
	r2.add_child(main._button("Save current game", func():
		var n := save_name.text.strip_edges()
		if n == "": n = "save-" + Time.get_datetime_string_from_system().replace(":", "-")
		_save_game(n)
		_fill_saves()))
	var asl := main._label("The game also autosaves every 5 minutes of play. F5 quick saves, F9 quick loads.", 13, Main.DIM)
	v.add_child(asl)
	main.key_text(asl, "text", ["quicksave", "quickload"])
	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(620, 360); v.add_child(sc)
	main.save_list = VBoxContainer.new(); main.save_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(main.save_list)
	main.save_panel.visible = false


func _open_saves() -> void:
	save_name.text = ""
	_fill_saves()
	main.save_panel.visible = true


func _safe_name(n: String) -> String:
	var out := ""
	for ch in n:
		out += ch if (ch.is_valid_identifier() or ch.is_valid_int() or ch in "-_ ") else "_"
	return out.strip_edges().substr(0, 60)


func _save_game(slot: String, quiet := false) -> void:
	if main.sim.players.is_empty() or (main.sim.over and slot == "autosave"):
		return
	DirAccess.make_dir_recursive_absolute(Main.SAVE_DIR)
	var path := Main.SAVE_DIR + "/" + _safe_name(slot) + ".save"
	if slot == "autosave":
		_roll_autosaves()
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		main._show_hint(tr("Could not save: %s") % error_string(FileAccess.get_open_error()), 4.0)
		return
	var data := main.sim.to_save()
	data["meta"] = {"name": slot, "saved": Time.get_datetime_string_from_system(false, true), "game_time": main.sim.time,
		"rivals": main.sim.foes, "age": GameData.age_name(main.sim.human().age), "size": main.sim.w, "version": Version.short(), "thumb": main.minimap.thumbnail(96) if main.minimap != null else PackedByteArray()}
	f.store_var(data)
	f.close()
	if not quiet:
		main._show_hint(tr("Saved \"%s\".") % slot, 3.0)


## Rolling autosaves (build 56): the last three are kept. Before a new autosave, the one before last
## becomes "autosave 3" and the last "autosave 2".
const AUTOSAVES := 3

func _roll_autosaves() -> void:
	var dir := Main.SAVE_DIR + "/"
	for k in range(AUTOSAVES - 1, 0, -1):
		var from := dir + ("autosave" if k == 1 else _safe_name("autosave %d" % k)) + ".save"
		var to := dir + _safe_name("autosave %d" % (k + 1)) + ".save"
		if FileAccess.file_exists(from):
			if FileAccess.file_exists(to):
				DirAccess.remove_absolute(to)
			DirAccess.rename_absolute(from, to)


func _read_save(path: String):
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return null
	var d = f.get_var()
	f.close()
	return d if d is Dictionary else null


func _load_game(slot: String) -> void:
	var path := Main.SAVE_DIR + "/" + _safe_name(slot) + ".save"
	if not FileAccess.file_exists(path):
		main._show_hint(tr("No save called \"%s\" yet.") % slot, 3.0)
		return
	var d = _read_save(path)
	if d == null:
		main._show_hint("That save file could not be read.", 4.0)
		return
	var err := main.sim.from_save(d)
	if err != "":
		main._show_hint(err, 4.0)
		return
	main.turn_on_new_features()
	main._after_world_change()
	if main.sim.mission.is_empty():
		main.guide_ui.box.visible = false
	else:
		main.guide_ui.start()
	var hq := main.sim.human().hq
	if hq != null:
		main.view.center_on(Vector2(hq.x + 0.5, hq.y + 0.5))
	main.setup.visible = false
	main.save_panel.visible = false
	main.paused = false
	main.btn_pause.text = "Pause"
	main._show_hint(tr("Loaded \"%s\".") % slot, 3.0)


func _fill_saves() -> void:
	for c in main.save_list.get_children():
		c.queue_free()
	var files: Array = []
	var dir := DirAccess.open(Main.SAVE_DIR)
	if dir != null:
		for fn in dir.get_files():
			if fn.ends_with(".save"):
				files.append([FileAccess.get_modified_time(Main.SAVE_DIR + "/" + fn), fn])
	files.sort_custom(func(a, b): return a[0] > b[0])
	if files.is_empty():
		main.save_list.add_child(main._label("No saved games yet.", 14, Main.DIM))
	for e in files:
		var fn: String = e[1]
		var base := fn.get_basename()
		var d = _read_save(Main.SAVE_DIR + "/" + fn)
		var meta: Dictionary = d.get("meta", {}) if d is Dictionary else {}
		# older rolling autosaves keep the name of their file ("autosave 2", "autosave 3")
		if base.begins_with("autosave "):
			meta = meta.duplicate()
			meta["name"] = base
		var row := HBoxContainer.new()
		# a small picture of the map as it was (saves from before build 33 have none)
		var tb: PackedByteArray = meta.get("thumb", PackedByteArray())
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(64, 64)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if tb.size() > 0:
			var img := Image.new()
			if img.load_png_from_buffer(tb) == OK:
				pic.texture = ImageTexture.create_from_image(img)
		row.add_child(pic)
		var gt := int(meta.get("game_time", 0))
		var info := "%s\n%s · %02d:%02d played · %d rivals · %s age · %d tiles · %s" % [String(meta.get("name", base)), String(meta.get("saved", "")), gt / 60, gt % 60, int(meta.get("rivals", 0)), String(meta.get("age", "?")), int(meta.get("size", 0)), String(meta.get("version", "older build"))]
		var l := main._label(info, 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(main._button("Load", func():
			if main.game_running():
				main.confirm(tr("Load \"%s\"? The game you are playing ends; anything not saved is lost.") % String(meta.get("name", base)), "Load", _load_game.bind(base))
			else:
				_load_game(base)))
		row.add_child(main._button("Delete", func():
			main.confirm(tr("Delete the save \"%s\"? This can't be undone.") % String(meta.get("name", base)), "Delete", func():
				DirAccess.remove_absolute(Main.SAVE_DIR + "/" + fn)
				_fill_saves())))
		main.save_list.add_child(row)
