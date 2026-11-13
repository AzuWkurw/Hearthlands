extends SceneTree
## The map editor's Generate and Open: maps of each shape come out with their starts, a map saved and
## opened again is the same, and generating with the usual settings gives the usual map.
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/editor_test.gd -- [out=/dir]
func _pic(sim: Sim, path: String) -> void:
	var img := Image.create(sim.w, sim.h, false, Image.FORMAT_RGB8)
	for y in sim.h:
		for x in sim.w:
			var i := y * sim.w + x
			var c: Color = [Color("2f6fb0"), Color("e3d39a"), Color("6a9e48"), Color("8d8a86")][sim.ter[i]]
			if sim.deco[i] == 1: c = Color("2f5f2a")
			if sim.ore[i] != 0: c = Color("c08a3a")
			img.set_pixel(x, y, c)
	img.resize(256, 256, Image.INTERPOLATE_NEAREST)
	img.save_png(path)

func _init() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	var ed: UiEditor = main.editor_ui
	var ok := true
	var sim: Sim = main.sim
	for shape in WorldGen.SHAPES:
		var p := WorldGen.GEN_DEFAULTS.duplicate()
		p["shape"] = shape
		var r := ed.start("edtest", 4, 160, p)
		var water := 0
		for i in sim.w * sim.h:
			if sim.ter[i] == Sim.WATER: water += 1
		print("%-12s made %s, %d starts, %d%% water" % [shape, r, ed.starts.size(), water * 100 / (sim.w * sim.h)])
		if not r or ed.starts.size() != 4: ok = false
		if out != "": _pic(sim, out + "shape_%s.png" % shape)
	# more water, more mountains
	var wet := WorldGen.GEN_DEFAULTS.duplicate(); wet["water"] = 0.8
	ed.start("edtest", 3, 160, wet)
	var w1 := 0
	for i in sim.w * sim.h:
		if sim.ter[i] == Sim.WATER: w1 += 1
	ed.start("edtest", 3, 160, {})
	var w0 := 0
	for i in sim.w * sim.h:
		if sim.ter[i] == Sim.WATER: w0 += 1
	print("water: usual %d tiles, more water %d" % [w0, w1])
	if w1 <= w0: ok = false; print("FAIL: the Water setting")
	# save, change, open again
	ed.map_name = "_editor_test"
	ed.animals = [["deer", ed.starts[0].x + 4, ed.starts[0].y]]
	ed.save()
	var saved_ter: PackedByteArray = sim.ter.duplicate()
	var saved_ore: PackedByteArray = sim.ore.duplicate()
	ed.start("other", 3, 128, {})
	var err := ed.load_file(UiEditor.MAP_DIR + "/_editor_test.json")
	print("opened again: '%s', %dx%d, same ground %s, same ore %s, starts %d, animals %d" % [err, sim.w, sim.h, sim.ter == saved_ter, sim.ore == saved_ore, ed.starts.size(), ed.animals.size()])
	if err != "" or sim.ter != saved_ter or sim.ore != saved_ore or ed.animals.size() != 1: ok = false; print("FAIL: opening a saved map")
	print("listed: %s" % str(UiEditor.map_files().map(func(f): return f.get_file())))
	DirAccess.remove_absolute(UiEditor.MAP_DIR + "/_editor_test.json")
	if out != "":
		var p2 := WorldGen.GEN_DEFAULTS.duplicate(); p2["shape"] = "lakes"
		ed.start("showcase", 4, 192, p2)
		ed._show_gen = true
		ed._fill()
		main.view.zoom = 5.0
		for i in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "editor_gen.png")
	print("EDITOR TEST: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
