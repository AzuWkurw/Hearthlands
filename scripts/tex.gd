class_name Tex
extends RefCounted
## Texture lookup with user overrides.
## For an id like "bld_sawmill" the game looks for, in order:
##   1. user://textures/bld_sawmill.png   (your custom texture, any size)
##   2. res://textures/bld_sawmill.png    (the default shipped with the project)
##   3. a magenta placeholder, so a missing file is obvious in game.

const USER_DIR := "user://textures"
const TERRAIN := ["water", "beach", "grass", "mountain"]
const VARIANTS := 4

## Animated textures are strips of frames side by side: id -> [frame count, width / height of one frame].
## A replacement PNG may be a strip with the same number of frames, or a single still picture.
const ANIM := {
	"unit_carrier": [4, 0.8], "unit_soldier": [6, 0.75], "unit_mule": [8, 1.308], "unit_cart": [8, 1.923],
	"unit_flag": [4, 0.714], "unit_sheep": [4, 1.2], "unit_pig": [4, 1.2],
	# people: 8 walking frames, then working (2) or talking (2) and standing (1); porters walk loaded (8),
	# empty (8), then set their load down (2). The *_tint strips are the tunic alone, drawn in the realm's colour.
	"unit_worker_axe": [10, 0.667], "unit_worker_pick": [10, 0.667], "unit_worker_shovel": [10, 0.667],
	"unit_worker_rod": [10, 0.667], "unit_worker_seed": [10, 0.667], "unit_worker_hammer": [10, 0.667],
	"unit_worker_axe_tint": [10, 0.667], "unit_worker_pick_tint": [10, 0.667], "unit_worker_shovel_tint": [10, 0.667],
	"unit_worker_rod_tint": [10, 0.667], "unit_worker_seed_tint": [10, 0.667], "unit_worker_hammer_tint": [10, 0.667],
	"unit_porter": [18, 0.667], "unit_porter_tint": [18, 0.667], "unit_porter_w": [18, 0.667], "unit_porter_w_tint": [18, 0.667],
	"unit_folk_peasant": [11, 0.667], "unit_folk_woman": [11, 0.667], "unit_folk_artisan": [11, 0.667],
	"unit_folk_noble": [11, 0.667], "unit_folk_child": [11, 0.667], "unit_folk_newcomer": [11, 0.667],
	# an ox cart's load, 1 to 6 units, drawn over the cart
	"unit_load_planks": [6, 1.923], "unit_load_stone": [6, 1.923], "unit_load_grain": [6, 1.923],
	"unit_load_wood": [6, 1.923], "unit_load_crates": [6, 1.923],
	"unit_scout": [4, 0.8], "unit_soldier_e0": [6, 0.75], "unit_soldier_e1": [6, 0.75], "unit_soldier_e2": [6, 0.75],
	"unit_soldier_e3": [6, 0.75], "unit_soldier_e4": [6, 0.75], "unit_soldier_e5": [6, 0.75], "unit_deer": [4, 1.143], "unit_boar": [4, 1.4], "unit_hare": [4, 1.125], "unit_wolf": [4, 1.455],
}

static var cache: Dictionary = {}
static var custom: Dictionary = {}
static var _frames: Dictionary = {}
static var _placeholder: Texture2D = null


static func get_tex(id: String) -> Texture2D:
	if cache.has(id):
		return cache[id]
	var t := _load(id)
	cache[id] = t
	return t


static func _load(id: String) -> Texture2D:
	var up := USER_DIR + "/" + id + ".png"
	if FileAccess.file_exists(up):
		var img := Image.load_from_file(up)
		if img != null and not img.is_empty():
			custom[id] = true
			# smaller copies for the GPU to use when zoomed out
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	var rp := "res://textures/" + id + ".png"
	if ResourceLoader.exists(rp):
		var r = load(rp)
		if r is Texture2D:
			return r
	if FileAccess.file_exists(rp):
		var img2 := Image.load_from_file(rp)
		if img2 != null and not img2.is_empty():
			return ImageTexture.create_from_image(img2)
	return placeholder()


## A building's picture in age era (0 Roman to 5 Industrial): your own bld_x_e<era>.png if there is
## one, else your own bld_x.png (it then stands for every age), else the built-in picture for that age,
## else the plain built-in one.
static func bld_era_tex(base: String, era: int) -> Texture2D:
	var id := "%s_e%d" % [base, clampi(era, 0, 5)]
	var key := "era:" + id
	if cache.has(key):
		return cache[key]
	var t: Texture2D
	if FileAccess.file_exists(USER_DIR + "/" + id + ".png"):
		t = get_tex(id)
	elif FileAccess.file_exists(USER_DIR + "/" + base + ".png"):
		t = get_tex(base)
	elif ResourceLoader.exists("res://textures/" + id + ".png"):
		t = get_tex(id)
	else:
		t = get_tex(base)
	cache[key] = t
	return t


static func placeholder() -> Texture2D:
	if _placeholder == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 16:
				img.set_pixel(x, y, Color.MAGENTA if ((x / 4 + y / 4) % 2 == 0) else Color.BLACK)
		_placeholder = ImageTexture.create_from_image(img)
	return _placeholder


static func reload() -> void:
	cache.clear()
	custom.clear()
	_frames.clear()


## How many animation frames the texture holds: the full count for a strip, 1 for a still picture.
static func frames(id: String) -> int:
	if _frames.has(id):
		return _frames[id]
	var n := 1
	if ANIM.has(id):
		var t := get_tex(id)
		var want: int = ANIM[id][0]
		var aspect: float = ANIM[id][1]
		if float(t.get_width()) / maxf(1.0, t.get_height()) >= want * aspect * 0.7:
			n = want
	_frames[id] = n
	return n


## The part of the texture that shows frame i (frames wrap around, so any i works).
static func frame_rect(id: String, i: int) -> Rect2:
	var t := get_tex(id)
	var n := frames(id)
	var fw := t.get_width() / float(n)
	return Rect2(fw * (posmod(i, n)), 0, fw, t.get_height())


static func ensure_user_dir() -> String:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	return ProjectSettings.globalize_path(USER_DIR)


static func open_user_dir() -> void:
	OS.shell_open(ensure_user_dir())


## Every texture id the game draws, grouped for the texture browser.
static func all_ids() -> Array:
	GameData.ensure()
	var out: Array = []
	for t in TERRAIN:
		for v in VARIANTS:
			out.append("terrain_%s_%d" % [t, v])
	for m in 16:
		out.append("road_%d" % m)
	for m in 16:
		out.append("road_paved_%d" % m)
	out.append_array(["deco_tree_0", "deco_tree_1", "deco_tree_2", "deco_rock_0", "deco_rock_1", "deco_clay", "deco_peak_0", "deco_peak_1"])
	for o in GameData.ORE_NAMES:
		out.append("ore_%d" % o)
	for r in GameData.resources:
		out.append("res_" + String(r.id))
	for b in GameData.bld:
		out.append(GameData.bld_tex_id(b))
		for e in 6:
			out.append("%s_e%d" % [GameData.bld_tex_id(b), e])
	for t in GameData.techs:
		out.append("tech_" + String(t))
	out.append_array(["fx_construction", "fx_smoke", "fx_glow", "anim_sails"])
	for a in ANIM:
		out.append(a)
	for c in GameData.CLASSES:
		out.append("ui_" + c)
	return out


## Writes every texture the game uses into user://textures as a starting point for editing.
## Existing files are left alone. Returns the number written.
static func export_defaults() -> int:
	ensure_user_dir()
	var n := 0
	for id: String in all_ids():
		var path := USER_DIR + "/" + id + ".png"
		if FileAccess.file_exists(path):
			continue
		var t := get_tex(id)
		if t == null:
			continue
		var img := t.get_image()
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		if img.save_png(path) == OK:
			n += 1
	return n


## Writes a manifest listing every texture id with its default size.
static func write_manifest() -> String:
	ensure_user_dir()
	var lines := ["Hearthlands texture list", "Put PNG files with these names in this folder to replace the defaults.", ""]
	for id: String in all_ids():
		var t := get_tex(id)
		lines.append("%s.png  (default %dx%d)%s" % [id, t.get_width(), t.get_height(), "  [custom]" if custom.has(id) else ""])
	var path := USER_DIR + "/TEXTURES.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
	return ProjectSettings.globalize_path(path)
