extends SceneTree
## Plays the same all-AI game twice for 30 minutes: once with the default features (seasons, clothes...),
## once with classic rules, and prints the climate and each realm's growth so the balance can be compared.
## Run: godot --headless --script res://tools/climate_test.gd -- [min=30] [seed=climate]

func _init() -> void:
	GameData.ensure()
	var mins := 30
	var seed := "climate"
	var only := ""
	var without := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("min="): mins = int(a.substr(4))
		if a.begins_with("seed="): seed = a.substr(5)
		if a.begins_with("only="): only = a.substr(5)
		if a.begins_with("without="): without = a.substr(8)
	var runs := [["features", Features.default_ids().filter(func(f): return f != without)], ["classic", []]]
	for run in runs:
		if only != "" and run[0] != only:
			continue
		var sim := Sim.new()
		sim.new_game(seed, 4, 5, false, 0, true, {"features": run[1]})
		for p in sim.players:
			p.ai = true
		print("== %s: %s" % [run[0], sim.feature_ids()])
		var t0 := Time.get_ticks_msec()
		var next := 150.0
		while sim.time < mins * 60.0:
			sim.tick(Sim.TICK)
			if sim.time >= next:
				next += 150.0
				var line := "%5.1f min" % (sim.time / 60.0)
				var cl = sim.get_feature("seasons")
				var wear = sim.get_feature("clothing")
				if cl != null:
					line += " %s %s" % [cl.SEASONS[cl.season()], ",".join(range(4).map(func(k): return "%s %d°%s" % [["tmp", "tai", "stp", "wet"][k], roundi(cl.biome_temp(k)), String(cl.weather[k]).left(4)]))]
				print(line)
				for p in sim.players:
					var s := "    %-8s pop %3d bld %3d food %4d" % [p.name, sim.pop_total(p), sim.realm_blds(p).size(), int(sim.food_total(p))]
					if cl != null:
						s += " %s %3d°" % [["tmp", "tai", "stp", "wet"][cl.biome_of(p)], roundi(cl.realm_temp(p))]
					if wear != null:
						s += " coats %3d%% linen %3d%% coldneed %.2f stock c%d l%d" % [roundi(wear.warm_share(p) * 100), roundi(wear.light_share(p) * 100), wear.cold_need(p), int(p.stock.fur_coats), int(p.stock.linen_clothes)]
					var dz = sim.get_feature("diseases")
					if dz != null:
						s += " sick %d died %d med %d" % [roundi(dz.total_sick(p)), int(dz.died.get(p.id, 0)), int(p.stock.get("medicine", 0))]
					var tq = sim.get_feature("tool_quality")
					if tq != null:
						s += " tools " + tq.panel_lines(p)[0].replace("Tools in use  ", "") if not tq.panel_lines(p).is_empty() else ""
					var wl = sim.get_feature("wildlife")
					if wl != null and p.id == 1:
						var c := {}
						for a in wl.animals: c[a[0]] = int(c.get(a[0], 0)) + 1
						s += " animals %s" % str(c)
					var hn := sim.realm_blds(p).filter(func(b): return b.ty == "hunter")
					s += " hunters %d (%d no game)" % [hn.size(), hn.filter(func(b): return b.msg == "No game in the hunting grounds").size()]
					print(s)
		var tot := 0
		for p in sim.players:
			tot += sim.pop_total(p)
		print("%s: total pop %d after %d min, %.1f s real" % [run[0], tot, mins, (Time.get_ticks_msec() - t0) / 1000.0])
		sim.dispose()
	quit()
