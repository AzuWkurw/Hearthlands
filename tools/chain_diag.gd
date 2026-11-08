extends SceneTree
## Where the iron chain chokes for rivals: godot --headless --script res://tools/chain_diag.gd [-- seed=valley mins=25]
func _init() -> void:
	GameData.ensure()
	var seed := "valley"; var mins := 25
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="): seed = a.substr(5)
		if a.begins_with("mins="): mins = int(a.substr(5))
	var sim := Sim.new()
	sim.new_game(seed, 7, 6, true)
	while sim.time < mins * 60.0: sim.tick(Sim.TICK)
	var st := {}
	for b in sim.blds:
		if b.p == 1 or b.state != "ready": continue
		if b.ty in ["iron_mine", "coal_mine", "iron_smelter", "weaponsmith", "toolsmith", "armorer", "geologist"]:
			var k := "%s: %s" % [b.ty, b.msg.get_slice(" (", 0)]
			st[k] = int(st.get(k, 0)) + 1
	var keys := st.keys(); keys.sort()
	for k in keys: print("%3d  %s" % [st[k], k])
	var known := 0; var iron_spots := 0
	for p in sim.players:
		if p.id == 1: continue
		var n := 0; var ki := 0
		for i in sim.owned(p.id)[1]:
			if sim.ore[i] == 2:
				n += 1
				if sim.ore_known(p.id, i) and sim.vein_left(i) > 0: ki += 1
		print("%s: iron tiles in its mountains %d (found and not used up %d), ore stock %d, coal %d, iron %d, weapons %d, tools waiting %s" % [p.name, n, ki, int(p.stock.get("ore_iron", 0)), int(p.stock.get("coal", 0)), int(p.stock.get("iron", 0)), int(p.stock.get("weapons", 0)), p.tool_wait])
	quit()
