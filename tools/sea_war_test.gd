extends SceneTree
## Build 49: landing from the sea at the start, landings on a rival's coast, fleets sinking ships at
## sea, and army supplies. godot --headless --script res://tools/sea_war_test.gd
var ok := true


func check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		ok = false


func _init() -> void:
	GameData.ensure()
	# 1. the harbour start: a map where it lands, and a rival it can reach by sea
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
			print("map %s: you land at %s, %s's headquarters reachable by sea" % [sd, Vector2i(sim.human().hq.x, sim.human().hq.y), sim.players[tgt.p - 1].name])
			break
	check(sim != null, "a map where you land from the sea and can reach a rival by ship")
	if sim == null:
		_end()
		return
	var me := sim.human()
	check(me.landed and me.ships == 1 and me.hq.ty == "hq", "you start with a harbour headquarters and one ship")
	check(sim.sea._moorings(me.hq.x, me.hq.y).size() >= 2, "it stands by open water")
	check(sim.sea.is_harbour(me.hq) and sim.sea.harbours(me).has(me.hq), "it counts as a harbour (expeditions, landings)")
	# 2. a landing: soldiers waiting, food in the stores, war
	for i in 20: sim.tick(Sim.TICK)
	me.reserve = 12
	me.rmix = [12, 0, 0, 0, 0, 0]
	me.ships = 2
	sim.give(me, "bread", 40.0)
	var bread0 := float(me.stock.get("bread", 0.0))
	Diplomacy.set_relation(sim, 1, tgt.p, Diplomacy.PEACE)
	check(sim.military.launch_landing(me.hq, tgt, 12) != "", "no landing while at peace")
	Diplomacy.declare_war(sim, 1, tgt.p)
	var why := sim.military.launch_landing(me.hq, tgt, 12)
	check(why == "", "a landing sets sail (%s)" % why)
	var a: Sim.Attack = null
	for x in sim.attacks:
		if x.p == 1 and x.sea > 0: a = x
	check(a != null and a.ships == 2 and me.ships_out == 2 and me.reserve == 0, "12 soldiers on 2 ships")
	if a == null:
		_end()
		return
	check(a.far and a.food > 0.0 and float(me.stock.get("bread", 0.0)) < bread0, "it took rations along (%d left after the crossing's share)" % int(a.food))
	check(sim.military.at_sea(a), "at sea")
	var p0 := sim.military.column_pos(a)
	check(sim.ter[sim.idx(roundi(p0.x), roundi(p0.y))] == Sim.WATER or p0.distance_to(Vector2(me.hq.x, me.hq.y)) < 3.5, "it starts on the water by the harbour")
	# 3. an enemy cargo ship on its way is sunk
	var q := sim.players[tgt.p - 1]
	q.ships = 1
	q.ships_out = 1
	var t := Sim.Trip.new()
	t.p = q.id; t.kind = "ship"; t.res = "planks"; t.n = 5
	var sea: PackedInt32Array = route[0]
	t.path = sea.slice(0, maxi(2, sea.size() - 1))
	t.path.reverse()
	t.t0 = sim.time; t.t1 = sim.time + 600.0; t.t2 = t.t1 + 600.0
	sim.trips.append(t)
	var t_end := sim.time + 400.0
	var landed_at := -1.0
	while sim.time < t_end and sim.attacks.has(a):
		sim.tick(Sim.TICK)
		if landed_at < 0.0 and not sim.military.at_sea(a):
			landed_at = sim.time
	check(not sim.trips.has(t) and q.ships == 0, "the fleet sank the enemy cargo ship it met")
	check(landed_at > 0.0, "the soldiers went ashore at %d s" % int(landed_at))
	check(me.ships_out == 0 and me.ships == 2, "the ships sailed home after the landing")
	print("  the landing: %s" % ("took the headquarters" if tgt.p == 1 or me.colonies >= 0 and sim.by_id.get(tgt.id) != null and sim.by_id[tgt.id].p == 1 else "fought (%d of 12 left)" % a.n))
	# 4. supplies: a column marching far from home with no food grows hungry at the gate
	var b := Sim.Attack.new()
	b.n = 8; b.far = true; b.food = 0.0; b.t_eat = sim.time - 1.0; b.p = 2
	sim.military._eat(b)
	sim.military._eat(b)
	b.t_eat = sim.time - 1.0
	sim.military._eat(b)
	check(b.hunger >= 0.99, "without food an army far from home starves (hunger %.1f)" % b.hunger)
	var c := Sim.Attack.new()
	c.n = 8; c.far = true; c.food = 10.0; c.t_eat = sim.time - 1.0; c.hunger = 0.5; c.p = 2
	sim.military._eat(c)
	check(c.food == 8.0 and c.hunger == 0.0, "fed from its rations: 2 for 8 soldiers, and no longer hungry")
	var d := Sim.Attack.new()
	d.n = 8; d.p = 1
	d.path = PackedInt32Array([0, 1, 2])
	sim.military.pack_supplies(d, me, me.hq)
	check(not d.far and d.food == 0.0, "near home no supplies are packed")
	_end()


func _end() -> void:
	print("SEA WAR TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
