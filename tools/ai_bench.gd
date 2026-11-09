extends SceneTree
## Rival AI benchmark: godot --headless --script res://tools/ai_bench.gd [-- seed=valley mins=30]
## Seven rivals (and an idle human). Prints each rival at the end, how much it grew in the last 10
## minutes, why its workshops wait, and one summary line to compare versions by.
func _init() -> void:
	GameData.ensure()
	var seed := "valley"; var mins := 30
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="): seed = a.substr(5)
		if a.begins_with("mins="): mins = int(a.substr(5))
	var feats := Features.default_ids()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("nofeat="): feats.erase(a.substr(7))
	var sim := Sim.new()
	sim.new_game(seed, 7, 6, true, 0, true, {"features": feats})
	var at20 := {}
	var hungry := {}
	var seen := {}
	var attacks := {}
	var owner_of := {}
	var captures := {}
	var t_real := Time.get_ticks_usec()
	while sim.time < mins * 60.0:
		sim.tick(Sim.TICK)
		if sim._ticks % 10 == 0:
			for p in sim.players:
				if p.starve > 0: hungry[p.id] = int(hungry.get(p.id, 0)) + 1
			for a in sim.attacks:
				if not seen.has(a.uid):
					seen[a.uid] = true
					attacks[a.p] = int(attacks.get(a.p, 0)) + 1
			for b in sim.blds:
				if b.def.has("garrison"):
					if owner_of.has(b.id) and int(owner_of[b.id]) != b.p:
						captures[b.p] = int(captures.get(b.p, 0)) + 1
					owner_of[b.id] = b.p
		if absf(sim.time - (mins - 10) * 60.0) < 0.05:
			for p in sim.players: at20[p.id] = sim.realm_blds(p).size()
	var secs := (Time.get_ticks_usec() - t_real) / 1e6
	var tot_b := 0; var tot_pop := 0; var tot_land := 0; var tot_tech := 0; var worst := 9999; var stalled := 0
	var tot_sold := 0; var hungry_n := 0; var alive := 0
	var msgs := {}
	for p in sim.players:
		if p.id == 1: continue
		var nb := sim.realm_blds(p).size()
		var land: int = (sim.owned(p.id)[0] as PackedInt32Array).size() + (sim.owned(p.id)[1] as PackedInt32Array).size()
		var grew := nb - int(at20.get(p.id, 0))
		if p.alive:
			alive += 1
			tot_b += nb; tot_pop += sim.pop_total(p); tot_land += land; tot_tech += p.techs.size(); tot_sold += sim.soldiers(p)
			worst = mini(worst, nb)
			if grew < 5: stalled += 1
		if int(hungry.get(p.id, 0)) > 6: hungry_n += 1
		print("%-9s %s %3d blds (+%2d in the last 10 min), pop %3d, land %4d, techs %2d age %d, soldiers %3d, attacks %2d, captured %2d, hungry %3d s%s" % [p.name, "     " if p.alive else "DEAD ", nb, grew, sim.pop_total(p), land, p.techs.size(), p.age, sim.soldiers(p), attacks.get(p.id, 0), captures.get(p.id, 0), int(hungry.get(p.id, 0)), "  CROWDED" if p.crowded else ""])
		for b in sim.blds:
			if b.p == p.id and b.state == "ready" and b.def.has("cycle"):
				var m := b.msg.get_slice(":", 0).get_slice(" (", 0)
				msgs[m] = int(msgs.get(m, 0)) + 1
	var keys := msgs.keys(); keys.sort_custom(func(a, c): return int(msgs[a]) > int(msgs[c]))
	print("workshops: ", ", ".join(keys.slice(0, 14).map(func(k): return "%s %d" % [k, msgs[k]])))
	print("SUMMARY %s %d min: buildings %d, people %d, land %d, techs %d, soldiers %d, smallest rival %d, stalled %d, hungry %d, alive %d, %.0f s" % [seed, mins, tot_b, tot_pop, tot_land, tot_tech, tot_sold, worst, stalled, hungry_n, alive, secs])
	quit()
