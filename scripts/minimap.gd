class_name Minimap
extends Control
## Whole-map overview: terrain, roads, territory, military buildings and the camera frame.
## Its images double as the far-zoom picture of the main map.

var sim: Sim
var view: MapView
var _base: ImageTexture
var _own: ImageTexture
var _base_img: Image            # one pixel per tile; only changed pixels are repainted
var _base_changed := false
const COLS := [Color("2f6d9c"), Color("d8c58c"), Color("6c9d47"), Color("7d786a")]
const TREE := Color("34602c")
const ROAD := Color("a88b5e")
var _ver := -1
var alerts: Array = []         # [tile, colour]: problems blinking on the map (see UiProblems)
var _t := 99.0
## What the minimap shows: "" everything, "roads" only roads, "land" only who holds the land and the
## forts, or "good:<id>" only your buildings that make that good (bright) on a dimmed map.
var filter := ""
var _filter_tex: ImageTexture


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func reset() -> void:
	_ver = -1
	_own_last = PackedByteArray()
	_t = 99.0
	_base = null
	_base_img = null
	_ore_tiles = PackedInt32Array()


func _process(delta: float) -> void:
	if sim == null or sim.w == 0:
		return
	_t += delta
	if _t > 1.0:
		_t = 0.0
		if _base == null or sim.map_dirty:
			_rebuild_base()
			sim.map_dirty = false
		elif _base_changed:
			_base.update(_base_img)
		_base_changed = false
		if _ver != sim.territory_version:
			_rebuild_owner()
		if filter == "roads":
			_rebuild_filter()
		elif filter == "ore":
			_ore_t += 1
			if _ore_t >= 5:
				_ore_t = 0
				_rebuild_ore()
	queue_redraw()


func set_filter(f: String) -> void:
	filter = f
	_filter_tex = null
	if f == "roads":
		_rebuild_filter()
	elif f == "ore":
		_ore_tiles = PackedInt32Array()
		_rebuild_ore()
	queue_redraw()


## (build 72) The prospecting view: every ore tile your geologists have found, in the ore's colour,
## brighter where more is left in its vein; empty veins dark. Made again every five seconds.
const ORE_COL := {1: Color("3a3a3a"), 2: Color("c0643c"), 3: Color("f0d040"), 4: Color("b0b0b8"), 5: Color("e08848"), 6: Color("e8e070"), 7: Color("8890a8"), 8: Color("d8d8e0")}
var _ore_tiles := PackedInt32Array()
var _ore_t := 0


func _rebuild_ore() -> void:
	if _ore_tiles.is_empty():
		for i in sim.w * sim.h:
			if sim.ore[i] != 0:
				_ore_tiles.append(i)
	var data := PackedByteArray()
	data.resize(sim.w * sim.h * 4)
	var me := sim.human()
	for i in _ore_tiles:
		if not sim.ore_known(me.id, i):
			continue
		var left := sim.vein_left(i)
		var c: Color = ORE_COL.get(int(sim.ore[i]), Color.WHITE)
		if int(sim.ore[i]) == 1:
			c = Color("9a9aa0")     # coal: grey, to show on the dimmed map
		var a := 70 if left <= 0 else clampi(140 + left, 150, 255)
		if left <= 0:
			c = c.darkened(0.6)
		data[i * 4] = c.r8; data[i * 4 + 1] = c.g8; data[i * 4 + 2] = c.b8; data[i * 4 + 3] = a
	_filter_tex = ImageTexture.create_from_image(Image.create_from_data(sim.w, sim.h, false, Image.FORMAT_RGBA8, data))


func _rebuild_filter() -> void:
	var data := PackedByteArray()
	data.resize(sim.w * sim.h * 4)
	for i in sim.w * sim.h:
		var o := int(sim.road[i])
		if o == 0:
			continue
		var c: Color = Color("f0d8a0") if o == 1 else sim.players[o - 1].color.lightened(0.2)
		if sim.ter[i] == Sim.WATER:
			c = Color("ffffff")
		data[i * 4] = c.r8; data[i * 4 + 1] = c.g8; data[i * 4 + 2] = c.b8; data[i * 4 + 3] = 255 if o == 1 else 170
	_filter_tex = ImageTexture.create_from_image(Image.create_from_data(sim.w, sim.h, false, Image.FORMAT_RGBA8, data))


func _tile_color(i: int) -> Color:
	if sim.road[i] != 0:
		return ROAD
	var c: Color = TREE if sim.deco[i] == Sim.D_TREE else COLS[sim.ter[i]]
	# hills: lighter where the ground faces the light (upper left), darker where it faces away
	if sim.ter[i] != Sim.WATER and sim.height.size() == sim.w * sim.h:
		var x := i % sim.w
		var y := i / sim.w
		var hx := int(sim.height[y * sim.w + mini(x + 1, sim.w - 1)]) - int(sim.height[y * sim.w + maxi(x - 1, 0)])
		var hy := int(sim.height[mini(y + 1, sim.h - 1) * sim.w + x]) - int(sim.height[maxi(y - 1, 0) * sim.w + x])
		var v := clampf((hx + hy) / 32.0 + (int(sim.height[i]) - 100) / 260.0, -1.0, 1.0)
		c = c.lightened(v * 0.4) if v > 0.0 else c.darkened(-v * 0.45)
	return c


func _rebuild_base() -> void:
	var data := PackedByteArray()
	data.resize(sim.w * sim.h * 3)
	for i in sim.w * sim.h:
		var c := _tile_color(i)
		data[i * 3] = c.r8; data[i * 3 + 1] = c.g8; data[i * 3 + 2] = c.b8
	_base_img = Image.create_from_data(sim.w, sim.h, false, Image.FORMAT_RGB8, data)
	# as RGBA: three-byte pictures came out black with Vulkan
	_base_img.convert(Image.FORMAT_RGBA8)
	_base = ImageTexture.create_from_image(_base_img)


## Repaints just the tiles that changed; the texture itself is refreshed once a second.
func tiles_changed(tiles: PackedInt32Array) -> void:
	if _base_img == null:
		return
	for i in tiles:
		_base_img.set_pixel(i % sim.w, i / sim.w, _tile_color(i))
	_base_changed = true


func base_tex() -> Texture2D:
	return _base


func own_tex() -> Texture2D:
	return _own


## A small picture of the map with everyone's land, for the save list. PNG bytes, empty if no map yet.
func thumbnail(px: int) -> PackedByteArray:
	if _base_img == null or sim == null or sim.w == 0:
		return PackedByteArray()
	var img := _base_img.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	if _own != null:
		img.blend_rect(_own.get_image(), Rect2i(0, 0, sim.w, sim.h), Vector2i.ZERO)
	img.resize(px, px * sim.h / maxi(1, sim.w), Image.INTERPOLATE_BILINEAR)
	return img.save_png_to_buffer()


var _own_data := PackedByteArray()   # the picture below, kept so only rows whose land changed are redone
var _own_last := PackedByteArray()   # sim.owner when it was last drawn
var _own_img: Image

func _rebuild_owner() -> void:
	_ver = sim.territory_version
	var w := sim.w
	var pc: Array = []
	for p in sim.players:
		pc.append(p.color)
	var full := _own_last.size() != sim.owner.size() or _own_img == null or _own_img.get_width() != w
	if full:
		_own_data = PackedByteArray()
		_own_data.resize(w * sim.h * 4)
		_own_last = PackedByteArray()
		_own_last.resize(sim.owner.size())
		_own_last.fill(255)        # every row counts as changed
	# rows whose land changed (comparing a row is done by the engine, so this is quick on big maps)
	var any := false
	for y in sim.h:
		var a := y * w
		if sim.owner.slice(a, a + w) == _own_last.slice(a, a + w):
			continue
		any = true
		for i in range(a, a + w):
			var o := sim.owner[i]
			if o == 0:
				_own_data[i * 4 + 3] = 0
				continue
			var c: Color = pc[o - 1]
			_own_data[i * 4] = c.r8; _own_data[i * 4 + 1] = c.g8; _own_data[i * 4 + 2] = c.b8; _own_data[i * 4 + 3] = 120
	if not any and _own != null:
		return
	_own_last = sim.owner.duplicate()
	_own_img = Image.create_from_data(w, sim.h, false, Image.FORMAT_RGBA8, _own_data)
	if _own == null or full:
		_own = ImageTexture.create_from_image(_own_img)
	else:
		_own.update(_own_img)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	if sim == null or sim.w == 0 or _base == null:
		return
	var r := Rect2(Vector2.ZERO, size)
	draw_texture_rect(_base, r, false)
	var s := size / Vector2(sim.w, sim.h)
	if filter != "":
		# a dimmed map with only what the filter picks drawn bright
		draw_rect(r, Color(0, 0, 0, 0.62))
		if filter == "land" and _own:
			draw_texture_rect(_own, r, false)
			draw_texture_rect(_own, r, false)
		if (filter == "roads" or filter == "ore") and _filter_tex != null:
			draw_texture_rect(_filter_tex, r, false)
		if filter.begins_with("good:"):
			var res := filter.substr(5)
			for b in sim.blds:
				if b.p == 1 and not b.dead and Crops.out_of(sim, b).has(res):
					draw_rect(Rect2(Vector2(b.x, b.y) * s - Vector2(2, 2), Vector2(5, 5)), Color("f0d060") if b.state == "ready" else Color("a09060"))
		if filter == "land":
			for b in sim.blds:
				if sim.is_mil(b):
					draw_rect(Rect2(Vector2(b.x, b.y) * s - Vector2(1.5, 1.5), Vector2(4, 4)), sim.players[b.p - 1].color.lightened(0.4))
		var fog2 = sim.get_feature("fog")
		if fog2 != null and fog2.tex != null:
			draw_texture_rect(fog2.tex, r, false)
		if view:
			var half2 := view.size / 2.0 / view.zoom
			draw_rect(Rect2((view.cam - half2) * s, half2 * 2.0 * s), Color.WHITE, false, 1.0)
		draw_rect(r, Color("3a4136"), false, 2.0)
		return
	if _own:
		draw_texture_rect(_own, r, false)
	var fog = sim.get_feature("fog")
	for b in sim.blds:
		if sim.is_mil(b):
			if fog != null and b.p != 1 and not fog.seen.has(sim.idx(b.x, b.y)) and not fog.visible_at(sim.idx(b.x, b.y)):
				continue
			draw_rect(Rect2(Vector2(b.x, b.y) * s - Vector2(1, 1), Vector2(3, 3)), sim.players[b.p - 1].color.lightened(0.3))
	if fog != null and fog.tex != null:
		draw_texture_rect(fog.tex, r, false)
	# problems blink: red where you are attacked, amber where a building is stuck
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	for a in alerts:
		var p: Vector2 = Vector2(a[0]) * s + s * 0.5
		var c: Color = a[1]
		draw_circle(p, 2.5, c)
		if c.is_equal_approx(Main.col("bad")):
			draw_arc(p, 4.0 + 3.0 * blink, 0, TAU, 16, Color(c, 0.4 + 0.5 * blink), 1.5)
	if view:
		var half := view.size / 2.0 / view.zoom
		draw_rect(Rect2((view.cam - half) * s, half * 2.0 * s), Color.WHITE, false, 1.0)
	draw_rect(r, Color("3a4136"), false, 2.0)


func _gui_input(event: InputEvent) -> void:
	var go := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		go = true; pos = event.position
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		go = true; pos = event.position
	if go and sim != null and view != null:
		view.center_on(pos / size * Vector2(sim.w, sim.h))
		accept_event()
