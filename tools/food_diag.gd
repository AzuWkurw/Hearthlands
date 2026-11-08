extends SceneTree
## Why a rival goes hungry: godot --headless --script res://tools/food_diag.gd [-- who=1]
func _init() -> void:
	GameData.ensure()
	var who := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("who="): who = int(a.substr(4))
	var sim := Sim.new()
	sim.new_game("valley", 7, 6, true)
	var p := sim.players[who]
	var food_res := ["bread", "fish", "meat", "smoked_fish", "smoked_meat", "apples", "honey", "cheese", "sausages", "wine"]
	var next := 12.0
	while sim.time < 22 * 60.0:
		sim.tick(Sim.TICK)
		if sim.time >= next * 60.0:
			next += 1.0
			var st := {}
			var held := 0
			for b in sim.blds:
				if b.p != p.id or b.state != "ready": continue
				held += sim.logistics.food_at(b, true)
				var outs: Dictionary = b.def.get("out", {})
				var makes_food := false
				for o in outs: if o in GameData.food_ids or o in ["grain", "flour"]: makes_food = true
				if makes_food:
					var key := "%s: %s" % [b.ty, b.msg.get_slice(" (", 0)]
					st[key] = int(st.get(key, 0)) + 1
			var stock := []
			for f in GameData.food_ids: if float(p.stock.get(f, 0.0)) >= 1: stock.append("%s %d" % [f, int(p.stock[f])])
			for r in ["grain", "flour", "water"]: stock.append("%s %d" % [r, int(p.stock.get(r, 0.0))])
			print("min %d: pop %d food %d (+%d held at workshops/mines) starve %d | %s" % [int(sim.time / 60), sim.pop_total(p), int(sim.food_total(p)), held, p.starve, ", ".join(stock)])
			var keys := st.keys(); keys.sort()
			print("    ", ", ".join(keys.map(func(k): return "%s x%d" % [k, st[k]])))
	quit()
