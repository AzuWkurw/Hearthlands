class_name SharePack
extends RefCounted
## Sharing maps and missions as one file (.hlpack): the map editor exports the map being edited (with
## any of your missions that are played on it), the Missions window exports all your own missions and
## their maps, and imports a pack someone sent you. A pack is JSON:
## {"hearthlands_pack": 1, "maps": {file name: map file contents}, "missions": [mission, ...]}.
## Imported maps go into user://maps (renamed if the name is taken), missions into
## user://data/missions.json with their map paths pointing at the imported maps.

const USER_MISSIONS := "user://data/missions.json"


static func user_missions() -> Array:
	if FileAccess.file_exists(USER_MISSIONS):
		var d = JSON.parse_string(FileAccess.get_file_as_string(USER_MISSIONS))
		if d is Array:
			return d
	return []


## Writes a pack with the map files given (paths) and the missions given. "" when done, else why not.
static func export_pack(path: String, map_paths: Array, missions: Array) -> String:
	var maps := {}
	for mp in map_paths:
		if not FileAccess.file_exists(String(mp)):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(String(mp)))
		if d is Dictionary:
			maps[String(mp).get_file()] = d
	var ms := []
	for m in missions:
		var c: Dictionary = (m as Dictionary).duplicate(true)
		if c.has("map"):
			c["map"] = String(c.map).get_file()
		ms.append(c)
	if maps.is_empty() and ms.is_empty():
		return "Nothing to export."
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Could not write %s" % path
	f.store_string(JSON.stringify({"hearthlands_pack": 1, "maps": maps, "missions": ms}))
	return ""


## Reads a pack into your maps and missions. Returns a line saying what came in (or what went wrong).
static func import_pack(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "No such file."
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or not d.has("hearthlands_pack"):
		return "That is not a Hearthlands map or mission pack."
	DirAccess.make_dir_recursive_absolute(UiEditor.MAP_DIR)
	var renamed := {}
	var nmaps := 0
	for fname in (d.get("maps", {}) as Dictionary):
		var base := String(fname).get_basename().validate_filename()
		var dest := UiEditor.MAP_DIR + "/" + base + ".json"
		var k := 2
		while FileAccess.file_exists(dest):
			dest = UiEditor.MAP_DIR + "/%s %d.json" % [base, k]
			k += 1
		var f := FileAccess.open(dest, FileAccess.WRITE)
		if f == null:
			continue
		f.store_string(JSON.stringify(d.maps[fname]))
		f.close()
		renamed[String(fname)] = dest
		nmaps += 1
	var mine := user_missions()
	var nmis := 0
	for m in d.get("missions", []):
		if not (m is Dictionary):
			continue
		var c: Dictionary = (m as Dictionary).duplicate(true)
		if c.has("map"):
			if not renamed.has(String(c.map)):
				continue
			c["map"] = renamed[String(c.map)]
		c["id"] = "imported_%d_%s" % [Time.get_unix_time_from_system(), String(c.get("id", nmis))]
		mine.append(c)
		nmis += 1
	if nmis > 0:
		DirAccess.make_dir_recursive_absolute(USER_MISSIONS.get_base_dir())
		var f2 := FileAccess.open(USER_MISSIONS, FileAccess.WRITE)
		if f2 != null:
			f2.store_string(JSON.stringify(mine, "\t"))
	return "Imported %d map%s and %d mission%s." % [nmaps, "" if nmaps == 1 else "s", nmis, "" if nmis == 1 else "s"]


## A file dialog on the computer's own folders, for a pack. save: choosing where to write one.
static func dialog(owner: Node, save: bool, on_path: Callable) -> void:
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	fd.filters = PackedStringArray(["*.hlpack ; Hearthlands map and mission packs"])
	fd.title = "Export a map or mission pack" if save else "Import a map or mission pack"
	fd.size = Vector2i(760, 520)
	fd.use_native_dialog = true
	fd.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	owner.add_child(fd)
	fd.file_selected.connect(func(p):
		on_path.call(p if not save or String(p).ends_with(".hlpack") else String(p) + ".hlpack")
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered()
