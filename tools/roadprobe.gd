extends SceneTree
## Road quality in an AI-only game: road tiles per building, average walk to the nearest store,
## and how long road work took.
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("roads", 6, 6, true, 160)
	for p in sim.players: p.ai = true
	var t0 := Time.get_ticks_msec()
	while sim.time < 30 * 60.0:
		sim.tick(Sim.TICK)
	var ms := Time.get_ticks_msec() - t0
	var roads := 0; var blds := 0; var walk := 0.0; var nw := 0; var unconn := 0
	for i in sim.w * sim.h:
		if sim.road[i] != 0: roads += 1
	for b in sim.blds:
		if not sim.players[b.p - 1].alive: continue
		blds += 1
		if b.cyc > 0.0 and b.state == "ready":
			var d := sim.net_dist(b.p, sim.idx(b.x, b.y))
			if d < Sim.INF: walk += d; nw += 1
			else: unconn += 1
	var perf := sim.perf
	print("ROADS 30 min in %d ms | %d buildings, %d road tiles (%.2f per building) | average walk to a store %.2f s over %d working buildings, %d unconnected | road network %.0f ms, road laying %.0f ms" % [ms, blds, roads, float(roads) / blds, walk / maxi(1, nw), nw, unconn, float(perf.get("road network", 0)) / 1000.0, float(perf.get("road laying", 0)) / 1000.0])
	quit()
