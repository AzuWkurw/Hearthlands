extends SceneTree
## Mission events (MissionScript, build 77): each kind of start and action works, events fire once (or
## every so often), hidden goals wait until shown, a scripted war lifts the peace at the start, and a
## game with events saves and loads the same. godot --headless --script res://tools/script_test.gd

var stories := 0
var won := -1


func _mission() -> Dictionary:
	return {"name": "script test", "minutes": 0, "opts": {"peace_min": 60},
		"goals": [
			{"kind": "pop", "n": 5, "text": "Have 5 people"},
			{"kind": "pop", "n": 6, "text": "Have 6 people", "hidden": true},
		],
		"rules": [
			{"id": "hello", "when": {"kind": "start"}, "do": [{"kind": "message", "title": "Hello", "text": "{1} watches you, {you}."}]},
			{"id": "gift", "when": {"kind": "time", "min": 1}, "do": [{"kind": "goods", "who": 0, "res": "planks", "n": 50}]},
			{"id": "tick", "when": {"kind": "every", "min": 1, "every": 1}, "do": [{"kind": "soldiers", "who": 0, "n": 1}]},
			{"id": "grow", "when": {"kind": "pop", "who": 0, "n": 5}, "do": [{"kind": "tech", "who": 1, "id": "herding"}]},
			{"id": "seen", "when": {"kind": "tech", "who": -1, "id": "herding"}, "do": [{"kind": "war", "who": 1}]},
			{"id": "later", "when": {"kind": "after", "rule": "seen", "min": 2}, "do": [{"kind": "landing", "who": 1, "n": 6}]},
			{"id": "war", "when": {"kind": "war", "who": 1}, "do": [{"kind": "message", "text": "War!"}]},
			{"id": "phase2", "when": {"kind": "time", "min": 3}, "do": [{"kind": "show_goal", "goal": 1}]},
		]}


func _init() -> void:
	GameData.ensure()
	var ok := true
	var sim := Sim.new()
	sim.story.connect(func(_t, _x): stories += 1)
	sim.ended.connect(func(w): won = 1 if w else 0)
	var ms := _mission()
	if not sim.new_game("script test", 2, 3, false, 0, false, ms.opts, {}, ms):
		print("script test: could not start")
		quit()
		return
	sim.players[0].ai = true
	var me := sim.human()
	var r1 := sim.players[1]
	var res0 := me.reserve
	while sim.time < 62.0:
		sim.tick(Sim.TICK)
	var fired := sim.script_fired.keys()
	fired.sort()
	print("fired after a minute: ", fired)
	var c1 := sim.script_fired.has("hello") and sim.script_fired.has("gift") and sim.script_fired.has("grow") and sim.script_fired.has("seen")
	print("start, minute, people, study and war events fired: ", c1)
	ok = ok and c1
	print("message shown: ", stories >= 2, " (", stories, "), log has the rival's name: ", _log_has(sim, r1.name + " watches you"))
	ok = ok and stories >= 2 and _log_has(sim, r1.name + " watches you")
	var c2 := _log_has(sim, "50 planks arrive")
	print("goods given: ", c2)
	ok = ok and c2
	var c3 := r1.techs.has("herding") and Diplomacy.at_war(sim, 2, 1) and r1.script_war
	print("rival learned herding and declared war in the peace: ", c3)
	ok = ok and c3
	print("hidden goal not done yet, mission not over: ", not sim.over)
	ok = ok and not sim.over
	# the game saved now must go on exactly the same, events and all
	var b := Sim.new()
	b.from_save(bytes_to_var(var_to_bytes(sim.to_save())))
	var att0 := sim.attacks.size()
	var r1_res := r1.reserve
	while sim.time < 150.0:
		sim.tick(Sim.TICK)
		b.tick(Sim.TICK)
	var same := sim.checksum() == b.checksum()
	print("matches after load: ", same, " (fired ", b.script_fired.size(), ")")
	ok = ok and same
	var land := sim.script_fired.has("later") and not fired.has("later") and (sim.attacks.size() > att0 or r1.reserve >= r1_res + 6)
	print("landing or attack sent: ", land, " (attacks ", sim.attacks.size(), ", rival reserve ", r1.reserve, ")")
	ok = ok and land
	var times := int((sim.script_fired.get("tick", [0, 0]) as Array)[0])
	print("repeating event fired ", times, " times; soldiers +", me.reserve - res0)
	ok = ok and times == 2
	while sim.time < 200.0 and not sim.over:
		sim.tick(Sim.TICK)
	print("hidden goal shown at minute 3, then the mission is won: ", won == 1, " (shown: ", not sim.mission.goals[1].has("hidden"), ")")
	ok = ok and won == 1
	sim.dispose()
	b.dispose()
	# a landing from a rival with a harbour goes by sea, with the ships it needs
	ok = _sea_landing() and ok
	# win and lose by event; checking a bad rule list
	won = -1
	var s2 := Sim.new()
	s2.ended.connect(func(w): won = 1 if w else 0)
	s2.new_game("script lose", 1, 3, false, 0, false, {}, {}, {"name": "x", "goals": [{"kind": "pop", "n": 9999, "text": "x"}],
		"rules": [{"when": {"kind": "time", "min": 0.1}, "do": [{"kind": "lose"}]}]})
	while s2.time < 10.0:
		s2.tick(Sim.TICK)
	print("lost by an event: ", won == 0)
	ok = ok and won == 0
	s2.dispose()
	var bad := MissionScript.problems({"goals": [], "rules": [{"when": {"kind": "after", "rule": "nope"}, "do": []}, {"when": {"kind": "time"}, "do": [{"kind": "show_goal", "goal": 3}, {"kind": "fly"}]}]})
	print("problems found: ", bad.size(), " ", bad)
	ok = ok and bad.size() == 4
	# every event in the shipped missions and the campaign is well formed
	var all_ok := true
	for m in UiMissions.missions():
		for why in MissionScript.problems(m):
			print("  %s: %s" % [String(m.get("name", "")), why])
			all_ok = false
	var camp = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign.json"))
	for ch in camp.chapters:
		for why in MissionScript.problems(ch.mission):
			print("  %s: %s" % [String(ch.mission.get("name", "")), why])
			all_ok = false
		for r in ch.mission.get("rules", []):
			MissionScript.rule_text(r)
	print("shipped missions' events are well formed: ", all_ok)
	ok = ok and all_ok
	print("SCRIPT TEST: ", "PASS" if ok else "FAIL")
	quit()


func _sea_landing() -> bool:
	var sim: Sim = null
	var tgt: Sim.Bld = null
	var route := []
	for sd in ["islands", "coast", "bay", "isles", "harbour", "sound", "fjord", "lagoon"]:
		var s := Sim.new()
		s.new_game(sd, 3, 5, false, 160, false, {"sea_start": true})
		if s.human().landed:
			for q in s.players:
				if q.id != 1 and tgt == null:
					var r := s.sea.landing_route(s.human().hq, q.hq)
					if not r.is_empty():
						sim = s; tgt = q.hq; route = r
		if sim != null:
			break
		s.dispose()
	if sim == null:
		print("no coast map for the landing (skipped)")
		return true
	var q := sim.players[tgt.p - 1]
	for i in 20: sim.tick(Sim.TICK)
	var beach: int = (route[0] as PackedInt32Array)[(route[0] as PackedInt32Array).size() - 1]
	sim.bmap[beach] = 0
	sim.add_bld("harbour", beach % sim.w, beach / sim.w, q, true)
	for i in 12: sim.tick(Sim.TICK)
	q.ships = 0; q.ships_out = 0
	MissionScript.run(sim, {"kind": "landing", "who": q.id - 1, "n": 12})
	var a: Array = sim.attacks.filter(func(x): return x.p == q.id and x.sea > 0)
	var good := Diplomacy.at_war(sim, q.id, 1) and a.size() == 1 and (a[0] as Sim.Attack).n == 12 and q.ships == 2
	print("a rival's fleet sails with 12 soldiers on 2 ships: ", good, " (", a.size(), " fleets, ", q.ships, " ships)")
	sim.dispose()
	return good


func _log_has(sim: Sim, s: String) -> bool:
	for e in sim.logs:
		if String(e[1]).contains(s):
			return true
	return false
