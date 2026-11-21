extends SceneTree
## Build 77: factory smoke and health in the Industrial age. Smoke from a steam engine reaches the house
## beside it, a park takes half of it away, a waterworks brings clean water, health and contentment follow,
## nothing changes before the Industrial age, rivals plan parks and waterworks, saved and loaded games go
## on the same, and a save made without the feature keeps it off.
## godot --headless --script res://tools/health_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


func spot(sim: Sim, ty: String, cx: int, cy: int) -> Vector2i:
	for r in range(0, 25):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and sim.can_place(ty, cx + dx, cy + dy, 1) == "":
					return Vector2i(cx + dx, cy + dy)
	return Vector2i(-1, -1)


func run(sim: Sim, secs: float) -> void:
	for i in int(secs / Sim.TICK):
		sim.tick(Sim.TICK)


func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("smoky", 1, 3, false, 128, false, {"start_goods": 4.0, "features": Features.default_ids()})
	var me := sim.human()
	var fh = sim.get_feature("factory_health")
	check(fh != null, "the feature is on in a new game")
	if fh == null:
		print("HEALTH TEST: FAIL")
		quit()
		return
	run(sim, 1.0)
	for y in range(maxi(0, me.hq.y - 26), mini(sim.h, me.hq.y + 27)):
		for x in range(maxi(0, me.hq.x - 26), mini(sim.w, me.hq.x + 27)):
			if sim.owner[sim.idx(x, y)] == 0: sim.owner[sim.idx(x, y)] = 1
	sim.net_dirty(1)
	var rw := sim.railway
	me.techs["steam_engine"] = true
	me.techs["town_planning"] = true
	me.techs["public_health"] = true
	# a sawmill with a steam engine and a house beside it
	var sm_at := spot(sim, "sawmill", me.hq.x, me.hq.y + 9)
	var sm := sim.add_bld("sawmill", sm_at.x, sm_at.y, me, true)
	var hs_at := spot(sim, "house", sm_at.x + 3, sm_at.y)
	var hs := sim.add_bld("house", hs_at.x, hs_at.y, me, true)
	sim.give(me, "steel", 4.0); sim.give(me, "iron", 8.0); sim.give(me, "bricks", 10.0)
	rw.fit_steam(sm)
	sm.steam_at = sim.time
	run(sim, 6.0)
	# 1. before the Industrial age nothing happens
	check(not fh.active(me) and fh.health_of(me) == 1.0 and fh.smoke_at(me, hs.x, hs.y) == 0.0, "no smoke trouble before the Industrial age (age %d)" % me.age)
	check(fh.speed_bonus(me, sm) == 0.0 and fh.unmet(me) == 0.0, "no work or contentment lost then")
	# 2. the Industrial age: the house is in the smoke
	me.age = 6
	run(sim, 6.0)
	var s0: float = fh.smoke_at(me, hs.x, hs.y)
	check(fh.active(me) and s0 > 0.3, "the house beside the steam engine breathes its smoke (%.2f)" % s0)
	check(fh.air_of(me) > 0.0 and fh.health_of(me) < 1.0, "the realm's health falls (%d%%, air %.2f)" % [roundi(fh.health_of(me) * 100.0), fh.air_of(me)])
	check(fh.speed_bonus(me, sm) < 0.0, "and work goes slower (%.1f%%)" % (fh.speed_bonus(me, sm) * 100.0))
	check(fh.unmet(me) > 0.0 or me.artisan + me.noble == 0, "artisans and nobles miss clean water (%.0f%% unmet)" % (fh.unmet(me) * 100.0))
	var lines: PackedStringArray = fh.building_lines(hs)
	check(lines.size() == 1 and "Air" in lines[0], "the house says what it breathes: %s" % (lines[0] if lines.size() > 0 else "-"))
	check(fh.panel_lines(me).size() >= 1, "the People panel has a line on it")
	# 2b. rivals plan parks and waterworks in their Industrial age
	var have := func(_t): return 0
	var steps: Array = fh.ai_steps(me, have)
	var tys := steps.map(func(s): return s[0])
	var want := {}
	for st in steps: want[st[0]] = int(st[1])
	check(int(want.get("park", 0)) > 0, "a rival in the same place would plan a park: %s" % str(steps))
	check(tys.has("waterworks"), "and has waterworks in its plan")
	check(fh.ai_site_score(me, "park", hs.x + 1, hs.y + 1) > fh.ai_site_score(me, "park", me.hq.x - 20, me.hq.y - 20), "a rival puts a park among smoky homes, not far away")
	check(fh.ai_site_score(me, "house", hs.x + 1, hs.y) < 0.0, "and keeps new homes out of the smoke")
	# 3. a park beside the house takes half the smoke away
	var pk_at := spot(sim, "park", hs.x, hs.y + 3)
	check(pk_at.x >= 0, "a park can be placed")
	var pk := sim.add_bld("park", pk_at.x, pk_at.y, me, true)
	run(sim, 6.0)
	var s1: float = fh.smoke_at(me, hs.x, hs.y)
	check(s1 < s0 * 0.6, "the park halves the smoke at the house (%.2f -> %.2f)" % [s0, s1])
	check(fh.park_share(me) > 0.0, "homes near a park: %d%%" % roundi(fh.park_share(me) * 100.0))
	check(fh.building_lines(pk).size() == 1, "the park says how many homes it helps: %s" % str(fh.building_lines(pk)))
	# 4. a waterworks with coal brings clean water
	var h0: float = fh.health_of(me)
	var ww_at := spot(sim, "waterworks", hs.x - 3, hs.y + 2)
	sim.give(me, "planks", 10.0); sim.give(me, "bricks", 10.0); sim.give(me, "iron", 4.0); sim.give(me, "coal", 20.0)
	check(sim.place("waterworks", ww_at.x, ww_at.y, me) == "", "a waterworks is placed with a road")
	var ww: Sim.Bld = sim.blds[-1]
	for k in 30:
		run(sim, 10.0)
		if fh.water_share(me) > 0.0:
			break
	check(fh.water_share(me) > 0.0, "the waterworks pipes clean water to %d%% of homes (worker %d, %s)" % [roundi(fh.water_share(me) * 100.0), ww.worker, ww.msg])
	check(fh.health_of(me) > h0, "and health is better (%d%% -> %d%%)" % [roundi(h0 * 100.0), roundi(fh.health_of(me) * 100.0)])
	var dis = sim.get_feature("diseases")
	if dis != null:
		var rk: Dictionary = dis.risks(me)
		check(float(rk["dysentery"][1]) > 0.0, "clean water keeps dysentery away (prevention %.2f)" % float(rk["dysentery"][1]))
	# 6. saved and loaded, it goes on the same (from a loaded game: techs given by hand above get their
	# earlier techs on loading)
	var sl := Sim.new()
	sl.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	sim = sl
	fh = sim.get_feature("factory_health")
	me = sim.human()
	run(sim, 5.0)
	var s2 := Sim.new()
	s2.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	var f2 = s2.get_feature("factory_health")
	check(f2 != null and is_equal_approx(f2.health_of(s2.human()), fh.health_of(me)), "health is saved")
	for i in int(60.0 / Sim.TICK):
		sim.tick(Sim.TICK)
		s2.tick(Sim.TICK)
	check(sim.checksum() == s2.checksum(), "the loaded game goes on the same (60 s)")
	# 7. a save from before the feature: it stays off and the game runs
	var d := sim.to_save()
	var o: Dictionary = d.get("opts", {}).duplicate()
	var feats: Array = (o.get("features", []) as Array).duplicate()
	feats.erase("factory_health")
	o["features"] = feats
	d["opts"] = o
	var fs: Dictionary = d.get("feature_state", {}).duplicate()
	fs.erase("factory_health")
	d["feature_state"] = fs
	var s3 := Sim.new()
	s3.from_save(d)
	run(s3, 10.0)
	check(s3.get_feature("factory_health") == null, "an older save keeps the feature off")
	print("HEALTH TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
