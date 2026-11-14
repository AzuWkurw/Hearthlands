extends SceneTree
## Events that ask you to choose, and an ally's call for help:
## godot --headless --script res://tools/choice_test.gd
func _init() -> void:
	GameData.ensure()
	var ok := true
	var sim := Sim.new()
	sim.new_game("choices", 2, 4, true, 0, true, {"features": Features.default_ids()})
	for i in 5: sim.tick(Sim.TICK)
	var me := sim.human()
	var ev = sim.get_feature("events")
	# a comet: ask, answer "study" -> research points
	ev.pending[me.id] = ["comet", sim.time]
	var q: Dictionary = ev.question(me)
	print("question: %s, %d answers" % [q.get("title", "-"), (q.get("options", []) as Array).size()])
	if q.get("id", "") != "comet": ok = false; print("FAIL: the comet should wait for an answer")
	var rp0 := me.rp
	ev.answer(me, 1)
	print("study the comet: research points %.0f -> %.0f, waiting %s" % [rp0, me.rp, ev.pending.has(me.id)])
	if me.rp <= rp0 or ev.pending.has(me.id): ok = false; print("FAIL: studying gives research")
	# grumbling left unanswered takes the last answer (slower work)
	ev.pending[me.id] = ["grumbling", sim.time]
	var t0 := sim.time
	while sim.time < t0 + Sim.TICK * 10 + 125.0: sim.tick(Sim.TICK)
	print("grumbling unanswered: waiting %s, boosts %s" % [ev.pending.has(me.id), ev.boosts.filter(func(b): return int(b[0]) == me.id)])
	if ev.pending.has(me.id): ok = false; print("FAIL: an unanswered question is answered by itself")
	# pilgrims taken in eat food
	sim.give(me, "bread", 30.0)
	var bread0 := float(me.stock.bread)
	ev.pending[me.id] = ["pilgrims", sim.time]
	ev.answer(me, 0)
	print("pilgrims fed: bread %.0f -> %.0f" % [bread0, me.stock.bread])
	# saved and loaded, a waiting question stays
	ev.pending[me.id] = ["strange_ship", sim.time]
	var d := sim.to_save()
	var sim2 := Sim.new()
	sim2.from_save(d)
	var ev2 = sim2.get_feature("events")
	print("after loading, waiting: ", ev2.question(sim2.human()).get("id", "-"))
	if ev2.question(sim2.human()).get("id", "") != "strange_ship": ok = false; print("FAIL: the question survives a save")
	# an ally at war calls for help; refusing costs trust
	var ally := sim.players[1]
	var foe := sim.players[2]
	Diplomacy.set_relation(sim, me.id, ally.id, Diplomacy.ALLY)
	Diplomacy.set_relation(sim, ally.id, foe.id, Diplomacy.WAR)
	Diplomacy.set_relation(sim, me.id, foe.id, Diplomacy.PEACE)
	ally.opinion[me.id] = 60.0
	var asked := Diplomacy._ai_call_for_help(sim, ally, me)
	var pr = sim.proposals.filter(func(x): return x.kind == "help")
	print("ally asks for help: %s, proposals %d" % [asked, pr.size()])
	if not asked or pr.is_empty(): ok = false; print("FAIL: an ally at war asks for help")
	else:
		Diplomacy.decline(sim, int(pr[0].id))
		print("refused: opinion %.0f" % Diplomacy.opinion(ally, me.id))
		if Diplomacy.opinion(ally, me.id) >= 60.0: ok = false; print("FAIL: refusing costs trust")
		sim.time += 500.0
		Diplomacy._ai_call_for_help(sim, ally, me)
		var pr2 = sim.proposals.filter(func(x): return x.kind == "help")
		var r := Diplomacy.accept(sim, int(pr2[0].id)) if not pr2.is_empty() else "none"
		print("accepted: '%s', at war with %s: %s" % [r, foe.name, Diplomacy.at_war(sim, me.id, foe.id)])
		if r != "" or not Diplomacy.at_war(sim, me.id, foe.id): ok = false; print("FAIL: accepting joins the war")
	# an ally that no longer trusts you leaves the alliance
	var other := sim.players[2]
	Diplomacy.set_relation(sim, me.id, other.id, Diplomacy.ALLY)
	other.opinion[me.id] = -10.0
	print("ally with low trust leaves: ", Diplomacy._ai_leave_alliance(sim, other, me), " now ", Diplomacy.NAMES[Diplomacy.relation(sim, me.id, other.id)])
	if Diplomacy.relation(sim, me.id, other.id) != Diplomacy.PEACE: ok = false; print("FAIL: leaving an alliance")
	print("choice test: ", "ok" if ok else "FAILED")
	sim.dispose(); sim2.dispose()
	quit()
