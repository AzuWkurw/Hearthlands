extends SceneTree
## Build 54: priority sets, rivals that set priorities. godot --headless --script res://tools/prio2_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("prio2", 2, 5, false, 128, false, {})
	var me := sim.human()
	for i in 20: sim.tick(Sim.TICK)
	check(PrioPresets.apply_named(me, "War") and int(me.carry_rank.get("weapons", 5)) == 1 and int(me.work_rank.get("weaponsmith", 5)) == 1, "the War set puts weapons and weaponsmiths first")
	check(PrioPresets.current(me) == "War", "and is known as the set in use")
	me.carry_rank["stone"] = 2
	check(PrioPresets.current(me) == "", "a changed number is no longer the set")
	PrioPresets.apply(me, {"bread": 2, "nonsense": 1, "food": 5}, {"bakery": 3, "nothing_like_it": 1})
	check(me.carry_rank == {"bread": 2} and me.work_rank == {"bakery": 3}, "a set of your own keeps only goods and kinds the game has (and drops 5s)")
	for name in PrioPresets.BUILT_IN:
		PrioPresets.apply_named(me, name)
		var bad := []
		for k in (PrioPresets.BUILT_IN[name][1] as Dictionary):
			if not (k == "food" or GameData.res_by_id.has(k)): bad.append(k)
		for k in (PrioPresets.BUILT_IN[name][2] as Dictionary):
			if not GameData.bld.has(k): bad.append(k)
		check(bad.is_empty(), "set %s names only real goods and buildings %s" % [name, bad])
	# a rival whose people go hungry puts food first
	var q := sim.players[1]
	for f in GameData.food_ids:
		sim.take(q, f, float(q.stock.get(f, 0.0)))
	q.prio_t = -1000.0
	sim.ai._ai_priorities(q)
	check(q.prio_set == "Feed everyone" and int(q.carry_rank.get("food", 5)) == 1, "a hungry rival puts food first")
	sim.give(q, "bread", 300.0)
	q.prio_t = -1000.0
	sim.ai._ai_priorities(q)
	check(q.prio_set != "Feed everyone", "fed again, it lets go of it (%s)" % (q.prio_set if q.prio_set != "" else "usual numbers"))
	print("PRIO2 TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
