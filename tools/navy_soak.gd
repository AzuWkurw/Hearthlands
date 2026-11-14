extends SceneTree
## Rivals and the sea over a long game: harbours, warships, coastal forts, field depots, generals.
## godot --headless --script res://tools/navy_soak.gd -- seed=islands mins=70 foes=4
func _init() -> void:
	GameData.ensure()
	var seed := "islands"
	var mins := 70
	var foes := 4
	var opts := {"all_research": true}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="): seed = a.substr(5)
		if a.begins_with("mins="): mins = int(a.substr(5))
		if a.begins_with("foes="): foes = int(a.substr(5))
	var sim := Sim.new()
	sim.new_game(seed, foes, 5, false, 192, false, opts)
	var t0 := Time.get_ticks_msec()
	var last := 0
	while sim.time < mins * 60.0:
		sim.tick(Sim.TICK)
		if int(sim.time / 600.0) != last:
			last = int(sim.time / 600.0)
			var line := "%d min:" % (last * 10)
			for p in sim.players:
				if p.id == 1 or not p.alive: continue
				var c := {}
				for b in sim.realm_blds(p):
					if b.ty in ["harbour", "shipyard", "naval_yard", "coastal_fort", "field_depot"]:
						c[b.ty] = int(c.get(b.ty, 0)) + 1
				line += "\n   %s %s%s cr %s ships %d war %d gen %.0f/%d back %.0f atk %d %s" % [p.name.substr(0, 6), p.pers, "(isl)" if p.island else "", p.crowded, p.ships, p.warships, p.general_xp, p.general_uid, p.general_back, p.attacks_made, c] + " techs %s planks %d stone %d war-any %s" % [p.techs.has("pack_mules"), int(p.stock.get("planks", 0)), int(p.stock.get("stone", 0)), sim.ai._at_war_any(p)]
			print(line)
	print("navy at the end: %d warships; %.0f s real" % [sim.navy.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	quit()
