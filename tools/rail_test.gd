extends SceneTree
## Build 64: steam and rails. Track laid between two stations, a train carrying goods for coal, steam
## engines in workshops (faster for coal, smoke near homes), track torn up by an enemy column, saved and
## loaded. godot --headless --script res://tools/rail_test.gd
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


func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("railways", 1, 5, false, 128, false, {"start_goods": 4.0, "features": Features.default_ids()})
	var me := sim.human()
	for i in 10: sim.tick(Sim.TICK)
	for y in range(maxi(0, me.hq.y - 26), mini(sim.h, me.hq.y + 27)):
		for x in range(maxi(0, me.hq.x - 26), mini(sim.w, me.hq.x + 27)):
			if sim.owner[sim.idx(x, y)] == 0: sim.owner[sim.idx(x, y)] = 1
	sim.net_dirty(1)
	var rw := sim.railway
	check(rw.can_lay(1) != "", "no track before Railways is studied")
	me.techs["railways"] = true
	me.techs["steam_engine"] = true
	# 1. two stations and the track between them
	var a_at := spot(sim, "railway_station", me.hq.x - 12, me.hq.y + 2)
	var b_at := spot(sim, "railway_station", me.hq.x + 12, me.hq.y + 2)
	var a := sim.add_bld("railway_station", a_at.x, a_at.y, me, true)
	var b := sim.add_bld("railway_station", b_at.x, b_at.y, me, true)
	for i in 12: sim.tick(Sim.TICK)
	sim.take(me, "rails", float(me.stock.get("rails", 0.0)))
	check(rw.build(a.x, a.y, b.x, b.y, 1).begins_with("This track needs"), "track needs rails in store")
	sim.give(me, "rails", 120.0)
	var path := rw.find_path(a.x, a.y, b.x, b.y, 1)
	var why := rw.build(a.x, a.y, b.x, b.y, 1)
	check(why == "" and rw.station_piece(a) >= 0 and rw.station_piece(a) == rw.station_piece(b), "track laid from one station to the other (%d tiles; %s)" % [path.size(), why])
	check(int(me.stock.get("rails", 0.0)) <= 120 - path.size() + 2, "one rail a tile (%d left)" % int(me.stock.get("rails", 0.0)))
	check(rw.line_path(a, b).size() >= 2, "a train can run between them")
	# 2. a train: goods from the station with plenty to the other, 1 coal a trip
	sim.logistics.store_add(a, me, "planks", 50.0)
	var b0 := float(b.inv.get("planks", 0.0))
	sim.give(me, "coal", 10.0)
	var c0 := float(me.stock.get("coal", 0.0))
	var trips := 0
	var t_end := sim.time + 8.0
	while sim.time < t_end:
		sim.tick(Sim.TICK)
		for t in sim.trips:
			if t.kind == "train": trips += 1
	check(trips == 0, "no locomotive, no train")
	sim.give(me, "locomotive", 1.0)
	var went := false
	t_end = sim.time + 120.0
	while sim.time < t_end:
		sim.tick(Sim.TICK)
		for t in sim.trips:
			if t.kind == "train": went = true
		if went and float(b.inv.get("planks", 0.0)) > b0 + 5.0:
			break
	check(went, "with a locomotive a train sets out")
	check(float(b.inv.get("planks", 0.0)) >= b0 + 10.0, "and brings planks to the other station (%d there now, carried %d)" % [int(b.inv.get("planks", 0.0)), b.carried])
	check(float(me.stock.get("coal", 0.0)) <= c0 - 1.0 + 0.01, "it burnt coal (%.0f left of %.0f)" % [float(me.stock.get("coal", 0.0)), c0])
	# 3. a steam engine
	var sm_at := spot(sim, "sawmill", me.hq.x, me.hq.y + 8)
	var sm := sim.add_bld("sawmill", sm_at.x, sm_at.y, me, true)
	var hs_at := spot(sim, "house", sm_at.x + 3, sm_at.y)
	var hs := sim.add_bld("house", hs_at.x, hs_at.y, me, true)
	for i in 12: sim.tick(Sim.TICK)
	check(rw.steam_why(sm) == "" or rw.steam_why(sm).begins_with("Not enough"), "a sawmill can take a steam engine (%s)" % rw.steam_why(sm))
	sim.give(me, "steel", 4.0); sim.give(me, "iron", 8.0); sim.give(me, "bricks", 10.0)
	var st0 := float(me.stock.get("steel", 0.0))
	check(rw.fit_steam(sm) == "" and sm.steam and float(me.stock.get("steel", 0.0)) == st0 - 2.0, "fitted: 2 steel, 4 iron, 6 bricks from the stores")
	check(not rw.steam_on(sm), "it takes a while to fit")
	sm.steam_at = sim.time
	check(rw.steam_why(sm) != "" and rw.fit_steam(sm) != "", "not twice")
	sim.give(me, "coal", 5.0)
	var cc := float(me.stock.get("coal", 0.0))
	var f1 := rw.steam_cycle(sm, me)
	var f2 := rw.steam_cycle(sm, me)
	check(is_equal_approx(f1, 1.0 + SimRail.STEAM) and is_equal_approx(f2, 1.0 + SimRail.STEAM) and is_equal_approx(float(me.stock.get("coal", 0.0)), cc - 1.0), "two cycles %.0f%% faster for one coal" % (SimRail.STEAM * 100))
	sim.take(me, "coal", float(me.stock.get("coal", 0.0)))
	check(is_equal_approx(rw.steam_cycle(sm, me), 1.0), "no coal: the old speed")
	check(not rw.steam_why(sim.add_bld("woodcutter", sm_at.x + 6, sm_at.y + 6, me, true)).is_empty(), "a woodcutter takes no steam engine")
	var ct = sim.get_feature("contentment")
	if ct != null:
		for i in int(6.0 / Sim.TICK): sim.tick(Sim.TICK)
		check(ct.smoke_share(me) > 0.0, "the house beside it is in its smoke (%d%% of homes)" % roundi(ct.smoke_share(me) * 100))
	# 4. an enemy column marching over the line tears it up
	var mid: int = path[path.size() / 2]
	var col := Sim.Attack.new()
	col.p = 2; col.n = 5; col.t0 = sim.time; col.t1 = sim.time + 100.0
	col.from = Vector2(mid % sim.w, mid / sim.w); col.to = col.from
	if sim.players.size() < 2:
		check(false, "a rival")
	else:
		Diplomacy.declare_war(sim, 1, 2)
		sim.attacks.append(col)
		var n0 := 0
		for i in sim.w * sim.h:
			if sim.rail[i] != 0: n0 += 1
		rw.second()
		var n1 := 0
		for i in sim.w * sim.h:
			if sim.rail[i] != 0: n1 += 1
		sim.attacks.erase(col)
		check(n1 < n0 and rw.station_piece(a) != rw.station_piece(b), "an enemy column tore up %d tiles: the stations are cut apart" % (n0 - n1))
		# laid again
		sim.give(me, "rails", 20.0)
		check(rw.build(a.x, a.y, b.x, b.y, 1) == "" and rw.station_piece(a) == rw.station_piece(b), "and laid again")
	# 5. taking track up
	var tk: int = rw.line_path(a, b)[3]
	var r0 := float(me.stock.get("rails", 0.0))
	var gone := rw.remove(tk % sim.w, tk / sim.w, 1)
	check(gone > 0 and float(me.stock.get("rails", 0.0)) >= r0 + gone / 2 - 1, "track taken up: %d tiles, half the rails back" % gone)
	rw.build(a.x, a.y, b.x, b.y, 1)
	# 6. saved and loaded, and goes on the same
	for i in int(3.0 / Sim.TICK): sim.tick(Sim.TICK)
	# (the techs given by hand above get their earlier techs on loading: go on from a loaded game)
	var s1 := Sim.new()
	s1.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	sim = s1
	for i in int(5.0 / Sim.TICK): sim.tick(Sim.TICK)
	var s2 := Sim.new()
	s2.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	check(s2.rail == sim.rail and s2.by_id[sm.id].steam, "rails and steam engines are saved")
	for i in int(40.0 / Sim.TICK):
		sim.tick(Sim.TICK)
		s2.tick(Sim.TICK)
	var same := sim.checksum() == s2.checksum()
	if not same:
		var d1 := sim.to_save()
		var d2 := s2.to_save()
		for k in d1:
			if var_to_str(d1[k]) != var_to_str(d2.get(k)):
				print("   differs: ", k)
				if k == "blds":
					for bi in d1[k].size():
						var x1: Dictionary = d1[k][bi]
						var x2: Dictionary = d2[k][bi]
						for kk in x1:
							if var_to_str(x1[kk]) != var_to_str(x2.get(kk)):
								print("     bld %s %s: %s vs %s" % [x1.get("ty"), kk, str(x1[kk]).left(80), str(x2.get(kk)).left(80)])
				if k == "players":
					for pi in d1[k].size():
						for kk in d1[k][pi]:
							if var_to_str(d1[k][pi][kk]) != var_to_str(d2[k][pi].get(kk)):
								print("     player %d %s: %s vs %s" % [pi, kk, str(d1[k][pi][kk]).left(100), str(d2[k][pi].get(kk)).left(100)])
	check(same, "the loaded game goes on the same (40 s)")
	print("RAIL TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
