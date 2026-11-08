extends SceneTree
## Entrances: roads join buildings only at the door. godot --headless --script res://tools/door_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("showcase", 2, 4, true)
	var me := sim.human()
	for i in 100: sim.tick(Sim.TICK)
	var ok := 0; var bad := 0
	for d in 4:
		var spot := Vector2i(-1, -1)
		for r in range(3, 12):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if spot.x < 0 and sim.can_place("woodcutter", me.hq.x + dx, me.hq.y + dy, 1, d) == "":
						spot = Vector2i(me.hq.x + dx, me.hq.y + dy)
		var r1 := sim.place("woodcutter", spot.x, spot.y, me, d, false)
		var b := sim.bld_at(spot.x, spot.y)
		var conn0 := sim.connected(b)
		# a road from the building to the headquarters' doorstep area
		var hqd := Vector2i(me.hq.x, me.hq.y + 1)
		var r2 := sim.build_road(spot.x, spot.y, me.hq.x, me.hq.y, 1)
		var path := sim.find_path(spot.x, spot.y, me.hq.x, me.hq.y, 1)
		var dt := sim.door_tile(b)
		var first := -1
		# which neighbour of the building carries road
		var sides := []
		for k in 4:
			var t := sim.door_at(b.x, b.y, k)
			if t >= 0 and sim.road[t] == 1: sides.append(Sim.DOOR_NAMES[k])
		for i in 30: sim.tick(Sim.TICK)
		var c := sim.connected(b)
		var sp: PackedInt32Array = sim.logistics.store_path(b)
		var via: int = sp[1] if sp.size() > 1 else -1
		print("door %s: place '%s' connected before %s, road '%s', road on sides %s, connected %s, store path leaves via door: %s" % [Sim.DOOR_NAMES[d], r1, conn0, r2, sides, c, via == dt])
		if c and via == dt: ok += 1
		else: bad += 1
	# a road touching a building on a side that is not its entrance must not connect it
	var spot2 := Vector2i(-1, -1)
	for r in range(4, 14):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x: int = me.hq.x + dx; var y: int = me.hq.y + dy
				if spot2.x < 0 and sim.can_place("woodcutter", x, y, 1, 2) == "" and sim.inb(x, y + 1) and sim.road[sim.idx(x, y + 1)] == 1:
					spot2 = Vector2i(x, y)
	if spot2.x >= 0:
		sim.place("woodcutter", spot2.x, spot2.y, me, 2, false)
		var b2 := sim.bld_at(spot2.x, spot2.y)
		for i in 30: sim.tick(Sim.TICK)
		print("road below, entrance north: connected %s (should be false)" % sim.connected(b2))
		if sim.connected(b2): bad += 1
		else: ok += 1
	print("door test: %d ok, %d bad" % [ok, bad])
	quit()
