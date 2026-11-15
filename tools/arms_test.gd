extends SceneTree
## Build 66: tools and weapons of bronze, iron or steel. Workers take the best tool in store, work at its
## pace, wear it out and take a new one; specialists keep theirs; bronze arms make bronze warriors and
## riflemen need steel; saved and loaded, older saves get iron tools.
## godot --headless --script res://tools/arms_test.gd
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
	sim.new_game("arms", 1, 5, false, 128, false, {"features": Features.default_ids()})
	var me := sim.human()
	var ar := sim.arms
	for i in 10: sim.tick(Sim.TICK)
	check(me.age == 0 and ar.default_tier(me) == SimArms.BRONZE, "a Bronze Age realm's tools from the start are bronze")
	# 1. a newcomer takes the best tool in store
	var at := spot(sim, "woodcutter", me.hq.x + 5, me.hq.y + 3)
	var wc := sim.add_bld("woodcutter", at.x, at.y, me, true, 0)
	sim.build_road(wc.x, wc.y, me.hq.x, me.hq.y, 1)
	ar.add(me, "axes", SimArms.IRON, 1)
	sim.give(me, "axes", 1.0)
	var t0 := sim.time
	while sim.time < t0 + 20.0 and wc.worker == 0:
		sim.tick(Sim.TICK)
	check(wc.worker > 0 and wc.tool_q == SimArms.IRON, "the woodcutter took the iron axe, not a bronze one (%s)" % SimArms.NAMES[wc.tool_q])
	# 2. its pace and how long it lasts
	check(is_equal_approx(ar.tool_cycle(wc, me, 1.0), 1.0), "iron works at the usual pace")
	wc.tool_q = SimArms.BRONZE
	check(is_equal_approx(ar.tool_cycle(wc, me, 1.0), SimArms.TOOL_SPEED[1]) and SimArms.TOOL_SPEED[1] < 1.0 and SimArms.life_of(1) < 1.0, "bronze is slower and wears out sooner")
	wc.tool_q = SimArms.STEEL
	check(ar.tool_cycle(wc, me, 1.0) > 1.0 and SimArms.life_of(3) > 1.0, "steel is faster, and lasts longest")
	# 3. worn out: work on slowly, the toolsmiths are asked for one, and the best in store replaces it
	var tqf = sim.get_feature("tool_quality")
	check(tqf != null, "the tool-quality feature is on (wear and craft)")
	tqf.held[wc.id] = [-1.0, 0.0]
	check(ar.worn(wc) and is_equal_approx(ar.tool_cycle(wc, me, 1.0), 1.0), "a worn-out tool: its metal no longer helps")
	sim.take(me, "axes", float(me.stock.get("axes", 0.0)))
	sim.staffing(me)
	check(int(me.tool_wait.get("axes", 0)) >= 1 and sim.wanted_tool(me) == "axes", "and the toolsmith is asked for an axe")
	ar.add(me, "axes", SimArms.STEEL, 1)
	sim.give(me, "axes", 1.0)
	tqf.held[wc.id] = [1.0, 0.5]
	tqf.on_cycle(me, wc)
	var h: Array = tqf.held[wc.id]
	check(wc.tool_q == SimArms.STEEL and float(h[1]) > tqf.q_value(tqf.LIFE, float(h[0])) * 1.2, "worn out with a steel axe in store: he takes it, and it lasts longer (%d cycles)" % roundi(float(h[1])))
	var lines: PackedStringArray = tqf.building_lines(wc)
	check(" ".join(lines).contains("steel[/color] axes") and " ".join(lines).contains("res_axes_steel.png"), "the panel says so: %s" % (lines[0] if lines.size() > 0 else ""))
	# 4. smiths make tools of their metal
	check(ar.maker_tier("bronze_smith") == 1 and ar.maker_tier("toolsmith") == 2 and ar.maker_tier("machine_works") == 3, "bronze smith, toolsmith, machine works: bronze, iron, steel")
	check(GameData.bld.machine_works["in"].has("steel"), "the machine works works steel")
	# 5. a specialist keeps his tool
	wc.wxp = float(Sim.WORKER_XP[Sim.SPECIALIST]) + 1.0
	var key := sim.people.spec_key(wc)
	sim._release_worker(me, wc)
	check((me.spec.get(key, []) as Array).size() == (me.spec_tool.get(key, []) as Array).size() and (me.spec_tool[key] as Array).size() >= 1, "an idle specialist keeps his tool")
	sim._hire_worker(me, wc)
	check(wc.tool_q == SimArms.STEEL, "and has it again when he is hired (%s)" % SimArms.NAMES[wc.tool_q])
	# 6. arms: the kind of soldier they make
	check(SimArms.ARM_KIND_MAX[SimArms.BRONZE] == 0 and SimArms.ARM_KIND_MAX[SimArms.IRON] == 5 and SimArms.ARM_KIND_MAX[SimArms.STEEL] == 6, "bronze arms: bronze warriors; iron: up to musketeers; rifles: steel")
	var bk_at := spot(sim, "barracks", me.hq.x - 6, me.hq.y + 4)
	var bk := sim.add_bld("barracks", bk_at.x, bk_at.y, me, true, 0)
	me.age = 2           # Early Medieval: spearmen
	me.artisan += 6
	me.tq["weapons"] = [0, 3, 0, 0]
	var rm0 := (sim.rmix_of(me) as Array).duplicate()
	sim.production.finish_prod(bk, me)
	var rm1: Array = sim.rmix_of(me)
	check(int(rm1[0]) == int(rm0[0]) + 1, "Early Medieval, but bronze arms: a bronze warrior (%s)" % Sim.mix_text(rm1))
	me.tq["weapons"] = [0, 0, 2, 0]
	sim.production.finish_prod(bk, me)
	check(int(sim.rmix_of(me)[2]) >= 1, "with iron arms: a spearman")
	me.age = 6
	me.tq["weapons"] = [0, 0, 2, 0]
	sim.production.finish_prod(bk, me)
	check(int(sim.rmix_of(me)[5]) >= 1 and int(sim.rmix_of(me)[6]) == 0, "Industrial with iron arms: a musketeer, not a rifleman")
	me.tq["weapons"] = [0, 0, 0, 2]
	sim.production.finish_prod(bk, me)
	check(int(sim.rmix_of(me)[6]) >= 1, "with steel arms: a rifleman")
	me.arm_q = SimArms.BRONZE
	var wb: float = sim.military._wear(1)
	me.arm_q = SimArms.STEEL
	check(wb > sim.military._wear(1), "bronze weapons wear out sooner in a fight than steel")
	me.age = 0
	# 7. the counts follow the goods there are
	me.tq["axes"] = [0, 5, 5, 0]
	sim.take(me, "axes", float(me.stock.get("axes", 0.0)))
	sim.give(me, "axes", 3.0)
	ar.trim(me)
	var ax: Array = me.tq["axes"]
	check(int(ax[1]) + int(ax[2]) + int(ax[3]) <= 3 and int(ax[2]) >= 3 - int(ax[1]) and int(ax[1]) == 0, "losses take the poorest first (%s)" % str(ax))
	# 8. saved and loaded
	for i in 30: sim.tick(Sim.TICK)
	var s1 := Sim.new()
	s1.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	check(s1.by_id[wc.id].tool_q == wc.tool_q and s1.human().tq.hash() == me.tq.hash(), "tools and counts are saved")
	var s2 := Sim.new()
	s2.from_save(bytes_to_var(var_to_bytes(s1.to_save())))
	for i in int(30.0 / Sim.TICK):
		s1.tick(Sim.TICK)
		s2.tick(Sim.TICK)
	check(s1.checksum() == s2.checksum(), "the loaded game goes on the same (30 s)")
	# 9. a save from before: its workers have iron tools
	var d := sim.to_save()
	d["version"] = 4
	for bd in d.blds:
		bd.erase("tool_q")
	var s3 := Sim.new()
	s3.from_save(d)
	check(s3.by_id[wc.id].tool_q == SimArms.IRON, "an older save: workers have iron tools")
	# 10. soldiers' arms by metal (build 67): counted as armed, kept to the soldiers there are
	me.arm_n = [0, 0, 0, 0]
	ar.fit_arms(me)
	var ns := sim.soldiers(me)
	check(int(me.arm_n[1]) + int(me.arm_n[2]) + int(me.arm_n[3]) == ns, "every soldier is counted with his arms' metal (%s of %d)" % [ar.arms_text(me), ns])
	me.arm_n = [0, 2, 0, ns]
	ar.fit_arms(me)
	check(int(me.arm_n[1]) + int(me.arm_n[2]) + int(me.arm_n[3]) == ns and int(me.arm_n[3]) >= int(me.arm_n[1]), "losses fall on each metal in proportion (%s)" % ar.arms_text(me))
	ar.rearmed(me, SimArms.STEEL)
	check(int(me.arm_n[3]) >= 1 and SimArms.icon_id("axes", SimArms.STEEL) == "res_axes_steel" and SimArms.icon_id("axes", SimArms.IRON) == "res_axes" and SimArms.icon_id("bread", SimArms.STEEL) == "res_bread", "pictures by metal for tools and weapons only")
	check(ResourceLoader.exists("res://textures/res_weapons_bronze.png") and ResourceLoader.exists("res://textures/metal_steel.png"), "the metal pictures are there")
	# 11. build 68: the order metals are used in, limits by metal, metal left for the other smiths
	sim.take(me, "axes", float(me.stock.get("axes", 0.0)))
	me.tq["axes"] = [0, 0, 0, 0]
	sim.give(me, "axes", 4.0); ar.add(me, "axes", SimArms.STEEL, 2); ar.add(me, "axes", SimArms.BRONZE, 2)
	check(ar.by_metal(me, "axes") == [0, 2, 0, 2], "axes by metal in store: %s" % str(ar.by_metal(me, "axes")))
	check(ar.best(me, "axes") == SimArms.STEEL, "by default the best metal is used first")
	me.metal_order["tools"] = [1, 2, 3]
	check(ar.take_best(me, "axes") == SimArms.BRONZE and ar.best(me, "pickaxes") >= 1, "poorest first: a bronze axe is taken, the steel ones kept")
	me.metal_order["tools"] = [3, 2, 1]
	me.metal_lim["tools"] = [-1, -1, -1, 2]
	check(not ar.under_limit(me, "axes", SimArms.STEEL) and ar.under_limit(me, "axes", SimArms.IRON) and ar.under_limit(me, "saws", SimArms.STEEL), "at most 2 steel axes: steel axes at their limit, iron axes and steel saws not")
	me.tool_wait = {"axes": 3}
	check(sim.wanted_tool(me, SimArms.STEEL) != "axes" and sim.wanted_tool(me, SimArms.IRON) == "axes", "the machine works makes another tool, the toolsmith the axes (%s, %s)" % [sim.wanted_tool(me, SimArms.STEEL), sim.wanted_tool(me, SimArms.IRON)])
	me.tool_wait = {}
	me.metal_lim["tools"] = [-1, -1, -1, -1]
	var ws_at := spot(sim, "weaponsmith", me.hq.x + 7, me.hq.y - 5)
	var ws := sim.add_bld("weaponsmith", ws_at.x, ws_at.y, me, true, 0)
	me.tq["weapons"] = [0, 0, 0, 0]
	sim.take(me, "weapons", float(me.stock.get("weapons", 0.0)))
	sim.give(me, "weapons", 3.0); ar.add(me, "weapons", SimArms.IRON, 3)
	me.metal_lim["weapons"] = [-1, -1, 3, -1]
	check(ar.smith_check(ws, me).begins_with("Limit reached"), "at most 3 iron weapons: the weaponsmith waits (%s)" % ar.smith_check(ws, me))
	me.metal_lim["weapons"] = [-1, -1, -1, -1]
	sim.give(me, "iron", 5.0)
	me.metal_keep["weapons"] = {"iron": int(me.stock.get("iron", 0.0)) + 5}
	check(ar.smith_check(ws, me).begins_with("Leaving iron"), "iron kept for the tools: the weaponsmith waits (%s)" % ar.smith_check(ws, me))
	me.metal_keep["weapons"] = {}
	check(ar.smith_check(ws, me) == "", "no limits: he works")
	var s4 := Sim.new()
	me.metal_order["weapons"] = [2, 3, 1]
	s4.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	check(s4.human().metal_order.get("weapons", []) == [2, 3, 1], "the settings are saved")
	print("ARMS TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
