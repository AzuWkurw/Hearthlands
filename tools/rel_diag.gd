extends SceneTree
## Diagnosis of how rivals see each other after 22 minutes on the valley map: crowding, reserve,
## strength, and the nearest distance between their military buildings (why they go to war or not).
## godot --headless --script res://tools/rel_diag.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("valley", 7, 6, true)
	while sim.time < 22 * 60.0: sim.tick(Sim.TICK)
	for who in [1, 2]:
		var p := sim.players[who]
		print(p.name, " crowded ", p.crowded, " since ", int(p.crowded_t), " reserve ", p.reserve, " pers ", p.pers, " strength ", int(Diplomacy.strength(sim, p)))
		for q in sim.players:
			if q.id == p.id: continue
			var md := 1e9
			for a in sim.mil_list():
				if a.p != p.id: continue
				for b in sim.mil_list():
					if b.p == q.id: md = minf(md, Vector2(a.x - b.x, a.y - b.y).length())
			print("   %s: %s, opinion %d, borders %s, nearest military %d tiles, strength %d" % [q.name, Diplomacy.NAMES[Diplomacy.relation(sim, p.id, q.id)], int(Diplomacy.opinion(p, q.id)), Diplomacy.borders(sim, p.id, q.id), int(md), int(Diplomacy.strength(sim, q))])
	quit()
