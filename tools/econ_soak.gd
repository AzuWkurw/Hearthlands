extends SceneTree
## Rivals' economy over a long game: festivals, taverns, beer and bread, schools, children, prices.
## godot --headless --script res://tools/econ_soak.gd -- seed=coast mins=60 foes=4
func _init() -> void:
	GameData.ensure()
	var seed := "coast"
	var mins := 60
	var foes := 4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="): seed = a.substr(5)
		if a.begins_with("mins="): mins = int(a.substr(5))
		if a.begins_with("foes="): foes = int(a.substr(5))
	var sim := Sim.new()
	sim.new_game(seed, foes, 5, false, 192, false, {"features": Features.default_ids()})
	var t0 := Time.get_ticks_msec()
	var last := 0
	while sim.time < mins * 60.0:
		sim.tick(Sim.TICK)
		if int(sim.time / 600.0) != last:
			last = int(sim.time / 600.0)
			print("%d min:" % (last * 10))
			var con = sim.get_feature("contentment")
			for p in sim.players:
				if not p.alive: continue
				var c := {}
				for b in sim.realm_blds(p):
					if b.ty in ["tavern", "brewery", "school", "bakery", "chapel", "market"]:
						c[b.ty] = int(c.get(b.ty, 0)) + 1
				var cv = con.cover.get(p.id, [0, 0]) if con != null else [0, 0]
				print("   %s pop %d (art %d) kids %d schooled %d cover %.2f beer %d bread %d gold %d feasts %d %s" % [p.name.substr(0, 6), sim.pop_total(p), p.artisan, p.kids.size(), p.schooled, float(cv[0]), int(p.stock.get("beer", 0)), int(p.stock.get("bread", 0)), int(p.stock.get("gold", 0)), int(con.feasts.get(p.id, 0)) if con != null else -1, c])
			var pr := []
			for r in ["planks", "stone", "bread", "beer", "iron", "tools", "cloth", "gold"]:
				if GameData.res_by_id.has(r): pr.append("%s %.2f" % [r, sim.market.factor(r)])
			print("   prices: %s" % ", ".join(pr))
	for p in sim.players:
		if not p.alive or p.id == 1: continue
		var ms := []
		for b in sim.realm_blds(p):
			if b.ty in ["brewery", "hop_farm", "tavern"]:
				ms.append("%s:%s%s" % [b.ty, b.msg, "" if b.staffed else "(no worker)"])
		var con2 = sim.get_feature("contentment")
		for b in sim.realm_blds(p):
			if b.ty == "tavern":
				var nd := 99.0
				for h in sim.realm_blds(p):
					if h.def.has("housing"): nd = minf(nd, Vector2(h.x - b.x, h.y - b.y).length())
				print("    tavern %s nearest home %.1f served %.0f s ago" % [b.state, nd, sim.time - float(con2.served.get(b.id, -1e9))])
		print("  %s %s grain %d hops %d water %d" % [p.name, ms, int(p.stock.get("grain", 0)), int(p.stock.get("hops", 0)), int(p.stock.get("water", 0))])
	print("%.0f s real" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()
