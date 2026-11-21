extends Feature
## Fog of war, watch towers and scouts.
## You see only what your realm can see: your own land, a few tiles around each building, further from
## military buildings, 14 tiles from a watch tower with a scout inside, and around scouts out exploring.
## Land you have seen once stays on the map (explored), but darkened, and rival buildings there show
## as you last saw them; their soldiers and carriers show only in sight. Unexplored land is black.
## Scouts are trained at the scout lodge. Idle scouts can be sent to any spot on the map (the Send
## scout tool in the Military tab): one walks there and back, seeing 5 tiles around him, and turns
## back at the shore. Rivals are not limited by the fog (the computer plays without it).

const SCOUT_SIGHT := 5
const SCOUT_SPEED := 1.1           # tiles a second
const BLD_SIGHT := 3
const HQ_SIGHT := 11

var explored := PackedByteArray()  # your realm: 1 where the land has been seen
var vis := PackedByteArray()       # your realm: 1 where it is seen right now (worked out every second)
var seen: Dictionary = {}          # tile -> [building type, realm id, under construction] last seen there
var walks: Array = []              # scouts out: [realm id, path (tiles), t0, t_turn, t_home]
var tex: CanvasTexture             # the fog picture, a pixel a tile, smoothed, for the map and the minimap
var _img_tex: ImageTexture
var _img_dirty := true
var _bsig := ""                    # what _bvis was worked out from
var _bvis := PackedByteArray()      # what your land and buildings see (without scouts and columns)
var _sig := ""                     # what the sight was last worked out from; unchanged means nothing to do
# On big maps whole-map loops in script are slow, so the work below is done again only for rows of the
# map that changed (the engine compares a row at once):
var _own_last := PackedByteArray()  # sim.owner when _own_vis was last brought up to date
var _own_vis := PackedByteArray()   # 1 where your realm holds the land
var _img_data := PackedByteArray()  # the fog picture's pixels (one a tile, before smoothing)
var _img_exp := PackedByteArray()   # explored and vis as the picture last showed them
var _img_vis := PackedByteArray()


## Whether row y of a and b differ (both w wide).
static func _row_differs(a: PackedByteArray, b: PackedByteArray, y: int, w: int) -> bool:
	var s := y * w
	return a.slice(s, s + w) != b.slice(s, s + w)


func _init() -> void:
	id = "fog"
	title = "Fog of war, watch towers and scouts"
	info = "You see only what your land, buildings, watch towers and scouts can see. Explored land stays visible as you last saw it. Adds the scout lodge and watch tower."
	default_on = true


func on_start(loaded: bool) -> void:
	var n := sim.w * sim.h
	if explored.size() != n:
		explored = PackedByteArray()
		explored.resize(n)
	vis = PackedByteArray()
	vis.resize(n)
	_own_last = PackedByteArray()
	_img_exp = PackedByteArray()
	_sig = ""
	_bsig = ""
	# scouts counted as out with no walk to show for it (the feature was off for a while) are home
	for p: Sim.Player in sim.players:
		if not walks.any(func(wk): return int(wk[0]) == p.id):
			p.scout_out = 0
	_update_sight()
	_img_dirty = true


func me() -> Sim.Player:
	return sim.human()


func visible_at(i: int) -> bool:
	return i >= 0 and i < vis.size() and vis[i] == 1


func explored_at(i: int) -> bool:
	return i >= 0 and i < explored.size() and explored[i] == 1


func _reveal(cx: int, cy: int, r: int, into: PackedByteArray = vis) -> void:
	var w := sim.w
	var r2 := r * r + r
	for y in range(maxi(0, cy - r), mini(sim.h - 1, cy + r) + 1):
		for x in range(maxi(0, cx - r), mini(w - 1, cx + r) + 1):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r2:
				var i := y * w + x
				into[i] = 1
				if explored[i] == 0:
					explored[i] = 1
					_img_dirty = true


## Where a scout out exploring is now, in tiles: along his path, then back along it.
func walk_pos(wk: Array) -> Vector2:
	var path: PackedInt32Array = wk[1]
	var n := path.size() - 1
	if n < 1:
		return Vector2(path[0] % sim.w, path[0] / sim.w)
	var t := sim.time
	var f := 0.0
	if t <= float(wk[3]):
		f = clampf((t - float(wk[2])) / maxf(0.01, float(wk[3]) - float(wk[2])), 0.0, 1.0)
	else:
		f = 1.0 - clampf((t - float(wk[3])) / maxf(0.01, float(wk[4]) - float(wk[3])), 0.0, 1.0)
	var k := mini(floori(f * n), n - 1)
	var a := path[k]
	var c := path[k + 1]
	return Vector2(a % sim.w, a / sim.w).lerp(Vector2(c % sim.w, c / sim.w), f * n - k)


func _update_sight() -> void:
	var p := me()
	if p == null:
		return
	# the sight changes only when the land, the buildings or a scout's position do
	var towers := 0
	var ready := 0
	var mine := sim.realm_blds(p)
	for b: Sim.Bld in mine:
		if b.def.has("vision") and b.staffed:
			towers += 1
		if b.state == "ready":
			ready += 1
	# your columns on the march and fleets at sea see where they go, as scouts do
	var cols := []
	for a: Sim.Attack in sim.attacks:
		if a.p == p.id and a.n > 0:
			cols.append(a)
	var sig := "%d:%d:%d:%d:%d:%d" % [sim.territory_version, mine.size(), ready, towers, walks.size(), cols.size()]
	if sig == _sig and walks.is_empty() and cols.is_empty():
		_remember_rivals(p)
		return
	_sig = sig
	var before := vis
	var n := sim.w * sim.h
	var w := sim.w
	# (build 66.1) what the land and buildings see changes only with them: worked out again only then;
	# scouts and columns on the march are added on top each second
	var bsig := "%d:%d:%d:%d" % [sim.territory_version, mine.size(), ready, towers]
	if bsig != _bsig or _bvis.size() != n:
		_bsig = bsig
		if _own_last.size() != n or _own_vis.size() != n:
			_own_vis = PackedByteArray()
			_own_vis.resize(n)
			_own_last = PackedByteArray()
			_own_last.resize(n)
			_own_last.fill(255)
		var own_moved := false
		for y in sim.h:
			if _row_differs(sim.owner, _own_last, y, w):
				own_moved = true
				for i2 in range(y * w, y * w + w):
					var o := 1 if sim.owner[i2] == p.id else 0
					_own_vis[i2] = o
					if o == 1 and explored[i2] == 0:
						explored[i2] = 1
						_img_dirty = true
		if own_moved:
			_own_last = sim.owner.duplicate()
		_bvis = _own_vis.duplicate()
		for b: Sim.Bld in mine:
			var r := BLD_SIGHT
			if b.ty == "hq":
				r = HQ_SIGHT
			elif b.def.has("vision"):
				r = int(b.def.vision) if (b.state == "ready" and b.staffed) else BLD_SIGHT
			elif b.def.has("radius") and b.state == "ready":
				r = int(b.def.radius) + 2
			_reveal(b.x, b.y, r, _bvis)
	vis = _bvis.duplicate()
	for wk in walks:
		if int(wk[0]) == p.id:
			var at := walk_pos(wk)
			_reveal(roundi(at.x), roundi(at.y), SCOUT_SIGHT)
	for a: Sim.Attack in cols:
		var cp: Vector2 = sim.military.column_pos(a)
		_reveal(roundi(cp.x), roundi(cp.y), SCOUT_SIGHT)
	if vis != before:
		_img_dirty = true
	_remember_rivals(p)


## Rival buildings in sight are remembered as they are; those seen gone are forgotten.
func _remember_rivals(p: Sim.Player) -> void:
	for k in seen.keys():
		if vis[k] == 1:
			seen.erase(k)
	for b: Sim.Bld in sim.blds:
		if b.p != p.id:
			var i := sim.idx(b.x, b.y)
			if vis[i] == 1:
				seen[i] = [b.ty, b.p, b.state == "build", b.era]


func on_second() -> void:
	# scouts coming home
	for i in range(walks.size() - 1, -1, -1):
		var wk: Array = walks[i]
		if sim.time >= float(wk[4]):
			var p: Sim.Player = sim.players[int(wk[0]) - 1]
			p.scout_out = maxi(0, p.scout_out - 1)
			walks.remove_at(i)
			if not p.ai:
				sim.emit_log("A scout is back from exploring.", Color("9fd0e8"))
	_update_sight()
	if _img_dirty:
		_make_image()


func _make_image() -> void:
	_img_dirty = false
	var w := sim.w
	var h := sim.h
	var n := w * h
	if _img_data.size() != n * 4 or _img_exp.size() != n or _img_vis.size() != n:
		_img_data = PackedByteArray()
		_img_data.resize(n * 4)
		_img_exp = PackedByteArray()
		_img_exp.resize(n)
		_img_exp.fill(255)          # every row is drawn
		_img_vis = PackedByteArray()
		_img_vis.resize(n)
	var data := _img_data
	for y in h:
		if not _row_differs(explored, _img_exp, y, w) and not _row_differs(vis, _img_vis, y, w):
			continue
		for i in range(y * w, y * w + w):
			var a := 0
			if explored[i] == 0:
				a = 255
			elif vis[i] == 0:
				a = 120
			data[i * 4] = 10; data[i * 4 + 1] = 12; data[i * 4 + 2] = 14; data[i * 4 + 3] = a
	_img_data = data
	_img_exp = explored.duplicate()
	_img_vis = vis.duplicate()
	# one pixel a tile, smoothed by the graphics card so the edge of sight is soft (build 66.1: it was
	# made four times as big on the processor, a stall of up to a tenth of a second each second)
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	if _img_tex == null or _img_tex.get_width() != img.get_width():
		_img_tex = ImageTexture.create_from_image(img)
		tex = CanvasTexture.new()
		tex.diffuse_texture = _img_tex
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	else:
		_img_tex.update(img)


# ---------------------------------------------------------------- scouting

## Sends an idle scout of realm p from the nearest store to tile (x, y). Returns "" or why not.
func send_scout(p: Sim.Player, x: int, y: int) -> String:
	if not sim.inb(x, y):
		return "Outside the map"
	if p.scout - p.used_scout - p.scout_out < 1:
		return "No idle scout: train one at a scout lodge (towers keep theirs)"
	# start from the nearest store
	var best: Sim.Bld = p.hq
	var bd := 1e9
	for b: Sim.Bld in sim.realm_blds(p):
		if sim.is_store(b) and b.state == "ready":
			var d := Vector2(b.x - x, b.y - y).length()
			if d < bd:
				bd = d; best = b
	var path := sim.logistics.land_path(sim.idx(best.x, best.y), sim.idx(x, y))
	if path.size() < 3:
		return "He can't get there over land"
	var walk := (path.size() - 1) / SCOUT_SPEED
	walks.append([p.id, path, sim.time, sim.time + walk, sim.time + walk * 2.0])
	p.scout_out += 1
	sim.staffing(p)
	return ""


func tools(cat: String) -> Array:
	if cat == "mil":
		return [["@scout", "Send scout", "unit_scout", "Click any spot on the map: an idle scout walks there and back, lifting the fog around him."]]
	return []


func use_tool(tool: String, t: Vector2i) -> String:
	if tool != "@scout":
		return "?"
	var r := send_scout(me(), t.x, t.y)
	return r if r != "" else "A scout sets out."


# ---------------------------------------------------------------- interface

func panel_lines(p: Sim.Player) -> PackedStringArray:
	var idle := p.scout - p.used_scout - p.scout_out
	if p.scout == 0:
		return PackedStringArray(["Scouts  none (train them at a scout lodge)"])
	return PackedStringArray(["Scouts  [b]%d[/b]: %d in watch towers, %d exploring, %d idle" % [p.scout, p.used_scout, p.scout_out, idle]])


func building_lines(b: Sim.Bld) -> PackedStringArray:
	if b.def.has("vision"):
		if b.state == "ready" and not b.staffed:
			return PackedStringArray(["[color=#f0a090]No scout inside: it sees only %d tiles. Train scouts at a scout lodge.[/color]" % BLD_SIGHT])
		return PackedStringArray(["Sees %d tiles around." % int(b.def.vision)])
	return PackedStringArray()


func tile_lines(i: int) -> PackedStringArray:
	if not explored_at(i):
		return PackedStringArray(["[color=#9a9c88]Unexplored. Send a scout, or build a watch tower nearby.[/color]"])
	if not visible_at(i):
		return PackedStringArray(["[color=#9a9c88]Out of sight: you see it as it was when last seen.[/color]"])
	return PackedStringArray()


## Rival buildings out of sight, drawn as last seen, then the fog itself over everything.
func draw_top(view: CanvasItem, rect: Rect2i) -> void:
	if tex == null:
		return
	var mv = view   # the map view, untyped so its own drawing helpers can be called
	var w := sim.w
	for k in seen:
		var x: int = k % w
		var y: int = k / w
		if x < rect.position.x - 2 or y < rect.position.y - 1 or x > rect.end.x + 2 or y > rect.end.y + 3:
			continue
		var e: Array = seen[k]
		mv.draw_ghost(String(e[0]), x, y, sim.players[int(e[1]) - 1].color, bool(e[2]), int(e[3]) if e.size() > 3 else 1)
	# scouts out exploring
	for wk in walks:
		var at := walk_pos(wk)
		if int(wk[0]) == sim.human().id or visible_at(sim.idx(roundi(at.x), roundi(at.y))):
			var going := sim.time <= float(wk[3])
			var path: PackedInt32Array = wk[1]
			var dir := float(path[path.size() - 1] % sim.w - path[0] % sim.w)
			mv._sprite("unit_scout", at + Vector2(0.5, 0.8 - float(mv.lift_at(at.x + 0.5, at.y + 0.8))), 0.42, int(sim.time * 5.0) % 4, (dir < 0) == going, sim.players[int(wk[0]) - 1].color.lightened(0.35))
	# (the map's shader knows the fog by this colour and gives it a soft, misty edge)
	mv.draw_map_texture(view, tex, MapView.FOG_TAG)


func save_state() -> Dictionary:
	return {"explored": explored, "seen": seen, "walks": walks}


func load_state(d: Dictionary) -> void:
	explored = d.get("explored", PackedByteArray())
	_own_last = PackedByteArray()
	_img_exp = PackedByteArray()
	_sig = ""
	_bsig = ""
	seen = {}
	for k in d.get("seen", {}):
		seen[int(k)] = d.seen[k]
	walks = d.get("walks", [])
