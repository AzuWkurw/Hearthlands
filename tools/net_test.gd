extends SceneTree
## Checks that updating road networks step by step gives exactly the same walking distances as
## rebuilding them from scratch, every 10 game seconds of an AI-only game.
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("nettest", 6, 6, true, 160)
	for p in sim.players: p.ai = true
	var checks := 0
	var bad := 0
	var relaxed := 0
	while sim.time < 20 * 60.0:
		for i in 100:
			sim.tick(Sim.TICK)
		for p in sim.players:
			var k: int = p.id - 1
			if not p.alive:
				continue
			if not (sim._net_add[k] as Array).is_empty() and not sim._net_dirty[k]:
				relaxed += 1
			sim._net_ready(p.id)
			var inc: PackedFloat32Array = sim._net_dist[k]
			sim._build_net(p.id)
			var full: PackedFloat32Array = sim._net_dist[k]
			checks += 1
			if inc != full:
				bad += 1
				var n := 0
				for i in inc.size():
					if inc[i] != full[i]: n += 1
				print("MISMATCH realm %d at %.0f s: %d tiles differ" % [p.id, sim.time, n])
	print("NETTEST %d checks, %d step-by-step updates, %d mismatches" % [checks, relaxed, bad])
	quit()
