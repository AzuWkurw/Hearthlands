extends SceneTree
## Farms sow a chosen crop; seeds come from research; crops keep their seasons:
## godot --headless --script res://tools/crop_test.gd

func _init() -> void:
	GameData.ensure()
	var ok := true
	var sim := Sim.new()
	sim.new_game("crops", 1, 4, true)
	var me := sim.human()
	var seasons = sim.get_feature("seasons")
	if seasons == null:
		print("FAIL: no seasons feature"); quit(1); return
	var farm: Sim.Bld = null
	for b: Sim.Bld in sim.blds:
		if b.p == 1 and b.ty == "farm": farm = b
	if farm == null:
		farm = sim.add_bld("farm", me.hq.x + 4, me.hq.y + 3, me, true, 0)
	# seeds locked until studied
	print("vegetables known at start: %s; rye: %s" % [Crops.known(sim, me, "vegetables"), Crops.known(sim, me, "rye")])
	if Crops.known(sim, me, "vegetables") or not Crops.known(sim, me, "wheat"):
		print("FAIL: seeds should start locked (wheat open)"); ok = false
	sim.complete_tech(me, "heavy_plough")
	sim.complete_tech(me, "open_fields")
	if not Crops.known(sim, me, "vegetables") or not Crops.known(sim, me, "rye"):
		print("FAIL: research did not unlock the seeds"); ok = false
	farm.crop = "vegetables"
	var out := Crops.out_of(sim, farm)
	print("vegetable farm makes %s" % str(out))
	if not out.has("vegetables"): ok = false
	# winter: vegetables stop, rye grows; rotation sows rye
	var winter := false
	for k in 4:
		var s := k
		print("season %d: vegetables '%s'  rye '%s'" % [s, "grows" if Crops.grows("vegetables", s) else "off", "grows" if Crops.grows("rye", s) else "off"])
	if Crops.grows("vegetables", 3) or not Crops.grows("rye", 3) or Crops.grows("hops", 0):
		print("FAIL: wrong seasons"); ok = false
	# run the game into winter and check the farm stands idle, then rotates
	while seasons.season() != 3 and sim.time < 1300.0:
		sim.tick(Sim.TICK)
	for i in 30: sim.tick(Sim.TICK)
	var why := Crops.block(sim, farm)
	print("in winter the vegetable farm says: '%s' (msg '%s')" % [why, farm.msg])
	if not why.begins_with("Out of season"): ok = false
	sim.complete_tech(me, "three_field")
	farm.rotate = true
	print("with rotation it sows %s, block '%s'" % [Crops.now(sim, farm), Crops.block(sim, farm)])
	if Crops.now(sim, farm) != "rye" or Crops.block(sim, farm) != "": ok = false
	# rivals change crops by the season too
	var rival_crops := {}
	for b: Sim.Bld in sim.blds:
		if b.p != 1 and b.ty == "farm": rival_crops[Crops.now(sim, b)] = true
	print("rival farms sow now: %s" % str(rival_crops.keys()))
	print("vegetables made so far: %d" % int(me.stock.get("vegetables", 0.0)))
	# fields in a real game: every realm played by the computer for 25 minutes
	var g := Sim.new()
	g.new_game("fields", 3, 6, true)
	var hu := g.human()
	hu.ai = true; hu.skill = 6; hu.pers = "balanced"; hu.prod = 1.0; hu.think = 3.0; hu.max_b = 2
	var harvests := 0
	var sown_max := 0
	var bad := 0
	var prev := {}
	var t_real := Time.get_ticks_msec()
	var last_s := 0
	while g.time < 1500.0:
		g.tick(Sim.TICK)
		if int(g.time) != last_s:
			last_s = int(g.time)
			for i in prev:
				if float(prev[i]) >= Crops.GROW and (not g.fields.has(i) or float(g.fields[i][2]) < Crops.GROW):
					harvests += 1
			prev = {}
			for i in g.fields:
				prev[i] = float(g.fields[i][2])
			if last_s % 300 == 0:
				print("  %d min: %d fields, %d harvests, %d s real" % [last_s / 60, g.fields.size(), harvests, (Time.get_ticks_msec() - t_real) / 1000])
		if int(g.time * 10.0) % 600 == 0:
			sown_max = maxi(sown_max, g.fields.size())
			for i in g.fields:
				var fb: Sim.Bld = g.by_id.get(int(g.fields[i][0]))
				if fb == null or g.bmap[i] != 0 or g.road[i] != 0 or Vector2(i % g.w - fb.x, i / g.w - fb.y).length() > 6.0:
					bad += 1
	var farms := 0
	for b2: Sim.Bld in g.blds:
		if b2.ty == "farm" and b2.state == "ready": farms += 1
	print("real game, 25 min: %d farms, up to %d fields at once, %d fields harvested, %d bad fields" % [farms, sown_max, harvests, bad])
	if farms > 0 and (sown_max == 0 or harvests == 0): print("FAIL: farms do not sow or harvest fields"); ok = false
	if bad > 0: print("FAIL: fields under roads or buildings, or far from their farm"); ok = false
	print("CROP TEST: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
