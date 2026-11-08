extends SceneTree
## What buildings wait for: godot --headless --script res://tools/econ_diag.gd [-- seed=valley mins=12]
func _init() -> void:
	GameData.ensure()
	var seed := "valley"; var mins := 12
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="): seed = a.substr(5)
		if a.begins_with("mins="): mins = int(a.substr(5))
	var sim := Sim.new()
	sim.new_game(seed, 7, 7, true)
	sim.players[0].ai = true
	while sim.time < mins * 60.0: sim.tick(Sim.TICK)
	var msgs := {}
	for b in sim.blds:
		if b.state == "ready" and b.def.has("cycle"):
			var m := b.msg.get_slice(":", 0)
			if not b.staffed: m = "(no worker)"
			msgs[m] = int(msgs.get(m, 0)) + 1
	var keys := msgs.keys(); keys.sort_custom(func(a, c): return int(msgs[a]) > int(msgs[c]))
	for k in keys.slice(0, 18): print("%4d  %s" % [msgs[k], k])
	for p in sim.players:
		var kinds := {}
		for t in sim.trips:
			if t.p == p.id: kinds[t.kind + ("/in" if t.dest != 0 else ("/site" if t.site != 0 else "/out"))] = int(kinds.get(t.kind + ("/in" if t.dest != 0 else ("/site" if t.site != 0 else "/out")), 0)) + 1
		print("%s: pop %d food %d starve %d porters free %d (stores give %d, idle peasants %d), trips %s" % [p.name, sim.pop_total(p), int(sim.food_total(p)), p.starve, sim.logistics.porters_free(p), p.store_porters, p.peasant - p.used_peasant, kinds])
	quit()
