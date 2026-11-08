extends SceneTree
## Finds what differs between a game and the same game saved and loaded, after both run on.
## godot --headless --script res://tools/checksum_diff.gd [-- seed=savetest at=10 more=5]
func _init() -> void:
	GameData.ensure()
	var seed := "savetest"; var at := 10.0; var more := 5.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="): seed = a.substr(5)
		if a.begins_with("at="): at = float(a.substr(3))
		if a.begins_with("more="): more = float(a.substr(5))
	var a := Sim.new()
	a.new_game(seed, 4, 7, true, 128, true)
	while a.time < at * 60.0: a.tick(Sim.TICK)
	var b := Sim.new()
	b.from_save(bytes_to_var(var_to_bytes(a.to_save())))
	var step := 0
	while a.time < (at + more) * 60.0:
		a.tick(Sim.TICK); b.tick(Sim.TICK)
		step += 1
		if step % 100 == 0 and a.checksum() != b.checksum():
			print("first different at %.1f s" % a.time)
			_diff(a.to_save(), b.to_save(), "")
			quit()
			return
	print("no difference")
	quit()


func _diff(x, y, where: String) -> void:
	if var_to_bytes(x) == var_to_bytes(y):
		return
	if x is Dictionary and y is Dictionary:
		for k in x:
			if str(k) == "path_ver": continue
			_diff(x[k], y.get(k), where + "." + str(k))
		for k in y:
			if not x.has(k): print(where, ".", k, " only in loaded")
	elif x is Array and y is Array and x.size() == y.size():
		for i in x.size():
			_diff(x[i], y[i], where + "[%d]" % i)
	else:
		print(where, ": ", str(x).substr(0, 200), "  VS  ", str(y).substr(0, 200))
