class_name Main


extends Control
## Builds the interface in code and runs the game loop.


const SIDE_W := 404
const DRY_MINE_WAIT := 30           # seconds between the warning and demolishing a mine that has run dry


const BRASS := Color("d8aa4a")


const DIM := Color("9a9c88")


var sim := Sim.new()

## The interface's parts (see ui_*.gd). Each holds a reference back to this object.
var research_ui := UiResearch.new(self)
var settings_ui := UiSettings.new(self)
var demolish_ui := UiDemolish.new(self)
var saves_ui := UiSaves.new(self)
var diplomacy_ui := UiDiplomacy.new(self)
var targets_ui := UiTargets.new(self)
var textures_ui := UiTextures.new(self)


var view: MapView


var minimap: Minimap


var paused := true


var speed := 1.0


var acc := 0.0


var ui_t := 0.0


var hint_t := 0.0


var cat := "raw"


var lbl_time: Label


var lbl_pop: Label


var lbl_foes: Label


var btn_pause: Button


var speed_btns := {}


var stock_labels := {}


var stock_icons := {}


var folk_label: RichTextLabel


var build_grid: GridContainer


var build_buttons := {}


var cat_buttons := {}


var sel_label: RichTextLabel


var sel_actions: HBoxContainer


var prio_row: HBoxContainer        # High / Normal / Low / Paused buttons for the selected building
var garrison_box: VBoxContainer    # the garrison settings of your selected military building
var _gar_sig := ""                 # what the garrison settings were last drawn from (rebuilt only on change)


var rivals_label: RichTextLabel


var log_ui := UiLog.new(self)      # the movable event log window (ui_log.gd)
var toolbar := UiToolbar.new(self) # the bottom toolbar: building menus, roads, demolish, scouts (ui_toolbar.gd)
var sound: Sound                    # sound effects and ambience (sound.gd)
var top_bar: HFlowContainer
var lbl_feat: Label                 # what features show on the top bar (season, weather)
var feature_ui := {}               # feature id -> {"nodes": [...], "keys": {keycode: Callable}}


var hint: Label


var setup: Control


var seed_edit: LineEdit


var foes_slider: HSlider


var foes_lbl: Label


var str_slider: HSlider


var str_lbl: Label


var mix_check: CheckBox


var end_panel: Control


var end_title: Label


var end_text: Label


var tex_panel: Control


var log_dirty := true


var size_opt: OptionButton


var rv_check: CheckBox


var diff := {}                     # the difficulty controls on the new-game screen


var targets_panel: Control         # the Production targets window


var research_label: RichTextLabel


var research_bar: ProgressBar


var tech_panel: Control


var save_panel: Control


var save_list: VBoxContainer


var autosave_t := 0.0


var rp_hist: Array = []


var sel_res := ""


var sel_box: PanelContainer


var tool_buttons := {}


var perf_label: Label


var perf_t := 0.0


var perf_last := {"time": 0.0, "usec": 0}


const TOOLS := [["@road", "Build road", "road_5", "Click one of your roads or buildings, then where the road should go. Keeps going from the end; Esc stops."], ["@pave", "Pave road", "road_paved_5", "Click a road to pave up to 12 tiles with stone (1 stone each). Carriers walk paved roads faster."], ["@unroad", "Remove road", "road_15", "Click a road to remove that stretch, up to the next junction or building."]]


var dip_btn: Button


var confirm_panel: Control


var confirm_title: Label


var confirm_text: RichTextLabel


var ask_demolish := true           # the "Ask before demolishing" option


var settings := Settings.new()     # options kept between games (settings.gd)


var set_panel: Control             # the Settings window


var set_body: VBoxContainer


var dip_panel: Control


var dip_rivals: VBoxContainer


var trade_who: OptionButton


var trade_give: OptionButton


var trade_give_n: SpinBox


var trade_want: OptionButton


var trade_result: Label


const SAVE_DIR := "user://saves"


const SIZES := [["Auto (fits the realms)", 0], ["Small (96)", 96], ["Medium (128)", 128], ["Large (160)", 160], ["Huge (200)", 200], ["Giant (256)", 256]]


func _exit_tree() -> void:
	sim.dispose()


# ================================================================ feature interface
## Features (scripts/features, and mods) add their own buttons, windows and keys through these, and the
## game removes them again when the feature is switched off.
func _feature_entry(f: Feature) -> Dictionary:
	if not feature_ui.has(f.id):
		feature_ui[f.id] = {"nodes": [], "keys": {}}
	return feature_ui[f.id]


## A button on the top bar.
func add_feature_button(f: Feature, text: String, pressed: Callable) -> Button:
	var b := _button(text, pressed)
	top_bar.add_child(b)
	_feature_entry(f).nodes.append(b)
	return b


## A hidden, movable and resizable window; the feature fills it and shows it when it likes.
func add_feature_window(f: Feature, title: String, size_px: Vector2i) -> Window:
	var w := Window.new()
	w.title = title
	w.transient = true
	w.visible = false
	w.size = size_px
	w.min_size = Vector2i(320, 200)
	w.position = Vector2i(60, int(top_bar.get_parent().size.y) + 44)
	w.theme = UiLog.window_theme()
	w.close_requested.connect(func(): w.visible = false)
	# keys pressed while the window has focus still reach the game's shortcuts
	w.window_input.connect(func(e): if e is InputEventKey: _unhandled_input(e))
	add_child(w)
	_feature_entry(f).nodes.append(w)
	return w


## Floating windows (the event log, feature windows) are drawn above everything else, so while a big
## panel such as the new-game screen or the research tree is open they step aside, and come back after.
var _stepped_aside: Array = []


func _hide_windows_under_panels() -> void:
	var covered := false
	for c: Control in [setup, end_panel, tex_panel, targets_panel, tech_panel, save_panel, confirm_panel, set_panel, dip_panel, kinds_panel]:
		if c != null and c.visible:
			covered = true
			break
	if covered and _stepped_aside.is_empty():
		var wins: Array = [log_ui.win]
		for fid in feature_ui:
			for n: Node in feature_ui[fid].nodes:
				if n is Window:
					wins.append(n)
		for w: Window in wins:
			if w != null and w.visible:
				w.visible = false
				_stepped_aside.append(w)
	elif not covered and not _stepped_aside.is_empty():
		for w in _stepped_aside:
			if is_instance_valid(w):
				(w as Window).visible = true
		_stepped_aside.clear()


## Where the player dragged the info box (its top-left corner), or (-1, -1) for the lower right corner.
var sel_pos := Vector2(-1, -1)


## Sizes the info box to its text and keeps it inside the map area, below the top bar.
func _place_sel_box() -> void:
	if sel_box == null or not sel_box.visible:
		return
	var want := sel_box.get_combined_minimum_size()
	var area := Rect2(8, 8 + top_bar.get_parent().size.y + 4, size.x - SIDE_W - 16, 0)
	area.size.y = size.y - 8 - UiToolbar.BAR_H - 10 - area.position.y
	var sz := Vector2(want.x, minf(want.y, area.size.y))
	var pos := sel_pos if sel_pos.x >= 0.0 else area.end - sz
	pos.x = clampf(pos.x, area.position.x, maxf(area.position.x, area.end.x - sz.x))
	pos.y = clampf(pos.y, area.position.y, maxf(area.position.y, area.end.y - sz.y))
	if sel_box.size != sz:
		sel_box.size = sz
	if sel_box.position != pos:
		sel_box.position = pos


func _sel_drag(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed and e.double_click:
		sel_pos = Vector2(-1, -1)
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		sel_pos = sel_box.position + e.relative


## A keyboard shortcut.
func add_feature_key(f: Feature, keycode: int, pressed: Callable) -> void:
	_feature_entry(f).keys[keycode] = pressed


## Removes every feature's interface and builds it again for the features now switched on.
func _rebuild_feature_ui() -> void:
	for fid in feature_ui:
		for n: Node in feature_ui[fid].nodes:
			if is_instance_valid(n):
				n.queue_free()
	feature_ui.clear()
	for f: Feature in sim.features:
		f.build_ui(self)
	# goods and buildings that belong to a switched-off feature are hidden
	_known_sig = ""
	_known_res = {}
	_refresh_stock_rows()
	if build_grid != null:
		_rebuild_build_list()


var _list_techs := -1                # research count when the build list was last made
var _known_res: Dictionary = {}       # goods your realm knows of (see res_known)
var _known_sig := ""


## Whether good id is in play: goods that belong to a switched-off feature are hidden, and so are
## goods your realm doesn't know of yet.
func res_shown(id: String) -> bool:
	var fid := String(GameData.res_by_id.get(id, {}).get("feature", ""))
	return (fid == "" or sim.feature_on(fid)) and res_known(id)


## A good is known once some building you can build makes it, uses it, or costs it (or its trade
## needs it as a tool), or once you have ever had some in store.
func res_known(id: String) -> bool:
	if sim.players.is_empty():
		return true
	var p := sim.human()
	var sig := "%d:%d:%d" % [p.techs.size(), sim.features.size(), sim.blds.size()]
	if sig != _known_sig:
		_known_sig = sig
		for bid in GameData.bld:
			var d: Dictionary = GameData.bld[bid]
			if not sim.bld_enabled(bid) or (d.has("tech") and not p.techs.has(d.tech)):
				continue
			for part in ["cost", "in", "out"]:
				for k in d.get(part, {}):
					_known_res[k] = true
			var tl := GameData.tool_for(GameData.trade(bid))
			if tl != "":
				_known_res[tl] = true
		for k in ["bread", "fish", "meat", "water"]:
			_known_res[k] = true
	if _known_res.has(id):
		return true
	if float(p.stock.get(id, 0.0)) >= 1.0:
		_known_res[id] = true
		return true
	return false


## Shows the stock rows of the goods your realm knows of, hides the rest.
func _refresh_stock_rows() -> void:
	for id in stock_labels:
		(stock_labels[id] as Control).get_parent().visible = res_shown(id)


## Switches a feature on or off in the running game (from Settings).
func set_feature(id: String, on: bool) -> void:
	sim.set_feature(id, on)
	_rebuild_feature_ui()


func _ready() -> void:
	if "vkprobe" in OS.get_cmdline_user_args():
		# the Vulkan test start: report what it draws with once a frame is on screen, then quit
		set_process(false); set_physics_process(false); set_process_input(false); set_process_unhandled_input(false)
		await RenderingServer.frame_post_draw
		var f := FileAccess.open(Settings.PROBE, FileAccess.WRITE)
		if f:
			f.store_string(Settings.running_renderer())
			f.close()
		get_tree().quit()
		return
	GameData.ensure()
	settings.load_file()
	_build_ui()
	settings.apply(get_window())
	view.set_animate(settings.animate)
	view.set_smooth(settings.smooth)
	view.auto_roads = settings.auto_roads
	ask_demolish = settings.ask_demolish
	# in a window the interface size must follow the window when it is resized
	get_window().size_changed.connect(func(): settings.apply_scale(get_window()))
	resized.connect(func(): toolbar.fit())
	sim.log_added.connect(func(_t, _c): log_dirty = true)
	sound = Sound.new()
	sound.name = "Sound"
	add_child(sound)
	sound.setup(self)
	sim.log_added.connect(sound.on_log)
	sim.ended.connect(_on_end)
	seed_edit.text = _rand_seed()
	_start(seed_edit.text, 3, 5, true)
	paused = true
	setup.visible = true
	if GameData.errors.size() > 0:
		_show_hint("Data problems: " + "; ".join(GameData.errors), 12.0)
	_after_restart()


## Finishes a restart asked for in Settings: keeps a renderer that started fine, reports one that did
## not, and continues the game that was autosaved just before.
func _after_restart() -> void:
	var args := OS.get_cmdline_user_args()
	var running := Settings.running_renderer()
	if settings.trial != "":
		var want := settings.trial
		settings.trial = ""
		if running == want:
			Settings.write_override(want)
			settings.renderer = want
			_show_hint("Now drawing with %s. It will be used from now on." % Settings.renderer_name(want), 8.0)
		else:
			settings.renderer = running
			_show_hint("%s could not start on this PC, so the game stays with %s." % [Settings.renderer_name(want), Settings.renderer_name(running)], 10.0)
		settings.save_file()
	elif running != settings.renderer:
		_show_hint("Started with %s instead of the chosen %s (safe mode?). Pick a renderer in Settings to keep one." % [Settings.renderer_name(running), Settings.renderer_name(settings.renderer)], 10.0)
	if "resume" in args and FileAccess.file_exists(SAVE_DIR + "/autosave.save"):
		_load_game("autosave")
	elif _should_probe_vulkan(running):
		_probe_vulkan()


## Vulkan is the preferred renderer. It is tested once, on the first start that runs with the default
## OpenGL and no renderer picked in Settings; not in OpenGL safe mode, tests or a headless run.
func _should_probe_vulkan(running: String) -> bool:
	if settings.vk_probed or Settings.has_override() or running != "gl_compatibility":
		return false
	var a := OS.get_cmdline_args()
	if "--rendering-driver" in a or "--rendering-method" in a or "--script" in a or "-s" in a:
		return false
	return DisplayServer.get_name() != "headless"


## Starts the game a second time in a small window with Vulkan. If that start draws a frame, Vulkan
## works here: it is saved as the renderer and, at the start screen, the game restarts with it at once.
## If not (no Vulkan driver, or it hangs on an error box), the test is stopped and the game stays on
## OpenGL. Either way it is done only once.
func _probe_vulkan() -> void:
	settings.vk_probed = true
	settings.save_file()
	if FileAccess.file_exists(Settings.PROBE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PROBE))
	var pid := OS.create_process(OS.get_executable_path(), Settings.restart_args(PackedStringArray([
		"--rendering-method", "forward_plus", "--rendering-driver", "vulkan", "--audio-driver", "Dummy",
		"--resolution", "320x180", "--", "vkprobe"])))
	if pid <= 0:
		return
	var ok := false
	for i in 40:
		await get_tree().create_timer(0.5).timeout
		if FileAccess.file_exists(Settings.PROBE):
			ok = FileAccess.get_file_as_string(Settings.PROBE).strip_edges() == "forward_plus"
			break
		if not OS.is_process_running(pid):
			break
	if OS.is_process_running(pid):
		OS.kill(pid)
	if FileAccess.file_exists(Settings.PROBE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PROBE))
	if not ok:
		print("Vulkan test start failed; staying with OpenGL")
		return
	Settings.write_override("forward_plus")
	settings.renderer = "forward_plus"
	settings.save_file()
	if setup.visible:
		_show_hint("Vulkan works on this PC: restarting with it...", 3.0)
		await get_tree().create_timer(0.6).timeout
		OS.set_restart_on_exit(true, Settings.restart_args(PackedStringArray(["--rendering-method", "forward_plus", "--rendering-driver", "vulkan"])))
		get_tree().quit()
	else:
		_show_hint("Vulkan works on this PC; it will be used from the next start (or switch now in Settings).", 10.0)


# ================================================================ UI construction

func _panel_style(alpha := 0.92) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.15, 0.125, alpha)
	sb.border_color = Color("3a4136")
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	return sb


func _label(text: String, size := 15, color := Color("e6e2d3")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(_click)
	b.pressed.connect(cb)
	return b


func _click() -> void:
	if sound != null:
		sound.play("click", 0.5)


func _rich(min_h := 0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = min_h == 0
	r.scroll_active = min_h > 0
	r.custom_minimum_size = Vector2(0, min_h)
	r.add_theme_font_size_override("normal_font_size", 14)
	r.add_theme_font_size_override("bold_font_size", 14)
	return r


func _section(parent: Control, title: String) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(1.0))
	parent.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)
	v.add_child(_label(title.to_upper(), 14, BRASS))
	return v


func _overlay() -> Control:
	var o := Control.new()
	o.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.offset_right = -SIDE_W
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(o)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.04, 0.8)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	o.add_child(cc)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_style(1.0))
	pc.custom_minimum_size = Vector2(480, 0)
	cc.add_child(pc)
	# the body scrolls when it is taller than the screen (Settings on a small screen, say)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc.add_child(sc)
	var v := VBoxContainer.new()
	v.name = "Body"
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	v.minimum_size_changed.connect(_fit_overlay.bind(sc, v))
	o.resized.connect(_fit_overlay.bind(sc, v))
	return o


## Makes an overlay's scroll area as big as its contents, but no taller than the screen allows.
func _fit_overlay(sc: ScrollContainer, v: Control) -> void:
	var want := v.get_combined_minimum_size()
	var room := maxf(200.0, size.y - 60.0)
	var sz := Vector2(want.x + (12.0 if want.y > room else 0.0), minf(want.y, room))
	if sc.custom_minimum_size != sz:
		sc.custom_minimum_size = sz


func _body(o: Control) -> VBoxContainer:
	return o.find_child("Body", true, false)


func _build_ui() -> void:
	view = MapView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.offset_right = -SIDE_W
	view.sim = sim
	view.tile_clicked.connect(_on_tile)
	view.cancel_requested.connect(_cancel_place)
	add_child(view)

	# top bar
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _panel_style())
	# as wide as the map; the buttons wrap onto a second row when they don't fit
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 8; top.offset_top = 8; top.offset_right = -SIDE_W - 8
	add_child(top)
	var tb := HFlowContainer.new()
	top_bar = tb
	tb.add_theme_constant_override("h_separation", 6)
	tb.add_theme_constant_override("v_separation", 4)
	top.add_child(tb)
	tb.add_child(_label("Hearthlands", 18, BRASS))
	tb.add_child(_label(Version.short(), 13, DIM))
	lbl_time = _label("00:00"); tb.add_child(lbl_time)
	lbl_pop = _label(""); tb.add_child(lbl_pop)
	lbl_foes = _label(""); tb.add_child(lbl_foes)
	lbl_feat = _label("", 14, BRASS); tb.add_child(lbl_feat)
	btn_pause = _button("Pause", _toggle_pause); tb.add_child(btn_pause)
	for s in [1, 2, 4, 8]:
		var b := _button("%dx" % s, _set_speed.bind(float(s)))
		b.toggle_mode = true
		speed_btns[s] = b
		tb.add_child(b)
	tb.add_child(_button("Research", _open_tech))
	dip_btn = _button("Diplomacy", _open_diplomacy)
	tb.add_child(dip_btn)
	tb.add_child(_button("Save / Load", _open_saves))
	tb.add_child(_button("Settings", _open_settings))
	tb.add_child(_button("Events", func(): log_ui.toggle()))
	tb.add_child(_button("New game", func(): setup.visible = true; paused = true))

	minimap = Minimap.new()
	minimap.sim = sim
	minimap.view = view
	view.minimap = minimap
	minimap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	# above the toolbar along the bottom
	minimap.offset_left = 8; minimap.offset_right = 196
	minimap.offset_top = -196 - UiToolbar.BAR_H - 10; minimap.offset_bottom = -8 - UiToolbar.BAR_H - 10
	add_child(minimap)

	hint = _label("", 15)
	var hs := _panel_style()
	hint.add_theme_stylebox_override("normal", hs)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -200; hint.offset_right = 200 - SIDE_W
	hint.offset_top = -48 - UiToolbar.BAR_H - 10; hint.offset_bottom = -12 - UiToolbar.BAR_H - 10
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.visible = false
	add_child(hint)
	perf_label = _label("", 13)
	perf_label.add_theme_stylebox_override("normal", _panel_style())
	perf_label.position = Vector2(8, 56)
	perf_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	perf_label.visible = false
	add_child(perf_label)

	# side panel
	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", _panel_style(1.0))
	side.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -SIDE_W; side.offset_right = 0; side.offset_top = 0; side.offset_bottom = 0
	add_child(side)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	scroll.add_child(col)

	var st := _section(col, "Stores")
	st.add_child(_button("Production targets (T)", _open_targets))
	var stn := _label("All your stores together. Each store keeps its own goods: click one to see what it holds.", 12, DIM)
	stn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stn.custom_minimum_size = Vector2(SIDE_W - 40, 0)
	st.add_child(stn)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	st.add_child(grid)
	for r in GameData.resources:
		var hb := HBoxContainer.new()
		hb.tooltip_text = String(r.name)
		hb.mouse_filter = Control.MOUSE_FILTER_STOP
		hb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hb.gui_input.connect(_on_stock_click.bind(String(r.id)))
		var ic := TextureRect.new()
		ic.texture = Tex.get_tex("res_" + String(r.id))
		ic.custom_minimum_size = Vector2(20, 20)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		hb.add_child(ic)
		var l := _label("0", 14)
		l.custom_minimum_size = Vector2(52, 0)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		hb.add_child(l)
		stock_labels[r.id] = l
		stock_icons[r.id] = ic
		grid.add_child(hb)

	var fk := _section(col, "People")
	folk_label = _rich(); fk.add_child(folk_label)

	var rs := _section(col, "Research")
	research_label = _rich(); rs.add_child(research_label)
	research_bar = ProgressBar.new(); research_bar.custom_minimum_size = Vector2(0, 16); research_bar.show_percentage = false
	rs.add_child(research_bar)
	rs.add_child(_button("Open research tree (R)", _open_tech))

	# building menus, road tools, demolish and scouts are on the toolbar along the bottom of the map
	toolbar.build()
	cat_buttons = toolbar.cat_btns

	# the info box sits in the lower right corner of the map; drag its title to put it elsewhere,
	# double-click the title to send it back. _place_sel_box keeps it whole on screen as it grows.
	sel_box = PanelContainer.new()
	sel_box.add_theme_stylebox_override("panel", _panel_style(0.95))
	add_child(sel_box)
	var se := VBoxContainer.new()
	sel_box.add_child(se)
	var sel_head := HBoxContainer.new(); se.add_child(sel_head)
	sel_head.mouse_filter = Control.MOUSE_FILTER_STOP
	sel_head.mouse_default_cursor_shape = Control.CURSOR_MOVE
	sel_head.tooltip_text = "Drag to move. Double-click to put it back in the corner."
	sel_head.gui_input.connect(_sel_drag)
	var sel_title := _label("INFO", 14, BRASS); sel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sel_head.add_child(sel_title)
	sel_head.add_child(_button("Close", _clear_selection))
	sel_label = _rich(); sel_label.custom_minimum_size = Vector2(390, 0); se.add_child(sel_label)
	garrison_box = VBoxContainer.new(); garrison_box.add_theme_constant_override("separation", 4); se.add_child(garrison_box)
	prio_row = HBoxContainer.new(); se.add_child(prio_row)
	sel_actions = HBoxContainer.new(); se.add_child(sel_actions)
	sel_box.visible = false

	var rv := _section(col, "Rivals")
	rivals_label = _rich(); rv.add_child(rivals_label)

	log_ui.build()

	var tx := _section(col, "Textures and mods")
	var info := _label("Put PNG files in the texture folder to replace any picture. Use Export defaults to get every current texture as a starting point, then Reload.", 13, DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(SIDE_W - 40, 0)
	tx.add_child(info)
	var tf := HFlowContainer.new(); tx.add_child(tf)
	tf.add_child(_button("Open texture folder", func(): Tex.open_user_dir()))
	tf.add_child(_button("Export defaults", func():
		var n := Tex.export_defaults()
		var p := Tex.write_manifest()
		_show_hint("Wrote %d textures and a list to %s" % [n, p.get_base_dir()], 6.0)))
	tf.add_child(_button("Reload textures", _reload_textures))
	tf.add_child(_button("Browse textures", _open_textures))
	var sl := _label("Smooth scaling, animations and other options are in Settings.", 13, DIM)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.custom_minimum_size = Vector2(200, 0)
	tx.add_child(sl)
	tx.add_child(_button("Open mod folder (data and textures)", func():
		DirAccess.make_dir_recursive_absolute("user://data")
		OS.shell_open(ProjectSettings.globalize_path("user://"))))

	var hp := _section(col, "How to play")
	var help := _label("Start with woodcutters, a sawmill and a quarry. Add houses, then food: fishers, hunters, farms with a mill, well and bakery. Guard huts and towers push your border out and need a soldier each. Mines go on mountain deposits and need food. Smelt iron for a toolsmith: every trade's new workers need their own tool (axes, pickaxes, farm tools...), while a returning specialist brings his own. Set production targets (T) to keep stocks where you want them. Weapons let barracks train soldiers. Armor makes veterans. Goods are carried along roads to the nearest store: build storehouses near busy areas, mule stations and cart yards for faster transport, and pave busy roads. Each store tier adds room for every good. Scriptoriums, libraries and universities produce research; open the research tree to pick what to study next, from Roman times to the Industrial Revolution. Beer, clothes, jewelry and furniture keep artisans and nobles content, which speeds up workshops and raises gold tax.\n\nDrag to pan, wheel to zoom, right click or Esc cancels. Hold Shift to place several. Pick buildings from the toolbar along the bottom; a building's entrance (the flag) faces south and R turns it while placing; then lay its road from the flag (or switch on Auto roads). Select one of your military buildings, then click an enemy one in range to attack. Space pauses, 1 to 4 set speed, R opens research, T production targets, G diplomacy, F3 shows performance, F5 quick saves and F9 quick loads.", 13, DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(SIDE_W - 40, 0)
	hp.add_child(help)

	_build_setup()
	_build_end()
	_build_tex_panel()
	_build_tech_panel()
	_build_save_panel()
	_build_confirm_panel()
	_build_settings_panel()
	_build_targets_panel()
	_build_diplomacy_panel()
	sim.diplomacy_changed.connect(_on_diplomacy_changed)
	_set_cat("raw")
	_set_speed(1.0)


func _build_setup() -> void:
	setup = _overlay()
	var v := _body(setup)
	v.add_child(_label("New realm", 26, BRASS))
	v.add_child(_label("Hearthlands " + Version.long(), 12, DIM))
	var p := _label("Every map is generated from its seed. Rivals run the same economy as you and scale with the strength you pick.", 14, DIM)
	p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.custom_minimum_size = Vector2(440, 0)
	v.add_child(p)
	var r1 := HBoxContainer.new(); v.add_child(r1)
	r1.add_child(_label("Map seed"))
	seed_edit = LineEdit.new(); seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r1.add_child(seed_edit)
	r1.add_child(_button("Random", func(): seed_edit.text = _rand_seed()))
	foes_lbl = _label(""); v.add_child(foes_lbl)
	foes_slider = HSlider.new(); foes_slider.min_value = 1; foes_slider.max_value = 8; foes_slider.value = 3
	foes_slider.value_changed.connect(func(x): foes_lbl.text = "Rival realms: %d" % int(x))
	v.add_child(foes_slider)
	str_lbl = _label(""); v.add_child(str_lbl)
	str_slider = HSlider.new(); str_slider.min_value = 1; str_slider.max_value = 10; str_slider.value = 5
	var names := ["", "Gentle", "Easy", "Easy+", "Moderate", "Normal", "Normal+", "Hard", "Hard+", "Brutal", "Merciless"]
	str_slider.value_changed.connect(func(x): str_lbl.text = "Rival strength: %s (%d)" % [names[int(x)], int(x)])
	v.add_child(str_slider)
	mix_check = CheckBox.new(); mix_check.text = "Vary each rival's skill"; mix_check.button_pressed = true; v.add_child(mix_check)
	var r2 := HBoxContainer.new(); v.add_child(r2)
	r2.add_child(_label("Map size"))
	size_opt = OptionButton.new(); size_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in SIZES:
		size_opt.add_item(String(s[0]))
	r2.add_child(size_opt)
	rv_check = CheckBox.new(); rv_check.text = "Research victory: first to the Industrial Revolution wins"; rv_check.button_pressed = true; v.add_child(rv_check)
	_build_difficulty(v)
	foes_slider.value_changed.emit(foes_slider.value)
	str_slider.value_changed.emit(str_slider.value)
	var go := _button("Found the realm", func():
		var sz: int = SIZES[size_opt.selected][1]
		var n := int(foes_slider.value) + 1
		if sz > 0 and sz < WorldGen.min_size(n):
			_show_hint("A %d-tile map is too small for %d realms. Pick at least %d tiles or fewer rivals." % [sz, n, WorldGen.min_size(n)], 6.0)
			return
		var o := _difficulty_opts()
		o["features"] = settings.enabled_features()
		if not _start(seed_edit.text if seed_edit.text != "" else "hearth", int(foes_slider.value), int(str_slider.value), mix_check.button_pressed, sz, rv_check.button_pressed, o):
			_show_hint("Could not fit that many realms on this map. Try another seed or a bigger map.", 5.0)
			return
		setup.visible = false
		paused = false
		_set_speed(1.0))
	go.custom_minimum_size = Vector2(0, 44)
	v.add_child(go)
	v.add_child(_button("Load a saved game", _open_saves))


## Difficulty choices: [label, option key, [[shown text, value], ...]].
const DIFF_CHOICES := [
	["Starting goods", "start_goods", [["Scarce (half)", 0.5], ["Normal", 1.0], ["Plenty (double)", 2.0], ["Rich (four times)", 4.0]]],
	["Peace at the start", "peace_min", [["None", 0], ["10 minutes", 10], ["20 minutes", 20], ["40 minutes", 40], ["60 minutes", 60]]],
	["Research speed", "research", [["50%", 0.5], ["100%", 1.0], ["200%", 2.0], ["400%", 4.0]]],
	["Construction speed", "build", [["100%", 1.0], ["150%", 1.5], ["200%", 2.0]]],
]


const DIFF_CHECKS := [["Endless ore veins", "endless_ore"], ["Endless stone, clay and fish", "endless_raw"], ["New workers need their trade's tool", "tools"],
	["All research done at the start", "all_research"], ["Creative mode: build free and at once, stores never run low", "creative"]]


## Presets: option values plus a rival strength. "Custom" leaves everything as it is.
const DIFF_PRESETS := [
	["Easy", {"start_goods": 2.0, "peace_min": 20, "research": 2.0, "build": 1.5, "endless_ore": true, "endless_raw": false, "tools": true, "all_research": false, "creative": false}, 3],
	["Normal", {"start_goods": 1.0, "peace_min": 0, "research": 1.0, "build": 1.0, "endless_ore": false, "endless_raw": false, "tools": true, "all_research": false, "creative": false}, 5],
	["Hard", {"start_goods": 0.5, "peace_min": 0, "research": 1.0, "build": 1.0, "endless_ore": false, "endless_raw": false, "tools": true, "all_research": false, "creative": false}, 8],
	["Custom", {}, 0],
]


## The Difficulty part of the new-game screen: a preset and the options it sets.
func _build_difficulty(v: VBoxContainer) -> void:
	v.add_child(_label("Difficulty", 16, BRASS))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	v.add_child(g)
	g.add_child(_label("Preset", 14, DIM))
	var pre := OptionButton.new()
	pre.focus_mode = Control.FOCUS_NONE
	for d in DIFF_PRESETS:
		pre.add_item(String(d[0]))
	pre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(pre)
	diff["preset"] = pre
	for c in DIFF_CHOICES:
		g.add_child(_label(String(c[0]), 14, DIM))
		var o := OptionButton.new()
		o.focus_mode = Control.FOCUS_NONE
		for it in c[2]:
			o.add_item(String(it[0]))
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# changing a single option turns the preset into Custom
		o.item_selected.connect(func(_i): pre.select(DIFF_PRESETS.size() - 1))
		g.add_child(o)
		diff[c[1]] = o
	var checks := HFlowContainer.new()
	v.add_child(checks)
	for c in DIFF_CHECKS:
		var cb := CheckBox.new()
		cb.text = String(c[0])
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(_on): pre.select(DIFF_PRESETS.size() - 1))
		checks.add_child(cb)
		diff[c[1]] = cb
	pre.item_selected.connect(_apply_preset)
	pre.select(1)
	_apply_preset(1)


## Sets every difficulty control (and the rival strength) from preset i.
func _apply_preset(i: int) -> void:
	var vals: Dictionary = DIFF_PRESETS[i][1]
	if vals.is_empty():
		return
	for c in DIFF_CHOICES:
		var o: OptionButton = diff[c[1]]
		for k in (c[2] as Array).size():
			if is_equal_approx(float(c[2][k][1]), float(vals[c[1]])):
				o.select(k)
	for c in DIFF_CHECKS:
		(diff[c[1]] as CheckBox).set_pressed_no_signal(bool(vals[c[1]]))
	str_slider.value = int(DIFF_PRESETS[i][2])
	(diff["preset"] as OptionButton).select(i)


## The options chosen on the new-game screen, for Sim.new_game.
func _difficulty_opts() -> Dictionary:
	var o := {}
	for c in DIFF_CHOICES:
		o[c[1]] = c[2][(diff[c[1]] as OptionButton).selected][1]
	for c in DIFF_CHECKS:
		o[c[1]] = (diff[c[1]] as CheckBox).button_pressed
	return o


## Steps the − and + buttons move through; -1 means no target.
const TARGET_STEPS := [-1, 0, 2, 5, 10, 15, 20, 30, 50, 80, 120, 200, 300, 500]


# ================================================================ end screen

func _build_end() -> void:
	end_panel = _overlay()
	var v := _body(end_panel)
	end_title = _label("Victory", 28, BRASS); v.add_child(end_title)
	end_text = _label("", 15, DIM); v.add_child(end_text)
	v.add_child(_button("New game", func(): end_panel.visible = false; setup.visible = true))
	end_panel.visible = false


# ================================================================ game flow

func _rand_seed() -> String:
	var chars := "abcdefghijkmnpqrstuvwxyz23456789"
	var s := ""
	for i in 6:
		s += chars[randi() % chars.length()]
	return s


func _start(seed_str: String, foes: int, strength: int, mix: bool, size := 0, rv := true, opts := {}) -> bool:
	if not sim.new_game(seed_str, foes, strength, mix, size, rv, opts):
		return false
	_after_world_change()
	var hq0 := sim.human().hq
	view.center_on(Vector2(hq0.x + 0.5, hq0.y + 0.5))
	view.zoom = 32.0
	return true


func _after_world_change() -> void:
	view.sim = sim
	_rebuild_feature_ui()
	minimap.reset()
	view.reset_world()
	view.place_type = ""
	view.sel_id = 0
	view.sel_tile = -1
	sel_res = ""
	_update_dip_button()
	end_panel.visible = false
	acc = 0.0
	autosave_t = 0.0
	rp_hist.clear()
	log_dirty = true
	_refresh_all()


func _on_end(win: bool) -> void:
	paused = true
	end_title.text = "Victory" if win else "Defeat"
	var m := int(sim.time) / 60
	var last := String(sim.logs[-1][1]) if sim.logs.size() > 0 else ""
	if "Industrial Revolution" in last:
		end_text.text = ("Your realm reached the Industrial Revolution first, after %d minutes." if win else last + " (%d minutes)") % m
	else:
		end_text.text = ("Every rival realm has fallen. Your reign took %d minutes." if win else "Your headquarters was captured after %d minutes.") % m
	end_panel.visible = true


func _toggle_pause() -> void:
	if sim.over or setup.visible:
		return
	paused = not paused
	btn_pause.text = "Resume" if paused else "Pause"


func _set_speed(s: float) -> void:
	speed = s
	for k in speed_btns:
		speed_btns[k].button_pressed = float(k) == s


func _set_cat(c: String) -> void:
	cat = c
	_rebuild_build_list()


func _rebuild_build_list() -> void:
	for ch in build_grid.get_children():
		ch.queue_free()
	build_buttons.clear()
	tool_buttons.clear()
	if cat == "mil":
		var kb := _button("Soldier kinds\nwho beats whom", _open_soldier_kinds)
		kb.custom_minimum_size = Vector2(176, 52)
		kb.add_theme_font_size_override("font_size", 13)
		kb.tooltip_text = "The six kinds of soldier, what each does and which beats which."
		build_grid.add_child(kb)
	# the road tools, Auto roads and the features' tools (scouts, geologists) are on the toolbar
	var p0: Sim.Player = null if sim.players.is_empty() else sim.human()
	_list_techs = p0.techs.size() if p0 != null else -1
	var hidden := 0
	for id in GameData.bld:
		var d: Dictionary = GameData.bld[id]
		if String(d.get("cat", "")) != cat or not sim.bld_enabled(id):
			continue
		# buildings not yet unlocked by research stay hidden (the research window shows what's to come)
		if p0 != null and d.has("tech") and not p0.techs.has(d.tech):
			hidden += 1
			continue
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.text = "%s\n%s" % [String(d.name), GameData.cost_text(d.get("cost", {}))]
		b.icon = Tex.get_tex(GameData.bld_tex_id(id))
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 40)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(176, 52)
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = _bld_tooltip(id)
		b.pressed.connect(_pick_build.bind(id))
		build_grid.add_child(b)
		build_buttons[id] = b
	_refresh_build()
	if hidden > 0:
		var note := _label("%d more to unlock by research (R)" % hidden, 12, DIM)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(176, 0)
		build_grid.add_child(note)


func _bld_tooltip(id: String) -> String:
	var d: Dictionary = GameData.bld[id]
	var sz := sim.size_of(id)
	var lines := [String(d.name), String(d.get("info", "")), "Size: %s (%d tile%s, a free tile all round%s)" % [String(Sim.SIZE_NAMES[sz]), (Sim.PLOTS[sz] as Array).size(), "" if (Sim.PLOTS[sz] as Array).size() == 1 else "s", "; flat ground, entrance south" if sz == "large" else ("; entrance south, east or west" if sz == "medium" else "")]]
	if d.has("in"):
		lines.append("Uses: " + ", ".join((d["in"] as Dictionary).keys().map(func(k): return "%d %s" % [int(d["in"][k]), GameData.res_name(k).to_lower()])))
	if d.has("out"):
		lines.append("Makes: " + ", ".join((d.out as Dictionary).keys().map(func(k): return "%d %s" % [int(d.out[k]), GameData.res_name(k).to_lower()])))
	if d.has("cycle"):
		lines.append("Cycle: %d s, worker: %s" % [int(d.cycle), String(d.get("worker", "none"))])
	return "\n".join(lines)


func _pick_build(id: String) -> void:
	view.road_after = false
	view.place_type = "" if view.place_type == id else id
	if GameData.bld.has(view.place_type) and not sim.door_ok(view.place_type, view.door):
		view.door = 0
	view.road_start = Vector2i(-1, -1)
	view.sel_id = 0
	_refresh_build()
	_refresh_sel()


## The feature and tool entry for tool id ("@geologist", "@scout"...), looked up in every building
## group, since the toolbar shows them whatever group is open. Empty if no feature has it.
func _feature_tool(id: String) -> Array:
	for f: Feature in sim.features:
		for c in GameData.CATEGORIES:
			for tl in f.tools(String(c[0])):
				if tl[0] == id:
					return [f, tl]
	return []


func _cancel_place() -> void:
	view.road_after = false
	view.place_type = ""
	view.road_start = Vector2i(-1, -1)
	_refresh_build()


func _on_tile(t: Vector2i) -> void:
	if sim.over or setup.visible:
		return
	if view.place_type.begins_with("@"):
		_use_tool(t)
		_refresh_all()
		return
	if view.place_type != "":
		var ty := view.place_type
		var r := sim.place(ty, t.x, t.y, sim.human(), view.door, settings.auto_roads)
		if r != "":
			_show_hint(r, 2.5)
		else:
			sim.emit_log("Building a %s." % String(GameData.bld[ty].name).to_lower(), DIM, Vector2i(t.x, t.y))
			var short := sim.missing(sim.human(), GameData.bld[ty].get("cost", {}))
			if short != "":
				_show_hint("Not enough %s in store yet: the site waits until carriers can bring it." % GameData.res_name(short).to_lower(), 3.0)
			var nb := sim.bld_at(t.x, t.y)
			if not Input.is_key_pressed(KEY_SHIFT):
				view.place_type = ""
				# roads by hand: go straight on to lay this building's road, from its entrance
				if not settings.auto_roads and nb != null and not sim.connected(nb):
					view.place_type = "@road"
					view.road_start = t
					view.road_after = true
					_show_hint("Now lay its road: click where it should join your roads (Esc to leave it for later).", 4.0)
		_refresh_all()
		return
	var b := sim.bld_at(t.x, t.y)
	# with the fog of war, what can't be seen can't be picked
	var fog = sim.get_feature("fog")
	if fog != null and sim.inb(t.x, t.y):
		var ti := sim.idx(t.x, t.y)
		if b != null and b.p != 1 and not fog.visible_at(ti):
			b = null
		if not fog.explored_at(ti):
			view.sel_id = 0
			view.sel_tile = -1
			sel_res = ""
			_refresh_sel()
			return
	var cur: Sim.Bld = sim.by_id.get(view.sel_id)
	if cur != null and cur.p == 1 and sim.is_mil(cur) and b != null and b.p != 1 and sim.is_mil(b):
		var r2 := sim.launch_attack(cur, b)
		if r2 != "":
			_show_hint(r2, 2.5)
		_refresh_all()
		return
	view.sel_id = b.id if b != null else 0
	sel_res = ""
	view.sel_tile = -1
	if b == null and _tile_has_info(sim.idx(t.x, t.y)):
		view.sel_tile = sim.idx(t.x, t.y)
	_refresh_sel()


## The road and work-area tools from the "Roads & stores" tab and the info window.
func _use_tool(t: Vector2i) -> void:
	var me := sim.human()
	match view.place_type:
		"@road":
			if view.road_start.x < 0:
				var sb := sim.bld_at(t.x, t.y)
				var eb := sim.door_owner(t.x, t.y, 1)
				if sim.inb(t.x, t.y) and (sim.road[sim.idx(t.x, t.y)] == 1 or (sb != null and sb.p == 1)):
					view.road_start = t
				elif eb != null:
					# a click on a building's entrance flag starts its road from the building
					view.road_start = Vector2i(eb.x, eb.y)
				else:
					_show_hint("Start a road on one of your roads or buildings.", 2.5)
				return
			var joins := sim.inb(t.x, t.y) and (sim.road[sim.idx(t.x, t.y)] == 1 or sim.bld_at(t.x, t.y) != null or sim.door_owner(t.x, t.y, 1) != null)
			var r := sim.build_road(view.road_start.x, view.road_start.y, t.x, t.y, 1)
			if r != "":
				_show_hint(r, 2.5)
			elif view.road_after and joins:
				# the new building's road reached the network: done
				view.road_after = false
				view.place_type = ""
				view.road_start = Vector2i(-1, -1)
				_refresh_build()
				_show_hint("Road joined.", 1.5)
			else:
				view.road_start = t
		"@demolish":
			var bd := sim.bld_at(t.x, t.y)
			if bd == null or bd.p != 1:
				_show_hint("Click one of your buildings to demolish it.", 2.0)
			elif bd.ty == "hq":
				_show_hint("The headquarters cannot be demolished.", 2.0)
			else:
				_ask_demolish(bd)
		"@pave":
			var r2 := sim.pave_road(t.x, t.y, me)
			_show_hint(r2 if r2 != "" else "Road paved.", 2.0)
		"@unroad":
			var n := sim.remove_road(t.x, t.y, 1)
			_show_hint("Removed %d road tiles." % n if n > 0 else "Click one of your roads.", 2.0)
		"@work":
			var b: Sim.Bld = sim.by_id.get(view.sel_id)
			if b == null:
				_cancel_place()
				return
			var r3 := sim.set_work_area(b, t.x, t.y)
			if r3 != "":
				_show_hint(r3, 3.0)
			else:
				_show_hint("Work area moved.", 2.0)
				_cancel_place()
		_:
			# a feature's tool (from the toolbar, whichever building group is open)
			var ft := _feature_tool(view.place_type)
			if not ft.is_empty():
				_show_hint((ft[0] as Feature).use_tool(view.place_type, t), 3.0)
				return


func _show_hint(text: String, secs: float) -> void:
	hint.text = text
	hint.visible = true
	hint_t = secs


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if confirm_panel.visible:
		# while the question is open, only Enter (demolish) and Esc (keep it) do anything
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_do_demolish()
		elif event.keycode == KEY_ESCAPE:
			confirm_panel.visible = false
		return
	if (set_panel.visible or targets_panel.visible) and event.keycode != KEY_ESCAPE:
		return
	for fid in feature_ui:
		if (feature_ui[fid].keys as Dictionary).has(event.keycode) and not setup.visible:
			(feature_ui[fid].keys[event.keycode] as Callable).call()
			return
	if event.keycode == KEY_E and not setup.visible:
		log_ui.toggle()
		return
	if event.keycode == KEY_B and not setup.visible and not save_panel.visible:
		toolbar.toggle_sites()
		return
	if (setup.visible or save_panel.visible) and not (event.keycode in [KEY_ESCAPE, KEY_F9]):
		if not (save_panel.visible and event.keycode == KEY_ESCAPE):
			return
	match event.keycode:
		KEY_F5: _save_game("quicksave")
		KEY_F9: _load_game("quicksave")
		KEY_R:
			# while placing a building R turns its entrance; otherwise it opens research
			if view.place_type != "" and GameData.bld.has(view.place_type):
				# only the sides its size allows (a large building's entrance always faces south)
				var sides: Array = Sim.SIZE_DOORS.get(sim.size_of(view.place_type), [0])
				if sides.size() <= 1:
					_show_hint("A %s building's entrance always faces %s." % [String(Sim.SIZE_NAMES[sim.size_of(view.place_type)]).to_lower(), Sim.DOOR_NAMES[sides[0]]], 2.0)
				else:
					var k := maxi(0, sides.find(view.door))
					view.door = int(sides[(k + (sides.size() - 1 if event.shift_pressed else 1)) % sides.size()])
				view.queue_redraw()
			else:
				_open_tech()
		KEY_G: _open_diplomacy()
		KEY_F3:
			perf_label.visible = not perf_label.visible
			perf_t = 1.0
		KEY_F10: _open_settings()
		KEY_T: _open_targets()
		KEY_ESCAPE:
			if set_panel.visible: set_panel.visible = false
			elif targets_panel.visible: targets_panel.visible = false
			elif tex_panel.visible: tex_panel.visible = false
			elif tech_panel.visible: tech_panel.visible = false
			elif save_panel.visible: save_panel.visible = false
			elif dip_panel.visible: dip_panel.visible = false
			elif kinds_panel != null and kinds_panel.visible: kinds_panel.visible = false
			elif toolbar.popup != null and toolbar.popup.visible: toolbar.close_popup()
			else: _cancel_place(); _clear_selection()
		KEY_SPACE: _toggle_pause()
		KEY_PAGEUP, KEY_PAGEDOWN, KEY_P:
			var bp: Sim.Bld = sim.by_id.get(view.sel_id)
			if bp != null:
				if event.keycode == KEY_P:
					_set_prio(Sim.PRIO_NORMAL if bp.prio == Sim.PRIO_PAUSED else Sim.PRIO_PAUSED)
				else:
					_set_prio(clampi(bp.prio + (1 if event.keycode == KEY_PAGEUP else -1), Sim.PRIO_LOW, Sim.PRIO_HIGH))
		KEY_DELETE:
			var bd: Sim.Bld = sim.by_id.get(view.sel_id)
			if bd != null and bd.p == 1 and bd.ty != "hq":
				_ask_demolish(bd)
		KEY_1: _set_speed(1.0)
		KEY_2: _set_speed(2.0)
		KEY_3: _set_speed(4.0)
		KEY_4: _set_speed(8.0)
		KEY_EQUAL, KEY_KP_ADD:
			if tech_panel.visible: research_ui.tree.set_zoom(research_ui.tree.zoom * 1.25)
			else: view.zoom_at(view.size / 2.0, 1.15)
		KEY_MINUS, KEY_KP_SUBTRACT:
			if tech_panel.visible: research_ui.tree.set_zoom(research_ui.tree.zoom / 1.25)
			else: view.zoom_at(view.size / 2.0, 1.0 / 1.15)
		KEY_0, KEY_KP_0:
			if tech_panel.visible: research_ui.tree.fit()


func _process(delta: float) -> void:
	_hide_windows_under_panels()
	_place_sel_box()
	# floating windows keep their title bar (drawn above the window) below the top bar
	var min_y := int(top_bar.get_parent().size.y + 8 + 30)
	for w: Window in [log_ui.win]:
		if w != null and w.visible and w.position.y < min_y:
			w.position.y = min_y
	if not setup.visible and not (get_viewport().gui_get_focus_owner() is LineEdit):
		var mv := Vector2.ZERO
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): mv.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): mv.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): mv.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): mv.x += 1
		if mv != Vector2.ZERO:
			if tech_panel.visible:
				research_ui.tree.pan(mv * 700.0 * delta)
			else:
				view.pan(mv * 600.0 * delta / view.zoom)
	if not paused and not sim.over and not setup.visible and not save_panel.visible and not tech_panel.visible and not dip_panel.visible:
		autosave_t += delta * speed
		if autosave_t >= 300.0:
			autosave_t = 0.0
			_save_game("autosave", true)
		acc += delta * speed
		var n := 0
		while acc >= Sim.TICK and n < 80:
			sim.tick(Sim.TICK)
			acc -= Sim.TICK
			n += 1
		if n >= 80:
			acc = 0.0
	if sim.map_dirty:
		view.chunks.mark_all()
	if sim.changed_tiles.size() > 0:
		view.tiles_changed(sim.changed_tiles)
		minimap.tiles_changed(sim.changed_tiles)
		sim.changed_tiles.clear()
	if view.flash > 0.0:
		view.flash = maxf(0.0, view.flash - delta)
	view.queue_redraw()
	if perf_label.visible:
		perf_t += delta
		if perf_t >= 0.5:
			_update_perf()
	if hint_t > 0.0:
		hint_t -= delta
		if hint_t <= 0.0:
			hint.visible = false
	elif view.place_type.begins_with("@"):
		match view.place_type:
			"@demolish": hint.text = "Demolish: click one of your buildings (Esc to stop)"
			"@road": hint.text = "Build road: " + ("click where the road should go (Esc to stop)" if view.road_start.x >= 0 else "click one of your roads or buildings to start")
			"@pave": hint.text = "Pave road: click a road (1 stone per tile, up to 12 tiles)"
			"@unroad": hint.text = "Remove road: click a road to remove that stretch"
			"@work": hint.text = "Move work area: click its new centre"
			_:
				hint.text = "Click a spot on the map (Esc or right click to stop)"
				var ft := _feature_tool(view.place_type)
				if not ft.is_empty():
					hint.text = "%s: %s" % [String(ft[1][1]), String(ft[1][3])]
		hint.visible = true
	elif view.place_type != "":
		var why := sim.can_place(view.place_type, view.ghost.x, view.ghost.y, 1, view.door)
		var szn := String(Sim.SIZE_NAMES[sim.size_of(view.place_type)])
		hint.text = "%s (%s): %s   (entrance faces %s, R turns it; roads: %s)" % [String(GameData.bld[view.place_type].name), szn.to_lower(), why if why != "" else "click to build", Sim.DOOR_NAMES[view.door], "auto" if settings.auto_roads else "by hand"]
		hint.visible = true
	else:
		hint.visible = false
	ui_t += delta
	if ui_t > 0.3:
		ui_t = 0.0
		_refresh_all()


# ================================================================ refresh

func _refresh_all() -> void:
	if sim.w == 0:
		return
	var p := sim.human()
	for id in stock_labels:
		var v := int(p.stock.get(id, 0.0))
		var l: Label = stock_labels[id]
		var s := str(v)
		if l.text != s:
			l.text = s
		# amber: the stores are full of it, so the buildings that make it have stopped
		var full := v > 0 and float(p.stock.get(id, 0.0)) + sim.coming(p, id) >= sim.capacity(p, id) - 0.5
		l.modulate = Color(1, 1, 1, 0.45) if v == 0 else (Color(1.0, 0.68, 0.32) if full else Color.WHITE)
		var row := l.get_parent() as Control
		if not row.visible and v >= 1 and res_shown(id):
			row.visible = true      # a good you had never seen arrived (trade, plunder, an event)
	_refresh_folk()
	_refresh_research()
	_refresh_build()
	_dry_mines()
	_refresh_sel()
	_refresh_rivals()
	if log_dirty:
		log_dirty = false
		log_ui.refresh()
		if sim.logs.size() > 0 and "attacks your" in String(sim.logs[-1][1]):
			view.flash = 1.0
	var m := int(sim.time) / 60
	lbl_time.text = "%02d:%02d" % [m, int(sim.time) % 60]
	lbl_pop.text = "Pop %d / %d" % [sim.pop_total(p), sim.housing(p)]
	var alive := 0
	for q in sim.players:
		if q.ai and q.alive: alive += 1
	lbl_foes.text = "Rivals %d" % alive
	var bits := PackedStringArray()
	for f: Feature in sim.features:
		var tt := f.top_text(p)
		if tt != "":
			bits.append(tt)
		f.refresh_ui(self)
	lbl_feat.text = "  ".join(bits)
	lbl_feat.visible = not bits.is_empty()


func _refresh_folk() -> void:
	var p := sim.human()
	var t := ""
	t += "Peasants  [b]%d[/b] (%d at work)\n" % [p.peasant, p.used_peasant]
	t += "Artisans  [b]%d[/b] (%d at work)  content %d%%\n" % [p.artisan, p.used_artisan, roundi(float(p.sat.get("artisan", 0.0)) * 100)]
	t += "Nobles  [b]%d[/b]  content %d%%\n" % [p.noble, roundi(float(p.sat.get("noble", 0.0)) * 100)]
	t += "Soldiers  [b]%d[/b] (%d in HQ, %d veterans): %s\n" % [sim.soldiers(p), p.reserve, int(p.vets), Sim.mix_text(sim.soldier_mix(p))]
	t += "Housing  [b]%d / %d[/b]\n" % [sim.pop_total(p), sim.housing(p)]
	# specialists: workers level up only in their own trade
	var ts := sim.trade_summary(p)
	var parts := []
	var trs := ts.keys()
	trs.sort_custom(func(a, c): return int(ts[a].work) > int(ts[c].work))
	for tr: String in trs:
		var e: Dictionary = ts[tr]
		var bit := "%s %d" % [GameData.trade_plural(tr).capitalize(), int(e.work)]
		if int(e.work) > 0:
			bit += " lv %.1f" % (float(e.levels) / int(e.work))
		if int(e.idle) > 0:
			bit += " +%d idle" % int(e.idle)
		parts.append(bit)
	if not parts.is_empty():
		t += "Trades  %s\n" % ", ".join(parts)
	for f: Feature in sim.features:
		for line in f.panel_lines(p):
			t += line + "\n"
	var mules := [0, 0]
	var carts := [0, 0]
	for b in sim.realm_blds(p):
		if b.def.has("carriers") and b.state == "ready":
			var c: Dictionary = b.def.carriers
			var pair: Array = mules if String(c.kind) == "mule" else carts
			pair[0] += int(c.count) - b.busy if b.working else 0
			pair[1] += int(c.count) if b.working else 0
	t += "Carriers  [b]%d[/b] porters free%s%s\n" % [maxi(0, sim.porters_free(p)), (", %d of %d mules" % mules) if mules[1] > 0 else "", (", %d of %d carts" % carts) if carts[1] > 0 else ""]
	t += "Storage  [b]%d[/b] of each good\n" % int(sim.capacity(p, "planks"))
	if p.starve > 0:
		t += "Food  [color=#f0a090][b]Starving[/b][/color]"
	else:
		t += "Food  [b]%d[/b] in store" % int(sim.food_total(p))
	folk_label.text = t


func _refresh_build() -> void:
	if sim.players.is_empty():
		return
	var p := sim.human()
	# research unlocked something: show it
	if p.techs.size() != _list_techs:
		_rebuild_build_list()
		_refresh_stock_rows()
	for id in tool_buttons:
		(tool_buttons[id] as Button).set_pressed_no_signal(view.place_type == id)
	toolbar.refresh()
	for id in build_buttons:
		var b: Button = build_buttons[id]
		var d: Dictionary = GameData.bld[id]
		var locked: bool = d.has("tech") and not p.techs.has(d.tech)
		b.disabled = locked
		b.text = "%s\n%s" % [String(d.name), ("Needs " + GameData.tech_name(d.tech)) if locked else "%s · %s" % [GameData.cost_text(d.get("cost", {})), String(Sim.SIZE_NAMES[sim.size_of(id)]).to_lower()]]
		b.modulate = Color(1, 1, 1, 0.5) if (locked or sim.missing(p, d.get("cost", {})) != "") else Color.WHITE
		b.set_pressed_no_signal(view.place_type == id)


func _refresh_sel() -> void:
	for c in sel_actions.get_children():
		c.queue_free()
	var gb: Sim.Bld = sim.by_id.get(view.sel_id)
	if not (gb != null and gb.p == 1 and gb.ty != "hq" and gb.def.has("garrison") and gb.state == "ready") and _gar_sig != "":
		_gar_sig = ""
		for c in garrison_box.get_children():
			garrison_box.remove_child(c)
			c.queue_free()
	for c in prio_row.get_children():
		prio_row.remove_child(c)
		c.queue_free()
	var b: Sim.Bld = sim.by_id.get(view.sel_id)
	sel_box.visible = b != null or sel_res != "" or view.sel_tile >= 0
	if b == null and sel_res != "":
		sel_label.text = _res_info(sel_res)
		sel_actions.add_child(_label("Keep in stock:", 14, DIM))
		sel_actions.add_child(_target_ctrl(sel_res))
		return
	if b == null and view.sel_tile >= 0:
		sel_label.text = _tile_info(view.sel_tile)
		return
	if b == null:
		return
	var d := b.def
	var owner := sim.players[b.p - 1]
	var t := "[b]%s[/b]%s\n%s\n" % [String(d.name), "" if b.p == 1 else " of " + owner.name, sim.status(b)]
	if b.state == "build" and b.mat_total > 0:
		t += "Materials: %s\n[color=#9a9c88]Carriers bring them from the stores as the site needs them; nothing is set aside before.[/color]\n" % sim.materials_text(b)
	if b.reno_to >= 0 and b.mat_total > 0:
		t += "Renovation materials: %s\n" % sim.materials_text(b).replace("/" , " of ")
	if b.era >= 0:
		var my_age: int = owner.age
		t += "Style: %s%s\n" % [GameData.age_name(b.era), (" [color=#9a9c88](its realm is in the %s age: it can be renovated)[/color]" % GameData.age_name(my_age)) if b.era < my_age and b.reno_to < 0 and b.state == "ready" and b.p == 1 else ""]
		if (sim.reno_queue.get(b.p, []) as Array).has(b.id):
			t += "Waiting its turn to be renovated.\n"
	if b.state == "ready" and sim.is_mil(b) and sim.own_def(b) > 0:
		t += "Soldiers: %s\n" % Sim.mix_text(sim.military.mix_of(b))
		if b.p == 1:
			t += "[color=#9a9c88]Each kind has its strengths (Military tab: Soldier kinds). Defenders always send their best answer to each attacker.[/color]\n"
	if d.has("info"):
		t += "[color=#9a9c88]%s[/color]\n" % String(d.info)
	if d.has("in"):
		t += "Uses: %s\n" % ", ".join((d["in"] as Dictionary).keys().map(func(k): return "%d %s" % [int(d["in"][k]), GameData.res_name(k).to_lower()]))
	if d.has("out"):
		t += "Makes: %s\n" % ", ".join((d.out as Dictionary).keys().map(func(k): return "%d %s" % [int(d.out[k]), GameData.res_name(k).to_lower()]))
	# goods carried here from the stores for its work
	if d.has("in") and b.state == "ready" and b.p == 1:
		var parts := []
		var keys := {}
		for k in b.inbuf: keys[k] = true
		for k in b.incoming: keys[k] = true
		for k in keys:
			var way := int(b.incoming.get(k, 0))
			parts.append("%d %s%s" % [int(b.inbuf.get(k, 0)), GameData.res_name(k).to_lower(), (" (+%d on the way)" % way) if way > 0 else ""])
		t += "Here for its work: %s\n" % (", ".join(parts) if not parts.is_empty() else "nothing yet (carriers fetch it from the nearest store that has it)")
	# a store's own goods
	if sim.is_store(b) and b.p == 1 and b.state == "ready":
		var items := b.inv.keys().filter(func(k): return float(b.inv[k]) >= 1.0)
		items.sort_custom(func(x, y): return float(b.inv[x]) > float(b.inv[y]))
		var total := 0
		for k in items: total += int(b.inv[k])
		t += "In this store: [b]%d goods[/b]%s\n" % [total, (": " + ", ".join(items.map(func(k): return "%d %s" % [int(b.inv[k]), GameData.res_name(k).to_lower()]))) if not items.is_empty() else ""]
	# idle people waiting here
	if b.p == 1 and b.state == "ready":
		var av := sim.home_avail(sim.human())
		var here := []
		for cls in ["peasant", "artisan", "scout", "soldier"]:
			var n := int((av[cls] as Dictionary).get(b.id, 0))
			if n > 0:
				here.append("%d %s%s" % [n, cls, "" if n == 1 else "s"])
		var room := int(d.get("residence", 0))
		if not here.is_empty() or room > 0:
			t += "Waiting here: %s%s\n" % [", ".join(here) if not here.is_empty() else "nobody", (" (room for %d)" % room) if room > 0 else ""]
	if d.has("worker") and b.state == "ready" and String(d.worker) != "scout":
		var tr := GameData.trade(b.ty)
		if b.staffed:
			var lv := Sim.level(b.wxp, Sim.WORKER_XP)
			var rank := "master " if lv >= 5 else ("" if lv >= Sim.SPECIALIST else "apprentice ")
			t += "Worker: %s%s (%s), trade: %s%s\n" % [rank, GameData.trade_title(tr), String(d.worker), GameData.trade_name(tr), " [color=#e0b060](on his way here)[/color]" if b.worker == 1 else ""]
		else:
			t += "Worker: %s (missing)\n" % String(d.worker)
		var tool := sim.tool_of(b)
		if tool != "":
			t += "New workers need %s (%d in store)\n" % [GameData.res_name(tool).to_lower(), int(sim.human().stock.get(tool, 0.0))]
		if b.staffed and d.has("cycle"):
			t += _xp_line("Worker", b.wxp, Sim.WORKER_XP, "work cycles", roundi(Sim.LEVEL_BONUS * 100))
			t += "[color=#9a9c88]Experience counts only in %s work; idle %s are hired first.[/color]\n" % [GameData.trade_name(tr).to_lower(), GameData.trade_plural(tr)]
	if b.state == "ready" and sim.is_mil(b) and sim.own_def(b) > 0:
		t += _xp_line("Soldiers here", sim.players[b.p - 1].res_xp if b.ty == "hq" else b.sxp, Sim.SOLDIER_XP, "battle experience", 3)
	if b.p == 1 and sim.is_mil(b):
		t += "[color=#d8aa4a]Click an enemy military building within the dashed circle to attack with all but one soldier.[/color]\n"
	var waiting := 0
	for r in b.out_buf:
		waiting += int(b.out_buf[r])
	if waiting > 0:
		t += "Waiting for carriers: %d goods\n" % waiting
	if b.state == "ready" and b.cyc > 0.0 and not sim.is_store(b):
		var dist := sim.net_dist(b.p, sim.idx(b.x, b.y))
		t += "Road to the nearest store: %s\n" % ("none, build a road" if dist >= Sim.INF else "%d s walk" % roundi(dist))
	var wr := sim.work_radius(b)
	if wr > 0:
		var wc := sim.work_center(b)
		var moved := wc != Vector2i(b.x, b.y)
		t += "Work area: %d tiles across%s\n" % [wr * 2 + 1, (", moved %d tiles away (+%.1f s walking per cycle)" % [roundi(Vector2(wc.x - b.x, wc.y - b.y).length()), sim.walk_time(b)]) if moved else ", around the building"]
	for f: Feature in sim.features:
		for line in f.building_lines(b):
			t += line + "\n"
	if b.p == 1 and b.def.has("mine") and b.dry_t >= 0.0:
		if settings.demolish_dry_mines:
			t += "[color=#e0b060]Its vein has run dry: it will be demolished in %d s (switch this off in Settings).[/color]\n" % maxi(0, ceili(DRY_MINE_WAIT - (sim.time - b.dry_t)))
		else:
			t += "[color=#e0b060]Its vein has run dry: demolish it to get back 40%% of its cost.[/color]\n"
	if b.p == 1 and sim.has_priority(b):
		t += "Priority: [b]%s[/b]. %s\n" % [Sim.PRIO_NAMES[b.prio], PRIO_HELP[b.prio]]
	sel_label.text = t
	if b.p == 1 and b.ty != "hq" and b.def.has("garrison") and b.state == "ready":
		_garrison_ui(b)
	if b.p == 1 and sim.has_priority(b):
		prio_row.add_child(_label("Priority", 14, DIM))
		for pr in [Sim.PRIO_HIGH, Sim.PRIO_NORMAL, Sim.PRIO_LOW, Sim.PRIO_PAUSED]:
			var pb := _button(Sim.PRIO_NAMES[pr], _set_prio.bind(pr))
			pb.toggle_mode = true
			pb.set_pressed_no_signal(b.prio == pr)
			pb.tooltip_text = PRIO_HELP[pr]
			prio_row.add_child(pb)
	if b.p == 1 and wr > 0 and b.state == "ready":
		sel_actions.add_child(_button("Move work area", func():
			view.place_type = "@work"
			_refresh_build()))
		if b.work.x >= 0:
			sel_actions.add_child(_button("Reset work area", func():
				var bb: Sim.Bld = sim.by_id.get(view.sel_id)
				if bb:
					sim.set_work_area(bb, bb.x, bb.y)
					_refresh_sel()))
	if b.p == 1 and b.state == "ready":
		var why := sim.can_renovate(b)
		if why == "":
			var rb := _button("Renovate", func():
				var bb: Sim.Bld = sim.by_id.get(view.sel_id)
				if bb:
					var r := sim.renovate(bb)
					_show_hint(r if r != "" else ("Renovation starts: carriers bring half the building's materials." if bb.reno_to >= 0 else "Renovation queued: two run at a time."), 3.0)
					_refresh_sel())
			rb.tooltip_text = "Rebuild it in the %s style: half its building cost, carried here, and half its building time. Work stops meanwhile; the worker keeps his job." % GameData.age_name(sim.human().age)
			sel_actions.add_child(rb)
			var same := 0
			for x: Sim.Bld in sim.realm_blds(sim.human()):
				if x.ty == b.ty and sim.can_renovate(x) == "":
					same += 1
			if same > 1:
				sel_actions.add_child(_button("Renovate all %d" % same, func():
					var bb: Sim.Bld = sim.by_id.get(view.sel_id)
					if bb:
						_show_hint("%d %s queued for renovation; two at a time." % [sim.renovate_all(sim.human(), bb.ty), String(bb.def.name).to_lower()], 3.0)
						_refresh_sel()))
	if b.p == 1 and b.ty != "hq":
		sel_actions.add_child(_button("Demolish", func():
			var bb: Sim.Bld = sim.by_id.get(view.sel_id)
			if bb:
				_ask_demolish(bb)))


## What each priority does, shown in the building panel and as button tooltips.
const PRIO_HELP := {
	2: "Gets workers and builders first, carriers fetch its goods first, and it checks for missing goods twice as often.",
	1: "Works as usual.",
	0: "Gets workers and builders last, and leaves the last 6 of each input (12 food) for other buildings.",
	-1: "Stopped: its worker (or builder) goes back to the idle workers, keeping his skill.",
}


## Changes the selected building's priority (also bound to Page Up / Page Down and P).
func _set_prio(pr: int) -> void:
	var b: Sim.Bld = sim.by_id.get(view.sel_id)
	if b == null or b.p != 1 or not sim.has_priority(b):
		return
	sim.set_priority(b, pr)
	_show_hint("%s: priority %s." % [String(b.def.name), Sim.PRIO_NAMES[b.prio].to_lower()], 2.5)
	_refresh_sel()


func _refresh_rivals() -> void:
	var t := ""
	for q in sim.players:
		if not q.ai:
			continue
		var n := 0
		for b in sim.blds:
			if b.p == q.id: n += 1
		var name_s := "[color=#%s]■[/color] %s [color=#9a9c88]%s, level %d[/color]" % [q.color.to_html(false), q.name, q.pers, q.skill]
		if q.alive:
			t += "%s  %d buildings, %d soldiers\n" % [name_s, n, sim.soldiers(q)]
		else:
			t += "%s  [s]defeated[/s]\n" % name_s
	rivals_label.text = t


# ================================================================ experience, resource and tile info

func _clear_selection() -> void:
	view.sel_id = 0
	view.sel_tile = -1
	sel_res = ""
	_refresh_sel()


func _xp_line(who: String, xp: float, table: Array, unit: String, pct: int) -> String:
	var lv := Sim.level(xp, table)
	var nxt := "max level" if lv >= table.size() else "%d / %d %s to level %d" % [int(xp), int(table[lv]), unit, lv + 1]
	return "%s level [b]%d[/b] (%s), %+d%% %s\n" % [who, lv, nxt, (lv - 1) * pct, "win chance" if table == Sim.SOLDIER_XP else "speed"]


func _on_stock_click(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		sel_res = id
		view.sel_id = 0
		view.sel_tile = -1
		_refresh_sel()


func _res_info(id: String) -> String:
	var p := sim.human()
	var r: Dictionary = GameData.res_by_id.get(id, {})
	var t := "[b]%s[/b]\nIn store: [b]%d[/b] of %d room" % [GameData.res_name(id), int(p.stock.get(id, 0.0)), int(sim.capacity(p, id))]
	var on_way := int(sim.coming(p, id))
	if on_way > 0:
		t += ", %d more on the way" % on_way
	if float(p.stock.get(id, 0.0)) + on_way >= sim.capacity(p, id) - 0.5:
		t += "\n[color=#e0a050]Full: buildings that make it have stopped until some is used. Build a storehouse for more room.[/color]\n"
	else:
		t += "\n[color=#9a9c88]When the stores are full, buildings that make it stop (goods on the way count).[/color]\n"
	if r.has("food"):
		t += "Food: each one feeds %.1f people-meals\n" % float(r.food)
	t += "Worth about %.1f in trade\n" % GameData.res_value(id)
	var makers := []
	var users := []
	var costs := []
	for b in GameData.bld:
		var d: Dictionary = GameData.bld[b]
		var mine := 0
		for x in sim.blds:
			if x.p == 1 and x.ty == b:
				mine += 1
		var have := " (you have %d)" % mine if mine > 0 else ""
		if (d.get("out", {}) as Dictionary).has(id):
			makers.append("%s: %d every %d s%s" % [String(d.name), int(d.out[id]), int(d.get("cycle", 0)), have])
		elif d.has("makes_tools") and GameData.is_tool_res(id):
			makers.append("%s: %d tools every %d s, the kind most wanted%s" % [String(d.name), int(d.makes_tools), int(d.get("cycle", 0)), have])
		if (d.get("in", {}) as Dictionary).has(id):
			users.append("%s uses %d%s" % [String(d.name), int(d["in"][id]), have])
		if (d.get("cost", {}) as Dictionary).has(id):
			costs.append(String(d.name))
	if id in ["coal", "ore_iron", "ore_gold", "ore_copper", "stone"]:
		makers.append("mines and quarries draw it from veins on the map; click a deposit to see what is left")
	t += "Made by: %s\n" % ("; ".join(makers) if makers.size() > 0 else "nothing")
	if users.size() > 0:
		t += "Used by: %s\n" % "; ".join(users)
	if r.has("food"):
		t += "Eaten by everyone; miners eat it too\n"
	if r.has("tool"):
		var tr := String(r.tool)
		var waiting := int(p.tool_wait.get(id, 0))
		t += "Each new %s (%s) needs one; an idle specialist brings his own%s\n" % [GameData.trade_title(tr), GameData.trade_name(tr).to_lower(), (". [color=#f08a7a]%d building%s waiting for one[/color]" % [waiting, "s" if waiting != 1 else ""]) if waiting > 0 else ""]
	var tg := sim.target_of(p, id)
	t += "Production target: %s\n" % ("none (makes up to the store room)" if tg < 0 else "keep %d in store, then pause" % tg)
	if costs.size() > 0:
		t += "Needed to build: %s\n" % ", ".join(costs)
	for cls in GameData.needs:
		for key: String in GameData.needs[cls]:
			var opts := GameData.need_options(key)
			if id in opts:
				var others := []
				for o in opts:
					if o != id:
						others.append(GameData.res_name(o).to_lower())
				t += "Keeps %ss content%s\n" % [cls, "" if others.is_empty() else " (or " + " or ".join(others) + " instead)"]
	return t


func _tile_has_info(i: int) -> bool:
	return sim.deco[i] != 0 or (sim.ter[i] == Sim.MOUNT and sim.get_feature("geology") != null) or (sim.ore[i] != 0 and sim.vein_left(i) > 0 and sim.ore_known(1, i)) or (sim.ter[i] == Sim.WATER and sim.amt[i] > 0)


func _tile_info(i: int) -> String:
	var names := ["Water", "Beach", "Grassland", "Mountain"]
	var t := "[b]%s[/b] at %d, %d\n" % [names[sim.ter[i]], i % sim.w, i / sim.w]
	if sim.height.size() == sim.w * sim.h and sim.ter[i] != Sim.WATER:
		t += "Height: %d m" % (int(sim.height[i]) * 4)
		if sim.road[i] != 0:
			var sl := sim.road_slope(i, int(sim.road[i]))
			t += ". Road: %s%s" % [Sim.SLOPE_NAMES[sl], (" (carriers take %.1f times as long)" % float(Sim.SLOPE_MUL[sl])) if sl > 0 else ""]
		t += "\n"
	if sim.deco[i] == Sim.D_TREE:
		t += "A tree: one log for a woodcutter.\n"
	elif sim.deco[i] == Sim.D_ROCK:
		t += "Rocks: [b]%d[/b] stone left for a quarry.\n" % sim.amt[i]
	elif sim.deco[i] == Sim.D_CLAY:
		t += "Clay patch: [b]%d[/b] clay left for a clay pit.\n" % sim.amt[i]
	if sim.ter[i] == Sim.WATER and sim.amt[i] > 0:
		t += "Fishing ground: [b]%d[/b] fish left.\n" % sim.amt[i]
	if sim.ore[i] != 0 and sim.vein_left(i) > 0 and sim.ore_known(1, i):
		var v := sim.vein[i]
		var tiles: PackedInt32Array = sim.vein_tiles[v]
		var left := sim.vein_left(i)
		var per := float(left) / maxf(1.0, tiles.size())
		var word := "poor" if per < 15.0 else ("average" if per < 35.0 else "rich")
		var kind := String(GameData.ORE_NAMES.get(int(sim.ore[i]), "ore"))
		t += "%s vein: [b]%d[/b] units left across %d tiles, %s %s vein.\n" % [kind.capitalize(), left, tiles.size(), "an" if word == "average" else "a", word]
		var mine_ty := ""
		for b in GameData.bld:
			if int(GameData.bld[b].get("mine", 0)) == int(sim.ore[i]):
				mine_ty = String(GameData.bld[b].name)
		t += "[color=#9a9c88]%s[/color]\n" % ("Quarries cut granite from it into stone." if kind == "granite" else "Build %s %s on any tile of this vein; it draws from the whole vein." % ["an" if mine_ty.to_lower().begins_with("i") else "a", mine_ty.to_lower()])
	for f: Feature in sim.features:
		for line in f.tile_lines(i):
			t += line + "\n"
	var o := sim.owner[i]
	t += ("Your territory\n" if o == 1 else "Territory of %s\n" % sim.players[o - 1].name) if o != 0 else "Nobody's land\n"
	return t


# ================================================================ performance overlay (F3)

func _update_perf() -> void:
	var usec := 0
	for k in sim.perf:
		usec += int(sim.perf[k])
	var game_secs := sim.time - float(perf_last.time)
	var per := float(usec - int(perf_last.usec)) / 1000.0 / maxf(0.001, game_secs)
	perf_last = {"time": sim.time, "usec": usec}
	perf_t = 0.0
	perf_label.text = "%d fps · map drawing %.1f ms · simulation %.1f ms per game second · %d buildings · %d carriers on the road" % [Engine.get_frames_per_second(), (view.draw_usec + view.ground_usec) / 1000.0, per if game_secs > 0.0 else 0.0, sim.blds.size(), sim.trips.size()]


# ================================================================ entry points into the parts
## Other scripts (and mods) call these on the simulation as before; the work happens in the part.

func _build_confirm_panel() -> void:
	demolish_ui._build_confirm_panel()

func _ask_demolish(b: Sim.Bld) -> void:
	demolish_ui._ask_demolish(b)

func _do_demolish() -> void:
	demolish_ui._do_demolish()

func _on_diplomacy_changed() -> void:
	diplomacy_ui._on_diplomacy_changed()

func _update_dip_button() -> void:
	diplomacy_ui._update_dip_button()

func _build_diplomacy_panel() -> void:
	diplomacy_ui._build_diplomacy_panel()

func _open_diplomacy() -> void:
	diplomacy_ui._open_diplomacy()

func _fill_diplomacy() -> void:
	diplomacy_ui._fill_diplomacy()

func _dip_propose(who: int, kind: String) -> void:
	diplomacy_ui._dip_propose(who, kind)

func _trade_quote() -> void:
	diplomacy_ui._trade_quote()

func _trade_offer() -> void:
	diplomacy_ui._trade_offer()

func _refresh_research() -> void:
	research_ui._refresh_research()

func _build_tech_panel() -> void:
	research_ui._build_tech_panel()

func _open_tech() -> void:
	research_ui._open_tech()

func _build_save_panel() -> void:
	saves_ui._build_save_panel()

func _open_saves() -> void:
	saves_ui._open_saves()

func _save_game(slot: String, quiet := false) -> void:
	saves_ui._save_game(slot, quiet)

func _load_game(slot: String) -> void:
	saves_ui._load_game(slot)

func _build_settings_panel() -> void:
	settings_ui._build_settings_panel()

func _open_settings() -> void:
	settings_ui._open_settings()

func _apply_settings() -> void:
	settings_ui._apply_settings()

func _target_ctrl(id: String) -> HBoxContainer:
	return targets_ui._target_ctrl(id)

func _build_targets_panel() -> void:
	targets_ui._build_targets_panel()

func _open_targets() -> void:
	targets_ui._open_targets()

func _build_tex_panel() -> void:
	textures_ui._build_tex_panel()

func _open_textures() -> void:
	textures_ui._open_textures()

func _reload_textures() -> void:
	textures_ui._reload_textures()


# ================================================================ soldier kinds
var kinds_panel: Control


## A reference of the six kinds of soldier: what each does and what it beats.
func _open_soldier_kinds() -> void:
	if kinds_panel == null:
		kinds_panel = _overlay()
		var v := _body(kinds_panel)
		v.add_child(_label("Soldier kinds", 22, BRASS))
		var txt := _rich()
		txt.custom_minimum_size = Vector2(620, 0)
		txt.name = "KindsText"
		v.add_child(txt)
		v.add_child(_button("Close (Esc)", func(): kinds_panel.visible = false))
	var tx: RichTextLabel = kinds_panel.find_child("KindsText", true, false)
	var me := sim.human()
	var t := "Each age trains its own kind of soldier; your barracks train [b]%s[/b] now. Every age ahead makes a soldier about 15%% stronger, and some kinds beat others outright (+12%% a duel).\n\n" % Sim.soldier_plural(me.age)
	var rows := [
		["Legionaries", "Roman", "Shield wall: hold a gate well.", "spearmen", "pikemen"],
		["Spearmen", "Early Medieval", "Cheap and quick to train (barracks 30% faster).", "-", "men-at-arms"],
		["Men-at-arms", "High Medieval", "Heavy armour: half the blows that would fell them don't (but pikes and bullets go through).", "spearmen, legionaries", "pikemen"],
		["Pikemen", "Renaissance", "Long reach: strike first, strong in defence.", "men-at-arms, legionaries", "musketeers"],
		["Musketeers", "Enlightenment", "Fire a volley or two (4 tiles, 6 s reload) before the melee; poor hand to hand.", "pikemen", "riflemen"],
		["Riflemen", "Industrial", "Fire again and again (7 tiles, 2.5 s reload).", "every older kind", "-"],
	]
	for r in rows:
		t += "[b][color=#d8aa4a]%s[/color][/b] (%s): %s\n   Beat: %s.  Beaten by: %s.\n" % r
	t += "\nMarching out, the best soldiers go first and the oldest stay to hold the building. At a gate the defenders always send their best answer to each attacker. Guns fire on the way in, and defenders with guns fire back.\n\nYour soldiers: %s." % Sim.mix_text(sim.soldier_mix(me))
	tx.text = t
	kinds_panel.visible = true


## After a save is loaded: game features added to the game since that save was made (fog of war,
## geologists, wildlife and so on, for an older save) are switched on if they are on in Settings, so
## their buildings and tools show. Features the save already had keep the choice made for that game.
## Saves from before build 20 don't say which features existed; for those, every feature on in
## Settings is switched on.
func turn_on_new_features() -> void:
	var known = sim.loaded_known
	var added := []
	for fid in settings.enabled_features():
		if sim.feature_on(fid):
			continue
		if known != null and fid in known:
			continue
		sim.set_feature(fid, true)
		if sim.feature_on(fid):
			var f := sim.get_feature(fid)
			added.append(f.title)
	if not added.is_empty():
		sim.emit_log("Switched on for this game: %s (new since it was saved; switch them off under Settings > Game features)." % ", ".join(added), Color("d8aa4a"))


## The garrison settings of your military building b: how many soldiers, which kinds, and who stays
## home when it attacks.
func _garrison_ui(b: Sim.Bld) -> void:
	var p := sim.human()
	var cap := int(b.def.garrison)
	var want := sim.garrison_wanted(b)
	var rm := sim.rmix_of(p)
	var gm := sim.gmix_of(b)
	# rebuilt only when something it shows changes, so a menu that is open stays open
	var sig := "%d|%d|%s|%d|%s|%s|%d" % [b.id, b.want_n, str(b.want_kinds), b.keep_kind, str(rm), str(gm), p.age]
	if sig == _gar_sig:
		return
	_gar_sig = sig
	for c in garrison_box.get_children():
		garrison_box.remove_child(c)
		c.queue_free()
	garrison_box.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_child(_label("Soldiers wanted", 14, DIM))
	var minus := _button("-", func(): _set_want(b, want - 1))
	minus.disabled = want <= 1
	row.add_child(minus)
	var n := _label("%d of %d" % [want, cap], 15)
	n.custom_minimum_size = Vector2(60, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(n)
	var plus := _button("+", func(): _set_want(b, want + 1))
	plus.disabled = want >= cap
	row.add_child(plus)
	if b.want_n >= 0:
		row.add_child(_button("Full", func(): _set_want(b, -1)))
	garrison_box.add_child(row)
	var row2 := HBoxContainer.new()
	var kl := _label("Kinds that may serve here", 14, DIM)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(kl)
	if not b.want_kinds.is_empty():
		row2.add_child(_button("Any", func():
			b.want_kinds = []
			sim.mil_fill(sim.human())
			_refresh_sel()))
	garrison_box.add_child(row2)
	var grid := GridContainer.new()
	grid.columns = 2
	for k in 6:
		var tb := Button.new()
		tb.focus_mode = Control.FOCUS_NONE
		tb.toggle_mode = true
		tb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tb.custom_minimum_size = Vector2(190, 0)
		tb.add_theme_font_size_override("font_size", 13)
		var at := AtlasTexture.new()
		at.atlas = Tex.get_tex("unit_soldier_e%d" % k)
		at.region = Tex.frame_rect("unit_soldier_e%d" % k, 0)
		tb.icon = at
		tb.add_theme_constant_override("icon_max_width", 22)
		var here := int(gm[k])
		var trainable := k <= p.age or int(rm[k]) > 0 or here > 0
		var info := ("%d at headquarters" % int(rm[k])) + ((", %d here" % here) if here > 0 else "")
		tb.text = "%s\n%s" % [Sim.soldier_plural(k).capitalize(), info if trainable else "not yet (%s age)" % GameData.age_name(k)]
		var ok := sim.kind_allowed(b, k)
		tb.set_pressed_no_signal(ok)
		# allowed kinds in gold, the others faded
		tb.add_theme_color_override("font_pressed_color", BRASS)
		tb.add_theme_color_override("font_hover_pressed_color", BRASS)
		if not ok:
			tb.modulate = Color(1, 1, 1, 0.55)
		tb.disabled = not trainable
		tb.tooltip_text = "Untick to keep %s out of this building: they are swapped for an allowed kind as soon as headquarters has one." % Sim.soldier_plural(k)
		var kk := k
		tb.toggled.connect(func(on):
			if b.want_kinds.is_empty():
				b.want_kinds = [true, true, true, true, true, true]
			b.want_kinds[kk] = on
			if not b.want_kinds.has(true):
				b.want_kinds[kk] = true       # at least one kind must be allowed
				_show_hint("At least one kind must be allowed.", 2.0)
			if not b.want_kinds.has(false):
				b.want_kinds = []
			_click()
			if sim.mil_fill(sim.human()):
				sim.recompute_territory()
			_refresh_sel())
		grid.add_child(tb)
	garrison_box.add_child(grid)
	var row3 := HBoxContainer.new()
	row3.add_child(_label("Stays home when it attacks", 14, DIM))
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_item("The oldest kind", 0)
	for k in 6:
		ob.add_item(Sim.soldier_name(k).capitalize(), k + 1)
	ob.select(b.keep_kind + 1)
	ob.tooltip_text = "When this building attacks, all but one soldier march. This picks who stays to hold it (if one of that kind is here)."
	ob.item_selected.connect(func(i):
		b.keep_kind = i - 1
		_gar_sig = "-"
		_click())
	row3.add_child(ob)
	garrison_box.add_child(row3)
	garrison_box.add_child(_label("Extra soldiers go back to headquarters; missing ones come from there, newest allowed kind first.", 12, DIM))
	(garrison_box.get_child(garrison_box.get_child_count() - 1) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _set_want(b: Sim.Bld, n: int) -> void:
	b.want_n = -1 if n < 0 or n >= int(b.def.garrison) else maxi(1, n)
	if sim.mil_fill(sim.human()):
		sim.recompute_territory()
	_refresh_sel()


## Your mines whose vein has run dry: a warning first, then (if the option is on) they are demolished
## DRY_MINE_WAIT seconds later, giving back 40% of their cost.
func _dry_mines() -> void:
	if sim.players.is_empty() or sim.over:
		return
	for b: Sim.Bld in sim.blds.duplicate():
		if b.p != 1 or not b.def.has("mine") or b.state != "ready":
			continue
		if b.msg != "Deposit exhausted":
			b.dry_t = -1.0
			continue
		if b.dry_t < 0.0:
			b.dry_t = sim.time
			if settings.demolish_dry_mines:
				sim.emit_log("Your %s has run dry. It will be demolished in %d s, giving back 40%% of its cost (switch this off in Settings)." % [String(b.def.name).to_lower(), DRY_MINE_WAIT], Color("e0b060"))
			else:
				sim.emit_log("Your %s has run dry and stands idle. Demolish it to get back 40%% of its cost." % String(b.def.name).to_lower(), Color("e0b060"))
		elif settings.demolish_dry_mines and sim.time - b.dry_t >= DRY_MINE_WAIT:
			var back := []
			var cost: Dictionary = b.def.get("cost", {})
			for k in cost:
				var n := int(floorf(float(cost[k]) * 0.4))
				if n > 0: back.append("%d %s" % [n, GameData.res_name(k).to_lower()])
			sim.emit_log("The dry %s was demolished%s." % [String(b.def.name).to_lower(), (": got back " + ", ".join(back)) if not back.is_empty() else ""], Color("e0b060"))
			if view.sel_id == b.id:
				view.sel_id = 0
			sim.demolish(b)
