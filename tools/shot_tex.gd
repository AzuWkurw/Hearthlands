extends SceneTree
## Screenshots for judging the textures: a town grown by the computer for a few minutes (no weather or
## fog, so the ground shows as it is), at four zooms round the headquarters, then a coast and mountains
## up close. The game is kept in user://saves/shot_tex.save and reused (fresh makes a new one):
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --script res://tools/shot_tex.gd -- out=/dir [tag=now] [fresh]

func _snap(main, path: String) -> void:
	for i in 30: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var out := "user://"
	var tag := "now"
	var fresh := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4) + "/"
		if a.begins_with("tag="): tag = a.substr(4)
		if a == "fresh": fresh = true
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.size = Vector2i(1600, 900)
	var main = load("res://main.tscn").instantiate(); root.add_child(main)
	for i in 3: await process_frame
	var sim: Sim = main.sim
	var path := Main.SAVE_DIR + "/shot_tex.save"
	if fresh or not FileAccess.file_exists(path):
		main._start("texshot", 2, 6, true, 128, false, {"features": []})
		var me := sim.human()
		me.ai = true; me.skill = 8; me.pers = "builder"; me.prod = 1.6; me.think = 3.0; me.max_b = 3
		while sim.time < 9 * 60.0:
			sim.tick(Sim.TICK)
		me.ai = false
		var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
		f.store_var(sim.to_save())
		f.close()
	else:
		var g := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		var err: String = sim.from_save(g.get_var())
		g.close()
		if err != "": print("load: ", err)
	main._after_world_change()
	main.setup.visible = false
	main.side_box.visible = false
	main.paused = true
	main.guide_ui.box.visible = false
	var hq: Sim.Bld = sim.human().hq
	for z in [24.0, 40.0, 64.0, 96.0]:
		main.view.zoom = z
		main.view.center_on(Vector2(hq.x + 0.5, hq.y + 2.0))
		await _snap(main, out + "tex_%s_town_z%d.png" % [tag, int(z)])
	# a coast and a mountain side up close
	var coast := Vector2i(-1, -1)
	var mtn := Vector2i(-1, -1)
	for r in range(4, 40):
		for k in 64:
			var a := k * TAU / 64.0
			var x := hq.x + int(cos(a) * r)
			var y := hq.y + int(sin(a) * r)
			if not sim.inb(x, y) or not sim.inb(x + 3, y + 3) or not sim.inb(x - 3, y - 3):
				continue
			var i := sim.idx(x, y)
			if coast.x < 0 and sim.ter[i] == Sim.BEACH and sim.ter[sim.idx(x + 3, y)] == Sim.WATER:
				coast = Vector2i(x, y)
			if mtn.x < 0 and sim.ter[i] == Sim.MOUNT and sim.ter[sim.idx(x + 2, y + 2)] == Sim.MOUNT and sim.ter[sim.idx(x - 2, y + 2)] != Sim.MOUNT:
				mtn = Vector2i(x, y)
	for spot in [["coast", coast], ["mountain", mtn]]:
		var at: Vector2i = spot[1]
		if at.x < 0:
			continue
		main.view.zoom = 64.0
		main.view.center_on(Vector2(at) + Vector2(0.5, 0.5))
		await _snap(main, out + "tex_%s_%s.png" % [tag, spot[0]])
	print("shots done")
	quit()
