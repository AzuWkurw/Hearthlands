extends SceneTree
## Plays 70 minutes with computer realms only and prints how far each got in research, and how many
## levels of repeatable studies each took: godot --headless --script res://tools/research_ai_test.gd
func _init() -> void:
	GameData.ensure()
	var sim := Sim.new()
	sim.new_game("resai", 4, 6, true)
	sim.players[0].ai = true
	var next := 10.0
	while sim.time < 70 * 60.0:
		sim.tick(Sim.TICK)
		if sim.time >= next * 60.0:
			next += 10.0
			var line := "min %d:" % roundi(sim.time / 60.0)
			for p in sim.players:
				var lv := 0
				for k in p.reps: lv += int(p.reps[k])
				line += "  %s age %d techs %d reps %d" % [p.name.left(6), p.age, p.techs.size(), lv]
			print(line)
	sim.dispose()
	quit()
