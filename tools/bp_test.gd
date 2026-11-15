extends SceneTree
## Build 58: blueprints. Copy buildings and roads from the map, place them again elsewhere, trees and
## roads in the way found and cleared, codes and the file. godot --headless --script res://tools/bp_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


## The first free spot for ty near (cx, cy), spiralling out; Vector2i(-1, -1) if none.
func spot(sim: Sim, ty: String, cx: int, cy: int, door := 0) -> Vector2i:
	for r in range(2, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and sim.can_place(ty, cx + dx, cy + dy, 1, door) == "":
					return Vector2i(cx + dx, cy + dy)
	return Vector2i(-1, -1)


func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("blueprint", 1, 4, true, 128, false, {"start_goods": 4.0})
	var me := sim.human()
	for i in 10: sim.tick(Sim.TICK)
	# the realm's land made wide and clear, so there is room to copy and place
	for y in range(maxi(0, me.hq.y - 24), mini(sim.h, me.hq.y + 25)):
		for x in range(maxi(0, me.hq.x - 24), mini(sim.w, me.hq.x + 25)):
			var i := sim.idx(x, y)
			if sim.owner[i] == 0: sim.owner[i] = 1
			if sim.ter[i] != Sim.WATER and sim.ter[i] != Sim.MOUNT and sim.bmap[i] == 0:
				sim.deco[i] = 0
	sim.net_dirty(1)
	# 1. three buildings with their roads
	var placed := []
	var near := Vector2i(me.hq.x, me.hq.y + 4)
	for ty in ["sawmill", "house", "house"]:
		var at := spot(sim, ty, near.x, near.y)
		if at.x >= 0: near = at
		var why := sim.place(ty, at.x, at.y, me, 0, true) if at.x >= 0 else "no spot"
		if why == "": placed.append(sim.bld_at(at.x, at.y))
	check(placed.size() == 3, "three buildings placed with their roads (%d)" % placed.size())
	var r := Rect2i(Vector2i(placed[0].x, placed[0].y), Vector2i.ZERO)
	for b in placed:
		r = r.expand(Vector2i(b.x, b.y))
	r = r.grow(1)
	r.size += Vector2i.ONE
	var bp := Blueprints.capture(sim, 1, r, "Wood corner", "Industry")
	check(bp.items.size() >= 3 and bp.w <= 12 and not (bp.roads as Array).is_empty(), "copied: %s, %d road tiles" % [Blueprints.summary(bp), (bp.roads as Array).size()])
	check(Blueprints.capture(sim, 1, Rect2i(me.hq.x, me.hq.y, 1, 1)).is_empty(), "the headquarters alone is not a blueprint")
	var c := Blueprints.cost(bp)
	check(int(c.get("planks", 0)) > 0, "a blueprint's cost adds its buildings up (%s)" % str(c))
	# 2. placed again elsewhere: a spot where every building fits
	var to := Vector2i(-1, -1)
	for k in range(6, 22):
		for d in [Vector2i(k, 0), Vector2i(-k, 0), Vector2i(0, k), Vector2i(0, -k), Vector2i(k, k), Vector2i(-k, -k)]:
			var at: Vector2i = r.position + d
			if to.x < 0 and Blueprints.check(sim, 1, bp, at).count("") == bp.items.size():
				to = at
	check(to.x >= 0, "a free place for it (%s)" % str(to))
	if to.x >= 0:
		var n0 := sim.blds.size()
		var res := Blueprints.place(sim, me, bp, to)
		check(int(res[0]) == bp.items.size() and sim.blds.size() == n0 + bp.items.size(), "all %d building sites go down at once (%s)" % [bp.items.size(), str(res[1])])
		var joined := 0
		for it in bp.items:
			var b := sim.bld_at(to.x + int(it[1]), to.y + int(it[2]))
			if b != null and b.ty == String(it[0]) and b.door == int(it[3]) and sim.connected(b):
				joined += 1
		check(joined == bp.items.size(), "each in its place, its entrance turned the same way, on the roads (%d)" % joined)
	# 3. trees and roads in the way
	var to2 := Vector2i(-1, -1)
	for k in range(4, 40):
		for d in [Vector2i(0, k), Vector2i(0, -k), Vector2i(k, 0), Vector2i(-k, 0), Vector2i(-k, k), Vector2i(k, -k), Vector2i(k, k), Vector2i(-k, -k)]:
			var at: Vector2i = r.position + d
			if to2.x < 0 and Blueprints.check(sim, 1, bp, at).count("") == bp.items.size():
				to2 = at
	if to2.x >= 0:
		var it0: Array = bp.items[0]
		var t_tree := sim.idx(to2.x + int(it0[1]), to2.y + int(it0[2]))
		sim.deco[t_tree] = Sim.D_TREE
		var it1: Array = bp.items[1]
		var t_road := sim.idx(to2.x + int(it1[1]), to2.y + int(it1[2]))
		sim.road[t_road] = 1
		sim.net_dirty(1)
		var obs := Blueprints.obstacles(sim, 1, bp, to2)
		check((obs.trees as PackedInt32Array).has(t_tree) and (obs.roads as PackedInt32Array).has(t_road), "a tree and a road in the way are found (%d trees, %d roads)" % [(obs.trees as PackedInt32Array).size(), (obs.roads as PackedInt32Array).size()])
		var why := Blueprints.check(sim, 1, bp, to2)
		check(String(why[0]).begins_with("Trees") and String(why[1]).begins_with("A road"), "and they stop those buildings (%s / %s)" % [why[0], why[1]])
		check(Blueprints.fits_cleared(sim, 1, String(it0[0]), to2.x + int(it0[1]), to2.y + int(it0[2]), int(it0[3]), Blueprints.obstacles_one(sim, 1, String(it0[0]), to2.x + int(it0[1]), to2.y + int(it0[2]))) and sim.deco[t_tree] == Sim.D_TREE,
			"one building would fit once the tree is felled (and the check leaves the tree)")
		Blueprints.clear(sim, 1, obs)
		check(sim.deco[t_tree] == 0 and sim.road[t_road] == 0, "cleared: the tree felled and the road taken up")
		var res2 := Blueprints.place(sim, me, bp, to2)
		check(int(res2[0]) == bp.items.size(), "then it all goes down (%s)" % str(res2[1]))
	else:
		var whys := {}
		for k in range(4, 40):
			for d in [Vector2i(0, k), Vector2i(0, -k), Vector2i(k, 0), Vector2i(-k, 0)]:
				for w in Blueprints.check(sim, 1, bp, r.position + d):
					whys[w] = int(whys.get(w, 0)) + 1
		check(false, "a second free place (%dx%d at %s; %s)" % [bp.w, bp.h, r.position, str(whys).left(400)])
	# 4. codes and the file
	var code := Blueprints.to_code(bp)
	var back := Blueprints.from_code(code)
	check(code.begins_with("HLBP1:") and back.items == bp.items and back.roads == bp.roads and back.name == "Wood corner", "a blueprint as a code and back")
	check(Blueprints.from_code("nonsense").is_empty() and Blueprints.from_code("HLBP1:bm9wZQ==").is_empty(), "a bad code is refused")
	var path := "user://bp_test.json"
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var store := Blueprints.new(path)
	store.add(bp)
	store.add_cat("Harbours")
	var b2 := bp.duplicate(true); b2.name = "Second"; b2.cat = "Harbours"
	store.add(b2)
	var again := Blueprints.new(path)
	check(again.list.size() == 2 and again.cats.has("Harbours") and again.in_cat("Industry").size() == 1 and again.in_cat("Harbours") == [1], "kept in the file with their categories")
	again.remove_cat("Harbours")
	check(not again.cats.has("Harbours") and again.list[1].cat == "Other", "a category removed: its blueprints go to Other")
	again.rename(0, "  Woods  ")
	check(Blueprints.new(path).list[0].name == "Woods", "renamed")
	DirAccess.remove_absolute(path)
	print("BLUEPRINT TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
