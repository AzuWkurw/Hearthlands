extends SceneTree
## Tests carried building materials, the fog of war, scouts and watch towers.
## Run: godot --headless --script res://tools/fog_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("fogtest", 3, 5, false, 0, true, {})
	var me := sim.human()
	var fog = sim.get_feature("fog")
	var n := sim.w * sim.h
	var ex: int = fog.explored.count(1)
	print("fog on: %s, explored at start %d of %d tiles, visible %d" % [fog != null, ex, n, fog.vis.count(1)])
	# carried materials: placing takes nothing from the store
	var planks0 := int(me.stock.planks)
	var spot := Vector2i(-1, -1)
	for r in range(2, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if spot.x < 0 and sim.can_place("scout_lodge", me.hq.x + dx, me.hq.y + dy, 1) == "":
					spot = Vector2i(me.hq.x + dx, me.hq.y + dy)
	print("place scout lodge: '%s', planks before %d after %d" % [sim.place("scout_lodge", spot.x, spot.y, me), planks0, int(me.stock.planks)])
	var lodge := sim.bld_at(spot.x, spot.y)
	for i in 300: sim.tick(Sim.TICK)
	print("after 30 s: %s | %s | planks in store %d" % [sim.status(lodge), sim.materials_text(lodge), int(me.stock.planks)])
	while lodge.state == "build" and sim.time < 200.0: sim.tick(Sim.TICK)
	print("lodge finished at %.0f s, spent %s" % [sim.time, lodge.spent])
	me.stock.bows = 4.0; me.stock.bread = 30.0
	while me.scout < 2 and sim.time < 400.0: sim.tick(Sim.TICK)
	print("scouts trained: %d at %.0f s" % [me.scout, sim.time])
	# send a scout far away
	var far := Vector2i(sim.players[1].hq.x, sim.players[1].hq.y)
	print("send scout: '%s'" % fog.send_scout(me, far.x, far.y))
	var e0: int = fog.explored.count(1)
	for i in 400: sim.tick(Sim.TICK)
	print("after 40 s of scouting: explored %d -> %d, scouts out %d" % [e0, fog.explored.count(1), me.scout_out])
	# save and load keep the fog and the scout
	var d := sim.to_save()
	var sim2 := Sim.new()
	print("load '%s': explored %d, walks %d" % [sim2.from_save(d), sim2.get_feature("fog").explored.count(1), sim2.get_feature("fog").walks.size()])
	while me.scout_out > 0 and sim.time < 1200.0: sim.tick(Sim.TICK)
	print("scout home at %.0f s, idle scouts %d" % [sim.time, me.scout - me.used_scout - me.scout_out])
	sim.dispose(); sim2.dispose()
	quit()
