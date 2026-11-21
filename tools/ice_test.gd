extends SceneTree
## River ice (build 78): in deep winter the taiga's rivers freeze, soldiers march over them and ice roads
## cross them without planks; at the thaw the ice roads melt and soldiers on the ice drown. Also a save
## made on the ice goes on the same as the game it came from, through the thaw.
## godot --headless --script res://tools/ice_test.gd

var ok := true


func _check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		ok = false


## A river 3 tiles wide across the whole map, `dy` rows south of the headquarters, all of the map taiga.
func _river(sim: Sim, dy: int) -> int:
	var se = sim.get_feature("seasons")
	var me := sim.human()
	var ry := me.hq.y + dy
	for y in range(ry, ry + 3):
		for x in sim.w:
			var i := y * sim.w + x
			sim.ter[i] = Sim.WATER; sim.deco[i] = 0; sim.road[i] = 0; sim.bmap[i] = 0; sim.plot[i] = 0
	# open land on both banks
	for y in range(me.hq.y + 2, ry):
		for x in range(me.hq.x - 8, me.hq.x + 10):
			if sim.inb(x, y): sim.ter[y * sim.w + x] = Sim.GRASS; sim.deco[y * sim.w + x] = 0
	for y in range(ry + 3, ry + 14):
		for x in range(me.hq.x - 8, me.hq.x + 10):
			if sim.inb(x, y): sim.ter[y * sim.w + x] = Sim.GRASS; sim.deco[y * sim.w + x] = 0
	# painted as taiga, as the map editor does (so a loaded game has it too)
	sim.map_biome = PackedByteArray()
	sim.map_biome.resize(sim.w * sim.h)
	sim.map_biome.fill(se.TAIGA + 1)
	se._make_biomes()
	se._make_freeze()
	return ry


## Jumps the clock to `at` (the marching columns keep their place on the way) and ticks `secs` seconds.
func _jump(sim: Sim, at: float, secs: float) -> void:
	var d := at - sim.time
	for a in sim.attacks:
		a.t0 += d; a.t1 += d
	sim.time = at
	for k in int(secs / Sim.TICK):
		sim.tick(Sim.TICK)


func _diff(x, y, where: String) -> void:
	if var_to_bytes(x) == var_to_bytes(y):
		return
	if x is Dictionary and y is Dictionary:
		for k in x:
			if str(k) == "path_ver": continue
			_diff(x[k], y.get(k), where + "." + str(k))
	elif x is Array and y is Array and x.size() == y.size():
		for i in x.size():
			_diff(x[i], y[i], where + "[%d]" % i)
	else:
		print("   differs ", where, ": ", str(x).substr(0, 160), "  VS  ", str(y).substr(0, 160))


func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	# (no fog: the towers put down by hand here see nothing until a loaded game works it out again)
	sim.new_game("ice", 1, 4, true, 0, true, {"features": Features.default_ids().filter(func(f): return f != "fog")})
	var se = sim.get_feature("seasons")
	_check(se != null, "the seasons are on")
	var me := sim.human()
	var foe := sim.players[1]
	Diplomacy.declare_war(sim, 1, 2)
	var ry := _river(sim, 6)
	var a := sim.add_bld("tower", me.hq.x + 2, ry - 3, me, true, 0)
	a.garrison = 7; a.gmix = [0, 0, 0, 7, 0, 0, 0]
	var d := sim.add_bld("tower", me.hq.x + 2, ry + 8, foe, true, 0)
	d.garrison = 3; d.gmix = [0, 3, 0, 0, 0, 0, 0]
	_check(sim.ice.is_empty(), "no ice in spring")
	_check(sim.military.land_path(a.x, a.y, d.x, d.y).is_empty(), "no way over the open river")

	# deep winter: the river freezes
	var year: float = se.YEAR
	_jump(sim, year * se.ICE_FROM - 2.0, 4.0)
	_check(se.ice_on and not sim.ice.is_empty(), "the river froze a minute into winter")
	_check(sim.icy(sim.idx(a.x, ry + 1)), "the middle of the river is ice")
	var froze := sim.logs.any(func(l): return String(l[1] if l is Array else l).contains("frozen hard"))
	_check(froze, "the freezing is told in the log")
	var way := sim.military.land_path(a.x, a.y, d.x, d.y)
	_check(not way.is_empty() and sim.military.crosses(way, sim.ice), "soldiers can march over the ice")
	_check(not sim.military.ice_trap(way), "early in the winter the crossing is safe")

	# an ice road: no planks, any way round, marked as one
	for y in range(ry - 4, ry + 8):
		for x in range(a.x - 6, a.x + 7):
			if sim.inb(x, y): sim.owner[y * sim.w + x] = 1
	sim._owned_dirty = true
	sim._owned_full = true
	var planks := float(me.stock.get("planks", 0.0))
	var s0 := sim.idx(a.x - 3, ry - 1)
	var g0 := sim.idx(a.x - 3, ry + 3)
	sim.road[s0] = 1
	var why := sim.build_road(a.x - 3, ry - 1, a.x - 3, ry + 3, 1)
	var ice_road := 0
	for y in range(ry, ry + 3):
		if sim.pave[y * sim.w + a.x - 3] == 2 and sim.road[y * sim.w + a.x - 3] == 1: ice_road += 1
	_check(why == "" and ice_road == 3, "a road over the ice is an ice road (%s, %d tiles)" % [why, ice_road])
	_check(absf(float(me.stock.get("planks", 0.0)) - planks) < 0.01, "an ice road takes no planks")
	_check(sim.road[g0] == 1, "the ice road reaches the far bank")

	# an attack over the ice, caught on it by the thaw
	var r := sim.military.launch_attack(a, d, 6)
	_check(r == "", "an attack sets out over the ice ('%s')" % r)
	var col: Sim.Attack = sim.attacks[0] if not sim.attacks.is_empty() else null
	var on_ice := false
	for k in 400:
		sim.tick(Sim.TICK)
		if col == null or not sim.attacks.has(col):
			break
		var pos: Vector2 = sim.military.column_pos(col).round()
		if sim.icy(int(pos.y) * sim.w + int(pos.x)):
			on_ice = true
			break
	_check(on_ice, "the column walks onto the ice")
	# warned before the thaw
	_jump(sim, year - se.ICE_WARN - 0.5, 1.2)
	var warned := sim.logs.any(func(l): return String(l[1] if l is Array else l).contains("thinning"))
	_check(warned, "the thinning ice is told before the thaw")
	var n0 := col.n if col != null and sim.attacks.has(col) else 0
	# a save made on the ice, played on side by side through the thaw
	var data = bytes_to_var(var_to_bytes(sim.to_save()))
	var sim2 := Sim.new()
	var lr := sim2.from_save(data)
	_check(lr == "" or lr == null, "the save loads ('%s')" % str(lr))
	_check(not sim2.ice.is_empty() and sim2.get_feature("seasons").ice_on, "the loaded game has the ice")
	_check(sim.checksum() == sim2.checksum(), "same checksum after loading on the ice")
	if sim.checksum() != sim2.checksum():
		_diff(sim.to_save(), sim2.to_save(), "")
	# keep the column standing on the ice for the thaw
	if sim.attacks.has(col):
		var pos2: Vector2 = sim.military.column_pos(col)
		col.t0 = sim.time + 1000.0; col.t1 = sim.time + 2000.0; col.from = pos2; col.path = PackedInt32Array([sim.idx(int(round(pos2.x)), int(round(pos2.y))), sim.idx(d.x, d.y)])
		var c2: Sim.Attack = sim2.attacks[0]
		c2.t0 = col.t0; c2.t1 = col.t1; c2.from = col.from; c2.path = col.path
	_jump(sim, year - 1.0, 2.5)
	_jump(sim2, year - 1.0, 2.5)
	_check(sim.ice.is_empty() and not se.ice_on, "the ice broke up on the first day of spring")
	var left := ice_road
	left = 0
	for y in range(ry, ry + 3):
		if sim.road[y * sim.w + a.x - 3] != 0 or sim.pave[y * sim.w + a.x - 3] != 0: left += 1
	_check(left == 0, "the ice road melted away")
	_check(sim.road[s0] == 1, "the road on the bank is still there")
	var n1 := col.n if sim.attacks.has(col) else 0
	print("   column on the ice: %d soldiers before the thaw, %d after" % [n0, n1])
	_check(n0 > 0 and n1 == n0 - ceili(n0 * SimMilitary.ICE_DROWN), "half the soldiers on the ice drowned")
	var drowned := sim.logs.any(func(l): return String(l[1] if l is Array else l).contains("drowned"))
	_check(drowned, "the drowning is told in the log")
	_check(sim.military.land_path(a.x, a.y, d.x, d.y).is_empty(), "no way over the river once it thaws")
	_check(sim.checksum() == sim2.checksum(), "the loaded game went through the thaw the same")
	if sim.checksum() != sim2.checksum():
		_diff(sim.to_save(), sim2.to_save(), "")
	for k in 600:
		sim.tick(Sim.TICK); sim2.tick(Sim.TICK)
	_check(sim.checksum() == sim2.checksum(), "and a minute after it")

	# a rival does not cross ice that breaks up before it is over, and calls back a column on it
	var sim3 := Sim.new()
	sim3.new_game("ice3", 1, 4, true)
	var se3 = sim3.get_feature("seasons")
	Diplomacy.declare_war(sim3, 1, 2)
	var ry3 := _river(sim3, 6)
	var me3 := sim3.human()
	var foe3 := sim3.players[1]
	var t3 := sim3.add_bld("tower", me3.hq.x + 2, ry3 - 3, me3, true, 0)
	t3.garrison = 2
	var s3 := sim3.add_bld("tower", me3.hq.x + 2, ry3 + 8, foe3, true, 0)
	s3.garrison = 9; s3.gmix = [0, 9, 0, 0, 0, 0, 0]
	foe3.ai = true
	_jump(sim3, se3.YEAR - 40.0, 2.0)
	_check(not sim3.ice.is_empty(), "late winter: still frozen")
	var w3 := sim3.military.land_path(s3.x, s3.y, t3.x, t3.y)
	_check(sim3.military.ice_trap(w3), "a crossing just before the thaw is a trap")
	var before := sim3.attacks.size()
	sim3.ai_attack(foe3)
	_check(sim3.attacks.size() == before, "the rival does not send a column onto the thinning ice")
	sim3.military.launch_attack(s3, t3, 4)
	_check(sim3.attacks.size() == before + 1, "(a column sent by hand)")
	# a slow one, that would still be on its way at the thaw
	if sim3.attacks.size() > before:
		sim3.attacks[before].t1 += 60.0
	var g3 := s3.garrison
	_jump(sim3, se3.YEAR - se3.ICE_WARN - 0.5, 1.2)
	_check(sim3.attacks.size() == before and s3.garrison > g3, "the rival calls the column back as the ice thins")

	print("ICE TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
