extends SceneTree
## Boundary stones claim free land without soldiers, and lose it to soldiers:
## godot --headless --script res://tools/claim_test.gd
func _land(sim: Sim, pid: int) -> int:
	var n := 0
	for o in sim.owner:
		if o == pid: n += 1
	return n

func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("showcase", 2, 4, true)
	var me := sim.human()
	for i in 50: sim.tick(Sim.TICK)
	var ok := true
	# the spot near the border that claims the most free land
	var best := Vector2i(-1, -1)
	var bg := 0
	for y in range(me.hq.y - 10, me.hq.y + 11):
		for x in range(me.hq.x - 10, me.hq.x + 11):
			if sim.inb(x, y) and sim.can_place("boundary_stone", x, y, 1) == "":
				var g := 0
				for dy in range(-4, 5):
					for dx in range(-4, 5):
						if dx * dx + dy * dy <= 16 and sim.inb(x + dx, y + dy) and sim.owner[sim.idx(x + dx, y + dy)] == 0: g += 1
				if g > bg: bg = g; best = Vector2i(x, y)
	var land0 := _land(sim, 1)
	var why := sim.place("boundary_stone", best.x, best.y, me)
	print("placed at ", best, " (", why, "), free land it can take: ", bg)
	var st: Sim.Bld = null
	for b in sim.blds:
		if b.ty == "boundary_stone": st = b
	var t0 := sim.time
	while st.state != "ready" and sim.time - t0 < 300.0: sim.tick(Sim.TICK)
	var land1 := _land(sim, 1)
	print("built after %.0f s; land %d -> %d (soldiers in reserve %d)" % [sim.time - t0, land0, land1, me.reserve])
	if st.state != "ready" or land1 - land0 < bg - 2:
		ok = false; print("FAIL: the stone did not claim its land")
	# a second stone can't stand on land only the first one claims
	var refused := 0
	var allowed := 0
	for y in range(st.y - 4, st.y + 5):
		for x in range(st.x - 4, st.x + 5):
			if sim.inb(x, y) and sim.owner[sim.idx(x, y)] == 1 and not sim._soldiers_hold(x, y, 1):
				var w := sim.can_place("boundary_stone", x, y, 1)
				if w == "": allowed += 1
				elif w.begins_with("A boundary stone must"): refused += 1
	print("stone spots on the stone's own land: %d refused, %d allowed" % [refused, allowed])
	if allowed > 0 or refused == 0:
		ok = false; print("FAIL: stones must not chain")
	# the headquarters' soldiers leave (as if the land were lost): the stone now holds its own tile,
	# and a rival's manned guard hut whose land reaches it takes that land and the stone falls
	var foe := sim.players[1]
	var hq_r := int(me.hq.def.radius)
	me.hq.def = me.hq.def.duplicate(); me.hq.def["radius"] = 2
	sim.recompute_territory()
	print("headquarters claims only 2 tiles now: stone alive ", not st.dead, ", land ", _land(sim, 1))
	if st.dead:
		ok = false; print("FAIL: the stone should hold its land with nobody else about")
	var spot := Vector2i(-1, -1)
	for y in range(st.y - 7, st.y + 8):
		for x in range(st.x - 7, st.x + 8):
			if spot.x < 0 and sim.inb(x, y) and sim.owner[sim.idx(x, y)] == 0 and sim.bmap[sim.idx(x, y)] == 0 and sim.ter[sim.idx(x, y)] == Sim.GRASS and Vector2(x - st.x, y - st.y).length() > 4.5 and Vector2(x - st.x, y - st.y).length() < 5.8:
				spot = Vector2i(x, y)
	var hut := sim.add_bld("hut", spot.x, spot.y, foe, true, 0)
	hut.garrison = 1; hut.gmix = [0, 1, 0, 0, 0, 0, 0]
	sim.recompute_territory()
	print("rival hut at ", spot, ": stone dead ", st.dead, ", hut alive ", not hut.dead, ", land ", _land(sim, 1))
	if not st.dead or hut.dead:
		ok = false; print("FAIL: soldiers' land should win over the stone")
	me.hq.def["radius"] = hq_r
	print("claim test: ", "ok" if ok else "FAILED")
	quit()
