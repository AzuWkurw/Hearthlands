extends SceneTree
## Spectator mode (build 77): every realm is played by the computer, there is no fog of war, the
## game stays deterministic through a save and load, and it ends when one realm is left standing.
## godot --headless --script res://tools/spectate_test.gd
func _init() -> void:
	GameData.ensure()
	var ok := true
	var feats: Array = Features.default_ids().duplicate()
	if not feats.has("fog"):
		feats.append("fog")
	var a := Sim.new()
	a.new_game("spectate", 3, 6, true, 0, true, {"spectate": true, "features": feats})
	var all_ai := a.players.all(func(p): return p.ai)
	var names := a.players.map(func(p): return p.name)
	print("realms: %d, all played by the computer: %s, names %s" % [a.players.size(), all_ai, names])
	ok = ok and all_ai and a.players.size() == 4 and not names.has("You")
	print("fog on: %s, features %s" % [a.get_feature("fog") != null, a.feature_ids()])
	ok = ok and a.get_feature("fog") == null
	a.set_feature("fog", true)
	print("fog after switching it on: %s" % (a.get_feature("fog") != null))
	ok = ok and a.get_feature("fog") == null
	# the first realm grows like the others
	for i in 3000: a.tick(Sim.TICK)   # 5 minutes
	var b0 := a.realm_blds(a.players[0]).size()
	print("after 5 minutes: first realm %d buildings, others %s" % [b0, a.players.slice(1).map(func(p): return a.realm_blds(p).size())])
	ok = ok and b0 > 5
	print("sandbox goals untouched: goal_i %d" % a.players[0].goal_i)
	ok = ok and a.players[0].goal_i == 0
	# save and load: both go on the same way
	var data = bytes_to_var(var_to_bytes(a.to_save()))   # as through a save file
	var b := Sim.new()
	var err := b.from_save(data)
	print("load: '%s', spectating after load: %s" % [err, b.spectating()])
	ok = ok and err == "" and b.spectating()
	for i in 1200:
		a.tick(Sim.TICK); b.tick(Sim.TICK)
	var same := a.checksum() == b.checksum()
	print("checksum match 2 minutes after load: %s" % same)
	ok = ok and same
	# the first realm falling does not end the game; the last one standing does
	var ended := []
	a.ended.connect(func(w): ended.append(w))
	_fall(a, a.players[0])
	print("first realm gone: over %s" % a.over)
	ok = ok and not a.over
	for p in a.players.slice(1, a.players.size() - 1):
		_fall(a, p)
	print("one realm left: over %s, ended %s, last log '%s'" % [a.over, ended, String(a.logs[-1][1])])
	ok = ok and a.over and ended == [true] and String(a.logs[-1][1]).contains("last realm standing")
	# a mission is never a spectator game
	var m := Sim.new()
	m.new_game("spectate", 1, 5, true, 0, true, {"spectate": true}, {}, {"name": "x", "goals": [{"kind": "pop", "n": 9999}]})
	print("mission spectating: %s" % m.spectating())
	ok = ok and not m.spectating() and not m.players[0].ai
	print("spectate test: %s" % ("ok" if ok else "FAILED"))
	a.dispose(); b.dispose(); m.dispose()
	quit()


## Realm p falls, as when its headquarters is taken.
func _fall(sim: Sim, p: Sim.Player) -> void:
	sim.military.eliminate(p, sim.players[-1])
