class_name Version
extends RefCounted
## The game's version. Run `python3 tools/bump_build.py` before every release: it raises BUILD by one
## (or FIX with --fix, for a fix release of the last build),
## updates DATE and copies the version into project.godot and the Windows export settings.

const NUMBER := "0.58.0"
const BUILD := 63
const FIX := 0          # a fix release of the same build: 43.1, 43.2... (0: none)
const DATE := "2026-11-15"


## Short form for the top bar and save files, e.g. "v0.4.0 build 4".
static func short() -> String:
	return "v%s build %s" % [NUMBER, build_name()]


## The build as players see it: "43", or "43.1" for the first fix release of build 43.
static func build_name() -> String:
	return str(BUILD) if FIX == 0 else "%d.%d" % [BUILD, FIX]


## Long form with the release date, for the new-game screen.
static func long() -> String:
	return "%s, build %s (%s)" % [NUMBER, build_name(), DATE]
