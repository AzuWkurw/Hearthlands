extends SceneTree
## Every campaign chapter and every mission starts as its data says (age, realms, map), its events are
## well formed, and five minutes of it (you played by the computer) run with events firing and no error.
## godot --headless --script res://tools/chapters_test.gd   (-- only=b9 for one chapter, mins=N to play longer)

func _init() -> void:
	GameData.ensure()
	var only := ""
	var mins := 5.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="): only = a.substr(5)
		if a.begins_with("mins="): mins = float(a.substr(5))
	var list := []
	var camp = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign.json"))
	for ch in camp.chapters:
		list.append([String(ch.id), ch.mission])
	for ms in UiMissions.missions():
		list.append([String(ms.get("id", "")), ms])
	var ok := true
	for it in list:
		if only != "" and it[0] != only:
			continue
		var ms: Dictionary = it[1]
		var sim := Sim.new()
		var o := Main.DEFAULT_MISSION_OPTS.duplicate()
		o.merge(ms.get("opts", {}), true)
		var started := false
		if ms.has("map"):
			var m := WorldGen.load_map(String(ms.map))
			started = not m.is_empty() and sim.new_game(String(m.seed), int(ms.foes), int(ms.strength), true, 0, false, o, m, ms)
		else:
			started = sim.new_game(String(ms.get("seed", "mission")), int(ms.get("foes", 1)), int(ms.get("strength", 5)), true, int(ms.get("size", 0)), false, o, {}, ms)
		if not started:
			print("%s: did not start" % it[0])
			ok = false
			continue
		var me := sim.human()
		var want_age := int(o.get("start_age", 0))
		var age_ok := me.age == want_age and sim.players.all(func(p): return p.age == want_age)
		var bad := MissionScript.problems(ms)
		# every goal must be of a known kind, every building and study must exist
		for g in ms.get("goals", []):
			if String(g.get("kind", "")) == "build" and not GameData.bld.has(String(g.ty)): bad.append("no building " + String(g.ty))
			if String(g.get("kind", "")) == "tech" and not GameData.techs.has(String(g.id)): bad.append("no study " + String(g.id))
			if String(g.get("kind", "")) == "stock" and not GameData.res_by_id.has(String(g.res)): bad.append("no good " + String(g.res))
		me.ai = true
		var t0 := Time.get_ticks_msec()
		while sim.time < mins * 60.0 and not sim.over:
			sim.tick(Sim.TICK)
		var prog := []
		for g in ms.get("goals", []):
			prog.append("%s%s" % [str(sim.goal_progress(g)), "h" if g.get("hidden", false) else ""])
		var fired := sim.script_fired.keys()
		var good: bool = age_ok and bad.is_empty() and sim.players.size() == int(ms.get("foes", 1)) + 1 and (not (ms.get("rules", []) as Array).size() > 0 or fired.size() > 0) and (not bool(o.get("sea_start", false)) or me.landed)
		print("%-6s %s  age %d (%s), %d realms, %dx%d, %.0f s; fired %s; goals %s%s" % [it[0], "ok " if good else "BAD", me.age, GameData.age_name(me.age), sim.players.size(), sim.w, sim.h, (Time.get_ticks_msec() - t0) / 1000.0, fired, " ".join(prog), ("; " + "; ".join(bad)) if not bad.is_empty() else ""])
		ok = ok and good
		sim.dispose()
	print("chapters test: ", "ok" if ok else "FAILED")
	quit()
