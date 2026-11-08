extends SceneTree
## Do carriers bring materials to a new construction site? godot --headless --script res://tools/site_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("showcase", 2, 4, true)
	var me := sim.human()
	for i in 600: sim.tick(Sim.TICK)
	var placed: Sim.Bld = null
	for r in range(2, 9):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if placed == null and sim.place("woodcutter", me.hq.x + dx, me.hq.y + dy, me) == "":
					placed = sim.bld_at(me.hq.x + dx, me.hq.y + dy)
	print("placed ", placed.ty, " at ", placed.x, ",", placed.y, " need ", placed.need, " connected ", sim.connected(placed))
	var t0 := sim.time
	var seen := 0
	while sim.time - t0 < 120.0:
		sim.tick(Sim.TICK)
		for t in sim.trips:
			if t.site == placed.id: seen += 1
		if int(sim.time * 10) % 100 == 0:
			print("t+%d state %s need %s coming %s onsite %s prog %.2f free porters %d" % [sim.time - t0, placed.state, placed.need, placed.coming, placed.onsite, placed.prog if "prog" in placed else -1.0, sim.porters_free(me)])
	print("site trip-ticks seen ", seen)
	quit()
