extends SceneTree
## Military upgrades, border priority, separate archers and rivals breaking the peace:
## godot --headless --script res://tools/mil2_test.gd

func _init() -> void:
	GameData.ensure()
	var ok := true
	var sim := Sim.new()
	sim.new_game("mil2", 1, 4, true)
	var me := sim.human()
	var mx := me.hq.x; var my := me.hq.y
	# an upgrade: hut (2) -> tower (4)? same size only: a hut is small; a guardhouse/tower are medium
	var t: Sim.Bld = null
	for y in range(my - 8, my + 9):
		for x in range(mx - 8, mx + 9):
			if t == null and sim.can_place("tower", x, y, 1) == "" and Vector2(x - mx, y - my).length() > 3:
				t = sim.add_bld("guardhouse", x, y, me, true, 0)
	t.garrison = 2; t.gmix = [2, 0, 0, 0, 0, 0]
	var ups := sim.upgrades_of(t)
	print("guardhouse (3 soldiers) can become: %s" % str(ups))
	if not ups.has("tower"): ok = false; print("FAIL: a guardhouse should upgrade to a tower")
	var r := sim.upgrade(t, "tower")
	var cost := sim.upgrade_cost(t, "tower")
	print("upgrade '%s', costs %s" % [r, str(cost)])
	# (it has no road in this test: the carriers' loads are put on site)
	for k in t.need:
		t.onsite[k] = int(t.need[k])
	t.need = {}
	var land0: int = (sim.owned(1)[0] as Array).size()
	var t0 := sim.time
	while t.ty != "tower" and sim.time < t0 + 400.0:
		sim.tick(Sim.TICK)
	var land1: int = (sim.owned(1)[0] as Array).size()
	print("after %d s: it is a %s, garrison %d, land %d -> %d" % [int(sim.time - t0), t.ty, t.garrison, land0, land1])
	if t.ty != "tower" or land1 <= land0: ok = false; print("FAIL: the upgrade did not finish or claim more land")
	# archers are extra to the soldiers
	t.archer_want = 2
	sim.give(me, "bows", 5.0)
	for i in 50: sim.tick(Sim.TICK)
	print("tower: %d soldiers + %d archers (own_def %d)" % [t.garrison, t.archers, sim.own_def(t)])
	if t.archers != maxi(1, (t.garrison + 1) / 2) or sim.own_def(t) != t.garrison: ok = false; print("FAIL: archers should be extra (half the soldiers inside) and not counted as soldiers")
	# border priority: inland buildings hold half
	me.inner_pct = 50
	t.border = false
	t.want_n = -1
	var want := sim.garrison_wanted(t)
	print("inland tower with 50%%: wants %d of %d" % [want, int(t.def.garrison)])
	if want != 2: ok = false; print("FAIL: inland at 50% should want 2")
	t.border = true
	if sim.garrison_wanted(t) != int(t.def.garrison): ok = false; print("FAIL: a border building wants all")
	# rivals break a peace with a neighbour over time
	var sim2 := Sim.new()
	sim2.new_game("peacewar", 3, 6, true, 96)
	var hu := sim2.human()
	hu.ai = true; hu.skill = 6; hu.pers = "balanced"; hu.prod = 1.0; hu.think = 3.0; hu.max_b = 2
	for q in sim2.players:
		for q2 in sim2.players:
			if q.id < q2.id: Diplomacy.set_relation(sim2, q.id, q2.id, Diplomacy.PEACE)
	var wars := []
	while sim2.time < 3600.0 and wars.is_empty():
		sim2.tick(Sim.TICK)
		if int(sim2.time * 10.0) % 300 == 0:
			for q in sim2.players:
				for q2 in sim2.players:
					if q.id < q2.id and Diplomacy.at_war(sim2, q.id, q2.id) and not wars.has("%d-%d" % [q.id, q2.id]):
						wars.append("%d-%d" % [q.id, q2.id])
						print("  minute %d: war between %s (%s) and %s (%s)" % [int(sim2.time / 60.0), q.name, q.pers, q2.name, q2.pers])
	print("wars in an hour that began at peace: %d" % wars.size())
	if wars.is_empty(): ok = false; print("FAIL: no rival ever broke the peace")
	print("MIL2 TEST: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
