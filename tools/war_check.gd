extends SceneTree
## Do rivals whose land is full fight for more? godot --headless --script res://tools/war_check.gd [-- seed=valley mins=40]
func _init() -> void:
	GameData.ensure()
	var seed := "valley"; var mins := 40
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="): seed = a.substr(5)
		if a.begins_with("mins="): mins = int(a.substr(5))
	var sim := Sim.new()
	sim.new_game(seed, 7, 6, true)
	var seen := {}
	var attacks := {}
	var owner_of := {}
	var captures := {}
	var next := 10
	var crowded_since := {}
	while sim.time < mins * 60.0:
		sim.tick(Sim.TICK)
		for a in sim.attacks:
			if not seen.has(a.uid):
				seen[a.uid] = true
				attacks[a.p] = int(attacks.get(a.p, 0)) + 1
		if sim._ticks % 10 == 0:
			for b in sim.blds:
				if b.def.has("garrison"):
					if owner_of.has(b.id) and int(owner_of[b.id]) != b.p:
						captures[b.p] = int(captures.get(b.p, 0)) + 1
					owner_of[b.id] = b.p
			for p in sim.players:
				if p.crowded and not crowded_since.has(p.id): crowded_since[p.id] = int(sim.time / 60)
		if sim.time >= next * 60.0:
			print("=== minute %d" % next)
			for p in sim.players:
				if p.id == 1: continue
				var wars := []
				for q in sim.players:
					if q.id != p.id and q.alive and Diplomacy.at_war(sim, p.id, q.id) and Diplomacy.borders(sim, p.id, q.id): wars.append(q.name.left(4))
				print("%-9s %s %3d blds, land %4d, soldiers %3d (reserve %2d) | %s | attacks %d, captured %d | at war with neighbours: %s" % [p.name, "ALIVE" if p.alive else "DEAD ", sim.realm_blds(p).size(), sim.owned(p.id)[0].size() + sim.owned(p.id)[1].size(), sim.soldiers(p), p.reserve, ("crowded since min %d" % crowded_since[p.id]) if crowded_since.has(p.id) else "room to grow", attacks.get(p.id, 0), captures.get(p.id, 0), wars])
			next += 10
	quit()
