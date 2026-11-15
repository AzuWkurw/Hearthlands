extends SceneTree
## A catapult wears down an enemy fort: godot --headless --script res://tools/catapult_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("showcase", 2, 4, true)
	var me := sim.human()
	me.techs["stone_masonry"] = true
	for i in 50: sim.tick(Sim.TICK)
	var foe := sim.players[1]
	if not Diplomacy.at_war(sim, 1, foe.id): Diplomacy.declare_war(sim, 1, foe.id)
	# an enemy tower set down in our land, 8 tiles from the headquarters (no territory change: a test)
	var tw: Sim.Bld = null
	for r in range(7, 10):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x: int = me.hq.x + dx; var y: int = me.hq.y + dy
				if tw == null and sim.inb(x, y) and sim.bmap[sim.idx(x, y)] == 0 and sim.plot[sim.idx(x, y)] == 0 and sim.road[sim.idx(x, y)] == 0 and sim.ter[sim.idx(x, y)] == Sim.GRASS:
					tw = sim.add_bld("tower", x, y, foe, true, 0)
	tw.garrison = 4
	tw.gmix = [0, 4, 0, 0, 0, 0, 0]
	# our catapult near the headquarters, with its road
	var cp := ""
	var spot := Vector2i(-1, -1)
	for r in range(2, 9):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x: int = me.hq.x + dx; var y: int = me.hq.y + dy
				if spot.x < 0 and sim.can_place("catapult", x, y, 1) == "" and Vector2(tw.x - x, tw.y - y).length() <= 10.0:
					spot = Vector2i(x, y)
	cp = sim.place("catapult", spot.x, spot.y, me, -1, true)
	var cat := sim.bld_at(spot.x, spot.y)
	print("catapult placed: '%s' at %s, tower at (%d, %d) with %d" % [cp, spot, tw.x, tw.y, tw.garrison])
	var hits := 0
	var t0 := sim.time
	while sim.time < t0 + 6 * 60.0:
		sim.tick(Sim.TICK)
		for l in sim.logs:
			pass
	for l in sim.logs:
		if "Your catapult hit" in String(l[1]): hits += 1
	print("after 6 min: catapult %s (%s), tower garrison %d, hits that killed %d" % [cat.state, cat.msg, tw.garrison, hits])
	print("catapult test: %s" % ("ok" if hits > 0 and tw.garrison < 4 else "FAILED"))
	quit()
