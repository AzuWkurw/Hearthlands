extends SceneTree
## Luxuries: spices, silk, porcelain and coffee. Nobles who have had one lately pay more tax, each kind
## counting once; the chains make them: godot --headless --script res://tools/luxury_test.gd
func _init() -> void:
	GameData.ensure()
	var ok := true
	var sim := Sim.new()
	sim.new_game("luxury", 1, 4, true)
	for i in 5: sim.tick(Sim.TICK)
	var me := sim.human()
	me.noble = 20
	print("luxury goods known: ", GameData.luxury)
	for k in ["spices", "silk", "porcelain", "coffee"]:
		if not GameData.res_by_id.has(k): ok = false; print("FAIL: no resource ", k)
	var t0 := sim.time
	while sim.time < t0 + 60.0: sim.tick(Sim.TICK)
	print("without luxuries: lux %d" % me.lux)
	if me.lux != 0: ok = false; print("FAIL: no luxuries yet")
	for k in ["spices", "silk", "porcelain", "coffee"]:
		sim.give(me, k, 20.0)
	t0 = sim.time
	while sim.time < t0 + 120.0: sim.tick(Sim.TICK)
	print("with all four in store: lux %d, used spices %d" % [me.lux, 20 - int(me.stock.spices)])
	if me.lux != 4: ok = false; print("FAIL: four luxuries")
	# each chain's buildings exist and take what the one before makes
	for pair in [["mulberry_grove", "silk_weaver"], ["pepper_garden", "spice_mill"], ["kaolin_pit", "porcelain_kiln"], ["coffee_plantation", "coffee_roaster"]]:
		var a: Dictionary = GameData.bld[pair[0]]
		var b: Dictionary = GameData.bld[pair[1]]
		var out := String(a.out.keys()[0])
		if not b.get("in", {}).has(out): ok = false; print("FAIL: ", pair)
	print("luxury test: ", "ok" if ok else "FAILED")
	sim.dispose()
	quit()
