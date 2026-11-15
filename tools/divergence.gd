extends SceneTree
## Finds where a loaded game first plays differently from the game it was saved from:
##   godot --headless --script res://tools/divergence.gd -- seed=isle2 size=224 foes=6 shape=isles opt=all_research,sea_start at=60
## (the human played by the computer, as in soak_test). Prints the first tick that differs and what.
func _diff(a: Sim, b: Sim) -> Array:
	var da := a.to_save(); var db := b.to_save()
	var out := []
	for k in da:
		if k == "blds" or k == "trips" or k == "attacks" or k == "players":
			for j in mini(da[k].size(), db[k].size()):
				for f in da[k][j]:
					if f != "path_ver" and var_to_str(da[k][j][f]) != var_to_str(db[k][j].get(f)):
						out.append("%s[%d] %s.%s: %s vs %s" % [k, j, str(da[k][j].get("ty", da[k][j].get("kind", ""))), f, str(da[k][j][f]).left(150), str(db[k][j].get(f)).left(150)])
			if da[k].size() != db[k].size():
				out.append("%s: %d vs %d" % [k, da[k].size(), db[k].size()])
		elif k == "feature_state":
			for fk in da[k]:
				var sa: Dictionary = da[k][fk]; var sb: Dictionary = db[k].get(fk, {})
				for kk in sa:
					if var_to_str(sa[kk]) != var_to_str(sb.get(kk)):
						out.append("feature %s.%s: %s vs %s" % [fk, kk, str(sa[kk]).left(200), str(sb.get(kk)).left(200)])
		elif var_to_str(da[k]) != var_to_str(db.get(k)):
			out.append("%s: %s vs %s" % [k, str(da[k]).left(200), str(db.get(k)).left(200)])
	return out


func _init() -> void:
	GameData.ensure()
	var seed := "valley"; var size := 0; var foes := 5; var at := 30; var opts := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="): seed = a.substr(5)
		if a.begins_with("size="): size = int(a.substr(5))
		if a.begins_with("foes="): foes = int(a.substr(5))
		if a.begins_with("at="): at = int(a.substr(3))
		if a.begins_with("shape="): opts["gen"] = {"shape": a.substr(6)}
		if a.begins_with("opt="):
			for o in a.substr(4).split(","): opts[o] = true
	var sim := Sim.new()
	sim.new_game(seed, foes, 6, true, size, false, opts)
	var me := sim.human()
	me.ai = true; me.skill = 6; me.pers = "balanced"; me.prod = 1.0; me.think = 3.0; me.max_b = 2
	while sim.time < at * 60.0:
		sim.tick(Sim.TICK)
	var twin := Sim.new()
	twin.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	print("saved at %.1f s; first check: %s" % [sim.time, _diff(sim, twin).slice(0, 5)])
	var last_ok := 0
	for t in 3000:
		sim.tick(Sim.TICK); twin.tick(Sim.TICK)
		if (t + 1) % 20 != 0 and sim.rng.state == twin.rng.state and sim.trips.size() == twin.trips.size():
			continue
		var dd := _diff(sim, twin)
		if dd.is_empty():
			last_ok = t + 1
			continue
		print("first difference seen after %d ticks (same at %d):" % [t + 1, last_ok])
		for l in dd.slice(0, 30): print("  ", l)
		break
	quit()
