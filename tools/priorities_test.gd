extends SceneTree
## Transport and worker priorities in numbers: godot --headless --script res://tools/priorities_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("prio", 1, 4, true)
	for i in 5: sim.tick(Sim.TICK)
	var me := sim.human()
	# transport: the order goods are taken in
	check(SimLogistics.by_rank(me, {"planks": 3, "stone": 2}) == ["planks", "stone"], "with no numbers set, goods keep their order")
	me.carry_rank = {"stone": 1}
	check(SimLogistics.by_rank(me, {"planks": 3, "stone": 2}) == ["stone", "planks"], "stone at 1 goes before planks")
	me.carry_rank = {"food": 2, "fish": 8}
	check(SimLogistics.rank_of(me, "bread") == 2 and SimLogistics.rank_of(me, "fish") == 8, "\"any food\" counts for bread; fish has its own number")
	# a building site takes the material with the lower number first
	me.carry_rank = {"stone": 1}
	var site: Sim.Bld = null
	for dy in range(2, 9):
		for dx in range(-6, 7):
			if site == null and sim.place("toolsmith", me.hq.x + dx, me.hq.y + dy, me) == "":
				site = sim.by_id.get(sim.bmap[sim.idx(me.hq.x + dx, me.hq.y + dy)])
	var first := ""
	if site != null:
		print("    road: '%s'" % sim.build_road(site.x, site.y, me.hq.x, me.hq.y, 1))
		for i in 600:
			sim.tick(Sim.TICK)
			for t in sim.trips:
				if t.site == site.id and first == "" and t.kind != "builder" and t.res != "":
					first = t.res
			if first != "":
				break
	check(first == "stone", "a building site gets stone (1) before planks (5): first load %s" % first)
	# workers: two kinds wait, one peasant is free
	me.carry_rank = {}
	var wc := sim.add_bld("woodcutter", me.hq.x - 4, me.hq.y + 4, me, false, 0)
	sim.production._finish_site(wc, me)
	var qu := sim.add_bld("quarry", me.hq.x - 4, me.hq.y - 3, me, false, 0)
	sim.production._finish_site(qu, me)
	me.spare_builder = false
	sim._rebuild_realm_lists()
	# exactly one peasant to give out among these two
	var others := 0
	for b in sim.realm_blds(me):
		if b != wc and b != qu and String(b.def.get("worker", "")) == "peasant" and b.state == "ready":
			others += 1
		if b.state == "build":
			others += 1
	me.peasant = others + 1 + me.away
	me.work_rank = {"quarry": 1}
	sim.staffing(me)
	print("    peasants %d, used %d; woodcutter %s %s, quarry %s %s" % [me.peasant, me.used_peasant, wc.staffed, wc.msg, qu.staffed, qu.msg])
	check(qu.staffed and not wc.staffed, "quarry at 1: the one free peasant goes to the quarry")
	me.work_rank = {"woodcutter": 2, "quarry": 7}
	sim.staffing(me)
	check(wc.staffed and not qu.staffed, "woodcutter 2, quarry 7: he goes to the woodcutter")
	# a building's own priority still comes first
	qu.prio = Sim.PRIO_HIGH
	sim.staffing(me)
	check(qu.staffed and not wc.staffed, "the quarry set to High in its info comes first anyway")
	# kept with the game
	me.carry_rank = {"stone": 1, "food": 3}
	var b2 := Sim.new()
	b2.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	check(b2.human().carry_rank == {"stone": 1, "food": 3} and b2.human().work_rank == me.work_rank, "the numbers are saved with the game")
	print("PRIORITIES TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
