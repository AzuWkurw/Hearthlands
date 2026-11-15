extends SceneTree
## Screenshots for build 57: the gunpowder buildings, a sulfur deposit and mine, the powder mill's info.
##   xvfb-run godot --rendering-driver opengl3 --script res://tools/shot_b57.gd -- out=/dir
func _shot(path: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _spot(sim: Sim, ty: String, near: Vector2i) -> Vector2i:
	for r in range(2, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r: continue
				if sim.can_place(ty, near.x + dx, near.y + dy, 1) == "":
					return Vector2i(near.x + dx, near.y + dy)
	return Vector2i(-1, -1)


func _init() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 3: await process_frame
	main._start("powder", 2, 5, false, 160, false, {"features": Features.default_ids().filter(func(f): return f != "fog" and f != "geology")})
	main.setup.visible = false
	var sim: Sim = main.sim
	var me := sim.human()
	for t in ["gunpowder", "musketry", "drill_manuals", "blasting_powder"]:
		me.techs[t] = true
	for i in 20: sim.tick(Sim.TICK)
	# the sulfur deposit nearest home, and land around it
	var su := -1
	var bd := 1e9
	for i in sim.ore.size():
		if sim.ore[i] == 6:
			var d := Vector2(i % sim.w - me.hq.x, i / sim.w - me.hq.y).length()
			if d < bd: bd = d; su = i
	var c := Vector2i(su % sim.w, su / sim.w)
	for y in range(maxi(0, c.y - 18), mini(sim.h, c.y + 19)):
		for x in range(maxi(0, c.x - 18), mini(sim.w, c.x + 19)):
			if sim.owner[sim.idx(x, y)] == 0: sim.owner[sim.idx(x, y)] = 1
	var placed := []
	for ty in ["sulfur_mine", "lead_mine", "charcoal_burner", "saltpeter_works", "powder_mill", "lead_smelter", "cartridge_works", "pyrotechnist", "gunsmith", "battery"]:
		var sp := c if ty == "sulfur_mine" else _spot(sim, ty, c)
		if ty == "lead_mine" or (ty == "sulfur_mine" and sim.can_place(ty, c.x, c.y, 1) != ""):
			var want_ore := 7 if ty == "lead_mine" else 6
			sp = Vector2i(-1, -1)
			var bd2 := 1e9
			for i in sim.ore.size():
				if sim.ore[i] == want_ore and sim.owner[i] == 1 and sim.can_place(ty, i % sim.w, i / sim.w, 1) == "":
					var d2 := Vector2(i % sim.w - c.x, i / sim.w - c.y).length()
					if d2 < bd2: bd2 = d2; sp = Vector2i(i % sim.w, i / sim.w)
		if sp.x >= 0:
			var b := sim.add_bld(ty, sp.x, sp.y, me, true)
			b.working = true
			placed.append(b)
	sim.give(me, "sulfur", 12.0); sim.give(me, "saltpeter", 20.0); sim.give(me, "charcoal", 14.0); sim.give(me, "gunpowder", 30.0)
	sim.give(me, "ore_lead", 9.0); sim.give(me, "lead", 16.0); sim.give(me, "ammunition", 24.0); sim.give(me, "fireworks", 6.0)
	for i in 20: sim.tick(Sim.TICK)
	main.paused = true
	main.view.center_on(Vector2(c.x + 3, c.y + 2))
	main.view.zoom = 28.0
	main._refresh_all()
	if main.age_ui.panel != null: main.age_ui.panel.visible = false
	await _shot(out + "b57_powder.png")
	for b in placed:
		if b.ty == "cartridge_works":
			main.view.sel_id = b.id
	main._refresh_sel()
	main._refresh_all()
	if main.age_ui.panel != null: main.age_ui.panel.visible = false
	await _shot(out + "b57_mill_info.png")
	quit()
