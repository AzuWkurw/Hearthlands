extends SceneTree
## The research queue and repeatable studies: godot --headless --script res://tools/research_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("rq", 1, 5, false, 0, true, {"features": []})
	var p := sim.human()
	print("techs %d, repeatables %d, lanes %d" % [GameData.techs.size(), GameData.reps.size(), GameData.lanes.size()])
	print("r1_tools open in Roman age: ", sim.tech_available(p, "r1_tools"))
	sim.complete_tech(p, "iron_axes")
	print("after a tech, age %d, r1_tools open: %s, cost %d" % [p.age, sim.tech_available(p, "r1_tools"), sim.research_cost(p, "r1_tools")])
	var path := sim.research_path(p, "printing_press")
	print("path to printing press: ", path)
	for x in path: sim.queue_research(p, x)
	print("queued 3 levels: ", sim.queue_research(p, "r1_tools"), sim.queue_research(p, "r1_tools"), sim.queue_research(p, "r1_tools"), " 4th: ", sim.queue_research(p, "r1_tools"))
	print("studying %s, queue %s" % [p.research, p.rqueue])
	sim.unqueue_research(p, p.rqueue.find("papermaking"))
	print("papermaking off (printing press goes too): ", p.rqueue)
	p.rp = 5000.0
	var t0 := sim.time
	while p.research != "" and sim.time < t0 + 30.0:
		sim.tick(Sim.TICK)
	print("after: techs %s reps %s research '%s' rp %d" % [p.techs.keys(), p.reps, p.research, int(p.rp)])
	print("speed:all mod: %.2f" % sim.mod(p, "speed:all"))
	sim.queue_research(p, "monasteries")
	var d := sim.to_save()
	var s2 := Sim.new()
	print("load: '%s' reps %s queue %s research %s mod %.2f" % [s2.from_save(d), s2.human().reps, s2.human().rqueue, s2.human().research, s2.mod(s2.human(), "speed:all")])
	sim.dispose(); s2.dispose()
	quit()
