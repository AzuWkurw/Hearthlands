extends SceneTree
## Realm laws: godot --headless --script res://tools/laws_test.gd
## Usual laws change nothing; each option moves what it should; laws wait between changes; rivals pick
## laws by personality; laws and tolls survive a save and load.

func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("lawful", 3, 4, true)
	var me := sim.human()
	var lw = sim.get_feature("laws")
	var ok := lw != null
	if not ok:
		print("FAIL: the laws feature is not on in a new game")
		print("LAWS TEST: FAIL")
		quit()
		return
	for i in 30: sim.tick(Sim.TICK)
	# usual laws: no effect at all
	var b: Sim.Bld = null
	for x: Sim.Bld in sim.realm_blds(me):
		if String(x.def.get("worker", "")) == "peasant":
			b = x
			break
	print("usual: tax ", lw.tax_factor(me), ", food ", lw.food_factor(me), ", carry ", lw.carry_factor(me), ", shift ", lw.mood_shift(me), ", speed ", lw.speed_bonus(me, b) if b != null else 0.0)
	if lw.tax_factor(me) != 1.0 or lw.food_factor(me) != 1.0 or lw.carry_factor(me) != 1.0 or lw.mood_shift(me) != 0.0:
		ok = false; print("FAIL: usual laws should change nothing")
	# heavy taxes: more tax, nobles unhappy
	if lw.set_law(me, "tax", "heavy") != "": ok = false; print("FAIL: could not set heavy taxes")
	print("heavy taxes: tax ", lw.tax_factor(me), ", nobles ", lw.class_delta(me, "noble"))
	if lw.tax_factor(me) <= 1.0 or lw.class_delta(me, "noble") >= 0.0: ok = false; print("FAIL: heavy taxes")
	# a law waits before it can change again
	var why: String = lw.set_law(me, "tax", "light")
	print("change again at once: '", why, "'")
	if why == "" or lw.law_of(me, "tax") != "heavy": ok = false; print("FAIL: should wait")
	# long working day: faster, peasants less content
	lw.set_law(me, "workday", "long")
	if b != null:
		print("long day: speed ", lw.speed_bonus(me, b), ", peasants ", lw.class_delta(me, "peasant"))
		if lw.class_delta(me, "peasant") >= 0.0: ok = false; print("FAIL: long day should displease peasants")
	lw.set_law(me, "rations", "generous")
	print("generous rations: food ", lw.food_factor(me))
	if lw.food_factor(me) <= 1.0: ok = false; print("FAIL: generous rations should eat more")
	lw.set_law(me, "tolls", "high")
	print("high tolls: carry ", lw.carry_factor(me))
	if lw.carry_factor(me) >= 1.0: ok = false; print("FAIL: high tolls slow carriers")
	print("class moods: ", lw.moods_text(me))
	print("panel: ", lw.panel_lines(me))
	# rivals: each has the laws of its personality
	for q: Sim.Player in sim.players:
		if q.ai:
			print("rival ", q.id, " (", q.pers, "): ", lw.laws_text(q))
			var want: Dictionary = lw.data().ai.get(q.pers, {})
			for lid in want:
				if lw.law_of(q, lid) != String(want[lid]):
					ok = false; print("FAIL: rival ", q.id, " law ", lid, " is ", lw.law_of(q, lid))
	# play on, then save and load
	var g0 := float(me.stock.get("gold", 0.0))
	var t0 := sim.time
	while sim.time < t0 + 240.0: sim.tick(Sim.TICK)
	print("after 4 minutes: tolls ", lw.tolls.get(me.id, 0), " gold, gold ", g0, " -> ", me.stock.get("gold", 0.0), ", contentment ", sim.get_feature("contentment").mood(me))
	var rival_tolls := 0
	for q: Sim.Player in sim.players:
		rival_tolls += int(lw.tolls.get(q.id, 0)) if q.ai else 0
	print("rivals' tolls: ", rival_tolls, " gold")
	if rival_tolls <= 0: ok = false; print("FAIL: rivals with tolls should take some gold")
	if lw.wait_left(me, "tax") > 0.0: ok = false; print("FAIL: the wait should be over")
	var d = bytes_to_var(var_to_bytes(sim.to_save()))
	var s2 := Sim.new()
	var err := s2.from_save(d)
	var lw2 = s2.get_feature("laws")
	print("loaded: '", err, "' laws ", lw2.laws_text(s2.human()) if lw2 != null else "none")
	if err != "" or lw2 == null or lw2.laws_text(s2.human()) != lw.laws_text(me) or lw2.tax_factor(s2.human()) != lw.tax_factor(me):
		ok = false; print("FAIL: laws after loading")
	for i in 600:
		sim.tick(Sim.TICK); s2.tick(Sim.TICK)
	print("checksums after a minute: ", sim.checksum() == s2.checksum())
	if sim.checksum() != s2.checksum(): ok = false; print("FAIL: loaded game drifts")
	# an old save without laws: the feature can be switched on and everything is usual
	var d2 = bytes_to_var(var_to_bytes(sim.to_save()))
	(d2.opts.features as Array).erase("laws")
	(d2.feature_state as Dictionary).erase("laws")
	var s3 := Sim.new()
	s3.from_save(d2)
	s3.set_feature("laws", true)
	var lw3 = s3.get_feature("laws")
	print("switched on later: human ", lw3.laws_text(s3.human()))
	if lw3.tax_factor(s3.human()) != 1.0: ok = false; print("FAIL: switched on later should start usual")
	print("LAWS TEST: ", "PASS" if ok else "FAIL")
	quit()
