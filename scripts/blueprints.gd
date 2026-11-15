class_name Blueprints
extends RefCounted
## Blueprints (build 58): a group of buildings and the roads between them, copied from your own land
## and kept across games in user://blueprints.json, sorted into categories. Placing one puts down
## every building site and road at once; trees and roads in the way are listed first, so the
## player can be asked whether to clear them (Blueprints.obstacles, Blueprints.clear).
##
## A blueprint: {"name", "cat", "w", "h", "items": [[type, dx, dy, door], ...], "roads": [[dx, dy], ...]}
## with every offset from the top-left corner of the area it was copied from.

const FILE := "user://blueprints.json"
const DEFAULT_CATS := ["Food", "Industry", "Homes", "Military", "Other"]
const MAX_SIZE := 40          # the largest area copied, in tiles a side

var cats: Array = DEFAULT_CATS.duplicate()
var list: Array = []          # the blueprints, in the order they were made
var file := FILE


func _init(path := FILE) -> void:
	file = path
	load_file()


func load_file() -> void:
	cats = DEFAULT_CATS.duplicate()
	list = []
	if file == "" or not FileAccess.file_exists(file):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not d is Dictionary:
		return
	if d.get("cats") is Array and not (d.cats as Array).is_empty():
		cats = []
		for c in d.cats:
			cats.append(String(c))
	if d.get("list") is Array:
		for bp in d.list:
			var ok := tidy(bp)
			if not ok.is_empty():
				list.append(ok)
	for bp in list:
		if not cats.has(bp.cat):
			cats.append(bp.cat)


func save_file() -> void:
	if file == "":
		return
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"version": 1, "cats": cats, "list": list}, " "))


## A blueprint read from a file or a code, checked and with whole numbers ({} when it is no good).
static func tidy(bp) -> Dictionary:
	if not bp is Dictionary or not bp.get("items") is Array:
		return {}
	var out := {"name": String(bp.get("name", "Blueprint")).left(40), "cat": String(bp.get("cat", "Other")).left(24),
		"w": clampi(int(bp.get("w", 1)), 1, MAX_SIZE), "h": clampi(int(bp.get("h", 1)), 1, MAX_SIZE), "items": [], "roads": []}
	for it in bp.items:
		if it is Array and it.size() >= 4 and GameData.bld.has(String(it[0])):
			out.items.append([String(it[0]), int(it[1]), int(it[2]), int(it[3])])
	for r in bp.get("roads", []):
		if r is Array and r.size() >= 2:
			out.roads.append([int(r[0]), int(r[1])])
	if out.items.is_empty():
		return {}
	if out.cat == "":
		out.cat = "Other"
	return out


# ---------------------------------------------------------------- the list

func add(bp: Dictionary) -> void:
	list.append(bp)
	if not cats.has(bp.cat):
		cats.append(bp.cat)
	save_file()


func remove(i: int) -> void:
	if i >= 0 and i < list.size():
		list.remove_at(i)
		save_file()


func rename(i: int, name: String) -> void:
	if i >= 0 and i < list.size() and name.strip_edges() != "":
		list[i].name = name.strip_edges().left(40)
		save_file()


func set_cat(i: int, cat: String) -> void:
	if i >= 0 and i < list.size():
		list[i].cat = cat
		if not cats.has(cat):
			cats.append(cat)
		save_file()


func add_cat(cat: String) -> bool:
	cat = cat.strip_edges().left(24)
	if cat == "" or cats.has(cat):
		return false
	cats.append(cat)
	save_file()
	return true


## Removes category cat; its blueprints go to "Other" (which is never removed).
func remove_cat(cat: String) -> void:
	if cat == "Other" or not cats.has(cat):
		return
	cats.erase(cat)
	for bp in list:
		if bp.cat == cat:
			bp.cat = "Other"
	if not cats.has("Other"):
		cats.append("Other")
	save_file()


## The blueprints of category cat, as indexes into the list.
func in_cat(cat: String) -> Array:
	var out := []
	for i in list.size():
		if list[i].cat == cat:
			out.append(i)
	return out


## A blueprint as text to share (paste it in another game or send it to a friend).
static func to_code(bp: Dictionary) -> String:
	return "HLBP1:" + Marshalls.utf8_to_base64(JSON.stringify(bp))


static func from_code(code: String) -> Dictionary:
	code = code.strip_edges()
	if not code.begins_with("HLBP1:"):
		return {}
	var txt := Marshalls.base64_to_utf8(code.substr(6))
	return tidy(JSON.parse_string(txt))


# ---------------------------------------------------------------- copying from the map

## Realm pid's buildings and roads in area r (tiles, inclusive), as a blueprint ({} when there is no
## building to copy). The headquarters and wonders (built once) are left out.
static func capture(sim: Sim, pid: int, r: Rect2i, name := "Blueprint", cat := "Other") -> Dictionary:
	r = r.abs()
	r.size = Vector2i(mini(r.size.x, MAX_SIZE), mini(r.size.y, MAX_SIZE))
	var items := []
	var roads := []
	for b in sim.blds:
		if b.dead or b.p != pid or b.ty == "hq" or bool(b.def.get("unique", false)):
			continue
		if r.has_point(Vector2i(b.x, b.y)):
			items.append([b.ty, b.x - r.position.x, b.y - r.position.y, b.door])
	if items.is_empty():
		return {}
	# a tidy order: rows top to bottom, so the list and the placing go the same way every time
	items.sort_custom(func(a, c): return a[2] < c[2] or (a[2] == c[2] and a[1] < c[1]))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if sim.inb(x, y) and sim.road[sim.idx(x, y)] == pid and sim.bmap[sim.idx(x, y)] == 0 and sim.ter[sim.idx(x, y)] != Sim.WATER:
				roads.append([x - r.position.x, y - r.position.y])
	return {"name": name, "cat": cat, "w": r.size.x, "h": r.size.y, "items": items, "roads": roads}


## How many of each building a blueprint has: "2 woodcutters, 1 sawmill".
static func summary(bp: Dictionary) -> String:
	var n := {}
	var order := []
	for it in bp.items:
		if not n.has(it[0]):
			order.append(it[0])
		n[it[0]] = int(n.get(it[0], 0)) + 1
	var parts := []
	for ty in order:
		parts.append(("%d× %s" if int(n[ty]) > 1 else "%d %s") % [n[ty], String(GameData.bld[ty].name).to_lower()])
	return ", ".join(parts)


## What a blueprint's buildings cost together.
static func cost(bp: Dictionary) -> Dictionary:
	var c := {}
	for it in bp.items:
		var bc: Dictionary = GameData.bld[it[0]].get("cost", {})
		for k in bc:
			c[k] = int(c.get(k, 0)) + int(bc[k])
	return c


# ---------------------------------------------------------------- placing

## The tiles a blueprint's buildings would stand on at top-left corner at (each with its plot).
static func _bld_tiles(sim: Sim, bp: Dictionary, at: Vector2i) -> Dictionary:
	var out := {}
	for it in bp.items:
		var x: int = at.x + int(it[1])
		var y: int = at.y + int(it[2])
		if not sim.inb(x, y):
			continue
		out[sim.idx(x, y)] = true
		for t in sim.plot_tiles(String(it[0]), x, y):
			out[t] = true
	return out


## What stands in the way of a blueprint at top-left corner at, that the player may clear: trees on
## the buildings' plots, and realm pid's roads crossing them (roads the blueprint keeps are not in the
## way). {"trees": tiles, "roads": tiles}.
static func obstacles(sim: Sim, pid: int, bp: Dictionary, at: Vector2i) -> Dictionary:
	var trees := PackedInt32Array()
	var roads := PackedInt32Array()
	for t: int in _bld_tiles(sim, bp, at):
		if sim.owner[t] != pid or sim.bmap[t] != 0:
			continue
		if sim.deco[t] == Sim.D_TREE:
			trees.append(t)
		if sim.road[t] == pid:
			roads.append(t)
	return {"trees": trees, "roads": roads}


## The same for one building of type ty at (x, y) (its own tile and its plot).
static func obstacles_one(sim: Sim, pid: int, ty: String, x: int, y: int) -> Dictionary:
	return obstacles(sim, pid, {"items": [[ty, 0, 0, -1]], "roads": []}, Vector2i(x, y))


## Clears what obstacles() found: the trees are felled (the wood is lost) and the roads taken up.
static func clear(sim: Sim, pid: int, obs: Dictionary) -> void:
	for t: int in obs.get("trees", []):
		if sim.deco[t] == Sim.D_TREE:
			sim.deco[t] = 0
			sim.amt[t] = 0
			sim.changed_tiles.append(t)
	var any := false
	for t: int in obs.get("roads", []):
		if sim.road[t] == pid and sim.bmap[t] == 0:
			sim.road[t] = 0
			sim.pave[t] = 0
			sim.changed_tiles.append(t)
			any = true
	if any:
		sim.net_dirty(pid)


## Whether building type ty would fit at (x, y) once obs (from obstacles_one) were cleared. The map
## is changed for the check and put back as it was.
static func fits_cleared(sim: Sim, pid: int, ty: String, x: int, y: int, door: int, obs: Dictionary) -> bool:
	# the road network and its reach worked out first, on the map as it is, so nothing is cached from
	# the changed map
	sim.logistics.reach(pid)
	var deco := {}
	var road := {}
	for t: int in obs.get("trees", []):
		deco[t] = sim.deco[t]; sim.deco[t] = 0
	for t: int in obs.get("roads", []):
		road[t] = sim.road[t]; sim.road[t] = 0
	var why := sim.can_place(ty, x, y, pid, door)
	for t in deco: sim.deco[t] = deco[t]
	for t in road: sim.road[t] = road[t]
	return why == ""


## Why each building of a blueprint at top-left corner at could not be placed now (type -> reason
## of the first one refused), or {} when all fit. Used for the coloured ghost.
static func check(sim: Sim, pid: int, bp: Dictionary, at: Vector2i) -> Array:
	var out := []
	for it in bp.items:
		var x: int = at.x + int(it[1])
		var y: int = at.y + int(it[2])
		out.append(sim.can_place(String(it[0]), x, y, pid, int(it[3])) if sim.inb(x, y) else "Outside the map")
	return out


## Puts a blueprint down at top-left corner at for realm p: its roads first (on the realm's own free
## land), then every building site that fits. Returns [sites placed, {reason: how many refused}].
static func place(sim: Sim, p: Sim.Player, bp: Dictionary, at: Vector2i) -> Array:
	var bt := _bld_tiles(sim, bp, at)
	var path := PackedInt32Array()
	for r in bp.roads:
		var x: int = at.x + int(r[0])
		var y: int = at.y + int(r[1])
		if not sim.inb(x, y):
			continue
		var i := sim.idx(x, y)
		if sim.owner[i] != p.id or sim.ter[i] == Sim.WATER or sim.bmap[i] != 0 or sim.plot[i] != 0 or bt.has(i):
			continue
		if sim.deco[i] == Sim.D_ROCK or sim.deco[i] == Sim.D_CLAY or sim.road[i] == p.id:
			continue
		path.append(i)
	if not path.is_empty():
		sim.lay_road(path, p.id)
	var placed := 0
	var why := {}
	var news := []
	for it in bp.items:
		var ty := String(it[0])
		var x: int = at.x + int(it[1])
		var y: int = at.y + int(it[2])
		var door := int(it[3])
		var r := "Outside the map"
		if sim.inb(x, y):
			# joined to the blueprint's roads where its entrance has one; otherwise its own road is laid
			var dt := sim.door_at(x, y, door)
			var joined := dt >= 0 and sim.road[dt] == p.id
			r = sim.place(ty, x, y, p, door, not joined)
			if r != "" and not joined:
				r = sim.place(ty, x, y, p, door, false)
		if r == "":
			placed += 1
			news.append(sim.bld_at(x, y))
		else:
			why[r] = int(why.get(r, 0)) + 1
	# the blueprint's roads may stand alone where it was put: each building not yet joined to a store
	# gets the shortest road from its entrance to the realm's roads
	for b: Sim.Bld in news:
		if b != null and not sim.connected(b):
			var p2 := sim._path_to_net(b.x, b.y, p.id, b.door)
			if p2.size() > 1 and sim.logistics.bridge_cost_ok(p2, p.id) == "":
				sim.lay_road(p2, p.id)
	return [placed, why]
