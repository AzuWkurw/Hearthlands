extends SceneTree
## Plays a game with rivals only and prints the state checksum each minute. Two versions that should
## behave the same (a pure code move, say) must print the same numbers.
## godot --headless --script res://tools/checksum_run.gd [-- seed=valley mins=6]
func _init() -> void:
	GameData.ensure()
	var seed := "valley"; var mins := 6
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="): seed = a.substr(5)
		if a.begins_with("mins="): mins = int(a.substr(5))
	var sim := Sim.new()
	sim.new_game(seed, 4, 6, true)
	sim.players[0].ai = true
	Sim.log_checksums = true
	while sim.time < mins * 60.0 + 0.5:
		sim.tick(Sim.TICK)
	quit()
