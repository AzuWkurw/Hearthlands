extends SceneTree
## Surrender and vassals: godot --headless --script res://tools/vassal_test.gd
## A broken realm surrenders when asked and refuses when strong; a vassal follows its overlord's wars and
## peace, pays tribute, cannot be attacked apart from its overlord, breaks free when its goodwill is gone,
## goes free when its overlord falls; rivals take surrenders among themselves; rivals that serve you count
## as beaten for victory, and a vassal cannot win; vassals survive a save and load.

var ok := true


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		ok = false


func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("vassals", 3, 4, true)
	var me := sim.human()
	var r2 := sim.players[1]
	var r3 := sim.players[2]
	var r4 := sim.players[3]
	for i in 20: sim.tick(Sim.TICK)
	for q in sim.players:
		if q.ai:
			q.dip_t = 1e9    # the rivals' own diplomacy stays out of the way until the end
	sim.time = 400.0
	check(Diplomacy.at_war(sim, 1, 2) and Diplomacy.at_war(sim, 1, 3), "every realm starts at war")
	# a strong rival refuses to surrender
	me.reserve = 40
	r2.reserve = 60
	var why := Diplomacy.propose(sim, 1, 2, "submit")
	print("  strong rival: ", why)
	check(why != "" and r2.overlord == 0, "a strong rival will not surrender")
	# a broken one does
	r2.reserve = 0
	me.reserve = 200
	why = Diplomacy.propose(sim, 1, 2, "submit")
	print("  broken rival: '", why, "'")
	check(why == "" and r2.overlord == 1, "a broken rival surrenders when asked")
	check(Diplomacy.relation(sim, 1, 2) == Diplomacy.ALLY, "a vassal and its overlord count as allies")
	# it joins your war with rival 3
	check(Diplomacy.at_war(sim, 2, 3), "the vassal is at war with its overlord's enemy")
	# peace with rival 3 is peace for the vassal too
	Diplomacy.execute(sim, "peace", 1, 3, {}, {})
	check(not Diplomacy.at_war(sim, 2, 3), "the overlord's peace is its vassal's peace")
	# a vassal makes no treaties of its own
	why = Diplomacy.propose(sim, 4, 2, "peace")
	print("  peace with a vassal: ", why)
	check(why != "", "a vassal does not make peace on its own")
	# war on the vassal is war on its overlord
	Diplomacy.declare_war(sim, 3, 2)
	check(Diplomacy.at_war(sim, 3, 1) and Diplomacy.at_war(sim, 3, 2), "war on a vassal is war on its overlord")
	Diplomacy.execute(sim, "peace", 1, 3, {}, {})
	# tribute
	sim.give(r2, "gold", 100.0)
	var due := Diplomacy.tribute_due(r2)
	print("  tribute due: ", Diplomacy.goods_text(due))
	check(int(due.get("gold", 0)) > 0, "a vassal with gold owes some of it")
	var g0 := float(me.stock.get("gold", 0.0))
	var trips0 := sim.trips.size()
	r2.tribute_t = sim.time
	Diplomacy.vassal_tick(sim)
	check(sim.trips.size() > trips0 or float(me.stock.get("gold", 0.0)) > g0, "the tribute is on its way")
	check(r2.tribute_t > sim.time, "the next tribute is due later")
	# victory: with every rival yours or gone, you win; as a vassal you cannot
	check(not sim.over, "the game goes on while free rivals remain")
	# save and load keep the vassal
	var d = bytes_to_var(var_to_bytes(sim.to_save()))
	var s2 := Sim.new()
	var err := s2.from_save(d)
	check(err == "" and s2.players[1].overlord == 1 and is_equal_approx(s2.players[1].tribute_t, r2.tribute_t), "a vassal is still a vassal after loading")
	# rivals among themselves: 4 asks 3 to surrender, 3 broken
	Diplomacy.declare_war(sim, 3, 4)
	sim.rel_since[Diplomacy.key(3, 4)] = 0.0
	r3.reserve = 0
	r4.reserve = 150
	why = Diplomacy.propose(sim, 4, 3, "submit")
	print("  rival to rival: '", why, "'")
	check(why == "" and r3.overlord == 4, "a rival takes another's surrender")
	check(Diplomacy.at_war(sim, 3, 1) == Diplomacy.at_war(sim, 4, 1), "the new vassal follows its overlord with you")
	# AI surrender decisions run through the rival's own turn
	var tries := 0
	r3.warned.clear()
	while r3.overlord == 4 and tries < 200:
		r3.opinion[4] = -90.0
		r3.vassal_t = 0.0
		Diplomacy._ai_vassal(sim, r3, [me, r2, r4])
		tries += 1
	check(r3.overlord == 0, "a vassal with no goodwill left breaks free (after %d turns)" % tries)
	# its overlord falls: its vassals go free
	Diplomacy.execute(sim, "peace", 3, 4, {}, {})
	Diplomacy.declare_war(sim, 4, 3)
	sim.rel_since[Diplomacy.key(3, 4)] = 0.0
	r3.reserve = 0
	Diplomacy.propose(sim, 4, 3, "submit")
	check(r3.overlord == 4, "surrenders again")
	sim.military.eliminate(r4, me)
	check(r3.overlord == 0, "a vassal goes free when its overlord falls")
	# now 2 serves you, 4 is gone, 3 is free: no victory yet; 3 surrenders: victory
	check(not sim.over, "no victory while a free rival stands")
	if not Diplomacy.at_war(sim, 1, 3):
		Diplomacy.declare_war(sim, 1, 3)
	sim.rel_since[Diplomacy.key(1, 3)] = 0.0
	var won := []
	sim.ended.connect(func(w): won.append(w))
	why = Diplomacy.propose(sim, 3, 1, "vassal")
	print("  offer to you: ", why)
	check(why == "pending", "a rival's offer to surrender waits for your answer")
	var pid := int(sim.proposals[-1].id)
	check(Diplomacy.accept(sim, pid) == "" and r3.overlord == 1, "you accept the surrender")
	sim.military._check_alliance_end()
	check(sim.over and won.size() == 1 and bool(won[0]), "every rival standing serves you: victory")
	# a vassal cannot win: a fresh game where you surrender
	var s3 := Sim.new()
	s3.new_game("vassals2", 2, 4, true)
	for i in 20: s3.tick(Sim.TICK)
	s3.time = 400.0
	s3.players[1].reserve = 200
	s3.human().reserve = 0
	why = Diplomacy.propose(s3, 1, 2, "vassal")
	print("  your surrender: '", why, "'")
	check(why == "" and s3.human().overlord == 2, "a rival takes your surrender")
	s3.military.eliminate(s3.players[2], s3.players[1])
	check(not s3.over, "a vassal does not win when the others fall")
	Diplomacy.declare_war(s3, 1, 2)
	check(s3.human().overlord == 0 and Diplomacy.at_war(s3, 1, 2), "declaring war on your overlord breaks free")
	# rivals play on with vassals in the game without errors
	for q in sim.players:
		q.dip_t = 1.0
	sim.over = false
	for i in 3000: sim.tick(Sim.TICK)
	print("  after 5 more minutes: overlords ", sim.players.map(func(q): return q.overlord))
	print("VASSAL TEST: ", "PASS" if ok else "FAIL")
	quit()
