extends SceneTree
## The chronicle (build 77): the game notes its history as it goes (towns, ages, wonders, captures,
## repelled attacks, fires, famines, fallen realms), the notes survive a save and load, and the written
## story names them: godot --headless --script res://tools/chronicle_test.gd
func _init() -> void:
	GameData.ensure()
	var ok := true
	var sim := Sim.new()
	sim.new_game("chronicle", 2, 4, true)
	for i in 3600: sim.tick(Sim.TICK)   # 6 minutes of real play
	var me := sim.human()
	var foe: Sim.Player = sim.players[1]
	var foe2: Sim.Player = sim.players[2]
	print("notes after 6 minutes: ", sim.players.map(func(p): return p.chron.size()))
	# an age: the gate study of the next age (the real hook in complete_tech)
	var age0 := me.age
	for id in GameData.techs:
		var t: Dictionary = GameData.techs[id]
		if t.get("gate", false) and int(t.get("age", 0)) == age0 + 1:
			sim.complete_tech(me, id)
			break
	print("age %d -> %d" % [age0, me.age])
	if me.age == age0 or me.chron.filter(func(e): return e.k == "age").is_empty(): ok = false; print("FAIL: the new age is noted")
	# a wonder (the real hook in _wonder_done)
	var wb := sim.add_bld("great_hall", 2, 2, me, false, 0)
	sim.production._finish_site(wb, me)
	if me.chron.filter(func(e): return e.k == "wonder").is_empty(): ok = false; print("FAIL: the wonder is noted")
	# a town: a storehouse site finished
	var sb := sim.add_bld("storehouse", 10, 2, me, false, 0)
	sim.production._finish_site(sb, me)
	var towns := me.chron.filter(func(e): return e.k == "town")
	print("towns noted: ", towns.map(func(e): return e.name))
	if towns.is_empty() or String(towns[-1].name) != sb.town: ok = false; print("FAIL: the new town is noted")
	# fires: two close together are one story; famine with a death
	Chronicle.fire(sim, me); Chronicle.fire(sim, me); Chronicle.burned(sim, me)
	var fires := me.chron.filter(func(e): return e.k == "fire")
	if fires.size() != 1 or int(fires[0].n) != 2 or int(fires[0].lost) != 1: ok = false; print("FAIL: fires merge ", fires)
	var fam0 := me.chron.filter(func(e): return e.k == "famine")
	var dead0 := int(fam0[-1].dead) if not fam0.is_empty() and sim.time - float(fam0[-1].e) <= Chronicle.MERGE_S else 0
	Chronicle.famine(sim, me); Chronicle.famine(sim, me, 1); Chronicle.famine(sim, me, 1)
	var fam := me.chron.filter(func(e): return e.k == "famine")
	if fam.size() != maxi(1, fam0.size()) or int(fam[-1].dead) != dead0 + 2: ok = false; print("FAIL: famine merge ", fam)
	# war: a capture both ways, an attack held, a realm that fell (the real hook in eliminate)
	Chronicle.note(sim, me, "capture", {"o": foe.id, "b": "guard_tower"})
	Chronicle.note(sim, foe, "capture", {"o": me.id, "b": "guard_tower"})
	Chronicle.note(sim, me, "repelled", {"o": foe.id})
	Chronicle.note(sim, me, "field_won", {"o": foe.id})
	sim.military.eliminate(foe2, me)
	if foe2.chron.filter(func(e): return e.k == "fall").is_empty(): ok = false; print("FAIL: the fall is noted")
	for i in 600: sim.tick(Sim.TICK)
	# the cap: a long war keeps the big moments
	var many := Sim.Player.new()
	many.id = 9
	for i in Chronicle.MAX + 50:
		Chronicle.note(sim, many, "repelled" if i % 2 == 0 else "capture", {"o": 1})
	if many.chron.size() != Chronicle.MAX: ok = false; print("FAIL: notes capped")
	if many.chron.filter(func(e): return e.k == "capture").size() != (Chronicle.MAX + 50) / 2: ok = false; print("FAIL: captures kept over minor notes")
	# the story
	var text := Chronicle.new().story(sim, true)
	print(text)
	for want in ["(minutes 0 to", "raised their headquarters", "was finished", "War with", "beaten back", "Fire broke out 2 times", "of your people starved", "your soldiers took the headquarters", "At its height", "The end"]:
		if not text.contains(want):
			ok = false; print("FAIL: the story tells '%s'" % want)
	var ser := Chronicle.series(sim, "pop")
	print("pop series: %d realms from minute %d, %d points" % [(ser[0] as Array).size(), ser[1], (ser[0][0].values as Array).size() if not (ser[0] as Array).is_empty() else 0])
	if sim.get_feature("statistics") != null and (ser[0] as Array).size() != sim.players.size(): ok = false; print("FAIL: series per realm")
	# save and load: the notes come back and the story reads the same
	var b := Sim.new()
	var why := b.from_save(sim.to_save())
	if why != "": ok = false; print("FAIL: load ", why)
	var same := true
	for k in sim.players.size():
		if var_to_str(sim.players[k].chron) != var_to_str(b.players[k].chron):
			same = false
	print("notes after load the same: ", same)
	if not same: ok = false; print("FAIL: notes saved")
	if Chronicle.new().story(b, true) != text: ok = false; print("FAIL: the story after load")
	if sim.checksum() != b.checksum(): ok = false; print("FAIL: checksum after load")
	print("chronicle test: ", "ok" if ok else "FAILED")
	sim.dispose(); b.dispose()
	quit()
