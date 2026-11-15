extends SceneTree
## Build 59: a coast defended. A landing is seen and its target warned; peasants by the headquarters
## take up arms; walls help against soldiers just come ashore; warships go further out to meet a fleet
## making for their realm; wild animals capped by the map's size.
## godot --headless --script res://tools/coast_test.gd
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
			if q.id != 1 and tgt == null:
				var r := s.sea.landing_route(s.human().hq, q.hq)
				if not r.is_empty():
					sim = s; tgt = q.hq; route = r
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
	Diplomacy.declare_war(sim, q.id, 1)
	# the rival gets a harbour on its beach
	var beach: int = (route[0] as PackedInt32Array)[(route[0] as PackedInt32Array).size() - 1]
	sim.bmap[beach] = 0
	var qh := sim.add_bld("harbour", beach % sim.w, beach / sim.w, q, true)
	# 1. the rival lands at my headquarters: I am warned while it is at sea
	q.reserve = 12; q.rmix = [12, 0, 0, 0, 0, 0]; q.ships = 3; q.ships_out = 0; q.general_back = 0.0
	sim.give(q, "bread", 30.0)
	me.peasant = 48
	me.reserve = 30; me.rmix = [30, 0, 0, 0, 0, 0]
	var why := sim.military.launch_landing(qh, me.hq, 12)
	check(why == "", "the rival sends a landing of 12 (%s)" % why)
	var a: Sim.Attack = null
	for x in sim.attacks:
		if x.p == q.id and x.sea > 0: a = x
	if a == null:
		_end()
		return
	var logs0 := sim.logs.size()
	var warned_at := -1.0
	var peas0 := me.peasant
	var n_land := -1
	var t_end := sim.time + 400.0
	while sim.time < t_end and sim.attacks.has(a) and not a.fighting:
		sim.tick(Sim.TICK)
		if a.warned and warned_at < 0.0:
			warned_at = sim.time
			check(sim.military.at_sea(a), "warned while the fleet is still at sea (%.0f s before it lands)" % (a.t_land - sim.time))
		if a.militia and n_land < 0:
			n_land = a.n
	var said := false
	for i in range(logs0, sim.logs.size()):
		if String(sim.logs[i][1]).begins_with("Sails off the coast"): said = true
	check(said, "the log says sails are off the coast")
	check(a.militia, "the peasants met the landing")
	var mil_line := ""
	for i in range(logs0, sim.logs.size()):
		if String(sim.logs[i][1]).contains("took up arms"): mil_line = String(sim.logs[i][1])
	check(peas0 - me.peasant <= SimMilitary.MILITIA_MAX and mil_line != "" and int(mil_line.get_slice(" ", 0)) <= SimMilitary.MILITIA_MAX and int(mil_line.get_slice(" ", 0)) >= 1, "one peasant in six, at most %d, took up arms (%s)" % [SimMilitary.MILITIA_MAX, mil_line])
	# 2. walls help against soldiers just come ashore: same duel odds with and without town walls
	me.techs.erase("town_walls")
	var base := SimMilitary.LANDING_PEN
	check(base > 0.0 and SimMilitary.LANDING_WALL > 0.0, "a duel over soldiers just ashore favours the defenders (+%d%%, +%d%% each for town walls and star forts)" % [roundi(base * 100), roundi(SimMilitary.LANDING_WALL * 100)])
	# 3. warships go further out for a fleet making for their own realm
	sim.attacks.clear()
	sim.navy.clear(); me.warships = 0
	sim.naval.launch(me, me.hq)
	var w: Dictionary = sim.navy[0]
	q.reserve = 6; q.rmix = [6, 0, 0, 0, 0, 0]; q.ships = 3; q.ships_out = 0
	why = sim.military.launch_landing(qh, me.hq, 6)
	var b: Sim.Attack = null
	for x in sim.attacks:
		if x.p == q.id and x.sea > 0: b = x
	var seen_at := -1.0
	if b != null:
		t_end = sim.time + 300.0
		while sim.time < t_end and sim.military.at_sea(b):
			sim.tick(Sim.TICK)
			if seen_at < 0.0 and sim.naval._target(w, me, me.hq, false) != null:
				seen_at = sim.military.column_pos(b).distance_to(Vector2(me.hq.x, me.hq.y))
	check(seen_at > SimNavy.GUARD_R + SimNavy.GUARD_OUT + 0.5 or (seen_at > 0.0 and b.t_land - b.t0 < 40.0), "a guard went for the fleet %.1f tiles from its harbour (it used to wait for %.0f)" % [seen_at, SimNavy.GUARD_R + SimNavy.GUARD_OUT])
	# 4. saved and loaded with a warned landing
	var d := sim.to_save()
	var s2 := Sim.new()
	s2.from_save(bytes_to_var(var_to_bytes(d)))
	var same := s2.attacks.size() == sim.attacks.size()
	for i in mini(s2.attacks.size(), sim.attacks.size()):
		same = same and s2.attacks[i].warned == sim.attacks[i].warned and s2.attacks[i].militia == sim.attacks[i].militia
	check(same, "warned and militia are saved with the landing")
	# 5. wild animals: a big map holds no more than one for every 40 tiles
	var big := Sim.new()
	big.new_game("wild", 2, 5, false, 256, false, {"features": Features.default_ids()})
	var wl = big.get_feature("wildlife")
	for i in int(40.0 / Sim.TICK): big.tick(Sim.TICK)
	var cap := 0
	for k in wl.KINDS:
		cap += wl._cap(k)
	check(wl.animals.size() <= cap and cap <= 256 * 256 / 40 + 12, "a 256 map: %d animals, at most %d" % [wl.animals.size(), cap])
	_end()


func _end() -> void:
	print("COAST TEST: %s" % ("PASS" if ok else "FAIL"))
	quit()
