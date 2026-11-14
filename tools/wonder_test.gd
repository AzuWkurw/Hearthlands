extends SceneTree
## Wonders: one per age, built once by each realm, their bonus counts while they stand, and the first
## realm with all five wins (with the peaceful victory on): godot --headless --script res://tools/wonder_test.gd
func _init() -> void:
	GameData.ensure()
	var ok := true
	var sim := Sim.new()
	sim.new_game("wonders", 1, 4, true)
	for i in 5: sim.tick(Sim.TICK)
	var me := sim.human()
	var won := [null]
	sim.ended.connect(func(w): won[0] = w)
	print("wonders in the game: ", Sim.wonder_count())
	if Sim.wonder_count() != 5: ok = false; print("FAIL: five wonders")
	# before its age: locked
	var spot := Vector2i(me.hq.x + 6, me.hq.y + 6)
	print("great hall before its age: '%s'" % sim.can_place("great_hall", spot.x, spot.y, 1))
	sim.complete_tech(me, "new_kingdoms")
	var tax0 := sim.mod(me, "tax")
	var ids := ["great_hall", "cathedral", "grand_academy", "observatory", "exhibition_palace"]
	var x := 2
	for k in ids.size():
		var b := sim.add_bld(ids[k], x, 2, me, false, 0)
		x += 6
		sim.production._finish_site(b, me)
		if k == 0:
			print("great hall: tax %+.2f -> %+.2f, wonders %d" % [tax0, sim.mod(me, "tax"), sim.wonders_of(me).size()])
			if absf(sim.mod(me, "tax") - tax0 - 0.10) > 0.001: ok = false; print("FAIL: the great hall's tax")
			var why := sim.can_place("great_hall", spot.x, spot.y, 1)
			print("a second great hall: '%s'" % why)
			if not why.begins_with("Your realm has its Great hall"): ok = false; print("FAIL: a wonder is built once")
		if k == 3:
			print("over after four: ", sim.over)
			if sim.over: ok = false; print("FAIL: four wonders don't win")
	print("after five: over %s, won %s" % [sim.over, won[0]])
	if not sim.over or won[0] != true: ok = false; print("FAIL: five wonders win")
	# a wonder lost takes its bonus with it
	var r0 := sim.mod(me, "research")
	sim.destroy(sim.wonders_of(me).filter(func(b): return b.ty == "grand_academy")[0], "is pulled down.")
	print("academy gone: research %+.2f -> %+.2f" % [r0, sim.mod(me, "research")])
	if absf(r0 - sim.mod(me, "research") - 0.20) > 0.001: ok = false; print("FAIL: the academy's research goes with it")
	print("wonder test: ", "ok" if ok else "FAILED")
	sim.dispose()
	quit()
