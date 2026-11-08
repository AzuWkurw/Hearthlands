extends SceneTree
## Headless check: godot --headless --script res://tools/sim_test.gd
## Plays a game where every realm, including yours, is run by the AI, and prints progress.

func _init() -> void:
	var foes := 6
	var strength := 8
	var minutes := [20, 45, 70]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("foes="): foes = int(a.substr(5))
		if a.begins_with("str="): strength = int(a.substr(4))
	var sim := Sim.new()
	var t0 := Time.get_ticks_msec()
	var ok := sim.new_game("test-%d" % foes, foes, strength, true)
	print("generated ok=%s size=%dx%d in %d ms, data errors=%s" % [ok, sim.w, sim.h, Time.get_ticks_msec() - t0, GameData.errors])
	var counts := [0, 0, 0, 0]
	for t in sim.ter: counts[t] += 1
	print("terrain water/beach/grass/mountain %%: ", counts.map(func(c): return roundi(100.0 * c / sim.ter.size())))
	var me: Sim.Player = sim.players[0]
	me.ai = true; me.skill = 6; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.odds = 99.0; me.grace = 1e9; me.attack_t = 1e9
	for m in minutes:
		t0 = Time.get_ticks_msec()
		while sim.time < m * 60.0:
			sim.tick(Sim.TICK)
		print("--- minute %d (%d ms) over=%s" % [m, Time.get_ticks_msec() - t0, sim.over])
		for p in sim.players:
			var n := 0
			var mil := 0
			var types := {}
			for b in sim.blds:
				if b.p == p.id:
					n += 1
					types[b.ty] = true
					if b.def.has("garrison"): mil += 1
			var s := p.stock
			print("%-9s age=%-14s techs=%2d ".replace("%-14s", GameData.age_name(p.age).rpad(14)) % [p.name, p.techs.size()] + "%s pop=%d/%d/%d sol=%d vets=%d bld=%d types=%d mil=%d food=%d bricks=%d coal=%d iron=%d wpn=%d armor=%d beer=%d clothes=%d gold=%d sat=%.1f/%.1f starve=%d" % ["alive" if p.alive else "DEAD ", p.peasant, p.artisan, p.noble, sim.soldiers(p), int(p.vets), n, types.size(), mil, int(sim.food_total(p)), int(s.bricks), int(s.coal), int(s.iron), int(s.weapons), int(s.armor), int(s.beer), int(s.clothes), int(s.gold), p.sat.artisan, p.sat.noble, p.starve])
		var war := []
		for l in sim.logs:
			if "captured" in l[1] or "defeated" in l[1]:
				war.append(l[0] + " " + l[1])
		print("war events: ", war.slice(-5))
		var rels := []
		for k in sim.rel:
			var ab: PackedStringArray = String(k).split(":")
			rels.append("%s-%s %s" % [sim.players[int(ab[0]) - 1].name, sim.players[int(ab[1]) - 1].name, Diplomacy.NAMES[int(sim.rel[k])]])
		print("treaties: ", rels)
		for p in sim.players:
			if not p.alive: continue
			var waiting := 0
			var unconnected := 0
			var stores := 0
			var stations := 0
			for b in sim.blds:
				if b.p != p.id: continue
				if b.msg == "Waiting for carriers": waiting += 1
				if b.msg.begins_with("Not connected") or b.msg.begins_with("Waiting for a road"): unconnected += 1
				if sim.is_store(b): stores += 1
				if b.def.has("carriers"): stations += 1
			print("  %-9s porters free %d busy %d, waiting for carriers %d, unconnected %d, stores %d, stations %d, room %d" % [p.name, sim.porters_free(p), p.busy_porters, waiting, unconnected, stores, stations, int(sim.capacity(p, "planks"))])
	quit()
