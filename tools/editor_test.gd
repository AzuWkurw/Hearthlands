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
	# the tools: a brush stroke undone and redone
	ed.start("tools", 4, 128, {})
	ed.tool = "brush"; ed.brush = 0; ed.size = 5; ed.round_brush = true; ed.mirror = "off"
	var c := Vector2i(sim.w / 2, sim.h / 2)
	var before: PackedByteArray = sim.ter.duplicate()
	ed._paint(c, true); ed._paint(c + Vector2i(3, 0), false); ed._paint_done()
	var after: PackedByteArray = sim.ter.duplicate()
	var changed := 0
	for i in sim.w * sim.h:
		if before[i] != after[i]: changed += 1
	ed.undo()
	var undone := sim.ter == before
	ed.redo()
	var redone := sim.ter == after
	print("stroke changed %d tiles; undo gives the map before: %s; redo the map after: %s" % [changed, undone, redone])
	if changed == 0 or not undone or not redone: ok = false; print("FAIL: undo and redo")
	# a round brush leaves the corners out
	var sq := EditorTools.brush_tiles(10, 10, 9, false).size()
	var rd := EditorTools.brush_tiles(10, 10, 9, true).size()
	print("brush of 9: square %d tiles, round %d" % [sq, rd])
	if sq != 81 or rd >= 81 or rd < 55: ok = false; print("FAIL: the round brush")
	# mirrored painting: four ways puts the same on all four quarters
	ed.mirror = "four ways"; ed.brush = 3; ed.size = 3; ed.round_brush = false
	var q := Vector2i(20, 25)
	ed._paint(q, true); ed._paint_done()
	var mx := sim.w - 1 - q.x
	var my := sim.h - 1 - q.y
	var four := [sim.ter[sim.idx(q.x, q.y)], sim.ter[sim.idx(mx, q.y)], sim.ter[sim.idx(q.x, my)], sim.ter[sim.idx(mx, my)]]
	print("mirrored four ways: %s" % str(four))
	if four != [Sim.MOUNT, Sim.MOUNT, Sim.MOUNT, Sim.MOUNT]: ok = false; print("FAIL: mirrored painting")
	ed.mirror = "off"
	# the fill bucket: a whole lake turns to grass
	var lake := -1
	for i in sim.w * sim.h:
		if sim.ter[i] == Sim.WATER and i % sim.w > 5 and i % sim.w < sim.w - 5 and i / sim.w > 5 and i / sim.w < sim.h - 5:
			var f := EditorTools.flood(sim, i % sim.w, i / sim.w, "ter")
			if f.size() > 4 and f.size() < 3000: lake = i; break
	if lake >= 0:
		var lk := EditorTools.flood(sim, lake % sim.w, lake / sim.w, "ter")
		ed.tool = "fill"; ed.brush = 2
		ed._paint(Vector2i(lake % sim.w, lake / sim.w), true); ed._paint_done()
		var left := 0
		for i in lk:
			if sim.ter[i] == Sim.WATER: left += 1
		print("filled a lake of %d tiles; water left %d" % [lk.size(), left])
		if left != 0: ok = false; print("FAIL: the fill bucket")
		ed.undo()
		if sim.ter[lake] != Sim.WATER: ok = false; print("FAIL: undoing a fill")
	# smoothing removes a speck of water in grass
	var spot := Vector2i(-1, -1)
	for y in range(5, sim.h - 5):
		for x in range(5, sim.w - 5):
			if spot.x < 0 and EditorTools.brush_tiles(x, y, 5, false).all(func(t): return sim.ter[sim.idx(t.x, t.y)] == Sim.GRASS):
				spot = Vector2i(x, y)
	ed.tool = "brush"; ed.brush = 0; ed.size = 1
	ed._paint(spot, true); ed._paint_done()
	ed.tool = "smooth"; ed.size = 3
	ed._paint(spot, true); ed._paint_done()
	print("a speck of water smoothed away: %s" % (sim.ter[sim.idx(spot.x, spot.y)] == Sim.GRASS))
	if sim.ter[sim.idx(spot.x, spot.y)] != Sim.GRASS: ok = false; print("FAIL: smoothing")
	# sulfur and lead painted on a mountain (build 58)
	var mt := -1
	for i in sim.w * sim.h:
		if mt < 0 and sim.ter[i] == Sim.MOUNT and sim.ore[i] == 0: mt = i
	var got := []
	for nm in ["Sulfur", "Lead"]:
		for k in UiEditor.BRUSHES.size():
			if UiEditor.BRUSHES[k][0] == nm: ed.brush = k
		ed.tool = "brush"; ed.size = 1
		ed._paint(Vector2i(mt % sim.w, mt / sim.w), true); ed._paint_done()
		got.append(sim.ore[mt])
	print("ore brushes: sulfur %d, lead %d" % [got[0], got[1]])
	if got != [6, 7]: ok = false; print("FAIL: sulfur and lead brushes")
	# a river with fords
	ed.tool = "river"; ed.ford_k = 1
	var ra := Vector2i(sim.w / 2 - 30, sim.h / 2 - 10)
	var rb := Vector2i(sim.w / 2 + 30, sim.h / 2 + 10)
	ed._paint(ra, true); ed._paint(rb, false); ed._paint_done()
	var rv := EditorTools.river(sim, ra, rb, 9)
	var rwet := 0
	for i: int in rv[0]:
		if sim.ter[i] == Sim.WATER: rwet += 1
	var fords := 0
	for i: int in rv[1]:
		if sim.ter[i] == Sim.BEACH: fords += 1
	print("river: %d water tiles, %d ford tiles" % [rwet, fords])
	if rwet < 60 or fords < 4: ok = false; print("FAIL: the river")
	# copy, turn, paste
	ed.tool = "copy"
	ed._paint(Vector2i(10, 12), true); ed._paint(Vector2i(17, 14), false); ed._paint_done()
	var cw := int(ed.clip.w)
	var ch := int(ed.clip.h)
	var corner: int = sim.ter[sim.idx(10, 12)]
	ed.clip = EditorTools.turn(ed.clip)
	ed.tool = "paste"
	var at := Vector2i(sim.w / 2, 30)
	ed._paint(at, true); ed._paint_done()
	# turned right: the old top-left corner is now the top-right one
	print("copied %dx%d, turned to %dx%d; corner carried: %s" % [cw, ch, int(ed.clip.w), int(ed.clip.h), sim.ter[sim.idx(at.x + ch - 1, at.y)] == corner])
	if cw != 8 or ch != 3 or int(ed.clip.w) != 3 or sim.ter[sim.idx(at.x + ch - 1, at.y)] != corner: ok = false; print("FAIL: copy, turn and paste")
	# climate, places and the starts' setup are saved with the map
	ed.tool = "fill"; ed.brush = 22   # taiga over the first start's land
	ed._paint(ed.starts[0], true); ed._paint_done()
	ed.tool = "brush"; ed.brush = 25; ed._paint(ed.starts[0] + Vector2i(8, 0), true); ed._paint_done()
	ed.brush = 26; ed._paint(ed.starts[1] + Vector2i(0, 9), true); ed._paint_done()
	ed._set_setup(1, "pers", "warlord"); ed._set_setup(1, "skill", 8); ed._set_setup(0, "goods", 2.0); ed._set_setup(0, "soldiers", 5)
	ed.map_name = "_editor_test2"
	var places_n := sim.places.size()
	var taiga := ed.biome.count(2)
	ed.save()
	var mp := WorldGen.load_map(UiEditor.MAP_DIR + "/_editor_test2.json")
	print("saved: %d places (placed %d), taiga tiles %d (painted %d), setup %s" % [(mp.places as Array).size(), places_n, (mp.get("biome", PackedByteArray()) as PackedByteArray).count(2), taiga, str(mp.setup)])
	if (mp.places as Array).size() != places_n or places_n < 1 or (mp.get("biome", PackedByteArray()) as PackedByteArray).count(2) != taiga or taiga == 0: ok = false; print("FAIL: places and climate saved with the map")
	# a game on that map: the setup applied, the taiga where it was painted
	var g2 := Sim.new()
	g2.new_game("x", 2, 4, false, 0, false, {}, mp)
	var me := g2.human()
	var foe := g2.players[1]
	var sea = g2.get_feature("seasons")
	var bk := -1
	if sea != null:
		bk = sea.biome[g2.idx(me.hq.x, me.hq.y)]
	print("in the game: rival manner %s, skill %d; your soldiers in reserve %d; your climate %d (taiga is 1); places %d" % [foe.pers, foe.skill, me.reserve, bk, g2.places.size()])
	if foe.pers != "warlord" or foe.skill != 8 or (sea != null and bk != 1) or g2.places.size() != places_n: ok = false; print("FAIL: the map's setup, climate and places in a game")
	# a mission written in the editor
	ed.mission = {"id": "", "name": "_ed test mission", "story": "x", "foes": 1, "strength": 3, "minutes": 30, "goals": [{"kind": "pop", "n": 40}]}
	ed.mission.goals[0]["text"] = UiEditor.goal_text(ed.mission.goals[0])
	var merr := ed.save_mission()
	var found := SharePack.user_missions().filter(func(m): return String(m.get("name", "")) == "_ed test mission")
	print("mission saved: '%s', in your missions: %d, map %s, goal '%s'" % [merr, found.size(), found[0].map if found.size() > 0 else "-", ed.mission.goals[0].text])
	if merr != "" or found.size() != 1: ok = false; print("FAIL: saving a mission")
	var keep := SharePack.user_missions().filter(func(m): return String(m.get("name", "")) != "_ed test mission")
	var mf := FileAccess.open(SharePack.USER_MISSIONS, FileAccess.WRITE); mf.store_string(JSON.stringify(keep)); mf.close()
	DirAccess.remove_absolute(UiEditor.MAP_DIR + "/_editor_test2.json")
	# fairness: a count for every start
	var fair := EditorTools.fairness(sim, ed.starts)
	print("fairness, start 1: %s" % str(fair[0]))
	if fair.size() != ed.starts.size() or int(fair[0].land) == 0: ok = false; print("FAIL: the fairness count")
	if out != "":
		for t in UiEditor.TABS:
			ed.tab = t
			ed._fill()
			main.view.zoom = 7.0
			ed.show_climate = t == "Paint"
			ed._sync_view()
			main.view.center_on(Vector2(ed.starts[0]))
			for i in 8: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out + "editor_tab_%s.png" % t.to_lower())
		ed.show_climate = false
		ed.tab = "Paint"
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
