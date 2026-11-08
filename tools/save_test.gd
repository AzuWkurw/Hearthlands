extends SceneTree
## Save/load round trip: play, save, load into a fresh Sim, then check both continue identically.
func _sig(sim: Sim) -> String:
	var parts := ["t=%.1f" % sim.time, "blds=%d" % sim.blds.size(), "trips=%d" % sim.trips.size(), "att=%d" % sim.attacks.size()]
	for p in sim.players:
		parts.append("%s:%d/%d/%d r%d rp%.1f tech%d wood%d bread%d" % [p.name, p.peasant, p.artisan, p.noble, p.reserve, p.rp, p.techs.size(), int(p.stock.wood), int(p.stock.bread)])
	return " ".join(parts)

func _init() -> void:
	var a := Sim.new()
	a.new_game("savetest", 4, 7, true, 128, true)
	for i in 6000: a.tick(Sim.TICK)   # 10 minutes
	var path := "user://saves/test.save"
	DirAccess.make_dir_recursive_absolute("user://saves")
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_var(a.to_save())
	f.close()
	print("save size bytes: ", FileAccess.get_file_as_bytes(path).size())
	var g := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var data = g.get_var()
	g.close()
	var b := Sim.new()
	print("load result: '", b.from_save(data), "'")
	print("A: ", _sig(a)); print("B: ", _sig(b))
	print("match after load: ", _sig(a) == _sig(b))
	print("checksum match after load: ", a.checksum() == b.checksum())
	for i in 3000:
		a.tick(Sim.TICK); b.tick(Sim.TICK)
	print("match after 5 more minutes: ", _sig(a) == _sig(b))
	print("checksum match after 5 more minutes: ", a.checksum() == b.checksum())
	print("A: ", _sig(a))
	print("map size ", a.w, " research: ", a.players.map(func(p): return "%s %s age=%s techs=%d -> %s" % [p.name, "", GameData.age_name(p.age), p.techs.size(), p.research]))
	quit()
