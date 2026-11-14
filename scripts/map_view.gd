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

const DETAIL_ZOOM := 10.0        # below this many pixels per tile, people and goods are drawn as dots
const FAR_ZOOM := 10.0           # below this, the ground comes from chunks baked at a quarter resolution
const SCENERY_ZOOM := 7.0        # below this, trees are baked into the ground instead of drawn one by one
const ANIM_ZOOM := 14.0          # below this, small details (smoke, workers, animals) are skipped
const LORES_ZOOM := 16.0         # below this, the ground comes from chunks baked at half resolution
const HIRES_ZOOM := 36.0         # from this on, from chunks baked at double resolution (64 pixels a tile)
## Tools that outdoor workers carry, by the building's "act".
const TOOL := {"cut_tree": "axe", "cut_rock": "pick", "dig_clay": "shovel", "fish": "rod", "plant": "seed", "farm": "seed"}
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
var editor_animals: Array = []      # animals placed in the map editor: [kind, x, y]
var editor_brush := 1          # the map editor's brush size, drawn around the mouse
var editor_round := false      # a round brush
var editor_mirror := "off"     # the brush also paints mirrored (EditorTools.MIRRORS)
var editor_line: Array = []    # a river being drawn: [from, to]
var editor_rect := Rect2i()    # an area being copied
var editor_paste := Vector2i.ZERO  # the size of the copied area, outlined at the mouse for pasting
var editor_climate := false    # the painted climate shown over the map
const CLIMATE_COL := [Color(0, 0, 0, 0), Color(0.45, 0.85, 0.3, 0.38), Color(0.35, 0.7, 1.0, 0.42), Color(1.0, 0.75, 0.25, 0.42), Color(0.15, 0.55, 0.5, 0.48)]
var _clim_img: Image
var _clim_tex: ImageTexture
var _clim_dirty := false
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
var _site_new := {}               # the marks being worked out (a few rows a frame)
var _site_row := -1               # the next row to work out (-1: done)
var _site_rect := Rect2i()
var _gain_todo: Array = []        # spots still to count land for (the "+N" marks)
var _gain_all: Array = []
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
var _sway_mat: ShaderMaterial      # the map view's own shader (swaying trees and crops)
var _shadow: Texture2D             # a soft dark ellipse, laid under buildings, people and trees
const SWAY_TREE := 3.0 / 255.0     # colour alphas the sway shader recognises (see map_sway.gdshader)
const SWAY_CROP := 5.0 / 255.0
const SUN := Vector2(0.16, 0.04)   # shadows fall a little to the right: the sun stands to the upper left
var _origin := Vector2.ZERO
var _folk_roads: Dictionary = {}   # house id -> [game time worked out, straight runs of road nearby: [from, to]]
var _vary: ImageTexture            # ground variation (see _make_variation)
var traffic_ui = null             # the traffic map (UiTraffic), drawn over the roads when on
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
		_ground_mat.set_shader_parameter("raised", false)
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
	_make_lift_map()


## The corner lifts as a picture for the ground shader (which finds the flat map position with it).
func _make_lift_map() -> void:
	var W := sim.w + 1
	var H := sim.h + 1
	var data := PackedByteArray()
	data.resize(W * H)
	for k in W * H:
		data[k] = clampi(int(round(_lift[k] / 4.0 * 255.0)), 0, 255)
	var img := Image.create_from_data(W, H, false, Image.FORMAT_R8, data)
	_ground_mat.set_shader_parameter("lift_map", ImageTexture.create_from_image(img))
	_ground_mat.set_shader_parameter("raised", raised)


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


## The seasons' tints are laid on by the ground shader (see ground.gdshader); the seasons feature
## hands them over each frame it draws. params: tint0..3, autumn_col, green_col, snow_amt, ice_col.
var _season_on := false

func set_season(mask: Texture2D, ice: Texture2D, params: Dictionary) -> void:
	_season_on = true
	_ground_mat.set_shader_parameter("season_mask", mask)
	_ground_mat.set_shader_parameter("ice_mask", ice)
	_ground_mat.set_shader_parameter("map_size", Vector2(sim.w, sim.h))
	for k in params:
		_ground_mat.set_shader_parameter(k, params[k])


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
	# the map's own shader: trees and crops sway in the wind (see shaders/map_sway.gdshader)
	_sway_mat = ShaderMaterial.new()
	_sway_mat.shader = load("res://shaders/map_sway.gdshader")
	material = _sway_mat
	_shadow = _make_shadow()
	set_smooth(true)
	refresh_textures()


## How hard the wind blows where you are looking (the weather there): trees and crops sway with it.
const WIND := {"storm": 2.6, "blizzard": 2.8, "rain": 1.5, "snow": 1.2, "cloudy": 1.1, "fog": 0.35, "heat": 0.5, "clear": 0.8}

func _wind() -> float:
	if sim == null or sim.w == 0:
		return 1.0
	var s = sim.get_feature("seasons")
	if s == null:
		return 0.9
	var b: int = s.biome_at(clampi(int(cam.x), 0, sim.w - 1), clampi(int(cam.y), 0, sim.h - 1))
	if b < 0 or b >= (s.weather as Array).size():
		return 0.9
	return float(WIND.get(String(s.weather[b]), 1.0))


## Birds: a few small flocks crossing the view in V shapes, flapping now and then and gliding in
## between (fewer in rain, none in a storm or snow). Only for the eye: they follow the clock.
func _draw_birds(x0: int, y0: int, x1: int, y1: int) -> void:
	var cl := _cloudiness()
	var wnd := _wind()
	if wnd >= 2.0 or cl >= 0.95:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var view := Rect2(x0, y0, x1 - x0, y1 - y0)
	var span := view.size.length() + 16.0
	var flocks := 2 if cl < 0.6 else 1
	for k in flocks:
		var period := 26.0 + k * 9.0
		var cyc := floori((t + k * 11.0) / period)
		var f := fmod(t + k * 11.0, period) / period
		var hh := MapChunks._hash(cyc * 7 + k, 913)
		if hh % 3 == 0:
			continue                  # now and then the sky stays empty
		var ang := float(hh % 628) / 100.0
		var dir := Vector2(cos(ang), sin(ang) * 0.6).normalized()
		var side := Vector2(-dir.y, dir.x)
		var mid := view.get_center() + side * (float((hh >> 8) % 100) / 100.0 - 0.5) * view.size.y * 0.7
		var lead := mid + dir * (f - 0.5) * span
		var n := 3 + (hh >> 4) % 5
		var sz := clampf(7.0 / zoom, 0.12, 0.45)
		for i in n:
			var row := (i + 1) / 2
			var lr := -1.0 if i % 2 == 1 else 1.0
			var p := lead - dir * row * sz * 2.6 + side * lr * row * sz * 2.0
			p += Vector2(sin(t * 0.9 + i * 1.7), cos(t * 1.1 + i)) * sz * 0.4
			# flap for a while, then glide
			var flap := sin(t * 11.0 + i * 0.9) if fmod(t + i * 0.37, 3.0) < 1.6 else 0.25
			var wing := Vector2(sz, -sz * 0.55 * flap)
			var col := Color(0.12, 0.12, 0.14, 0.85)
			draw_polyline(PackedVector2Array([p - Vector2(wing.x, wing.y), p + Vector2(0, sz * 0.1), p + Vector2(wing.x, -wing.y)]), col, sz * 0.22)
			# its shadow far below on the ground
			draw_circle(p + Vector2(sz * 6.0, sz * 9.0), sz * 0.35, Color(0, 0, 0, 0.12))


## How cloudy it is where you are looking: 0 clear .. 1 overcast (cloud shadows on the ground).
const CLOUDS := {"clear": 0.12, "heat": 0.0, "cloudy": 0.7, "rain": 0.9, "storm": 1.0, "snow": 0.8, "blizzard": 1.0, "fog": 0.5}

func _cloudiness() -> float:
	if sim == null or sim.w == 0:
		return 0.2
	var s = sim.get_feature("seasons")
	if s == null:
		return 0.25
	var b: int = s.biome_at(clampi(int(cam.x), 0, sim.w - 1), clampi(int(cam.y), 0, sim.h - 1))
	if b < 0 or b >= (s.weather as Array).size():
		return 0.25
	return float(CLOUDS.get(String(s.weather[b]), 0.3))


## A soft shadow: dark in the middle, fading out to the edge, twice as wide as high.
static func _make_shadow() -> Texture2D:
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 64:
			var d := Vector2((x + 0.5 - 32.0) / 32.0, (y + 0.5 - 16.0) / 16.0).length()
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.02, 0.03, 0.02, pow(a, 1.2) * 0.5))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _process(_delta: float) -> void:
	_ground.queue_redraw()
	if _sway_mat != null:
		var wnd := _wind()
		_sway_mat.set_shader_parameter("animate", animate)
		_sway_mat.set_shader_parameter("wind", wnd)
		_ground_mat.set_shader_parameter("clouds", _cloudiness() if animate else 0.0)
		_ground_mat.set_shader_parameter("drift", Vector2(0.3, 0.1) * maxf(0.5, wnd))
	if follow != null:
		var fp := follow_pos()
		if fp.x < 0.0:
			follow = null
			following_ended.emit()
		else:
			cam = fp
			_clamp()


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
	_make_relief_map()


## The hills' light and shade, one pixel a tile, for the ground shader: the slope towards the light
## (from the upper left) plus a little for height, as -1..1 stored as 0..255 (128 flat).
func _make_relief_map() -> void:
	if sim.height.size() != sim.w * sim.h:
		_ground_mat.set_shader_parameter("use_relief", false)
		return
	var w := sim.w
	var h := sim.h
	var data := PackedByteArray()
	data.resize(w * h)
	for y in h:
		for x in w:
			data[y * w + x] = _relief_at(x, y)
	_relief_img = Image.create_from_data(w, h, false, Image.FORMAT_R8, data)
	_relief_tex = ImageTexture.create_from_image(_relief_img)
	_ground_mat.set_shader_parameter("relief_map", _relief_tex)
	_ground_mat.set_shader_parameter("map_size", Vector2(w, h))
	_ground_mat.set_shader_parameter("use_relief", true)


var _relief_img: Image
var _relief_tex: ImageTexture
var _relief_dirty := false


## Tile (x, y)'s light and shade (0..255, 128 flat). Water, roads and tiles showing an ore marker stay
## flat, so they keep their own colour (as when the shading was baked under them), and the shore isn't
## darkened by the low ground of the water next to it.
func _relief_at(x: int, y: int) -> int:
	var w := sim.w
	var h := sim.h
	var i := y * w + x
	if sim.road[i] != 0 or sim.ter[i] == Sim.WATER or (sim.ore[i] != 0 and sim.ore_known(1, i)):
		return 128
	var hx := int(sim.height[y * w + mini(x + 1, w - 1)]) - int(sim.height[y * w + maxi(x - 1, 0)])
	var hy := int(sim.height[mini(y + 1, h - 1) * w + x]) - int(sim.height[maxi(y - 1, 0) * w + x])
	var v := clampf((hx + hy) / 30.0 + (int(sim.height[i]) - 100) / 260.0, -1.0, 1.0)
	return clampi(int(round((v * 0.5 + 0.5) * 255.0)), 0, 255)


## Tiles whose look changed in the simulation (trees cut, roads laid...).
func tiles_changed(tiles: PackedInt32Array) -> void:
	if _relief_img != null and _relief_img.get_width() == sim.w and _relief_img.get_height() == sim.h:
		for i in tiles:
			var v := _relief_at(i % sim.w, i / sim.w)
			if _relief_img.get_pixel(i % sim.w, i / sim.w).r8 != v:
				_relief_img.set_pixel(i % sim.w, i / sim.w, Color8(v, 0, 0))
				_relief_dirty = true
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


## The map point under screen position pos (in tiles, not rounded), on the ground.
func screen_to_world(pos: Vector2) -> Vector2:
	var wpos := (pos - size / 2.0) / zoom + cam
	if raised and sim != null and _lift.size() == (sim.w + 1) * (sim.h + 1):
		var y := wpos.y
		for k in 4:
			y = wpos.y + lift_at(wpos.x, y)
		return Vector2(wpos.x, y)
	return wpos


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
	follow = null
	cam = tile
	_clamp()


# ---------------------------------------------------------------- the follow camera
var follow = null            # a Sim.Trip (carrier, cart, ship, walker) or Sim.Attack the camera follows
signal following_ended

## Where trip t is now, in tiles (the middle of the tile it is crossing).
func trip_pos(t: Sim.Trip) -> Vector2:
	var n := t.path.size() - 1
	if n < 1:
		return Vector2(-1, -1)
	if not t.legs.is_empty():
		var lp := _leg_pos(t)
		var a := int(lp.x)
		var c := int(lp.y)
		return Vector2(a % sim.w, a / sim.w).lerp(Vector2(c % sim.w, c / sim.w), absf(lp.z)) + Vector2(0.5, 0.75)
	var prog := 0.0
	if not t.delivered:
		prog = clampf((sim.time - t.t0) / maxf(0.01, t.t1 - t.t0), 0.0, 0.999)
	else:
		prog = 1.0 - clampf((sim.time - t.t1) / maxf(0.01, t.t2 - t.t1), 0.0, 1.0)
	if (t.site != 0 or t.dest != 0) and t.kind != "ship" and t.kind != "trade":
		prog = 1.0 - prog
	var f := prog * n
	var k := mini(floori(f), n - 1)
	var a2 := t.path[k]
	var c2 := t.path[k + 1]
	return Vector2(a2 % sim.w, a2 / sim.w).lerp(Vector2(c2 % sim.w, c2 / sim.w), f - k) + Vector2(0.5, 0.75)


func follow_pos() -> Vector2:
	if follow is Sim.Trip:
		if not sim.trips.has(follow):
			return Vector2(-1, -1)
		return trip_pos(follow)
	if follow is Sim.Attack:
		if not sim.attacks.has(follow):
			return Vector2(-1, -1)
		return sim.military.column_pos(follow) + Vector2(0.5, 0.5)
	return Vector2(-1, -1)


## Something moving near map point at (within a tile): a carrier, cart, ship, walker or a column of
## soldiers, or null.
func pick_mover(at: Vector2):
	var best = null
	var bd := 0.45
	var fog = sim.get_feature("fog")
	for t in sim.trips:
		var p := trip_pos(t)
		if p.x < 0.0:
			continue
		if fog != null and t.p != 1 and not fog.visible_at(sim.idx(clampi(int(p.x), 0, sim.w - 1), clampi(int(p.y), 0, sim.h - 1))):
			continue
		# the figure stands a little above its feet
		var d := (p + Vector2(0, -0.3)).distance_to(at)
		if d < bd:
			bd = d; best = t
	for a in sim.attacks:
		var d2 := (sim.military.column_pos(a) + Vector2(0.5, 0.3)).distance_to(at)
		if d2 < bd:
			bd = d2; best = a
	return best


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
				follow = null
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
	if _relief_dirty and _relief_tex != null:
		_relief_tex.update(_relief_img)
		_relief_dirty = false
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
	if z >= HIRES_ZOOM and chunks.hi == null:
		chunks.hi = MapChunks.new()
		chunks.hi.TS = 64
		chunks.hi.max_chunks = 28      # 4 MB each: up close only a few are on screen
		chunks.hi.sim = sim
		chunks.hi.smooth = chunks.smooth
		chunks.hi.details = chunks.details
		chunks.hi.load_images()
	if z < FAR_ZOOM and chunks.far == null:
		chunks.far = MapChunks.new()
		chunks.far.TS = 8
		chunks.far.bake_trees = true
		chunks.far.sim = sim
		chunks.far.smooth = chunks.smooth
		chunks.far.details = false
		chunks.far.load_images()
	var ch: MapChunks = chunks.hi if z >= HIRES_ZOOM else (chunks if z >= LORES_ZOOM else (chunks.twin if z >= FAR_ZOOM else chunks.far))
	# how many chunks are on screen: on a big screen, or with a small interface size, far more than
	# at 1600 x 900. The chunks kept must hold them all, or each frame forgets chunks it still shows
	# and those parts stay the minimap's flat colours; very many → the quarter-size chunks.
	var on_screen := (x1 / MapChunks.CH - x0 / MapChunks.CH + 1) * (y1 / MapChunks.CH - y0 / MapChunks.CH + 1)
	if on_screen > 160 and ch != chunks.far:
		if chunks.far == null:
			chunks.far = MapChunks.new()
			chunks.far.TS = 8
			chunks.far.bake_trees = true
			chunks.far.sim = sim
			chunks.far.smooth = chunks.smooth
			chunks.far.details = false
			chunks.far.load_images()
		ch = chunks.far
	ch.max_chunks = maxi(ch.max_chunks, on_screen + 40)
	chunks.sim = sim
	ch.sim = sim
	ch.begin_frame()
	if true:
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
	ground_usec = Time.get_ticks_usec() - t_start


## Timing of the parts of a frame's drawing (for tools/late_bench.gd): name -> microseconds, summed.
var prof_on := false
var prof := {}
var _pm_t := 0

var prof_max := {}
var _trip_bb := {}      # trip -> the box round its path (to skip carriers off screen)
var _trip_bb_n := {}
var _trip_bb_t := 0
var _pcol_light: Array = []   # each realm's colour, lightened, for its carriers

func _pm(name: String) -> void:
	var now := Time.get_ticks_usec()
	prof[name] = int(prof.get(name, 0)) + (now - _pm_t)
	prof_max[name] = maxi(int(prof_max.get(name, 0)), now - _pm_t)
	_pm_t = now


func _draw() -> void:
	var t_start := Time.get_ticks_usec()
	_pm_t = t_start
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
	if _vary != null:
		draw_map_texture(self, _vary)
	if prof_on: _pm("ground")
	_draw_fields(x0, x1, y0, y1)
	if prof_on: _pm("fields")
	if z >= SCENERY_ZOOM:
		_draw_scenery(x0, x1, y0, y1)
	if prof_on: _pm("scenery")
	if traffic_ui != null and traffic_ui.on:
		traffic_ui.draw(self, x0, x1, y0, y1)
	# features draw on the ground (season colours, snow) under the buildings
	_season_on = false
	if not sim.features.is_empty():
		var vr := Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
		for f: Feature in sim.features:
			f.draw_map(self, vr)
			if prof_on: _pm("ground:" + f.id)
	_ground_mat.set_shader_parameter("use_season", _season_on)
	if prof_on: _pm("features_ground")
	# building-site markers (while placing, or with a building group open), under the buildings
	_tool_labels = []
	_site_markers(x0, y0, x1, y1)
	if prof_on: _pm("site_markers")
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
	if prof_on: _pm("bld_list")
	# ruins and bandit camps (hand-made maps), under the buildings
	if not sim.places.is_empty():
		_draw_places(x0, y0, x1, y1, fog_on, fog)
	# soft shadows on the ground first, so no building's shadow falls over another building
	for b in vis:
		_building_shadow(b)
	if prof_on: _pm("bld_shadows")
	var labels: Array = []
	# townsfolk about the houses and roads (close up only), drawn in turn with the buildings so a house
	# in front hides the people behind it
	var tfk := Time.get_ticks_usec() if prof_on else 0
	var folk: Array = _collect_folk(vis) if detail else []
	if prof_on:
		prof["x_collect_folk"] = int(prof.get("x_collect_folk", 0)) + Time.get_ticks_usec() - tfk
		prof["n_folk"] = int(prof.get("n_folk", 0)) + folk.size() * 1000
	var fi := 0
	for b in vis:
		while fi < folk.size() and float(folk[fi][0]) < b.y + 0.98:
			_draw_folk_one(folk[fi]); fi += 1
		if raised: _lift_to(b.x + 0.5, b.y + 0.9)
		var nl := labels.size()
		var tb := Time.get_ticks_usec() if prof_on else 0
		_draw_building(b, labels, detail)
		if prof_on:
			prof["n_blds"] = int(prof.get("n_blds", 0)) + 1000
			prof["x_bld_only"] = int(prof.get("x_bld_only", 0)) + Time.get_ticks_usec() - tb
		for li in range(nl, labels.size()):
			labels[li][0] = (labels[li][0] as Vector2) + Vector2(0, -_cur_lift)
		_unlift()
	while fi < folk.size():
		_draw_folk_one(folk[fi]); fi += 1
	if prof_on: _pm("buildings_folk")
	# entrance flags of your buildings, close up; one still without a road waves a warning ring
	if detail:
		for b in vis:
			if b.p == 1 and b.door >= 0 and not b.dead:
				var dt := sim.door_tile(b)
				if dt >= 0:
					if raised: _lift_to(dt % w + 0.5, dt / w + 0.6)
					_door_flag(dt, sim.players[0].color, not sim.connected(b))
					_unlift()
	if prof_on: _pm("door_flags")
	# flags you set on your roads (road carriers mode)
	if detail and not sim.players.is_empty():
		for fi2 in sim.players[0].flags:
			var fx: int = fi2 % w
			var fy: int = fi2 / w
			if fx >= x0 and fx <= x1 and fy >= y0 and fy <= y1 and sim.road[fi2] == 1:
				if raised: _lift_to(fx + 0.5, fy + 0.6)
				_door_flag(fi2, Color(0.95, 0.95, 0.9), false)
				_unlift()
	if prof_on: _pm("road_flags")
	# carriers: loaded on the way to the store, empty on the way back (drawn in batches, see _batch_add)
	var drawn := 0
	_batching = true
	if Time.get_ticks_msec() - _trip_bb_t > 5000:
		# refreshed now and then: the boxes of finished trips, the colours (colour-blind setting)
		# and the sprite sheets (a texture swapped in the texture browser)
		_trip_bb = {}
		_trip_bb_n = {}
		_pcol_light = []
		_spr = {}
		_trip_bb_t = Time.get_ticks_msec()
	var vx0 := float(x0 - 2)
	var vx1 := float(x1 + 2)
	var vy0 := float(y0 - 2)
	var vy1 := float(y1 + 3)
	if _pcol_light.size() != sim.players.size():
		_pcol_light = []
		for pl in sim.players:
			_pcol_light.append(pl.color.lightened(0.25))
	for t in sim.trips:
		if drawn > 700:
			break
		var n := t.path.size() - 1
		if n < 1:
			continue
		# a carrier whose whole way lies off screen is skipped before working out where he is
		var bb: Rect2 = _trip_bb.get(t, Rect2(-1, -1, -1, -1))
		if bb.size.x < 0.0 or int(_trip_bb_n.get(t, -1)) != t.path.size():
			var mnx := 1e9; var mny := 1e9; var mxx := -1e9; var mxy := -1e9
			for pi in t.path:
				var px := float(pi % w); var py := float(pi / w)
				mnx = minf(mnx, px); mxx = maxf(mxx, px); mny = minf(mny, py); mxy = maxf(mxy, py)
			bb = Rect2(mnx, mny, mxx - mnx, mxy - mny)
			_trip_bb[t] = bb
			_trip_bb_n[t] = t.path.size()
		if bb.end.x < vx0 or bb.position.x > vx1 or bb.end.y < vy0 or bb.position.y > vy1:
			continue
		var prog := 0.0
		if not t.delivered:
			prog = clampf((sim.time - t.t0) / maxf(0.01, t.t1 - t.t0), 0.0, 0.999)
		else:
			prog = 1.0 - clampf((sim.time - t.t1) / maxf(0.01, t.t2 - t.t1), 0.0, 1.0)
		# carriers bringing materials walk the other way: from the store out to the site
		if (t.site != 0 or t.dest != 0) and t.kind != "ship" and t.kind != "trade":
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
		var dx := (c % w - a % w) * (-1 if t.delivered else 1) * (-1 if (t.site != 0 or t.dest != 0) and t.kind != "ship" and t.kind != "trade" else 1)
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
			var woman := (t.p * 7 + int(t.t0 * 10.0)) % 3 == 0
			var pid := "unit_porter_w" if woman else "unit_porter"
			var pe := _spr_info(pid)
			var fr := (step % 8) + (0 if loaded else 8)
			if int(pe[1]) < 18:
				fr = step
			elif t.delivered and sim.time - t.t1 < 0.8 and t.site == 0:
				fr = 16 if sim.time - t.t1 < 0.4 else 17
			chh = _sprite(pid, pos, 0.4, fr, dx < 0)
			if bool(pe[4]):
				_batch_layer = 1
				_sprite("unit_porter_w_tint" if woman else "unit_porter_tint", pos, 0.4, fr, dx < 0, _pcol_light[t.p - 1])
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
	if prof_on:
		_pm("carriers")
		prof["n_carriers"] = int(prof.get("n_carriers", 0)) + drawn * 1000
	_flush_batches()
	if prof_on: _pm("flush")
	# marching soldiers
	for a in sim.attacks:
		if fog_on and a.p != 1:
			var ap: Vector2 = sim.military.column_pos(a)
			if fv[clampi(int(ap.y), 0, sim.h - 1) * w + clampi(int(ap.x), 0, w - 1)] == 0:
				continue
		var cdir: Vector2 = sim.military.column_dir(a)
		var left := cdir.x < -0.05 if absf(cdir.x) > 0.05 else a.to.x < a.from.x
		var col: Color = sim.players[a.p - 1].color.lightened(0.2)
		if raised:
			var apos: Vector2 = sim.military.column_pos(a)
			_lift_to(apos.x + 0.5, apos.y + 0.9)
		var nl2 := labels.size()
		if a.fighting:
			# the fight at the gate: the front of the column against the defenders, each pair taking
			# turns to lunge and strike, with sparks where blades meet and dust under their feet
			var tgt: Sim.Bld = sim.by_id.get(a.tgt)
			# in front of its gate (the entrance), on the side the column came from
			var at := a.to + Vector2(0.5, 1.7)
			if tgt != null and tgt.door >= 0:
				var dtile := sim.door_tile(tgt)
				if dtile >= 0:
					at = Vector2(dtile % w + 0.5, dtile / w + 0.85)
			var sgn := 1.0 if left else -1.0
			var tt := sim.time * 3.0 if animate else 0.0
			var ak := Sim.mix_newest(a.amix)
			var aid := _soldier_id(ak if ak >= 0 else a.era)
			var did := aid
			var dcol := col
			var ndef := 0
			if tgt != null:
				# the defenders' best answer to the attackers' strongest kind
				var dk: int = sim.military.best_counter(sim.military.mix_of(sim.military._defending(tgt)), maxi(0, ak))
				did = _soldier_id(dk if dk >= 0 else sim.military.defender_era(tgt))
				dcol = sim.players[tgt.p - 1].color.lightened(0.2)
				ndef = sim.military.own_def(sim.military._defending(tgt))
				_track_losses(-tgt.id, ndef, at + Vector2(-0.3 * sgn, 0), did, dcol, not left)
			var pairs := clampi(mini(a.n, maxi(1, ndef)), 1, 3)
			for k in pairs:
				var row := Vector2(0.08 * k, (k - (pairs - 1) / 2.0) * 0.32)
				var ph := fmod(tt + k * 0.37, 2.0)
				var lunge := sin(clampf(ph, 0.0, 1.0) * PI) * 0.1
				var dl := sin(clampf(ph - 1.0, 0.0, 1.0) * PI) * 0.1
				var apos := at + row + Vector2(0.3 * sgn - lunge * sgn, 0)
				var dpos := at + row + Vector2(-0.3 * sgn + dl * sgn, 0)
				_sprite(aid, apos, 0.5, 4 + int(ph) % 2, left, col)
				if ndef > 0:
					_sprite(did, dpos, 0.5, 4 + (int(ph) + 1) % 2, not left, dcol)
				if animate:
					var hit := fmod(ph, 1.0)
					if hit > 0.45 and hit < 0.65:
						var sp := (apos + dpos) / 2.0 + Vector2(0, -0.3)
						var u := (hit - 0.45) / 0.2
						for s in 4:
							var ang := s * PI / 2.0 + 0.6 + k
							draw_line(sp, sp + Vector2(cos(ang), sin(ang)) * (0.04 + u * 0.12), Color(1.0, 0.92, 0.55, 1.0 - u), 0.025)
			if animate:
				var t2 := Time.get_ticks_msec() / 1000.0
				for k in 4:
					var dph := fmod(t2 * 0.7 + k * 0.25, 1.0)
					draw_circle(at + Vector2((k - 1.5) * 0.25 + sin(t2 + k) * 0.08, 0.05 - dph * 0.35), 0.1 + dph * 0.15, Color(0.75, 0.68, 0.55, 0.3 * (1.0 - dph)))
			_track_losses(a.uid, a.n, at + Vector2(0.35 * sgn, 0), aid, col, left)
			labels.append([at + Vector2(0, -0.85), str(a.n), Color.WHITE])
		else:
			var pos2: Vector2 = sim.military.column_pos(a) + Vector2(0.5, 0.75)
			if a.field != 0:
				# a battle in the open: crossed swords over the column, dust and the flash of blades
				var sw := pos2 + Vector2(0, -1.25)
				draw_line(sw + Vector2(-0.22, -0.22), sw + Vector2(0.22, 0.22), Color(0.95, 0.93, 0.85), 0.07)
				draw_line(sw + Vector2(0.22, -0.22), sw + Vector2(-0.22, 0.22), Color(0.95, 0.93, 0.85), 0.07)
				if animate:
					var t3 := Time.get_ticks_msec() / 1000.0 + a.uid
					for k in 5:
						var dph := fmod(t3 * 0.6 + k * 0.2, 1.0)
						draw_circle(pos2 + Vector2((k - 2) * 0.3 + sin(t3 + k) * 0.1, -dph * 0.4), 0.14 + dph * 0.2, Color(0.75, 0.68, 0.55, 0.28 * (1.0 - dph)))
					if fmod(t3 * 2.0, 1.0) < 0.15:
						var sp2 := pos2 + Vector2(sin(t3 * 7.0) * 0.3, -0.4)
						for s in 4:
							draw_line(sp2, sp2 + Vector2(cos(s * 1.6), sin(s * 1.6)) * 0.12, Color(1, 0.93, 0.6, 0.9), 0.025)
			_track_losses(a.uid, a.n, pos2 + Vector2(0, 0.2), _soldier_id(roundi(a.era)), col, left)
			var walked := (sim.time - a.t0) * 0.9
			var dir := cdir
			# the column: up to five figures in twos, its kinds shown in proportion (most numerous first)
			var kinds := []
			var order := []
			for kk in range(5, -1, -1):
				if a.amix.size() > kk and int(a.amix[kk]) > 0:
					order.append(kk)
			order.sort_custom(func(x, y): return int(a.amix[x]) > int(a.amix[y]))
			var figs := clampi(a.n, 1, 5)
			for kk in order:
				for r in maxi(1, roundi(float(a.amix[kk]) / maxf(1.0, a.n) * figs)):
					if kinds.size() < figs:
						kinds.append(kk)
			if kinds.is_empty():
				kinds = [roundi(a.era)]
			# the last stretch is a charge: weapons lowered, running
			var charging := a.chase == 0 and pos2.distance_to(a.to + Vector2(0.5, 0.75)) < 1.6
			for i in kinds.size():
				var side2 := Vector2(-dir.y, dir.x) * (0.16 if i % 2 == 1 else -0.16) * (0.0 if i == 0 else 1.0)
				var off := -dir * 0.36 * ((i + 1) / 2) + side2
				var fr := (4 + int(sim.time * 8.0 + i) % 2) if charging and animate else (int(walked * 5.0 + i) % 4 if animate else 0)
				_sprite(_soldier_id(kinds[i]), pos2 + off, 0.5, fr, left, col)
			# the column's banner, carried at its head, waving
			var bp := pos2 + Vector2(0.12 * (-1.0 if left else 1.0), -0.02)
			var top := bp + Vector2(0, -0.95)
			draw_line(bp, top, Color("4a3520"), 0.035)
			var wv := sin(Time.get_ticks_msec() / 1000.0 * 6.0 + a.uid) * 0.04 if animate else 0.0
			var fdir := -1.0 if left else 1.0
			draw_colored_polygon(PackedVector2Array([top, top + Vector2(0.32 * fdir, 0.05 + wv), top + Vector2(0.3 * fdir, 0.2 + wv), top + Vector2(0, 0.22)]), sim.players[a.p - 1].color)
			draw_polyline(PackedVector2Array([top, top + Vector2(0.32 * fdir, 0.05 + wv), top + Vector2(0.3 * fdir, 0.2 + wv), top + Vector2(0, 0.22)]), Color(0, 0, 0, 0.45), 0.015)
			# gunfire: smoke and flashes at the shooters, streaks toward the other side
			var tgt2: Sim.Bld = sim.by_id.get(a.tgt)
			if sim.time - a.shot_t < 0.45:
				var u := (sim.time - a.shot_t) / 0.45
				var muzzle := pos2 + Vector2(0.25 * (-1 if left else 1), -0.3)
				draw_circle(muzzle + Vector2(0, -u * 0.25), 0.12 + u * 0.22, Color(0.92, 0.92, 0.88, 0.75 * (1.0 - u)))
				if u < 0.25:
					draw_circle(muzzle, 0.07, Color(1.0, 0.85, 0.4, 0.95))
					draw_line(muzzle, a.to + Vector2(0.5, 0.5), Color(1.0, 0.95, 0.7, 0.5), 0.03)
			if tgt2 != null and a.chase == 0 and sim.time - a.dshot_t < 0.45:
				var u2 := (sim.time - a.dshot_t) / 0.45
				var gate := Vector2(tgt2.x + 0.5, tgt2.y + 0.4)
				draw_circle(gate + Vector2(0, -u2 * 0.25), 0.15 + u2 * 0.25, Color(0.92, 0.92, 0.88, 0.75 * (1.0 - u2)))
				if u2 < 0.25:
					draw_circle(gate, 0.08, Color(1.0, 0.85, 0.4, 0.95))
					draw_line(gate, pos2 + Vector2(0, -0.3), Color(1.0, 0.95, 0.7, 0.5), 0.03)
			labels.append([pos2 + Vector2(0, -0.85), str(a.n), Color.WHITE])
		# arrows: a volley from a tower's archers, arcing down onto the column
		if sim.time - a.arrow_t < 1.0 and a.arrow_n > 0:
			var u := (sim.time - a.arrow_t) / 1.0
			var src := a.arrow_src + Vector2(0.5, -0.6)
			var dst: Vector2 = (a.to + Vector2(0.5, 0.8)) if a.fighting else (sim.military.column_pos(a) + Vector2(0.5, 0.5))
			for k in mini(a.arrow_n, 6):
				var uk := clampf(u * 1.3 - k * 0.06, 0.0, 1.0)
				if uk <= 0.0 or uk >= 1.0:
					continue
				var off := Vector2((k % 3 - 1) * 0.18, (k / 3) * 0.15)
				var p0 := src.lerp(dst + off, uk) + Vector2(0, -sin(uk * PI) * 1.2)
				var p1 := src.lerp(dst + off, uk + 0.04) + Vector2(0, -sin((uk + 0.04) * PI) * 1.2)
				var d := (p1 - p0).normalized() * 0.34
				draw_line(p0 - d, p0, Color(0.28, 0.2, 0.1), 0.035)
				draw_line(p0 - d, p0 - d * 0.72, Color(0.95, 0.95, 0.92), 0.06)
				draw_line(p0, p0 - d.rotated(0.5) * 0.25, Color(0.5, 0.5, 0.52), 0.03)
		for li in range(nl2, labels.size()):
			labels[li][0] = (labels[li][0] as Vector2) + Vector2(0, -_cur_lift)
		_unlift()
	if not sim.features.is_empty():
		var vr2 := Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
		for f: Feature in sim.features:
			f.draw_top(self, vr2)
	if prof_on: _pm("soldiers_top")
	_draw_fx(x0, y0, x1, y1)
	if animate and z >= 9.0:
		_draw_birds(x0, y0, x1, y1)
	_draw_night(vis, x0, y0, x1, y1)
	if prof_on: _pm("night")
	_draw_selection_and_tools()
	if prof_on: _pm("selection")
	# screen-space text
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for f: Feature in sim.features:
		f.draw_overlay(self, screen_to_tile)
		if prof_on: _pm("overlay:" + f.id)
	# town names over the stores
	if z >= 9.0 and not editor:
		var tfont := get_theme_default_font()
		var tfs := clampi(int(z * 0.5), 11, 22)
		var fogf = sim.get_feature("fog")
		for b in sim.blds:
			if b.town == "" or b.dead or b.x < x0 - 2 or b.x > x1 + 2 or b.y < y0 - 2 or b.y > y1 + 3:
				continue
			if fogf != null and b.p != 1 and not fogf.explored_at(sim.idx(b.x, b.y)):
				continue
			var tp := Vector2(b.x + 0.5, b.y - 1.55)
			if raised:
				tp.y -= lift_at(b.x + 0.5, b.y + 0.5)
			var sp2: Vector2 = origin + tp * z
			draw_string_outline(tfont, sp2 + Vector2(-90, 0), b.town, HORIZONTAL_ALIGNMENT_CENTER, 180, tfs, 5, Color(0, 0, 0, 0.85))
			draw_string(tfont, sp2 + Vector2(-90, 0), b.town, HORIZONTAL_ALIGNMENT_CENTER, 180, tfs, sim.players[b.p - 1].color.lightened(0.55))
	if prof_on: _pm("town_names")
	if z >= 14.0:
		var font := get_theme_default_font()
		var fs := clampi(int(z * 0.42), 10, 20)
		for l in _tool_labels:
			l[0] = (l[0] as Vector2) + Vector2(0, -lift_at((l[0] as Vector2).x, (l[0] as Vector2).y + 0.6))
		for l in labels + _tool_labels:
			var sp: Vector2 = origin + (l[0] as Vector2) * z
			draw_string_outline(font, sp + Vector2(-110, 0), String(l[1]), HORIZONTAL_ALIGNMENT_CENTER, 220, fs, 4, Color.BLACK)
			draw_string(font, sp + Vector2(-110, 0), String(l[1]), HORIZONTAL_ALIGNMENT_CENTER, 220, fs, l[2])
	if flash > 0.0:
		_draw_alert_edges(flash)
	if prof_on: _pm("labels")
	draw_usec = Time.get_ticks_usec() - t_start


## The warning of an attack: a red glow along the screen's edges, fading towards the middle, so the
## map itself stays clear.
func _draw_alert_edges(f: float) -> void:
	var w := minf(size.x, size.y) * 0.09
	var o := Color(0.85, 0.2, 0.16, 0.45 * f)
	var i := Color(0.85, 0.2, 0.16, 0.0)
	var a := Vector2.ZERO
	var b := Vector2(size.x, 0)
	var c := size
	var d := Vector2(0, size.y)
	var ia := Vector2(w, w)
	var ib := Vector2(size.x - w, w)
	var ic := size - Vector2(w, w)
	var id := Vector2(w, size.y - w)
	for q in [[a, b, ib, ia], [b, c, ic, ib], [c, d, id, ic], [d, a, ia, id]]:
		draw_polygon(PackedVector2Array(q), PackedColorArray([o, o, i, i]))


## The map editor's climate picture: one pixel a tile, drawn stretched over the map.
func editor_climate_load(b: PackedByteArray) -> void:
	_clim_img = Image.create(sim.w, sim.h, false, Image.FORMAT_RGBA8)
	for i in b.size():
		if b[i] > 0:
			_clim_img.set_pixel(i % sim.w, i / sim.w, CLIMATE_COL[b[i]])
	_clim_tex = ImageTexture.create_from_image(_clim_img)
	_clim_dirty = false


func editor_climate_set(i: int, v: int) -> void:
	if _clim_img == null or _clim_img.get_width() != sim.w:
		return
	_clim_img.set_pixel(i % sim.w, i / sim.w, CLIMATE_COL[v])
	_clim_dirty = true


func _draw_editor() -> void:
	if editor_climate and _clim_tex != null and _clim_img.get_width() == sim.w:
		if _clim_dirty:
			_clim_tex.update(_clim_img)
			_clim_dirty = false
		draw_texture_rect(_clim_tex, Rect2(0, 0, sim.w, sim.h), false)
	if editor_mirror != "off":
		# the lines the brush mirrors across
		var mc := Color(1, 1, 1, 0.3)
		if editor_mirror == "left-right" or editor_mirror == "four ways":
			draw_line(Vector2(sim.w / 2.0, 0), Vector2(sim.w / 2.0, sim.h), mc, 0.12)
		if editor_mirror == "top-bottom" or editor_mirror == "four ways":
			draw_line(Vector2(0, sim.h / 2.0), Vector2(sim.w, sim.h / 2.0), mc, 0.12)
		if editor_mirror == "turned":
			draw_circle(Vector2(sim.w / 2.0, sim.h / 2.0), 0.6, mc)
	if editor_line.size() == 2:
		var a: Vector2i = editor_line[0]
		var b: Vector2i = editor_line[1]
		draw_line(Vector2(a) + Vector2(0.5, 0.5), Vector2(b) + Vector2(0.5, 0.5), Color(0.35, 0.65, 1.0, 0.85), 0.5)
		draw_circle(Vector2(a) + Vector2(0.5, 0.5), 0.5, Color(0.35, 0.65, 1.0))
	if editor_rect.size.x > 0:
		draw_rect(Rect2(editor_rect), Color(1.0, 0.9, 0.4, 0.15))
		draw_rect(Rect2(editor_rect), Color(1.0, 0.9, 0.4, 0.95), false, 0.12)
	if editor_paste.x > 0 and sim.inb(ghost.x, ghost.y):
		draw_rect(Rect2(Vector2(ghost), Vector2(editor_paste)), Color(0.5, 1.0, 0.6, 0.12))
		draw_rect(Rect2(Vector2(ghost), Vector2(editor_paste)), Color(0.5, 1.0, 0.6, 0.95), false, 0.12)
		return
	if sim.inb(ghost.x, ghost.y):
		for p: Vector2i in EditorTools.mirrored(ghost.x, ghost.y, sim.w, sim.h, editor_mirror):
			var gl := lift_at(p.x + 0.5, p.y + 0.5)
			var col := Color(1, 1, 1, 0.9) if p == ghost else Color(1, 1, 1, 0.45)
			if editor_round and editor_brush > 2:
				var c := Vector2(p.x + (0.5 if editor_brush % 2 == 1 else 0.0), p.y + (0.5 if editor_brush % 2 == 1 else 0.0) - gl)
				draw_arc(c, editor_brush / 2.0, 0, TAU, 48, col, 0.08)
			else:
				var r := editor_brush / 2
				draw_rect(Rect2(p.x - r, p.y - r - gl, editor_brush, editor_brush), col, false, 0.08)


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
		for a in editor_animals:
			var ap := Vector2(int(a[1]) + 0.5, int(a[2]) + 0.8)
			ap.y -= lift_at(ap.x, ap.y)
			var wd := {"deer": 0.62, "boar": 0.5, "hare": 0.3, "wolf": 0.6}.get(String(a[0]), 0.5) as float
			_sprite("unit_" + String(a[0]), ap, wd, 0, false)
		for k in editor_starts.size():
			var st: Vector2i = editor_starts[k]
			var c := Vector2(st.x + 0.5, st.y + 0.5 - lift_at(st.x + 0.5, st.y + 0.5))
			draw_rect(Rect2(c.x - 3.5, c.y - 3.5, 7, 7), Color(Sim.PCOL[k % Sim.PCOL.size()], 0.18))
			draw_rect(Rect2(c.x - 3.5, c.y - 3.5, 7, 7), Sim.PCOL[k % Sim.PCOL.size()], false, 0.1)
			draw_circle(c, 0.7, Sim.PCOL[k % Sim.PCOL.size()])
			_tool_labels.append([c + Vector2(0, -0.9), "Start %d%s" % [k + 1, " (you)" if k == 0 else ""], Color.WHITE])
		_draw_editor()
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
	# worked out again when the view, the building, its entrance or the map changes (roads, buildings,
	# land), a few rows a frame so turning the entrance doesn't stall a frame; the old marks stay up
	# until the new ones are ready
	var lg := sim.logistics
	var key := "%s|%d|%d,%d,%d,%d|%s|%d|%d|%d" % [place_type if placing else "", door, x0, y0, x1, y1,
		str(lg.net_ver), lg._store_ver, sim.territory_version, sim.blds.size()]
	if key != _site_key:
		_site_key = key
		_site_new = {}
		_site_row = maxi(0, y0)
		_site_rect = Rect2i(x0, y0, x1 - x0, y1 - y0)
		# a small change of view (scrolling) keeps the marks in view until the new ones are ready
	if _site_row >= 0:
		var deadline := Time.get_ticks_usec() + 2500
		var sz := sim.size_of(place_type) if placing else ""
		var ry1 := mini(sim.h - 1, _site_rect.end.y)
		while _site_row <= ry1:
			var y := _site_row
			for x in range(maxi(0, _site_rect.position.x), mini(sim.w - 1, _site_rect.end.x) + 1):
				if placing:
					if Vector2i(x, y) != ghost and sim.can_place(place_type, x, y, 1, door) == "":
						_site_new[y * sim.w + x] = sz
				else:
					var s := sim.site_size(x, y, 1)
					if s != "":
						_site_new[y * sim.w + x] = s
			_site_row += 1
			if Time.get_ticks_usec() > deadline:
				break
		if _site_row > ry1:
			_site_row = -1
			_sites = _site_new
			_gain = {}
			_gain_todo = []
			_gain_all = []
		else:
			queue_redraw()
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
			# also a few at a time: each spot counts the land in its radius
			if _gain_todo.is_empty() and _gain_all.is_empty():
				_gain_todo = _sites.keys()
			var r := int(GameData.bld[place_type].radius)
			var dl := Time.get_ticks_usec() + 2000
			while not _gain_todo.is_empty() and Time.get_ticks_usec() < dl:
				var t: int = _gain_todo.pop_back()
				_gain_all.append([land_gain(t % sim.w, t / sim.w, r, 1), t])
			if _gain_todo.is_empty():
				_gain_all.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
				for k in mini(5, _gain_all.size()):
					if int(_gain_all[k][0]) > 0:
						_gain[_gain_all[k][1]] = _gain_all[k][0]
				_gain[-1] = 0   # worked out (even when nothing gains)
				_gain_all = []
			else:
				queue_redraw()
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
	if chunks.hi != null:
		chunks.hi.details = on
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
var _flag_tex := {}   # flag colour -> a little picture of the flag on its pole (one draw call a flag)

func _flag_picture(col: Color) -> Texture2D:
	var t = _flag_tex.get(col)
	if t != null:
		return t
	# 32 x 64 pixels for 0.5 x 1 tile: the pole's foot at (16, 56), its shadow, the pennant
	var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(54, 60):
		for x in range(12, 21):
			if Vector2(x - 16, (y - 57) * 1.6).length() <= 4.5:
				img.set_pixel(x, y, Color(0, 0, 0, 0.35))
	for y in range(29, 57):
		img.set_pixel(16, y, Color("3a2a18"))
		img.set_pixel(17, y, Color("3a2a18"))
	for y in range(29, 39):
		var reach := int(15.0 * (1.0 - absf(y - 33.5) / 5.0))
		for x in range(17, 18 + reach):
			var edge := y == 29 or y == 38 or x == 17 + reach
			img.set_pixel(x, y, col.darkened(0.45) if edge else col)
	t = ImageTexture.create_from_image(img)
	_flag_tex[col] = t
	return t


func _door_flag(i: int, col: Color, warn: bool) -> void:
	var c := Vector2(i % sim.w + 0.5, i / sim.w + 0.62)
	if warn:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		draw_arc(c + Vector2(0, -0.05), 0.36 + 0.06 * pulse, 0, TAU, 24, Color(1.0, 0.85, 0.3, 0.55 + 0.4 * pulse), 0.06)
	draw_texture_rect(_flag_picture(col), Rect2(c.x - 0.25, c.y - 0.875, 0.5, 1.0), false)


## Draws frame f of an animated texture with its bottom centre at foot, wid tiles wide, mirrored when
## flip is true. Returns the height it was drawn at, so labels and loads can sit above it.
## Per sprite sheet: [texture, frames, frame width, height, whether a "_tint" sheet matches it].
## Looked up once, as the carriers alone draw hundreds of sprites a frame.
var _spr := {}

func _spr_info(id: String) -> Array:
	var e = _spr.get(id)
	if e == null:
		var t := Tex.get_tex(id)
		var n := Tex.frames(id)
		e = [t, n, t.get_width() / float(n), float(t.get_height()), Tex.frames(id + "_tint") == n and Tex.get_tex(id + "_tint") != null]
		_spr[id] = e
	return e


func _sprite(id: String, foot: Vector2, wid: float, f: int, flip: bool, col := Color.WHITE) -> float:
	var e := _spr_info(id)
	var tex: Texture2D = e[0]
	var fw: float = e[2]
	var src := Rect2(fw * posmod(f, int(e[1])), 0, fw, e[3])
	var hgt := wid * src.size.y / maxf(1.0, src.size.x)
	var dst := Rect2(foot.x - wid / 2.0, foot.y - hgt, wid, hgt)
	if flip:
		# a rectangle with a negative width is drawn mirrored left to right
		dst = Rect2(foot.x + wid / 2.0, foot.y - hgt, -wid, hgt)
	# a little shadow under the feet of people, animals and carts (not under flags, loads or tints)
	if wid <= 1.3 and _batch_layer == 0 and id.begins_with("unit_") and not id.begins_with("unit_flag") \
			and not id.begins_with("unit_load") and not id.ends_with("_tint"):
		var sr := Rect2(foot.x - wid * 0.42 + SUN.x * 0.3, foot.y - wid * 0.13, wid * 0.84, wid * 0.26)
		if _batching:
			_shadows.append(sr)
		else:
			draw_texture_rect(_shadow, sr, false)
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
var _shadows: Array = []          # shadows of the batched sprites, drawn first

func _batch_add(tex: Texture2D, dst: Rect2, src: Rect2, col: Color) -> void:
	var layer: Dictionary = _batches[_batch_layer]
	if not layer.has(tex):
		layer[tex] = []
	(layer[tex] as Array).append([dst, src, col])


func _flush_batches() -> void:
	_batching = false
	for sr: Rect2 in _shadows:
		draw_texture_rect(_shadow, sr, false)
	_shadows.clear()
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


## A building's shadow on the ground: as wide as its picture, falling a little to the right.
func _building_shadow(b: Sim.Bld) -> void:
	var ai := _art_of(b.ty)
	var sw: float = ai[1]
	var w := sw * 1.05
	var h := minf(1.0, sw * 0.45)
	var foot := Vector2(b.x + 0.5, b.y + 0.98) + SUN * sw * 1.6
	if raised:
		foot.y -= lift_at(b.x + 0.5, b.y + 0.9)
	var a := 0.55 if b.state == "build" else 1.0
	draw_texture_rect(_shadow, Rect2(foot.x - w / 2.0, foot.y - h * 0.62, w, h), false, Color(1, 1, 1, a))


## What drawing a building of a type needs from its data, looked up once per type:
## [style, picture width, hub, glow, smoke, military, siege, flag height share by picture].
var _art := {}

func _art_of(ty: String) -> Array:
	var e = _art.get(ty)
	if e == null:
		var d: Dictionary = GameData.bld[ty]
		var art: Dictionary = d.get("art", {})
		var style := String(art.get("style", "house"))
		var anchors: Dictionary = ANCHORS.get(style, {})
		e = [style, float(art.get("sw", 2.0)), art.get("hub", anchors.get("hub", [])), art.get("glow", anchors.get("glow", [])),
			art.get("smoke", anchors.get("smoke", [])), ty == "hq" or d.has("garrison"), d.has("siege")]
		_art[ty] = e
	return e


func _draw_building(b: Sim.Bld, labels: Array, detail: bool) -> void:
	# a site is drawn in the look it will have: its realm's age when it was placed
	var tex: Texture2D = bld_texture(b.ty, b.era)
	var ai := _art_of(b.ty)
	var style: String = ai[0]
	var sw: float = ai[1]
	var hgt := sw * tex.get_height() / maxf(1.0, tex.get_width())
	var rect := Rect2(b.x + 0.5 - sw / 2.0, b.y + 1.0 - hgt, sw, hgt)
	var pc: Color = sim.players[b.p - 1].color
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
			var bt := sim.time * 4.0 + b.id
			var beat := int(bt)
			var hp := Vector2(b.x + 0.12, b.y + 1.0)
			_sprite("unit_worker_hammer", hp, 0.4, 4 + beat % 2, false, pc.lightened(0.35))
			if animate:
				# each blow: a flick of sparks where the hammer lands, and dust drifting up from the site
				var ph := fmod(bt, 1.0)
				if beat % 2 == 1 and ph < 0.3:
					var sp := hp + Vector2(0.2, -0.22)
					for k in 3:
						var a := -0.6 - k * 0.5
						draw_line(sp, sp + Vector2(cos(a), sin(a)) * (0.05 + ph * 0.25), Color(1.0, 0.9, 0.5, 1.0 - ph * 3.0), 0.02)
				var tt := Time.get_ticks_msec() / 1000.0
				for k in 3:
					var dph := fmod(tt * 0.45 + k * 0.33 + b.id * 0.17, 1.0)
					var dp := Vector2(b.x + 0.2 + k * 0.3 + sin(tt + k) * 0.05, b.y + 0.95 - dph * 0.7)
					draw_circle(dp, 0.07 + dph * 0.12, Color(0.78, 0.7, 0.58, 0.32 * (1.0 - dph)))
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
		var ntex := bld_texture(b.upg if b.upg != "" else b.ty, b.reno_to)
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
	var hub: Array = ai[2]
	if hub.size() == 2:
		var turn := sim.time * 1.6 if b.working and animate else float(b.id)
		var hp := _anchor(rect, hub)
		var ss := sw * 0.9
		draw_set_transform(_origin + hp * zoom, turn, Vector2(zoom, zoom))
		draw_texture_rect(_sails, Rect2(-ss / 2.0, -ss / 2.0, ss, ss), false)
		draw_set_transform(_origin, 0.0, Vector2(zoom, zoom))
	if detail:
		var glow: Array = ai[3]
		if glow.size() == 2 and b.working:
			var fl := 0.65 + 0.35 * sin(sim.time * 13.0 + b.id) * sin(sim.time * 7.3)
			var gp := _anchor(rect, glow)
			var gr := 0.28 * sw / 2.0
			draw_texture_rect(_glow, Rect2(gp.x - gr, gp.y - gr, gr * 2.0, gr * 2.0), false, Color(1, 1, 1, fl))
		var smoke: Array = ai[4]
		if smoke.size() == 2 and (b.working or (style in HOME_SMOKE and b.state == "ready")):
			_smoke_at(_anchor(rect, smoke), b.id * 0.137, 1.0 if b.working else 0.5)
		_draw_worker(b, pc)
	# a catapult's stone in flight, and dust where it lands
	if ai[6] and b.target >= 0:
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
		# a "!" badge on the building's roof: it can't work (the reason shows when you click it)
		var bc := Vector2(rect.position.x + rect.size.x * 0.28, rect.position.y + rect.size.y * _tex_top(tex) + 0.12)
		draw_circle(bc, 0.15, Color(0.12, 0.08, 0.05, 0.85))
		draw_circle(bc, 0.12, Color("e0603a"))
		draw_line(bc + Vector2(0, -0.075), bc + Vector2(0, 0.025), Color.WHITE, 0.035)
		draw_circle(bc + Vector2(0, 0.065), 0.02, Color.WHITE)
	var waiting := 0
	for r in b.out_buf:
		waiting += int(b.out_buf[r])
	if waiting > 0 and zoom >= 18.0:
		var first: String = b.out_buf.keys()[0]
		if _res_tex.has(first):
			draw_texture_rect(_res_tex[first], Rect2(b.x + 0.62, b.y + 0.55, 0.36, 0.36), false)
	if ai[5]:
		labels.append([Vector2(b.x + 0.5, rect.position.y - 0.05), str(sim.own_def(b)), pc.lightened(0.5)])
	if b.p == 1 and b.prio != Sim.PRIO_NORMAL:
		_prio_badge(b)


## Farm fields: ploughed soil with furrows, and rows of plants that grow taller as the field grows,
## turn the crop's colour when ripe and sway in the wind (their tips are marked for the map shader).
## All fields make one mesh, made again only when a field is sown, grows a stage or is harvested.
var _field_mesh: ArrayMesh
var _field_sig := ""
var _white: Texture2D

## [how tall when grown (tiles), how wide a plant, plants per row, ripe colour, colour of the tips]
const CROP_LOOK := {
	"wheat": [0.21, 0.10, 9, Color("d4ab42"), Color("f4dc86")],
	"rye": [0.24, 0.09, 9, Color("b39c62"), Color("dccb96")],
	"vegetables": [0.12, 0.17, 5, Color("5fa443"), Color("8acb5e")],
	"potatoes": [0.13, 0.16, 5, Color("6f9a46"), Color("a9c472")],
	"flax": [0.22, 0.08, 9, Color("6f9d4c"), Color("94aee6")],
	"hops": [0.36, 0.11, 4, Color("4f8a36"), Color("b6d070")],
}

func _draw_fields(_x0: int, _x1: int, _y0: int, _y1: int) -> void:
	if sim.fields.is_empty():
		return
	var sig := "%d|%s|%d" % [sim.fields.size(), str(raised), chunks.ver]
	var h := 0
	for i in sim.fields:
		var f: Array = sim.fields[i]
		h = (h * 31 + i * 7 + int(float(f[2]) / Crops.GROW * 8.0) + String(f[1]).length()) % 1000000007
	sig += "|%d" % h
	if sig != _field_sig or _field_mesh == null:
		_field_sig = sig
		_field_mesh = _make_field_mesh()
	if _white == null:
		var wi := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		wi.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(wi)
	if _field_mesh != null:
		draw_mesh(_field_mesh, _white)


func _make_field_mesh() -> ArrayMesh:
	var v := PackedVector2Array()
	var c := PackedColorArray()
	var soil := Color("6e4c2e")
	var soil_dark := Color("4f3420")
	var soil_light := Color("85603c")
	var green := Color("5c8c36")
	var keys: Array = sim.fields.keys()
	keys.sort()
	for i in keys:
		var x: int = i % sim.w
		var y: int = i / sim.w
		var f: Array = sim.fields[i]
		var g := clampf(float(f[2]) / Crops.GROW, 0.0, 1.0)
		var look: Array = CROP_LOOK.get(String(f[1]), CROP_LOOK.wheat)
		var q := tile_quad(x, y)
		# a corner of the plot, from fractions of the tile (u across, w down)
		var at := func(u: float, w: float) -> Vector2:
			return q[0].lerp(q[1], u).lerp(q[3].lerp(q[2], u), w)
		var mg := 0.05
		var ripe := clampf((g - 0.65) / 0.35, 0.0, 1.0)
		var body := green.lerp(look[3], ripe)
		var tipc := body.lerp(look[4], ripe)
		var dark := body.darkened(0.3)
		# the ground: ploughed soil, covered by the crop as it grows
		var cover := clampf((g - 0.25) / 0.6, 0.0, 1.0) * 0.85
		var ground := soil.lerp(dark, cover)
		_quad(v, c, at.call(mg, mg), at.call(1.0 - mg, mg), at.call(1.0 - mg, 1.0 - mg), at.call(mg, 1.0 - mg), ground)
		# furrows: a dark groove with a light ridge below it
		for r in 5:
			var w0 := 0.13 + r * 0.17
			_quad(v, c, at.call(mg + 0.02, w0), at.call(1.0 - mg - 0.02, w0), at.call(1.0 - mg - 0.02, w0 + 0.04), at.call(mg + 0.02, w0 + 0.04), soil_dark.lerp(dark.darkened(0.2), cover))
			_quad(v, c, at.call(mg + 0.02, w0 + 0.04), at.call(1.0 - mg - 0.02, w0 + 0.04), at.call(1.0 - mg - 0.02, w0 + 0.065), at.call(mg + 0.02, w0 + 0.065), soil_light.lerp(body, cover))
		if g < 0.08:
			continue
		# plants along the ridges, back rows first
		var tall: float = float(look[0]) * (0.25 + 0.75 * g)
		var wid: float = float(look[1]) * (0.6 + 0.4 * g)
		var n: int = look[2]
		for r in 5:
			var w0 := 0.13 + r * 0.17 + 0.05
			for k in n:
				var hh := MapChunks._hash(i * 7 + r, k)
				var u := mg + 0.06 + (k + 0.5) / n * (0.88 - 2.0 * mg) + float(hh % 7 - 3) / 200.0
				var base: Vector2 = at.call(u, w0)
				var tl := tall * (0.85 + float(hh % 30) / 100.0)
				var tip := base + Vector2(float((hh >> 4) % 5 - 2) / 100.0, -tl)
				# a blade: two triangles, the shaded side and the lit side; the tip sways
				var tc := Color(tipc, SWAY_CROP)
				v.append_array(PackedVector2Array([base + Vector2(-wid / 2.0, 0), base, tip]))
				c.append_array(PackedColorArray([dark, dark, Color(dark, SWAY_CROP)]))
				v.append_array(PackedVector2Array([base, base + Vector2(wid / 2.0, 0), tip]))
				c.append_array(PackedColorArray([body, body, tc]))
	if v.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_COLOR] = c
	var uv := PackedVector2Array()
	uv.resize(v.size())
	arr[Mesh.ARRAY_TEX_UV] = uv
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Two triangles (a, b, cc, d) of one colour, for a mesh being made.
static func _quad(v: PackedVector2Array, c: PackedColorArray, a: Vector2, b: Vector2, cc: Vector2, d: Vector2, col: Color) -> void:
	v.append_array(PackedVector2Array([a, b, cc, a, cc, d]))
	for k in 6:
		c.append(col)


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
		var outs: Dictionary = Crops.out_of(sim, b)
		if outs.size() > 0 and _res_tex.has(outs.keys()[0]):
			draw_texture_rect(_res_tex[outs.keys()[0]], Rect2(p2.x - 0.13, p2.y - hh - 0.2, 0.26, 0.26), false)
	elif act == "fish" and dist > 1.2:
		# out in his boat over the fishing ground, rocking on the water, casting now and then
		var bp := spot.lerp(tgt, 0.6) + Vector2(0, 0.04 * sin(sim.time * 2.1 + b.id))
		var fl := -1.0 if tgt.x < spot.x else 1.0
		_boat(bp, fl, 0.55)
		_person(id, bp + Vector2(0, -0.06), nw + int(sim.time * 1.5 + b.id) % 2, fl < 0, col)
		# the line, and rings on the water where it goes in
		var tipp := bp + Vector2(0.32 * fl, -0.42)
		var bob := bp + Vector2(0.62 * fl, 0.08)
		draw_line(tipp, bob, Color(0.9, 0.9, 0.85, 0.7), 0.012)
		var rr := fmod(sim.time * 0.8 + b.id * 0.3, 1.0)
		draw_arc(bob, 0.05 + rr * 0.18, 0, TAU, 16, Color(1, 1, 1, 0.5 * (1.0 - rr)), 0.02)
	else:
		_person(id, spot, nw + int(sim.time * 3.0 + b.id) % 2, tgt.x < spot.x, col)
		_work_fx(act, b, spot, tgt)


## Little bits flying where a worker is at work: seeds sown and chaff at the harvest in the fields,
## wood chips at the tree, stone chips at the rock. at: where he stands; tgt: what he works on.
func _work_fx(act: String, b: Sim.Bld, at: Vector2, tgt: Vector2) -> void:
	if not animate or zoom < DETAIL_ZOOM:
		return
	var t := Time.get_ticks_msec() / 1000.0 + b.id * 0.31
	var fl := 1.0 if tgt.x >= at.x else -1.0
	match act:
		"farm":
			if b.sowing:
				# a swing of the arm: seeds fan out onto the furrows
				var ph := fmod(t * 1.2, 1.0)
				for k in 5:
					var d := Vector2(fl * (0.15 + k * 0.07), -0.25)
					var p := at + Vector2(0, -0.28) + d * ph + Vector2(0, 0.6 * ph * ph)
					draw_circle(p, 0.018, Color(0.85, 0.75, 0.45, 1.0 - ph * 0.6))
			else:
				# reaping: chaff and straw flying from the sickle
				for k in 6:
					var ph := fmod(t * 0.9 + k * 0.17, 1.0)
					var p := at + Vector2(fl * (0.2 + ph * 0.3) + sin(t * 3.0 + k) * 0.05, -0.15 - sin(ph * PI) * 0.35)
					draw_line(p, p + Vector2(0.04, -0.02).rotated(t * 4.0 + k), Color(0.95, 0.82, 0.42, 1.0 - ph), 0.02)
		"cut_tree", "cut_rock":
			# chips flying from each blow
			var ph := fmod(t * 1.6, 1.0)
			if ph < 0.6:
				var c := Color(0.62, 0.45, 0.26) if act == "cut_tree" else Color(0.7, 0.7, 0.68)
				var src := tgt + Vector2(-fl * 0.12, -0.35 if act == "cut_tree" else -0.15)
				for k in 4:
					var a := -PI / 2.0 + (k - 1.5) * 0.45 - fl * 0.6
					var p := src + Vector2(cos(a), sin(a)) * ph * 0.45 + Vector2(0, ph * ph * 0.5)
					draw_rect(Rect2(p, Vector2(0.04, 0.03)), Color(c, 1.0 - ph / 0.6))


# ---------------------------------------------------------------- effects: a tree falls, a building is done
var _fx: Array = []              # [kind, where (tiles), start time (s), extra]

func fx_tree(tile: int) -> void:
	if not animate or sim == null:
		return
	var x := tile % sim.w
	var y := tile / sim.w
	var fog = sim.get_feature("fog")
	if fog != null and not fog.visible_at(tile):
		return
	_fx.append(["tree", Vector2(x + 0.5, y + 1.0), Time.get_ticks_msec() / 1000.0, _tree_kind(x, y)])
	if _fx.size() > 120:
		_fx.pop_front()


func fx_done(id: int) -> void:
	if not animate or sim == null:
		return
	var b: Sim.Bld = sim.by_id.get(id)
	if b == null:
		return
	var fog = sim.get_feature("fog")
	if fog != null and b.p != 1 and not fog.visible_at(sim.idx(b.x, b.y)):
		return
	_fx.append(["done", Vector2(b.x + 0.5, b.y + 0.9), Time.get_ticks_msec() / 1000.0, float(_art_of(b.ty)[1])])
	if _fx.size() > 120:
		_fx.pop_front()


## Which tree picture stood on (x, y) (the same choice as the scenery makes).
func _tree_kind(x: int, y: int) -> int:
	var patch := MapChunks._hash(x / 5 + 101, y / 5 + 37)
	var hh := MapChunks._hash(x, y)
	if patch % 3 == 0:
		return [0, 3, 0, 3, 1][hh % 5]
	return [1, 4, 2, 1, 4, 0][hh % 6]


func _draw_fx(x0: int, y0: int, x1: int, y1: int) -> void:
	if _fx.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var keep: Array = []
	for e in _fx:
		var age := now - float(e[2])
		var p: Vector2 = e[1]
		if age > 3.0:
			continue
		keep.append(e)
		if p.x < x0 - 3 or p.x > x1 + 3 or p.y < y0 - 3 or p.y > y1 + 4:
			continue
		var lp := p
		if raised:
			lp.y -= lift_at(p.x, p.y - 0.2)
		match String(e[0]):
			"tree":
				# it leans, then falls ever faster, lies a moment and fades; leaves and dust where it lands
				var dirn := 1.0 if MapChunks._hash(int(p.x), int(p.y)) % 2 == 0 else -1.0
				var fall := clampf(age / 1.1, 0.0, 1.0)
				var ang := dirn * fall * fall * 1.5
				var alpha := 1.0 if age < 1.6 else clampf(1.0 - (age - 1.6) / 1.2, 0.0, 1.0)
				var tex := Tex.get_tex(String(SCENERY[int(e[3])]))
				if tex != null:
					draw_set_transform(_origin + lp * zoom, ang, Vector2(zoom, zoom))
					draw_texture_rect(tex, Rect2(-0.5, -1.5, 1.0, 1.5), false, Color(1, 1, 1, alpha))
					draw_set_transform(_origin, 0.0, Vector2(zoom, zoom))
				# a stump stays
				draw_rect(Rect2(lp.x - 0.06, lp.y - 0.1, 0.12, 0.1), Color(0.45, 0.3, 0.18, alpha))
				if age > 1.0 and age < 1.8:
					var u := (age - 1.0) / 0.8
					var land := lp + Vector2(dirn * 1.1, -0.1)
					for k in 7:
						var a := -PI / 2.0 + (k - 3) * 0.4
						draw_circle(land + Vector2(cos(a), sin(a) * 0.5) * u * 0.5, 0.05 + u * 0.08, Color(0.75, 0.68, 0.5, 0.45 * (1.0 - u)))
						draw_circle(land + Vector2(cos(a + 0.2), sin(a + 0.2)) * u * 0.6 + Vector2(0, u * u * 0.3), 0.03, Color(0.35, 0.55, 0.25, 0.8 * (1.0 - u)))
			"fall":
				# a fallen soldier: he topples over, lies a while and fades
				if age > 2.8:
					continue
				var info: Array = e[3]
				var tilt := clampf(age / 0.4, 0.0, 1.0) * (PI / 2.0) * (-1.0 if bool(info[2]) else 1.0)
				var fa := 1.0 if age < 1.8 else clampf(1.0 - (age - 1.8) / 1.0, 0.0, 1.0)
				var ec := _spr_info(String(info[0]))
				var stex: Texture2D = ec[0]
				var fw: float = ec[2]
				var src := Rect2(0, 0, fw, float(ec[3]))
				var hgt := 0.5 * src.size.y / maxf(1.0, src.size.x)
				draw_set_transform(_origin + lp * zoom, tilt, Vector2(zoom, zoom))
				var cc: Color = info[1]
				draw_texture_rect_region(stex, Rect2(-0.25, -hgt, 0.5, hgt), src, Color(cc.r, cc.g, cc.b, fa))
				draw_set_transform(_origin, 0.0, Vector2(zoom, zoom))
			"done":
				# a ring of dust rolling out from the walls, and sparkles rising
				if age > 1.8:
					continue
				var u := age / 1.8
				var w: float = float(e[3]) * 0.6
				for k in 10:
					var a := k * TAU / 10.0
					var d := Vector2(cos(a) * w * (0.6 + u * 0.9), sin(a) * 0.35 * (0.6 + u * 0.9))
					draw_circle(lp + d, 0.12 + u * 0.25, Color(0.86, 0.82, 0.72, 0.5 * (1.0 - u)))
				for k in 6:
					var sx := lp + Vector2((k - 2.5) * w * 0.35, -0.6 - u * 1.4 - float(k % 3) * 0.2)
					var r := 0.08 * (1.0 - u)
					var sc := Color(1.0, 0.92, 0.55, 1.0 - u)
					draw_line(sx - Vector2(r, 0), sx + Vector2(r, 0), sc, 0.03)
					draw_line(sx - Vector2(0, r), sx + Vector2(0, r), sc, 0.03)
	_fx = keep


## Ruins: broken stone walls and rubble (grey once looted). Bandit camps: tents round a fire, a few
## bandits about, and soldiers marching out to clear it.
func _draw_places(x0: int, y0: int, x1: int, y1: int, fog_on: bool, fog) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for pl: Dictionary in sim.places:
		var x := int(pl.x)
		var y := int(pl.y)
		if x < x0 - 2 or x > x1 + 2 or y < y0 - 2 or y > y1 + 3:
			continue
		if fog_on and not fog.explored_at(sim.idx(x, y)):
			continue
		var base := Vector2(x + 0.5, y + 0.9)
		if raised:
			base.y -= lift_at(base.x, base.y - 0.2)
		if pl.kind == "ruins":
			var stone := Color(0.62, 0.6, 0.55) if not bool(pl.done) else Color(0.5, 0.49, 0.46)
			draw_texture_rect(_shadow, Rect2(base.x - 0.9, base.y - 0.35, 1.9, 0.6), false)
			# a broken wall: blocks of uneven height, a gap, an arch stump
			for k in 5:
				var hgt: float = [0.55, 0.85, 0.3, 0.7, 0.45][k]
				var bx := base.x - 0.8 + k * 0.33
				draw_rect(Rect2(bx, base.y - hgt, 0.28, hgt), stone)
				draw_rect(Rect2(bx, base.y - hgt, 0.28, 0.06), stone.lightened(0.2))
				draw_line(Vector2(bx, base.y - hgt * 0.5), Vector2(bx + 0.28, base.y - hgt * 0.5), stone.darkened(0.25), 0.02)
			for k in 4:
				draw_circle(base + Vector2(-0.6 + k * 0.4, 0.05), 0.08, stone.darkened(0.15))
			if not bool(pl.done) and animate:
				# something glints among the stones
				if fmod(t * 0.7 + x, 3.0) < 0.25:
					var g := base + Vector2(0.15, -0.25)
					draw_line(g - Vector2(0.08, 0), g + Vector2(0.08, 0), Color(1, 0.95, 0.6), 0.03)
					draw_line(g - Vector2(0, 0.08), g + Vector2(0, 0.08), Color(1, 0.95, 0.6), 0.03)
			continue
		# a bandit camp
		var cleared := bool(pl.done)
		draw_texture_rect(_shadow, Rect2(base.x - 1.2, base.y - 0.4, 2.4, 0.7), false)
		for k in 3:
			var tp := base + Vector2(-0.8 + k * 0.75, -0.05 * k)
			var tc := Color(0.55, 0.32, 0.22) if k != 1 else Color(0.45, 0.36, 0.25)
			if cleared:
				tc = tc.darkened(0.4)
			draw_colored_polygon(PackedVector2Array([tp + Vector2(-0.35, 0), tp + Vector2(0, -0.6), tp + Vector2(0.35, 0)]), tc)
			draw_colored_polygon(PackedVector2Array([tp + Vector2(-0.08, 0), tp + Vector2(0, -0.25), tp + Vector2(0.08, 0)]), Color(0.12, 0.08, 0.05))
		if cleared:
			continue
		# the fire, its smoke, and bandits standing about
		var fp := base + Vector2(0.0, 0.35)
		if animate:
			for k in 3:
				var fl := 0.18 + 0.08 * sin(t * 11.0 + k * 2.0)
				draw_colored_polygon(PackedVector2Array([fp + Vector2(-0.08 + k * 0.06, 0), fp + Vector2(-0.04 + k * 0.06, -fl), fp + Vector2(0.0 + k * 0.06, 0)]), Color(1.0, 0.55, 0.15, 0.9))
			for k in 3:
				var ph := fmod(t * 0.4 + k * 0.33, 1.0)
				draw_circle(fp + Vector2(sin(t + k) * 0.1 + ph * 0.3, -0.3 - ph * 1.2), 0.08 + ph * 0.15, Color(0.3, 0.3, 0.3, 0.4 * (1.0 - ph)))
		for k in mini(int(pl.n), 3):
			var bp := base + Vector2(-0.55 + k * 0.55, 0.55)
			_sprite(_soldier_id(0), bp, 0.42, int(t * 2.0 + k) % 2, k % 2 == 0, Color(0.35, 0.3, 0.28))
		# soldiers marching out to clear it
		var pp := Places.party_pos(sim, pl)
		if pp.x >= 0.0:
			var party: Dictionary = pl.party
			var pc: Color = sim.players[int(party.p) - 1].color.lightened(0.2)
			var dir := (Vector2(x, y) - pp).normalized()
			for k in mini(int(party.n), 4):
				_sprite(_soldier_id(roundi(Sim.mix_avg(party.mix))), pp + Vector2(0.5, 0.75) - dir * 0.36 * k, 0.5, int(t * 5.0 + k) % 4, dir.x < 0, pc)


## Soldiers falling: when a column (key: its uid) or a garrison (key: minus the building's id) has
## fewer than last time it was drawn, that many fall where they fight and fade out.
var _last_n := {}

func _track_losses(key: int, n: int, where: Vector2, sid: String, col: Color, flip: bool) -> void:
	var was := int(_last_n.get(key, n))
	_last_n[key] = n
	if not animate or n >= was:
		return
	var now := Time.get_ticks_msec() / 1000.0
	for k in mini(was - n, 4):
		_fx.append(["fall", where + Vector2((k - 1) * 0.22, 0.05 * k), now, [sid, col, flip]])
	if _last_n.size() > 400:
		_last_n.clear()


## A rowing boat with its keel at p, facing right when fl is 1 (left at -1), sz tiles long.
func _boat(p: Vector2, fl: float, sz: float) -> void:
	var w := sz
	draw_colored_polygon(PackedVector2Array([p + Vector2(-w * 0.5 * fl, -0.08), p + Vector2(w * 0.55 * fl, -0.1), p + Vector2(w * 0.38 * fl, 0.04), p + Vector2(-w * 0.4 * fl, 0.04)]), Color("6b4a2a"))
	draw_line(p + Vector2(-w * 0.5 * fl, -0.08), p + Vector2(w * 0.55 * fl, -0.1), Color("8a6440"), 0.03)
	# its wake: two thin ripples spreading behind it
	var rr := fmod(Time.get_ticks_msec() / 1000.0 * 0.6, 1.0)
	draw_arc(p + Vector2(0, 0.03), w * (0.5 + rr * 0.4), 0.2, PI - 0.2, 12, Color(1, 1, 1, 0.35 * (1.0 - rr)), 0.02)


## A worker: the picture as it is, then the tunic in the realm's colour (an older single-layer picture
## is tinted whole, as before). Returns the drawn height.
func _person(id: String, at: Vector2, f: int, flip: bool, col: Color) -> float:
	var e := _spr_info(id)
	if int(e[1]) >= 10:
		var hh := _sprite(id, at, 0.4, f, flip)
		if bool(e[4]):
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
const SCN_PX := 128                # atlas pixels per tile (mipmapped, so far out stays smooth)
var _scn_shadow_uv := Rect2()      # where the shadow lies in the scenery atlas
const SCN_PEAK := 5
const SCN_ROCK := 7


func _make_scenery_atlas() -> void:
	var n := SCENERY.size()
	var cw := SCN_PX + 4
	var chh := SCN_PX * 3 / 2 + 4
	# one cell more at the end: the soft shadow laid under trees and boulders
	var img := Image.create(cw * (n + 1), chh, false, Image.FORMAT_RGBA8)
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
	var sh := (_shadow as ImageTexture).get_image() if _shadow is ImageTexture else _make_shadow().get_image()
	sh = sh.duplicate()
	sh.clear_mipmaps()
	var sat := Vector2i(n * cw + 2, chh - 2 - sh.get_height())
	img.blit_rect(sh, Rect2i(0, 0, sh.get_width(), sh.get_height()), sat)
	_scn_shadow_uv = Rect2(Vector2(sat) / Vector2(img.get_size()), Vector2(sh.get_size()) / Vector2(img.get_size()))
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
	# shadows go in first, so every tree stands on top of its neighbours' shadows
	var sv := PackedVector2Array()
	var su := PackedVector2Array()
	var suv := _scn_shadow_uv
	var shade := Color(1, 1, 1, 1)
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
			# its shadow (not for mountain peaks, whose shade is in the ground)
			if k < SCN_PEAK or k >= SCN_ROCK:
				var sw := sz.x * (0.78 if k < SCN_PEAK else 0.95)
				var shh := sw * (0.34 if k < SCN_PEAK else 0.42)
				var sc0 := Vector2(foot.x + SUN.x * sz.y * 0.9, foot.y - lift - 0.06)
				var stl := sc0 - Vector2(sw / 2.0, shh * 0.55)
				sv.append_array(PackedVector2Array([stl, stl + Vector2(sw, 0), stl + Vector2(sw, shh), stl + Vector2(0, shh)]))
				su.append_array(PackedVector2Array([suv.position, suv.position + Vector2(suv.size.x, 0), suv.end, suv.position + Vector2(0, suv.size.y)]))
			var n := verts.size()
			verts.append_array(PackedVector2Array([tl, tl + Vector2(sz.x, 0), tl + sz, tl + Vector2(0, sz.y)]))
			uvs.append_array(PackedVector2Array([uv.position, uv.position + Vector2(uv.size.x, 0), uv.end, uv.position + Vector2(0, uv.size.y)]))
			var b := 0.9 + float((hh >> 3) % 15) / 100.0
			var c := Color(b, b, b)
			# a tree's top corners are marked to sway in the wind (see map_sway.gdshader)
			var ct := Color(b, b, b, SWAY_TREE) if k < SCN_PEAK else c
			cols.append_array(PackedColorArray([ct, ct, c, c]))
			idx.append_array(PackedInt32Array([n, n + 1, n + 2, n, n + 2, n + 3]))
	if verts.is_empty():
		return null
	# the shadows first, then the trees and rocks
	if not sv.is_empty():
		var ns := sv.size()
		var idx2 := PackedInt32Array()
		for q in ns / 4:
			var o := q * 4
			idx2.append_array(PackedInt32Array([o, o + 1, o + 2, o, o + 2, o + 3]))
		for v in idx.size():
			idx[v] += ns
		idx2.append_array(idx)
		idx = idx2
		sv.append_array(verts); verts = sv
		su.append_array(uvs); uvs = su
		var sc2 := PackedColorArray()
		sc2.resize(ns)
		sc2.fill(shade)
		sc2.append_array(cols); cols = sc2
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
