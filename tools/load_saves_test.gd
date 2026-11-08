extends SceneTree
## Loads every save in the saves folder (user://saves) and plays each on for a minute: old saves must
## still load. godot --headless --script res://tools/load_saves_test.gd
func _init() -> void:
	GameData.ensure()
	var dir := DirAccess.open("user://saves")
	var ok := 0
	var bad := 0
	if dir != null:
		for fn in dir.get_files():
			if not fn.ends_with(".save"):
				continue
			var f := FileAccess.open_compressed("user://saves/" + fn, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
			if f == null:
				continue
			var d = f.get_var()
			f.close()
			if not (d is Dictionary):
				print("%s: not a save" % fn)
				continue
			var sim := Sim.new()
			var err := sim.from_save(d)
			var ver := String(d.get("meta", {}).get("version", "older build"))
			if err != "":
				print("%s (%s): load failed: %s" % [fn, ver, err]); bad += 1
				continue
			for i in 600: sim.tick(Sim.TICK)
			var sm := sim.logistics.stock_matches()
			print("%s (%s): loaded, %d buildings after a minute, stock = stores: %s" % [fn, ver, sim.blds.size(), "yes" if sm == "" else sm])
			if sm == "": ok += 1
			else: bad += 1
			sim.dispose()
	print("saves test: %d ok, %d bad" % [ok, bad])
	quit()
