extends SceneTree
## Full stores stop production: godot --headless --script res://tools/full_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("full", 1, 5, false, 0, true, {"features": []})
	var p := sim.human()
	var cap := sim.capacity(p, "water")
	var wc: Sim.Bld = null
	for b in sim.realm_blds(p):
		if b.ty == "well": wc = b
	if wc == null:
		for y in range(p.hq.y - 6, p.hq.y + 7):
			for x in range(p.hq.x - 6, p.hq.x + 7):
				if wc == null and sim.can_place("well", x, y, p.id) == "":
					var c := sim.add_bld("well", x, y, p, true)
					if sim.build_road(c.x, c.y, p.hq.x, p.hq.y, p.id) == "" or sim.connected(c):
						wc = c
					else:
						sim.destroy(c)
	print("connected: ", sim.connected(wc))
	p.stock["water"] = cap - 1.0
	var t0 := sim.time
	while sim.time < t0 + 120.0: sim.tick(Sim.TICK)
	print("water %d of %d (+%d coming), well: %s" % [int(p.stock.water), int(cap), int(sim.coming(p, "water")), wc.msg if wc != null else "none"])
	p.stock["water"] = 0.0
	while sim.time < t0 + 160.0: sim.tick(Sim.TICK)
	print("after using them: well: %s" % (wc.msg if wc != null else "none"))
	sim.dispose(); quit()
