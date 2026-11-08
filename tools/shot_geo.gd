extends SceneTree
## Screenshots of geologists at work, their markers, surveyed ore shown while placing a mine, and wildlife.
## xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_geo.gd -- out=/dir
var out := "user://"
func _snap(name: String) -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name + ".png")
	print("saved ", name)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 4: await process_frame
	main._start("geotest", 3, 5, true)
	main.setup.visible = false
	main.log_ui.set_open(false)
	var sim: Sim = main.sim
	var me := sim.human()
	var geo = sim.get_feature("geology")
	var wl = sim.get_feature("wildlife")
	me.ai = true; me.skill = 7; me.pers = "builder"; me.prod = 1.0; me.think = 3.0; me.max_b = 2; me.grace = 1e9; me.attack_t = 1e9
	while sim.time < 4 * 60.0: sim.tick(Sim.TICK)
	me.ai = false
	# a mountain with ore in or near our land that a geologist can still survey
	var target := -1
	for r in range(2, 24):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x: int = me.hq.x + dx
				var y: int = me.hq.y + dy
				if target < 0 and sim.inb(x, y) and sim.ter[sim.idx(x, y)] == Sim.MOUNT and sim.ore[sim.idx(x, y)] != 0 and not geo.known_at(1, sim.idx(x, y)):
					if geo.send(me, x, y) == "":
						target = sim.idx(x, y)
	print("target ", target)
	var tx := target % sim.w
	var ty := target / sim.w
	while sim.time < 4 * 60.0 + 70.0: sim.tick(Sim.TICK)
	main.view.center_on(Vector2(tx + 0.5, ty + 0.5))
	main.view.zoom = 34.0
	main._refresh_all()
	await _snap("geo_survey")
	main.view.place_type = "iron_mine" if sim.ore[target] == 2 else ("coal_mine" if sim.ore[target] == 1 else ("gold_mine" if sim.ore[target] == 3 else "copper_mine"))
	await _snap("geo_place_mine")
	main.view.place_type = ""
	# the busiest patch of wildlife in sight
	var best := Vector2.ZERO
	var bn := -1
	for a in wl.animals:
		var p: Vector2 = wl.pos(a)
		if not sim.get_feature("fog").visible_at(sim.idx(int(p.x), int(p.y))): continue
		var n := 0
		for b in wl.animals:
			if wl.pos(b).distance_to(p) < 5.0: n += 1
		if n > bn: bn = n; best = p
	main.view.center_on(best)
	main.view.zoom = 40.0
	await _snap("wildlife")
	quit()
