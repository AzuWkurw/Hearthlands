extends SceneTree
## The toolbar's feature tools work whatever building group was open last:
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/toolbar_tool_test.gd
func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main._start("showcase", 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	for i in 50: sim.tick(Sim.TICK)
	# the nearest mountain tile in or near your land
	var best := -1; var bd := 1e9
	for i in sim.ter.size():
		if sim.ter[i] == Sim.MOUNT:
			var d := Vector2(i % sim.w - me.hq.x, i / sim.w - me.hq.y).length()
			if d < bd: bd = d; best = i
	var t := Vector2i(best % sim.w, best / sim.w)
	var ok := 0
	for cat in ["raw", "food", "mil", "logistics"]:
		main.toolbar._on_cat(cat)
		main.toolbar.close_popup()
		main.toolbar._on_tool("@geologist")
		main.hint.text = ""
		main._on_tile(t)
		print("group %s: geologist click -> '%s'" % [cat, main.hint.text])
		if main.hint.text != "": ok += 1
		main.toolbar._on_tool("@scout")
		main.hint.text = ""
		main._on_tile(Vector2i(me.hq.x + 8, me.hq.y))
		print("group %s: scout click -> '%s'" % [cat, main.hint.text])
		if main.hint.text != "": ok += 1
		main._cancel_place()
	print("tool clicks answered: %d of 8" % ok)
	quit()
