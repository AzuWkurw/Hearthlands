class_name UiSettings
extends RefCounted
## The Settings window: renderer, display, resolution and options.
## Part of the interface: main.gd holds the shared state and calls in here; the functions reach
## the rest of the game through `main`.

var main: Main

var ask_check: CheckBox


func _init(p_owner: Main) -> void:
	main = p_owner


func _build_settings_panel() -> void:
	main.set_panel = main._overlay()
	main.set_body = main.set_panel.find_child("Body", true, false)
	main.set_panel.visible = false


func _open_settings() -> void:
	_fill_settings()
	main.set_panel.visible = true


## A row of the Settings window: a label on the left, a control on the right.
func _set_row(grid: GridContainer, title: String, ctrl: Control) -> void:
	var l := main._label(title, 15, Main.DIM)
	grid.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ctrl)


## A drop-down list; pick(i) is called with the index chosen.
func _choice(items: Array, current: int, pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for it in items:
		o.add_item(String(it))
	o.select(current)
	o.item_selected.connect(pick)
	return o


func _check(text: String, on: bool, toggled: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = on
	c.toggled.connect(toggled)
	return c


## Builds the Settings window's contents from the current settings (again after every change).
func _fill_settings() -> void:
	for c in main.set_body.get_children():
		main.set_body.remove_child(c)
		c.queue_free()
	main.set_body.add_child(main._label("Settings", 20, Main.BRASS))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 8)
	main.set_body.add_child(g)
	# renderer: OpenGL or Vulkan; changing it needs a restart
	var running := Settings.running_renderer()
	var ids := Settings.RENDERERS.map(func(r): return r[0])
	var langs := I18n.languages()
	var li := 0
	for k in langs.size():
		if langs[k][0] == main.settings.language: li = k
	_set_row(g, "Language", _choice(langs.map(func(l): return l[1]), li, func(i):
		main.settings.language = String(langs[i][0])
		main.settings.save_file()
		TranslationServer.set_locale(main.settings.language)
		main._show_hint(tr("Some text changes when its window is next opened or refreshed."), 4.0)
		_fill_settings.call_deferred()))
	_set_row(g, "Renderer", _choice(Settings.RENDERERS.map(func(r): return r[1]), maxi(0, ids.find(running)), func(i):
		_switch_renderer(String(ids[i]))))
	var adapter := "%s, %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()]
	var note := main._label(tr("Now drawing with %s on %s.") % [Settings.renderer_name(running), adapter], 13, Main.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(380, 0)
	_set_row(g, "", note)
	# display mode and resolution
	var modes := Settings.MODES.map(func(m): return m[0])
	_set_row(g, "Display", _choice(Settings.MODES.map(func(m): return m[1]), maxi(0, modes.find(main.settings.mode)), func(i):
		main.settings.mode = String(modes[i])
		_apply_settings()))
	var sizes := Settings.sizes_for_screen()
	if not sizes.has(main.settings.resolution):
		sizes.append(main.settings.resolution)
	_set_row(g, "Resolution", _choice(sizes.map(func(z): return Settings.size_name(z)), sizes.find(main.settings.resolution), func(i):
		main.settings.resolution = sizes[i]
		_apply_settings()))
	var rn := main._label("In a window this is the window size. In fullscreen a lower resolution draws fewer pixels: faster on a slow graphics card, but softer and larger.", 13, Main.DIM)
	rn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rn.custom_minimum_size = Vector2(380, 0)
	_set_row(g, "", rn)
	_set_row(g, "Interface size", _choice(Settings.UI_SCALES.map(func(v): return tr("Auto (%d%%)") % roundi(main.settings.scale_now() * 100) if v == 0.0 and main.settings.ui_scale == 0.0 else (tr("Auto (fits the screen)") if v == 0.0 else "%d%%" % roundi(v * 100))), maxi(0, Settings.UI_SCALES.find(main.settings.ui_scale)), func(i):
		main.settings.ui_scale = Settings.UI_SCALES[i]
		_apply_settings()))
	_set_row(g, "Frame rate limit", _choice(Settings.FPS_LIMITS.map(func(v): return "No limit" if v == 0 else "%d fps" % v), maxi(0, Settings.FPS_LIMITS.find(main.settings.max_fps)), func(i):
		main.settings.max_fps = Settings.FPS_LIMITS[i]
		_apply_settings()))
	_set_row(g, "", _check("VSync (wait for the screen; no tearing)", main.settings.vsync, func(on):
		main.settings.vsync = on
		_apply_settings()))
	_set_row(g, "", _check("Animations (turn off on slow computers)", main.settings.animate, func(on):
		main.settings.animate = on
		main.view.set_animate(on)
		main.settings.save_file()))
	_set_row(g, "", _check("Raised ground: hills stand up from the map (2.5D)", main.settings.raised, func(on):
		main.settings.raised = on
		main.view.raised = on
		main.settings.save_file()))
	_set_row(g, "", _check("Ground details: grass tufts, reeds, foam, snow on peaks", main.settings.details, func(on):
		main.settings.details = on
		main.view.set_details(on)
		main.settings.save_file()))
	_set_row(g, "", _check("Colour-blind colours (realms and warnings that stay apart for red-green colour blindness)", main.settings.cb_colors, func(on):
		main.settings.cb_colors = on
		main._apply_colors()
		main.settings.save_file()))
	_set_row(g, "", _check("Day and night (only the look changes)", main.settings.daynight, func(on):
		main.settings.daynight = on
		main.view.daynight = on
		main.settings.save_file()))
	_set_row(g, "", _check("Smooth scaling (turn off for a crisp pixel look)", main.settings.smooth, func(on):
		main.settings.smooth = on
		main.view.set_smooth(on)
		main.settings.save_file()))
	ask_check = _check("Ask before demolishing", main.ask_demolish, func(on):
		main.ask_demolish = on
		main.settings.ask_demolish = on
		main.settings.save_file())
	_set_row(g, "", ask_check)
	_set_row(g, "", _check(tr("Demolish mines whose vein has run dry (warns %d s before)") % Main.DRY_MINE_WAIT, main.settings.demolish_dry_mines, func(on):
		main.settings.demolish_dry_mines = on
		main.settings.save_file()))
	_set_row(g, "", _check("Show the first-game guide (in the next new game)", main.settings.guide, func(on):
		main.settings.guide = on
		main.settings.save_file()))
	# optional features: each one can be switched on or off, here and in the running game
	set_body_sound_rows(g)
	set_body_key_rows(g)
	set_body_feature_rows(g)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	main.set_body.add_child(row)
	row.add_child(main._button("Close (Esc)", func(): main.set_panel.visible = false))


## Applies display settings at once, saves them, and redraws the window to show the new choices.
func _apply_settings() -> void:
	main.settings.apply(main.get_window())
	main.settings.save_file()
	_fill_settings.call_deferred()


## Switching renderer means restarting the game. The game is autosaved first and continues after the
## restart. Vulkan is tried in a one-off start; if that works it is kept, if not the game stays on OpenGL.
func _switch_renderer(id: String) -> void:
	if id == Settings.running_renderer():
		# already drawing with it (for example started in OpenGL safe mode): just make it the saved choice
		if main.settings.renderer != id:
			Settings.write_override(id)
			main.settings.renderer = id
			main.settings.save_file()
			main._show_hint(tr("%s will be used from now on.") % Settings.renderer_name(id), 5.0)
		return
	var extra := PackedStringArray()
	if id == "gl_compatibility":
		Settings.write_override(id)
		main.settings.renderer = id
		extra.append_array(["--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3"])
	else:
		main.settings.trial = id
		extra.append_array(["--rendering-method", id, "--rendering-driver", "vulkan"])
	main.settings.save_file()
	var resume := main.sim.w > 0 and not main.setup.visible and not main.sim.over
	if resume:
		main._save_game("autosave", true)
	extra.append("--")
	extra.append("rm=" + id)
	if resume:
		extra.append("resume")
	main._show_hint(tr("Restarting with %s...") % Settings.renderer_name(id), 3.0)
	OS.set_restart_on_exit(true, Settings.restart_args(extra))
	main.get_tree().quit()


## The "Game features" rows: one switch per feature (built-in and mods), a switch for classic rules
## with every optional feature off, and the mods folder.
func set_body_feature_rows(g: GridContainer) -> void:
	var avail := Features.available()
	var on_ids: Array = main.sim.feature_ids() if main.sim.w > 0 else main.settings.enabled_features()
	_set_row(g, "Game features", main._label("Optional systems; switching one changes this game and new ones.", 13, main.DIM))
	var classic := _check("Classic rules (all optional features off)", on_ids.is_empty(), func(on):
		for e in avail:
			_set_feature(String(e.id), not on and bool(e.default_on))
		_refill())
	_set_row(g, "", classic)
	for e in avail:
		var missing := []
		for need in e.needs:
			if not (need in on_ids):
				for e2 in avail:
					if e2.id == need:
						missing.append(String(e2.title))
		var label := "%s%s" % [e.title, " (mod)" if e.mod else ""]
		if not missing.is_empty():
			label += "  (needs %s)" % ", ".join(missing)
		var cb := _check(label, String(e.id) in on_ids, func(on):
			_set_feature(String(e.id), on)
			_refill())
		cb.tooltip_text = String(e.info)
		cb.disabled = not missing.is_empty()
		_set_row(g, "", cb)
	var row := HBoxContainer.new()
	row.add_child(main._label("Mods folder: " + ProjectSettings.globalize_path(Features.MOD_DIR), 12, main.DIM))
	row.add_child(main._button("Open", func(): OS.shell_open(Features.ensure_mod_dir())))
	_set_row(g, "", row)


func _set_feature(fid: String, on: bool) -> void:
	main.settings.features[fid] = on
	main.settings.save_file()
	if main.sim.w > 0:
		main.set_feature(fid, on)


func _refill() -> void:
	_fill_settings.call_deferred()


## Sound: on or off, and three volumes.
func set_body_sound_rows(g: GridContainer) -> void:
	var st: Settings = main.settings
	_set_row(g, "Sound", _check("Sound on", st.sound_on, func(on):
		st.sound_on = on
		st.save_file()))
	for row in [["Volume", "master_vol"], ["Music", "music_vol"], ["Effects", "sfx_vol"], ["Ambience", "amb_vol"]]:
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(st.get(row[1]))
		sl.custom_minimum_size = Vector2(200, 24)
		sl.focus_mode = Control.FOCUS_NONE
		var key: String = row[1]
		sl.value_changed.connect(func(v):
			st.set(key, v)
			st.save_file())
		sl.drag_ended.connect(func(_c):
			if main.sound != null:
				main.sound.play("click", 1.0, 0.0))
		_set_row(g, String(row[0]), sl)


## Keys: one row per action, with a button showing its key; click it, then press the new key.
func set_body_key_rows(g: GridContainer) -> void:
	var first := true
	for a in Main.KEY_ACTIONS:
		var id := String(a[0])
		var waiting: bool = main.key_wait == id
		var b := main._button("press a key... (Esc: keep)" if waiting else OS.get_keycode_string(main.key_for(id)), func():
			main.key_wait = id
			_fill_settings())
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(110, 0)
		b.tooltip_text = tr("Click, then press the key for: %s") % tr(String(a[1]))
		var row := HBoxContainer.new()
		row.add_child(b)
		row.add_child(main._label(tr(String(a[1])), 13, Main.DIM))
		_set_row(g, "Keys" if first else "", row)
		first = false
	var reset := main._button("Default keys", func():
		main.settings.keys = {}
		main.settings.save_file()
		_fill_settings())
	reset.focus_mode = Control.FOCUS_NONE
	_set_row(g, "", reset)
