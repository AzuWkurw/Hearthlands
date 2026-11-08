class_name I18n
extends RefCounted
## Interface languages. Each data/lang_<code>.json (and the same name in the mods folder) maps the
## English text to its translation; "_language" holds the language's own name. The files are loaded
## at start as Godot translations, so every label and button whose text is a key is shown translated,
## and text with numbers in it goes through tr("... %d ...") in the code. tools/extract_strings.py
## collects new text into the files. The game's own messages (event log, building info) stay English.

## [code, name] of every language found, English first.
static func languages() -> Array:
	var out := [["en", "English"]]
	for code in _codes():
		var d := _read(code)
		out.append([code, String(d.get("_language", code))])
	return out


static func _codes() -> Array:
	var codes := []
	for dir in ["res://data", "user://data"]:
		var da := DirAccess.open(dir)
		if da == null:
			continue
		for f in da.get_files():
			# exported games list imported files with a .remap suffix; the json itself is kept as is
			if f.begins_with("lang_") and f.ends_with(".json"):
				var c := f.trim_prefix("lang_").trim_suffix(".json")
				if not codes.has(c):
					codes.append(c)
	codes.sort()
	return codes


static func _read(code: String) -> Dictionary:
	var out := {}
	for path in ["res://data/lang_%s.json" % code, "user://data/lang_%s.json" % code]:
		if FileAccess.file_exists(path):
			var d = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary:
				out.merge(d, true)
	return out


## Loads every language and switches to code ("en" or "" for English).
static func setup(code: String) -> void:
	for c in _codes():
		var t := Translation.new()
		t.locale = c
		var d := _read(c)
		for k in d:
			if not String(k).begins_with("_") and String(d[k]) != "":
				t.add_message(k, d[k])
		TranslationServer.add_translation(t)
	TranslationServer.set_locale(code if code != "" else "en")
