class_name Features
extends RefCounted
## Finds the features the game can use: the built-in ones and any mod scripts in the mods folder.

const BUILT_IN := [
	"res://scripts/features/statistics.gd",
	"res://scripts/features/seasons.gd",
	"res://scripts/features/clothing.gd",
	"res://scripts/features/diseases.gd",
	"res://scripts/features/events.gd",
	"res://scripts/features/tool_quality.gd",
	"res://scripts/features/fog.gd",
	"res://scripts/features/geology.gd",
	"res://scripts/features/wildlife.gd",
]
const MOD_DIR := "user://mods"


## Every feature found, as {"id", "title", "info", "default_on", "script", "mod"}.
## A mod that fails to load, or does not extend Feature, is skipped with a warning.
static func available() -> Array:
	var out := []
	for path: String in BUILT_IN:
		_add(out, path, false)
	if DirAccess.dir_exists_absolute(MOD_DIR):
		for f in DirAccess.get_files_at(MOD_DIR):
			if f.ends_with(".gd"):
				_add(out, MOD_DIR + "/" + f, true)
	return out


static func _add(out: Array, path: String, mod: bool) -> void:
	var sc = load(path)
	if not (sc is GDScript) or not (sc as GDScript).can_instantiate():
		push_warning("Feature script could not be loaded: " + path)
		return
	var inst = (sc as GDScript).new()
	if not (inst is Feature) or String(inst.id) == "":
		push_warning("Not a feature (it must extend Feature and set an id): " + path)
		return
	for e in out:
		if e.id == inst.id:
			push_warning("Two features use the id '%s'; skipping %s" % [inst.id, path])
			return
	out.append({"id": inst.id, "title": inst.title, "info": inst.info, "default_on": inst.default_on, "script": sc, "mod": mod, "needs": inst.needs})


## The ids switched on by default.
static func default_ids() -> Array:
	var ids := []
	for e in available():
		if e.default_on and not e.mod:
			ids.append(e.id)
	return ids


## Makes the folder for mods and returns its place on disk.
static func ensure_mod_dir() -> String:
	DirAccess.make_dir_recursive_absolute(MOD_DIR)
	return ProjectSettings.globalize_path(MOD_DIR)
