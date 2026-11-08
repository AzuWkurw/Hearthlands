extends SceneTree
## Why new buildings find no road route: godot --headless --script res://tools/route_diag.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("perf", 7, 6, true)
	while sim.time < 25 * 60.0: sim.tick(Sim.TICK)
	var p := sim.players[7]
	var ok := 0; var fail := 0
	var why := {}
	for i in sim.owned(p.id)[0]:
		var x: int = i % sim.w; var y: int = i / sim.w
		if sim.can_place("house", x, y, p.id) != "": continue
		var path: PackedInt32Array = sim._path_to_net(x, y, p.id, -1, [0, 1, 3])
		if path.size() > 0:
			ok += 1
			continue
		fail += 1
		# what is round the spot within 4 tiles: own road on the network? any own road?
		var net_road := 999; var any_road := 999
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				if not sim.inb(x + dx, y + dy): continue
				var j := sim.idx(x + dx, y + dy)
				if sim.road[j] == p.id:
					any_road = mini(any_road, absi(dx) + absi(dy))
					if sim.net_dist(p.id, j) < Sim.INF: net_road = mini(net_road, absi(dx) + absi(dy))
		var k := "road on the network %s, any road %s" % ["within %d" % net_road if net_road < 999 else "none near", "within %d" % any_road if any_road < 999 else "none near"]
		var doors := []
		for d in [0, 1, 3]:
			var dt := sim.door_at(x, y, d)
			if dt < 0: doors.append("off"); continue
			if sim.plot[dt] != 0 or sim.bmap[dt] != 0: doors.append("plot")
			elif sim.owner[dt] != p.id: doors.append("foreign")
			elif sim.ter[dt] == Sim.WATER or sim.deco[dt] == Sim.D_ROCK: doors.append("blocked")
			else: doors.append("free")
		k += ", doors " + "/".join(doors)
		why[k] = int(why.get(k, 0)) + 1
	print("house spots: %d with a road route, %d without" % [ok, fail])
	var keys := why.keys(); keys.sort_custom(func(a, b): return int(why[a]) > int(why[b]))
	for k in keys.slice(0, 10): print("%4d  %s" % [why[k], k])
	quit()
