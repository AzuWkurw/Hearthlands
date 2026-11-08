extends SceneTree
## Rival realms' buildings all get roads (entrances and all): godot --headless --script res://tools/ai_roads_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("showcase", 4, 6, true)
	while sim.time < 25 * 60.0: sim.tick(Sim.TICK)
	var tot := 0; var unc := 0; var wrong := 0; var nodoor := 0
	for b in sim.blds:
		if b.p == 1 or b.ty == "hq" or b.dead: continue
		tot += 1
		if b.door < 0: nodoor += 1
		if not sim.connected(b): unc += 1
		elif b.door >= 0:
			var sp: PackedInt32Array = sim.logistics.store_path(b)
			if sp.size() > 1 and sp[1] != sim.door_tile(b): wrong += 1
	print("rival buildings %d: without entrance %d, not connected %d, path not through entrance %d" % [tot, nodoor, unc, wrong])
	quit()
