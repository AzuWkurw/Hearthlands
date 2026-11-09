extends SceneTree
## The smaller touches of build 37: undo, town names, follow camera, minimap filters, map packs.
## xvfb-run -a godot --rendering-driver opengl3 --script res://tools/touches_test.gd
func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.guide = false
	main._start("showcase", 2, 4, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	var ok := true
	for i in 30: sim.tick(Sim.TICK)
	# town names
	print("headquarters' town: ", me.hq.town)
	if me.hq.town == "": ok = false; print("FAIL: the headquarters should have a town name")
	# undo a placement
	var spot := Vector2i(-1, -1)
	for r in range(3, 10):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if spot.x < 0 and sim.can_place("woodcutter", me.hq.x + dx, me.hq.y + dy, 1) == "":
					spot = Vector2i(me.hq.x + dx, me.hq.y + dy)
	sim.logistics.last_laid = PackedInt32Array()
	sim.place("woodcutter", spot.x, spot.y, me)
	main.undo_ui.placed(sim.bld_at(spot.x, spot.y))
	var roads := (main.undo_ui.last.roads as PackedInt32Array).size()
	main.undo_ui.undo()
	print("undo placement: site gone ", sim.bld_at(spot.x, spot.y) == null, ", road tiles taken up ", roads)
	if sim.bld_at(spot.x, spot.y) != null: ok = false; print("FAIL: undo should remove the site")
	# undo a demolish
	var b := sim.add_bld("woodcutter", spot.x, spot.y, me, true, 0)
	var planks0 := float(me.stock.get("planks", 0.0))
	var rec: Dictionary = main.undo_ui.before_demolish(b)
	sim.demolish(b)
	main.undo_ui.demolished(rec)
	var planks1 := float(me.stock.get("planks", 0.0))
	main.undo_ui.undo()
	var b2 := sim.bld_at(spot.x, spot.y)
	print("undo demolish: stands again ", b2 != null and b2.state == "ready", ", planks ", planks0, " -> ", planks1, " -> ", float(me.stock.get("planks", 0.0)))
	if b2 == null or float(me.stock.get("planks", 0.0)) != planks0: ok = false; print("FAIL: undo should bring it back and take back the refund")
	# follow camera
	for i in 200: sim.tick(Sim.TICK)
	var t: Sim.Trip = null
	for tt in sim.trips:
		if tt.path.size() > 3: t = tt
	if t != null:
		main.view.follow = t
		for i in 3: await process_frame
		print("follow: camera on the carrier ", main.view.cam.distance_to(main.view.trip_pos(t)) < 0.5)
	# minimap filters
	for f in ["roads", "land", "good:planks", ""]:
		main.minimap.set_filter(f)
		for i in 2: await process_frame
	# share packs: a map and a mission there and back
	var pack := OS.get_user_data_dir() + "/test.hlpack"
	var err := SharePack.export_pack(pack, ["res://data/map_iron_coast.json"], [{"id": "x", "name": "Test mission", "map": "res://data/map_iron_coast.json", "goals": [{"kind": "pop", "n": 10, "text": "x"}]}])
	var had := SharePack.user_missions().size()
	var msg := SharePack.import_pack(pack)
	var mine := SharePack.user_missions()
	print("pack: export '", err, "', import: ", msg, " missions now ", mine.size())
	if mine.size() != had + 1 or WorldGen.load_map(String(mine[-1].map)).is_empty(): ok = false; print("FAIL: the pack should bring the mission and its map")
	# tidy up what the test made
	DirAccess.remove_absolute(String(mine[-1].map))
	mine.pop_back()
	var f2 := FileAccess.open(SharePack.USER_MISSIONS, FileAccess.WRITE); f2.store_string(JSON.stringify(mine)); f2.close()
	if mine.is_empty(): DirAccess.remove_absolute(SharePack.USER_MISSIONS)
	DirAccess.remove_absolute(pack)
	print("touches test: ", "ok" if ok else "FAILED")
	quit()
