class_name Version
extends RefCounted
## The game's version. Run `python3 tools/bump_build.py` before every release: it raises BUILD by one,
## updates DATE and copies the version into project.godot and the Windows export settings.

const NUMBER := "0.27.0"
const BUILD := 32
const DATE := "2026-11-08"


## Short form for the top bar and save files, e.g. "v0.4.0 build 4".
static func short() -> String:
	return "v%s build %d" % [NUMBER, BUILD]


## Long form with the release date, for the new-game screen.
static func long() -> String:
	return "%s, build %d (%s)" % [NUMBER, BUILD, DATE]
