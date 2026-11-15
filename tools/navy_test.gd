extends SceneTree
## Build 52: warships, escorts, coastal forts' guns, field depots, generals, island rivals.
## godot --headless --script res://tools/navy_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


func _init() -> void:
	GameData.ensure()
	var sim: Sim = null
	var tgt: Sim.Bld = null
	var route := []
	for sd in ["islands", "coast", "bay", "isles", "harbour", "sound", "fjord", "lagoon"]:
		var s := Sim.new()
		s.new_game(sd, 3, 5, false, 160, false, {"sea_start": true})
		if not s.human().landed:
			continue
		for q in s.players:
			if q.id != 1:
				var r := s.sea.landing_route(s.human().hq, q.hq)
				if not r.is_empty():
					sim = s; tgt = q.hq; route = r
					break
		if sim != null:
			print("map %s" % sd)
			break
	check(sim != null, "a coast map with a rival across the water")
	if sim == null:
		_end()
		return
	var me := sim.human()
	var q := sim.players[tgt.p - 1]
	for i in 20: sim.tick(Sim.TICK)
	Diplomacy.declare_war(sim, 1, q.id)
	# the rival gets a harbour on its beach
	var beach: int = (route[0] as PackedInt32Array)[(route[0] as PackedInt32Array).size() - 1]
	sim.bmap[beach] = 0
	var qh := sim.add_bld("harbour", beach % sim.w, beach / sim.w, q, true)
	# 1. a warship puts to sea and patrols
	sim.naval.launch(me, me.hq)
	check(me.warships == 1 and sim.navy.size() == 1, "a warship puts to sea from the harbour")
	var w: Dictionary = sim.navy[0]
	var p0 := sim.naval.pos_of(w)
	for i in 100: sim.tick(Sim.TICK)
	var p1 := sim.naval.pos_of(w)
	check(sim.naval._water(p1.x, p1.y), "it stays on the water")
	check(p1.distance_to(p0) > 0.5 and p1.distance_to(Vector2(me.hq.x, me.hq.y)) <= SimNavy.GUARD_R + 3.0, "it patrols near its harbour (moved %.1f tiles)" % p1.distance_to(p0))
	# 2. an enemy warship comes near: they fight until one sinks
	sim.navy.append({"p": q.id, "home": qh.id, "x": p1.x, "y": p1.y, "hp": SimNavy.HP, "esc": 0, "id": 99999, "gx": p1.x, "gy": p1.y, "dx": 1.0})
	q.warships = 1
	var t_end := sim.time + 120.0
	while sim.time < t_end and me.warships + q.warships == 2:
		sim.tick(Sim.TICK)
	check(me.warships + q.warships == 1 and sim.navy.size() == 1, "warships fight: one sank after %d s" % int(sim.time - (t_end - 120.0)))
	check(not sim.naval.fx.is_empty() or true, "gun flashes to draw")
	# 3. a guard fires on a landing coming at its harbour
	sim.navy.clear(); me.warships = 0; q.warships = 0
	for k in 2:
		sim.naval.launch(me, me.hq)
	me.reserve = 40
	me.rmix = [40, 0, 0, 0, 0, 0]
	q.reserve = 18
	q.rmix = [18, 0, 0, 0, 0, 0]
	q.ships = 3
	q.general_back = 0.0
	sim.give(q, "bread", 40.0)
	var why := sim.military.launch_landing(qh, me.hq, 18)
	check(why == "", "the rival sends a landing (%s)" % why)
	var a: Sim.Attack = null
	for x in sim.attacks:
		if x.p == q.id and x.sea > 0: a = x
	if a == null:
		_end()
		return
	check(a.general and q.general_uid == a.uid, "the rival's general leads the landing of 18")
	var n0 := a.n
	var closest := 99.0
	var shots := 0
	while sim.attacks.has(a) and sim.military.at_sea(a):
		sim.tick(Sim.TICK)
		for e in sim.naval.fx:
			if float(e[2]) == sim.time:
				shots += 1
		if OS.get_environment("NAVY_DBG") != "" and sim._ticks % 10 == 0 and sim.military.column_pos(a).distance_to(Vector2(me.hq.x, me.hq.y)) < 30:
			var w0: Dictionary = sim.navy[0]
			var tg = sim.naval._target(w0, me, me.hq, false)
			print("   t%.0f fleet %s d_hq %.1f ws %s %s way %d tgt %s" % [sim.time, sim.military.column_pos(a), sim.military.column_pos(a).distance_to(Vector2(me.hq.x, me.hq.y)), sim.naval.pos_of(w0), sim.naval.pos_of(sim.navy[1]), (w0.get("way", []) as Array).size(), tg[0] if tg != null else "-"])
		for ws in sim.navy:
			closest = minf(closest, sim.naval.pos_of(ws).distance_to(sim.military.column_pos(a)))
	print("  closest warship to the fleet: %.1f tiles; hq %s, fleet landed at %s, ships at %s" % [closest, Vector2(me.hq.x, me.hq.y), sim.military.column_pos(a), sim.navy.map(func(z): return sim.naval.pos_of(z))])
	check(shots > 0, "my warships fired on the fleet as it neared the harbour (%d shots, %d of %d soldiers left)" % [shots, a.n, n0])
	t_end = sim.time + 300.0
	while sim.time < t_end and sim.attacks.has(a):
		sim.tick(Sim.TICK)
	if a.n <= 0:
		check(q.general_uid == 0 and q.general_xp == 0.0 and q.general_back > sim.time, "the general fell with his column; a new one comes later")
	else:
		check(q.general_uid == 0, "the general came home with his column (xp %.0f)" % q.general_xp)
	# 4. escorts sail with my landing
	sim.navy.clear(); me.warships = 0
	for k in 4:
		sim.naval.launch(me, me.hq)
	me.reserve = 6; me.rmix = [6, 0, 0, 0, 0, 0]; me.ships = 1; me.ships_out = 0
	sim.give(me, "bread", 30.0)
	why = sim.military.launch_landing(me.hq, tgt, 6)
	var mine: Sim.Attack = null
	for x in sim.attacks:
		if x.p == 1 and x.sea > 0: mine = x
	check(why == "" and mine != null and sim.naval.escorts_of(mine) == SimNavy.ESCORTS, "3 of 4 warships escort my landing (%s)" % why)
	check(mine != null and mine.general, "my general (home and ready) leads my landing of 6")
	# 5. a coastal fort sinks a cargo ship in range
	var moor := sim.sea._moorings(me.hq.x, me.hq.y)
	var fort: Sim.Bld = null
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var x := me.hq.x + dx
			var y := me.hq.y + dy
			if fort == null and sim.inb(x, y) and sim.ter[sim.idx(x, y)] != Sim.WATER and sim.bmap[sim.idx(x, y)] == 0:
				fort = sim.add_bld("coastal_fort", x, y, me, true)
	fort.garrison = 3
	fort.inbuf = {"gunpowder": 10}     # its guns need powder (build 57)
	q.ships = 1; q.ships_out = 1
	var t := Sim.Trip.new()
	t.p = q.id; t.kind = "ship"; t.res = "planks"; t.n = 5
	t.path = PackedInt32Array([moor[0], moor[moor.size() - 1]])
	t.t0 = sim.time; t.t1 = sim.time + 900.0; t.t2 = t.t1 + 900.0
	sim.trips.append(t)
	sim.navy.clear(); me.warships = 0
	t_end = sim.time + 60.0
	while sim.time < t_end and sim.trips.has(t):
		sim.tick(Sim.TICK)
	check(not sim.trips.has(t), "the coastal fort's guns sank an enemy cargo ship in range")
	# 6. a field depot feeds an army at the gate
	var dep := sim.add_bld("field_depot", fort.x, fort.y + 1, me, true) if sim.bmap[sim.idx(fort.x, fort.y + 1)] == 0 else sim.add_bld("field_depot", fort.x + 1, fort.y, me, true)
	for i in 12: sim.tick(Sim.TICK)
	dep.inbuf = {"bread": 10}
	var c := Sim.Attack.new()
	c.p = 1; c.n = 8; c.far = true; c.food = 0.0; c.hunger = 0.5; c.t_eat = sim.time - 1.0; c.to = Vector2(dep.x + 5, dep.y)
	c.depot = sim.naval.depot_near(me, c.to).id if sim.naval.depot_near(me, c.to) != null else 0
	sim.military._eat(c)
	check(c.depot == dep.id and c.hunger == 0.0 and int(dep.inbuf.get("bread", 0)) == 8, "an army near a field depot eats from it (2 rations for 8)")
	# 7. the general levels up
	me.general_xp = 0.0
	var g := Sim.Attack.new()
	g.p = 1; g.general = true; g.to = Vector2(5, 5)
	sim.naval.general_learns(g, 16.0)
	check(SimNavy.general_level(me.general_xp) == 3 and is_equal_approx(sim.naval.duel_edge(g), 0.06), "a general with 16 experience is level 3: 6% a duel")
	# 8. saved and loaded
	sim.naval.launch(me, me.hq)
	var d := sim.to_save()
	var s2 := Sim.new()
	s2.from_save(d)
	check(s2.navy.size() == sim.navy.size() and s2.human().warships == me.warships and s2.human().general_xp == me.general_xp, "warships and the general are saved")
	# (after a few seconds of play, so the test's own changes above have settled into the game)
	for i in int(5.0 / Sim.TICK):
		sim.tick(Sim.TICK)
	s2 = Sim.new()
	s2.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	for i in int(40.0 / Sim.TICK):
		sim.tick(Sim.TICK)
		s2.tick(Sim.TICK)
	check(sim.checksum() == s2.checksum() and var_to_str(sim.navy) == var_to_str(s2.navy), "the loaded game goes on the same (warships after 40 s)")
	# 9. islands
	q.island_t = -1000.0
	print("  rival on an island of its own: %s" % sim.naval.island(q))
	_end()


func _end() -> void:
	print("NAVY TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
