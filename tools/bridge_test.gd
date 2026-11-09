extends SceneTree
## Bridges: roads across narrow water, paid in planks; too wide water is refused:
## godot --headless --script res://tools/bridge_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("showcase", 1, 4, true)
	var me := sim.human()
	for i in 20: sim.tick(Sim.TICK)
	var ok := true
	var hx := me.hq.x
	var hy := me.hq.y
	# a channel of water 2 tiles wide across our land, 4 tiles east of the headquarters, and one 5 wide
	# further south
	for y in range(hy - 6, hy + 7):
		for x in [hx + 4, hx + 5]:
			if sim.bmap[sim.idx(x, y)] == 0 and sim.road[sim.idx(x, y)] == 0:
				sim.ter[sim.idx(x, y)] = Sim.WATER; sim.deco[sim.idx(x, y)] = 0
	for x in range(hx - 6, hx + 3):
		for y in range(hy + 3, hy + 8):
			if sim.bmap[sim.idx(x, y)] == 0 and sim.road[sim.idx(x, y)] == 0:
				sim.ter[sim.idx(x, y)] = Sim.WATER; sim.deco[sim.idx(x, y)] = 0
	for x in range(hx + 6, hx + 9):
		for y in range(hy - 3, hy + 3):
			sim.deco[sim.idx(x, y)] = 0
	sim.logistics.net_dirty(1)
	var planks0 := float(me.stock.get("planks", 0.0))
	# from the headquarters' road out east over the channel
	# a road from the headquarters' door to the channel's near shore first
	var start := Vector2i(hx + 3, hy + 2)
	print("road to the shore: '", sim.build_road(hx, hy, start.x, start.y, 1), "'")
	planks0 = float(me.stock.get("planks", 0.0))
	var goal := Vector2i(hx + 7, start.y)
	var why := sim.build_road(start.x, start.y, goal.x, goal.y, 1)
	var on_water := 0
	for x in range(hx + 3, hx + 7):
		if sim.ter[sim.idx(x, start.y)] == Sim.WATER and sim.road[sim.idx(x, start.y)] == 1: on_water += 1
	print("road from ", start, " to ", goal, ": '", why, "', bridge tiles ", on_water, ", planks ", planks0, " -> ", float(me.stock.get("planks", 0.0)))
	if why != "" or on_water != 2 or float(me.stock.get("planks", 0.0)) != planks0 - 4.0:
		ok = false; print("FAIL: a 2-tile bridge for 4 planks")
	print("far shore joined to the roads: ", sim.logistics.net_dist(1, sim.idx(goal.x, goal.y)) < INF)
	if not sim.logistics.net_dist(1, sim.idx(goal.x, goal.y)) < INF: ok = false; print("FAIL: carriers should reach across")
	# the far shore counts as reachable for building
	var r := sim.logistics.reach(1)
	print("reach beyond the bridge: ", r[sim.idx(goal.x + 1, goal.y)] == 1)
	# five tiles of water: no bridge
	var land := sim.logistics.bridge_landing(sim.idx(hx - 3, hy + 2), sim.idx(hx - 3, hy + 3), 1)
	var land1 := sim.logistics.bridge_landing(sim.idx(hx + 3, hy), sim.idx(hx + 4, hy), 1)
	print("bridge over 5 tiles lands at ", land, "; over 2 tiles at ", land1)
	if land != -1 or land1 != sim.idx(hx + 6, hy): ok = false; print("FAIL: bridges span at most 3 tiles")
	# paving makes it a stone bridge
	print("pave the bridge: '", sim.pave_road(hx + 4, start.y, me), "'")
	print("bridge test: ", "ok" if ok else "FAILED")
	quit()
