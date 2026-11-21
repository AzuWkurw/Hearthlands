class_name Settings
extends RefCounted
## Options that last between games: renderer, display mode and resolution, interface size, frame rate,
## and a few conveniences. They are kept in user://settings.cfg.
## The renderer is special: Godot picks it before any script runs, so it goes into a second file,
## user://graphics_override.cfg, which the engine reads at start-up (project.godot points to it with
## application/config/project_settings_override). A new renderer is first tried in a one-off restart;
## only if that start works is it written there, so a PC without Vulkan always gets back to OpenGL.
## Vulkan is preferred: on the first start the game checks, in a small hidden-away test start, whether
## Vulkan works on this PC, and switches to it if it does (Main._probe_vulkan).

const PATH := "user://settings.cfg"
const OVERRIDE := "user://graphics_override.cfg"
const PROBE := "user://vulkan_probe.txt"   # written by the test start when Vulkan works
## Renderers: [id Godot knows it by, name shown in the menu].
const RENDERERS := [
	["forward_plus", "Vulkan (Forward+), preferred"],
	["gl_compatibility", "OpenGL (Compatibility), works on almost every PC"],
	["mobile", "Vulkan (Mobile), a lighter Vulkan renderer"],
]
const MODES := [["windowed", "Window"], ["fullscreen", "Borderless fullscreen"], ["exclusive", "Exclusive fullscreen"]]
## Resolutions offered; only those that fit the screen are listed. "Native" is the screen's own size.
const SIZES := [Vector2i(3840, 2160), Vector2i(2560, 1440), Vector2i(1920, 1080), Vector2i(1600, 900),
	Vector2i(1366, 768), Vector2i(1280, 720), Vector2i(1024, 576)]
## Interface sizes; 0 is Auto: by the screen's height (100% up to 1080 lines, 150% at 1440, 200% at 2160).
const UI_SCALES := [0.0, 0.75, 0.9, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0]
const FPS_LIMITS := [0, 30, 60, 120, 144, 240]

var renderer := "gl_compatibility"
var mode := "windowed"
var resolution := Vector2i(1600, 900)   # (0, 0) means the screen's native size
var ui_scale := 1.0
var vsync := true
var max_fps := 0                          # 0 = no limit
var animate := true
var smooth := true
var ask_demolish := true
var demolish_dry_mines := true          # demolish your mines once their vein runs dry (after a warning)
var auto_roads := false                 # lay a new building's road at once; off: you lay it yourself
var trial := ""                           # a renderer being tried in a one-off restart
var vk_probed := false                    # the first-start Vulkan test has been done
var log_rect := Rect2i()                  # where the event log window is (empty: the default place)
var log_open := true
var features := {}                        # feature id -> switched on; features not listed use their default
var language := "en"                      # interface language (see I18n)
var daynight := false                     # a slow day and night (only looks)
var vignette := true                      # the map darkens softly towards the screen's corners
var cb_colors := false                    # colours that stay apart for red-green colour blindness
var details := true                       # grass tufts, reeds, foam, snow on peaks
var raised := true                        # hills drawn raised (2.5D); off: a flat map
var pause_attacked := false   # pause the game when a rival attacks you or sails for your shore (build 66)
var store_folded := {}        # the stores list's groups folded away (build 72)
var voices := true        # a word from the worker when you pick a building (build 63)
var goals := true         # the sandbox goals in endless games (build 63)
var guide := true                         # show the first-game guide in a new game
var keys := {}                            # action -> key code the player chose (Keys in Settings)
var sea_guide := false                    # the sea and supplies guide has been shown once
var prio_presets := {}                    # name -> {"carry": {...}, "work": {...}}: priority sets the player saved
var sound_on := true
var master_vol := 0.8
var sfx_vol := 0.8
var amb_vol := 0.5
var music_vol := 0.55


func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	renderer = String(cf.get_value("display", "renderer", renderer))
	mode = String(cf.get_value("display", "mode", mode))
	resolution = cf.get_value("display", "resolution", resolution)
	ui_scale = float(cf.get_value("display", "ui_scale", ui_scale))
	vsync = bool(cf.get_value("display", "vsync", vsync))
	max_fps = int(cf.get_value("display", "max_fps", max_fps))
	animate = bool(cf.get_value("game", "animate", animate))
	smooth = bool(cf.get_value("game", "smooth", smooth))
	ask_demolish = bool(cf.get_value("game", "ask_demolish", ask_demolish))
	demolish_dry_mines = bool(cf.get_value("game", "demolish_dry_mines", demolish_dry_mines))
	auto_roads = bool(cf.get_value("game", "auto_roads", auto_roads))
	trial = String(cf.get_value("display", "trial", ""))
	vk_probed = bool(cf.get_value("display", "vk_probed", false))
	log_rect = cf.get_value("display", "log_rect", log_rect)
	log_open = bool(cf.get_value("display", "log_open", log_open))
	features = cf.get_value("game", "features", {})
	guide = bool(cf.get_value("game", "guide", guide))
	voices = bool(cf.get_value("game", "voices", voices))
	pause_attacked = bool(cf.get_value("game", "pause_attacked", pause_attacked))
	var sf = cf.get_value("ui", "store_folded", {})
	store_folded = sf if sf is Dictionary else {}
	goals = bool(cf.get_value("game", "goals", goals))
	raised = bool(cf.get_value("display", "raised", raised))
	daynight = bool(cf.get_value("display", "daynight", daynight))
	vignette = bool(cf.get_value("display", "vignette", vignette))
	cb_colors = bool(cf.get_value("display", "cb_colors", cb_colors))
	details = bool(cf.get_value("display", "details", details))
	language = String(cf.get_value("display", "language", language))
	keys = cf.get_value("game", "keys", {})
	prio_presets = cf.get_value("game", "prio_presets", {})
	sea_guide = bool(cf.get_value("game", "sea_guide", false))
	sound_on = bool(cf.get_value("sound", "on", sound_on))
	master_vol = float(cf.get_value("sound", "master", master_vol))
	sfx_vol = float(cf.get_value("sound", "effects", sfx_vol))
	amb_vol = float(cf.get_value("sound", "ambience", amb_vol))
	music_vol = float(cf.get_value("sound", "music", music_vol))


func save_file() -> void:
	var cf := ConfigFile.new()
	cf.set_value("display", "renderer", renderer)
	cf.set_value("display", "mode", mode)
	cf.set_value("display", "resolution", resolution)
	cf.set_value("display", "ui_scale", ui_scale)
	cf.set_value("display", "vsync", vsync)
	cf.set_value("display", "max_fps", max_fps)
	cf.set_value("display", "trial", trial)
	cf.set_value("display", "vk_probed", vk_probed)
	cf.set_value("game", "animate", animate)
	cf.set_value("game", "smooth", smooth)
	cf.set_value("game", "ask_demolish", ask_demolish)
	cf.set_value("game", "demolish_dry_mines", demolish_dry_mines)
	cf.set_value("game", "auto_roads", auto_roads)
	cf.set_value("display", "log_rect", log_rect)
	cf.set_value("display", "log_open", log_open)
	cf.set_value("game", "features", features)
	cf.set_value("game", "guide", guide)
	cf.set_value("game", "voices", voices)
	cf.set_value("game", "pause_attacked", pause_attacked)
	cf.set_value("ui", "store_folded", store_folded)
	cf.set_value("game", "goals", goals)
	cf.set_value("display", "raised", raised)
	cf.set_value("display", "daynight", daynight)
	cf.set_value("display", "vignette", vignette)
	cf.set_value("display", "details", details)
	cf.set_value("display", "cb_colors", cb_colors)
	cf.set_value("display", "language", language)
	cf.set_value("game", "keys", keys)
	cf.set_value("game", "prio_presets", prio_presets)
	cf.set_value("game", "sea_guide", sea_guide)
	cf.set_value("sound", "on", sound_on)
	cf.set_value("sound", "master", master_vol)
	cf.set_value("sound", "effects", sfx_vol)
	cf.set_value("sound", "ambience", amb_vol)
	cf.set_value("sound", "music", music_vol)
	# keep sections other parts of the game store here (the random events list)
	var old := ConfigFile.new()
	if old.load(PATH) == OK and old.has_section("events"):
		for k in old.get_section_keys("events"):
			cf.set_value("events", k, old.get_value("events", k))
	cf.save(PATH)


## The renderer this run actually uses. Vulkan renderers have a RenderingDevice; OpenGL has none.
## Which Vulkan renderer it is can't be asked from the engine (and "--rendering-method" on the command
## line is not among OS.get_cmdline_args()), so a restart names it again after "--" as "rm=<id>";
## otherwise it is the one in the override file or the project.
static func running_renderer() -> String:
	if RenderingServer.get_rendering_device() == null:
		return "gl_compatibility"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("rm="):
			return a.substr(3)
	var cf := ConfigFile.new()
	if FileAccess.file_exists(OVERRIDE) and cf.load(OVERRIDE) == OK:
		var m := String(cf.get_value("rendering", "renderer/rendering_method", ""))
		if m != "" and m != "gl_compatibility":
			return m
	var proj := String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"))
	return proj if proj != "gl_compatibility" else "forward_plus"


static func renderer_name(id: String) -> String:
	for r in RENDERERS:
		if r[0] == id:
			return String(r[1]).get_slice(",", 0)
	return id


## Makes renderer id the one the engine starts with from now on (OpenGL needs no file: it is the default).
static func write_override(id: String) -> void:
	if id == "gl_compatibility":
		if FileAccess.file_exists(OVERRIDE):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(OVERRIDE))
		return
	var f := FileAccess.open(OVERRIDE, FileAccess.WRITE)
	if f:
		f.store_string("[rendering]\n\nrenderer/rendering_method=\"%s\"\nrendering_device/driver=\"vulkan\"\n" % id)


static func has_override() -> bool:
	return FileAccess.file_exists(OVERRIDE)


## Arguments for restarting the game: when run from the editor's Godot rather than an exported game,
## the project folder has to be passed too.
static func restart_args(extra: PackedStringArray) -> PackedStringArray:
	var args := PackedStringArray()
	if not OS.has_feature("template"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(extra)
	return args


## Resolutions to offer: those no larger than the screen, and the screen's own size first.
static func sizes_for_screen() -> Array:
	var scr := DisplayServer.screen_get_size()
	var out := [Vector2i.ZERO]
	for s: Vector2i in SIZES:
		if s.x <= scr.x and s.y <= scr.y and s != scr:
			out.append(s)
	return out


static func size_name(s: Vector2i) -> String:
	if s == Vector2i.ZERO:
		var scr := DisplayServer.screen_get_size()
		return "Native (%d x %d)" % [scr.x, scr.y]
	return "%d x %d" % [s.x, s.y]


## Applies display mode, resolution, interface size, VSync and the frame limit to window win.
func apply(win: Window) -> void:
	var scr := DisplayServer.screen_get_size()
	match mode:
		"fullscreen":
			win.mode = Window.MODE_FULLSCREEN
		"exclusive":
			win.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		_:
			win.mode = Window.MODE_WINDOWED
			var want := resolution if resolution != Vector2i.ZERO else DisplayServer.screen_get_usable_rect().size
			want = Vector2i(mini(want.x, scr.x), mini(want.y, scr.y))
			win.size = want
			win.position = DisplayServer.screen_get_position() + (scr - want) / 2
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	apply_scale(win)


## How big things are drawn. In a window, or at native resolution, the game draws at the window's own
## size and the interface size just scales everything. In fullscreen at a lower resolution, the game
## draws at that resolution and the result is stretched to fill the screen: fewer pixels to draw,
## so it runs faster on a slow graphics card, but everything is softer and larger.
func apply_scale(win: Window) -> void:
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_factor = scale_now()
	if mode != "windowed" and resolution != Vector2i.ZERO:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		win.content_scale_size = resolution
	else:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		win.content_scale_size = win.size


## The interface size in use: the chosen one, or for Auto one that fits the screen.
func scale_now() -> float:
	if ui_scale > 0.0:
		return ui_scale
	var hgt := DisplayServer.screen_get_size().y
	if hgt <= 0:
		return 1.0
	return clampf(snappedf(hgt / 1080.0, 0.25), 1.0, 2.0) if hgt > 1200 else 1.0


## One step bigger (+1) or smaller (-1), for Ctrl and + or - (Auto turns into the size it had).
func step_scale(d: int) -> void:
	var cur := scale_now()
	var steps := UI_SCALES.filter(func(v): return v > 0.0)
	var i := 0
	for k in steps.size():
		if absf(float(steps[k]) - cur) < absf(float(steps[i]) - cur):
			i = k
	ui_scale = float(steps[clampi(i + d, 0, steps.size() - 1)])


## The ids of the features switched on for new games.
func enabled_features() -> Array:
	var out := []
	for e in Features.available():
		if bool(features.get(e.id, e.default_on and not e.mod)):
			out.append(e.id)
	return out
