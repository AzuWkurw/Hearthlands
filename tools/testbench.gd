extends SceneTree
## The test bench (build 66): a long game of computer realms on a big hand-made map (by default the
## player's "Test" map, 448 x 448 with 9 starts, in tools/bench_maps/test.json). Every few minutes it
## prints where the time goes, each realm's age, people, soldiers and tools, and anything that looks
## stuck; at the end a short summary. godot --headless --script res://tools/testbench.gd -- mins=60
## [map=res://tools/bench_maps/test.json] [every=5] [save=user://bench.save]
var map_path := "res://tools/bench_maps/test.json"


func _row(sim: Sim, p: Sim.Player) -> String:
	var tools := 0
	var worn := 0
	var tiers := [0, 0, 0, 0]
	for b: Sim.Bld in sim.realm_blds(p):
		if b.tool_q > 0 and b.worker > 0:
			tools += 1
			tiers[b.tool_q] += 1
			if sim.arms.worn(b): worn += 1
	return "  %-12s age %d %-15s pop %4d sold %3d blds %4d techs %3d | tools %3d (%d bronze, %d iron, %d steel, %d worn) wpn %3d" % [
		p.name.left(12), p.age, GameData.age_name(p.age), sim.pop_total(p), sim.mix_count(sim.soldier_mix(p)), sim.realm_blds(p).size(),
		p.techs.size(), tools, tiers[1], tiers[2], tiers[3], worn, int(p.stock.get("weapons", 0.0))]


func _init() -> void:
	var mins := 60.0
	var every := 5.0
	var save_to := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("mins="): mins = float(a.substr(5))
		if a.begins_with("map="): map_path = a.substr(4)
		if a.begins_with("every="): every = float(a.substr(6))
		if a.begins_with("save="): save_to = a.substr(5)
	GameData.ensure()
	var m := WorldGen.load_map(map_path)
	if m.is_empty():
		print("TESTBENCH: no map at ", map_path)
		quit()
		return
	var sim := Sim.new()
	var foes := maxi(1, (m.starts as Array).size() - 1)
	var t_real := Time.get_ticks_msec()
	sim.new_game(String(m.get("seed", "bench")), foes, 6, true, 0, false, {"features": Features.default_ids()}, m)
	sim.players[0].ai = true
	sim._recompute_mods(sim.players[0])
	print("TESTBENCH: %s, %d x %d, %d realms, %.0f min (set up in %d ms)" % [m.get("name", "?"), sim.w, sim.h, sim.players.size(), mins, Time.get_ticks_msec() - t_real])
	var errors_at := 0
	var next := every
	var last_pop := {}
	var stuck := {}
	sim.perf = {}
	var span_t := sim.time
	var span_real := Time.get_ticks_msec()
	while sim.time < mins * 60.0 and not sim.over:
		sim.tick(Sim.TICK)
		if sim.time >= next * 60.0:
			var secs := sim.time - span_t
			var parts := []
			var total := 0.0
			for k in sim.perf:
				total += float(sim.perf[k])
			var keys := sim.perf.keys()
			keys.sort_custom(func(x, y): return float(sim.perf[x]) > float(sim.perf[y]))
			for k in keys.slice(0, 8):
				parts.append("%s %.1f" % [k, float(sim.perf[k]) / secs / 1000.0])
			print("min %3d: %.1f ms per game second (%.0fx real time) | %s | %d buildings, %d trips, %d animals" % [
				roundi(next), total / secs / 1000.0, secs * 1000.0 / maxf(1.0, float(Time.get_ticks_msec() - span_real)), ", ".join(parts),
				sim.blds.size(), sim.trips.size(), (sim.get_feature("wildlife").animals.size() if sim.get_feature("wildlife") != null else 0)])
			for p in sim.players:
				if not p.alive:
					continue
				print(_row(sim, p))
				var pop := sim.pop_total(p)
				if last_pop.has(p.id) and pop <= int(last_pop[p.id]) and next >= 15.0:
					stuck[p.id] = int(stuck.get(p.id, 0)) + 1
				else:
					stuck[p.id] = 0
				last_pop[p.id] = pop
				if int(stuck[p.id]) >= 3:
					print("  !! %s has not grown for %d minutes" % [p.name, roundi(every * 3)])
			sim.perf = {}
			span_t = sim.time
			span_real = Time.get_ticks_msec()
			next += every
	print("TESTBENCH: %.0f game minutes in %.0f s" % [sim.time / 60.0, (Time.get_ticks_msec() - t_real) / 1000.0])
	var ages := []
	for p in sim.players:
		ages.append("%s %s%s" % [p.name.left(10), GameData.age_name(p.age), "" if p.alive else " (fallen)"])
	print("TESTBENCH ages: ", ", ".join(ages))
	if save_to != "":
		var f := FileAccess.open(save_to, FileAccess.WRITE)
		f.store_var(sim.to_save())
		f.close()
		print("TESTBENCH: saved to ", save_to)
	print("TESTBENCH: DONE")
	quit()
