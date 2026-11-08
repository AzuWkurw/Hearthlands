extends SceneTree
## How rival realms cope with local stores, carried inputs and walking workers:
## godot --headless --script res://tools/rival_check.gd [-- seed=valley mins=30]
var walks := {}         # kind -> [count, total seconds]
var seen := {}

func _init() -> void:
	GameData.ensure()
	var seed := "valley"; var mins := 30
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="): seed = a.substr(5)
		if a.begins_with("mins="): mins = int(a.substr(5))
	var sim := Sim.new()
	sim.new_game(seed, 7, 6, true)
	var next := 10
	while sim.time < mins * 60.0:
		sim.tick(Sim.TICK)
		if sim.time >= next * 60.0 - 0.05 and sim.time < next * 60.0 + 0.05:
			pass
		for t in sim.trips:
			if t.p != 1 and (t.kind == "worker" or t.kind == "builder" or t.kind == "soldier" or t.dest != 0) and not seen.has(t):
				seen[t] = true
				var k := t.kind if t.dest == 0 else "input"
				var e: Array = walks.get(k, [0, 0.0])
				e[0] += 1; e[1] += t.t1 - t.t0
				walks[k] = e
		if sim.time >= next * 60.0:
			report(sim, next)
			next += 10
	var parts := []
	for k in walks: parts.append("%s %d (%.1f s on average)" % [k, walks[k][0], walks[k][1] / maxf(1, walks[k][0])])
	print("rival trips started: ", ", ".join(parts))
	quit()

func report(sim: Sim, m: int) -> void:
	print("=== minute %d" % m)
	var msgs := {}
	for p in sim.players:
		if p.id == 1 or not p.alive: continue
		var stores: Array = sim.logistics.stores_of(p)
		var cap := 0.0; var have := 0.0; var full_kinds := 0
		var store_txt := []
		for s: Sim.Bld in stores:
			var n := 0.0
			for k in s.inv: n += float(s.inv[k])
			store_txt.append("%s %d" % [s.ty.left(5), int(n)])
		for r in GameData.resources:
			var c := sim.capacity(p, r.id)
			if c > 0 and float(p.stock.get(r.id, 0.0)) >= c - 0.5: full_kinds += 1
		var cnt := {"lodge": 0, "storehouse": 0, "warehouse": 0, "house": 0}
		var wait_in := 0; var need_in := 0; var wait_worker := 0; var walking := 0; var wait_builder := 0; var sites := 0
		for b in sim.blds:
			if b.p != p.id: continue
			if cnt.has(b.ty): cnt[b.ty] += 1
			if b.state == "build":
				sites += 1
				if b.builder != 2: wait_builder += 1
				continue
			if b.def.has("cycle"):
				var mm := b.msg.get_slice(":", 0).get_slice(" (", 0)
				msgs[mm] = int(msgs.get(mm, 0)) + 1
				if mm.begins_with("Waiting for") and mm.ends_with("on its way"): wait_in += 1
				elif mm.begins_with("Needs"): need_in += 1
			if b.worker == 1: walking += 1
			if b.msg.begins_with("Waiting for a worker"): wait_worker += 1
		var trips := {"out": 0, "in": 0, "site": 0}
		for t in sim.trips:
			if t.p != p.id or t.kind in ["worker", "builder", "soldier"]: continue
			trips["in" if t.dest != 0 else ("site" if t.site != 0 else "out")] += 1
		print("%-9s age %d, %3d blds, pop %3d (idle peasants %2d), food %3d%s | stores: %s, %d goods full | storehouses %d, lodges %d | inputs: %d waiting on the way, %d none in store | workers walking %d, no worker reachable %d | sites %d (%d waiting for builder) | carriers free %d, trips out %d in %d site %d" % [
			p.name, p.age, sim.realm_blds(p).size(), sim.pop_total(p), p.peasant - p.used_peasant, int(sim.food_total(p)), " STARVING" if p.starve > 0 else "",
			", ".join(store_txt), full_kinds, cnt.storehouse + cnt.warehouse, cnt.lodge, wait_in, need_in, walking, wait_worker, sites, wait_builder,
			sim.logistics.porters_free(p), trips.out, trips["in"], trips.site])
	var keys := msgs.keys(); keys.sort_custom(func(a, c): return int(msgs[a]) > int(msgs[c]))
	print("rival workshops, top states: ", ", ".join(keys.slice(0, 12).map(func(k): return "%s %d" % [k, msgs[k]])))
