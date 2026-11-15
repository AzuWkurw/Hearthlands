class_name UiEditor
extends RefCounted
## The map editor: opened from the new-game screen. It starts from the map of the seed and size chosen
## there, without any realm on it. Its panel has five tabs:
## - Paint: tools (brush, fill bucket, smoothing, rivers with fords, copy and paste turned or mirrored)
##   and what they paint: ground, trees/rocks/clay, ore and its amount, climate, animals, ruins and
##   bandit camps. Brushes are square or round, and can paint mirrored (left|right, top|bottom, four
##   ways, turned) for fair maps. Every stroke can be undone (Ctrl+Z) and redone (Ctrl+Y).
## - Map: open a saved map, make a new one from a seed with the landscape settings, name, save, play,
##   export.
## - Starts: move, add and remove the headquarters' places (start 1 is yours), and set each one up: a
##   name, the rival's personality and strength, more or fewer goods, extra soldiers.
## - Mission: goals, a story and a deadline, saved to your missions and played on this map.
## - Check: what lies around each start (trees, stone, ore, fish, open land), so the starts are fair.
## Maps are saved as JSON in the "maps" folder of the game's data folder (user://maps).

const MAP_DIR := "user://maps"
const TABS := ["Paint", "Map", "Starts", "Mission", "Check"]
const TOOLS := [
	["brush", "Brush", "Paints under the brush; drag to paint a stroke."],
	["fill", "Fill", "Fills the patch joined to where you click: the same ground (and for trees, rocks and clay the same things on it; for climate the whole piece of land)."],
	["smooth", "Smooth", "Each tile under the brush takes the ground most of its neighbours have: jagged coasts and specks of land round off."],
	["river", "River", "Drag from where the river starts to where it ends. A ford of beach crosses it now and then, so people can get over."],
	["copy", "Copy", "Drag over an area to copy its ground, things, ore and climate."],
	["paste", "Paste", "Click where the copied area's top-left corner goes. Turn or mirror it first with the buttons below."],
]
## [name, what it paints, value]. The first twenty keep their places (tests and tools refer to them).
const BRUSHES := [
	["Water", "ter", Sim.WATER], ["Beach", "ter", Sim.BEACH], ["Grass", "ter", Sim.GRASS], ["Mountain", "ter", Sim.MOUNT],
	["Trees", "deco", 1], ["Rocks", "deco", 2], ["Clay", "deco", 3], ["Clear", "deco", 0],
	["Coal", "ore", 1], ["Iron", "ore", 2], ["Gold", "ore", 3], ["Granite", "ore", 4], ["Copper", "ore", 5], ["No ore", "ore", 0],
	["Set ore amount", "amount", 0],
	["Deer", "animal", "deer"], ["Boar", "animal", "boar"], ["Hare", "animal", "hare"], ["Wolf", "animal", "wolf"], ["No animals", "animal", ""],
	["Game decides", "climate", 0], ["Temperate", "climate", 1], ["Taiga", "climate", 2], ["Steppe", "climate", 3], ["Wetland", "climate", 4],
	["Ruins", "place", "ruins"], ["Bandit camp", "place", "bandits"], ["Remove place", "place", ""],
	["Sulfur", "ore", 6], ["Lead", "ore", 7], ["Tin", "ore", 8],
]
## The brushes in the order the panel shows them: sulfur and lead (added in build 58) and tin (build 65) next to the other
## ores, before "No ore".
static func _brush_order() -> Array:
	var out := []
	for k in BRUSHES.size():
		if String(BRUSHES[k][0]) == "No ore":
			for j in BRUSHES.size():
				if BRUSHES[j][1] == "ore" and int(BRUSHES[j][2]) > 5: out.append(j)
		if not (BRUSHES[k][1] == "ore" and int(BRUSHES[k][2]) > 5):
			out.append(k)
	return out


const GROUPS := [["Ground", ["ter"]], ["Things on it", ["deco"]], ["Ore", ["ore", "amount"]], ["Climate", ["climate"]],
	["Animals", ["animal"]], ["Places", ["place"]]]
const AMOUNT_NAMES := ["Poor", "Normal", "Rich", "Very rich"]
const SIZES := [1, 3, 5, 9, 15]
const FORDS := [["No fords", 100000], ["Fords often", 9], ["Fords now and then", 14], ["Few fords", 22]]
const UNDO_MAX := 60
const GOAL_KINDS := [["build", "Build"], ["pop", "People"], ["soldiers", "Soldiers"], ["stock", "Goods in store"],
	["tech", "Study"], ["land", "Land"], ["trades", "Trades"], ["defeat", "Defeat rivals"]]

var main: Main
var win: Window
var body: VBoxContainer
var open := false
var tab := "Paint"
var tool := "brush"
var brush := 2          # index in BRUSHES
var size := 3           # brush width in tiles
var round_brush := false
var mirror := "off"     # see EditorTools.MIRRORS
var ford_k := 2         # index in FORDS
var moving := -1        # a start being moved (its index), or -1
var starts: Array = []  # Vector2i
var setup: Array = []   # per start: {} or {name, pers, skill, goods, soldiers}
var biome := PackedByteArray()  # per tile: 0 the game decides, 1 + climate
var map_name := "my map"
var name_edit: LineEdit
var _touched := {}
var ore_amt := 1        # index in WorldGen.ORE_AMOUNTS for the ore brushes
var animals: Array = [] # [kind, x, y] placed on the map (none: the game puts them at random)
var show_climate := false
var gen_seed := ""      # the new-map settings
var gen_size := 128
var gen_starts := 4
var gen := WorldGen.GEN_DEFAULTS.duplicate()
var _show_gen := false  # the new-map settings are open
# undo: one record per stroke: {tiles: {tile: [ter, deco, amt, ore, biome] before}, starts, animals, places}
var _undo: Array = []
var _redo: Array = []
var _stroke := {}
var _ground_moved := false
var _a := Vector2i(-1, -1)     # where a river or a copy drag began
var clip := {}                 # the copied area (EditorTools.cut)
var mission := {}              # the mission being written
var _goal_kind := 0
var _goal_param := 0
var _goal_n := 1
var _fair_r := 15


func _init(p_owner: Main) -> void:
	main = p_owner


func build() -> void:
	win = Window.new()
	win.title = "Map editor"
	win.transient = true
	win.wrap_controls = true
	win.position = Vector2i(12, 84)
	win.size = Vector2i(330, 520)
	win.theme = UiLog.window_theme()
	win.visible = false
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", main._panel_style(0.94))
	win.add_child(bg)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bg.add_child(sc)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	win.close_requested.connect(close)
	# Ctrl+Z and Ctrl+Y work with the panel focused too (not while typing in a field)
	win.window_input.connect(func(e: InputEvent):
		if e is InputEventKey and e.pressed and not e.echo and e.ctrl_pressed and (e.keycode == KEY_Z or e.keycode == KEY_Y):
			if win.gui_get_focus_owner() is LineEdit or win.gui_get_focus_owner() is TextEdit:
				return
			if e.keycode == KEY_Y or e.shift_pressed: redo()
			else: undo()
			win.set_input_as_handled())
	main.add_child(win)
	main.view.paint.connect(_paint)
	main.view.paint_done.connect(_paint_done)


## Opens the editor on the map of this seed and size (with room for n realms), made with the landscape
## settings params (see WorldGen.GEN_DEFAULTS; empty: the usual).
func start(seed_str: String, n: int, map_size: int, params := {}) -> bool:
	var sim: Sim = main.sim
	if not sim.new_game(seed_str, maxi(1, n - 1), 5, false, map_size, false, {"features": [], "gen": params}):
		return false
	gen_seed = seed_str
	gen_size = sim.w
	gen_starts = n
	starts = []
	animals = []
	setup = []
	sim.places = []
	for p in sim.players:
		starts.append(p.start)
		setup.append({})
	biome = PackedByteArray()
	biome.resize(sim.w * sim.h)
	map_name = "map " + seed_str
	_begin_editing()
	return true


## Opens a saved map file for editing: its ground, ore (with the amounts painted), climate, starts and
## their setup, animals and places.
func load_file(path: String) -> String:
	var m := WorldGen.load_map(path)
	if m.is_empty():
		return "That map could not be read."
	var sim: Sim = main.sim
	# a world of the right size first, then the map's own ground over it
	if not sim.new_game(String(m.seed), 1, 5, false, int(m.w), false, {"features": []}):
		return "That map is too small to open."
	sim.ter = (m.ter as PackedByteArray).duplicate()
	sim.deco = (m.deco as PackedByteArray).duplicate()
	sim.amt = (m.amt as PackedByteArray).duplicate()
	sim.ore = (m.ore as PackedByteArray).duplicate()
	sim.shade = (m.shade as PackedByteArray).duplicate()
	sim.height = WorldGen.heights(sim.seed_str, sim.ter, sim.w, sim.h)
	_rejoin_veins()
	starts = (m.starts as Array).duplicate()
	animals = (m.get("animals", []) as Array).duplicate(true)
	setup = (m.get("setup", []) as Array).duplicate(true)
	setup.resize(starts.size())
	for k in setup.size():
		if not (setup[k] is Dictionary):
			setup[k] = {}
	sim.places = []
	for pl in m.get("places", []):
		sim.places.append(Places.make(String(pl[0]), int(pl[1]), int(pl[2])))
	biome = (m.get("biome", PackedByteArray()) as PackedByteArray).duplicate()
	if biome.size() != sim.w * sim.h:
		biome = PackedByteArray()
		biome.resize(sim.w * sim.h)
	map_name = String(m.get("name", path.get_file().get_basename()))
	gen_seed = sim.seed_str
	gen_size = sim.w
	gen_starts = starts.size()
	_begin_editing()
	return ""


## Every map file there is to open: yours (user://maps) and the game's own (res://maps).
static func map_files() -> Array:
	var out := []
	for dir in [MAP_DIR, "res://maps"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".json"):
				out.append(dir + "/" + f)
	out.sort()
	return out


func _begin_editing() -> void:
	var sim: Sim = main.sim
	# an empty map: no realms, buildings, roads or land
	sim.blds.clear(); sim.by_id.clear(); sim.trips.clear(); sim.attacks.clear()
	sim.bmap.fill(0); sim.owner.fill(0); sim.road.fill(0); sim.plot.fill(0)
	for p in sim.players:
		p.hq = null
	main._after_world_change()
	main.guide_ui.box.visible = false
	var v := main.view
	v.editor = true
	v.editor_starts = starts
	v.editor_animals = animals
	v.editor_brush = size
	v.editor_round = round_brush
	v.editor_mirror = mirror
	v.editor_line = []
	v.editor_rect = Rect2i()
	v.editor_paste = Vector2i.ZERO
	v.editor_climate_load(biome)
	v.editor_climate = show_climate
	v.center_on(Vector2(sim.w / 2.0, sim.h / 2.0))
	v.zoom = 12.0
	main.setup.visible = false
	main.side_box.visible = false
	main.toolbar.bar.visible = false
	main.paused = true
	open = true
	_undo = []
	_redo = []
	mission = {}
	_fill()
	# in the side panel's place, full height
	var vs: Vector2 = main.get_viewport().get_visible_rect().size
	win.position = Vector2i(int(vs.x) - Main.SIDE_W, 0)
	win.size = Vector2i(Main.SIDE_W, int(vs.y))
	win.visible = true


func close() -> void:
	open = false
	win.visible = false
	var v := main.view
	v.editor = false
	v.editor_starts = []
	v.editor_animals = []
	v.editor_climate = false
	v.editor_line = []
	v.editor_rect = Rect2i()
	v.editor_paste = Vector2i.ZERO
	main.side_box.visible = true
	main.toolbar.bar.visible = true
	main.setup.visible = true
	main._fill_maps()


# --- The panel --------------------------------------------------------------------------------------------

func _fill() -> void:
	for c in body.get_children():
		c.queue_free()
	var tr_row := HBoxContainer.new()
	body.add_child(tr_row)
	for t in TABS:
		var b := main._button(t, func():
			tab = t
			moving = -1
			_fill())
		b.toggle_mode = true
		b.set_pressed_no_signal(t == tab)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tr_row.add_child(b)
	body.add_child(HSeparator.new())
	match tab:
		"Paint": _paint_tab()
		"Map": _map_tab()
		"Starts": _starts_tab()
		"Mission": _mission_tab()
		"Check": _check_tab()
	_sync_view()
	# the panel keeps its width (a wider tab before would have stretched it)
	if win.visible:
		win.size = Vector2i(Main.SIDE_W, win.size.y)


func _wrap(text: String, sz := 12, col := Main.DIM) -> Label:
	var l := main._label(text, sz, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(360, 0)
	return l


func _toggle(text: String, on: bool, cb: Callable) -> Button:
	var b := main._button(text, cb)
	b.toggle_mode = true
	b.set_pressed_no_signal(on)
	return b


func _paint_tab() -> void:
	var ur := HBoxContainer.new()
	body.add_child(ur)
	var ub := main._button(tr("Undo (%d)") % _undo.size(), undo)
	ub.disabled = _undo.is_empty()
	ub.tooltip_text = "Ctrl+Z"
	ur.add_child(ub)
	var rb := main._button(tr("Redo (%d)") % _redo.size(), redo)
	rb.disabled = _redo.is_empty()
	rb.tooltip_text = "Ctrl+Y"
	ur.add_child(rb)
	body.add_child(main._label("Tool", 14, Main.BRASS))
	var tf := HFlowContainer.new()
	body.add_child(tf)
	for t in TOOLS:
		var id: String = t[0]
		var b := _toggle(String(t[1]), tool == id and moving < 0, func():
			tool = id
			moving = -1
			_fill())
		b.tooltip_text = String(t[2])
		b.disabled = id == "paste" and clip.is_empty()
		tf.add_child(b)
	for t in TOOLS:
		if t[0] == tool:
			body.add_child(_wrap(String(t[2])))
	if tool == "brush" or tool == "fill":
		for g in GROUPS:
			# a fill paints ground, things, ore and climate (not animals or places)
			if tool == "fill" and ((g[1] as Array).has("animal") or (g[1] as Array).has("place")):
				continue
			body.add_child(main._label(String(g[0]), 13, Main.DIM))
			var gf := HFlowContainer.new()
			body.add_child(gf)
			for k in _brush_order():
				if not (g[1] as Array).has(BRUSHES[k][1]):
					continue
				var b := _toggle(String(BRUSHES[k][0]), k == brush and moving < 0, func():
					brush = k
					moving = -1
					if BRUSHES[k][1] == "climate":
						show_climate = true
					_fill())
				b.custom_minimum_size = Vector2(84, 0)
				gf.add_child(b)
		var what: String = BRUSHES[brush][1]
		if tool == "fill" and (what == "animal" or what == "place"):
			brush = 2
			what = "ter"
		if what == "ore" or what == "amount":
			var orr := HBoxContainer.new()
			body.add_child(orr)
			orr.add_child(main._label("Amount", 13, Main.DIM))
			for k in AMOUNT_NAMES.size():
				var ob := _toggle(AMOUNT_NAMES[k], k == ore_amt, func():
					ore_amt = k
					_fill())
				ob.tooltip_text = "Each ore tile painted holds %d units; a vein holds what its tiles hold together." % (int(WorldGen.ORE_AMOUNTS[k]) * WorldGen.ORE_UNIT)
				orr.add_child(ob)
		if what == "animal":
			body.add_child(_wrap(tr("%d animals placed. Click to place one; No animals clears them under the brush. With none placed the game puts animals at random.") % animals.size()))
		if what == "place":
			body.add_child(_wrap("Ruins: the first realm whose land reaches them finds planks, stone, gold and tools. Bandit camps: nobody builds within %d tiles, they steal from realms nearby until soldiers clear them (click the camp in the game), and hold gold and weapons." % Places.BLOCK_R))
		if what == "climate":
			body.add_child(_wrap("Climate decides the weather and the temperature (taiga is cold, steppe warm and dry, wetland rainy). Where you paint none, the game decides as on any map."))
	if tool == "brush" or tool == "smooth":
		var sr := HBoxContainer.new()
		body.add_child(sr)
		sr.add_child(main._label("Size", 13, Main.DIM))
		for s in SIZES:
			sr.add_child(_toggle("%d" % s, s == size, func():
				size = s
				_fill()))
		var rr := _toggle("Round", round_brush, func():
			round_brush = not round_brush
			_fill())
		rr.tooltip_text = "A round brush instead of a square one (sizes 5 and up)"
		sr.add_child(rr)
	if tool != "copy" and tool != "paste":
		var mr := HBoxContainer.new()
		body.add_child(mr)
		mr.add_child(main._label("Mirror", 13, Main.DIM))
		var mo := OptionButton.new()
		mo.focus_mode = Control.FOCUS_NONE
		for k in EditorTools.MIRRORS.size():
			mo.add_item(String(EditorTools.MIRROR_NAMES[k]))
			if EditorTools.MIRRORS[k] == mirror:
				mo.select(k)
		mo.tooltip_text = "Paint the same on the other side of the map too, so every start gets the same land."
		mo.item_selected.connect(func(i):
			mirror = EditorTools.MIRRORS[i]
			_sync_view())
		mr.add_child(mo)
	if tool == "river":
		var fr := HBoxContainer.new()
		body.add_child(fr)
		fr.add_child(main._label("Fords", 13, Main.DIM))
		var fo := OptionButton.new()
		fo.focus_mode = Control.FOCUS_NONE
		for k in FORDS.size():
			fo.add_item(String(FORDS[k][0]))
		fo.select(ford_k)
		fo.item_selected.connect(func(i): ford_k = i)
		fr.add_child(fo)
	if tool == "copy" or tool == "paste":
		if clip.is_empty():
			body.add_child(_wrap("Nothing copied yet."))
		else:
			body.add_child(main._label(tr("Copied: %d x %d tiles") % [int(clip.w), int(clip.h)], 13, Main.DIM))
			var cr := HBoxContainer.new()
			body.add_child(cr)
			cr.add_child(main._button("Turn", func():
				clip = EditorTools.turn(clip)
				_fill()))
			cr.add_child(main._button("Mirror ↔", func():
				clip = EditorTools.flip(clip, false)
				_fill()))
			cr.add_child(main._button("Mirror ↕", func():
				clip = EditorTools.flip(clip, true)
				_fill()))
	var cc := CheckBox.new()
	cc.text = tr("Show the climate")
	cc.button_pressed = show_climate
	cc.focus_mode = Control.FOCUS_NONE
	cc.toggled.connect(func(on):
		show_climate = on
		_sync_view())
	body.add_child(cc)
	body.add_child(_wrap("Left button paints, the middle button or a drag with the wheel moves the map. Ctrl+Z undoes a stroke, Ctrl+Y does it again."))


func _map_tab() -> void:
	body.add_child(main._label("Name", 14, Main.BRASS))
	name_edit = LineEdit.new()
	name_edit.text = map_name
	name_edit.text_changed.connect(func(t): map_name = t)
	body.add_child(name_edit)
	var br := HFlowContainer.new()
	body.add_child(br)
	br.add_child(main._button("Save", save))
	br.add_child(main._button("Play this map", play))
	br.add_child(main._button("Export to share", func():
		save()
		var mp := _map_path()
		var ms := SharePack.user_missions().filter(func(m): return String(m.get("map", "")).get_file() == mp.get_file())
		SharePack.dialog(main, true, func(path):
			var err := SharePack.export_pack(path, [mp], ms)
			main._show_hint(err if err != "" else "Exported to %s" % path, 4.0))))
	br.add_child(main._button("Close the editor", close))
	body.add_child(HSeparator.new())
	body.add_child(main._label("Open a map", 14, Main.BRASS))
	var lr := HBoxContainer.new()
	body.add_child(lr)
	var files := map_files()
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.clip_text = true
	if files.is_empty():
		ob.add_item("(no saved maps yet)")
		ob.disabled = true
	for f in files:
		ob.add_item(String(f).get_file().get_basename() + ("  (game)" if String(f).begins_with("res://") else ""))
		ob.set_item_metadata(ob.item_count - 1, f)
	lr.add_child(ob)
	var lb := main._button("Open", func():
		if ob.disabled:
			return
		var path := String(ob.get_item_metadata(ob.selected))
		main.confirm(tr("Open \"%s\"? Changes to the map in the editor that you have not saved are lost.") % path.get_file().get_basename(), "Open", func():
			var err := load_file(path)
			main._show_hint(err if err != "" else tr("Opened \"%s\".") % map_name, 3.0)))
	lb.disabled = files.is_empty()
	lr.add_child(lb)
	body.add_child(HSeparator.new())
	body.add_child(main._label("A new map", 14, Main.BRASS))
	_gen_section()
	body.add_child(_wrap("Maps are kept in %s." % ProjectSettings.globalize_path(MAP_DIR)))


## Generate: a new map from a seed, a size, a number of starts and the landscape settings.
func _gen_section() -> void:
	var g := GridContainer.new()
	g.columns = 2
	body.add_child(g)
	g.add_child(main._label("Seed", 13, Main.DIM))
	var sr := HBoxContainer.new()
	var se := LineEdit.new()
	se.text = gen_seed
	se.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	se.text_changed.connect(func(t): gen_seed = t)
	sr.add_child(se)
	sr.add_child(main._button("Dice", func():
		gen_seed = main._rand_seed()
		_fill()))
	g.add_child(sr)
	g.add_child(main._label("Size", 13, Main.DIM))
	var so := OptionButton.new()
	so.focus_mode = Control.FOCUS_NONE
	var best := 1e9
	for s in Main.SIZES:
		if int(s[1]) > 0:
			so.add_item(String(s[0]), int(s[1]))
			# the size nearest the map open now
			if absf(int(s[1]) - gen_size) < best:
				best = absf(int(s[1]) - gen_size)
				so.select(so.item_count - 1)
	gen_size = so.get_item_id(so.selected)
	so.item_selected.connect(func(i): gen_size = so.get_item_id(i))
	g.add_child(so)
	g.add_child(main._label("Starts", 13, Main.DIM))
	var sp := SpinBox.new()
	sp.min_value = 2; sp.max_value = 9; sp.value = gen_starts
	sp.value_changed.connect(func(v): gen_starts = int(v))
	g.add_child(sp)
	landscape_controls(main, g, gen)
	var br := HBoxContainer.new()
	body.add_child(br)
	br.add_child(main._button("Generate", func():
		main.confirm("Make a new map? The map in the editor is replaced; anything you have not saved is lost.", "Generate", func():
			var sd := gen_seed.strip_edges() if gen_seed.strip_edges() != "" else main._rand_seed()
			gen_seed = sd
			if not start(sd, gen_starts, gen_size, gen.duplicate()):
				main._show_hint("No map with room for that many starts came out of this. Try more land (less water), a bigger size or fewer starts.", 6.0))))
	br.add_child(main._button("Usual settings", func():
		gen = WorldGen.GEN_DEFAULTS.duplicate()
		_fill()))


## The landscape settings (shape and five sliders) as rows of a two-column grid, changing params in
## place. The new-game screen uses them too.
static func landscape_controls(m: Main, g: GridContainer, params: Dictionary) -> void:
	g.add_child(m._label("Shape", 13, Main.DIM))
	var sh := OptionButton.new()
	sh.focus_mode = Control.FOCUS_NONE
	for k in WorldGen.SHAPES:
		sh.add_item({"island": "Island (sea all round)", "continent": "Continent (land to the edges)", "lakes": "Lakes (mostly land)", "archipelago": "Archipelago (many islands)", "isles": "Isles (a realm on each island)"}[k])
		if String(params.shape) == k:
			sh.select(sh.item_count - 1)
	sh.item_selected.connect(func(i): params["shape"] = WorldGen.SHAPES[i])
	g.add_child(sh)
	for k in [["water", "Water"], ["mountains", "Mountains"], ["forests", "Forests"], ["ore", "Ore"], ["scale", "Landform size"]]:
		g.add_child(m._label(String(k[1]), 13, Main.DIM))
		var hs := HSlider.new()
		hs.min_value = 0.0; hs.max_value = 1.0; hs.step = 0.05
		hs.value = float(params[k[0]])
		hs.custom_minimum_size = Vector2(150, 0)
		hs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hs.tooltip_text = {"water": "How much sea and lake", "mountains": "How much mountain (where mines go)", "forests": "How much woodland", "ore": "How much of the mountains holds ore", "scale": "Small: many small lakes, hills and woods. Large: a few big ones."}[k[0]]
		var key: String = k[0]
		hs.value_changed.connect(func(v): params[key] = v)
		g.add_child(hs)


func _starts_tab() -> void:
	body.add_child(_wrap("Start 1 is yours; the others are the rivals' (as many as the game asks for, in order). Leave a field empty or on \"Game's\" to use the new-game screen's settings."))
	for k in starts.size():
		var s: Dictionary = setup[k] if k < setup.size() and setup[k] is Dictionary else {}
		var head := HBoxContainer.new()
		body.add_child(head)
		var sw := ColorRect.new()
		sw.color = Sim.PCOL[k % Sim.PCOL.size()]
		sw.custom_minimum_size = Vector2(14, 14)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(sw)
		head.add_child(main._label(tr("Start %d") % (k + 1) + (tr(" (you)") if k == 0 else ""), 14, Main.BRASS))
		var mv := _toggle("Move", moving == k, func():
			moving = k
			main._show_hint(tr("Click where start %d should be.") % (k + 1), 3.0)
			_fill())
		head.add_child(mv)
		head.add_child(main._button("Go", func():
			main.view.center_on(Vector2(starts[k]) + Vector2(0.5, 0.5))))
		var g := GridContainer.new()
		g.columns = 4
		body.add_child(g)
		g.add_child(main._label("Name", 12, Main.DIM))
		var ne := LineEdit.new()
		ne.text = String(s.get("name", ""))
		ne.placeholder_text = tr("(usual)")
		ne.custom_minimum_size = Vector2(110, 0)
		ne.text_changed.connect(func(t): _set_setup(k, "name", t.strip_edges()))
		g.add_child(ne)
		g.add_child(main._label("Goods", 12, Main.DIM))
		var go := OptionButton.new()
		go.focus_mode = Control.FOCUS_NONE
		var goods := [0.5, 1.0, 1.5, 2.0]
		for gv in goods:
			go.add_item("x %s" % str(gv))
		go.select(maxi(0, goods.find(float(s.get("goods", 1.0)))))
		go.tooltip_text = "The goods this realm starts with, times this"
		go.item_selected.connect(func(i): _set_setup(k, "goods", goods[i]))
		g.add_child(go)
		g.add_child(main._label("Soldiers", 12, Main.DIM))
		var so := SpinBox.new()
		so.min_value = 0; so.max_value = 30; so.value = int(s.get("soldiers", 0))
		so.tooltip_text = "Soldiers more than usual in the headquarters"
		so.value_changed.connect(func(v): _set_setup(k, "soldiers", int(v)))
		g.add_child(so)
		if k > 0:
			g.add_child(main._label("Strength", 12, Main.DIM))
			var st := OptionButton.new()
			st.focus_mode = Control.FOCUS_NONE
			st.add_item(tr("Game's"))
			for lv in range(1, 11):
				st.add_item("%d" % lv)
			st.select(clampi(int(s.get("skill", 0)), 0, 10))
			st.item_selected.connect(func(i): _set_setup(k, "skill", i))
			g.add_child(st)
			g.add_child(main._label("Manner", 12, Main.DIM))
			var po := OptionButton.new()
			po.focus_mode = Control.FOCUS_NONE
			var pers := ["", "builder", "balanced", "warlord"]
			for pv in pers:
				po.add_item(tr("Game's") if pv == "" else tr(String(pv).capitalize()))
			po.select(maxi(0, pers.find(String(s.get("pers", "")))))
			po.tooltip_text = "Builder: grows its economy. Warlord: builds an army early and attacks. Balanced: some of both."
			po.item_selected.connect(func(i): _set_setup(k, "pers", pers[i]))
			g.add_child(po)
	body.add_child(HSeparator.new())
	var ar := HBoxContainer.new()
	body.add_child(ar)
	ar.add_child(main._button("Add a start", func():
		if starts.size() < 9:
			starts.append(Vector2i(main.sim.w / 2, main.sim.h / 2))
			setup.append({})
			moving = starts.size() - 1
			main._show_hint(tr("Click where start %d should be.") % starts.size(), 3.0)
			_fill()))
	ar.add_child(main._button("Remove last", func():
		if starts.size() > 2:
			starts.pop_back()
			setup.resize(starts.size())
			moving = -1
			_fill()))
	body.add_child(_wrap("Starts need open grass around them."))


func _set_setup(k: int, key: String, v) -> void:
	while setup.size() <= k:
		setup.append({})
	var s: Dictionary = setup[k] if setup[k] is Dictionary else {}
	var usual := {"name": "", "goods": 1.0, "soldiers": 0, "skill": 0, "pers": ""}
	if v == usual.get(key):
		s.erase(key)
	else:
		s[key] = v
	setup[k] = s


func _goal_params(kind: String) -> Array:
	match kind:
		"build":
			var out := []
			for id in GameData.bld:
				if id != "hq":
					out.append([id, String(GameData.bld[id].get("name", id))])
			return out
		"stock":
			return GameData.resources.map(func(r): return [String(r.id), GameData.res_name(String(r.id))])
		"tech":
			var out2 := []
			for id in GameData.techs:
				out2.append([id, GameData.tech_name(id)])
			return out2
	return []


static func goal_text(g: Dictionary) -> String:
	var n := int(g.get("n", 1))
	match String(g.kind):
		"build": return "Build %d: %s" % [n, String(GameData.bld.get(String(g.ty), {}).get("name", g.ty)).to_lower()]
		"pop": return "Grow to %d people" % n
		"soldiers": return "Have %d soldiers" % n
		"stock": return "Store %d %s" % [n, GameData.res_name(String(g.res)).to_lower()]
		"tech": return "Study %s" % GameData.tech_name(String(g.id))
		"land": return "Hold %d tiles of land" % n
		"trades": return "Make %d trades" % n
		"defeat": return "Defeat every rival" if n <= 0 else "Defeat %d rival realm%s" % [n, "" if n == 1 else "s"]
	return ""


func _mission_tab() -> void:
	if mission.is_empty():
		mission = {"id": "", "name": map_name, "story": "", "foes": mini(2, starts.size() - 1), "strength": 5, "minutes": 0, "goals": []}
	# missions already written for this map
	var mine := SharePack.user_missions().filter(func(m): return String(m.get("map", "")).get_file() == _map_path().get_file())
	if not mine.is_empty():
		body.add_child(main._label("Missions on this map", 14, Main.BRASS))
		var mf := HFlowContainer.new()
		body.add_child(mf)
		for m in mine:
			mf.add_child(main._button(String(m.get("name", "?")), func():
				mission = (m as Dictionary).duplicate(true)
				_fill()))
		mf.add_child(main._button("A new one", func():
			mission = {}
			_fill()))
	body.add_child(main._label("Mission", 14, Main.BRASS))
	var g := GridContainer.new()
	g.columns = 2
	body.add_child(g)
	g.add_child(main._label("Name", 13, Main.DIM))
	var ne := LineEdit.new()
	ne.text = String(mission.name)
	ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ne.text_changed.connect(func(t): mission["name"] = t)
	g.add_child(ne)
	g.add_child(main._label("Rivals", 13, Main.DIM))
	var fs := SpinBox.new()
	fs.min_value = 1; fs.max_value = maxi(1, starts.size() - 1); fs.value = int(mission.foes)
	fs.value_changed.connect(func(v): mission["foes"] = int(v))
	g.add_child(fs)
	g.add_child(main._label("Their strength", 13, Main.DIM))
	var ss := SpinBox.new()
	ss.min_value = 1; ss.max_value = 10; ss.value = int(mission.strength)
	ss.value_changed.connect(func(v): mission["strength"] = int(v))
	g.add_child(ss)
	g.add_child(main._label("Minutes", 13, Main.DIM))
	var ms := SpinBox.new()
	ms.min_value = 0; ms.max_value = 600; ms.step = 5; ms.value = int(mission.minutes)
	ms.tooltip_text = "The deadline in game minutes (0: none)"
	ms.value_changed.connect(func(v): mission["minutes"] = int(v))
	g.add_child(ms)
	body.add_child(main._label("Story", 13, Main.DIM))
	var st := TextEdit.new()
	st.text = String(mission.story)
	st.custom_minimum_size = Vector2(0, 70)
	st.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	st.text_changed.connect(func(): mission["story"] = st.text)
	body.add_child(st)
	body.add_child(main._label("Goals", 14, Main.BRASS))
	var goals: Array = mission.goals
	if goals.is_empty():
		body.add_child(_wrap("No goals yet: add some below. All goals done wins the mission; the deadline passing first loses it."))
	for k in goals.size():
		var gr := HBoxContainer.new()
		body.add_child(gr)
		var gl := main._label("•  " + String(goals[k].get("text", "")), 13)
		gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gr.add_child(gl)
		gr.add_child(main._button("Remove", func():
			goals.remove_at(k)
			_fill()))
	# a new goal: its kind, what it is about, how many
	var ar := HBoxContainer.new()
	body.add_child(ar)
	var ko := OptionButton.new()
	ko.focus_mode = Control.FOCUS_NONE
	for gk in GOAL_KINDS:
		ko.add_item(String(gk[1]))
	ko.select(_goal_kind)
	ko.item_selected.connect(func(i):
		_goal_kind = i
		_goal_param = 0
		_fill())
	ar.add_child(ko)
	var kind: String = GOAL_KINDS[_goal_kind][0]
	var params := _goal_params(kind)
	if not params.is_empty():
		var po := OptionButton.new()
		po.focus_mode = Control.FOCUS_NONE
		po.custom_minimum_size = Vector2(130, 0)
		po.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		po.clip_text = true
		for p in params:
			po.add_item(String(p[1]))
		po.select(clampi(_goal_param, 0, params.size() - 1))
		po.item_selected.connect(func(i): _goal_param = i)
		ar.add_child(po)
	var ar2 := HBoxContainer.new()
	body.add_child(ar2)
	if kind != "tech":
		ar2.add_child(main._label("How many" if kind != "defeat" else "Rivals (0: all)", 13, Main.DIM))
		var ns := SpinBox.new()
		ns.min_value = 0 if kind == "defeat" else 1; ns.max_value = 100000; ns.value = _goal_n
		ns.tooltip_text = "0: every rival" if kind == "defeat" else ""
		ns.value_changed.connect(func(v): _goal_n = int(v))
		ar2.add_child(ns)
	ar2.add_child(main._button("Add the goal", func():
		var gd := {"kind": kind, "n": _goal_n if kind != "tech" else 1}
		if not params.is_empty():
			var key: String = {"build": "ty", "stock": "res", "tech": "id"}[kind]
			gd[key] = String(params[clampi(_goal_param, 0, params.size() - 1)][0])
		gd["text"] = goal_text(gd)
		goals.append(gd)
		_fill()))
	var br := HFlowContainer.new()
	body.add_child(br)
	br.add_child(main._button("Save the mission", func():
		var err := save_mission()
		main._show_hint(err if err != "" else tr("Saved the mission \"%s\" with the map. It is in the Missions list.") % String(mission.name), 4.0)))
	br.add_child(main._button("Play it", func():
		var err := save_mission()
		if err != "":
			main._show_hint(err, 4.0)
			return
		var ms2 := mission.duplicate(true)
		close()
		if not main.start_mission(ms2):
			main._show_hint("The mission could not be started: each start needs open grass around it.", 5.0)))


## Saves the map, then the mission (on this map) into your missions. "" when done, else why not.
func save_mission() -> String:
	if (mission.get("goals", []) as Array).is_empty():
		return "Give the mission at least one goal."
	if String(mission.get("name", "")).strip_edges() == "":
		return "Give the mission a name."
	var err := save(true)
	if err != "":
		return err
	if String(mission.get("id", "")) == "":
		mission["id"] = "user_" + String(mission.name).to_lower().validate_filename().replace(" ", "_") + "_%d" % (int(Time.get_unix_time_from_system()) % 100000)
	mission["map"] = _map_path()
	var all := SharePack.user_missions()
	var put := false
	for k in all.size():
		if String(all[k].get("id", "")) == String(mission.id):
			all[k] = mission.duplicate(true)
			put = true
	if not put:
		all.append(mission.duplicate(true))
	DirAccess.make_dir_recursive_absolute(SharePack.USER_MISSIONS.get_base_dir())
	var f := FileAccess.open(SharePack.USER_MISSIONS, FileAccess.WRITE)
	if f == null:
		return "The mission could not be saved."
	f.store_string(JSON.stringify(all, "\t"))
	f.close()
	return ""


func _check_tab() -> void:
	var sim: Sim = main.sim
	var rr := HBoxContainer.new()
	body.add_child(rr)
	rr.add_child(main._label("What lies within", 13, Main.DIM))
	for r in [10, 15, 20]:
		rr.add_child(_toggle(tr("%d tiles") % r, r == _fair_r, func():
			_fair_r = r
			_fill()))
	var fair := EditorTools.fairness(sim, starts, _fair_r)
	var cols := [["land", "Open land"], ["trees", "Trees"], ["stone", "Rocks"], ["clay", "Clay"], ["fish", "Fish"], ["mountain", "Mountain"],
		["coal", "Coal"], ["iron", "Iron"], ["gold", "Gold"], ["granite", "Granite"], ["copper", "Copper"], ["sulfur", "Sulfur"], ["lead", "Lead"], ["tin", "Tin"]]
	var g := GridContainer.new()
	g.columns = starts.size() + 1
	body.add_child(g)
	g.add_child(main._label("", 12))
	for k in starts.size():
		var l := main._label(tr("Start %d") % (k + 1), 12, Sim.PCOL[k % Sim.PCOL.size()].lightened(0.3))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.custom_minimum_size = Vector2(52, 0)
		g.add_child(l)
	var notes: Array = []
	for c in cols:
		g.add_child(main._label(String(c[1]), 12, Main.DIM))
		var hi := 0
		for e in fair:
			hi = maxi(hi, int(e[c[0]]))
		for k in starts.size():
			var v := int(fair[k][c[0]])
			var col := Color("e6e2d3")
			if hi > 0 and v < hi * 0.5:
				col = Color("ff8a6a")
				notes.append(tr("Start %d: %s %d, the richest start %d.") % [k + 1, tr(String(c[1])).to_lower(), v, hi])
			elif hi > 0 and v >= hi * 0.85:
				col = Color("a6d88a")
			var l := main._label("%d" % v, 12, col)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			g.add_child(l)
	# how near the nearest other start is
	g.add_child(main._label("Nearest start", 12, Main.DIM))
	var near_lo := 1e9
	for k in starts.size():
		var d := 1e9
		for j in starts.size():
			if j != k:
				d = minf(d, Vector2(starts[k] - starts[j]).length())
		near_lo = minf(near_lo, d)
		var l := main._label("%d" % roundi(d), 12, Color("ff8a6a") if d < 24 else Color("e6e2d3"))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		g.add_child(l)
	if near_lo < 24:
		notes.append(tr("Two starts are only %d tiles apart: those realms meet at once.") % roundi(near_lo))
	body.add_child(_wrap("Counted in tiles within %d tiles of each start. Green: about as much as the richest start; red: less than half of it." % _fair_r))
	if notes.is_empty():
		body.add_child(_wrap("The starts look fair.", 13, Color("a6d88a")))
	for n in notes:
		body.add_child(_wrap("•  " + String(n), 12, Color("ffb08a")))
	var bc := 0
	var rc := 0
	for pl: Dictionary in sim.places:
		if pl.kind == "bandits": bc += 1
		else: rc += 1
	var painted := 0
	for v in biome:
		if v > 0: painted += 1
	body.add_child(_wrap(tr("On the map: %d ruins, %d bandit camps, %d animals placed, climate painted on %d%% of it.") % [rc, bc, animals.size(), painted * 100 / maxi(1, biome.size())]))


# --- Saving and playing -----------------------------------------------------------------------------------

func _map_path() -> String:
	return MAP_DIR + "/" + map_name.strip_edges().validate_filename() + ".json"


## The map as it is now, in the map file shape (see WorldGen.load_map).
func current_map() -> Dictionary:
	var sim: Sim = main.sim
	var m := {"name": map_name, "w": sim.w, "h": sim.h, "seed": sim.seed_str, "starts": starts.duplicate(), "animals": animals.duplicate(true)}
	for k in WorldGen.MAP_KEYS:
		m[k] = (sim.get(k) as PackedByteArray).duplicate()
	m["places"] = sim.places.map(func(pl): return [String(pl.kind), int(pl.x), int(pl.y)])
	var su := setup.duplicate(true)
	su.resize(starts.size())
	var any := false
	for k in su.size():
		if not (su[k] is Dictionary):
			su[k] = {}
		if not (su[k] as Dictionary).is_empty():
			any = true
	m["setup"] = su if any else []
	for v in biome:
		if v > 0:
			m["biome"] = biome.duplicate()
			break
	return m


func save(quiet := false) -> String:
	var fn := map_name.strip_edges().validate_filename()
	if fn == "":
		main._show_hint("Give the map a name first.", 3.0)
		return "Give the map a name first."
	var err := WorldGen.save_map(current_map(), MAP_DIR + "/" + fn + ".json")
	if not quiet or err != "":
		main._show_hint(err if err != "" else "Saved the map \"%s\"." % fn, 3.0)
	return err


## Plays the map: you on start 1, rivals on the others (as many as the new-game screen asks, at most
## one per start), with the new-game screen's strength and options.
func play() -> void:
	var m := current_map()
	var foes := mini(int(main.foes_slider.value), starts.size() - 1)
	close()
	if not main.start_map(m, foes):
		main._show_hint("This map could not be started: each start needs open grass around it.", 5.0)


# --- Painting ---------------------------------------------------------------------------------------------

func _sync_view() -> void:
	var v := main.view
	v.editor_brush = size if tool == "brush" or tool == "smooth" else 1
	v.editor_round = round_brush
	v.editor_mirror = mirror if tool != "copy" and tool != "paste" else "off"
	v.editor_climate = show_climate
	v.editor_paste = Vector2i(int(clip.w), int(clip.h)) if tool == "paste" and not clip.is_empty() else Vector2i.ZERO
	if tool != "copy":
		v.editor_rect = Rect2i()
	if tool != "river":
		v.editor_line = []
	v.editor_starts = starts
	v.editor_animals = animals


## Remembers tile i as it was before this stroke changed it (once a stroke).
func _rec(i: int) -> void:
	var t: Dictionary = _stroke.tiles
	if not t.has(i):
		var sim: Sim = main.sim
		t[i] = [sim.ter[i], sim.deco[i], sim.amt[i], sim.ore[i], biome[i]]
	_touched[i] = true


func _begin_stroke() -> void:
	_stroke = {"tiles": {}, "starts": starts.duplicate(), "animals": animals.duplicate(true), "places": main.sim.places.duplicate(true)}
	_ground_moved = false


func _end_stroke() -> void:
	if _stroke.is_empty():
		return
	var changed: bool = not (_stroke.tiles as Dictionary).is_empty() or _stroke.starts != starts or _stroke.animals != animals or _stroke.places != main.sim.places
	if changed:
		_undo.append(_stroke)
		if _undo.size() > UNDO_MAX:
			_undo.pop_front()
		_redo = []
	_stroke = {}


func undo() -> void:
	_swap(_undo, _redo)


func redo() -> void:
	_swap(_redo, _undo)


## Takes the last record off one stack, puts the map back as it says, and the map as it was onto the
## other stack.
func _swap(from: Array, to: Array) -> void:
	if from.is_empty() or not open:
		return
	var sim: Sim = main.sim
	var r: Dictionary = from.pop_back()
	var back := {"tiles": {}, "starts": starts.duplicate(), "animals": animals.duplicate(true), "places": sim.places.duplicate(true)}
	var ground := false
	var biome_moved := false
	for i: int in r.tiles:
		var o: Array = r.tiles[i]
		back.tiles[i] = [sim.ter[i], sim.deco[i], sim.amt[i], sim.ore[i], biome[i]]
		if sim.ter[i] != o[0]:
			ground = true
		if biome[i] != o[4]:
			biome_moved = true
			main.view.editor_climate_set(i, int(o[4]))
		sim.ter[i] = o[0]; sim.deco[i] = o[1]; sim.amt[i] = o[2]; sim.ore[i] = o[3]; biome[i] = o[4]
		sim.changed_tiles.append(i)
	starts = (r.starts as Array).duplicate()
	animals = (r.animals as Array).duplicate(true)
	sim.places = (r.places as Array).duplicate(true)
	to.append(back)
	if starts.size() != setup.size():
		setup.resize(starts.size())
		for k in setup.size():
			if not (setup[k] is Dictionary):
				setup[k] = {}
	_rejoin_veins()
	if ground:
		_reheight()
	_fill()


## Sets one tile to what brush index k paints (ground, things, ore, amount, climate).
func _apply(i: int, what: String, val: int) -> void:
	var sim: Sim = main.sim
	match what:
		"ter":
			if sim.ter[i] == val:
				return
			_rec(i)
			_ground_moved = true
			sim.ter[i] = val
			if val == Sim.WATER or val == Sim.MOUNT:
				sim.deco[i] = 0
			sim.ore[i] = 0
			sim.amt[i] = 6 if val == Sim.WATER else ([0, 0, 8, 10][sim.deco[i]] if val != Sim.MOUNT else 0)
		"deco":
			# trees, rocks and clay grow on grass and beach only
			# (clearing water or mountain leaves its fish and ore alone)
			if (val == 0 and sim.deco[i] != 0) or (val != 0 and (sim.ter[i] == Sim.GRASS or sim.ter[i] == Sim.BEACH)):
				_rec(i)
				sim.deco[i] = val
				sim.amt[i] = [0, 0, 8, 10][val]
		"amount":
			if sim.ore[i] != 0:
				_rec(i)
				sim.amt[i] = int(WorldGen.ORE_AMOUNTS[ore_amt])
		"ore":
			if sim.ter[i] == Sim.MOUNT:
				_rec(i)
				sim.ore[i] = val
				sim.amt[i] = int(WorldGen.ORE_AMOUNTS[ore_amt]) if val > 0 else 0
				# a vein of its own for now, so it shows at once (joined up when the stroke ends)
				if val > 0:
					sim.vein[i] = sim.vein_amt.size()
					sim.vein_amt.append(20)
					sim.vein_tiles.append(PackedInt32Array([i]))
		"climate":
			if biome[i] != val:
				_rec(i)
				biome[i] = val
				main.view.editor_climate_set(i, val)
			return
	if sim.ore[i] == 0:
		sim.vein[i] = 0
	sim.changed_tiles.append(i)


func _paint(t: Vector2i, first: bool) -> void:
	if not open:
		return
	var sim: Sim = main.sim
	if first:
		_begin_stroke()
	if moving >= 0:
		if first and sim.inb(t.x, t.y):
			starts[moving] = t
			moving = -1
			main.view.editor_starts = starts
			_fill()
		return
	var pts := EditorTools.mirrored(t.x, t.y, sim.w, sim.h, mirror)
	match tool:
		"river":
			if first:
				_a = t
			main.view.editor_line = [_a, t]
			return
		"copy":
			if first:
				_a = t
			main.view.editor_rect = Rect2i(mini(_a.x, t.x), mini(_a.y, t.y), absi(t.x - _a.x) + 1, absi(t.y - _a.y) + 1)
			return
		"paste":
			if first:
				_stamp(t)
			return
		"smooth":
			for p: Vector2i in pts:
				for ch in EditorTools.smooth(sim, EditorTools.brush_tiles(p.x, p.y, size, round_brush)):
					_apply(int(ch[0]), "ter", int(ch[1]))
			return
		"fill":
			if first:
				_fill_at(pts)
			return
	if not sim.inb(t.x, t.y):
		return
	var what: String = BRUSHES[brush][1]
	if what == "animal":
		_animal(t, first)
		return
	if what == "place":
		if first:
			for p: Vector2i in pts:
				_place(p)
		return
	var val: int = int(BRUSHES[brush][2])
	for p: Vector2i in pts:
		for q: Vector2i in EditorTools.brush_tiles(p.x, p.y, size, round_brush):
			if sim.inb(q.x, q.y):
				_apply(q.y * sim.w + q.x, what, val)


func _animal(t: Vector2i, first: bool) -> void:
	var sim: Sim = main.sim
	var kind := String(BRUSHES[brush][2])
	if kind == "":
		var r0 := maxi(1, size / 2)
		for k in range(animals.size() - 1, -1, -1):
			if absi(int(animals[k][1]) - t.x) <= r0 and absi(int(animals[k][2]) - t.y) <= r0:
				animals.remove_at(k)
	elif first:
		var ti := sim.idx(t.x, t.y)
		if sim.ter[ti] == Sim.GRASS or sim.ter[ti] == Sim.BEACH:
			animals.append([kind, t.x, t.y])
		else:
			main._show_hint("Animals live on grass.", 2.0)
	main.view.editor_animals = animals
	_fill()


## Puts a ruin or bandit camp at p (or takes away what is near it).
func _place(p: Vector2i) -> void:
	var sim: Sim = main.sim
	var kind := String(BRUSHES[brush][2])
	if kind == "":
		for k in range(sim.places.size() - 1, -1, -1):
			if absi(int(sim.places[k].x) - p.x) <= 2 and absi(int(sim.places[k].y) - p.y) <= 2:
				sim.places.remove_at(k)
		_fill()
		return
	if not sim.inb(p.x, p.y):
		return
	if not Places.at(sim, p.x, p.y, 3).is_empty():
		main._show_hint("There is a place right next to this already.", 2.0)
		return
	var ti := sim.idx(p.x, p.y)
	if sim.ter[ti] != Sim.GRASS and sim.ter[ti] != Sim.BEACH:
		main._show_hint("Ruins and camps stand on grass.", 2.0)
		return
	sim.places.append(Places.make(kind, p.x, p.y))
	# their ground is cleared
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if sim.inb(p.x + dx, p.y + dy):
				var i := sim.idx(p.x + dx, p.y + dy)
				if sim.deco[i] != 0:
					_apply(i, "deco", 0)
	_fill()


func _fill_at(pts: Array) -> void:
	var sim: Sim = main.sim
	var what: String = BRUSHES[brush][1]
	if what == "animal" or what == "place":
		return
	var val: int = int(BRUSHES[brush][2])
	var mode := "deco" if what == "deco" else ("land" if what == "climate" else "ter")
	for p: Vector2i in pts:
		for i in EditorTools.flood(sim, p.x, p.y, mode):
			_apply(i, what, val)


## The copied area stamped with its top-left corner at t.
func _stamp(t: Vector2i) -> void:
	var sim: Sim = main.sim
	if clip.is_empty():
		return
	var cw: int = clip.w
	for y in int(clip.h):
		for x in cw:
			var tx := t.x + x
			var ty := t.y + y
			if not sim.inb(tx, ty):
				continue
			var i := ty * sim.w + tx
			var j := y * cw + x
			_rec(i)
			if sim.ter[i] != (clip.ter as PackedByteArray)[j]:
				_ground_moved = true
			sim.ter[i] = (clip.ter as PackedByteArray)[j]
			sim.deco[i] = (clip.deco as PackedByteArray)[j]
			sim.amt[i] = (clip.amt as PackedByteArray)[j]
			sim.ore[i] = (clip.ore as PackedByteArray)[j]
			var bv: int = (clip.biome as PackedByteArray)[j]
			if biome[i] != bv:
				biome[i] = bv
				main.view.editor_climate_set(i, bv)
			sim.changed_tiles.append(i)


## After a stroke: rivers are carved and areas copied, the ore joins up into veins, and the heights and
## the raised ground follow the new shape of the land. Only the parts of the map that changed are drawn
## again.
func _paint_done() -> void:
	var sim: Sim = main.sim
	if not open:
		return
	if tool == "river" and _a.x >= 0 and not main.view.editor_line.is_empty():
		var b: Vector2i = main.view.editor_line[1]
		if Vector2(b - _a).length() >= 3.0:
			var ends := [[_a, b]]
			var ma := EditorTools.mirrored(_a.x, _a.y, sim.w, sim.h, mirror)
			var mb := EditorTools.mirrored(b.x, b.y, sim.w, sim.h, mirror)
			for k in range(1, mini(ma.size(), mb.size())):
				ends.append([ma[k], mb[k]])
			for e in ends:
				var rv := EditorTools.river(sim, e[0], e[1], int(FORDS[ford_k][1]))
				for i: int in rv[0]:
					_apply(i, "ter", Sim.WATER)
				for i: int in rv[1]:
					_apply(i, "ter", Sim.BEACH)
					_apply(i, "deco", 0)
		main.view.editor_line = []
		_a = Vector2i(-1, -1)
	if tool == "copy" and _a.x >= 0:
		var r: Rect2i = main.view.editor_rect
		if r.size.x * r.size.y >= 1:
			clip = EditorTools.cut(sim, biome, r)
			main._show_hint(tr("Copied %d x %d tiles. Pick Paste and click where it goes.") % [r.size.x, r.size.y], 3.0)
		main.view.editor_rect = Rect2i()
		_a = Vector2i(-1, -1)
		_end_stroke()
		_fill()
		return
	var touched := not _touched.is_empty()
	_touched = {}
	var had_undo := _undo.size()
	_end_stroke()
	if had_undo != _undo.size() and tab == "Paint":
		_fill()
	if not touched:
		return
	_rejoin_veins()
	if _ground_moved:
		_reheight()


func _rejoin_veins() -> void:
	var sim: Sim = main.sim
	var g := {"w": sim.w, "h": sim.h, "ore": sim.ore, "amt": sim.amt}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sim.seed_str + "veins")
	WorldGen._make_veins(g, rng)
	sim.vein = g.vein; sim.vein_amt = g.vein_amt; sim.vein_tiles = g.vein_tiles


func _reheight() -> void:
	var sim: Sim = main.sim
	var old := sim.height
	sim.height = WorldGen.heights(sim.seed_str, sim.ter, sim.w, sim.h)
	var moved := PackedInt32Array()
	for i in sim.height.size():
		if i >= old.size() or old[i] != sim.height[i]:
			moved.append(i)
	sim.changed_tiles.append_array(moved)
	main.view.ground_changed()
