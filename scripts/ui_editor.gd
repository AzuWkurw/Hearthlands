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


## Opens the editor on the map of this seed and size (with room for n realms).
func start(seed_str: String, n: int, map_size: int) -> bool:
	var sim: Sim = main.sim
	if not sim.new_game(seed_str, maxi(1, n - 1), 5, false, map_size, false, {"features": []}):
		return false
	starts = []
	animals = []
	main.view.editor_animals = animals
	for p in sim.players:
		starts.append(p.start)
	# an empty map: no realms, buildings, roads or land
	sim.blds.clear(); sim.by_id.clear(); sim.trips.clear(); sim.attacks.clear()
	sim.bmap.fill(0); sim.owner.fill(0); sim.road.fill(0); sim.plot.fill(0)
	for p in sim.players:
		p.hq = null
	main._after_world_change()
	main.guide_ui.box.visible = false
	main.view.editor = true
	main.view.editor_starts = starts
	main.view.editor_brush = size
	main.view.center_on(Vector2(sim.w / 2.0, sim.h / 2.0))
	main.view.zoom = 12.0
	main.setup.visible = false
	main.side_box.visible = false
	main.toolbar.bar.visible = false
	main.paused = true
	open = true
	map_name = "map " + seed_str
	_fill()
	# in the side panel's place, full height
	var vs: Vector2 = main.get_viewport().get_visible_rect().size
	win.position = Vector2i(int(vs.x) - Main.SIDE_W, 0)
	win.size = Vector2i(Main.SIDE_W, int(vs.y))
	win.visible = true
	return true


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
