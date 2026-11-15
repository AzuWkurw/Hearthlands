extends SceneTree
## Worker limits, the standby builder, moving a building, crops by season, map ore amounts and
## animals, and the fog not showing land of the game before:
## godot --headless --script res://tools/econ2_test.gd

func _init() -> void:
	GameData.ensure()
	var ok := true
	var sim := Sim.new()
	sim.new_game("econ2", 1, 4, true)
	var me := sim.human()
	me.peasant += 20
	var mx := me.hq.x; var my := me.hq.y
	# three woodcutters, a limit of one
	var wcs: Array = []
	for y in range(my - 9, my + 10):
		for x in range(mx - 9, mx + 10):
			if wcs.size() < 3 and Vector2(x - mx, y - my).length() > 4 and sim.can_place("woodcutter", x, y, 1) == "":
				wcs.append(sim.add_bld("woodcutter", x, y, me, true, 0))
	sim._rebuild_realm_lists()
	for b: Sim.Bld in wcs:
		b.staffed = true
	sim.staffing(me)
	var before := wcs.filter(func(b): return b.staffed).size()
	me.job_limit["woodcutter"] = 1
	sim.staffing(me)
	var after := wcs.filter(func(b): return b.staffed).size()
	print("woodcutters with workers: %d, with a limit of 1: %d" % [before, after])
	if before < 2 or after != 1: ok = false; print("FAIL: the worker limit")
	me.job_limit = {}
	# the standby builder: one peasant stays free
	sim.staffing(me)
	var free0 := me.peasant - me.used_peasant - me.away
	me.spare_builder = true
	me.peasant = me.used_peasant             # every peasant at work
	sim.staffing(me)
	var free1 := me.peasant - me.used_peasant - me.away
	print("free peasants: %d; all busy with a standby builder: %d free" % [free0, free1])
	if free1 != 1: ok = false; print("FAIL: one peasant should stay free as builder")
	me.spare_builder = false
	me.peasant += 10
	sim.staffing(me)
	# moving a building: the new one takes over when finished
	var old: Sim.Bld = wcs[0]
	old.prio = Sim.PRIO_HIGH
	var nb: Sim.Bld = null
	for y in range(my - 12, my + 13):
		for x in range(mx - 12, mx + 13):
			if nb == null and Vector2(x - old.x, y - old.y).length() > 5 and sim.can_place("woodcutter", x, y, 1) == "":
				nb = sim.add_bld("woodcutter", x, y, me, false, 0)
	nb.replaces = old.id
	nb.need = {}; nb.mat_total = 0
	sim.production._finish_site(nb, me)
	print("moved woodcutter: new one %s, old one gone %s, priority carried %s" % [nb.state, old.dead or not sim.by_id.has(old.id), nb.prio == Sim.PRIO_HIGH])
	if nb.state != "ready" or not (old.dead or not sim.by_id.has(old.id)) or nb.prio != Sim.PRIO_HIGH: ok = false; print("FAIL: moving a building")
	# crops by season, and the same plan for every farm
	sim._rebuild_realm_lists()
	var farms: Array = []
	for y in range(my - 20, my + 21):
		for x in range(mx - 20, mx + 21):
			if farms.size() < 2 and sim.inb(x, y) and sim.can_place("farm", x, y, 1) == "":
				farms.append(sim.add_bld("farm", x, y, me, true, 0))
	sim._rebuild_realm_lists()
	sim.complete_tech(me, "open_fields")
	sim.complete_tech(me, "heavy_plough")
	var f0: Sim.Bld = farms[0]
	var s := Crops.season_now(sim)
	f0.season_crop = ["", "", "", "rye"]
	f0.season_crop[s] = "vegetables"
	print("season %d: farm sows %s (plan %s)" % [s, Crops.now(sim, f0), str(f0.season_crop)])
	if Crops.now(sim, f0) != "vegetables": ok = false; print("FAIL: the crop for this season")
	var n := Crops.apply_to_all(sim, f0)
	print("plan copied to %d other farm(s): %s" % [n, str((farms[1] as Sim.Bld).season_crop)])
	if (farms[1] as Sim.Bld).season_crop != f0.season_crop: ok = false; print("FAIL: copying the plan")
	# a map with painted ore amounts and placed animals
	var g := WorldGen.generate("orez", 1, 96)
	var m := {"name": "t", "w": g.w, "h": g.h, "seed": "orez", "starts": g.starts}
	for k in WorldGen.MAP_KEYS:
		m[k] = (g[k] as PackedByteArray).duplicate()
	var placed := 0
	var at := -1
	for i in g.w * g.h:
		# (away from the starts: their home mountains are stamped over the map)
		var far := true
		for st in g.starts:
			if Vector2(i % g.w - st.x, i / g.w - st.y).length() < 22.0: far = false
		if g.ter[i] == Sim.MOUNT and far and placed < 4 and (at < 0 or i == at + 1):
			m.ore[i] = 2; m.amt[i] = WorldGen.ORE_AMOUNTS[3]
			at = i; placed += 1
		elif g.ter[i] == Sim.MOUNT:
			m.ore[i] = 0
	m["animals"] = [["deer", g.starts[0].x + 6, g.starts[0].y + 6], ["wolf", g.starts[0].x - 6, g.starts[0].y + 6]]
	var path := "user://maps/_econ2_test.json"
	WorldGen.save_map(m, path)
	var m2 := WorldGen.load_map(path)
	var sim2 := Sim.new()
	sim2.new_game("x", 1, 4, true, 0, false, {}, m2)
	var vt := sim2.vein[at]
	var wl = sim2.get_feature("wildlife")
	print("painted vein: %d units (want %d); animals from the map: %d" % [int(sim2.vein_amt[vt]), placed * WorldGen.ORE_AMOUNTS[3] * WorldGen.ORE_UNIT, wl.animals.size() if wl != null else -1])
	if int(sim2.vein_amt[vt]) != placed * WorldGen.ORE_AMOUNTS[3] * WorldGen.ORE_UNIT: ok = false; print("FAIL: the painted ore amount")
	if wl != null and wl.animals.size() != 2: ok = false; print("FAIL: the map's animals")
	DirAccess.remove_absolute(path)
	# a new game on the same Sim object doesn't see the old game's buildings (the fog patches)
	var sim3 := Sim.new()
	sim3.new_game("fogold", 2, 4, true)
	var old_hq: Sim.Bld = sim3.human().hq
	sim3.new_game("fognew", 2, 4, true)
	var fog = sim3.get_feature("fog")
	var far := 0
	if fog != null:
		for i in sim3.w * sim3.h:
			if fog.explored[i] == 1 and Vector2(i % sim3.w - sim3.human().hq.x, i / sim3.w - sim3.human().hq.y).length() > 20:
				far += 1
	print("explored land far from the new headquarters: %d tiles (old hq was at %d,%d)" % [far, old_hq.x, old_hq.y])
	if far > 0: ok = false; print("FAIL: the fog shows land around the old game's buildings")
	print("ECON2 TEST: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
