extends SceneTree
## Save and load from a real save: plays it a minute, saves and loads into a second game, then plays
## both on and compares checksums every 30 seconds. godot --headless --script res://tools/save_test2.gd -- save=user_save mins=4
func _init() -> void:
	var save := "user_save"
	var mins := 4
	for a in OS.get_cmdline_user_args():
		if a.begins_with("save="): save = a.substr(5)
		if a.begins_with("mins="): mins = int(a.substr(5))
	GameData.ensure()
	var f := FileAccess.open_compressed("user://saves/%s.save" % save, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var d = f.get_var()
	f.close()
	var a := Sim.new()
	a.from_save(d)
	print("loaded: '%s'" % "ok")
	for i in int(60.0 / Sim.TICK): a.tick(Sim.TICK)
	var b := Sim.new()
	b.from_save(bytes_to_var(var_to_bytes(a.to_save())))
	var same := true
	for s in mins * 2:
		for i in int(30.0 / Sim.TICK):
			a.tick(Sim.TICK); b.tick(Sim.TICK)
		var ok := a.checksum() == b.checksum()
		print("  %d s: %s" % [(s + 1) * 30, "same" if ok else "DIFFERENT"])
		if not ok:
			same = false
			var da := a.to_save(); var db := b.to_save()
			for k in da:
				if var_to_str(da[k]) != var_to_str(db.get(k)):
					print("    differs: %s" % k)
			break
	print("SAVE TEST 2: %s" % ("PASS" if same else "FAIL"))
	quit()
