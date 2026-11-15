extends SceneTree
## Columns march round water, buildings react to columns passing by, and survivors go home:
## godot --headless --script res://tools/march_test.gd

func _init() -> void:
	GameData.ensure()
	var ok := true
	var sim := Sim.new()
	sim.new_game("march", 1, 4, true)
	var me := sim.human(); var foe := sim.players[1]
	var mx := me.hq.x; var my := me.hq.y
	Diplomacy.declare_war(sim, 1, 2)
	# a lake between two towers: a strip of water 3 wide, 13 long, with open ends
	for y in range(my + 7, my + 10):
		for x in range(mx - 5, mx + 9):
			var i := y * sim.w + x
			sim.ter[i] = Sim.WATER; sim.deco[i] = 0; sim.road[i] = 0
	for y in range(my + 1, my + 16):
		for x in range(mx - 12, mx + 16):
			if sim.inb(x, y) and sim.ter[y * sim.w + x] == Sim.WATER and not (y >= my + 7 and y < my + 10 and x >= mx - 5 and x < mx + 9): sim.ter[y * sim.w + x] = Sim.GRASS
	var a := sim.add_bld("tower", mx + 2, my + 3, me, true, 0)
	a.garrison = 4; a.gmix = [0, 0, 4, 0, 0, 0]
	var d := sim.add_bld("tower", mx + 2, my + 13, foe, true, 0)
	d.garrison = 1; d.gmix = [1, 0, 0, 0, 0, 0]
	var path := sim.military.land_path(a.x, a.y, d.x, d.y)
	var wet := 0
	for i in path:
		if sim.ter[i] == Sim.WATER: wet += 1
	var straight := Vector2(d.x - a.x, d.y - a.y).length()
	print("way round the lake: %d tiles, %.1f long (straight %.1f), %d on water" % [path.size(), SimMilitary.path_len(sim.w, path), straight, wet])
	if path.size() < 3 or wet > 0: print("FAIL: the column should walk round the water"); ok = false
	var r := sim.military.launch_attack(a, d, 3)
	var on_water := 0
	var gate := false
	var last_n := 0
	var res0 := me.reserve
	while sim.attacks.size() > 0 and sim.time < 120.0:
		sim.tick(Sim.TICK)
		for at in sim.attacks:
			last_n = at.n
			if at.fighting: gate = true
			var pos: Vector2 = sim.military.column_pos(at).round()
			if sim.ter[int(pos.y) * sim.w + int(pos.x)] == Sim.WATER: on_water += 1
	print("attack '%s': column on water for %d ticks; tower taken %s; soldiers back home %d (reserve %d)" % [r, on_water, d.p == 1, a.garrison, me.reserve])
	print("   the column reached the gate: %s" % gate)
	for lg in sim.logs.slice(maxi(0, sim.logs.size() - 8)):
		print("   log: ", lg)
	if r != "" or on_water > 0 or not gate: ok = false; print("FAIL: the attack round the lake")
	print("   %d reached the end; 1 holds the new tower, tower at home now %d, reserve %+d" % [last_n, a.garrison, me.reserve - res0])
	if d.p == 1 and (a.garrison != 1 + (last_n - 1) or me.reserve != res0): ok = false; print("FAIL: the survivors should go back to their tower")
	# water all round: no way
	for y in range(my + 18, my + 23):
		for x in range(mx - 16, mx + 20):
			var i := y * sim.w + x
			if sim.inb(x, y): sim.ter[i] = Sim.WATER; sim.deco[i] = 0; sim.road[i] = 0
	var far := sim.add_bld("tower", mx + 2, my + 26, foe, true, 0) if sim.inb(mx + 2, my + 26) else null
	if far != null:
		far.garrison = 1
		# a full moat: close the sides too
		for y in range(my + 18, my + 35):
			for x in [mx - 16, mx - 15, mx + 18, mx + 19]:
				if sim.inb(x, y): sim.ter[y * sim.w + x] = Sim.WATER
		var r2 := sim.military.launch_attack(d, far, 1) if d.p == 1 and d.garrison > 1 else sim.military.launch_attack(a, far, 1)
		print("across a moat: '%s'" % r2)
	# a column passing a tower with archers and one set to march out
	var sim2 := Sim.new()
	sim2.new_game("march2", 1, 4, true)
	var me2 := sim2.human(); var foe2 := sim2.players[1]
	Diplomacy.declare_war(sim2, 1, 2)
	var hx := me2.hq.x; var hy := me2.hq.y
	# the way runs south of the headquarters, or north when the map ends too soon (s: which way)
	var sg := 1 if hy + 26 < sim2.h else -1
	if hx + 12 >= sim2.w: hx = sim2.w - 13
	for k in range(2, 26):
		var y := hy + sg * k
		for x in range(hx - 4, hx + 12):
			if sim2.inb(x, y) and sim2.ter[y * sim2.w + x] == Sim.WATER: sim2.ter[y * sim2.w + x] = Sim.GRASS
	var src := sim2.add_bld("tower", hx + 2, hy + sg * 22, foe2, true, 0)
	src.garrison = 4; src.gmix = [4, 0, 0, 0, 0, 0]
	var tgt := sim2.add_bld("tower", hx + 2, hy + sg * 4, me2, true, 0)
	tgt.garrison = 2; tgt.gmix = [2, 0, 0, 0, 0, 0]
	var side := sim2.add_bld("tower", hx + 5, hy + sg * 13, me2, true, 0)
	side.garrison = 4; side.gmix = [4, 0, 0, 0, 0, 0]; side.sally = true; side.archers = 2; side.archer_want = 2
	var r3 := sim2.military.launch_attack(src, tgt, 3)
	var chased := false
	var field := false
	while sim2.attacks.size() > 0 and sim2.time < 120.0:
		sim2.tick(Sim.TICK)
		for at in sim2.attacks:
			if at.chase != 0: chased = true
			if at.field != 0: field = true
	print("passing column '%s': side tower marched out %s, field battle %s; target still mine %s; side tower has %d soldiers" % [r3, chased, field, tgt.p == 1, side.garrison])
	if not chased or not field: ok = false; print("FAIL: the tower by the way should march out and fight")
	print("MARCH TEST: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
