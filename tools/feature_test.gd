extends SceneTree
## Tests the feature system: statistics counting, saving and loading feature data, switching a feature
## off, and a mod loaded from the mods folder.
func _init() -> void:
	GameData.ensure()
	# install the example mod
	var dir := Features.ensure_mod_dir()
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://mods_examples/bountiful_harvest.gd"), dir + "/bountiful_harvest.gd")
	var avail := Features.available()
	print("features found: ", avail.map(func(e): return "%s%s" % [e.id, " (mod)" if e.mod else ""]))
	var sim := Sim.new()
	sim.new_game("feat", 2, 5, false, 0, true, {"features": ["statistics", "bountiful_harvest"]})
	for p in sim.players: p.ai = true
	print("switched on: ", sim.feature_ids())
	while sim.time < 6 * 60.0: sim.tick(Sim.TICK)
	var st = sim.get_feature("statistics")
	var h: Array = st.hist.get(1, [])
	var m := 0.0
	for b in h: m += float(b.made.get("planks", 0.0))
	print("statistics: %d minutes counted, %.0f planks made, population now %d" % [h.size(), m, h[-1].pop])
	var harvest = sim.get_feature("bountiful_harvest")
	print("mod: harvest until %.0f s; farm bonus now %.2f" % [harvest.until, harvest.speed_bonus(sim.players[0], sim.blds.filter(func(b): return b.ty == "farm")[0]) if sim.blds.any(func(b): return b.ty == "farm") else -1.0])
	var data := sim.to_save()
	var sim2 := Sim.new()
	print("load: '%s', features %s, statistics minutes %d" % [sim2.from_save(data), sim2.feature_ids(), sim2.get_feature("statistics").hist.get(1, []).size()])
	sim2.set_feature("statistics", false)
	print("after switching statistics off: ", sim2.feature_ids())
	sim2.tick(Sim.TICK)
	DirAccess.remove_absolute(dir + "/bountiful_harvest.gd")
	sim.dispose(); sim2.dispose()
	quit()
