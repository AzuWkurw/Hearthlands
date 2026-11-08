extends SceneTree
## Lists what each tab of the Build panel shows, for a new game and for a loaded older save, and
## names every building that appears in no tab.
## Run: godot --headless --script res://tools/menu_test.gd -- [save=path]
func _list(main, label: String) -> void:
	await process_frame
	var shown := {}
	for cat in ["raw", "food", "industry", "crafts", "folk", "science", "logistics", "mil"]:
		main._set_cat(cat)
		await process_frame
		var names := []
		for c in main.build_grid.get_children():
			if c is Button:
				names.append(c.text.get_slice("\n", 0))
				shown[c.text.get_slice("\n", 0)] = true
		print("%s %-9s %d: %s" % [label, cat, names.size(), ", ".join(names)])
	var missing := []
	for id in GameData.bld:
		var d: Dictionary = GameData.bld[id]
		if id == "hq": continue
		if not shown.has(String(d.name)):
			missing.append("%s (%s)" % [d.name, "needs " + String(d.get("tech", "")) if d.has("tech") else ("feature " + String(d.get("feature", "")) if d.has("feature") else "?")])
	print("%s not in any tab: %s" % [label, ", ".join(missing)])

func _init() -> void:
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 4: await process_frame
	main._start("menu", 3, 5, true)
	main.setup.visible = false
	await process_frame
	await _list(main, "NEW")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("save="):
			var f := FileAccess.open_compressed(a.substr(5), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
			var d = f.get_var()
			print("load: '%s' features %s" % [main.sim.from_save(d), main.sim.feature_ids()])
			main.turn_on_new_features()
			print("after turning on new features: %s" % [main.sim.feature_ids()])
			main._after_world_change()
			await process_frame
			await _list(main, "OLD")
	quit()
