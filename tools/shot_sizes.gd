extends SceneTree
## Screenshots of building sizes and site markers:
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_sizes.gd -- out=/dir
var out := "user://"
var main

func shot(name: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name + ".png")

## The first spot from (x, y) going right and then down where ty fits with its entrance south.
func spot_for(sim: Sim, ty: String, x0: int, y0: int, r: int) -> Vector2i:
	for dy in range(0, r):
		for dx in range(0, r):
			for sgn in [1, -1]:
				var x: int = x0 + dx * sgn; var y: int = y0 + dy
				if sim.can_place(ty, x, y, 1, 0) == "": return Vector2i(x, y)
	return Vector2i(-1, -1)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	main.settings.auto_roads = true; main.view.auto_roads = true
	main._start("showcase", 3, 6, true); main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 16 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	main.paused = true
	main.log_ui.set_open(false)
	main.view.center_on(Vector2(me.hq.x + 1.0, me.hq.y + 2.0))
	main.view.zoom = 40.0
	main._refresh_all()
	await shot("1_town")
	# a building group open: the largest building each free spot takes
	main.toolbar._on_cat("food")
	main.view.center_on(Vector2(me.hq.x + 1.0, me.hq.y + 2.0))
	await shot("2_sites")
	main.toolbar.close_popup()
	# placing a small building (guard hut): where it fits
	main._pick_build("hut")
	var s1 := spot_for(sim, "hut", me.hq.x + 3, me.hq.y + 4, 14)
	main.view.ghost = s1; main.view.door = 0
	main.view.center_on(Vector2(s1.x, s1.y))
	await shot("3_small")
	# placing a large one (farm)
	main._pick_build("farm")
	var s2 := spot_for(sim, "farm", me.hq.x - 10, me.hq.y - 8, 26)
	main.view.ghost = s2; main.view.door = 0
	main.view.center_on(Vector2(s2.x, s2.y))
	await shot("4_large")
	# a large one where it does not fit (next to a building)
	var near: Sim.Bld = null
	for b in sim.blds:
		if b.p == 1 and b.ty == "house" and near == null: near = b
	var bad := Vector2i(near.x + 2, near.y)
	for b2 in sim.blds:
		if b2.p != 1: continue
		for dy in range(-3, 4):
			for dx in range(-4, 5):
				if String(sim.can_place("farm", b2.x + dx, b2.y + dy, 1, 0)).begins_with("Too close"):
					bad = Vector2i(b2.x + dx, b2.y + dy)
	main.view.ghost = bad
	main.view.center_on(Vector2(bad.x, bad.y))
	await shot("5_large_bad")
	print("bad spot: ", sim.can_place("farm", bad.x, bad.y, 1, 0))
	print("farm spot ", s2)
	main._cancel_place()
	# a second game in creative mode with everything researched, the land cleared for the demo:
	# military buildings as close together as the rules allow, small and medium in one row, large in another
	main._start("showcase", 1, 1, false, 0, true, {"creative": true, "all_research": true, "start_goods": 1.0, "peace_min": 0, "research": 1.0, "build": 1.0, "endless_ore": false, "endless_raw": false, "tools": true})
	main.setup.visible = false
	sim = main.sim
	me = sim.human()
	for i in sim.deco.size():
		if sim.owner[i] == 1 and sim.deco[i] != 0: sim.deco[i] = 0; sim.changed_tiles.append(i)
	var placed := []
	for rowdef in [[["palisade", "hut", "watch_tower", "guardhouse", "tower"], me.hq.y + 5, me.hq.x - 7], [["keep", "castle", "fortress"], me.hq.y - 4, me.hq.x - 6]]:
		var x: int = rowdef[2]
		var y: int = rowdef[1]
		for ty in rowdef[0]:
			var sp := Vector2i(-1, -1)
			for dx in range(0, 8):
				for dy in [0, 1, -1, 2]:
					if sp.x < 0 and sim.can_place(ty, x + dx, y + dy, 1, 0) == "":
						sp = Vector2i(x + dx, y + dy)
			if sp.x < 0:
				print("no room for ", ty, ": ", sim.can_place(ty, x, y, 1, 0)); continue
			var r: String = sim.place(ty, sp.x, sp.y, me, 0, true)
			placed.append("%s %s at %d,%d %s" % [ty, sim.size_of(ty), sp.x, sp.y, r])
			x = sp.x + int((Sim.PLOTS[sim.size_of(ty)] as Array).map(func(o): return o.x).max()) + 2 + (1 if sim.size_of(ty) == "large" else 0)
	for i in 30: sim.tick(Sim.TICK)
	print("\n".join(placed))
	main.paused = true
	main.view.center_on(Vector2(me.hq.x + 0.5, me.hq.y + 1.0))
	main.view.zoom = 40.0
	main._refresh_all()
	await shot("6_row")
	# placing a farm (large) next to them
	main._pick_build("farm")
	var fs := spot_for(sim, "farm", me.hq.x + 4, me.hq.y - 3, 8)
	main.view.ghost = fs; main.view.door = 0
	print("creative farm spot ", fs)
	await shot("7_farm")
	main._cancel_place()
	main.toolbar._on_cat("raw")
	await shot("8_sites_open")
	quit()
