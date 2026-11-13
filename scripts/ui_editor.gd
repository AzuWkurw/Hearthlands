class_name UiEditor
extends RefCounted
## The map editor: opened from the new-game screen. It starts from the map of the seed and size chosen
## there, without any realm on it, and paints ground, trees, rocks, clay and ore with a brush. The
## numbered banners are the headquarters' places (start 1 is yours); "Move start" puts one where you
## click next. Maps are saved as JSON in the "maps" folder of the game's data folder (user://maps) and
## can be played from the editor or picked on the new-game screen. Missions can name a map too.

const MAP_DIR := "user://maps"
const BRUSHES := [
	["Water", "ter", Sim.WATER], ["Beach", "ter", Sim.BEACH], ["Grass", "ter", Sim.GRASS], ["Mountain", "ter", Sim.MOUNT],
	["Trees", "deco", 1], ["Rocks", "deco", 2], ["Clay", "deco", 3], ["Clear", "deco", 0],
	["Coal", "ore", 1], ["Iron", "ore", 2], ["Gold", "ore", 3], ["Granite", "ore", 4], ["Copper", "ore", 5], ["No ore", "ore", 0],
	["Set ore amount", "amount", 0],
	["Deer", "animal", "deer"], ["Boar", "animal", "boar"], ["Hare", "animal", "hare"], ["Wolf", "animal", "wolf"], ["No animals", "animal", ""],
]
const AMOUNT_NAMES := ["Poor", "Normal", "Rich", "Very rich"]

var main: Main
var win: Window
var body: VBoxContainer
var open := false
var brush := 2          # index in BRUSHES
var size := 3           # brush width in tiles
var moving := -1        # a start being moved (its index), or -1
var starts: Array = []  # Vector2i
var map_name := "my map"
var name_edit: LineEdit
var _touched := {}
var ore_amt := 1        # index in WorldGen.ORE_AMOUNTS for the ore brushes
var animals: Array = [] # [kind, x, y] placed on the map (none: the game puts them at random)
var gen_seed := ""      # the Generate section's settings
var gen_size := 128
var gen_starts := 4
var gen := WorldGen.GEN_DEFAULTS.duplicate()
var _show_gen := false  # the Generate section is open


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
	for p in sim.players:
		starts.append(p.start)
	map_name = "map " + seed_str
	_begin_editing()
	return true


## Opens a saved map file for editing: its ground, ore (with the amounts painted), starts and animals.
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
	var g := {"w": sim.w, "h": sim.h, "ore": sim.ore, "amt": sim.amt}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sim.seed_str + "veins")
	WorldGen._make_veins(g, rng)
	sim.vein = g.vein; sim.vein_amt = g.vein_amt; sim.vein_tiles = g.vein_tiles
	starts = (m.starts as Array).duplicate()
	animals = (m.get("animals", []) as Array).duplicate(true)
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
	main.view.editor = true
	main.view.editor_starts = starts
	main.view.editor_animals = animals
	main.view.editor_brush = size
	main.view.center_on(Vector2(sim.w / 2.0, sim.h / 2.0))
	main.view.zoom = 12.0
	main.setup.visible = false
	main.side_box.visible = false
	main.toolbar.bar.visible = false
	main.paused = true
	open = true
	_fill()
	# in the side panel's place, full height
	var vs: Vector2 = main.get_viewport().get_visible_rect().size
	win.position = Vector2i(int(vs.x) - Main.SIDE_W, 0)
	win.size = Vector2i(Main.SIDE_W, int(vs.y))
	win.visible = true


## The top of the panel: open a saved map, or make a new one with the landscape settings.
func _map_section() -> void:
	body.add_child(main._label("Map", 14, Main.BRASS))
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
	var gb := main._button("New map..." if not _show_gen else "Hide", func():
		_show_gen = not _show_gen
		_fill())
	gb.toggle_mode = true
	gb.set_pressed_no_signal(_show_gen)
	lr.add_child(gb)
	if _show_gen:
		_gen_section()
	body.add_child(HSeparator.new())


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
	g.add_child(main._label("Shape", 13, Main.DIM))
	var sh := OptionButton.new()
	sh.focus_mode = Control.FOCUS_NONE
	for k in WorldGen.SHAPES:
		sh.add_item({"island": "Island (sea all round)", "continent": "Continent (land to the edges)", "lakes": "Lakes (mostly land)", "archipelago": "Archipelago (many islands)"}[k])
		if String(gen.shape) == k:
			sh.select(sh.item_count - 1)
	sh.item_selected.connect(func(i): gen["shape"] = WorldGen.SHAPES[i])
	g.add_child(sh)
	for k in [["water", "Water"], ["mountains", "Mountains"], ["forests", "Forests"], ["ore", "Ore"], ["scale", "Landform size"]]:
		g.add_child(main._label(String(k[1]), 13, Main.DIM))
		var hs := HSlider.new()
		hs.min_value = 0.0; hs.max_value = 1.0; hs.step = 0.05
		hs.value = float(gen[k[0]])
		hs.custom_minimum_size = Vector2(150, 0)
		hs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hs.tooltip_text = {"water": "How much sea and lake", "mountains": "How much mountain (where mines go)", "forests": "How much woodland", "ore": "How much of the mountains holds ore", "scale": "Small: many small lakes, hills and woods. Large: a few big ones."}[k[0]]
		var key: String = k[0]
		hs.value_changed.connect(func(v): gen[key] = v)
		g.add_child(hs)
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


func close() -> void:
	open = false
	win.visible = false
	main.view.editor = false
	main.view.editor_starts = []
	main.view.editor_animals = []
	main.side_box.visible = true
	main.toolbar.bar.visible = true
	main.setup.visible = true
	main._fill_maps()


func _fill() -> void:
	for c in body.get_children():
		c.queue_free()
	_map_section()
	body.add_child(main._label("Brush", 14, Main.BRASS))
	var g := GridContainer.new()
	g.columns = 3
	body.add_child(g)
	for k in BRUSHES.size():
		var b := main._button(String(BRUSHES[k][0]), func():
			brush = k
			moving = -1
			_fill())
		b.toggle_mode = true
		b.set_pressed_no_signal(k == brush and moving < 0)
		b.custom_minimum_size = Vector2(96, 0)
		g.add_child(b)
	# how much ore the ore brushes put in (and "Set ore amount" changes on ore already painted)
	var orr := HBoxContainer.new()
	body.add_child(orr)
	orr.add_child(main._label("Ore", 13, Main.DIM))
	for k in AMOUNT_NAMES.size():
		var ob := main._button(AMOUNT_NAMES[k], func():
			ore_amt = k
			_fill())
		ob.toggle_mode = true
		ob.set_pressed_no_signal(k == ore_amt)
		ob.tooltip_text = "Each ore tile painted holds %d units; a vein holds what its tiles hold together." % (int(WorldGen.ORE_AMOUNTS[k]) * WorldGen.ORE_UNIT)
		orr.add_child(ob)
	var what0: String = BRUSHES[brush][1]
	if what0 == "animal":
		body.add_child(main._label(tr("%d animals placed. Click to place one; No animals clears them under the brush. With none placed the game puts animals at random.") % animals.size(), 12, Main.DIM))
		(body.get_child(body.get_child_count() - 1) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sr := HBoxContainer.new()
	body.add_child(sr)
	sr.add_child(main._label("Size", 13, Main.DIM))
	for s in [1, 3, 5, 9]:
		var b := main._button("%d" % s, func():
			size = s
			main.view.editor_brush = s
			_fill())
		b.toggle_mode = true
		b.set_pressed_no_signal(s == size)
		sr.add_child(b)
	body.add_child(main._label("Starts (start 1 is yours)", 14, Main.BRASS))
	var st := HFlowContainer.new()
	body.add_child(st)
	for k in starts.size():
		var b := main._button("Move %d" % (k + 1), func():
			moving = k
			main._show_hint("Click where start %d should be." % (k + 1), 3.0)
			_fill())
		b.toggle_mode = true
		b.set_pressed_no_signal(moving == k)
		st.add_child(b)
	var ar := HBoxContainer.new()
	body.add_child(ar)
	ar.add_child(main._button("Add a start", func():
		if starts.size() < 9:
			starts.append(Vector2i(main.sim.w / 2, main.sim.h / 2))
			moving = starts.size() - 1
			_fill()))
	ar.add_child(main._button("Remove last", func():
		if starts.size() > 2:
			starts.pop_back()
			moving = -1
			_fill()))
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
		var fn := map_name.strip_edges().validate_filename()
		var mp := MAP_DIR + "/" + fn + ".json"
		var ms := SharePack.user_missions().filter(func(m): return String(m.get("map", "")).get_file() == mp.get_file())
		SharePack.dialog(main, true, func(path):
			var err := SharePack.export_pack(path, [mp], ms)
			main._show_hint(err if err != "" else "Exported to %s" % path, 4.0))))
	br.add_child(main._button("Close", close))
	var tip := main._label("Left button paints, the middle button or a drag with the wheel moves the map. Starts need open grass around them. Maps are kept in %s." % ProjectSettings.globalize_path(MAP_DIR), 12, Main.DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(370, 0)
	body.add_child(tip)


## The map as it is now, in the map file shape (see WorldGen.load_map).
func current_map() -> Dictionary:
	var sim: Sim = main.sim
	var m := {"name": map_name, "w": sim.w, "h": sim.h, "seed": sim.seed_str, "starts": starts.duplicate(), "animals": animals.duplicate(true)}
	for k in WorldGen.MAP_KEYS:
		m[k] = (sim.get(k) as PackedByteArray).duplicate()
	return m


func save() -> void:
	var fn := map_name.strip_edges().validate_filename()
	if fn == "":
		main._show_hint("Give the map a name first.", 3.0)
		return
	var err := WorldGen.save_map(current_map(), MAP_DIR + "/" + fn + ".json")
	main._show_hint(err if err != "" else "Saved the map \"%s\"." % fn, 3.0)


## Plays the map: you on start 1, rivals on the others (as many as the new-game screen asks, at most
## one per start), with the new-game screen's strength and options.
func play() -> void:
	var m := current_map()
	var foes := mini(int(main.foes_slider.value), starts.size() - 1)
	close()
	if not main.start_map(m, foes):
		main._show_hint("This map could not be started: each start needs open grass around it.", 5.0)


func _paint(t: Vector2i, first: bool) -> void:
	if not open:
		return
	var sim: Sim = main.sim
	if not sim.inb(t.x, t.y):
		return
	if moving >= 0:
		if first:
			starts[moving] = t
			moving = -1
			main.view.editor_starts = starts
			_fill()
		return
	var what: String = BRUSHES[brush][1]
	if what == "animal":
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
		return
	var val: int = int(BRUSHES[brush][2]) if what != "animal" else 0
	var r := size / 2
	for dy in range(-r, size - r):
		for dx in range(-r, size - r):
			var x := t.x + dx
			var y := t.y + dy
			if not sim.inb(x, y):
				continue
			var i := sim.idx(x, y)
			match what:
				"ter":
					sim.ter[i] = val
					if val == Sim.WATER or val == Sim.MOUNT:
						sim.deco[i] = 0
					if val != Sim.MOUNT:
						sim.ore[i] = 0
					sim.amt[i] = 6 if val == Sim.WATER else 0
				"deco":
					# trees, rocks and clay grow on grass and beach only
					if val == 0 or sim.ter[i] == Sim.GRASS or sim.ter[i] == Sim.BEACH:
						sim.deco[i] = val
						sim.amt[i] = [0, 0, 8, 10][val]
				"amount":
					if sim.ore[i] != 0:
						sim.amt[i] = int(WorldGen.ORE_AMOUNTS[ore_amt])
				"ore":
					if sim.ter[i] == Sim.MOUNT:
						sim.ore[i] = val
						sim.amt[i] = int(WorldGen.ORE_AMOUNTS[ore_amt]) if val > 0 else 0
						# a vein of its own for now, so it shows at once (joined up when the stroke ends)
						if val > 0:
							sim.vein[i] = sim.vein_amt.size()
							sim.vein_amt.append(20)
							sim.vein_tiles.append(PackedInt32Array([i]))
						else:
							sim.vein[i] = 0
			if sim.ore[i] == 0:
				sim.vein[i] = 0
			_touched[i] = true
			sim.changed_tiles.append(i)


## After a stroke: the ore joins up into veins, and the heights and the raised ground follow the new
## shape of the land. Only the parts of the map that changed are drawn again.
func _paint_done() -> void:
	if _touched.is_empty():
		return
	_touched = {}
	var sim: Sim = main.sim
	var what: String = BRUSHES[brush][1]
	if what == "ore" or what == "ter" or what == "amount":
		var g := {"w": sim.w, "h": sim.h, "ore": sim.ore, "amt": sim.amt}
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(sim.seed_str + "veins")
		WorldGen._make_veins(g, rng)
		sim.vein = g.vein; sim.vein_amt = g.vein_amt; sim.vein_tiles = g.vein_tiles
	if what != "ter":
		return
	var old := sim.height
	sim.height = WorldGen.heights(sim.seed_str, sim.ter, sim.w, sim.h)
	var moved := PackedInt32Array()
	for i in sim.height.size():
		if i >= old.size() or old[i] != sim.height[i]:
			moved.append(i)
	sim.changed_tiles.append_array(moved)
	main.view.ground_changed()
