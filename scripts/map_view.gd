class_name MapView
extends Control
## Draws the world and turns mouse input into tile clicks.
## The ground, roads, scenery and borders come from pre-baked chunks (map_chunks.gd), drawn by a child
## layer whose shader makes the water shimmer. Everything that moves or changes often (buildings,
## carriers, soldiers, workers, smoke, selections, tool previews) is drawn every frame on top.
## Animations follow the game clock, so they freeze while the game is paused and speed up with it.

signal tile_clicked(tile: Vector2i)
signal cancel_requested
signal paint(tile: Vector2i, first: bool)   # map editor: the left button is down over this tile
signal paint_done                           # map editor: the left button was let go

const DETAIL_ZOOM := 10.0        # below this many pixels per tile, the map is drawn from the minimap image
const ANIM_ZOOM := 14.0          # below this, small details (smoke, workers, animals) are skipped
const LORES_ZOOM := 16.0         # below this, the ground comes from chunks baked at half resolution
## Tools that outdoor workers carry, by the building's "act".
const TOOL := {"cut_tree": "axe", "cut_rock": "pick", "dig_clay": "shovel", "fish": "rod", "plant": "seed"}
## Where effects sit on each building style, as fractions of the picture's width and height.
## A building can override these in buildings.json with "art": {"smoke": [u, v], "glow": [u, v], "hub": [u, v]}.
const ANCHORS := {
	"house": {"smoke": [0.57, 0.28]}, "apartments": {"smoke": [0.65, 0.14]},
	"workshop": {"smoke": [0.66, 0.25]}, "kiln": {"smoke": [0.27, 0.17], "glow": [0.28, 0.89]},
	"mill": {"hub": [0.47, 0.34]},
}
## Smoke that rises all the time from homes, not only while a building works.
const HOME_SMOKE := ["house", "apartments"]
## Farms that keep animals grazing around them.
const ANIMALS := {"sheep_farm": "unit_sheep", "pig_farm": "unit_pig"}

var sim: Sim
var minimap: Minimap
var chunks := MapChunks.new()
var cam := Vector2(40, 40)       # camera centre in tiles
var zoom := 32.0                 # screen pixels per tile
var place_type := ""             # a building id, or a tool: "@road", "@pave", "@unroad", "@work"
var ghost := Vector2i(-1, -1)
var editor := false            # the map editor is open: left button paints (see UiEditor)
var editor_starts: Array = []  # the map editor's start places, drawn as numbered banners
var editor_brush := 1          # the map editor's brush size, drawn around the mouse
var _painting := false
var _paint_last := Vector2i(-1, -1)
var _tool_labels: Array = []   # text drawn over the map for the tool in hand (land a military building would claim)
var _gain := {}                # while placing a military building: the best spots and how much new land each claims
var sel_id := 0
var preview_tiles := PackedInt32Array()   # land a demolition would lose (drawn red while it is asked)
var preview_blds: Array = []               # buildings it would lose (crossed out)
var sel_tile := -1               # a selected map tile (deposit info), or -1
var road_start := Vector2i(-1, -1)
var door := 0                     # the side a building being placed faces (Sim.DOOR_NAMES); R turns it
var road_after := false           # the road tool was started for a building just placed: it stops once joined
var show_sites := false           # a building group is open: mark the largest building each spot takes
var _site_key := ""
var _sites := {}                  # tile -> "small", "medium", "large" or "mine"
var auto_roads := false           # new buildings get their road at once (Settings.auto_roads; preview only)
var _auto_key := Vector4i(-1, -1, -1, -1)
var _auto_path := PackedInt32Array()
var flash := 0.0
var draw_usec := 0               # time the last _draw took, for the F3 performance overlay
var ground_usec := 0             # time the last ground drawing took
var animate := true              # the "Animations" option; off shows still pictures

var _drag := false
var _moved := false
var _press := Vector2.ZERO
var _preview := PackedInt32Array()
var _preview_key := Vector4i(-1, -1, -1, -1)
var _bld_tex: Dictionary = {}
var _era_tex: Dictionary = {}        # building type -> its picture in each of the six ages
var _res_tex: Dictionary = {}
var _carrier_tex: Dictionary = {}
var _constr: Texture2D
var _smoke: Texture2D
var _glow: Texture2D
var _sails: Texture2D
var _ground: Control
var _ground_mat: ShaderMaterial
var _origin := Vector2.ZERO
var _folk_roads: Dictionary = {}   # house id -> [game time worked out, straight runs of road nearby: [from, to]]
var _vary: ImageTexture            # ground variation (see _make_variation)
var _scn_atlas: ImageTexture       # trees, peaks and boulders side by side (see _make_scenery_atlas)
var _scn_size: Array = []          # per SCENERY entry: [uv rect in the atlas, size in tiles]
var _scn_mesh := {}                # chunk key -> ArrayMesh of the scenery standing in it (null: none)
var _scn_ver := -1                 # chunks.ver the meshes were made for

# --- Raised ground (2.5D) ---------------------------------------------------------------------------
# Each tile corner is raised by the height of the ground around it (LIFT tiles per height step, the sea
# stays flat), and the ground is drawn as a grid of quads through those corners, so hills stand up from
# the map as in The Settlers II; the light and shade from the slopes is baked into the chunks. Buildings,
# people and markers are drawn raised by the height under their feet (lift_at). Clicks are traced back
# through the raised ground (screen_to_tile). The "Raised ground" option turns it off (all flat).
const LIFT := 0.014
var raised := true
var _lift := PackedFloat32Array()  # (w + 1) x (h + 1) tile corners: how far each is raised, in tiles
var _lift_key := ""
var _chunk_mesh := {}              # chunk key -> ArrayMesh through its raised corners
var _map_mesh: ArrayMesh           # the whole map, a coarse grid (for pictures covering the whole map)
var _base_origin := Vector2.ZERO
var _cur_lift := 0.0


## Works out the corner heights again when the map or the option changed.
func _ensure_lift() -> void:
	var key := "%d|%d|%d|%s" % [sim.get_instance_id(), sim.w, sim.h, raised]
	if key == _lift_key and _lift.size() == (sim.w + 1) * (sim.h + 1):
		return
	_lift_key = key
	_chunk_mesh = {}
	_scn_mesh = {}
	_map_mesh = null
	var W := sim.w + 1
	_lift = PackedFloat32Array(); _lift.resize(W * (sim.h + 1))
	if not raised or sim.height.size() != sim.w * sim.h:
		return
	for cy in sim.h + 1:
		for cx in W:
			var s := 0.0
			var n := 0
			var water := false
			for dy in [-1, 0]:
				for dx in [-1, 0]:
					var x: int = cx + dx
					var y: int = cy + dy
					if x >= 0 and y >= 0 and x < sim.w and y < sim.h:
						var i := y * sim.w + x
						if sim.ter[i] == Sim.WATER:
							water = true
						s += float(sim.height[i])
						n += 1
			# corners touching the sea stay at sea level, so the shore meets the water
			_lift[cy * W + cx] = 0.0 if water or n == 0 else maxf(0.0, s / n - 6.0) * LIFT


## How far the ground at (fx, fy), in tiles, is raised on screen.
func lift_at(fx: float, fy: float) -> float:
	if not raised or sim == null or _lift.size() != (sim.w + 1) * (sim.h + 1):
		return 0.0
	if is_nan(fx) or is_nan(fy):
		return 0.0
	var W := sim.w + 1
	var x := clampf(fx, 0.0, float(sim.w) - 0.001)
	var y := clampf(fy, 0.0, float(sim.h) - 0.001)
	var ix := int(x)
	var iy := int(y)
	var u := x - ix
	var v := y - iy
	var a := _lift[iy * W + ix]
	var b := _lift[iy * W + ix + 1]
	var c := _lift[(iy + 1) * W + ix]
	var d := _lift[(iy + 1) * W + ix + 1]
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


## Draw what follows raised as the ground at (fx, fy) is; _unlift goes back to the flat map.
func _lift_to(fx: float, fy: float) -> void:
	_cur_lift = lift_at(fx, fy)
	_origin = _base_origin + Vector2(0, -_cur_lift * zoom)
	draw_set_transform(_origin, 0.0, Vector2(zoom, zoom))


func _unlift() -> void:
	if _cur_lift == 0.0 and _origin == _base_origin:
		return
	_cur_lift = 0.0
	_origin = _base_origin
	draw_set_transform(_origin, 0.0, Vector2(zoom, zoom))


## A grid of quads over tiles (x0, y0) to (x0 + nx * step, y0 + ny * step) through the raised corners,
## its picture spread over uv0..uv1.
func _grid_mesh(x0: int, y0: int, nx: int, ny: int, step: int, uv0: Vector2, uv1: Vector2) -> ArrayMesh:
	var W := sim.w + 1
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for j in ny + 1:
		for i in nx + 1:
			var cx := mini(x0 + i * step, sim.w)
			var cy := mini(y0 + j * step, sim.h)
			var l := _lift[cy * W + cx] if _lift.size() == W * (sim.h + 1) else 0.0
			verts.append(Vector2(x0 + i * step, y0 + j * step - l))
			uvs.append(uv0 + (uv1 - uv0) * Vector2(float(i) / nx, float(j) / ny))
	var idx := PackedInt32Array()
	for j in ny:
		for i in nx:
			var a := j * (nx + 1) + i
			idx.append_array(PackedInt32Array([a, a + 1, a + nx + 1, a + 1, a + nx + 2, a + nx + 1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _chunk_grid(cx: int, cy: int) -> ArrayMesh:
	var k := cy * 1000 + cx
	if not _chunk_mesh.has(k):
		_chunk_mesh[k] = _grid_mesh(cx * MapChunks.CH, cy * MapChunks.CH, MapChunks.CH, MapChunks.CH, 1, Vector2.ZERO, Vector2.ONE)
	return _chunk_mesh[k]


## Draws a picture that covers the whole map (fog, territory far out, ground variation) on canvas item
## ci, raised with the ground.
func draw_map_texture(ci: CanvasItem, tex: Texture2D, mod := Color.WHITE) -> void:
	if not raised or _lift.size() != (sim.w + 1) * (sim.h + 1):
		ci.draw_texture_rect(tex, Rect2(0, 0, sim.w, sim.h), false, mod)
		return
	if _map_mesh == null:
		var st := 2
		var nx := ceili(sim.w / float(st))
		var ny := ceili(sim.h / float(st))
		_map_mesh = _grid_mesh(0, 0, nx, ny, st, Vector2.ZERO, Vector2(nx * st / float(sim.w), ny * st / float(sim.h)))
	ci.draw_mesh(_map_mesh, tex, Transform2D(), mod)


## Four raised corners of tile (x, y), for drawing something lying on the ground there.
func tile_quad(x: int, y: int) -> PackedVector2Array:
	var W := sim.w + 1
	if not raised or _lift.size() != W * (sim.h + 1):
		return PackedVector2Array([Vector2(x, y), Vector2(x + 1, y), Vector2(x + 1, y + 1), Vector2(x, y + 1)])
	return PackedVector2Array([Vector2(x, y - _lift[y * W + x]), Vector2(x + 1, y - _lift[y * W + x + 1]),
		Vector2(x + 1, y + 1 - _lift[(y + 1) * W + x + 1]), Vector2(x, y + 1 - _lift[(y + 1) * W + x])])


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = load("res://shaders/ground.gdshader")
	_ground = Control.new()
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.show_behind_parent = true
	_ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ground.material = _ground_mat
	_ground.draw.connect(_draw_ground)
	add_child(_ground)
	set_smooth(true)
	refresh_textures()


func _process(_delta: float) -> void:
	_ground.queue_redraw()


func set_animate(on: bool) -> void:
	animate = on
	_ground_mat.set_shader_parameter("animate", on)


func set_smooth(on: bool) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if on else CanvasItem.TEXTURE_FILTER_NEAREST
	chunks.smooth = on
	chunks.clear()


## Re-reads every texture (call after adding custom PNGs).
func refresh_textures() -> void:
	chunks.sim = sim
	chunks.load_images()
	_bld_tex.clear()
	_tops.clear()
	_era_tex.clear()
	for b in GameData.bld:
		_bld_tex[b] = Tex.get_tex(GameData.bld_tex_id(b))
	_res_tex.clear()
	_scn_atlas = null
	for r in GameData.resources:
		_res_tex[r.id] = Tex.get_tex("res_" + String(r.id))
	_constr = Tex.get_tex("fx_construction")
	_smoke = Tex.get_tex("fx_smoke")
	_glow = Tex.get_tex("fx_glow")
	_sails = Tex.get_tex("anim_sails")
	queue_redraw()


## A new or loaded game: forget everything baked for the old map.
## The map editor changed the ground's shape: heights and the water's depth again, without throwing
## away the baked map (the tiles that changed are re-baked as usual).
func ground_changed() -> void:
	_lift_key = ""
	_make_variation()


func reset_world() -> void:
	chunks.sim = sim
	chunks.clear()
	_lift_key = ""          # the ground's heights may have changed (map editor)
	road_start = Vector2i(-1, -1)
	_preview = PackedInt32Array()
	_make_variation()


## A soft picture laid over the whole map so the ground doesn't look tiled: darker and lighter
## patches of grass and rock a dozen tiles across, and water that darkens as it gets deeper
## (further from land). Four pixels a tile, smoothed.
func _make_variation() -> void:
	_vary = null
	if sim == null or sim.w == 0:
		return
	var w := sim.w
	var h := sim.h
	var n := FastNoiseLite.new()
	n.seed = sim.seed_str.hash() & 0x7fffffff
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 1.0 / 13.0
	n.fractal_octaves = 3
	# how far each water tile is from land, up to 6
	var depth := PackedByteArray()
	depth.resize(w * h)
	var q := PackedInt32Array()
	for i in w * h:
		if sim.ter[i] == Sim.WATER:
			depth[i] = 255
		else:
			q.append(i)
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		if depth[i] >= 6:
			continue
		var x := i % w
		var y := i / w
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var xx := x + d.x
			var yy := y + d.y
			if xx >= 0 and yy >= 0 and xx < w and yy < h:
				var j := yy * w + xx
				if depth[j] == 255:
					depth[j] = depth[i] + 1
					q.append(j)
	var data := PackedByteArray()
	data.resize(w * h * 4)
	for i in w * h:
		var c := Color(0, 0, 0, 0)
		var t := sim.ter[i]
		var v := n.get_noise_2d(i % w, i / w)
		if t == Sim.WATER:
			var dd := mini(int(depth[i]), 6)
			c = Color(0.02, 0.08, 0.2, clampf((dd - 1) / 5.0, 0.0, 1.0) * 0.32)
		elif v < 0.0:
			c = Color(0.06, 0.12, 0.02, -v * (0.26 if t == Sim.GRASS else 0.16))
		else:
			c = Color(1.0, 0.94, 0.66, v * (0.14 if t == Sim.GRASS else 0.08))
		data[i * 4] = int(c.r * 255); data[i * 4 + 1] = int(c.g * 255); data[i * 4 + 2] = int(c.b * 255); data[i * 4 + 3] = int(c.a * 255)
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	img.resize(w * 4, h * 4, Image.INTERPOLATE_BILINEAR)
	_vary = ImageTexture.create_from_image(img)


## Tiles whose look changed in the simulation (trees cut, roads laid...).
func tiles_changed(tiles: PackedInt32Array) -> void:
	for i in tiles:
		chunks.mark_tile(i)
		# the scenery of this tile's chunk, and of its neighbours' (a peak needs mountain all round)
		var x := i % sim.w
		var y := i / sim.w
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var xx: int = x + d.x
			var yy: int = y + d.y
			if xx >= 0 and yy >= 0 and xx < sim.w and yy < sim.h:
				_scn_mesh.erase((yy / MapChunks.CH) * 1000 + xx / MapChunks.CH)


func screen_to_tile(pos: Vector2) -> Vector2i:
	var wpos := (pos - size / 2.0) / zoom + cam
	if raised and sim != null and _lift.size() == (sim.w + 1) * (sim.h + 1):
		# the ground at y is drawn lift_at higher: look for the y whose raised place is under the mouse
		var y := wpos.y
		for k in 4:
			y = wpos.y + lift_at(wpos.x, y)
		return Vector2i(floori(wpos.x), floori(y))
	return Vector2i(floori(wpos.x), floori(wpos.y))


func center_on(tile: Vector2) -> void:
	cam = tile
	_clamp()


func zoom_at(pos: Vector2, f: float) -> void:
	var before := (pos - size / 2.0) / zoom + cam
	zoom = clampf(zoom * f, 4.0, 96.0)
	cam = before - (pos - size / 2.0) / zoom
	_clamp()


func pan(delta: Vector2) -> void:
	cam += delta
	_clamp()


func _clamp() -> void:
	if sim != null and sim.w > 0:
		cam = cam.clamp(Vector2.ZERO, Vector2(sim.w, sim.h))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_at(mb.position, 1.12)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_at(mb.position, 1.0 / 1.12)
		elif editor and mb.button_index == MOUSE_BUTTON_LEFT:
			# the map editor paints with the left button (the middle button still moves the map)
			if mb.pressed:
				_painting = true
				_paint_last = screen_to_tile(mb.position)
				paint.emit(_paint_last, true)
			elif _painting:
				_painting = false
				paint_done.emit()
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_drag = true; _moved = mb.button_index == MOUSE_BUTTON_MIDDLE; _press = mb.position
			else:
				if _drag and not _moved and mb.button_index == MOUSE_BUTTON_LEFT:
					tile_clicked.emit(screen_to_tile(mb.position))
				_drag = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			cancel_requested.emit()
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		ghost = screen_to_tile(mm.position)
		if _painting and ghost != _paint_last:
			_paint_last = ghost
			paint.emit(ghost, false)
		if _drag:
			if not _moved and mm.position.distance_to(_press) > 6.0:
				_moved = true
			if _moved:
				pan(-mm.relative / zoom)
		accept_event()
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		zoom_at(mg.position, mg.factor)
	elif event is InputEventPanGesture:
		pan((event as InputEventPanGesture).delta * 12.0 / zoom)


## The road a "build road" click would lay now, recomputed only when the start or the mouse tile changes.
func road_preview() -> PackedInt32Array:
	if road_start.x < 0 or not sim.inb(ghost.x, ghost.y):
		return PackedInt32Array()
	var key := Vector4i(road_start.x, road_start.y, ghost.x, ghost.y)
	if key != _preview_key:
		_preview_key = key
		_preview = sim.find_path(road_start.x, road_start.y, ghost.x, ghost.y, 1) if ghost != road_start and sim.owner[sim.idx(ghost.x, ghost.y)] == 1 else PackedInt32Array()
	return _preview


## Draws the ground on the child layer, which sits behind everything this view draws itself.
func _draw_ground() -> void:
	var t_start := Time.get_ticks_usec()
	var g := _ground
	if sim == null or sim.w == 0:
		g.draw_rect(Rect2(Vector2.ZERO, size), Color("0d0f0c"))
		return
	var z := zoom
	var half := size / 2.0
	var x0 := maxi(0, floori(cam.x - half.x / z) - 1)
	var x1 := mini(sim.w - 1, ceili(cam.x + half.x / z) + 1)
	var y0 := maxi(0, floori(cam.y - half.y / z) - 1)
	var y1 := mini(sim.h - 1, ceili(cam.y + half.y / z) + (5 if raised else 2))
	_ensure_lift()
	g.draw_set_transform(half - cam * z, 0.0, Vector2(z, z))
	# the dark background beyond the map edge, given in tiles like everything on this layer
	g.draw_rect(Rect2(cam - half / z, size / z), Color("0d0f0c"))
	# baked chunks up close (half resolution when zoomed out a little), the minimap picture far out
	if chunks.twin == null:
		chunks.twin = MapChunks.new()
		chunks.twin.TS = 16
		chunks.twin.sim = sim
		chunks.twin.smooth = chunks.smooth
		chunks.twin.details = chunks.details
		chunks.twin.load_images()
	var ch: MapChunks = chunks if z >= LORES_ZOOM else chunks.twin
	chunks.sim = sim
	ch.sim = sim
	ch.begin_frame()
	if z >= DETAIL_ZOOM:
		# bake for at most 3 ms per frame (and at least one chunk), so scrolling never stutters
		var budget := [Time.get_ticks_usec() + 3000, 0]
		for cy in range(y0 / MapChunks.CH, y1 / MapChunks.CH + 1):
			for cx in range(x0 / MapChunks.CH, x1 / MapChunks.CH + 1):
				var tex := ch.get_chunk(cx, cy, budget)
				var r := Rect2(cx * MapChunks.CH, cy * MapChunks.CH, MapChunks.CH, MapChunks.CH)
				if tex != null:
					if raised:
						g.draw_mesh(_chunk_grid(cx, cy), tex)
					else:
						g.draw_texture_rect(tex, r, false)
				elif minimap != null and minimap.base_tex() != null:
					# not baked yet: that part of the minimap picture, raised the same way
					if raised:
						var fk := -(cy * 1000 + cx) - 1
						if not _chunk_mesh.has(fk):
							var CHN := MapChunks.CH
							_chunk_mesh[fk] = _grid_mesh(cx * CHN, cy * CHN, CHN, CHN, 1, Vector2(cx * CHN / float(sim.w), cy * CHN / float(sim.h)), Vector2((cx + 1) * CHN / float(sim.w), (cy + 1) * CHN / float(sim.h)))
						g.draw_mesh(_chunk_mesh[fk], minimap.base_tex())
					else:
						g.draw_texture_rect_region(minimap.base_tex(), r, r)
	elif minimap != null and minimap.base_tex() != null:
		draw_map_texture(g, minimap.base_tex())
	ground_usec = Time.get_ticks_usec() - t_start


func _draw() -> void:
	var t_start := Time.get_ticks_usec()
	if sim == null or sim.w == 0:
		return
	var z := zoom
	var half := size / 2.0
	var origin := half - cam * z
	_origin = origin
	var x0 := maxi(0, floori(cam.x - half.x / z) - 1)
	var x1 := mini(sim.w - 1, ceili(cam.x + half.x / z) + 1)
	var y0 := maxi(0, floori(cam.y - half.y / z) - 1)
	var y1 := mini(sim.h - 1, ceili(cam.y + half.y / z) + 2)
	var w := sim.w
	var detail := animate and z >= ANIM_ZOOM
	draw_set_transform(origin, 0.0, Vector2(z, z))
	_ensure_lift()
	_base_origin = origin
	_cur_lift = 0.0
	if raised:
		y1 = mini(sim.h - 1, y1 + 3)
	# far out the territory comes from the minimap's picture, drawn here so it skips the water shader
	if z < DETAIL_ZOOM and minimap != null and minimap.own_tex() != null:
		draw_map_texture(self, minimap.own_tex())
	if _vary != null:
		draw_map_texture(self, _vary)
	if z >= DETAIL_ZOOM:
		_draw_scenery(x0, x1, y0, y1)
	# features draw on the ground (season colours, snow) under the buildings
	if not sim.features.is_empty():
		var vr := Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
		for f: Feature in sim.features:
			f.draw_map(self, vr)
	# building-site markers (while placing, or with a building group open), under the buildings
	_tool_labels = []
	_site_markers(x0, y0, x1, y1)
	# buildings, sorted back to front
	var vis: Array = []
	# with the fog of war, rival buildings out of sight are drawn by the fog as last seen
	var fog = sim.get_feature("fog")
	var fv: PackedByteArray = PackedByteArray() if fog == null else fog.vis
	var fog_on: bool = fog != null and fv.size() == sim.w * sim.h
	for b in sim.blds:
		if b.x >= x0 - 3 and b.x <= x1 + 3 and b.y >= y0 - 1 and b.y <= y1 + 4:
			if fog_on and b.p != 1 and fv[b.y * w + b.x] == 0:
				continue
			vis.append(b)
	vis.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var labels: Array = []
	# townsfolk about the houses and roads (close up only), drawn in turn with the buildings so a house
	# in front hides the people behind it
	var folk: Array = _collect_folk(vis) if detail else []
	var fi := 0
	for b in vis:
		while fi < folk.size() and float(folk[fi][0]) < b.y + 0.98:
			_draw_folk_one(folk[fi]); fi += 1
		if raised: _lift_to(b.x + 0.5, b.y + 0.9)
		var nl := labels.size()
		_draw_building(b, labels, detail)
		for li in range(nl, labels.size()):
			labels[li][0] = (labels[li][0] as Vector2) + Vector2(0, -_cur_lift)
		_unlift()
	while fi < folk.size():
		_draw_folk_one(folk[fi]); fi += 1
	# entrance flags of your buildings, close up; one still without a road waves a warning ring
	if detail:
		for b in vis:
			if b.p == 1 and b.door >= 0 and not b.dead:
				var dt := sim.door_tile(b)
				if dt >= 0:
					if raised: _lift_to(dt % w + 0.5, dt / w + 0.6)
					_door_flag(dt, sim.players[0].color, not sim.connected(b))
					_unlift()
	# flags you set on your roads (road carriers mode)
	if detail and not sim.players.is_empty():
		for fi2 in sim.players[0].flags:
			var fx: int = fi2 % w
			var fy: int = fi2 / w
			if fx >= x0 and fx <= x1 and fy >= y0 and fy <= y1 and sim.road[fi2] == 1:
				if raised: _lift_to(fx + 0.5, fy + 0.6)
				_door_flag(fi2, Color(0.95, 0.95, 0.9), false)
				_unlift()
	# carriers: loaded on the way to the store, empty on the way back (drawn in batches, see _batch_add)
	var drawn := 0
	_batching = true
	for t in sim.trips:
		if drawn > 700:
			break
		var n := t.path.size() - 1
		if n < 1:
			continue
		var prog := 0.0
		if not t.delivered:
			prog = clampf((sim.time - t.t0) / maxf(0.01, t.t1 - t.t0), 0.0, 0.999)
		else:
			prog = 1.0 - clampf((sim.time - t.t1) / maxf(0.01, t.t2 - t.t1), 0.0, 1.0)
		# carriers bringing materials walk the other way: from the store out to the site
		if (t.site != 0 or t.dest != 0) and t.kind != "ship":
			prog = 1.0 - prog
		var f := prog * n
		var k := mini(floori(f), n - 1)
		var a := t.path[k]
		var c := t.path[k + 1]
		var pos := Vector2(a % w, a / w).lerp(Vector2(c % w, c / w), f - k) + Vector2(0.5, 0.75)
		var waiting := false
		if not t.legs.is_empty():
			# road carriers: on the stretch the load is on now, or lying at a flag waiting its turn
			var lp := _leg_pos(t)
			if lp.z < 0.0:
				waiting = true
			a = int(lp.x); c = int(lp.y)
			pos = Vector2(a % w, a / w).lerp(Vector2(c % w, c / w), absf(lp.z)) + Vector2(0.5, 0.75)
			if waiting:
				pos = Vector2(a % w, a / w) + Vector2(0.5 + 0.12 * float(t.p * 7 + int(t.t0 * 10.0) % 5) / 5.0, 0.7)
		if pos.x < x0 or pos.x > x1 + 1 or pos.y < y0 or pos.y > y1 + 1:
			continue
		if fog_on and t.p != 1 and fv[mini(sim.h - 1, int(pos.y)) * w + mini(w - 1, int(pos.x))] == 0:
			continue
		drawn += 1
		if raised:
			pos.y -= lift_at(pos.x, pos.y)
		var pc: Color = sim.players[t.p - 1].color
		if z < DETAIL_ZOOM:
			# far out a carrier is a few pixels: a dot in the realm's colour is enough
			draw_rect(Rect2(pos.x - 0.2, pos.y - 0.45, 0.4, 0.4), pc.lightened(0.3))
			continue
		if waiting:
			# goods waiting at a flag for the next stretch's carrier
			if _res_tex.has(t.res):
				var wt: Texture2D = _res_tex[t.res]
				_batch_layer = 2
				_batch_add(wt, Rect2(pos.x - 0.15, pos.y - 0.3, 0.3, 0.3), Rect2(Vector2.ZERO, wt.get_size()), Color.WHITE)
				_batch_layer = 0
			continue
		# facing: the way along the path it is walking (backwards on the way home)
		var dx := (c % w - a % w) * (-1 if t.delivered else 1) * (-1 if (t.site != 0 or t.dest != 0) and t.kind != "ship" else 1)
		if not t.legs.is_empty():
			dx = c % w - a % w
		var step := int(f * 8.0) if animate else 0
		var loaded := not t.delivered
		var chh := 0.0
		# a builder on his way to a site (or home), a soldier on his way to his post
		if t.kind == "builder":
			_person("unit_worker_hammer", pos, step % (8 if Tex.frames("unit_worker_hammer") >= 10 else 4), dx < 0, pc.lightened(0.25))
			continue
		if t.kind == "worker":
			# a new worker on his way from his home: peasants in straw hats, artisans in caps
			var wb: Sim.Bld = sim.by_id.get(t.site)
			var cls := String(wb.def.get("worker", "peasant")) if wb != null else "peasant"
			var fid := "unit_folk_artisan" if cls == "artisan" else "unit_folk_peasant"
			_person(fid, pos, step % (8 if Tex.frames(fid) >= 10 else 4), dx < 0, pc.lightened(0.25))
			continue
		if t.kind == "ship":
			# a little ship: brown hull, a white sail with the realm's colour
			var fl := -1.0 if dx < 0 else 1.0
			var bob := 0.03 * sin(sim.time * 3.0 + t.t0)
			var hp := pos + Vector2(0, -0.2 + bob)
			draw_colored_polygon(PackedVector2Array([hp + 1.6 * Vector2(-0.45 * fl, -0.1), hp + 1.6 * Vector2(0.5 * fl, -0.1), hp + 1.6 * Vector2(0.3 * fl, 0.12), hp + 1.6 * Vector2(-0.35 * fl, 0.12)]), Color("6b4a2a"))
			draw_line(hp + 1.6 * Vector2(0, -0.1), hp + 1.6 * Vector2(0, -0.75), Color("3a2a18"), 0.07)
			draw_colored_polygon(PackedVector2Array([hp + 1.6 * Vector2(0.03 * fl, -0.72), hp + 1.6 * Vector2(0.34 * fl, -0.2), hp + 1.6 * Vector2(0.03 * fl, -0.2)]), Color("f2efe4"))
			draw_rect(Rect2(hp + 1.6 * Vector2(-0.02, -0.82), Vector2(0.16 * fl, 0.08)).abs(), pc)
			if t.res != "@expedition" and _res_tex.has(t.res):
				draw_texture_rect(_res_tex[t.res], Rect2(hp + 1.6 * Vector2(-0.32 * fl - 0.1, -0.32), Vector2(0.32, 0.32)), false)
			continue
		if t.kind == "soldier":
			_sprite(_soldier_id(t.n if t.n >= 0 else float(sim.players[t.p - 1].age)), pos, 0.5, step % 4, dx < 0, pc.lightened(0.2))
			continue
		if t.kind == "porter" and not t.legs.is_empty() and _leg_donkey:
			# road carriers: a donkey takes this load along a busy stretch
			chh = _sprite("unit_mule", pos, 0.7, step, dx < 0)
		elif t.kind == "porter":
			# men with a crate on an A-frame, women with a sack; empty on the way back; at the store
			# they stoop to set the load down
			var pid := "unit_porter_w" if (t.p * 7 + int(t.t0 * 10.0)) % 3 == 0 else "unit_porter"
			var fr := (step % 8) + (0 if loaded else 8)
			if Tex.frames(pid) < 18:
				fr = step
			elif t.delivered and sim.time - t.t1 < 0.8 and t.site == 0:
				fr = 16 if sim.time - t.t1 < 0.4 else 17
			chh = _sprite(pid, pos, 0.4, fr, dx < 0)
			if Tex.frames(pid + "_tint") == Tex.frames(pid):
				_batch_layer = 1
				_sprite(pid + "_tint", pos, 0.4, fr, dx < 0, pc.lightened(0.25))
				_batch_layer = 0
		elif t.kind == "mule":
			chh = _sprite("unit_mule", pos, 0.78, step, dx < 0)
		else:
			chh = _sprite("unit_cart", pos, 1.15, step, dx < 0)
			# the cart's load: the goods themselves, as many as it carries
			if loaded:
				var lid := "unit_load_" + _load_kind(t.res)
				_batch_layer = 1
				_sprite(lid, pos, 1.15, clampi(t.n, 1, 6) - 1, dx < 0)
				_batch_layer = 0
		if loaded and t.kind != "cart" and _res_tex.has(t.res):
			var rt: Texture2D = _res_tex[t.res]
			_batch_layer = 2
			_batch_add(rt, Rect2(pos.x - 0.13, pos.y - chh - 0.24, 0.26, 0.26), Rect2(Vector2.ZERO, rt.get_size()), Color.WHITE)
			_batch_layer = 0
	_flush_batches()
	# marching soldiers
	for a in sim.attacks:
		if fog_on and a.p != 1:
			var ap: Vector2 = a.to if a.fighting else a.from.lerp(a.to, clampf((sim.time - a.t0) / maxf(0.01, a.t1 - a.t0), 0.0, 1.0))
			if fv[clampi(int(ap.y), 0, sim.h - 1) * w + clampi(int(ap.x), 0, w - 1)] == 0:
				continue
		var left := a.to.x < a.from.x
		var col: Color = sim.players[a.p - 1].color.lightened(0.2)
		if raised:
			var apos: Vector2 = a.to if a.fighting else a.from.lerp(a.to, clampf((sim.time - a.t0) / maxf(0.01, a.t1 - a.t0), 0.0, 1.0))
			_lift_to(apos.x + 0.5, apos.y + 0.9)
		var nl2 := labels.size()
		if a.fighting:
			# a duel at the gate: the attacker and a defender take turns to strike
			var tgt: Sim.Bld = sim.by_id.get(a.tgt)
			var at := a.to + Vector2(0.5, 1.05)
			var side := Vector2(0.3, 0) * (1 if left else -1)
			var beat := int(sim.time * 3.0) if animate else 0
			var ak := Sim.mix_newest(a.amix)
			_sprite(_soldier_id(ak if ak >= 0 else a.era), at + side, 0.5, 4 + beat % 2, left, col)
			if tgt != null:
				# the defenders' best answer to the attackers' strongest kind
				var dk: int = sim.military.best_counter(sim.military.mix_of(sim.military._defending(tgt)), maxi(0, ak))
				_sprite(_soldier_id(dk if dk >= 0 else sim.military.defender_era(tgt)), at - side, 0.5, 4 + (beat + 1) % 2, not left, sim.players[tgt.p - 1].color.lightened(0.2))
			if animate and beat % 2 == 1:
				draw_circle(at + Vector2(0, -0.32), 0.05, Color(1.0, 0.9, 0.5, 0.9))
			labels.append([at + Vector2(0, -0.85), str(a.n), Color.WHITE])
		else:
			var f2 := clampf((sim.time - a.t0) / maxf(0.01, a.t1 - a.t0), 0.0, 1.0)
			var pos2 := a.from.lerp(a.to, f2) + Vector2(0.5, 0.75)
			if a.field != 0:
				# a battle in the open: crossed swords over the column
				var sw := pos2 + Vector2(0, -1.25)
				draw_line(sw + Vector2(-0.22, -0.22), sw + Vector2(0.22, 0.22), Color(0.95, 0.93, 0.85), 0.07)
				draw_line(sw + Vector2(0.22, -0.22), sw + Vector2(-0.22, 0.22), Color(0.95, 0.93, 0.85), 0.07)
			var walked := a.from.distance_to(pos2)
			var dir := (a.to - a.from).normalized()
			# the column: up to three figures, one for each of its most numerous kinds
			var kinds := []
			for kk in range(5, -1, -1):
				if a.amix.size() > kk and int(a.amix[kk]) > 0:
					kinds.append(kk)
			kinds.sort_custom(func(x, y): return int(a.amix[x]) > int(a.amix[y]))
			kinds = kinds.slice(0, 3)
			if kinds.is_empty():
				kinds = [roundi(a.era)]
			# the last stretch is a charge: weapons lowered, running
			var charging := pos2.distance_to(a.to + Vector2(0.5, 0.75)) < 1.6
			for i in kinds.size():
				var side2 := Vector2(-dir.y, dir.x) * (0.22 if i % 2 == 1 else -0.12 * float(i))
				var off := -dir * 0.42 * i + side2
				var fr := (4 + int(sim.time * 8.0 + i) % 2) if charging and animate else (int(walked * 5.0 + i) % 4 if animate else 0)
				_sprite(_soldier_id(kinds[i]), pos2 + off, 0.5, fr, left, col)
			# gunfire: smoke and flashes at the shooters, streaks toward the other side
			var tgt2: Sim.Bld = sim.by_id.get(a.tgt)
			if sim.time - a.shot_t < 0.45:
				var u := (sim.time - a.shot_t) / 0.45
				var muzzle := pos2 + Vector2(0.25 * (-1 if left else 1), -0.3)
				draw_circle(muzzle + Vector2(0, -u * 0.25), 0.12 + u * 0.22, Color(0.92, 0.92, 0.88, 0.75 * (1.0 - u)))
				if u < 0.25:
					draw_circle(muzzle, 0.07, Color(1.0, 0.85, 0.4, 0.95))
					draw_line(muzzle, a.to + Vector2(0.5, 0.5), Color(1.0, 0.95, 0.7, 0.5), 0.03)
			if tgt2 != null and sim.time - a.dshot_t < 0.45:
				var u2 := (sim.time - a.dshot_t) / 0.45
				var gate := Vector2(tgt2.x + 0.5, tgt2.y + 0.4)
				draw_circle(gate + Vector2(0, -u2 * 0.25), 0.15 + u2 * 0.25, Color(0.92, 0.92, 0.88, 0.75 * (1.0 - u2)))
				if u2 < 0.25:
					draw_circle(gate, 0.08, Color(1.0, 0.85, 0.4, 0.95))
					draw_line(gate, pos2 + Vector2(0, -0.3), Color(1.0, 0.95, 0.7, 0.5), 0.03)
			labels.append([pos2 + Vector2(0, -0.85), str(a.n), Color.WHITE])
		for li in range(nl2, labels.size()):
			labels[li][0] = (labels[li][0] as Vector2) + Vector2(0, -_cur_lift)
		_unlift()
	if not sim.features.is_empty():
		var vr2 := Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
		for f: Feature in sim.features:
			f.draw_top(self, vr2)
	_draw_night(vis, x0, y0, x1, y1)
	_draw_selection_and_tools()
	# screen-space text
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for f: Feature in sim.features:
		f.draw_overlay(self, screen_to_tile)
	if z >= 14.0:
		var font := get_theme_default_font()
		var fs := clampi(int(z * 0.42), 10, 20)
		for l in _tool_labels:
			l[0] = (l[0] as Vector2) + Vector2(0, -lift_at((l[0] as Vector2).x, (l[0] as Vector2).y + 0.6))
		for l in labels + _tool_labels:
			var sp: Vector2 = origin + (l[0] as Vector2) * z
			draw_string_outline(font, sp + Vector2(-40, 0), String(l[1]), HORIZONTAL_ALIGNMENT_CENTER, 80, fs, 4, Color.BLACK)
			draw_string(font, sp + Vector2(-40, 0), String(l[1]), HORIZONTAL_ALIGNMENT_CENTER, 80, fs, l[2])
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.28, 0.24, flash * 0.25))
	draw_usec = Time.get_ticks_usec() - t_start


func _draw_selection_and_tools() -> void:
	var w := sim.w
	if not preview_tiles.is_empty() or not preview_blds.is_empty():
		for i in preview_tiles:
			draw_rect(Rect2(i % w, i / w, 1, 1), Color(0.9, 0.2, 0.15, 0.38))
		for id in preview_blds:
			var o: Sim.Bld = sim.by_id.get(id)
			if o != null:
				var c := Vector2(o.x + 0.5, o.y + 0.4)
				draw_line(c + Vector2(-0.45, -0.45), c + Vector2(0.45, 0.45), Color("ff4a3a"), 0.14)
				draw_line(c + Vector2(0.45, -0.45), c + Vector2(-0.45, 0.45), Color("ff4a3a"), 0.14)
	if editor:
		for k in editor_starts.size():
			var st: Vector2i = editor_starts[k]
			var c := Vector2(st.x + 0.5, st.y + 0.5 - lift_at(st.x + 0.5, st.y + 0.5))
			draw_rect(Rect2(c.x - 3.5, c.y - 3.5, 7, 7), Color(Sim.PCOL[k % Sim.PCOL.size()], 0.18))
			draw_rect(Rect2(c.x - 3.5, c.y - 3.5, 7, 7), Sim.PCOL[k % Sim.PCOL.size()], false, 0.1)
			draw_circle(c, 0.7, Sim.PCOL[k % Sim.PCOL.size()])
			_tool_labels.append([c + Vector2(0, -0.9), "Start %d%s" % [k + 1, " (you)" if k == 0 else ""], Color.WHITE])
		if sim.inb(ghost.x, ghost.y):
			var r := editor_brush / 2
			var gl := lift_at(ghost.x + 0.5, ghost.y + 0.5)
			draw_rect(Rect2(ghost.x - r, ghost.y - r - gl, editor_brush, editor_brush), Color(1, 1, 1, 0.9), false, 0.08)
		return
	var sel: Sim.Bld = sim.by_id.get(sel_id)
	if sel != null:
		if raised: _lift_to(sel.x + 0.5, sel.y + 0.5)
		draw_rect(Rect2(sel.x, sel.y, 1, 1), Color("ffe28a"), false, 0.08)
		if sel.p == 1 and sim.is_mil(sel):
			draw_arc(Vector2(sel.x + 0.5, sel.y + 0.5), Sim.RANGE, 0, TAU, 96, Color(1, 1, 1, 0.35), 0.08)
			for t2 in sim.blds:
				if t2.p != 1 and sim.is_mil(t2) and t2.state == "ready" and Vector2(t2.x - sel.x, t2.y - sel.y).length() <= Sim.RANGE:
					draw_arc(Vector2(t2.x + 0.5, t2.y + 0.5), 0.8, 0, TAU, 32, Color("ff6a4a"), 0.1)
		var wr := sim.work_radius(sel)
		if wr > 0:
			var wc := sim.work_center(sel)
			var cpos := Vector2(wc.x + 0.5, wc.y + 0.5)
			draw_arc(cpos, wr + 0.5, 0, TAU, 64, Color(1.0, 1.0, 0.6, 0.6), 0.07)
			if wc != Vector2i(sel.x, sel.y):
				draw_line(Vector2(sel.x + 0.5, sel.y + 0.5), cpos, Color(1.0, 1.0, 0.6, 0.6), 0.06)
		if sel.def.has("carriers"):
			draw_arc(Vector2(sel.x + 0.5, sel.y + 0.5), float(sel.def.carriers.range), 0, TAU, 64, Color(0.6, 0.9, 1.0, 0.5), 0.07)
	_unlift()
	if sel_tile >= 0:
		var q := tile_quad(sel_tile % w, sel_tile / w)
		q.append(q[0])
		draw_polyline(q, Color("8fe0ff"), 0.08)
	if place_type == "" or not sim.inb(ghost.x, ghost.y):
		return
	# the tool's marks lie on the ground at the mouse
	if raised: _lift_to(ghost.x + 0.5, ghost.y + 0.5)
	var g := Rect2(ghost.x, ghost.y, 1, 1)
	match place_type:
		"@road":
			if road_start.x >= 0:
				draw_rect(Rect2(road_start.x, road_start.y, 1, 1), Color("ffe28a"), false, 0.1)
				var path := road_preview()
				# the planned road, each step coloured by how steep it is (yellow to red), as on roads
				for k in path.size():
					var i := path[k]
					var sl := 0
					if k > 0: sl = maxi(sl, sim.slope_level(path[k - 1], i))
					if k < path.size() - 1: sl = maxi(sl, sim.slope_level(i, path[k + 1]))
					var col := Color(0.66, 0.55, 0.37, 0.85) if sl == 0 else (MapChunks.SLOPE_COL[sl] as Color)
					var dl := lift_at(i % w + 0.5, i / w + 0.5) - _cur_lift
					draw_rect(Rect2(i % w + 0.25, i / w + 0.25 - dl, 0.5, 0.5), col)
				draw_rect(g, Color("86ad5c") if path.size() > 0 else Color("d9483d"), false, 0.08)
			else:
				var ok := sim.road[sim.idx(ghost.x, ghost.y)] == 1 or (sim.bld_at(ghost.x, ghost.y) != null and sim.bld_at(ghost.x, ghost.y).p == 1) or sim.door_owner(ghost.x, ghost.y, 1) != null
				draw_rect(g, Color("86ad5c") if ok else Color("d9483d"), false, 0.08)
		"@demolish":
			var db := sim.bld_at(ghost.x, ghost.y)
			var can := db != null and db.p == 1 and db.ty != "hq"
			var dc := Color("e0402f") if can else Color(0.6, 0.6, 0.6, 0.8)
			draw_rect(g, Color(dc, 0.25))
			draw_rect(g, dc, false, 0.08)
			if can:
				draw_line(g.position + Vector2(0.2, 0.2), g.end - Vector2(0.2, 0.2), dc, 0.1)
				draw_line(Vector2(g.position.x + 0.8, g.position.y + 0.2), Vector2(g.position.x + 0.2, g.position.y + 0.8), dc, 0.1)
		"@pave", "@unroad":
			var on_road := sim.road[sim.idx(ghost.x, ghost.y)] == 1
			draw_rect(g, Color("86ad5c") if on_road else Color("d9483d"), false, 0.08)
		"@work":
			if sel != null and sim.work_radius(sel) > 0:
				var lim := int(sel.def.work.get("move", 6))
				var ok2 := Vector2(ghost.x - sel.x, ghost.y - sel.y).length() <= lim + 0.01
				draw_arc(Vector2(sel.x + 0.5, sel.y + 0.5), lim + 0.5, 0, TAU, 64, Color(1, 1, 1, 0.35), 0.06)
				draw_arc(Vector2(ghost.x + 0.5, ghost.y + 0.5), sim.work_radius(sel) + 0.5, 0, TAU, 64, Color("86ad5c") if ok2 else Color("d9483d"), 0.08)
		_:
			if not GameData.bld.has(place_type):
				# a feature's tool (send scout, send geologist...): a plain marker
				draw_rect(g, Color(1, 1, 1, 0.8), false, 0.08)
				return
			var why := sim.can_place(place_type, ghost.x, ghost.y, 1, door)
			var gc := Color("d9483d") if why != "" else Color("86ad5c")
			# the whole plot it stands on, and the free tile it needs all round (faint)
			var tiles := sim.plot_tiles(place_type, ghost.x, ghost.y)
			var ring := {}
			for t in tiles:
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx: int = t % w + dx
						var ny: int = t / w + dy
						if sim.inb(nx, ny) and not tiles.has(ny * w + nx):
							ring[ny * w + nx] = true
			for t in ring:
				var bad: bool = sim.plot[t] != 0
				draw_rect(Rect2(t % w + 0.06, t / w + 0.06, 0.88, 0.88), Color("d9483d", 0.75) if bad else Color(1, 1, 1, 0.22), false, 0.04)
			for t in tiles:
				draw_rect(Rect2(t % w, t / w, 1, 1), Color(gc, 0.4))
				draw_rect(Rect2(t % w, t / w, 1, 1), gc, false, 0.06)
			if tiles.is_empty():
				draw_rect(g, Color(gc, 0.4))
			draw_rect(g, gc, false, 0.08)
			# the entrance: an arrow out of the building to its flag on the tile in front (R turns it)
			var dt := sim.door_at(ghost.x, ghost.y, door)
			if dt >= 0:
				var a0 := Vector2(ghost.x + 0.5, ghost.y + 0.5)
				var a1 := Vector2(dt % w + 0.5, dt / w + 0.5)
				var dirv := (a1 - a0).normalized()
				var perp := Vector2(-dirv.y, dirv.x)
				var tip := a0 + dirv * 0.95
				draw_line(a0 + dirv * 0.3, tip - dirv * 0.2, Color(1, 0.95, 0.6, 0.95), 0.1)
				draw_colored_polygon(PackedVector2Array([tip, tip - dirv * 0.28 + perp * 0.17, tip - dirv * 0.28 - perp * 0.17]), Color(1, 0.95, 0.6, 0.95))
				draw_rect(Rect2(dt % w, dt / w, 1, 1), Color(1, 0.95, 0.6, 0.8), false, 0.06)
				_door_flag(dt, sim.players[0].color, false)
				# with auto roads on, the road it would get
				if auto_roads and why == "":
					var key := Vector4i(ghost.x, ghost.y, door, int(sim.time))
					if Vector3i(key.x, key.y, key.z) != Vector3i(_auto_key.x, _auto_key.y, _auto_key.z):
						_auto_key = key
						_auto_path = sim._path_to_net(ghost.x, ghost.y, 1, door)
					for k in range(1, _auto_path.size()):
						var i := _auto_path[k]
						if sim.road[i] != 1:
							var dl2 := lift_at(i % w + 0.5, i / w + 0.5) - _cur_lift
							draw_rect(Rect2(i % w + 0.3, i / w + 0.3 - dl2, 0.4, 0.4), Color(0.66, 0.55, 0.37, 0.75))
			var d: Dictionary = GameData.bld[place_type]
			if d.has("radius"):
				draw_arc(Vector2(ghost.x + 0.5, ghost.y + 0.5), float(d.radius), 0, TAU, 64, Color(1, 1, 1, 0.5), 0.08)
				if why == "":
					_tool_labels.append([Vector2(ghost.x + 0.5, ghost.y - 0.6), "+%d land" % land_gain(ghost.x, ghost.y, int(d.radius), 1), Color("f2cf5a")])
			if d.has("work"):
				draw_arc(Vector2(ghost.x + 0.5, ghost.y + 0.5), float(d.work.radius) + 0.5, 0, TAU, 48, Color(1, 1, 0.6, 0.35), 0.06)
			if d.has("carriers"):
				draw_arc(Vector2(ghost.x + 0.5, ghost.y + 0.5), float(d.carriers.range), 0, TAU, 64, Color(0.6, 0.9, 1.0, 0.4), 0.06)


## Marks the free spots: while placing a building, every spot it fits (with the current entrance);
## with a building group open, the largest size each spot takes. Worked out again a few times a
## second at most, and only close up (far out there would be thousands of spots).
func _site_markers(x0: int, y0: int, x1: int, y1: int) -> void:
	var placing := GameData.bld.has(place_type)
	if not placing and not show_sites:
		return
	if zoom < 20.0 or (x1 - x0 + 1) * (y1 - y0 + 1) > 3500:
		return
	var key := "%s|%d|%d,%d,%d,%d|%d" % [place_type if placing else "", door, x0, y0, x1, y1, Time.get_ticks_msec() / 600]
	if key != _site_key:
		_site_key = key
		_sites = {}
		var sz := sim.size_of(place_type) if placing else ""
		_gain = {}
		for y in range(maxi(0, y0), mini(sim.h - 1, y1) + 1):
			for x in range(maxi(0, x0), mini(sim.w - 1, x1) + 1):
				if placing:
					if Vector2i(x, y) != ghost and sim.can_place(place_type, x, y, 1, door) == "":
						_sites[y * sim.w + x] = sz
				else:
					var s := sim.site_size(x, y, 1)
					if s != "":
						_sites[y * sim.w + x] = s
	# none under the building being placed, so its plot stays easy to read
	var skip := {}
	if placing and sim.inb(ghost.x, ghost.y):
		for t in sim.plot_tiles(place_type, ghost.x, ghost.y):
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					skip[t + dy * sim.w + dx] = true
	# placing a military building: the spots that would claim the most new land get a "+N" ("expand here")
	if placing and GameData.bld[place_type].has("radius"):
		if _gain.is_empty() and not _sites.is_empty():
			var r := int(GameData.bld[place_type].radius)
			var all: Array = []
			for t in _sites:
				all.append([land_gain(t % sim.w, t / sim.w, r, 1), t])
			all.sort_custom(func(a, b): return a[0] > b[0])
			for k in mini(5, all.size()):
				if int(all[k][0]) > 0:
					_gain[all[k][1]] = all[k][0]
			_gain[-1] = 0   # worked out (even when nothing gains)
		for t in _gain:
			if t >= 0 and not skip.has(t):
				if raised: _lift_to(t % sim.w + 0.5, t / sim.w + 0.5)
				draw_circle(Vector2(t % sim.w + 0.5, t / sim.w + 0.5), 0.42, Color(0.95, 0.8, 0.3, 0.3))
				_tool_labels.append([Vector2(t % sim.w + 0.5, t / sim.w - 0.15), "+%d" % int(_gain[t]), Color("f2cf5a")])
	for t in _sites:
		if not skip.has(t):
			if raised: _lift_to(t % sim.w + 0.5, t / sim.w + 0.6)
			_site_icon(Vector2(t % sim.w + 0.5, t / sim.w + 0.72), String(_sites[t]))
			# while placing: a small pennant on the side its entrance (and flag) would be
			if placing:
				var dt2 := sim.door_at(t % sim.w, t / sim.w, door)
				if dt2 >= 0:
					var c0 := Vector2(t % sim.w + 0.5, t / sim.w + 0.5)
					var c1 := c0 + (Vector2(dt2 % sim.w + 0.5, dt2 / sim.w + 0.5) - c0) * 0.42
					draw_line(c1, c1 + Vector2(0, -0.26), Color(0.2, 0.15, 0.08, 0.9), 0.035)
					draw_colored_polygon(PackedVector2Array([c1 + Vector2(0, -0.26), c1 + Vector2(0.15, -0.2), c1 + Vector2(0, -0.14)]), Color(sim.players[0].color, 0.95))
	_unlift()


## How many tiles nobody owns yet a military building at (x, y) with radius r would claim for pid
## (every second tile counted, times four, so it is quick enough for many spots at once).
func land_gain(x: int, y: int, r: int, pid: int) -> int:
	var n := 0
	var r2 := r * r
	for dy in range(-r, r + 1, 2):
		for dx in range(-r, r + 1, 2):
			if dx * dx + dy * dy > r2 or not sim.inb(x + dx, y + dy):
				continue
			var o := sim.owner[sim.idx(x + dx, y + dy)]
			if o == 0:
				n += 4
	return n


# --- Day and night (an option in Settings; only looks, the game itself does not change) ----------------
const DAY_LENGTH := 480.0          # game seconds from one dawn to the next
var daynight := false


## Grass tufts, reeds, foam and snow baked into the ground (Settings); the chunks are baked again.
func set_details(on: bool) -> void:
	chunks.details = on
	if chunks.twin != null:
		chunks.twin.details = on
	chunks.mark_all()


## How dark it is now: 0 by day, 1 in the middle of the night; dusk and dawn in between.
func night_amount() -> float:
	if not daynight or sim == null:
		return 0.0
	var ph := fmod(sim.time / DAY_LENGTH, 1.0)
	return clampf(-cos(ph * TAU) * 1.6 - 0.45, 0.0, 1.0)


## A dark blue veil over the map at night (orange around dusk and dawn), and the lit windows of homes and
## workshops with people in them, and torches at military buildings.
func _draw_night(vis: Array, x0: int, y0: int, x1: int, y1: int) -> void:
	var n := night_amount()
	if n <= 0.0:
		return
	var area := Rect2(x0 - 2, y0 - 6, x1 - x0 + 5, y1 - y0 + 9)
	var dusk := sin(n * PI)
	draw_rect(area, Color(1.0, 0.55, 0.25, 0.10 * dusk))
	draw_rect(area, Color(0.04, 0.06, 0.17, 0.58 * n))
	if _glow == null:
		return
	for b: Sim.Bld in vis:
		if b.dead or b.state != "ready":
			continue
		var lit := b.def.has("housing") or b.def.has("residence") or b.ty == "hq" or (b.staffed and b.def.has("worker")) or sim.is_mil(b)
		if not lit:
			continue
		var art: Dictionary = b.def.get("art", {})
		var sw := float(art.get("sw", 2.0))
		var c := Vector2(b.x + 0.5, b.y + 0.55 - lift_at(b.x + 0.5, b.y + 0.9))
		# each window flickers a little, and some houses go dark late at night
		if b.def.has("housing") and _hash(b.id, int(sim.time / 30.0)) % 5 == 0 and n > 0.8:
			continue
		var fl := 0.85 + 0.15 * sin(sim.time * 3.0 + b.id * 1.7)
		var r := 0.34 * sw if not sim.is_mil(b) else 0.5
		draw_texture_rect(_glow, Rect2(c.x - r, c.y - r, r * 2.0, r * 2.0), false, Color(1.0, 0.78, 0.4, 0.75 * n * fl))
		draw_circle(c + Vector2(0.06, 0.05), minf(0.08, 0.04 * sw), Color(1.0, 0.85, 0.45, 0.9 * n))


## Where a road-carriers load is: Vector3(tile from, tile to, how far between them); z < 0 when it lies
## waiting at the flag (tile from) for the stretch's carrier.
var _leg_donkey := false     # set by _leg_pos: the load is on a donkey's back on this stretch

func _leg_pos(t: Sim.Trip) -> Vector3:
	var L := t.legs
	var now := sim.time
	var nl := L.size() / 4
	for k in nl:
		var ia := int(L[k * 4]); var ib := int(L[k * 4 + 1])
		_leg_donkey = ib >= SimLogistics.DONKEY_LEG
		ib = ib % SimLogistics.DONKEY_LEG
		var st := L[k * 4 + 2]; var en := L[k * 4 + 3]
		if now < st:
			return Vector3(t.path[ia], t.path[ia], -0.0001)
		if now < en:
			var f := (now - st) / maxf(0.01, en - st) * absi(ib - ia)
			var step := 1 if ib > ia else -1
			var j := mini(floori(f), absi(ib - ia) - 1)
			return Vector3(t.path[ia + j * step], t.path[ia + (j + 1) * step], f - j)
	var last := int(L[(nl - 1) * 4 + 1]) % SimLogistics.DONKEY_LEG
	_leg_donkey = false
	return Vector3(t.path[last], t.path[last], 0.0)


## A building-site marker, as in The Settlers: a small house, a bigger house, a castle, or a mine.
func _site_icon(c: Vector2, size: String) -> void:
	var gold := Color("f2cf5a")
	var edge := Color(0.18, 0.12, 0.04, 0.85)
	match size:
		"small", "medium":
			var s := 0.12 if size == "small" else 0.17
			var body := Rect2(c.x - s, c.y - s * 1.3, s * 2.0, s * 1.3)
			var roof := PackedVector2Array([Vector2(c.x - s * 1.3, c.y - s * 1.3), Vector2(c.x, c.y - s * 2.5), Vector2(c.x + s * 1.3, c.y - s * 1.3)])
			draw_rect(body.grow(0.025), edge)
			draw_colored_polygon(PackedVector2Array([roof[0] + Vector2(-0.04, 0.02), roof[1] + Vector2(0, -0.045), roof[2] + Vector2(0.04, 0.02)]), edge)
			draw_rect(body, gold)
			draw_colored_polygon(roof, gold.darkened(0.15))
		"large":
			var s := 0.2
			var body := Rect2(c.x - s * 1.2, c.y - s * 1.4, s * 2.4, s * 1.4)
			draw_rect(body.grow(0.025), edge)
			draw_rect(body, gold)
			for k in 3:
				var bx := c.x - s * 1.2 + k * s * 0.9
				draw_rect(Rect2(bx - 0.02, c.y - s * 1.85 - 0.02, s * 0.6 + 0.04, s * 0.5 + 0.03), edge)
				draw_rect(Rect2(bx, c.y - s * 1.85, s * 0.6, s * 0.5), gold)
		"mine":
			var s := 0.16
			var arch := PackedVector2Array([Vector2(c.x - s * 1.4, c.y), Vector2(c.x - s * 0.9, c.y - s * 1.7), Vector2(c.x + s * 0.9, c.y - s * 1.7), Vector2(c.x + s * 1.4, c.y)])
			draw_colored_polygon(PackedVector2Array([arch[0] + Vector2(-0.04, 0.02), arch[1] + Vector2(-0.02, -0.04), arch[2] + Vector2(0.02, -0.04), arch[3] + Vector2(0.04, 0.02)]), edge)
			draw_colored_polygon(arch, gold)
			draw_rect(Rect2(c.x - s * 0.45, c.y - s * 0.9, s * 0.9, s * 0.9), Color(0.15, 0.1, 0.05))


## A small flag in colour col on tile i: a building's entrance. warn adds a pulsing ring (no road yet).
func _door_flag(i: int, col: Color, warn: bool) -> void:
	var c := Vector2(i % sim.w + 0.5, i / sim.w + 0.62)
	if warn:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		draw_arc(c + Vector2(0, -0.05), 0.36 + 0.06 * pulse, 0, TAU, 24, Color(1.0, 0.85, 0.3, 0.55 + 0.4 * pulse), 0.06)
	draw_circle(c + Vector2(0, 0.02), 0.07, Color(0, 0, 0, 0.35))
	draw_line(c, c + Vector2(0, -0.42), Color("3a2a18"), 0.04)
	var fl := PackedVector2Array([c + Vector2(0.02, -0.42), c + Vector2(0.25, -0.35), c + Vector2(0.02, -0.28)])
	draw_colored_polygon(fl, col)
	fl.append(fl[0])
	draw_polyline(fl, Color(0, 0, 0, 0.5), 0.015)


## Draws frame f of an animated texture with its bottom centre at foot, wid tiles wide, mirrored when
## flip is true. Returns the height it was drawn at, so labels and loads can sit above it.
func _sprite(id: String, foot: Vector2, wid: float, f: int, flip: bool, col := Color.WHITE) -> float:
	var tex := Tex.get_tex(id)
	var src := Tex.frame_rect(id, f)
	var hgt := wid * src.size.y / maxf(1.0, src.size.x)
	var dst := Rect2(foot.x - wid / 2.0, foot.y - hgt, wid, hgt)
	if flip:
		# a rectangle with a negative width is drawn mirrored left to right
		dst = Rect2(foot.x + wid / 2.0, foot.y - hgt, -wid, hgt)
	if _batching:
		_batch_add(tex, dst, src, col)
	else:
		draw_texture_rect_region(tex, dst, src, col)
	return hgt


# Batching: while _batching is on, sprites are collected by layer and picture and drawn together at
# _flush_batches, so the renderer can send all the pictures of one kind in one go instead of switching
# pictures for every carrier (bodies first, then their colour and loads, then the goods they carry).
var _batching := false
var _batch_layer := 0
var _batches: Array = [{}, {}, {}]

func _batch_add(tex: Texture2D, dst: Rect2, src: Rect2, col: Color) -> void:
	var layer: Dictionary = _batches[_batch_layer]
	if not layer.has(tex):
		layer[tex] = []
	(layer[tex] as Array).append([dst, src, col])


func _flush_batches() -> void:
	_batching = false
	for layer: Dictionary in _batches:
		for tex: Texture2D in layer:
			for c: Array in layer[tex]:
				draw_texture_rect_region(tex, c[0], c[1], c[2])
		layer.clear()
	_batch_layer = 0


## A small marker under your building when its priority isn't normal: an orange arrow up for high,
## a grey arrow down for low, two bars for paused. It is drawn after the building, so it stays visible.
func _prio_badge(b: Sim.Bld) -> void:
	var c := Vector2(b.x + 0.14, b.y + 0.86)
	draw_circle(c, 0.17, Color(0, 0, 0, 0.7))
	match b.prio:
		Sim.PRIO_HIGH:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.12), c + Vector2(0.1, 0.07), c + Vector2(-0.1, 0.07)]), Color("f0a040"))
		Sim.PRIO_LOW:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0.12), c + Vector2(0.1, -0.07), c + Vector2(-0.1, -0.07)]), Color("a0b0c0"))
		Sim.PRIO_PAUSED:
			draw_rect(Rect2(c.x - 0.085, c.y - 0.09, 0.055, 0.18), Color("e0e0e0"))
			draw_rect(Rect2(c.x + 0.03, c.y - 0.09, 0.055, 0.18), Color("e0e0e0"))


## A point on a building's picture, given as fractions of its width and height.
func _anchor(rect: Rect2, uv: Array) -> Vector2:
	return rect.position + Vector2(float(uv[0]) * rect.size.x, float(uv[1]) * rect.size.y)


## Puffs of smoke rising from p and drifting with the wind; seed keeps chimneys out of step.
func _smoke_at(p: Vector2, seed: float, strength: float) -> void:
	for i in 4:
		var ph := fposmod(sim.time * 0.35 + i * 0.25 + seed, 1.0)
		var c := p + Vector2(sin(ph * 5.0 + seed * 7.0) * 0.06 + ph * 0.35, -ph * 0.95)
		var r := 0.1 + ph * 0.25
		draw_texture_rect(_smoke, Rect2(c.x - r, c.y - r, r * 2.0, r * 2.0), false, Color(1, 1, 1, (1.0 - ph) * 0.9 * strength))


## A building's picture in the look of age era (built-in or your own; see Tex.bld_era_tex).
func bld_texture(ty: String, era: int) -> Texture2D:
	var list: Array = _era_tex.get(ty, [])
	if list.is_empty():
		for e in 6:
			list.append(Tex.bld_era_tex(GameData.bld_tex_id(ty), e))
		_era_tex[ty] = list
	return list[clampi(era, 0, 5)] if era >= 0 else _bld_tex.get(ty, Tex.placeholder())


func _draw_building(b: Sim.Bld, labels: Array, detail: bool) -> void:
	# a site is drawn in the look it will have: its realm's age when it was placed
	var tex: Texture2D = bld_texture(b.ty, b.era)
	var art: Dictionary = b.def.get("art", {})
	var style := String(art.get("style", "house"))
	var sw := float(art.get("sw", 2.0))
	var hgt := sw * tex.get_height() / maxf(1.0, tex.get_width())
	var rect := Rect2(b.x + 0.5 - sw / 2.0, b.y + 1.0 - hgt, sw, hgt)
	var pc: Color = sim.players[b.p - 1].color
	var anchors: Dictionary = ANCHORS.get(style, {})
	if b.state == "build":
		# the building rises from the ground as work progresses, inside a scaffold
		var p := clampf(b.prog, 0.0, 1.0)
		draw_texture_rect(tex, rect, false, Color(1, 1, 1, 0.22))
		var th := float(tex.get_height())
		draw_texture_rect_region(tex, Rect2(rect.position.x, rect.end.y - rect.size.y * p, rect.size.x, rect.size.y * p),
			Rect2(0, th * (1.0 - p), tex.get_width(), th * p))
		var cs := minf(sw, 1.6)
		draw_texture_rect(_constr, Rect2(b.x + 0.5 - cs / 2.0, b.y + 1.0 - cs, cs, cs), false)
		if detail and b.builder == 2:
			var beat := int(sim.time * 4.0 + b.id)
			_sprite("unit_worker_hammer", Vector2(b.x + 0.12, b.y + 1.0), 0.4, 4 + beat % 2, false, pc.lightened(0.35))
		# materials lying at the site, waiting to be used
		if zoom >= 18.0 and not b.onsite.is_empty():
			var k := 0
			for r in b.onsite:
				if _res_tex.has(r) and k < 3:
					draw_texture_rect(_res_tex[r], Rect2(b.x - 0.05 + k * 0.24, b.y + 0.66, 0.3, 0.3), false)
					k += 1
		draw_rect(Rect2(b.x, b.y + 1.02, 1.0, 0.1), Color(0, 0, 0, 0.6))
		if b.mat_total > 0:
			draw_rect(Rect2(b.x, b.y + 1.02, float(b.mat_used + _count(b.onsite)) / b.mat_total, 0.1), Color(0.55, 0.45, 0.3, 0.9))
		draw_rect(Rect2(b.x, b.y + 1.02, b.prog, 0.1), Color("d8aa4a"))
		if b.p == 1 and b.prio != Sim.PRIO_NORMAL:
			_prio_badge(b)
		return
	if detail and ANIMALS.has(b.ty):
		_draw_animals(b, String(ANIMALS[b.ty]), true)
	draw_texture_rect(tex, rect, false)
	if detail and ANIMALS.has(b.ty):
		_draw_animals(b, String(ANIMALS[b.ty]), false)
	if b.reno_to >= 0:
		# renovation: scaffolding over the building, the new look rising behind it
		var ntex := bld_texture(b.ty, b.reno_to)
		var th := float(ntex.get_height())
		var rp := clampf(b.reno_prog, 0.0, 1.0)
		var nh := sw * th / maxf(1.0, ntex.get_width())
		var nrect := Rect2(b.x + 0.5 - sw / 2.0, b.y + 1.0 - nh, sw, nh)
		draw_texture_rect_region(ntex, Rect2(nrect.position.x, nrect.end.y - nrect.size.y * rp, nrect.size.x, nrect.size.y * rp), Rect2(0, th * (1.0 - rp), ntex.get_width(), th * rp))
		var cs := minf(sw, 1.6)
		draw_texture_rect(_constr, Rect2(b.x + 0.5 - cs / 2.0, b.y + 1.0 - cs, cs, cs), false, Color(1, 1, 1, 0.85))
		draw_rect(Rect2(b.x, b.y + 1.02, 1.0, 0.1), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(b.x, b.y + 1.02, rp, 0.1), Color("9fd0e8"))
	# moving parts: windmill sails, furnace glow and chimney smoke
	var hub: Array = art.get("hub", anchors.get("hub", []))
	if hub.size() == 2:
		var turn := sim.time * 1.6 if b.working and animate else float(b.id)
		var hp := _anchor(rect, hub)
		var ss := sw * 0.9
		draw_set_transform(_origin + hp * zoom, turn, Vector2(zoom, zoom))
		draw_texture_rect(_sails, Rect2(-ss / 2.0, -ss / 2.0, ss, ss), false)
		draw_set_transform(_origin, 0.0, Vector2(zoom, zoom))
	if detail:
		var glow: Array = art.get("glow", anchors.get("glow", []))
		if glow.size() == 2 and b.working:
			var fl := 0.65 + 0.35 * sin(sim.time * 13.0 + b.id) * sin(sim.time * 7.3)
			var gp := _anchor(rect, glow)
			var gr := 0.28 * sw / 2.0
			draw_texture_rect(_glow, Rect2(gp.x - gr, gp.y - gr, gr * 2.0, gr * 2.0), false, Color(1, 1, 1, fl))
		var smoke: Array = art.get("smoke", anchors.get("smoke", []))
		if smoke.size() == 2 and (b.working or (style in HOME_SMOKE and b.state == "ready")):
			_smoke_at(_anchor(rect, smoke), b.id * 0.137, 1.0 if b.working else 0.5)
		_draw_worker(b, pc)
	# a catapult's stone in flight, and dust where it lands
	if b.def.has("siege") and b.target >= 0:
		var tp := Vector2(b.target % sim.w + 0.5, b.target / sim.w + 0.4)
		var sp := Vector2(b.x + 0.3, b.y + 0.1)
		if b.working:
			var u := sim.work_progress(b)
			if u > 0.8:
				var f := (u - 0.8) / 0.2
				var pos := sp.lerp(tp, f) + Vector2(0, -sin(f * PI) * maxf(2.0, sp.distance_to(tp) * 0.35))
				draw_circle(pos, 0.12, Color(0.6, 0.6, 0.56))
				draw_circle(pos + Vector2(-0.03, -0.03), 0.05, Color(0.8, 0.8, 0.76))
		var since := sim.time - b.sxp
		if b.sxp > 0.0 and since < 0.8:
			for k in 5:
				var ang := k * 1.3 + b.id
				draw_circle(tp + Vector2(cos(ang), sin(ang) * 0.5) * (0.2 + since * 0.6), 0.14 + since * 0.15, Color(0.75, 0.7, 0.6, 0.7 * (1.0 - since / 0.8)))
	var ff := int(sim.time * 5.0 + b.id) if animate else 0
	_sprite("unit_flag", Vector2(rect.position.x + rect.size.x * 0.85, rect.position.y + rect.size.y * _tex_top(tex) + 0.17), 0.3, ff, false, pc)
	if b.working and b.cyc > 0.0:
		draw_rect(Rect2(b.x + 0.1, b.y + 1.02, 0.8, 0.08), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(b.x + 0.1, b.y + 1.02, 0.8 * sim.work_progress(b), 0.08), Color("86ad5c"))
	elif b.p == 1 and b.cyc > 0.0 and b.msg != "" and b.msg != "Working":
		draw_circle(Vector2(rect.position.x + 0.1, rect.position.y + 0.2), 0.14, Color("e0603a"))
	var waiting := 0
	for r in b.out_buf:
		waiting += int(b.out_buf[r])
	if waiting > 0 and zoom >= 18.0:
		var first: String = b.out_buf.keys()[0]
		if _res_tex.has(first):
			draw_texture_rect(_res_tex[first], Rect2(b.x + 0.62, b.y + 0.55, 0.36, 0.36), false)
	if sim.is_mil(b):
		labels.append([Vector2(b.x + 0.5, rect.position.y - 0.05), str(sim.own_def(b)), pc.lightened(0.5)])
	if b.p == 1 and b.prio != Sim.PRIO_NORMAL:
		_prio_badge(b)


## An outdoor worker: walks out to the tree, rock, clay or water, works there, and walks home with
## what he got. How far the work cycle has got decides which part of the trip he is on.
func _draw_worker(b: Sim.Bld, pc: Color) -> void:
	var act := String(b.def.get("act", ""))
	if not b.working or b.target < 0 or not TOOL.has(act):
		return
	var id := "unit_worker_" + String(TOOL[act])
	var total := b.cyc + sim.walk_time(b)
	var k := sim.work_progress(b) * total
	var home := Vector2(b.x + 0.5, b.y + 1.05)
	var tgt := Vector2(b.target % sim.w + 0.5, b.target / sim.w + 0.9)
	var dist := home.distance_to(tgt)
	if dist < 0.5:
		return
	# he works standing a little short of the target, facing it; a fisher stays on the shore
	var spot := tgt + (home - tgt).normalized() * 0.45
	if act == "fish":
		var step := (home - spot).normalized() * 0.25
		for n in 40:
			var i := sim.idx(int(spot.x), int(spot.y - 0.3))
			if sim.ter[i] != 0 or spot.distance_to(home) < 0.3:
				break
			spot += step
	var walk := minf((dist - 0.45) * 0.5, total * 0.3)
	var col := pc.lightened(0.25)
	# detailed strips: 8 walking frames, working at 8 and 9; an older 6-frame picture walks on 4
	var nf := Tex.frames(id)
	var nw := 8 if nf >= 10 else 4
	if k < walk:
		var p := spot.lerp(home, 1.0 - k / walk)
		_person(id, p, int(home.distance_to(p) * 8.0) % nw, spot.x < home.x, col)
	elif k > total - walk:
		var p2 := spot.lerp(home, (k - (total - walk)) / walk)
		var hh := _person(id, p2, int(spot.distance_to(p2) * 8.0) % nw, home.x < spot.x, col)
		var outs: Dictionary = b.def.get("out", {})
		if outs.size() > 0 and _res_tex.has(outs.keys()[0]):
			draw_texture_rect(_res_tex[outs.keys()[0]], Rect2(p2.x - 0.13, p2.y - hh - 0.2, 0.26, 0.26), false)
	else:
		_person(id, spot, nw + int(sim.time * 3.0 + b.id) % 2, tgt.x < spot.x, col)


## A worker: the picture as it is, then the tunic in the realm's colour (an older single-layer picture
## is tinted whole, as before). Returns the drawn height.
func _person(id: String, at: Vector2, f: int, flip: bool, col: Color) -> float:
	if Tex.frames(id) >= 10:
		var hh := _sprite(id, at, 0.4, f, flip)
		if Tex.frames(id + "_tint") == Tex.frames(id):
			_batch_layer = 1
			_sprite(id + "_tint", at, 0.4, f, flip, col)
			_batch_layer = 0
		return hh
	return _sprite(id, at, 0.4, f, flip, col.lightened(0.1))


## Which load picture an ox cart carrying goods res shows.
func _load_kind(res: String) -> String:
	match res:
		"planks", "wood": return "planks" if res == "planks" else "wood"
		"stone", "bricks", "granite", "marble", "ore_iron", "ore_gold", "ore_copper", "coal", "clay", "sand": return "stone"
		"grain", "flour", "wool", "flax", "hops", "salt", "herbs", "malt": return "grain"
	return "crates"


## Animals grazing around a farm. Those behind the farm are drawn before it and those in front after,
## so the farm hides the ones walking behind it.
func _draw_animals(b: Sim.Bld, id: String, behind: bool) -> void:
	for i in 3:
		var a := sim.time * 0.25 * (1.0 + i * 0.3) + i * 2.1 + b.id
		if (sin(a) < 0.0) != behind:
			continue
		var p := Vector2(b.x + 0.5 + cos(a) * 0.75, b.y + 0.95 + sin(a) * 0.25)
		_sprite(id, p, 0.32, int(sim.time * 5.0) + i, sin(a) > 0.0, Color.WHITE)


static func _count(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


## A building as last seen through the fog: its picture, slightly faded, with a scaffold if it was
## still being built.
func draw_ghost(ty: String, x: int, y: int, col: Color, building: bool, era := 1) -> void:
	var tex: Texture2D = bld_texture(ty, era)
	if tex == null:
		return
	var art: Dictionary = GameData.bld.get(ty, {}).get("art", {})
	var sw := float(art.get("sw", 2.0))
	var hgt := sw * tex.get_height() / maxf(1.0, tex.get_width())
	var rect := Rect2(x + 0.5 - sw / 2.0, y + 1.0 - hgt - lift_at(x + 0.5, y + 0.9), sw, hgt)
	draw_texture_rect(tex, rect, false, Color(0.85, 0.85, 0.85, 0.45 if building else 0.95))
	if building:
		var cs := minf(sw, 1.6)
		draw_texture_rect(_constr, Rect2(x + 0.5 - cs / 2.0, rect.end.y - cs, cs, cs), false)
	_sprite("unit_flag", Vector2(rect.position.x + rect.size.x * 0.85, rect.position.y + rect.size.y * _tex_top(tex) + 0.17), 0.3, 0, false, col.darkened(0.2))


var _tops := {}   # texture -> how far down (0 to 1) its picture really starts

## Where the drawing in a building picture starts, as a fraction of its height: the building's flag
## stands there, on the roof, and not at the top of the picture's empty margin.
func _tex_top(tex: Texture2D) -> float:
	var k := tex.get_rid()
	if _tops.has(k):
		return _tops[k]
	var top := 0.0
	var img := tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var used := img.get_used_rect()
		if img.get_height() > 0 and used.size.y > 0:
			top = float(used.position.y) / img.get_height()
	_tops[k] = top
	return top


## The soldier picture for soldiers of average age era (legionary ... rifleman).
static func _soldier_id(era: float) -> String:
	return "unit_soldier_e%d" % clampi(roundi(era), 0, 5)


# ---------------------------------------------------------------- townsfolk

const FOLK_KINDS := ["peasant", "woman", "artisan", "noble"]


## Straight runs of realm p's road (3 tiles or more) within 5 tiles of house b, nearest first.
func _road_runs(b: Sim.Bld) -> Array:
	var c: Array = _folk_roads.get(b.id, [])
	if not c.is_empty() and sim.time - float(c[0]) < 20.0 and sim.time >= float(c[0]):
		return c[1]
	var runs := []
	var w := sim.w
	var r := 5
	for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
		for y in range(maxi(0, b.y - r), mini(sim.h - 1, b.y + r) + 1):
			for x in range(maxi(0, b.x - r), mini(w - 1, b.x + r) + 1):
				if sim.road[y * w + x] != b.p:
					continue
				var px := x - dir.x
				var py := y - dir.y
				if px >= 0 and py >= 0 and sim.road[py * w + px] == b.p and absi(px - b.x) <= r and absi(py - b.y) <= r:
					continue    # not the start of a run
				var n := 1
				while true:
					var nx := x + dir.x * n
					var ny := y + dir.y * n
					if nx >= w or ny >= sim.h or absi(nx - b.x) > r or absi(ny - b.y) > r or sim.road[ny * w + nx] != b.p:
						break
					n += 1
				if n >= 3:
					runs.append([Vector2(x, y), Vector2(x + dir.x * (n - 1), y + dir.y * (n - 1))])
	runs.sort_custom(func(a1, a2): return (a1[0] + a1[1]).distance_to(Vector2(b.x, b.y) * 2.0) < (a2[0] + a2[1]).distance_to(Vector2(b.x, b.y) * 2.0))
	runs = runs.slice(0, 6)
	_folk_roads[b.id] = [sim.time, runs]
	return runs


## A small number from a few others, the same every frame (so a person keeps their looks).
static func _hash(a: int, b: int) -> int:
	return absi((a * 73856093) ^ (b * 19349663)) % 1000


## People out and about: walking the roads near their homes, chatting at the door, children playing,
## and newcomers on their way to headquarters. They are only for show: the game doesn't move them.
func _collect_folk(vis: Array) -> Array:
	_folk = []
	var count := 0
	var t := sim.time
	var pops := {}    # realm id -> [people, room in the houses], worked out once a frame
	for b: Sim.Bld in vis:
		if count > 140:
			break
		if b.state != "ready":
			continue
		var p: Sim.Player = sim.players[b.p - 1]
		if b.ty != "hq" and not b.def.has("housing"):
			continue
		if not pops.has(p.id):
			pops[p.id] = [sim.pop_total(p), sim.housing(p)]
		var people: int = pops[p.id][0]
		if b.ty == "hq":
			if people < int(pops[p.id][1]):
				_draw_newcomer(b)
			continue
		var ratio := clampf(float(people) / maxf(1.0, float(pops[p.id][1])), 0.0, 1.0)
		var door := Vector2(b.x + 0.5, b.y + 1.12)
		# walkers along the roads nearby
		var runs := _road_runs(b)
		var walkers := roundi(2.0 * ratio) if not runs.is_empty() else 0
		for j in walkers:
			var run: Array = runs[(b.id + j * 3) % runs.size()]
			var a: Vector2 = run[0] + Vector2(0.5, 0.82)
			var e: Vector2 = run[1] + Vector2(0.5, 0.82)
			var length := a.distance_to(e)
			var period := 3.0 + length * 1.4
			var u := fmod(t + b.id * 1.7 + j * 2.9, period * 2.0) / period
			var back := u > 1.0
			var f := u - 1.0 if back else u
			var pos := e.lerp(a, f) if back else a.lerp(e, f)
			var kind := _folk_kind(p, b.id * 5 + j)
			var going := (e - a) * (-1.0 if back else 1.0)
			_folk_add("unit_folk_" + kind, pos, 0.4, int(f * length * 8.0) % 8, going.x < 0 or (going.x == 0 and back))
			count += 1
		# two neighbours chatting at the door, now and then
		if b.id % 3 == 0 and int((t + b.id) / 9.0) % 5 < 3 and ratio > 0.3:
			var k1 := _folk_kind(p, b.id * 11)
			var k2 := _folk_kind(p, b.id * 13 + 1)
			_folk_add("unit_folk_" + k1, door + Vector2(-0.3, 0.05), 0.38, 8 + int(t * 2.0 + b.id) % 2, false)
			_folk_add("unit_folk_" + k2, door + Vector2(0.3, 0.08), 0.38, 10 if int(t / 3.0 + b.id) % 2 == 0 else 8 + int(t * 2.0) % 2, true)
			count += 2
		# children running round the house
		if b.id % 2 == 1 and people >= 20:
			for j in 2:
				var ang := t * 1.6 + j * 2.4 + b.id
				var at := door + Vector2(cos(ang) * 0.75, sin(ang) * 0.22 + 0.05)
				_folk_add("unit_folk_child", at, 0.3, int(t * 10.0 + j * 3) % 8, sin(ang) > 0.0)
				count += 1
	_folk.sort_custom(func(a1, a2): return float(a1[0]) < float(a2[0]))
	return _folk


var _folk: Array = []


func _folk_add(id: String, pos: Vector2, wid: float, f: int, flip: bool) -> void:
	_folk.append([pos.y, id, pos, wid, f, flip])


func _draw_folk_one(e: Array) -> void:
	var at: Vector2 = e[2]
	if raised:
		at.y -= lift_at(at.x, at.y)
	_sprite(String(e[1]), at, float(e[3]), int(e[4]), bool(e[5]))


func _folk_kind(p: Sim.Player, seed: int) -> String:
	var h := _hash(seed, p.id) % 100
	if p.noble > 0 and h < 8:
		return "noble"
	if p.artisan > 0 and h < 30:
		return "artisan"
	return "woman" if h % 2 == 0 else "peasant"


## A newcomer with a bundle on his head walking in to headquarters while there is room in the houses.
func _draw_newcomer(hq: Sim.Bld) -> void:
	var cyc := 24.0
	var n := floori(sim.time / cyc)
	var u := fmod(sim.time, cyc) / 14.0
	if u > 1.0:
		return
	var ang := float(_hash(n, hq.id)) / 1000.0 * TAU
	var door := Vector2(hq.x + 0.5, hq.y + 1.2)
	var from := door + Vector2(cos(ang), sin(ang) * 0.6) * 7.0
	var pos := from.lerp(door, u)
	_folk_add("unit_folk_newcomer", pos, 0.4, int(u * 7.0 * 8.0) % 8, door.x < from.x)


# --- Scenery standing on the map -------------------------------------------------------------------
# Trees, mountain peaks and boulders stand upright at the height of the ground under their foot. They
# are not baked into the ground pictures, where the raised ground would bend and stretch them. Each
# chunk's scenery is one mesh of upright pictures from one atlas, made when the chunk changes, so
# thousands of trees cost a few draw calls a frame. Each object is a little bigger or smaller, a little
# lighter or darker and a little off the tile's centre (from a hash of its tile), and woods keep to one
# kind of tree in patches (firs here, broad-leaved trees there), so forests don't look stamped.

const SCENERY := ["deco_tree_0", "deco_tree_1", "deco_tree_2", "deco_tree_3", "deco_tree_4",
	"deco_peak_0", "deco_peak_1", "deco_rock_0", "deco_rock_1"]
const SCN_PX := 64                 # atlas pixels per tile
const SCN_PEAK := 5
const SCN_ROCK := 7


func _make_scenery_atlas() -> void:
	var n := SCENERY.size()
	var cw := SCN_PX + 4
	var chh := SCN_PX * 3 / 2 + 4
	var img := Image.create(cw * n, chh, false, Image.FORMAT_RGBA8)
	_scn_size = []
	for k in n:
		var id: String = SCENERY[k]
		var tall := not id.begins_with("deco_rock")
		var tw := SCN_PX
		var th := SCN_PX * 3 / 2 if tall else SCN_PX
		var t := Tex.get_tex(id)
		var src: Image = t.get_image() if t != null else null
		if src == null:
			src = Image.create(tw, th, false, Image.FORMAT_RGBA8)
		else:
			src = src.duplicate()
			if src.is_compressed():
				src.decompress()
			src.clear_mipmaps()
			src.convert(Image.FORMAT_RGBA8)
		if src.get_width() != tw or src.get_height() != th:
			src.resize(tw, th, Image.INTERPOLATE_LANCZOS if src.get_width() > tw else Image.INTERPOLATE_BILINEAR)
		var at := Vector2i(k * cw + 2, chh - 2 - th)
		img.blit_rect(src, Rect2i(0, 0, tw, th), at)
		var isz := Vector2(img.get_size())
		_scn_size.append([Rect2(Vector2(at) / isz, Vector2(tw, th) / isz), Vector2(1.0, float(th) / SCN_PX)])
	img.fix_alpha_edges()
	img.generate_mipmaps()
	_scn_atlas = ImageTexture.create_from_image(img)
	_scn_mesh = {}


## Which picture stands on tile (x, y), or -1: a tree, a peak (on mountain inside a range) or a boulder.
func _scenery_kind(x: int, y: int, i: int) -> int:
	var d := sim.deco[i]
	if d == Sim.D_TREE:
		# patches of woods about five tiles across lean to firs or to broad-leaved trees
		var patch := MapChunks._hash(x / 5 + 101, y / 5 + 37)
		var hh := MapChunks._hash(x, y)
		if patch % 3 == 0:
			return [0, 3, 0, 3, 1][hh % 5]
		return [1, 4, 2, 1, 4, 0][hh % 6]
	if d == Sim.D_ROCK:
		return SCN_ROCK + (x + y) % 2
	if d == 0 and chunks._has_peak(x, y, i):
		return SCN_PEAK + (x + y) % 2
	return -1


func _scenery_mesh(cx: int, cy: int) -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var CHN := MapChunks.CH
	for ly in CHN:
		var y := cy * CHN + ly
		if y >= sim.h:
			break
		for lx in CHN:
			var x := cx * CHN + lx
			if x >= sim.w:
				break
			var i := y * sim.w + x
			var k := _scenery_kind(x, y, i)
			if k < 0:
				continue
			var hh := MapChunks._hash(x, y)
			var sc := 1.0
			var off := Vector2.ZERO
			if k < SCN_PEAK:
				sc = 0.9 + float(hh % 25) / 100.0
				off = Vector2(float((hh >> 5) % 21 - 10), float((hh >> 10) % 11 - 5)) / 100.0
			elif k < SCN_ROCK:
				sc = 1.0 + float(hh % 13) / 100.0
			else:
				sc = 0.85 + float(hh % 21) / 100.0
				off = Vector2(float((hh >> 5) % 13 - 6), 0.0) / 100.0
			var cell: Array = _scn_size[k]
			var uv: Rect2 = cell[0]
			var sz: Vector2 = (cell[1] as Vector2) * sc
			var foot := Vector2(x + 0.5, y + 1.0) + off
			var lift := lift_at(foot.x, foot.y - 0.2) if raised else 0.0
			var tl := Vector2(foot.x - sz.x / 2.0, foot.y - sz.y - lift)
			var n := verts.size()
			verts.append_array(PackedVector2Array([tl, tl + Vector2(sz.x, 0), tl + sz, tl + Vector2(0, sz.y)]))
			uvs.append_array(PackedVector2Array([uv.position, uv.position + Vector2(uv.size.x, 0), uv.end, uv.position + Vector2(0, uv.size.y)]))
			var b := 0.9 + float((hh >> 3) % 15) / 100.0
			var c := Color(b, b, b)
			cols.append_array(PackedColorArray([c, c, c, c]))
			idx.append_array(PackedInt32Array([n, n + 1, n + 2, n, n + 2, n + 3]))
	if verts.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Draws the scenery of the chunks in view, top row first so what stands lower down is in front.
## Meshes missing or out of date are made while time is left this frame (2 ms, at least one).
func _draw_scenery(x0: int, x1: int, y0: int, y1: int) -> void:
	if _scn_atlas == null:
		_make_scenery_atlas()
	if _scn_ver != chunks.ver:
		_scn_ver = chunks.ver
		_scn_mesh = {}
	var CHN := MapChunks.CH
	var deadline := Time.get_ticks_usec() + 2000
	var made := 0
	for cy in range(y0 / CHN, mini(sim.h - 1, y1 + 2) / CHN + 1):
		for cx in range(x0 / CHN, x1 / CHN + 1):
			var k := cy * 1000 + cx
			if not _scn_mesh.has(k):
				if made > 0 and Time.get_ticks_usec() > deadline:
					continue
				_scn_mesh[k] = _scenery_mesh(cx, cy)
				made += 1
			var m: ArrayMesh = _scn_mesh[k]
			if m != null:
				draw_mesh(m, _scn_atlas)
