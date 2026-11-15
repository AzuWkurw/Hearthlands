extends SceneTree
## Build 65: the Bronze Age, the first age of every game. Tin on the map, bronze from copper and tin
## ore with charcoal, tools and weapons of bronze, bronze warriors, Iron working opening the Roman age,
## a save from before build 65 loading one age on, and the pictures of the new age.
## godot --headless --script res://tools/bronze_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


func spot(sim: Sim, ty: String, cx: int, cy: int) -> Vector2i:
	for r in range(0, 25):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and sim.can_place(ty, cx + dx, cy + dy, 1, 0) == "":
					return Vector2i(cx + dx, cy + dy)
	return Vector2i(-1, -1)


func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("bronze", 1, 5, false, 128, false, {"features": Features.default_ids()})
	var me := sim.human()
	for i in 10: sim.tick(Sim.TICK)
	# 1. every game starts in the Bronze Age
	check(GameData.ages.size() == 7 and GameData.age_name(0) == "Bronze", "seven ages, the first the Bronze Age (%s)" % ", ".join(GameData.ages))
	check(me.age == 0 and sim.players[1].age == 0, "every realm starts in it")
	check(float(me.stock.get("bronze", 0.0)) > 0.0 and float(me.stock.get("iron", 0.0)) == 0.0, "the stores hold bronze, not iron")
	check(Sim.soldier_name(me.age) == "bronze warrior", "the barracks train bronze warriors")
	var open := []
	var shut := []
	for ty in ["woodcutter", "sawmill", "quarry", "farm", "copper_mine", "tin_mine", "charcoal_burner", "bronze_foundry", "bronze_smith", "bronze_weaponsmith", "scriptorium", "school", "barracks", "hut"]:
		var d: Dictionary = GameData.bld[ty]
		if d.has("tech") and not me.techs.has(d.tech): shut.append(ty)
	for ty in ["iron_mine", "coal_mine", "iron_smelter", "toolsmith", "weaponsmith", "mint", "tower", "market", "harbour", "brickworks", "bowyer"]:
		var d: Dictionary = GameData.bld[ty]
		if not d.has("tech") or me.techs.has(d.tech): open.append(ty)
	check(shut.is_empty(), "the Bronze Age buildings are there from the start %s" % str(shut))
	check(open.is_empty(), "iron, coal, towers, markets, harbours, kilns and bows must be studied first %s" % str(open))
	var bronze_techs := 0
	for id in GameData.techs:
		if int(GameData.techs[id].get("age", -1)) == 0: bronze_techs += 1
	check(bronze_techs >= 10 and not sim.research.tech_available(me, "iron_working"), "%d Bronze techs; Iron working not yet open" % bronze_techs)
	# 2. tin on the map: near every start, and a brush for it in the editor
	var tin_near := 0
	for p in sim.players:
		var n := 0
		for y in range(maxi(0, p.start.y - 18), mini(sim.h, p.start.y + 19)):
			for x in range(maxi(0, p.start.x - 18), mini(sim.w, p.start.x + 19)):
				if sim.ore[sim.idx(x, y)] == 8: n += 1
		if n > 0: tin_near += 1
	check(tin_near == sim.players.size(), "tin near every start (%d of %d)" % [tin_near, sim.players.size()])
	check(GameData.ORE_NAMES.get(8, "") == "tin" and int(GameData.bld.tin_mine.mine) == 8, "tin is ore 8; the tin mine digs it")
	var brush := false
	for b in UiEditor.BRUSHES:
		if String(b[0]) == "Tin" and String(b[1]) == "ore" and int(b[2]) == 8: brush = true
	check(brush and UiEditor._brush_order().size() == UiEditor.BRUSHES.size(), "the map editor has a Tin brush")
	var fair := EditorTools.fairness(sim, [me.start], 18)
	check(int(fair[0].get("tin", 0)) > 0, "and counts tin in its fairness check (%d tiles)" % int(fair[0].get("tin", 0)))
	# 3. bronze: copper and tin ore with charcoal at the foundry
	for y in range(maxi(0, me.hq.y - 26), mini(sim.h, me.hq.y + 27)):
		for x in range(maxi(0, me.hq.x - 26), mini(sim.w, me.hq.x + 27)):
			if sim.owner[sim.idx(x, y)] == 0: sim.owner[sim.idx(x, y)] = 1
	sim.net_dirty(1)
	var fd_at := spot(sim, "bronze_foundry", me.hq.x + 6, me.hq.y + 2)
	var fd := sim.add_bld("bronze_foundry", fd_at.x, fd_at.y, me, true, 0)
	var ws_at := spot(sim, "bronze_weaponsmith", me.hq.x - 6, me.hq.y + 2)
	var ws := sim.add_bld("bronze_weaponsmith", ws_at.x, ws_at.y, me, true, 0)
	for b in [fd, ws]:
		print("    road: '%s'" % sim.build_road(b.x, b.y, me.hq.x, me.hq.y, 1))
	me.artisan += 4
	for i in 12: sim.tick(Sim.TICK)
	sim.take(me, "bronze", float(me.stock.get("bronze", 0.0)))
	sim.give(me, "ore_copper", 12.0); sim.give(me, "ore_tin", 6.0); sim.give(me, "charcoal", 12.0)
	var w0 := float(me.stock.get("weapons", 0.0))
	var t_end := sim.time + 240.0
	while sim.time < t_end:
		sim.tick(Sim.TICK)
		if float(me.stock.get("weapons", 0.0)) > w0 + 0.5:
			break
	check(float(me.stock.get("ore_tin", 0.0)) < 6.0 and float(me.stock.get("ore_copper", 0.0)) < 12.0, "the foundry melts copper and tin ore (%.0f copper, %.0f tin left)" % [float(me.stock.get("ore_copper", 0.0)), float(me.stock.get("ore_tin", 0.0))])
	check(float(me.stock.get("weapons", 0.0)) > w0, "with no bronze in store but the foundry's: bronze weapons from the bronze weaponsmith (%.0f weapons now, %.0f before)" % [float(me.stock.get("weapons", 0.0)), w0])
	check(GameData.bld.bronze_smith.has("makes_tools") and GameData.bld.bronze_smith["in"].has("bronze"), "the bronze smith makes tools of bronze")
	# 4. the gate: six Bronze techs open Iron working, which opens the Roman age
	var n := 0
	for id in GameData.techs:
		var t: Dictionary = GameData.techs[id]
		if int(t.get("age", -1)) == 0 and n < 5 and (t.get("requires", []) as Array).is_empty():
			sim.research.complete_tech(me, id)
			n += 1
	check(sim.research.tech_available(me, "iron_working"), "after %d Bronze techs Iron working can be studied" % n)
	sim.research.complete_tech(me, "iron_working")
	check(me.age == 1 and GameData.age_name(me.age) == "Roman", "Iron working opens the Roman age")
	check(me.techs.has(String(GameData.bld.iron_mine.tech)) and me.techs.has(String(GameData.bld.toolsmith.tech)), "iron mines and toolsmiths now")
	check(Sim.soldier_name(me.age) == "legionary", "the barracks train legionaries")
	check(sim.missing_age_bonus(me) == 1 and not sim.age_bonus_options(1).is_empty(), "the Roman age has its bonus to pick")
	# 5. soldiers of seven kinds
	var m := Sim.mix_fix([], 3, 0)
	check(m.size() == Sim.KINDS and int(m[0]) == 3 and Sim.mix_text(m) == "3 bronze warriors", "a mix has seven kinds (%s)" % Sim.mix_text(m))
	check(SimMilitary.ADV.size() == Sim.KINDS and (SimMilitary.ADV[1] as Array)[0] == 1, "legionaries beat bronze warriors")
	check(SimMilitary.GUNS.has(5) and SimMilitary.GUNS.has(6) and not SimMilitary.GUNS.has(4), "musketeers and riflemen still carry the guns")
	# 6. a save from before build 65 loads one age on
	me.hq.era = 1        # (built in Roman times: 0 in an old save)
	var d := sim.to_save()
	var old := d.duplicate(true)
	old["version"] = 3
	for bd in old.blds:
		if int(bd.era) >= 0: bd["era"] = int(bd.era) - 1
		if float(bd.get("sera", -1.0)) >= 1.0: bd["sera"] = float(bd.sera) - 1.0
		var gm: Array = bd.get("gmix", [])
		if gm.size() == 7:
			gm.pop_front(); bd["gmix"] = gm
	var pd: Dictionary = old.players[0]
	for id in pd.techs.keys():
		if int(GameData.techs.get(id, {}).get("age", -1)) == 0 or id == "iron_working":
			pd.techs.erase(id)
	var rm: Array = pd.get("rmix", [])
	rm = rm.duplicate()
	if rm.size() == 7: rm.pop_front()
	while rm.size() < 6: rm.append(0)
	for k in 6: rm[k] = 0
	rm[0] = 2           # two legionaries in the old numbering
	pd["rmix"] = rm
	pd["res_era"] = 0.0
	pd["age_bonus"] = {}
	pd["reserve"] = 2
	var s3 := Sim.new()
	var why := s3.from_save(old)
	var me3 := s3.human()
	check(why == "" and me3.techs.has("iron_working") and me3.techs.has("herding") and me3.age == 1, "an old save gets the Bronze studies and stays in its age (%s)" % GameData.age_name(me3.age))
	var hq3: Sim.Bld = me3.hq
	check(hq3.era == me.hq.era, "its buildings keep their look (%s)" % GameData.age_name(hq3.era))
	check(int(s3.rmix_of(me3)[1]) == 2 and int(s3.rmix_of(me3)[0]) == 0, "its legionaries stay legionaries (%s)" % Sim.mix_text(s3.rmix_of(me3)))
	# 7. the pictures of the new age
	var miss := []
	for id in ["ore_8", "bld_house_e0", "bld_farm_e0", "bld_hq_e0", "bld_tin_mine_e0", "bld_bronze_foundry_e0", "bld_bronze_smith_e0",
			"bld_bronze_weaponsmith_e0", "bld_bronze_armorer_e0", "bld_house_e6", "bld_bronze_foundry_e6", "unit_soldier_e0", "unit_soldier_e6",
			"res_bronze", "res_ore_tin", "tech_iron_working", "tech_herding"]:
		if not ResourceLoader.exists("res://textures/%s.png" % id): miss.append(id)
	check(miss.is_empty(), "the Bronze Age pictures are there %s" % str(miss))
	var e0 := Tex.bld_era_tex("bld_house", 0)
	var e2 := Tex.bld_era_tex("bld_house", 2)
	check(e0 != null and e2 != null and e0 != e2 and e0.get_image().get_pixel(e0.get_width() / 2, e0.get_height() * 3 / 4) != e2.get_image().get_pixel(e2.get_width() / 2, e2.get_height() * 3 / 4), "a house looks different in the Bronze Age")
	# 8. saved and loaded, it goes on the same
	var s1 := Sim.new()
	s1.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	sim = s1
	for i in int(3.0 / Sim.TICK): sim.tick(Sim.TICK)
	var s2 := Sim.new()
	s2.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	for i in int(30.0 / Sim.TICK):
		sim.tick(Sim.TICK)
		s2.tick(Sim.TICK)
	check(sim.checksum() == s2.checksum(), "the loaded game goes on the same (30 s)")
	print("BRONZE TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
