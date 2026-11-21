extends SceneTree
## Rivals in their Industrial age (build 77): do they build parks and waterworks, and how healthy are
## their towns? godot --headless --script res://tools/health_rivals.gd [-- seed=valley mins=25 foes=4]
## Starts every realm with all research done (the Industrial age) and prints each rival's smoke, water, parks,
## health and how many parks and waterworks it built.
func _init() -> void:
	GameData.ensure()
	var seed := "valley"; var mins := 25; var foes := 4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="): seed = a.substr(5)
		if a.begins_with("mins="): mins = int(a.substr(5))
		if a.begins_with("foes="): foes = int(a.substr(5))
	var sim := Sim.new()
	sim.new_game(seed, foes, 6, true, 0, true, {"features": Features.default_ids(), "start_age": 1, "all_research": true})
	var fh = sim.get_feature("factory_health")
	var t_real := Time.get_ticks_usec()
	var next := 300.0
	while sim.time < mins * 60.0:
		sim.tick(Sim.TICK)
		if sim.time >= next:
			next += 300.0
			_report(sim, fh)
	print("took %.0f s" % ((Time.get_ticks_usec() - t_real) / 1e6))
	quit()


func _report(sim: Sim, fh) -> void:
	print("-- minute %d" % int(sim.time / 60.0))
	for p: Sim.Player in sim.players:
		if not p.ai or not p.alive:
			continue
		var n := {"park": 0, "waterworks": 0, "smoky": 0, "steam": 0}
		for b: Sim.Bld in sim.realm_blds(p):
			if b.dead: continue
			if n.has(b.ty): n[b.ty] += 1
			if fh.smoke_of(b) > 0.0: n.smoky += 1
			if b.steam: n.steam += 1
		print("  %-12s age %d pop %3d  health %3d%%  air %.2f  water %3d%%  parks %3d%%  unmet %3d%%  | parks %d, waterworks %d, smoky buildings %d (steam %d), died %d  nobles %d bricks %d coal %d nosite %d" % [p.name, p.age, sim.pop_total(p), roundi(fh.health_of(p) * 100), fh.air_of(p), roundi(fh.water_share(p) * 100), roundi(fh.park_share(p) * 100), roundi(fh.unmet(p) * 100), n.park, n.waterworks, n.smoky, n.steam, int(fh.died.get(p.id, 0)), p.noble, int(p.stock.get("bricks", 0)), int(p.stock.get("coal", 0)), int(sim.ai.stats.get("nosite:waterworks", 0))])
